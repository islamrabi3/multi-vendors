-- Security-definer helpers and RPCs. These are the only write paths for
-- order creation and status transitions; pricing is always computed server-side.

create or replace function public.is_vendor_owner(p_vendor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.vendors
    where id = p_vendor_id and owner_id = auth.uid()
  );
$$;

create or replace function public.is_online_driver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.drivers
    where id = auth.uid() and is_online
  );
$$;

create or replace function public.can_view_order(p_order_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.orders o
    where o.id = p_order_id
      and (
        o.customer_id = auth.uid()
        or o.driver_id = auth.uid()
        or public.is_vendor_owner(o.vendor_id)
        or (o.status = 'ready_for_pickup'
            and o.driver_id is null
            and public.is_online_driver())
      )
  );
$$;

-- Shared coupon math: returns the discount for a (code, vendor, subtotal)
-- combination, or raises if the coupon is invalid.
create or replace function public.compute_coupon_discount(
  p_code text,
  p_vendor_id uuid,
  p_subtotal numeric,
  out o_coupon_id uuid,
  out o_discount numeric
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_coupon public.coupons%rowtype;
begin
  select * into v_coupon
  from public.coupons
  where code = upper(trim(p_code))
    and is_active
    and (expires_at is null or expires_at > now())
    and (vendor_id is null or vendor_id = p_vendor_id)
    and (usage_limit is null or used_count < usage_limit);

  if not found then
    raise exception 'COUPON_INVALID';
  end if;

  if p_subtotal < v_coupon.min_order_amount then
    raise exception 'COUPON_MIN_ORDER:%', v_coupon.min_order_amount;
  end if;

  o_coupon_id := v_coupon.id;
  if v_coupon.discount_type = 'percentage' then
    o_discount := round(p_subtotal * v_coupon.value / 100, 2);
    if v_coupon.max_discount is not null then
      o_discount := least(o_discount, v_coupon.max_discount);
    end if;
  else
    o_discount := least(v_coupon.value, p_subtotal);
  end if;
end;
$$;

-- Checkout preview: lets the client show the discount before placing the order.
create or replace function public.validate_coupon(
  p_code text,
  p_vendor_id uuid,
  p_subtotal numeric
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_coupon_id uuid;
  v_discount numeric;
begin
  select o_coupon_id, o_discount
  into v_coupon_id, v_discount
  from public.compute_coupon_discount(p_code, p_vendor_id, p_subtotal);
  return v_discount;
end;
$$;

-- Atomically turn the caller's cart into an order. Prices, option deltas,
-- coupon discount, and delivery fee are all resolved server-side.
create or replace function public.place_order(
  p_address_id uuid,
  p_payment_method public.payment_method,
  p_coupon_code text default null,
  p_notes text default null
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
  v_coupon_id uuid;
  v_order_id uuid;
  v_unit_price numeric;
  v_options_snapshot jsonb;
  v_options_delta numeric;
begin
  select * into v_cart from public.carts where user_id = auth.uid();
  if not found then
    raise exception 'CART_EMPTY';
  end if;
  if not exists (select 1 from public.cart_items where cart_id = v_cart.id) then
    raise exception 'CART_EMPTY';
  end if;

  select * into v_vendor from public.vendors
  where id = v_cart.vendor_id and is_active;
  if not found or not v_vendor.is_open then
    raise exception 'VENDOR_CLOSED';
  end if;

  select * into v_address from public.addresses
  where id = p_address_id and user_id = auth.uid();
  if not found then
    raise exception 'ADDRESS_NOT_FOUND';
  end if;

  select * into v_customer from public.profiles where id = auth.uid();

  -- Server-side subtotal: product price + selected option deltas, per item.
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

  if p_coupon_code is not null and trim(p_coupon_code) <> '' then
    select o_coupon_id, o_discount into v_coupon_id, v_discount
    from public.compute_coupon_discount(p_coupon_code, v_vendor.id, v_subtotal);
    update public.coupons set used_count = used_count + 1 where id = v_coupon_id;
  end if;

  insert into public.orders (
    customer_id, vendor_id, delivery_address, delivery_lat, delivery_lng,
    subtotal, delivery_fee, discount, total,
    payment_method, payment_status, coupon_id, customer_notes, order_number
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
    v_subtotal, v_vendor.delivery_fee, v_discount,
    v_subtotal - v_discount + v_vendor.delivery_fee,
    p_payment_method, 'unpaid', v_coupon_id, p_notes, ''
  )
  returning id into v_order_id;

  -- Snapshot items with server-resolved names and prices.
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

-- Driver claims an order from the pool. Race-safe: first update wins.
create or replace function public.claim_delivery(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed boolean;
begin
  if not public.is_online_driver() then
    raise exception 'NOT_AN_ONLINE_DRIVER';
  end if;

  update public.orders
  set driver_id = auth.uid(),
      status = 'out_for_delivery',
      picked_up_at = now()
  where id = p_order_id
    and driver_id is null
    and status = 'ready_for_pickup';

  v_claimed := found;
  return v_claimed;
end;
$$;

-- Role-aware status transitions. Anything not in the matrix is rejected.
create or replace function public.update_order_status(
  p_order_id uuid,
  p_new_status public.order_status,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_is_customer boolean;
  v_is_vendor boolean;
  v_is_driver boolean;
  v_allowed boolean := false;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  v_is_customer := v_order.customer_id = auth.uid();
  v_is_vendor := public.is_vendor_owner(v_order.vendor_id);
  v_is_driver := v_order.driver_id = auth.uid();

  if v_is_vendor then
    v_allowed := (v_order.status = 'pending' and p_new_status in ('accepted', 'rejected'))
              or (v_order.status = 'accepted' and p_new_status = 'preparing')
              or (v_order.status = 'preparing' and p_new_status = 'ready_for_pickup');
  end if;

  if not v_allowed and v_is_driver then
    v_allowed := v_order.status = 'out_for_delivery' and p_new_status = 'delivered';
  end if;

  if not v_allowed and v_is_customer then
    v_allowed := v_order.status = 'pending' and p_new_status = 'cancelled';
  end if;

  if not v_allowed then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> %', v_order.status, p_new_status;
  end if;

  update public.orders
  set status = p_new_status,
      rejection_reason = case when p_new_status = 'rejected' then p_reason
                              else rejection_reason end,
      accepted_at = case when p_new_status = 'accepted' then now() else accepted_at end,
      ready_at = case when p_new_status = 'ready_for_pickup' then now() else ready_at end,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      cancelled_at = case when p_new_status in ('cancelled', 'rejected') then now()
                          else cancelled_at end,
      -- COD is collected on handover.
      payment_status = case
        when p_new_status = 'delivered' and payment_method = 'cod' then 'paid'::public.payment_status
        else payment_status end
  where id = p_order_id;
end;
$$;
