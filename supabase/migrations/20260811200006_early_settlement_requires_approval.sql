-- Early Payout stops being instant/self-approved and joins the same
-- request→approve queue as the free settlement path. The vendor still sees
-- and locks in the same fee quote before submitting; what changes is that
-- submitting now opens a `pending` row instead of posting the ledger on the
-- spot. The same option is added for drivers, who never had a fee-based
-- early cash-out at all until now.
--
-- `settlements.fee` is new: 0 for every existing/free row, the locked-in fee
-- amount for an early one. Whether a row is "early" is just `fee > 0` — no
-- separate kind column needed.

alter table public.settlements
  add column if not exists fee numeric not null default 0 check (fee >= 0);

-- Was: quote, then four `finance_post` calls and an immediately-`completed`
-- row, self-approved (`approved_by = auth.uid()`, i.e. the vendor). Now:
-- quote, one guard against a second open request, one `pending` row. The
-- fee/net math itself (`vendor_early_settlement_quote`) is untouched.
create or replace function public.vendor_request_early_settlement(
  p_vendor_id uuid, p_method text default 'bank_transfer',
  p_reference text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_quote jsonb; v_payable numeric; v_fee numeric; v_net numeric;
  v_settlement uuid;
begin
  if not (public.is_vendor_owner(p_vendor_id) or public.is_admin()) then
    raise exception 'FORBIDDEN';
  end if;

  perform 1 from public.finance_wallets
  where owner_type = 'vendor' and owner_id = p_vendor_id for update;

  -- One open request per wallet, whichever path opened it — two pending
  -- rows could both claim the same payable.
  if exists (
    select 1 from public.settlements
    where owner_type = 'vendor' and owner_id = p_vendor_id and status = 'pending'
  ) then
    raise exception 'REQUEST_ALREADY_PENDING';
  end if;

  v_quote := public.vendor_early_settlement_quote(p_vendor_id);
  v_payable := (v_quote ->> 'payable')::numeric;
  v_fee := (v_quote ->> 'fee')::numeric;
  v_net := (v_quote ->> 'net_payout')::numeric;

  if not (v_quote ->> 'available')::boolean then
    raise exception 'NOTHING_TO_SETTLE';
  end if;

  insert into public.settlements (
    owner_type, owner_id, amount, fee, method, status, reference, notes, created_by
  ) values (
    'vendor', p_vendor_id, v_net, v_fee, p_method, 'pending', p_reference,
    'Early payout (fee ' || v_fee::text || ')', auth.uid()
  ) returning id into v_settlement;

  return jsonb_build_object('settlement_id', v_settlement,
    'payable', v_payable, 'fee', v_fee, 'net_payout', v_net);
end;
$$;

revoke all on function public.vendor_request_early_settlement(uuid, text, text)
  from public, anon;
grant execute on function public.vendor_request_early_settlement(uuid, text, text)
  to authenticated;

-- Driver mirror of `vendor_early_settlement_quote` — same fee/min/percent
-- config, self-scoped like every other driver RPC. There is no scheduled
-- driver payout run to reference, so `next_scheduled_payout` is always null.
create or replace function public.driver_early_settlement_quote()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare
  v_payable numeric;
  v_percent numeric := public.early_settlement_fee_percent();
  v_min numeric := public.early_settlement_fee_min();
  v_fee numeric;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;

  select public.wallet_payable(coalesce(balance, 0)) into v_payable
  from public.finance_wallets
  where owner_type = 'driver' and owner_id = auth.uid();
  v_payable := coalesce(v_payable, 0);

  v_fee := case when v_payable <= 0 then 0
    else greatest(round(v_payable * v_percent / 100.0, 2), v_min) end;
  if v_fee >= v_payable then v_fee := 0; end if;

  return jsonb_build_object(
    'payable', v_payable, 'fee_percent', v_percent, 'fee_min', v_min,
    'fee', v_fee, 'net_payout', round(v_payable - v_fee, 2),
    'available', v_payable > 0 and v_fee > 0,
    'next_scheduled_payout', null);
end;
$$;

revoke all on function public.driver_early_settlement_quote() from public, anon;
grant execute on function public.driver_early_settlement_quote() to authenticated;

create or replace function public.driver_request_early_settlement(
  p_method text default 'bank_transfer', p_reference text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_quote jsonb; v_payable numeric; v_fee numeric; v_net numeric;
  v_settlement uuid;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if not exists (select 1 from public.drivers where id = auth.uid()) then
    raise exception 'NOT_A_DRIVER';
  end if;

  perform 1 from public.finance_wallets
  where owner_type = 'driver' and owner_id = auth.uid() for update;

  if exists (
    select 1 from public.settlements
    where owner_type = 'driver' and owner_id = auth.uid() and status = 'pending'
  ) then
    raise exception 'REQUEST_ALREADY_PENDING';
  end if;

  v_quote := public.driver_early_settlement_quote();
  v_payable := (v_quote ->> 'payable')::numeric;
  v_fee := (v_quote ->> 'fee')::numeric;
  v_net := (v_quote ->> 'net_payout')::numeric;

  if not (v_quote ->> 'available')::boolean then
    raise exception 'NOTHING_TO_SETTLE';
  end if;

  insert into public.settlements (
    owner_type, owner_id, amount, fee, method, status, reference, notes, created_by
  ) values (
    'driver', auth.uid(), v_net, v_fee, p_method, 'pending', p_reference,
    'Early payout (fee ' || v_fee::text || ')', auth.uid()
  ) returning id into v_settlement;

  return jsonb_build_object('settlement_id', v_settlement,
    'payable', v_payable, 'fee', v_fee, 'net_payout', v_net);
end;
$$;

revoke all on function public.driver_request_early_settlement(text, text)
  from public, anon;
grant execute on function public.driver_request_early_settlement(text, text)
  to authenticated;

-- Approving now also settles the fee, when there is one — the same second
-- `finance_post` pair `vendor_request_early_settlement` used to post inline
-- before it became a request. A free request (`fee = 0`) skips this
-- unchanged from before.
create or replace function public.admin_review_settlement_request(
  p_settlement_id uuid, p_approve boolean, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_row public.settlements%rowtype;
  v_txn uuid;
  v_type public.ledger_entry_type;
  v_party_direction public.ledger_direction;
  v_key text;
  v_balance numeric;
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;

  select * into v_row from public.settlements where id = p_settlement_id for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  -- Reviewing twice must not post the ledger twice.
  if v_row.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  if p_approve then
    v_type := case v_row.owner_type
      when 'driver' then 'driver_settlement'::public.ledger_entry_type
      else 'vendor_settlement'::public.ledger_entry_type end;

    v_party_direction := 'debit'::public.ledger_direction;

    v_key := 'settlement_request:' || p_settlement_id::text;

    v_txn := public.finance_post(
      v_row.owner_type, v_row.owner_id, v_type, v_row.amount, v_party_direction,
      null, v_row.reference, coalesce(p_notes, v_row.notes, 'Settlement'),
      jsonb_build_object('method', v_row.method, 'settlement_id', p_settlement_id),
      v_key);

    if v_txn is null then raise exception 'SETTLEMENT_NOT_RECORDED'; end if;

    perform public.finance_post(
      'platform', null, v_type, v_row.amount, 'credit'::public.ledger_direction,
      null, v_row.reference, 'Settlement counterparty',
      jsonb_build_object('method', v_row.method, 'counterparty_of', v_txn),
      v_key || ':platform');

    if v_row.fee > 0 then
      perform public.finance_post(
        v_row.owner_type, v_row.owner_id, 'early_settlement_fee', v_row.fee,
        'debit', null, v_row.reference, 'Early payout fee',
        jsonb_build_object('settlement_id', p_settlement_id), v_key || ':fee');

      perform public.finance_post(
        'platform', null, 'early_settlement_fee', v_row.fee,
        'credit', null, v_row.reference, 'Early payout fee counterparty',
        jsonb_build_object('settlement_id', p_settlement_id),
        v_key || ':platform_fee');
    end if;

    update public.settlements set
      status = 'completed', completed_at = now(), approved_by = auth.uid(),
      transaction_id = v_txn, notes = coalesce(p_notes, notes)
    where id = p_settlement_id;

    -- 'payout' — this RPC's rows are always money paid out, never cash
    -- handed in, regardless of owner_type.
    perform public.notify_settlement(
      v_row.owner_type, v_row.owner_id, v_row.amount, 'payout');
  else
    update public.settlements set
      status = 'cancelled', approved_by = auth.uid(), notes = coalesce(p_notes, notes)
    where id = p_settlement_id;

    perform public.notify_settlement(
      v_row.owner_type, v_row.owner_id, v_row.amount, 'rejected');
  end if;

  select balance into v_balance from public.finance_wallets
  where owner_type = v_row.owner_type and owner_id = v_row.owner_id;

  return jsonb_build_object(
    'settlement_id', p_settlement_id, 'approved', p_approve,
    'transaction_id', v_txn, 'balance', v_balance,
    'cash_due', public.wallet_cash_due(v_balance),
    'payable', public.wallet_payable(v_balance));
end;
$$;

revoke all on function public.admin_review_settlement_request(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_review_settlement_request(uuid, boolean, text)
  to authenticated;
