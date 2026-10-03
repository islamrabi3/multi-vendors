-- On an order no store is running, the driver buys it at the counter.
--
-- Platform and direct orders come from stores that are not in the app. The
-- driver pays the store its own price in cash, takes the bag, and brings it
-- to the customer. So when such an order is settled:
--
--   * the store is owed nothing — it was paid on the spot, and there is no
--     commission (20260923110000);
--   * the driver is credited what they paid the store, alongside their share
--     of the delivery fee as on any other order;
--   * any discount the customer got is the platform's: the store charged its
--     full price regardless, so a store-funded coupon cannot apply.
--
-- Everything else is unchanged, and the order still balances. On a cash order
-- the driver collected the total from the customer, so the purchase and the
-- delivery share are simply what they keep of it; the rest (service fee,
-- delivery margin, campaign uplift, less any discount) is what they hand to
-- the platform. On a card or in-app wallet order the platform was paid, and
-- the driver's wallet shows the purchase plus the delivery share owed to them.

create or replace function public.finance_settle_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
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
  v_markup numeric := 0;
  v_is_cod boolean;
  v_holder text;
  -- The driver paid the store at the counter: no store in the app.
  v_bought_at_counter boolean;
begin
  -- Locks the order for the rest of the transaction, so two concurrent
  -- deliveries of the same order serialise here instead of both settling.
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  if v_order.settlement_status = 'settled' then
    return jsonb_build_object('status', 'already_settled', 'order_id', p_order_id);
  end if;
  if v_order.status <> 'delivered' then
    raise exception 'ORDER_NOT_DELIVERED';
  end if;

  select * into v_vendor from public.vendors where id = v_order.vendor_id;

  v_bought_at_counter := v_order.order_flow <> 'vendor'
                         and v_order.driver_id is not null;

  -- Who funded the discount, exactly as the reports decide it: a coupon scoped
  -- to a store is that store's own marketing spend.
  select
    case when (c.vendor_id is not null and c.funded_by = 'vendor') then coalesce(v_order.discount, 0) else 0 end,
    case when (c.vendor_id is null or c.funded_by = 'platform') then coalesce(v_order.discount, 0) else 0 end
  into v_vendor_discount, v_platform_discount
  from (select 1) x
  left join public.coupons c on c.id = v_order.coupon_id;

  v_vendor_discount := coalesce(v_vendor_discount, 0);
  v_platform_discount := coalesce(v_platform_discount, 0);

  -- The store charged the driver its full price, so nothing the customer was
  -- let off came out of the store.
  if v_order.order_flow <> 'vendor' then
    v_platform_discount := v_platform_discount + v_vendor_discount;
    v_vendor_discount := 0;
  end if;

  -- What the campaign added to the menu prices on this order.
  select round(coalesce(sum(
           (oi.unit_price - coalesce(oi.base_unit_price, oi.unit_price))
           * oi.quantity), 0), 2)
  into v_markup
  from public.order_items oi
  where oi.order_id = p_order_id;

  -- Only an order the store ran itself earns the platform a commission.
  if v_order.order_flow = 'vendor' then
    v_commission := public.order_commission(
      coalesce(v_vendor.billing_model, 'commission'),
      coalesce(v_vendor.commission_rate, 10),
      v_order.subtotal - v_markup - v_vendor_discount);
  end if;

  -- The store's own price for what was bought. For a store in the app this is
  -- what it is owed; for one that is not, it is what the driver paid it.
  v_vendor_net := round(
    v_order.subtotal - v_markup - v_vendor_discount - v_commission, 2);
  v_delivery_margin := round(
    coalesce(v_order.delivery_fee, 0) * (100 - v_share) / 100.0, 2);
  v_driver_earning := round(
    coalesce(v_order.delivery_fee, 0) * v_share / 100.0, 2);

  v_is_cod := v_order.payment_method = 'cod';

  update public.orders set settlement_status = 'processing' where id = p_order_id;

  -- --- Who is holding the customer's money ------------------------------
  -- Always exactly one party, and always the full order total. This is the
  -- liability that the earnings below are paid out of.
  if v_is_cod and v_order.order_type = 'pickup' then
    v_holder := 'vendor';
    perform public.finance_post(
      'vendor', v_order.vendor_id, 'cash_collection', v_order.total, 'debit',
      p_order_id, v_order.order_number,
      'Cash taken at the counter', '{}'::jsonb, v_key || 'cash');
  elsif v_is_cod and v_order.driver_id is not null then
    v_holder := 'driver';
    perform public.finance_post(
      'driver', v_order.driver_id, 'cash_collection', v_order.total, 'debit',
      p_order_id, v_order.order_number,
      'Cash collected from customer', '{}'::jsonb, v_key || 'cash');
  elsif not v_is_cod then
    -- Card or in-app wallet: the platform was paid directly and now owes the
    -- store and the driver their share of it.
    v_holder := 'platform';
    perform public.finance_post(
      'platform', null, 'online_collection', v_order.total, 'debit',
      p_order_id, v_order.order_number,
      'Paid online to the platform',
      jsonb_build_object('payment_method', v_order.payment_method),
      v_key || 'collection');
  end if;

  -- --- What each party earned -------------------------------------------
  if v_order.driver_id is not null and v_driver_earning > 0 then
    perform public.finance_post(
      'driver', v_order.driver_id, 'driver_earning', v_driver_earning, 'credit',
      p_order_id, v_order.order_number,
      'Delivery fee share', jsonb_build_object('share_percent', v_share),
      v_key || 'driver');
  end if;

  if v_bought_at_counter then
    -- Paid out of the driver's own pocket at the counter; the store is square.
    perform public.finance_post(
      'driver', v_order.driver_id, 'driver_store_purchase', v_vendor_net, 'credit',
      p_order_id, v_order.order_number, 'Paid the store for the order',
      jsonb_build_object(
        'vendor_id', v_order.vendor_id,
        'subtotal', v_order.subtotal,
        'campaign_markup', v_markup),
      v_key || 'store_purchase');
  else
    perform public.finance_post(
      'vendor', v_order.vendor_id, 'vendor_earning', v_vendor_net, 'credit',
      p_order_id, v_order.order_number, 'Order earnings',
      jsonb_build_object(
        'subtotal', v_order.subtotal,
        'campaign_markup', v_markup,
        'vendor_discount', v_vendor_discount,
        'commission', v_commission,
        'billing_model', coalesce(v_vendor.billing_model, 'commission')),
      v_key || 'vendor');
  end if;

  perform public.finance_post(
    'platform', null, 'platform_commission', v_commission, 'credit',
    p_order_id, v_order.order_number, 'Commission', '{}'::jsonb,
    v_key || 'commission');

  perform public.finance_post(
    'platform', null, 'platform_delivery_margin', v_delivery_margin, 'credit',
    p_order_id, v_order.order_number, 'Delivery margin', '{}'::jsonb,
    v_key || 'margin');

  perform public.finance_post(
    'platform', null, 'platform_service_fee', coalesce(v_order.service_fee, 0),
    'credit', p_order_id, v_order.order_number, 'Service fee', '{}'::jsonb,
    v_key || 'service_fee');

  -- The campaign uplift: charged to the customer, never owed to the store.
  perform public.finance_post(
    'platform', null, 'platform_markup', v_markup, 'credit',
    p_order_id, v_order.order_number, 'Campaign price uplift', '{}'::jsonb,
    v_key || 'markup');

  -- A platform-funded discount is money the platform never collected but the
  -- store is still paid for, so it lands on the platform as a cost.
  perform public.finance_post(
    'platform', null, 'platform_discount', v_platform_discount, 'debit',
    p_order_id, v_order.order_number, 'Platform-funded discount', '{}'::jsonb,
    v_key || 'discount');

  update public.orders set
    settlement_status = 'settled',
    settled_at = now(),
    cash_status = case
      when not v_is_cod then 'not_applicable'::public.cash_status
      else 'cash_collected'::public.cash_status end
  where id = p_order_id;

  return jsonb_build_object(
    'status', 'settled',
    'order_id', p_order_id,
    'vendor_net', case when v_bought_at_counter then 0 else v_vendor_net end,
    'store_purchase', case when v_bought_at_counter then v_vendor_net else 0 end,
    'driver_earning', v_driver_earning,
    'commission', v_commission,
    'delivery_margin', v_delivery_margin,
    'service_fee', coalesce(v_order.service_fee, 0),
    'platform_discount', v_platform_discount,
    'campaign_markup', v_markup,
    'money_held_by', v_holder
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- Reports follow the same rules
-- ---------------------------------------------------------------------------
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef(
    'public.admin_platform_report(timestamptz, timestamptz, numeric)'::regprocedure);
  if d like '%driver_store_purchases%' then
    return;
  end if;

  n := replace(d,
    '      o.payment_method,
',
    '      o.payment_method,
      o.order_flow,
      coalesce(o.markup_amount, 0) as markup,
');

  -- No store in the app: nothing it could have funded.
  n := replace(n,
    '      case when (c.vendor_id is not null and c.funded_by = ''vendor'') then o.discount else 0 end
        as vendor_discount,',
    '      case when o.order_flow = ''vendor''
                and (c.vendor_id is not null and c.funded_by = ''vendor'') then o.discount else 0 end
        as vendor_discount,');
  n := replace(n,
    '      case when (c.vendor_id is null or c.funded_by = ''platform'') then o.discount else 0 end
        as platform_discount',
    '      case when o.order_flow <> ''vendor''
                or (c.vendor_id is null or c.funded_by = ''platform'') then o.discount else 0 end
        as platform_discount');

  -- A store that is not in the app was paid at the counter by the driver.
  n := replace(n,
    '                                  subtotal - vendor_discount)), 0), 2) from d),
    ''cash_collected''',
    '                                  subtotal - vendor_discount)), 0), 2) from d
        where order_flow = ''vendor''),
    ''driver_store_purchases'', (select round(coalesce(sum(subtotal - markup), 0), 2)
        from d where order_flow <> ''vendor''),
    ''cash_collected''');

  if n not like '%driver_store_purchases%'
     or n not like '%as markup%'
     or n not like '%when o.order_flow = ''vendor''%'
     or n not like '%or (c.vendor_id is null%' then
    raise exception 'admin_platform_report anchors not found';
  end if;
  execute n;
end
$patch$;

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
      -- platform-wide one is not, and must not be taken off its payout. A
      -- store not in the app funds nothing: it was paid its full price.
      case when o.order_flow = 'vendor'
                and (c.vendor_id is not null and c.funded_by = 'vendor') then o.discount else 0 end
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
      -- Only the orders the store ran itself are owed to it and carry a
      -- commission; the rest the driver paid for at the counter.
      round(coalesce(sum(s.subtotal - s.vendor_discount)
        filter (where s.order_flow = 'vendor'), 0), 2) as payable
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
    case when t.billing_model = 'subscription' then 0 else t.commission_rate end,
    t.subscription_fee,
    public.order_commission(t.billing_model, t.commission_rate,
                            t.payable) as commission_fee,
    round(
      t.payable
      - public.order_commission(t.billing_model, t.commission_rate, t.payable),
      2) as net_payout
  from totals t
  order by t.gross desc;
end;
$$;

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
      case when o.order_flow = 'vendor'
                and (c.vendor_id is not null and c.funded_by = 'vendor') then o.discount else 0 end
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
      -- Owed to the store and commissioned: only what it ran itself.
      round(coalesce(sum(subtotal - vendor_discount)
        filter (where order_flow = 'vendor'), 0), 2) as payable,
      -- Already paid in cash at the counter by the driver.
      round(coalesce(sum(subtotal)
        filter (where order_flow <> 'vendor'), 0), 2) as paid_at_counter
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
      t.payable),
    'net_payout', round(
      t.payable
      - public.order_commission(
          coalesce(v_vendor.billing_model, 'commission'),
          coalesce(v_vendor.commission_rate, 10),
          t.payable),
      2),
    'paid_at_counter', t.paid_at_counter,
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
