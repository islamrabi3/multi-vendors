-- Records whoever is holding the customer's money, for online orders too.
--
-- With this the ledger has a single, checkable invariant: the sum of every
-- signed amount across all parties is zero. Money is only ever moved between
-- the three accounts, never created -- so a non-zero total means a bug, and
-- `finance_integrity_check` says so out loud.

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
  v_holder text;
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

  -- Exactly one party holds the customer's money, and always the full total.
  -- This is the liability the earnings below are paid out of, and recording it
  -- for online orders too is what makes the ledger balance globally.
  if v_is_cod and v_order.order_type = 'pickup' then
    v_holder := 'vendor';
    perform public.finance_post('vendor', v_order.vendor_id, 'cash_collection',
      v_order.total, 'debit', p_order_id, v_order.order_number,
      'Cash taken at the counter', '{}'::jsonb, v_key || 'cash');
  elsif v_is_cod and v_order.driver_id is not null then
    v_holder := 'driver';
    perform public.finance_post('driver', v_order.driver_id, 'cash_collection',
      v_order.total, 'debit', p_order_id, v_order.order_number,
      'Cash collected from customer', '{}'::jsonb, v_key || 'cash');
  elsif not v_is_cod then
    -- Card or in-app wallet: the platform was paid directly and now owes the
    -- store and the driver their share of it.
    v_holder := 'platform';
    perform public.finance_post('platform', null, 'online_collection',
      v_order.total, 'debit', p_order_id, v_order.order_number,
      'Paid online to the platform',
      jsonb_build_object('payment_method', v_order.payment_method),
      v_key || 'collection');
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
    'money_held_by', v_holder);
end;
$$;


-- The whole system in one number.
--
-- Every ledger row moves money between the three accounts; none creates or
-- destroys it. So the signed total across all parties must be exactly zero,
-- and any other answer is a bug worth waking someone for.
create or replace function public.finance_integrity_check()
returns jsonb language sql stable security definer set search_path = public
as $$
  select jsonb_build_object(
    'net_across_all_parties', coalesce(round(sum(signed_amount), 2), 0),
    'balanced', coalesce(round(sum(signed_amount), 2), 0) = 0,
    'posted_rows', count(*) filter (where status = 'posted'),
    'wallets_out_of_sync', (
      select count(*) from public.finance_wallets w
      where w.balance <> coalesce((
        select sum(t.signed_amount) from public.ledger_transactions t
        where t.wallet_id = w.id and t.status = 'posted'), 0)),
    'delivered_unsettled', (
      select count(*) from public.orders
      where status = 'delivered' and settlement_status <> 'settled')
  )
  from public.ledger_transactions where status = 'posted';
$$;

revoke all on function public.finance_integrity_check() from public, anon;
grant execute on function public.finance_integrity_check() to authenticated;
