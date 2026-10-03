-- A store is only charged for orders it runs itself.
--
-- On a platform or direct order the store never saw the order in the app: an
-- operator or a rider bought from it like any other customer would. Taking a
-- commission off that sale charges the store for a service it did not use.
-- So those orders carry no commission — not in the ledger when the order is
-- settled, and not in any report that works the figure out again from the
-- orders. A store currently run by the platform is also left out of the
-- monthly subscription total, for the same reason.

-- ---------------------------------------------------------------------------
-- The ledger
-- ---------------------------------------------------------------------------
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.finance_settle_order(uuid)'::regprocedure);
  if d like '%v_order.order_flow%' then
    return;
  end if;

  n := replace(d,
    '  v_vendor_net := round(
    v_order.subtotal - v_markup - v_vendor_discount - v_commission, 2);',
    '  -- Only an order the store ran itself earns the platform a commission.
  if v_order.order_flow <> ''vendor'' then
    v_commission := 0;
  end if;

  v_vendor_net := round(
    v_order.subtotal - v_markup - v_vendor_discount - v_commission, 2);');

  if n = d then
    raise exception 'finance_settle_order anchors not found';
  end if;
  execute n;
end
$patch$;

-- ---------------------------------------------------------------------------
-- The platform report
-- ---------------------------------------------------------------------------
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef(
    'public.admin_platform_report(timestamptz, timestamptz, numeric)'::regprocedure);
  if d like '%o.order_flow%' then
    return;
  end if;

  -- A zero rate makes order_commission() come out at zero for that order.
  n := replace(d,
    '      coalesce(vn.commission_rate, 10) as commission_rate,',
    '      case when o.order_flow <> ''vendor'' then 0
           else coalesce(vn.commission_rate, 10) end as commission_rate,');

  n := replace(n,
    '  where coalesce(billing_model, ''commission'') = ''subscription''
    and approval_status = ''active'';',
    '  where coalesce(billing_model, ''commission'') = ''subscription''
    and approval_status = ''active''
    and coalesce(order_flow, ''vendor'') = ''vendor'';');

  if n not like '%o.order_flow%' or n not like '%coalesce(order_flow%' then
    raise exception 'admin_platform_report anchors not found';
  end if;
  execute n;
end
$patch$;

-- ---------------------------------------------------------------------------
-- Per-store sales report
-- ---------------------------------------------------------------------------
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
      -- A store the platform runs is not paying to be on it.
      case when coalesce(v.order_flow, 'vendor') = 'vendor'
           then coalesce(v.subscription_fee, 0) else 0 end as subscription_fee,
      o.id as order_id,
      o.order_flow,
      o.subtotal - coalesce(o.markup_amount, 0) as subtotal,
      -- A store-scoped coupon is that store's own marketing spend; a
      -- platform-wide one is not, and must not be taken off its payout.
      case when (c.vendor_id is not null and c.funded_by = 'vendor') then o.discount else 0 end
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
      round(coalesce(sum(s.vendor_discount), 0), 2) as discounts,
      -- Only the orders the store ran itself carry a commission.
      round(coalesce(sum(s.subtotal - s.vendor_discount)
        filter (where s.order_flow = 'vendor'), 0), 2) as commission_base
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
                            t.commission_base) as commission_fee,
    round(
      t.gross - t.discounts
      - public.order_commission(t.billing_model, t.commission_rate,
                                t.commission_base),
      2) as net_payout
  from totals t
  order by t.gross desc;
end;
$$;

-- ---------------------------------------------------------------------------
-- The store's own settlement view
-- ---------------------------------------------------------------------------
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
      o.subtotal - coalesce(o.markup_amount, 0) as subtotal,
      o.delivery_fee,
      o.total,
      o.order_flow,
      case when (c.vendor_id is not null and c.funded_by = 'vendor') then o.discount else 0 end
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
      round(coalesce(avg(total), 0), 2) as average_order,
      -- Only the orders the store ran itself carry a commission.
      round(coalesce(sum(subtotal - vendor_discount)
        filter (where order_flow = 'vendor'), 0), 2) as commission_base
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
    'subscription_fee', case
      when coalesce(v_vendor.order_flow, 'vendor') = 'vendor'
      then coalesce(v_vendor.subscription_fee, 0) else 0 end,
    'commission', public.order_commission(
      coalesce(v_vendor.billing_model, 'commission'),
      coalesce(v_vendor.commission_rate, 10),
      t.commission_base),
    'net_payout', round(
      t.item_sales - t.vendor_discounts
      - public.order_commission(
          coalesce(v_vendor.billing_model, 'commission'),
          coalesce(v_vendor.commission_rate, 10),
          t.commission_base),
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
