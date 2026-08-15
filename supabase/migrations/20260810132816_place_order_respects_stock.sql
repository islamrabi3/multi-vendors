-- Selling the last box has to stop the next customer buying it.
--
-- `place_order` checked `is_available` only, which is the right question for a
-- kitchen and the wrong one for a shelf. It now also checks and decrements
-- `stock_quantity` for tracked products, inside the same transaction that
-- creates the order -- so two customers racing for the last unit cannot both
-- get it, and a failure anywhere rolls the stock back with the order.
--
-- Only the guard and the decrement are new; the rest is the 20260806171955
-- body unchanged.

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
  if not v_is_scheduled and not public.vendor_is_open_now(v_vendor.id) then
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
           p.name as product_name, p.price, p.is_available,
           p.track_stock, p.stock_quantity
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart.id
    -- Locking the product row is what makes the stock check safe: two
    -- customers racing for the last unit serialise here.
    for update of p
  loop
    if not v_item.is_available then
      raise exception 'PRODUCT_UNAVAILABLE:%', v_item.product_name;
    end if;
    if v_item.track_stock and v_item.stock_quantity < v_item.quantity then
      -- Named so the app can tell the customer which item, and how many are
      -- actually left, rather than a bare failure.
      raise exception 'INSUFFICIENT_STOCK:%:%',
        v_item.product_name, v_item.stock_quantity;
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
           p.name as product_name, p.price, p.track_stock, p.stock_quantity
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

    -- Stock leaves the shelf when the order is placed, not when it is
    -- delivered: the customer has committed to it and nobody else can have it.
    if v_item.track_stock then
      update public.products
      set stock_quantity = stock_quantity - v_item.quantity
      where id = v_item.product_id;

      insert into public.stock_movements (
        product_id, vendor_id, order_id, delta, quantity_after, reason, created_by
      ) values (
        v_item.product_id, v_vendor.id, v_order_id, -v_item.quantity,
        v_item.stock_quantity - v_item.quantity, 'sale', auth.uid()
      );
    end if;
  end loop;

  delete from public.carts where id = v_cart.id;

  return v_order_id;
end;
$$;

-- An order that never happens puts its stock back.
--
-- Without this a shop would bleed inventory to every rejected order and have
-- to notice and correct it by hand -- exactly the kind of quiet drift that
-- makes a stock number untrustworthy.
create or replace function public.restore_stock_on_cancel()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_item record;
begin
  if new.status not in ('cancelled', 'rejected')
     or old.status in ('cancelled', 'rejected') then
    return null;
  end if;

  for v_item in
    select oi.product_id, oi.quantity, p.track_stock, p.stock_quantity, p.vendor_id
    from public.order_items oi
    join public.products p on p.id = oi.product_id
    where oi.order_id = new.id and p.track_stock
  loop
    update public.products
    set stock_quantity = stock_quantity + v_item.quantity
    where id = v_item.product_id;

    insert into public.stock_movements (
      product_id, vendor_id, order_id, delta, quantity_after, reason
    ) values (
      v_item.product_id, v_item.vendor_id, new.id, v_item.quantity,
      v_item.stock_quantity + v_item.quantity, 'order_cancelled'
    );
  end loop;
  return null;
end;
$$;

drop trigger if exists orders_restore_stock on public.orders;
create trigger orders_restore_stock
  after update of status on public.orders
  for each row execute function public.restore_stock_on_cancel();
