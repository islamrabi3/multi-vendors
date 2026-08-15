-- What the admin, the driver and the store can actually do with the ledger.
--
-- Every write here is SECURITY DEFINER and checks the caller. The tables grant
-- nothing but SELECT, so these functions are the entire write surface: there
-- is no route by which a driver approves their own deposit or edits a balance.

-- Records that a driver handed cash in, or that a store was paid.
create or replace function public.admin_record_settlement(
  p_owner_type public.ledger_owner_type, p_owner_id uuid, p_amount numeric,
  p_method text default 'cash', p_reference text default null,
  p_notes text default null, p_idempotency_key text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_txn uuid; v_settlement uuid;
  v_type public.ledger_entry_type; v_balance numeric;
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;
  if p_owner_type = 'platform' then raise exception 'PLATFORM_NOT_SETTLEABLE'; end if;

  v_type := case p_owner_type
    when 'driver' then 'driver_settlement'::public.ledger_entry_type
    else 'vendor_settlement'::public.ledger_entry_type end;

  v_txn := public.finance_post(
    p_owner_type, p_owner_id, v_type, p_amount,
    -- A driver handing cash in reduces what they owe; a store being paid
    -- reduces what it is owed. Opposite directions, same idea.
    case when p_owner_type = 'driver' then 'credit'::public.ledger_direction
         else 'debit'::public.ledger_direction end,
    null, p_reference, coalesce(p_notes, 'Settlement'),
    jsonb_build_object('method', p_method), p_idempotency_key);

  if v_txn is null then raise exception 'SETTLEMENT_NOT_RECORDED'; end if;

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

revoke all on function public.admin_record_settlement(
  public.ledger_owner_type, uuid, numeric, text, text, text, text) from public, anon;
grant execute on function public.admin_record_settlement(
  public.ledger_owner_type, uuid, numeric, text, text, text, text) to authenticated;

create or replace function public.driver_create_deposit_request(
  p_amount numeric, p_payment_method text default 'bank_transfer',
  p_reference text default null, p_proof_url text default null,
  p_notes text default null)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if not exists (select 1 from public.drivers where id = auth.uid()) then
    raise exception 'NOT_A_DRIVER';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'INVALID_AMOUNT'; end if;

  -- Nothing is credited here. A request is a claim to have paid, and money
  -- only exists once someone has checked it.
  insert into public.deposit_requests (
    driver_id, amount, payment_method, reference, proof_url, notes
  ) values (
    auth.uid(), round(p_amount, 2), p_payment_method, p_reference, p_proof_url, p_notes
  ) returning id into v_id;
  return v_id;
end;
$$;

revoke all on function public.driver_create_deposit_request(numeric, text, text, text, text)
  from public, anon;
grant execute on function public.driver_create_deposit_request(numeric, text, text, text, text)
  to authenticated;

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

revoke all on function public.admin_review_deposit(uuid, boolean, text) from public, anon;
grant execute on function public.admin_review_deposit(uuid, boolean, text) to authenticated;

create or replace function public.admin_ledger_adjustment(
  p_owner_type public.ledger_owner_type, p_owner_id uuid, p_amount numeric,
  p_direction public.ledger_direction, p_reason text,
  p_type public.ledger_entry_type default 'adjustment', p_reference text default null)
returns uuid language plpgsql security definer set search_path = public
as $$
begin
  if not public.has_permission('finance.adjust') then raise exception 'FORBIDDEN'; end if;
  -- A correction without a stated reason is indistinguishable from theft in
  -- an audit, so the reason is required rather than optional.
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'REASON_REQUIRED'; end if;
  if p_type not in ('adjustment', 'bonus', 'penalty') then
    raise exception 'INVALID_ADJUSTMENT_TYPE';
  end if;

  return public.finance_post(p_owner_type, p_owner_id, p_type, p_amount, p_direction,
    null, p_reference, p_reason, jsonb_build_object('manual', true), null);
end;
$$;

revoke all on function public.admin_ledger_adjustment(
  public.ledger_owner_type, uuid, numeric, public.ledger_direction, text,
  public.ledger_entry_type, text) from public, anon;
grant execute on function public.admin_ledger_adjustment(
  public.ledger_owner_type, uuid, numeric, public.ledger_direction, text,
  public.ledger_entry_type, text) to authenticated;

-- Cancels a posted row without deleting it.
--
-- Writes an opposite row pointing back at the original and flips the original
-- to `reversed`. Both rows stay in the trail, which is the difference between
-- an accounting system and a spreadsheet.
create or replace function public.admin_reverse_transaction(
  p_transaction_id uuid, p_reason text)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_original public.ledger_transactions%rowtype; v_reversal uuid;
begin
  if not public.has_permission('finance.adjust') then raise exception 'FORBIDDEN'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'REASON_REQUIRED'; end if;

  select * into v_original from public.ledger_transactions
  where id = p_transaction_id for update;
  if not found then raise exception 'TRANSACTION_NOT_FOUND'; end if;
  if v_original.status <> 'posted' then raise exception 'ONLY_POSTED_CAN_BE_REVERSED'; end if;

  insert into public.ledger_transactions (
    wallet_id, owner_type, owner_id, order_id, type, amount, direction,
    status, reference, description, metadata, reverses_id, idempotency_key, created_by
  ) values (
    v_original.wallet_id, v_original.owner_type, v_original.owner_id,
    v_original.order_id, 'reversal', v_original.amount,
    case when v_original.direction = 'credit' then 'debit'::public.ledger_direction
         else 'credit'::public.ledger_direction end,
    'posted', v_original.reference, p_reason,
    jsonb_build_object('reversed_type', v_original.type),
    p_transaction_id, 'reversal:' || p_transaction_id::text, auth.uid()
  ) returning id into v_reversal;

  update public.ledger_transactions set status = 'reversed' where id = p_transaction_id;
  return v_reversal;
end;
$$;

revoke all on function public.admin_reverse_transaction(uuid, text) from public, anon;
grant execute on function public.admin_reverse_transaction(uuid, text) to authenticated;

-- Unwinds a whole order: every row it produced is reversed and the order goes
-- back to `pending` settlement.
create or replace function public.admin_reverse_order_settlement(
  p_order_id uuid, p_reason text)
returns int language plpgsql security definer set search_path = public
as $$
declare v_row record; v_count int := 0;
begin
  if not public.has_permission('finance.adjust') then raise exception 'FORBIDDEN'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then raise exception 'REASON_REQUIRED'; end if;

  for v_row in
    select id from public.ledger_transactions where order_id = p_order_id and status = 'posted'
  loop
    perform public.admin_reverse_transaction(v_row.id, p_reason);
    v_count := v_count + 1;
  end loop;

  update public.orders
  set settlement_status = 'pending', settled_at = null, cash_status = 'cash_refunded'
  where id = p_order_id;
  return v_count;
end;
$$;

revoke all on function public.admin_reverse_order_settlement(uuid, text) from public, anon;
grant execute on function public.admin_reverse_order_settlement(uuid, text) to authenticated;

-- One party's position, with the derived figures spelled out so no client has
-- to know the sign convention.
create or replace function public.finance_wallet_summary(
  p_owner_type public.ledger_owner_type, p_owner_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v public.finance_wallets%rowtype; v_last_settlement timestamptz; v_settled numeric;
begin
  if not (public.is_admin()
    or (p_owner_type = 'driver' and p_owner_id = auth.uid())
    or (p_owner_type = 'vendor' and public.is_vendor_owner(p_owner_id))) then
    raise exception 'FORBIDDEN';
  end if;

  select * into v from public.finance_wallets
  where owner_type = p_owner_type
    and (owner_id = p_owner_id or (p_owner_id is null and owner_id is null));

  select max(created_at), coalesce(sum(amount), 0) into v_last_settlement, v_settled
  from public.settlements
  where owner_type = p_owner_type and owner_id = p_owner_id and status = 'completed';

  return jsonb_build_object(
    'owner_type', p_owner_type, 'owner_id', p_owner_id,
    'currency', coalesce(v.currency, 'EGP'),
    'balance', coalesce(v.balance, 0),
    'cash_due', public.wallet_cash_due(coalesce(v.balance, 0)),
    'payable', public.wallet_payable(coalesce(v.balance, 0)),
    'pending_balance', coalesce(v.pending_balance, 0),
    'cash_collected', coalesce(v.cash_collected, 0),
    'cash_settled', coalesce(v.cash_settled, 0),
    'total_earnings', coalesce(v.total_earnings, 0),
    'total_deposited', coalesce(v.total_deposited, 0),
    'total_adjustments', coalesce(v.total_adjustments, 0),
    'total_settlements', coalesce(v_settled, 0),
    'last_settlement_at', v_last_settlement);
end;
$$;

revoke all on function public.finance_wallet_summary(public.ledger_owner_type, uuid)
  from public, anon;
grant execute on function public.finance_wallet_summary(public.ledger_owner_type, uuid)
  to authenticated;

-- The admin's money screen, for a period.
create or replace function public.admin_finance_overview(
  p_start timestamptz default null, p_end timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v jsonb;
begin
  if not public.has_permission('reports.view') then raise exception 'FORBIDDEN'; end if;

  with t as (
    select * from public.ledger_transactions
    where status = 'posted'
      and (p_start is null or created_at >= p_start)
      and (p_end is null or created_at <= p_end)
  ), o as (
    select * from public.orders
    where status = 'delivered'
      and (p_start is null or created_at >= p_start)
      and (p_end is null or created_at <= p_end)
  )
  select jsonb_build_object(
    'total_orders', (select count(*) from o),
    'cash_orders', (select count(*) from o where payment_method = 'cod'),
    'online_orders', (select count(*) from o where payment_method <> 'cod'),
    'cash_collected', (select coalesce(sum(amount), 0) from t where type = 'cash_collection'),
    'driver_earnings', (select coalesce(sum(amount), 0) from t
                        where type in ('driver_earning', 'driver_tip')),
    'vendor_earnings', (select coalesce(sum(amount), 0) from t where type = 'vendor_earning'),
    'platform_commission', (select coalesce(sum(amount), 0) from t
                            where type = 'platform_commission'),
    'platform_delivery_margin', (select coalesce(sum(amount), 0) from t
                                 where type = 'platform_delivery_margin'),
    'platform_discounts', (select coalesce(sum(amount), 0) from t
                           where type = 'platform_discount'),
    'platform_revenue', (select coalesce(sum(signed_amount), 0) from t
                         where owner_type = 'platform'),
    'settlements', (select coalesce(sum(amount), 0) from t
                    where type in ('driver_settlement', 'vendor_settlement')),
    'deposits', (select coalesce(sum(amount), 0) from t where type = 'driver_deposit'),
    'refunds', (select coalesce(sum(amount), 0) from t where type = 'refund'),
    'adjustments', (select coalesce(sum(signed_amount), 0) from t
                    where type in ('adjustment', 'bonus', 'penalty')),
    -- Outstanding is a position, not a flow: it is what is owed right now,
    -- across all time, so it deliberately ignores the period filter.
    'driver_cash_due', (select coalesce(sum(public.wallet_cash_due(balance)), 0)
                        from public.finance_wallets where owner_type = 'driver'),
    'vendor_payable', (select coalesce(sum(public.wallet_payable(balance)), 0)
                       from public.finance_wallets where owner_type = 'vendor'),
    'pending_deposits', (select count(*) from public.deposit_requests where status = 'pending'),
    'unsettled_orders', (select count(*) from public.orders
                         where status = 'delivered' and settlement_status <> 'settled')
  ) into v;
  return v;
end;
$$;

revoke all on function public.admin_finance_overview(timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_finance_overview(timestamptz, timestamptz) to authenticated;

-- Cash reconciliation: what should have been collected against what the ledger
-- says was, and what has come back.
create or replace function public.admin_cash_reconciliation(
  p_start timestamptz default null, p_end timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v_expected numeric; v_collected numeric; v_settled numeric; v_outstanding numeric;
begin
  if not public.has_permission('reports.view') then raise exception 'FORBIDDEN'; end if;

  -- What the orders say should have been taken at the door.
  select coalesce(sum(total), 0) into v_expected from public.orders
  where status = 'delivered' and payment_method = 'cod'
    and (p_start is null or created_at >= p_start)
    and (p_end is null or created_at <= p_end);

  -- What the ledger says was taken.
  select coalesce(sum(amount), 0) into v_collected from public.ledger_transactions
  where status = 'posted' and type = 'cash_collection'
    and (p_start is null or created_at >= p_start)
    and (p_end is null or created_at <= p_end);

  select coalesce(sum(amount), 0) into v_settled from public.ledger_transactions
  where status = 'posted' and type in ('driver_settlement', 'vendor_settlement')
    and (p_start is null or created_at >= p_start)
    and (p_end is null or created_at <= p_end);

  select coalesce(sum(public.wallet_cash_due(balance)), 0) into v_outstanding
  from public.finance_wallets;

  return jsonb_build_object(
    'expected_cash', v_expected, 'collected_cash', v_collected,
    'settled_cash', v_settled, 'outstanding_cash', v_outstanding,
    -- Non-zero means an order was delivered for cash without a matching
    -- collection row, which is a settlement that did not run. It is an
    -- exception for a human, not a number to quietly absorb.
    'difference', round(v_expected - v_collected, 2));
end;
$$;

revoke all on function public.admin_cash_reconciliation(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_cash_reconciliation(timestamptz, timestamptz)
  to authenticated;

create or replace function public.admin_driver_balances()
returns table(driver_id uuid, driver_name text, balance numeric, cash_due numeric,
  payable numeric, cash_collected numeric, total_earnings numeric,
  total_settlements numeric, last_settlement_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select w.owner_id, coalesce(nullif(trim(p.full_name), ''), 'Driver'), w.balance,
    public.wallet_cash_due(w.balance), public.wallet_payable(w.balance),
    w.cash_collected, w.total_earnings, coalesce(s.total, 0), s.last_at
  from public.finance_wallets w
  left join public.profiles p on p.id = w.owner_id
  left join lateral (
    select sum(amount) as total, max(created_at) as last_at from public.settlements
    where owner_type = 'driver' and owner_id = w.owner_id and status = 'completed'
  ) s on true
  where w.owner_type = 'driver' and public.has_permission('reports.view')
  order by public.wallet_cash_due(w.balance) desc;
$$;

revoke all on function public.admin_driver_balances() from public, anon;
grant execute on function public.admin_driver_balances() to authenticated;

create or replace function public.admin_vendor_balances()
returns table(vendor_id uuid, vendor_name text, balance numeric, payable numeric,
  cash_due numeric, total_earnings numeric, total_settlements numeric,
  last_settlement_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select w.owner_id, coalesce(v.name, 'Store'), w.balance,
    public.wallet_payable(w.balance), public.wallet_cash_due(w.balance),
    w.total_earnings, coalesce(s.total, 0), s.last_at
  from public.finance_wallets w
  left join public.vendors v on v.id = w.owner_id
  left join lateral (
    select sum(amount) as total, max(created_at) as last_at from public.settlements
    where owner_type = 'vendor' and owner_id = w.owner_id and status = 'completed'
  ) s on true
  where w.owner_type = 'vendor' and public.has_permission('reports.view')
  order by public.wallet_payable(w.balance) desc;
$$;

revoke all on function public.admin_vendor_balances() from public, anon;
grant execute on function public.admin_vendor_balances() to authenticated;
