-- Settlement, corrected for the two billing models.
--
-- Three things were wrong, and they compounded:
--
--   1. `vendors.billing_model` was ignored. A store on the subscription plan
--      pays a flat monthly fee and no per-order cut, but every report charged
--      it `subtotal * commission_rate` anyway — overstating platform
--      commission and understating what the store is owed.
--
--   2. Discounts were shown but never deducted. `net_margin` was
--      `commission - driver_cost + delivery_fees`, with no discount term, so a
--      coupon the platform funded cost it nothing on paper. Who funds one now
--      follows the coupon: a coupon scoped to a store (`coupons.vendor_id`) is
--      that store's marketing and comes out of its payout; a platform-wide
--      coupon comes out of platform margin.
--
--   3. Tips were booked as a platform cost. `driver_tip` is not part of
--      `orders.total` — the customer pays it on top and the driver keeps all
--      of it — so counting it against margin understated the platform by the
--      whole tip. It is a pass-through and now sits outside the P&L entirely.
--
-- The delivery fee is also split explicitly rather than being added back
-- whole: the driver keeps `p_driver_share`% and the platform keeps the rest.
-- That remainder is what the driver report was missing — it showed the 18 the
-- driver takes from a 20 fee and never showed the 2 the platform keeps.

-- ===========================================================================
-- Shared: what one store's cut is on one order
-- ===========================================================================

-- Per-order commission, honouring the billing model.
--
-- Immutable and tiny so it can be inlined into the aggregate queries below and
-- stay the single definition of the rule — three reports disagreeing about the
-- commission is how this drifted in the first place.
create or replace function public.order_commission(
  p_billing_model text,
  p_commission_rate numeric,
  p_commission_base numeric
)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select case
    -- A subscription store has already paid; taking a cut as well would be
    -- charging it twice for the same order.
    when p_billing_model = 'subscription' then 0::numeric
    else round(
      greatest(p_commission_base, 0) * coalesce(p_commission_rate, 10) / 100.0,
      2)
  end;
$$;

grant execute on function public.order_commission(text, numeric, numeric)
  to authenticated;

-- ===========================================================================
-- Vendor settlement
-- ===========================================================================

drop function if exists public.admin_vendor_sales_report(timestamptz, timestamptz);

