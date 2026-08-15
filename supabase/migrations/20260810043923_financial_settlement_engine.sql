-- Turning a delivered order into ledger rows.
--
-- The order module does not touch a balance. It calls `finance_settle_order`,
-- which is the only thing that knows how an order divides, and which can be
-- called any number of times for the same order without paying anyone twice.
--
-- NOTE: `finance_settle_order` is superseded twice below this migration — by
-- 20260810044401 (records who holds the money on online orders) and by
-- 20260810044545 (platform discount is a debit). The body here is the original
-- and is kept so the history reads in order.

alter table public.orders
  add column if not exists settlement_status public.order_settlement_status
    not null default 'pending',
  add column if not exists settled_at timestamptz,
  add column if not exists cash_status public.cash_status
    not null default 'not_applicable';

create index if not exists orders_settlement_status_idx
  on public.orders (settlement_status) where settlement_status <> 'settled';

-- The driver's cut of the delivery fee, as a percentage. A single stored
-- number rather than an argument, so the reports, the settlement and the
-- driver's own screen cannot each be told something different.
create or replace function public.driver_delivery_share()
returns numeric language sql stable security definer
set search_path = public, private
as $$
  select coalesce(
    (select value::numeric from private.app_config where key = 'driver_delivery_share'),
    90);
$$;

grant execute on function public.driver_delivery_share() to authenticated;

-- Finds or creates a party's account.
create or replace function public.finance_wallet_for(
  p_owner_type public.ledger_owner_type,
  p_owner_id uuid
)
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  v_id uuid;
begin
  if p_owner_type = 'platform' then
    select id into v_id from public.finance_wallets
    where owner_type = 'platform' and owner_id is null;
    if v_id is null then
      insert into public.finance_wallets (owner_type, owner_id)
      values ('platform', null) on conflict do nothing returning id into v_id;
      if v_id is null then
        select id into v_id from public.finance_wallets
        where owner_type = 'platform' and owner_id is null;
      end if;
    end if;
    return v_id;
  end if;

  if p_owner_id is null then
    raise exception 'OWNER_REQUIRED';
  end if;

  select id into v_id from public.finance_wallets
  where owner_type = p_owner_type and owner_id = p_owner_id;
  if v_id is null then
    insert into public.finance_wallets (owner_type, owner_id)
    values (p_owner_type, p_owner_id) on conflict do nothing returning id into v_id;
    if v_id is null then
      select id into v_id from public.finance_wallets
      where owner_type = p_owner_type and owner_id = p_owner_id;
    end if;
  end if;
  return v_id;
end;
$$;

-- Writes one ledger row. Every other function goes through this.
--
-- Returns the existing row's id when `p_idempotency_key` has already been
-- used, so a caller that retries gets the same answer rather than a duplicate
-- or an error. That is what makes the whole system safe to retry.
create or replace function public.finance_post(
  p_owner_type public.ledger_owner_type,
  p_owner_id uuid,
  p_type public.ledger_entry_type,
  p_amount numeric,
  p_direction public.ledger_direction,
  p_order_id uuid default null,
  p_reference text default null,
  p_description text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_idempotency_key text default null,
  p_status public.ledger_status default 'posted',
  p_created_by uuid default null
)
returns uuid language plpgsql security definer set search_path = public
as $$
declare
  v_wallet uuid;
  v_id uuid;
begin
  if p_amount is null or p_amount < 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  -- A zero row carries no money and only clutters the trail.
  if p_amount = 0 then
    return null;
  end if;

  if p_idempotency_key is not null then
    select id into v_id from public.ledger_transactions
    where idempotency_key = p_idempotency_key;
    if v_id is not null then
      return v_id;
    end if;
  end if;

  v_wallet := public.finance_wallet_for(p_owner_type, p_owner_id);

  insert into public.ledger_transactions (
    wallet_id, owner_type, owner_id, order_id, type, amount, direction,
    status, reference, description, metadata, idempotency_key, created_by
  ) values (
    v_wallet, p_owner_type, p_owner_id, p_order_id, p_type, round(p_amount, 2),
    p_direction, p_status, p_reference, p_description,
    coalesce(p_metadata, '{}'::jsonb), p_idempotency_key,
    coalesce(p_created_by, auth.uid())
  )
  -- Two concurrent callers with the same key: one inserts, the other reads.
  on conflict (idempotency_key) where idempotency_key is not null do nothing
  returning id into v_id;

  if v_id is null and p_idempotency_key is not null then
    select id into v_id from public.ledger_transactions
    where idempotency_key = p_idempotency_key;
  end if;

  return v_id;
