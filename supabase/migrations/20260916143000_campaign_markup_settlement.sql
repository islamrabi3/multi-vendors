-- The store is paid on its own price; the campaign's uplift is the
-- platform's. Commission is charged on the store's price too, so a campaign
-- never quietly raises what the store pays in commission.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.finance_settle_order(uuid)'::regprocedure);
  if d like '%platform_markup%' then
    return;
  end if;

  n := replace(d,
    '  v_is_cod boolean;',
    '  v_markup numeric := 0;
  v_is_cod boolean;');

  n := replace(n,
    '  v_commission := public.order_commission(',
    '  -- What the campaign added to the menu prices on this order.
  select round(coalesce(sum(
           (oi.unit_price - coalesce(oi.base_unit_price, oi.unit_price))
           * oi.quantity), 0), 2)
  into v_markup
  from public.order_items oi
  where oi.order_id = p_order_id;

  v_commission := public.order_commission(');

  n := replace(n,
    '    v_order.subtotal - v_vendor_discount);',
    '    v_order.subtotal - v_markup - v_vendor_discount);');

  n := replace(n,
    '  v_vendor_net := round(v_order.subtotal - v_vendor_discount - v_commission, 2);',
    '  v_vendor_net := round(
    v_order.subtotal - v_markup - v_vendor_discount - v_commission, 2);');

  n := replace(n,
    '      ''subtotal'', v_order.subtotal,',
    '      ''subtotal'', v_order.subtotal,
      ''campaign_markup'', v_markup,');

  n := replace(n,
    '  -- A platform-funded discount is money the platform never collected but the',
    '  -- The campaign uplift: charged to the customer, never owed to the store.
  perform public.finance_post(
    ''platform'', null, ''platform_markup'', v_markup, ''credit'',
    p_order_id, v_order.order_number, ''Campaign price uplift'', ''{}''::jsonb,
    v_key || ''markup'');

  -- A platform-funded discount is money the platform never collected but the');

  n := replace(n,
    '    ''platform_discount'', v_platform_discount,',
    '    ''platform_discount'', v_platform_discount,
    ''campaign_markup'', v_markup,');

  if n = d then
    raise exception 'finance_settle_order anchors not found';
  end if;
  execute n;
end
$patch$;

-- The store's own reports show what the store sold, not what the campaign
-- added on top of it.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.vendor_settlement(uuid, timestamptz, timestamptz)'::regprocedure);
  n := replace(d,
    '      o.subtotal,
      o.delivery_fee,',
    '      o.subtotal - coalesce(o.markup_amount, 0) as subtotal,
      o.delivery_fee,');
  if n = d then
    raise exception 'vendor_settlement anchor not found';
  end if;
  execute n;
end
$patch$;

do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.admin_vendor_sales_report(timestamptz, timestamptz)'::regprocedure);
  n := replace(d,
    '      o.id as order_id,
      o.subtotal,',
    '      o.id as order_id,
      o.subtotal - coalesce(o.markup_amount, 0) as subtotal,');
  if n = d then
    raise exception 'admin_vendor_sales_report anchor not found';
  end if;
  execute n;
end
$patch$;
