-- Settlements and deposits are transfers, not one-sided events.
--
-- `admin_record_settlement` wrote a single row against the party. That is what
-- a balance-based system would do, but it breaks the ledger's invariant: money
-- only ever moves *between* accounts, and a driver handing 1,626 in does not
-- make 1,626 vanish — the platform is now holding it. A single-sided
-- settlement threw `finance_integrity_check` off by exactly the settled
-- amount, and it went unnoticed only because nothing had settled yet.
--
-- Every money movement below now names both sides. The platform is the
-- counterparty to every settlement and every deposit.

-- Stores are paid on a weekly run. 4 = Thursday, matching `extract(dow)`.
alter table public.vendors
  add column if not exists payout_day_of_week int not null default 4
    check (payout_day_of_week between 0 and 6);

-- When this store's money is next due on the normal run.
create or replace function public.vendor_next_payout_at(p_vendor_id uuid)
returns timestamptz language plpgsql stable security definer
set search_path = public
as $$
declare v_day int; v_today date; v_delta int;
begin
  select coalesce(payout_day_of_week, 4) into v_day
  from public.vendors where id = p_vendor_id;
  if v_day is null then v_day := 4; end if;

  v_today := (now() at time zone public.platform_timezone())::date;
  v_delta := (v_day - extract(dow from v_today)::int + 7) % 7;
  -- Landing on payout day means the run is today, not next week.
  return (v_today + v_delta)::timestamptz;
end;
$$;

grant execute on function public.vendor_next_payout_at(uuid) to authenticated;

-- What an early payout costs, as a percentage of the amount advanced.
create or replace function public.early_settlement_fee_percent()
returns numeric language sql stable security definer
set search_path = public, private
as $$
  select coalesce((select value::numeric from private.app_config
     where key = 'early_settlement_fee_percent'), 1.5);
$$;

-- A floor, so advancing 40 EGP is not free to the platform.
create or replace function public.early_settlement_fee_min()
returns numeric language sql stable security definer
set search_path = public, private
as $$
  select coalesce((select value::numeric from private.app_config
     where key = 'early_settlement_fee_min'), 10);
$$;

grant execute on function public.early_settlement_fee_percent() to authenticated;
grant execute on function public.early_settlement_fee_min() to authenticated;

