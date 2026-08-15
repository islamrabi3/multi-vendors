-- Tell people when their money moves.
--
-- A settlement is the one financial event the other party cannot see coming:
-- a driver hands cash over and wants confirmation it landed, a store wants to
-- know it has been paid. Silence here generates support tickets.
--
-- Written into `public.notifications`, which is already the in-app inbox and
-- already on the realtime publication, so it appears without a push round
-- trip.

-- Undo the tracked-stock demo left behind while proving the stock guard, so
-- the catalogue is exactly as the vendor left it.
update public.products
set track_stock = false, stock_quantity = 0, low_stock_threshold = 0
where track_stock and not exists (
  select 1 from public.stock_movements m where m.product_id = products.id);

create or replace function public.notify_settlement(
  p_owner_type public.ledger_owner_type, p_owner_id uuid,
  p_amount numeric, p_kind text default 'settlement')
returns void language plpgsql security definer set search_path = public
as $$
declare v_user uuid; v_title text; v_body text; v_route text;
begin
  -- A driver's wallet is keyed by their own profile; a store's by the store,
  -- so the message has to reach its owner rather than the store row.
  if p_owner_type = 'driver' then
    v_user := p_owner_id;
    v_route := '/driver-app/wallet';
    v_title := 'Settlement recorded';
    v_body := 'We have recorded ' || to_char(p_amount, 'FM999999990.00')
           || ' EGP handed in. Your balance is up to date.';
  elsif p_owner_type = 'vendor' then
    select owner_id into v_user from public.vendors where id = p_owner_id;
    v_route := '/vendor-app/dashboard';
    if p_kind = 'early' then
      v_title := 'Early payout sent';
      v_body := to_char(p_amount, 'FM999999990.00')
             || ' EGP is on its way to you today.';
    else
      v_title := 'You have been paid';
      v_body := to_char(p_amount, 'FM999999990.00') || ' EGP has been settled.';
    end if;
  else
    return;
  end if;

  if v_user is null then return; end if;

  insert into public.notifications (user_id, title, body, type, route)
  values (v_user, v_title, v_body, 'settlement', v_route);
end;
$$;

revoke all on function public.notify_settlement(
  public.ledger_owner_type, uuid, numeric, text) from public, anon, authenticated;

-- Hooked into the three places money is handed over. Each body is otherwise
-- the 20260810054956 version.

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

  perform public.notify_settlement(p_owner_type, p_owner_id, p_amount);

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

  -- A rejection matters more than an approval: the driver is expecting money
  -- that is not coming, and needs to know why.
  insert into public.notifications (user_id, title, body, type, route)
  values (
    v_request.driver_id,
    case when p_approve then 'Deposit approved' else 'Deposit rejected' end,
    case when p_approve
      then to_char(v_request.amount, 'FM999999990.00') || ' EGP added to your wallet.'
      else coalesce(p_notes, 'Your deposit could not be confirmed.') end,
    'settlement', '/driver-app/wallet');

  return jsonb_build_object('request_id', p_request_id, 'approved', p_approve,
    'transaction_id', v_txn);
end;
$$;

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

  perform public.notify_settlement('vendor', p_vendor_id, v_net, 'early');

  return jsonb_build_object('settlement_id', v_settlement,
    'payable', v_payable, 'fee', v_fee, 'net_payout', v_net);
end;
$$;

