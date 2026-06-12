-- Row Level Security. Catalog data is public-read; everything personal is
-- owner-scoped. Order status writes only happen through security-definer RPCs,
-- so no UPDATE policies exist on orders for regular roles.

alter table public.profiles enable row level security;
alter table public.vendor_categories enable row level security;
alter table public.vendors enable row level security;
alter table public.product_categories enable row level security;
alter table public.products enable row level security;
alter table public.product_option_groups enable row level security;
alter table public.product_options enable row level security;
alter table public.addresses enable row level security;
alter table public.carts enable row level security;
alter table public.cart_items enable row level security;
alter table public.coupons enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.order_status_history enable row level security;
alter table public.drivers enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.favorites enable row level security;
alter table public.banners enable row level security;

-- profiles: own row only. Vendors/drivers see customer contact info via the
-- order's delivery_address snapshot instead.
create policy "profiles_select_own" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- Catalog: public read.
create policy "vendor_categories_read" on public.vendor_categories
  for select using (is_active);

create policy "vendors_read" on public.vendors
  for select using (is_active or owner_id = auth.uid());
create policy "vendors_insert_own" on public.vendors
  for insert with check (owner_id = auth.uid());
create policy "vendors_update_own" on public.vendors
  for update using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "product_categories_read" on public.product_categories
  for select using (true);
create policy "product_categories_write" on public.product_categories
  for all using (public.is_vendor_owner(vendor_id))
  with check (public.is_vendor_owner(vendor_id));

create policy "products_read" on public.products
  for select using (true);
create policy "products_write" on public.products
  for all using (public.is_vendor_owner(vendor_id))
  with check (public.is_vendor_owner(vendor_id));

create policy "option_groups_read" on public.product_option_groups
  for select using (true);
create policy "option_groups_write" on public.product_option_groups
  for all using (
    exists (select 1 from public.products p
            where p.id = product_id and public.is_vendor_owner(p.vendor_id)))
  with check (
    exists (select 1 from public.products p
            where p.id = product_id and public.is_vendor_owner(p.vendor_id)));

create policy "options_read" on public.product_options
  for select using (true);
create policy "options_write" on public.product_options
  for all using (
    exists (select 1 from public.product_option_groups g
            join public.products p on p.id = g.product_id
            where g.id = group_id and public.is_vendor_owner(p.vendor_id)))
  with check (
    exists (select 1 from public.product_option_groups g
            join public.products p on p.id = g.product_id
            where g.id = group_id and public.is_vendor_owner(p.vendor_id)));

-- Personal data: owner-scoped.
create policy "addresses_all_own" on public.addresses
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "carts_all_own" on public.carts
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "cart_items_all_own" on public.cart_items
  for all using (
    exists (select 1 from public.carts c
            where c.id = cart_id and c.user_id = auth.uid()))
  with check (
    exists (select 1 from public.carts c
            where c.id = cart_id and c.user_id = auth.uid()));

create policy "coupons_read_active" on public.coupons
  for select using (is_active);

-- Orders: customer, vendor owner, assigned driver — plus the unassigned
-- ready_for_pickup pool for online drivers.
create policy "orders_read" on public.orders
  for select using (
    customer_id = auth.uid()
    or driver_id = auth.uid()
    or public.is_vendor_owner(vendor_id)
    or (status = 'ready_for_pickup' and driver_id is null and public.is_online_driver())
  );

create policy "order_items_read" on public.order_items
  for select using (public.can_view_order(order_id));

create policy "order_status_history_read" on public.order_status_history
  for select using (public.can_view_order(order_id));

create policy "drivers_select_own" on public.drivers
  for select using (id = auth.uid());
create policy "drivers_update_own" on public.drivers
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy "payments_read_own" on public.payments
  for select using (
    exists (select 1 from public.orders o
            where o.id = order_id and o.customer_id = auth.uid()));

create policy "reviews_read" on public.reviews
  for select using (true);
create policy "reviews_insert_own_delivered" on public.reviews
  for insert with check (
    customer_id = auth.uid()
    and exists (select 1 from public.orders o
                where o.id = order_id
                  and o.customer_id = auth.uid()
                  and o.status = 'delivered'));

create policy "favorites_all_own" on public.favorites
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "banners_read" on public.banners
  for select using (is_active);
