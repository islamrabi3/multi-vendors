-- What a store is actually owed, from the store's own side.
--
-- The vendor analytics screen summed `orders.total` and called it revenue.
-- That figure includes the delivery fee — which goes to the driver and the
-- platform, never to the store — and says nothing about commission, so the
-- number a store owner saw was neither their sales nor their payout.
--
-- This returns the same settlement the admin's vendor report produces, scoped
-- to one store, so the two can never disagree: both call `order_commission`
-- and both split discounts by who funded the coupon.
create or replace function public.vendor_settlement(
  p_vendor_id uuid,
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_vendor public.vendors%rowtype;
  v jsonb;
begin
  select * into v_vendor from public.vendors where id = p_vendor_id;
  if not found then
    raise exception 'VENDOR_NOT_FOUND';
  end if;

  -- The owner, or an admin looking at the store's file. Nobody else: this is
  -- the store's commercial position.
  if v_vendor.owner_id <> (select auth.uid()) and not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  with scoped as (
    select
      o.subtotal,
      o.delivery_fee,
      o.total,
      case when c.vendor_id is not null then o.discount else 0 end
        as vendor_discount
    from public.orders o
    left join public.coupons c on c.id = o.coupon_id
    where o.vendor_id = p_vendor_id
      and o.status = 'delivered'
      and (p_start is null or o.created_at >= p_start)
      and (p_end is null or o.created_at <= p_end)
  ),
  t as (
    select
      count(*) as orders,
      round(coalesce(sum(subtotal), 0), 2) as item_sales,
      round(coalesce(sum(vendor_discount), 0), 2) as vendor_discounts,
      round(coalesce(sum(delivery_fee), 0), 2) as delivery_fees,
      round(coalesce(avg(total), 0), 2) as average_order
    from scoped
  )
  select jsonb_build_object(
    'delivered_orders', t.orders,
    -- What the store sold, before anything is taken off. Not `total`: the
    -- delivery fee in there was never the store's money.
    'item_sales', t.item_sales,
    'vendor_discounts', t.vendor_discounts,
    -- Collected from the customer and passed on; shown so the store can
    -- reconcile against what the customer was charged.
    'delivery_fees_collected', t.delivery_fees,
    'average_order', t.average_order,
    'billing_model', coalesce(v_vendor.billing_model, 'commission'),
    'commission_rate', case
      when coalesce(v_vendor.billing_model, 'commission') = 'subscription'
      then 0 else coalesce(v_vendor.commission_rate, 10) end,
    'subscription_fee', coalesce(v_vendor.subscription_fee, 0),
    'commission', public.order_commission(
      coalesce(v_vendor.billing_model, 'commission'),
      coalesce(v_vendor.commission_rate, 10),
      t.item_sales - t.vendor_discounts),
    'net_payout', round(
      t.item_sales - t.vendor_discounts
      - public.order_commission(
          coalesce(v_vendor.billing_model, 'commission'),
          coalesce(v_vendor.commission_rate, 10),
          t.item_sales - t.vendor_discounts),
      2),
    -- Real figures rather than the placeholders the screen used to print.
    'rating_avg', coalesce(v_vendor.rating_avg, 0),
    'rating_count', coalesce(v_vendor.rating_count, 0),
    'avg_prep_minutes', coalesce(v_vendor.avg_prep_minutes, 0)
  )
  into v
  from t;

  return v;
end;
$$;

revoke all on function public.vendor_settlement(uuid, timestamptz, timestamptz)
  from public, anon;
grant execute on function public.vendor_settlement(uuid, timestamptz, timestamptz)
  to authenticated;
