-- Opening hours actually close the store.
--
-- `vendor_schedules` has existed since the competitive-features migration but
-- nothing read it: `vendors.is_open` was a manual switch, so a store that
-- forgot to flip it at 1am kept taking orders all night and a customer saw
-- "open" against a shut kitchen.
--
-- From here `is_open` means "the owner has not shut us early"; whether the
-- store is *actually* taking orders is `is_open` AND inside today's window.
-- A store with no schedule row for today is unrestricted, so nothing changes
-- for the ones that never configured hours.

-- Times are wall-clock strings in the market's timezone, not the server's.
create or replace function public.platform_timezone()
returns text
language sql
stable
security definer
set search_path = public, private
as $$
  select coalesce(
    (select value from private.app_config where key = 'timezone'),
    'Africa/Cairo'
  );
$$;

grant execute on function public.platform_timezone() to authenticated, anon;

-- Whether `p_time` (HH:MM) falls inside the window, including windows that
-- cross midnight — a 18:00–02:00 shift is one continuous opening, not a
-- closed store for eight hours of it.
create or replace function public.time_within_window(
  p_time time,
  p_open time,
  p_close time
)
returns boolean
language sql
immutable
as $$
  select case
    when p_open = p_close then true              -- 24 hours
    when p_close > p_open then p_time >= p_open and p_time < p_close
    else p_time >= p_open or p_time < p_close    -- spans midnight
  end;
$$;

grant execute on function public.time_within_window(time, time, time) to authenticated, anon;

create or replace function public.vendor_is_open_now(p_vendor_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_open boolean;
  v_local timestamp;
  v_row public.vendor_schedules%rowtype;
begin
  select is_open into v_open from public.vendors where id = p_vendor_id;
  if v_open is null or not v_open then
    return false;
  end if;

  v_local := now() at time zone public.platform_timezone();

  select * into v_row
  from public.vendor_schedules
  where vendor_id = p_vendor_id
    and day_of_week = extract(dow from v_local)::int;

  -- No hours configured for today: the manual switch is the whole answer.
  if not found then
    return true;
  end if;
  if v_row.is_closed then
    return false;
  end if;

  return public.time_within_window(
    v_local::time,
    v_row.open_time::time,
    v_row.close_time::time
  );
end;
$$;

grant execute on function public.vendor_is_open_now(uuid) to authenticated, anon;

create index if not exists vendor_schedules_vendor_day_idx
  on public.vendor_schedules (vendor_id, day_of_week);

-- place_order now refuses an order placed after closing time. Only the open
-- guard changed; the rest is the 20260805143222 body unchanged.
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

-- The store list ranks open stores first. That ordering was on the manual
-- switch alone, so an out-of-hours store still led the page.
alter table public.vendor_schedules replica identity full;

-- Realtime: a schedule edit should reach a customer sitting on the store page.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'vendor_schedules'
  ) then
    alter publication supabase_realtime add table public.vendor_schedules;
  end if;
end $$;
