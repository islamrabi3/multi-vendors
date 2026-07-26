-- Admin (platform ops) role: vendor approval, cross-tenant order monitoring &
-- intervention, and coupon/promo management. Builds on the is_admin() helper
-- introduced in the offers migration.

-- ---------------------------------------------------------------------------
-- Vendor approval lifecycle
-- ---------------------------------------------------------------------------
-- pending  : just onboarded, invisible to customers until an admin approves
-- active   : approved, live in the marketplace (subject to is_open)
-- suspended: blocked by an admin, hidden from customers
alter table public.vendors
  add column if not exists approval_status text not null default 'pending'
    check (approval_status in ('pending', 'active', 'suspended'));

-- Existing stores predate approval — treat them as already approved so the
-- customer marketplace keeps working unchanged.
update public.vendors set approval_status = 'active'
  where approval_status = 'pending';

-- Customers only ever see approved stores; owners always see their own row;
-- admins see everything.
drop policy if exists "vendors_read" on public.vendors;
create policy "vendors_read" on public.vendors
  for select using (
    (is_active and approval_status = 'active')
    or owner_id = auth.uid()
    or public.is_admin()
  );

-- ---------------------------------------------------------------------------
-- Admin table access (RLS). Reads/writes are all gated by is_admin().
-- ---------------------------------------------------------------------------
drop policy if exists "vendors_admin_all" on public.vendors;
create policy "vendors_admin_all" on public.vendors
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "orders_admin_read" on public.orders;
create policy "orders_admin_read" on public.orders
  for select to authenticated using (public.is_admin());

drop policy if exists "coupons_admin_all" on public.coupons;
create policy "coupons_admin_all" on public.coupons
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Owner contact (approval detail) and online drivers (order intervention).
drop policy if exists "profiles_admin_read" on public.profiles;
create policy "profiles_admin_read" on public.profiles
  for select to authenticated using (public.is_admin());

drop policy if exists "drivers_admin_read" on public.drivers;
create policy "drivers_admin_read" on public.drivers
  for select to authenticated using (public.is_admin());

-- Let admins read order items / status history (used by the intervention view).
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
        or public.is_admin()
        or (o.status = 'ready_for_pickup'
            and o.driver_id is null
            and public.is_online_driver())
      )
  );
$$;

-- ---------------------------------------------------------------------------
-- place_order: never let customers order from a store that is not approved.
-- ---------------------------------------------------------------------------
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
  where id = v_cart.vendor_id and is_active and approval_status = 'active';
  if not found or not v_vendor.is_open then
    raise exception 'VENDOR_CLOSED';
  end if;

  select * into v_address from public.addresses
  where id = p_address_id and user_id = auth.uid();
  if not found then
    raise exception 'ADDRESS_NOT_FOUND';
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

-- ---------------------------------------------------------------------------
-- Admin RPCs
-- ---------------------------------------------------------------------------

-- Approve / suspend / reactivate a store. Suspended stores also lose their
-- customer-facing visibility (is_active = false).
create or replace function public.admin_set_vendor_status(
  p_vendor_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'NOT_ADMIN';
  end if;
  if p_status not in ('pending', 'active', 'suspended') then
    raise exception 'INVALID_STATUS:%', p_status;
  end if;

  update public.vendors
  set approval_status = p_status,
      is_active = (p_status <> 'suspended'),
      updated_at = now()
  where id = p_vendor_id;
end;
$$;

-- Manually attach a driver to a stuck order (dispatch intervention).
create or replace function public.admin_assign_driver(
  p_order_id uuid,
  p_driver_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'NOT_ADMIN';
  end if;

  -- Dispatch intervention: attaching a driver to a stuck order also pushes it
  -- out for delivery so it lands in the driver's Active tab immediately.
  update public.orders
  set driver_id = p_driver_id,
      status = case when status in ('preparing', 'ready_for_pickup')
                    then 'out_for_delivery'::public.order_status
                    else status end,
      picked_up_at = case when status in ('preparing', 'ready_for_pickup')
                          then now() else picked_up_at end,
      updated_at = now()
  where id = p_order_id;
end;
$$;

-- Live platform snapshot for the control-room dashboard.
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
        and created_at >= date_trunc('day', now())), 0),
    'orders_today', (
      select count(*) from public.orders
      where status not in ('cancelled', 'rejected')
        and created_at >= date_trunc('day', now())),
    'vendors_active', (
      select count(*) from public.vendors where approval_status = 'active'),
    'vendors_open', (
      select count(*) from public.vendors
      where approval_status = 'active' and is_open),
    'vendors_pending', (
      select count(*) from public.vendors where approval_status = 'pending'),
    'drivers_online', (
      select count(*) from public.drivers where is_online),
    'orders_attention', (
      select count(*) from public.orders
      where status in ('pending', 'accepted', 'preparing', 'ready_for_pickup')
        and created_at < now() - interval '30 minutes')
  ) else jsonb_build_object() end;
$$;

-- Role-aware status transitions, now with an admin escape hatch: admins may
-- cancel any non-terminal order (customer refund / dispute resolution).
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
  v_is_admin boolean;
  v_allowed boolean := false;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  v_is_customer := v_order.customer_id = auth.uid();
  v_is_vendor := public.is_vendor_owner(v_order.vendor_id);
  v_is_driver := v_order.driver_id = auth.uid();
  v_is_admin := public.is_admin();

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

  if not v_allowed and v_is_admin then
    v_allowed := v_order.status not in ('delivered', 'cancelled', 'rejected')
             and p_new_status = 'cancelled';
  end if;

  if not v_allowed then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> %', v_order.status, p_new_status;
  end if;

  update public.orders
  set status = p_new_status,
      rejection_reason = case
        when p_new_status in ('rejected', 'cancelled') and p_reason is not null
          then p_reason else rejection_reason end,
      accepted_at = case when p_new_status = 'accepted' then now() else accepted_at end,
      ready_at = case when p_new_status = 'ready_for_pickup' then now() else ready_at end,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      cancelled_at = case when p_new_status in ('cancelled', 'rejected') then now()
                          else cancelled_at end,
      payment_status = case
        when p_new_status = 'delivered' and payment_method = 'cod' then 'paid'::public.payment_status
        else payment_status end
  where id = p_order_id;
end;
$$;
