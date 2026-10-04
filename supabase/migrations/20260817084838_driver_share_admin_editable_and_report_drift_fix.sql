-- Real bug: the Sales & Financial Reports screen priced every delivery split
-- at a driver share of exactly 90%, hardcoded as the RPC parameter's default
-- and never overridden by the client. The actual settlement engine
-- (`finance_settle_order`) has read a *configurable* `driver_delivery_share()`
-- since the early-settlement-fee work. The two happened to agree (both 90)
-- only because nothing had changed the config yet — the moment it does, the
-- reports silently stop matching what vendors and drivers were actually paid,
-- which is indistinguishable from "the report's math is wrong" to whoever is
-- reading it.
--
-- Fixed by making both report RPCs default to the live config instead of a
-- literal 90, the same way `finance_settle_order` already does.

create or replace function public.admin_platform_report(
  p_start timestamp with time zone default null,
  p_end timestamp with time zone default null,
  p_driver_share numeric default null)
returns jsonb language plpgsql security definer
set search_path = public
as $$
declare
  v jsonb;
  v_subscriptions numeric;
  v_subscription_stores int;
  -- Only ever supplied by a caller deliberately asking "what if the split
  -- were X" — the report screen no longer sends one, so this is the live
  -- config on every real read, exactly like the ledger.
  v_share numeric := coalesce(p_driver_share, public.driver_delivery_share());
begin
  if not public.has_permission('reports.view') then
    raise exception 'FORBIDDEN';
  end if;
  if v_share < 0 or v_share > 100 then
    raise exception 'INVALID_SHARE';
  end if;

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
    'platform_discounts',
      (select round(coalesce(sum(platform_discount), 0), 2) from d),
    'commission', (select round(coalesce(sum(
        public.order_commission(billing_model, commission_rate,
                                subtotal - vendor_discount)), 0), 2) from d),
    'delivery_margin', (select round(coalesce(sum(
        delivery_fee * (100 - v_share) / 100.0), 0), 2) from d),
    'driver_cost', (select round(coalesce(sum(
        delivery_fee * v_share / 100.0 + driver_tip), 0), 2) from d),
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
    'driver_share', v_share
  )
  into v;

  return v;
end;
$$;

create or replace function public.admin_driver_payout_report(
  p_start timestamp with time zone default null,
  p_end timestamp with time zone default null,
  p_driver_share numeric default null)
returns table(
  driver_id uuid, driver_name text, delivered_orders bigint,
  delivery_fees numeric, driver_fee_share numeric, platform_fee_share numeric,
  tips numeric, net_payout numeric)
language plpgsql security definer
set search_path = public
as $$
declare
  v_share numeric := coalesce(p_driver_share, public.driver_delivery_share());
begin
  if not public.has_permission('reports.view') then
    raise exception 'FORBIDDEN';
  end if;
  if v_share < 0 or v_share > 100 then
    raise exception 'INVALID_SHARE';
  end if;

  return query
  select
    p.id,
    coalesce(nullif(trim(p.full_name), ''), 'Driver'),
    count(o.id),
    round(coalesce(sum(o.delivery_fee), 0), 2) as delivery_fees,
    round(coalesce(sum(o.delivery_fee), 0) * v_share / 100.0, 2)
      as driver_fee_share,
    round(
      coalesce(sum(o.delivery_fee), 0) * (100 - v_share) / 100.0, 2)
      as platform_fee_share,
    round(coalesce(sum(o.driver_tip), 0), 2) as tips,
    round(
      coalesce(sum(o.delivery_fee), 0) * v_share / 100.0
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

-- The other half of the request: an admin control for the value both of the
-- above now read live. Same shape as the early-settlement-fee control —
-- read/write pair over `private.app_config`, gated on `finance.adjust`, and
-- audited.

create or replace function public.admin_driver_share_config()
returns jsonb language plpgsql stable security definer
set search_path = public, private
as $$
begin
  if not public.has_permission('reports.view') then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object('driver_share', public.driver_delivery_share());
end;
$$;

create or replace function public.admin_set_driver_share(p_share numeric)
returns jsonb language plpgsql security definer
set search_path = public, private
as $$
declare
  v_old numeric := public.driver_delivery_share();
begin
  if not public.has_permission('finance.adjust') then raise exception 'FORBIDDEN'; end if;
  if p_share is null or p_share < 0 or p_share > 100 then
    raise exception 'INVALID_SHARE';
  end if;

  insert into private.app_config (key, value)
  values ('driver_delivery_share', round(p_share, 2)::text)
  on conflict (key) do update set value = excluded.value;

  perform public.log_admin_action(
    'finance.driver_share', 'config', null,
    jsonb_build_object('from', v_old, 'to', round(p_share, 2)));

  return jsonb_build_object('driver_share', public.driver_delivery_share());
end;
$$;

revoke all on function public.admin_driver_share_config() from public, anon;
revoke all on function public.admin_set_driver_share(numeric) from public, anon;
grant execute on function public.admin_driver_share_config() to authenticated;
grant execute on function public.admin_set_driver_share(numeric) to authenticated;;