create or replace function public.admin_record_settlement(
  p_owner_type public.ledger_owner_type, p_owner_id uuid, p_amount numeric,
  p_method text default 'cash', p_reference text default null,
  p_notes text default null, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_txn uuid; v_settlement uuid;
  v_type public.ledger_entry_type; v_balance numeric;
  v_party_direction public.ledger_direction; v_key text;
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if p_owner_type = 'platform' then raise exception 'PLATFORM_NOT_SETTLEABLE'; end if;

  v_type := case p_owner_type
    when 'driver' then 'driver_settlement'::public.ledger_entry_type
    else 'vendor_settlement'::public.ledger_entry_type end;

  -- A driver handing cash in owes less afterwards; a store being paid is owed
  -- less afterwards. Opposite directions on the party, and the platform always
  -- takes the mirror of whichever it is.
  v_party_direction := case when p_owner_type = 'driver'
    then 'credit'::public.ledger_direction
    else 'debit'::public.ledger_direction end;

  v_key := coalesce(p_idempotency_key, 'settlement:' || gen_random_uuid()::text);

  v_txn := public.finance_post(
    p_owner_type, p_owner_id, v_type, p_amount, v_party_direction,
    null, p_reference, coalesce(p_notes, 'Settlement'),
    jsonb_build_object('method', p_method), v_key);

  if v_txn is null then raise exception 'SETTLEMENT_NOT_RECORDED'; end if;

  -- The other side. Without it the money would simply disappear from the
  -- books: the platform is holding what the driver handed over, and has paid
  -- out what the store received.
  perform public.finance_post(
    'platform', null, v_type, p_amount,
    case when v_party_direction = 'credit'
      then 'debit'::public.ledger_direction
      else 'credit'::public.ledger_direction end,
    null, p_reference, coalesce(p_notes, 'Settlement counterparty'),
    jsonb_build_object('method', p_method, 'counterparty_of', v_txn),
    v_key || ':platform');

  insert into public.settlements (
    owner_type, owner_id, amount, method, status, reference, notes,
    transaction_id, created_by, approved_by, completed_at
  ) values (
    p_owner_type, p_owner_id, round(p_amount, 2), p_method, 'completed',
    p_reference, p_notes, v_txn, auth.uid(), auth.uid(), now()
  ) returning id into v_settlement;

  select balance into v_balance from public.finance_wallets
  where owner_type = p_owner_type and owner_id = p_owner_id;

  return jsonb_build_object('settlement_id', v_settlement, 'transaction_id', v_txn,
    'balance', v_balance, 'cash_due', public.wallet_cash_due(v_balance),
    'payable', public.wallet_payable(v_balance));
end;
$$;

create or replace function public.admin_review_deposit(
  p_request_id uuid, p_approve boolean, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_request public.deposit_requests%rowtype; v_txn uuid;
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;

  select * into v_request from public.deposit_requests where id = p_request_id for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  -- Reviewing twice must not credit twice.
  if v_request.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  if p_approve then
    v_txn := public.finance_post('driver', v_request.driver_id, 'driver_deposit',
      v_request.amount, 'credit', null, v_request.reference,
      coalesce(p_notes, 'Deposit approved'),
      jsonb_build_object('payment_method', v_request.payment_method,
                         'request_id', p_request_id),
      'deposit:' || p_request_id::text);

    -- The platform received the transfer, so it holds the money.
    perform public.finance_post('platform', null, 'driver_deposit',
      v_request.amount, 'debit', null, v_request.reference,
      'Deposit counterparty', jsonb_build_object('request_id', p_request_id),
      'deposit:' || p_request_id::text || ':platform');
  end if;

  update public.deposit_requests set
    status = case when p_approve then 'approved'::public.deposit_status
                  else 'rejected'::public.deposit_status end,
    transaction_id = v_txn, reviewed_by = auth.uid(), reviewed_at = now(),
    notes = coalesce(p_notes, notes)
  where id = p_request_id;

  return jsonb_build_object('request_id', p_request_id, 'approved', p_approve,
    'transaction_id', v_txn);
end;
$$;

-- What a store would receive and pay if it cashed out right now.
--
-- Read-only, so the app can show the offer before the store commits to it --
-- nobody should have to press the button to find out the fee.
create or replace function public.vendor_early_settlement_quote(p_vendor_id uuid)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare
  v_payable numeric;
  v_percent numeric := public.early_settlement_fee_percent();
  v_min numeric := public.early_settlement_fee_min();
  v_fee numeric;
begin
  if not (public.is_vendor_owner(p_vendor_id) or public.is_admin()) then
    raise exception 'FORBIDDEN';
  end if;

  select public.wallet_payable(coalesce(balance, 0)) into v_payable
  from public.finance_wallets
  where owner_type = 'vendor' and owner_id = p_vendor_id;
  v_payable := coalesce(v_payable, 0);

  v_fee := case when v_payable <= 0 then 0
    else greatest(round(v_payable * v_percent / 100.0, 2), v_min) end;
  -- Never advance less than nothing: on a tiny balance the floor could exceed
  -- the payable, and the offer is simply not available.
  if v_fee >= v_payable then v_fee := 0; end if;

  return jsonb_build_object(
    'payable', v_payable, 'fee_percent', v_percent, 'fee_min', v_min,
    'fee', v_fee, 'net_payout', round(v_payable - v_fee, 2),
    'available', v_payable > 0 and v_fee > 0,
    'next_scheduled_payout', public.vendor_next_payout_at(p_vendor_id));
end;
$$;

revoke all on function public.vendor_early_settlement_quote(uuid) from public, anon;
grant execute on function public.vendor_early_settlement_quote(uuid) to authenticated;

-- The store cashes out now, at the quoted fee.
--
-- The store initiates this itself -- that is the product -- but it still
-- cannot name the amount: the payable comes from the ledger and the fee from
-- config, so there is nothing here for a caller to inflate.
create or replace function public.vendor_request_early_settlement(
  p_vendor_id uuid, p_method text default 'bank_transfer',
  p_reference text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_quote jsonb; v_payable numeric; v_fee numeric; v_net numeric;
  v_key text; v_txn uuid; v_settlement uuid;
begin
  if not (public.is_vendor_owner(p_vendor_id) or public.is_admin()) then
    raise exception 'FORBIDDEN';
  end if;

  -- Locks the wallet so two taps cannot both cash out the same balance.
  perform 1 from public.finance_wallets
  where owner_type = 'vendor' and owner_id = p_vendor_id for update;

  v_quote := public.vendor_early_settlement_quote(p_vendor_id);
  v_payable := (v_quote ->> 'payable')::numeric;
  v_fee := (v_quote ->> 'fee')::numeric;
  v_net := (v_quote ->> 'net_payout')::numeric;

  if not (v_quote ->> 'available')::boolean then
    raise exception 'NOTHING_TO_SETTLE';
  end if;

  -- One key per store per day: a double tap inside the same day reuses it and
  -- the second call returns the first result instead of cashing out twice.
  v_key := 'early:' || p_vendor_id::text || ':'
        || (now() at time zone public.platform_timezone())::date::text;

  -- The store's whole payable leaves its account, split between what it
  -- receives and what it pays for the speed.
  v_txn := public.finance_post(
    'vendor', p_vendor_id, 'vendor_settlement', v_net, 'debit',
    null, p_reference, 'Early payout',
    jsonb_build_object('method', p_method, 'early', true), v_key);

  if v_txn is null then raise exception 'EARLY_SETTLEMENT_NOT_RECORDED'; end if;

  perform public.finance_post(
    'vendor', p_vendor_id, 'early_settlement_fee', v_fee, 'debit',
    null, p_reference, 'Early payout fee',
    jsonb_build_object('fee_percent', (v_quote ->> 'fee_percent')::numeric),
    v_key || ':fee');

  -- Platform side: it paid the net out, and kept the fee.
  perform public.finance_post(
    'platform', null, 'vendor_settlement', v_net, 'credit',
    null, p_reference, 'Early payout counterparty',
    jsonb_build_object('vendor_id', p_vendor_id), v_key || ':platform');

  perform public.finance_post(
    'platform', null, 'early_settlement_fee', v_fee, 'credit',
    null, p_reference, 'Early payout fee',
    jsonb_build_object('vendor_id', p_vendor_id), v_key || ':platform_fee');

  insert into public.settlements (
    owner_type, owner_id, amount, method, status, reference, notes,
    transaction_id, created_by, approved_by, completed_at
  ) values (
    'vendor', p_vendor_id, v_net, p_method, 'completed', p_reference,
    'Early payout (fee ' || v_fee::text || ')', v_txn, auth.uid(), auth.uid(), now()
  ) returning id into v_settlement;

  return jsonb_build_object('settlement_id', v_settlement,
    'payable', v_payable, 'fee', v_fee, 'net_payout', v_net);
end;
$$;

revoke all on function public.vendor_request_early_settlement(uuid, text, text)
  from public, anon;
grant execute on function public.vendor_request_early_settlement(uuid, text, text)
  to authenticated;
