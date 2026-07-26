-- Admin policies for vendor_categories.
drop policy if exists "vendor_categories_read" on public.vendor_categories;
create policy "vendor_categories_read" on public.vendor_categories
  for select using (is_active or public.is_admin());

drop policy if exists "vendor_categories_admin_all" on public.vendor_categories;
create policy "vendor_categories_admin_all" on public.vendor_categories
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