end;
$$;

revoke all on function public.finance_post(
  public.ledger_owner_type, uuid, public.ledger_entry_type, numeric,
  public.ledger_direction, uuid, text, text, jsonb, text,
  public.ledger_status, uuid) from public, anon, authenticated;

-- Splits one delivered order across the three parties.
--
-- Idempotent twice over: the order row is locked and short-circuits once its
-- `settlement_status` is `settled`, and every individual ledger row carries an
-- idempotency key of its own. Either guard alone would be enough; together
-- they also survive a crash between the two.
--
-- Everything happens in the caller's transaction, so a failure anywhere rolls
-- back the whole split.
create or replace function public.finance_settle_order(p_order_id uuid)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_vendor public.vendors%rowtype;
  v_share numeric := public.driver_delivery_share();
  v_vendor_discount numeric := 0;
  v_platform_discount numeric := 0;
  v_commission numeric := 0;
  v_vendor_net numeric := 0;
  v_driver_earning numeric := 0;
  v_delivery_margin numeric := 0;
  v_key text := 'order:' || p_order_id::text || ':';
  v_is_cod boolean;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  if v_order.settlement_status = 'settled' then
    return jsonb_build_object('status', 'already_settled', 'order_id', p_order_id);
  end if;
  if v_order.status <> 'delivered' then raise exception 'ORDER_NOT_DELIVERED'; end if;

  select * into v_vendor from public.vendors where id = v_order.vendor_id;

  -- Who funded the discount, exactly as the reports decide it.
  select
    case when c.vendor_id is not null then coalesce(v_order.discount, 0) else 0 end,
    case when c.vendor_id is null then coalesce(v_order.discount, 0) else 0 end
  into v_vendor_discount, v_platform_discount
  from (select 1) x
  left join public.coupons c on c.id = v_order.coupon_id;

  v_vendor_discount := coalesce(v_vendor_discount, 0);
  v_platform_discount := coalesce(v_platform_discount, 0);

  v_commission := public.order_commission(
    coalesce(v_vendor.billing_model, 'commission'),
    coalesce(v_vendor.commission_rate, 10),
    v_order.subtotal - v_vendor_discount);

  v_vendor_net := round(v_order.subtotal - v_vendor_discount - v_commission, 2);
  v_delivery_margin := round(coalesce(v_order.delivery_fee, 0) * (100 - v_share) / 100.0, 2);
  v_driver_earning := round(coalesce(v_order.delivery_fee, 0) * v_share / 100.0, 2);
  v_is_cod := v_order.payment_method = 'cod';

  update public.orders set settlement_status = 'processing' where id = p_order_id;

  if v_is_cod then
    if v_order.order_type = 'pickup' then
      perform public.finance_post('vendor', v_order.vendor_id, 'cash_collection',
        v_order.total, 'debit', p_order_id, v_order.order_number,
        'Cash taken at the counter', '{}'::jsonb, v_key || 'cash');
    elsif v_order.driver_id is not null then
      perform public.finance_post('driver', v_order.driver_id, 'cash_collection',
        v_order.total, 'debit', p_order_id, v_order.order_number,
        'Cash collected from customer', '{}'::jsonb, v_key || 'cash');
    end if;
  end if;

  if v_order.driver_id is not null and v_driver_earning > 0 then
    perform public.finance_post('driver', v_order.driver_id, 'driver_earning',
      v_driver_earning, 'credit', p_order_id, v_order.order_number,
      'Delivery fee share', jsonb_build_object('share_percent', v_share),
      v_key || 'driver');
  end if;

  perform public.finance_post('vendor', v_order.vendor_id, 'vendor_earning',
    v_vendor_net, 'credit', p_order_id, v_order.order_number, 'Order earnings',
    jsonb_build_object('subtotal', v_order.subtotal,
      'vendor_discount', v_vendor_discount, 'commission', v_commission,
      'billing_model', coalesce(v_vendor.billing_model, 'commission')),
    v_key || 'vendor');

  perform public.finance_post('platform', null, 'platform_commission',
    v_commission, 'credit', p_order_id, v_order.order_number, 'Commission',
    '{}'::jsonb, v_key || 'commission');

  perform public.finance_post('platform', null, 'platform_delivery_margin',
    v_delivery_margin, 'credit', p_order_id, v_order.order_number,
    'Delivery margin', '{}'::jsonb, v_key || 'margin');

  perform public.finance_post('platform', null, 'platform_discount',
    v_platform_discount, 'debit', p_order_id, v_order.order_number,
    'Platform-funded discount', '{}'::jsonb, v_key || 'discount');

  update public.orders set
    settlement_status = 'settled', settled_at = now(),
    cash_status = case when not v_is_cod then 'not_applicable'::public.cash_status
                       else 'cash_collected'::public.cash_status end
  where id = p_order_id;

  return jsonb_build_object('status', 'settled', 'order_id', p_order_id,
    'vendor_net', v_vendor_net, 'driver_earning', v_driver_earning,
    'commission', v_commission, 'delivery_margin', v_delivery_margin,
    'platform_discount', v_platform_discount,
    'cash_held_by', case when not v_is_cod then null
      when v_order.order_type = 'pickup' then 'vendor' else 'driver' end);
