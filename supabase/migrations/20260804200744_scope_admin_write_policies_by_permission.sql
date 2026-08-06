-- Hiding a button is courtesy; this is the part that actually stops anything.
--
-- These policies said `is_admin()`, so a member of staff whose role holds
-- nothing but `support.handle` could still write coupons, banners, service
-- areas and store categories straight through PostgREST. The management roles
-- only meant something for the RPCs until now.
--
-- Reads are untouched throughout: seeing the catalogue is not the risk.

drop policy if exists coupons_admin_all on public.coupons;
create policy coupons_admin_all on public.coupons
  for all to authenticated
  using (public.has_permission('promos.manage'))
  with check (public.has_permission('promos.manage'));

drop policy if exists banners_admin_all on public.banners;
create policy banners_admin_all on public.banners
  for all to authenticated
  using (public.has_permission('ads.manage'))
  with check (public.has_permission('ads.manage'));

drop policy if exists app_content_admin_all on public.app_content;
create policy app_content_admin_all on public.app_content
  for all to authenticated
  using (public.has_permission('content.manage'))
  with check (public.has_permission('content.manage'));

drop policy if exists app_links_admin_all on public.app_links;
create policy app_links_admin_all on public.app_links
  for all to authenticated
  using (public.has_permission('content.manage'))
  with check (public.has_permission('content.manage'));

drop policy if exists service_areas_admin_all on public.service_areas;
create policy service_areas_admin_all on public.service_areas
  for all to authenticated
  using (public.has_permission('content.manage'))
  with check (public.has_permission('content.manage'));

drop policy if exists vendor_categories_admin_all on public.vendor_categories;
create policy vendor_categories_admin_all on public.vendor_categories
  for all to authenticated
  using (public.has_permission('catalog.manage'))
  with check (public.has_permission('catalog.manage'));

drop policy if exists support_templates_admin_write on public.support_templates;
create policy support_templates_admin_write on public.support_templates
  for all to authenticated
  using (public.has_permission('support.handle'))
  with check (public.has_permission('support.handle'));

drop policy if exists support_threads_admin_update on public.support_threads;
create policy support_threads_admin_update on public.support_threads
  for update to authenticated
  using (public.has_permission('support.handle'))
  with check (public.has_permission('support.handle'));

-- `drivers` and `vendors` keep a broad admin write policy: their approval and
-- commercial columns are already guarded by the RPCs and the terms trigger,
-- and the rest of those rows (a driver's vehicle type, a store's address) is
-- ordinary operator upkeep rather than a privileged action.

-- Managing roles is itself a permission — otherwise a limited admin could
-- write themselves a new one and assign it.
drop policy if exists admin_roles_write on public.admin_roles;
create policy admin_roles_write on public.admin_roles
  for all to authenticated
  using (public.has_permission('staff.manage'))
  with check (public.has_permission('staff.manage'));
