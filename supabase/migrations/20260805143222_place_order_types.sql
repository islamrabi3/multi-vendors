-- place_order, for all three kinds of order.
--
-- Three things differ by type and everything else is shared:
--   delivery  — as before: store must be open, address must be in range.
--   pickup    — no delivery fee, no service-area check (the customer travels
--               to the store, not the other way round), and no driver stage.
--   scheduled — placed against a future slot, so the store being shut right
--               now is not a reason to refuse it; it is released to them
--               shortly before the slot.
create or replace function public.place_order(
  p_address_id uuid,
  p_payment_method payment_method,
  p_coupon_code text default null,
  p_notes text default null,
  p_order_type order_type default 'delivery',
  p_scheduled_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cart public.carts%rowtype;
  v_vendor public.vendors%rowtype;
  v_address public.addresses%rowtype;
  v_customer public.profiles%rowtype;
  v_item record;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_delivery_fee numeric := 0;
  v_coupon_id uuid;
  v_coupon record;
  v_order_id uuid;
  v_unit_price numeric;
  v_options_snapshot jsonb;
  v_options_delta numeric;
  v_is_pickup boolean := p_order_type = 'pickup';
  v_is_scheduled boolean := p_order_type = 'scheduled';
begin
  if public.is_blocked() then
    raise exception 'ACCOUNT_BLOCKED';
  end if;

  if v_is_scheduled then
    if p_scheduled_at is null then
      raise exception 'SCHEDULE_REQUIRED';
    end if;
    -- Far enough ahead that the store can actually make it, and not so far
    -- that a menu price from today is meaningless.
    if p_scheduled_at < now() + interval '45 minutes' then
      raise exception 'SCHEDULE_TOO_SOON';
    end if;
    if p_scheduled_at > now() + interval '7 days' then
      raise exception 'SCHEDULE_TOO_FAR';
    end if;
  end if;

  select * into v_cart from public.carts where user_id = auth.uid();
  if not found then
    raise exception 'CART_EMPTY';
  end if;
  if not exists (select 1 from public.cart_items where cart_id = v_cart.id) then
    raise exception 'CART_EMPTY';
  end if;

  select * into v_vendor from public.vendors
  where id = v_cart.vendor_id and is_active and approval_status = 'active';
  if not found then
    raise exception 'VENDOR_CLOSED';
  end if;
  -- A scheduled order is for later, so "closed right now" says nothing about
  -- whether it can be fulfilled.
  if not v_is_scheduled and not v_vendor.is_open then
    raise exception 'VENDOR_CLOSED';
  end if;

  select * into v_address from public.addresses
  where id = p_address_id and user_id = auth.uid();
  if not found then
    raise exception 'ADDRESS_NOT_FOUND';
  end if;

  -- Pickup travels the other way, so the delivery area does not apply.
  if not v_is_pickup
     and not public.is_within_service_area(v_address.lat, v_address.lng) then
    raise exception 'OUTSIDE_SERVICE_AREA';
  end if;

  select * into v_customer from public.profiles where id = auth.uid();

  for v_item in
    select ci.id, ci.quantity, ci.selected_options, p.id as product_id,
           p.name as product_name, p.price, p.is_available
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart.id
  loop
    if not v_item.is_available then
      raise exception 'PRODUCT_UNAVAILABLE:%', v_item.product_name;
    end if;

    select coalesce(sum(po.price_delta), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'option_id', po.id, 'name', po.name, 'price_delta', po.price_delta
           )), '[]'::jsonb)
    into v_options_delta, v_options_snapshot
    from jsonb_array_elements(v_item.selected_options) sel
    join public.product_options po on po.id = (sel ->> 'option_id')::uuid;

    v_unit_price := v_item.price + v_options_delta;
    v_subtotal := v_subtotal + v_unit_price * v_item.quantity;
  end loop;

  if v_subtotal < v_vendor.min_order_amount then
    raise exception 'MIN_ORDER_NOT_MET:%', v_vendor.min_order_amount;
  end if;

  -- Nothing to deliver, nothing to charge for delivering.
  v_delivery_fee := case when v_is_pickup then 0 else v_vendor.delivery_fee end;

  if p_coupon_code is not null and trim(p_coupon_code) <> '' then
    select * into v_coupon
    from public.compute_coupon_discount(
      p_coupon_code, v_vendor.id, v_subtotal, v_delivery_fee, auth.uid());
    v_coupon_id := v_coupon.o_coupon_id;
    v_discount := v_coupon.o_discount;
  end if;

  insert into public.orders (
    customer_id, vendor_id, delivery_address, delivery_lat, delivery_lng,
    subtotal, delivery_fee, discount, total,
    payment_method, payment_status, coupon_id, customer_notes, order_number,
    order_type, scheduled_at, released_at
  ) values (
    auth.uid(), v_vendor.id,
    jsonb_build_object(
      'label', v_address.label,
      'street', v_address.street,
      'building', v_address.building,
      'floor', v_address.floor,
      'apartment', v_address.apartment,
      'notes', v_address.notes,
      'customer_name', v_customer.full_name,
      'customer_phone', v_customer.phone
    ),
    v_address.lat, v_address.lng,
    v_subtotal, v_delivery_fee, v_discount,
    greatest(v_subtotal - v_discount + v_delivery_fee, 0),
    p_payment_method, 'unpaid', v_coupon_id, p_notes, '',
    p_order_type,
    case when v_is_scheduled then p_scheduled_at else null end,
    -- Held back from the store until close to its slot; everything else is
    -- theirs immediately.
    case when v_is_scheduled then null else now() end
  )
  returning id into v_order_id;

  if v_coupon_id is not null then
    insert into public.coupon_redemptions (coupon_id, user_id, order_id, discount)
    values (v_coupon_id, auth.uid(), v_order_id, v_discount);
  end if;

  for v_item in
    select ci.quantity, ci.selected_options, p.id as product_id,
           p.name as product_name, p.price
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart.id
  loop
    select coalesce(sum(po.price_delta), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'option_id', po.id, 'name', po.name, 'price_delta', po.price_delta
           )), '[]'::jsonb)
    into v_options_delta, v_options_snapshot
    from jsonb_array_elements(v_item.selected_options) sel
    join public.product_options po on po.id = (sel ->> 'option_id')::uuid;

    v_unit_price := v_item.price + v_options_delta;

    insert into public.order_items (
      order_id, product_id, product_name, unit_price, quantity,
      selected_options, line_total
    ) values (
      v_order_id, v_item.product_id, v_item.product_name, v_unit_price,
      v_item.quantity, v_options_snapshot, v_unit_price * v_item.quantity
    );
  end loop;

  delete from public.carts where id = v_cart.id;

  return v_order_id;
end;
$$;