end;
$$;

revoke all on function public.finance_settle_order(uuid) from public, anon;
grant execute on function public.finance_settle_order(uuid) to authenticated;

-- `update_order_status` is the only route to `delivered`, so it is the only
-- place settlement has to be wired. The body is the 20260806 version with one
-- call added at the end; nothing else changed.
create or replace function public.update_order_status(
  p_order_id uuid, p_new_status public.order_status, p_reason text default null)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_is_customer boolean; v_is_vendor boolean; v_is_driver boolean;
  v_is_admin boolean; v_allowed boolean := false;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  v_is_customer := v_order.customer_id = auth.uid();
  v_is_vendor := public.is_vendor_owner(v_order.vendor_id);
  v_is_driver := v_order.driver_id = auth.uid();
  v_is_admin := public.is_admin();

  if v_is_vendor then
    v_allowed := (v_order.status = 'pending' and p_new_status in ('accepted', 'rejected'))
              or (v_order.status = 'accepted' and p_new_status = 'preparing')
              or (v_order.status = 'preparing' and p_new_status = 'ready_for_pickup')
              -- Pickup only: nobody else can hand the food over.
              or (v_order.order_type = 'pickup' and v_order.status = 'ready_for_pickup'
                  and p_new_status = 'delivered');
  end if;
  if not v_allowed and v_is_driver then
    v_allowed := v_order.status = 'out_for_delivery' and p_new_status = 'delivered';
  end if;
  if not v_allowed and v_is_customer then
    v_allowed := v_order.status = 'pending' and p_new_status = 'cancelled';
  end if;
  if not v_allowed and v_is_admin then
    v_allowed := v_order.status not in ('delivered', 'cancelled', 'rejected')
             and p_new_status = 'cancelled';
  end if;
  if not v_allowed then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> %', v_order.status, p_new_status;
  end if;

  update public.orders
  set status = p_new_status,
      rejection_reason = case
        when p_new_status in ('rejected', 'cancelled') and p_reason is not null
          then p_reason else rejection_reason end,
      accepted_at = case when p_new_status = 'accepted' then now() else accepted_at end,
      ready_at = case when p_new_status = 'ready_for_pickup' then now() else ready_at end,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      cancelled_at = case when p_new_status in ('cancelled', 'rejected') then now()
                          else cancelled_at end,
      payment_status = case
        when p_new_status = 'delivered' and payment_method = 'cod'
          then 'paid'::public.payment_status else payment_status end
  where id = p_order_id;

  -- Same transaction as the status change: an order cannot end up delivered
  -- but unsettled, or settled but not delivered.
  if p_new_status = 'delivered' then
    perform public.finance_settle_order(p_order_id);
  end if;
end;
$$;

-- Backfills orders that were delivered before any of this existed, so the
-- ledger opens with a true position rather than pretending the business
-- started today.
create or replace function public.finance_backfill_settlements(p_limit int default 5000)
returns int language plpgsql security definer set search_path = public
as $$
declare v_row record; v_count int := 0;
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  for v_row in
    select id from public.orders
    where status = 'delivered' and settlement_status <> 'settled'
    order by created_at limit p_limit
  loop
    perform public.finance_settle_order(v_row.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.finance_backfill_settlements(int) from public, anon;
grant execute on function public.finance_backfill_settlements(int) to authenticated;