create or replace function public.admin_vendor_sales_report(
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns table(
  vendor_id uuid,
  vendor_name text,
  total_orders bigint,
  gross_sales numeric,
  vendor_discounts numeric,
  billing_model text,
  commission_rate numeric,
  subscription_fee numeric,
  commission_fee numeric,
  net_payout numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('reports.view') then
    raise exception 'FORBIDDEN';
  end if;

  return query
  with scoped as (
    select
      v.id,
      v.name,
      coalesce(v.billing_model, 'commission') as billing_model,
      coalesce(v.commission_rate, 10) as commission_rate,
      coalesce(v.subscription_fee, 0) as subscription_fee,
      o.id as order_id,
      o.subtotal,
      -- A store-scoped coupon is that store's own marketing spend; a
      -- platform-wide one is not, and must not be taken off its payout.
      case when c.vendor_id is not null then o.discount else 0 end
        as vendor_discount
    from public.vendors v
    join public.orders o on o.vendor_id = v.id
    left join public.coupons c on c.id = o.coupon_id
    where o.status = 'delivered'
      and (p_start is null or o.created_at >= p_start)
      and (p_end is null or o.created_at <= p_end)
  ),
  totals as (
    select
      s.id,
      s.name,
      s.billing_model,
      s.commission_rate,
      s.subscription_fee,
      count(s.order_id) as orders,
      round(coalesce(sum(s.subtotal), 0), 2) as gross,
      round(coalesce(sum(s.vendor_discount), 0), 2) as discounts
    from scoped s
    group by s.id, s.name, s.billing_model, s.commission_rate, s.subscription_fee
  )
  select
    t.id,
    t.name,
    t.orders,
    t.gross,
    t.discounts,
    t.billing_model,
    -- Reported as 0 on a subscription store rather than the dormant rate on
    -- its row, so the column always matches the fee beside it.
    case when t.billing_model = 'subscription' then 0 else t.commission_rate end,
    t.subscription_fee,
    public.order_commission(t.billing_model, t.commission_rate,
                            t.gross - t.discounts) as commission_fee,
    round(
      t.gross - t.discounts
      - public.order_commission(t.billing_model, t.commission_rate,
                                t.gross - t.discounts),
      2) as net_payout
  from totals t
  order by t.gross desc;
end;
$$;

revoke all on function public.admin_vendor_sales_report(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_vendor_sales_report(timestamptz, timestamptz)
  to authenticated;

-- ===========================================================================
-- Driver settlement
-- ===========================================================================

drop function if exists public.admin_driver_payout_report(timestamptz, timestamptz, numeric);

create or replace function public.admin_driver_payout_report(
  p_start timestamptz default null,
  p_end timestamptz default null,
  p_driver_share numeric default 90
)
returns table(
  driver_id uuid,
  driver_name text,
  delivered_orders bigint,
  delivery_fees numeric,
  driver_fee_share numeric,
  platform_fee_share numeric,
  tips numeric,
  net_payout numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('reports.view') then
    raise exception 'FORBIDDEN';
  end if;
  if p_driver_share < 0 or p_driver_share > 100 then
    raise exception 'INVALID_SHARE';
  end if;

  return query
  select
    p.id,
    coalesce(nullif(trim(p.full_name), ''), 'Driver'),
    count(o.id),
    round(coalesce(sum(o.delivery_fee), 0), 2) as delivery_fees,
    round(coalesce(sum(o.delivery_fee), 0) * p_driver_share / 100.0, 2)
      as driver_fee_share,
    -- The half of the fee the report never showed: what the platform keeps
    -- for putting the order in front of the driver.
    round(
      coalesce(sum(o.delivery_fee), 0) * (100 - p_driver_share) / 100.0, 2)
      as platform_fee_share,
    round(coalesce(sum(o.driver_tip), 0), 2) as tips,
    round(
      coalesce(sum(o.delivery_fee), 0) * p_driver_share / 100.0
      + coalesce(sum(o.driver_tip), 0),
      2) as net_payout
  from public.profiles p
  join public.orders o on o.driver_id = p.id
  where o.status = 'delivered'
    and (p_start is null or o.created_at >= p_start)
    and (p_end is null or o.created_at <= p_end)
  group by p.id, p.full_name
  having count(o.id) > 0
  order by 4 desc;
end;
$$;

revoke all on function public.admin_driver_payout_report(timestamptz, timestamptz, numeric)
  from public, anon;
grant execute on function public.admin_driver_payout_report(timestamptz, timestamptz, numeric)
  to authenticated;

-- ===========================================================================
-- Platform P&L
-- ===========================================================================

create or replace function public.admin_platform_report(
  p_start timestamptz default null,
  p_end timestamptz default null,
  p_driver_share numeric default 90
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
  v_subscriptions numeric;
  v_subscription_stores int;
begin
  if not public.has_permission('reports.view') then
    raise exception 'FORBIDDEN';
  end if;
  if p_driver_share < 0 or p_driver_share > 100 then
    raise exception 'INVALID_SHARE';
  end if;

  -- Billed per month, not per order, so it is reported beside the order P&L
  -- rather than folded into it: prorating a monthly fee across an arbitrary
  -- date range would put an invented number in the middle of a settlement.
  select
    round(coalesce(sum(coalesce(subscription_fee, 0)), 0), 2),
    count(*)
  into v_subscriptions, v_subscription_stores
  from public.vendors
  where coalesce(billing_model, 'commission') = 'subscription'
    and approval_status = 'active';

  with scoped as (
    select
      o.status,
      o.subtotal,
      o.delivery_fee,
      o.discount,
      o.total,
      o.payment_method,
      coalesce(o.driver_tip, 0) as driver_tip,
      coalesce(vn.billing_model, 'commission') as billing_model,
      coalesce(vn.commission_rate, 10) as commission_rate,
      case when c.vendor_id is not null then o.discount else 0 end
        as vendor_discount,
      case when c.vendor_id is null then o.discount else 0 end
        as platform_discount
    from public.orders o
    left join public.vendors vn on vn.id = o.vendor_id
    left join public.coupons c on c.id = o.coupon_id
    where (p_start is null or o.created_at >= p_start)
      and (p_end is null or o.created_at <= p_end)
  ),
  d as (select * from scoped where status = 'delivered')
  select jsonb_build_object(
    'delivered_orders', (select count(*) from d),
    'cancelled_orders',
      (select count(*) from scoped where status in ('cancelled', 'rejected')),
    'gross_revenue', (select round(coalesce(sum(total), 0), 2) from d),
    'item_sales', (select round(coalesce(sum(subtotal), 0), 2) from d),
    'delivery_fees', (select round(coalesce(sum(delivery_fee), 0), 2) from d),
    'discounts', (select round(coalesce(sum(discount), 0), 2) from d),
    'vendor_discounts',
      (select round(coalesce(sum(vendor_discount), 0), 2) from d),
    -- The only discount that costs the platform anything.
    'platform_discounts',
      (select round(coalesce(sum(platform_discount), 0), 2) from d),
    -- Summed per order at that store's own model and rate, so a subscription
    -- store contributes nothing here.
    'commission', (select round(coalesce(sum(
        public.order_commission(billing_model, commission_rate,
                                subtotal - vendor_discount)), 0), 2) from d),
    'delivery_margin', (select round(coalesce(sum(
        delivery_fee * (100 - p_driver_share) / 100.0), 0), 2) from d),
    -- What the drivers are owed. Tips are in here because the driver is owed
    -- them; they are excluded from the platform net below because the
    -- platform never earned them.
    'driver_cost', (select round(coalesce(sum(
        delivery_fee * p_driver_share / 100.0 + driver_tip), 0), 2) from d),
    'driver_tips', (select round(coalesce(sum(driver_tip), 0), 2) from d),
    'vendor_payout', (select round(coalesce(sum(
        subtotal - vendor_discount
        - public.order_commission(billing_model, commission_rate,
                                  subtotal - vendor_discount)), 0), 2) from d),
    'cash_collected', (select round(coalesce(sum(total) filter (
        where payment_method = 'cod'), 0), 2) from d),
    'card_collected', (select round(coalesce(sum(total) filter (
        where payment_method <> 'cod'), 0), 2) from d),
    'average_order', (select round(coalesce(avg(total), 0), 2) from d),
    'subscription_fees_monthly', v_subscriptions,
    'subscription_stores', v_subscription_stores,
    'driver_share', p_driver_share
  )
  into v;

  return v;
end;
$$;

revoke all on function public.admin_platform_report(timestamptz, timestamptz, numeric)
  from public, anon;
grant execute on function public.admin_platform_report(timestamptz, timestamptz, numeric)
  to authenticated;

-- ===========================================================================
-- "Today" means today where the market is
-- ===========================================================================
--
-- `date_trunc('day', now())` truncates in the server's UTC, so an admin in
-- Cairo saw the day roll over at 02:00 and two hours of last night's orders
-- counted as today's.

-- Midnight in the market's timezone, as an instant.
--
-- SECURITY DEFINER because it reads `platform_timezone()`, which is not on the
-- REST surface; it returns nothing but a timestamp, so it is safe to expose.
create or replace function public.start_of_today()
returns timestamptz
language sql
stable
security definer
set search_path = public
as $$
  select date_trunc('day', now() at time zone public.platform_timezone())
         at time zone public.platform_timezone();
$$;

grant execute on function public.start_of_today() to authenticated;

create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_admin() then jsonb_build_object(
    'gmv_today', coalesce((
      select sum(total) from public.orders
      where status not in ('cancelled', 'rejected')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at >= public.start_of_today()), 0),
    'orders_today', (
      select count(*) from public.orders
      where status not in ('cancelled', 'rejected')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at >= public.start_of_today()),
    'vendors_active', (
      select count(*) from public.vendors where approval_status = 'active'),
    'vendors_open', (
      select count(*) from public.vendors
      where approval_status = 'active' and is_open),
    'vendors_pending', (
      select count(*) from public.vendors where approval_status = 'pending'),
    'drivers_online', (
      select count(*) from public.drivers where is_online),
    'drivers_pending', (
      select count(*) from public.drivers where approval_status = 'pending'),
    'support_open', (
      select count(*) from public.support_threads where status = 'open'),
    'orders_attention', (
      select count(*) from public.orders
      where status in ('pending', 'accepted', 'preparing', 'ready_for_pickup')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at < now() - interval '30 minutes')
  ) else jsonb_build_object() end;
$$;
