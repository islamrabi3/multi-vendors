-- Stop FOR ALL write policies from doubling as second SELECT policies.
--
-- `for all` covers SELECT too, so every table with an `X_write ... for all`
-- beside an `X_read ... for select` evaluated two permissive policies on every
-- read. That is 57 of the linter's remaining warnings and one cause of slow
-- catalogue queries: reading a product ran the ownership subquery against
-- vendors for every row, for every visitor, including anonymous ones who can
-- never satisfy it.
--
-- Splitting each `for all` into insert/update/delete leaves writes identical
-- and drops the read to a single policy.
--
-- The catch, and the reason this is not a mechanical rewrite: four read
-- policies were narrower than the `for all` sitting next to them, and were
-- relying on it for the admin's read. Those are widened first, so no console
-- screen loses rows.

-- ---------------------------------------------------------------------------
-- 1. Widen the four reads that were leaning on the write policy.
-- ---------------------------------------------------------------------------

-- The ad manager lists ads that are scheduled, paused or finished. `is_active`
-- alone would show it only what customers see.
drop policy if exists banners_read on public.banners;
create policy banners_read on public.banners
  for select
  using (is_active or public.is_admin());

-- Same for the promos screen: an expired or paused code still has to be
-- editable and reportable.
drop policy if exists coupons_read_active on public.coupons;
create policy coupons_read_active on public.coupons
  for select
  using (is_active or public.is_admin());

-- Support staff answer these; the customer only ever sees their own.
drop policy if exists "Users can view their own reports" on public.customer_reports;
create policy customer_reports_read on public.customer_reports
  for select
  using ((select auth.uid()) = user_id or public.is_admin());

-- A retired template must stay visible to whoever retired it.
drop policy if exists support_templates_read on public.support_templates;
create policy support_templates_read on public.support_templates
  for select to authenticated
  using (is_active or public.has_permission('support.handle'));

-- ---------------------------------------------------------------------------
-- 2. Split each `for all` into the three write commands.
--    Expressions are carried over verbatim; only the command list changes.
--    Where the original had no `with check`, Postgres was defaulting it to
--    `using`, so that is written out explicitly here.
-- ---------------------------------------------------------------------------

drop policy if exists admin_roles_write on public.admin_roles;
create policy admin_roles_insert on public.admin_roles
  for insert to authenticated with check (public.has_permission('staff.manage'));
create policy admin_roles_update on public.admin_roles
  for update to authenticated using (public.has_permission('staff.manage'))
  with check (public.has_permission('staff.manage'));
create policy admin_roles_delete on public.admin_roles
  for delete to authenticated using (public.has_permission('staff.manage'));

drop policy if exists app_content_admin_all on public.app_content;
create policy app_content_insert on public.app_content
  for insert to authenticated with check (public.has_permission('content.manage'));
create policy app_content_update on public.app_content
  for update to authenticated using (public.has_permission('content.manage'))
  with check (public.has_permission('content.manage'));
create policy app_content_delete on public.app_content
  for delete to authenticated using (public.has_permission('content.manage'));

drop policy if exists app_links_admin_all on public.app_links;
create policy app_links_insert on public.app_links
  for insert to authenticated with check (public.has_permission('content.manage'));
create policy app_links_update on public.app_links
  for update to authenticated using (public.has_permission('content.manage'))
  with check (public.has_permission('content.manage'));
create policy app_links_delete on public.app_links
  for delete to authenticated using (public.has_permission('content.manage'));

drop policy if exists banners_admin_all on public.banners;
create policy banners_insert on public.banners
  for insert to authenticated with check (public.has_permission('ads.manage'));
create policy banners_update on public.banners
  for update to authenticated using (public.has_permission('ads.manage'))
  with check (public.has_permission('ads.manage'));
create policy banners_delete on public.banners
  for delete to authenticated using (public.has_permission('ads.manage'));

drop policy if exists coupon_redemptions_admin on public.coupon_redemptions;
create policy coupon_redemptions_insert on public.coupon_redemptions
  for insert to authenticated with check (public.is_admin());
create policy coupon_redemptions_update on public.coupon_redemptions
  for update to authenticated using (public.is_admin())
  with check (public.is_admin());
create policy coupon_redemptions_delete on public.coupon_redemptions
  for delete to authenticated using (public.is_admin());

drop policy if exists coupons_admin_all on public.coupons;
create policy coupons_insert on public.coupons
  for insert to authenticated with check (public.has_permission('promos.manage'));
create policy coupons_update on public.coupons
  for update to authenticated using (public.has_permission('promos.manage'))
  with check (public.has_permission('promos.manage'));
create policy coupons_delete on public.coupons
  for delete to authenticated using (public.has_permission('promos.manage'));

drop policy if exists "Admins can manage all reports" on public.customer_reports;
create policy customer_reports_update on public.customer_reports
  for update to authenticated using (public.is_admin())
  with check (public.is_admin());
create policy customer_reports_delete on public.customer_reports
  for delete to authenticated using (public.is_admin());
-- No admin insert: reports are filed by the customer, under the existing
-- insert policy. An admin-authored report would misattribute it.

-- Drivers and vendors already had an owner-update policy. Adding an admin one
-- beside it would trade a duplicate SELECT for a duplicate UPDATE, so the two
-- are merged instead. A driver still cannot promote themselves: the columns
-- that matter are locked by trigger, not by this policy.
drop policy if exists drivers_admin_all on public.drivers;
drop policy if exists drivers_update_own on public.drivers;
create policy drivers_insert on public.drivers
  for insert to authenticated with check (public.is_admin());
create policy drivers_update on public.drivers
  for update
  using (id = (select auth.uid()) or public.is_admin())
  with check (id = (select auth.uid()) or public.is_admin());
create policy drivers_delete on public.drivers
  for delete to authenticated using (public.is_admin());

drop policy if exists campaigns_write on public.notification_campaigns;
create policy campaigns_insert on public.notification_campaigns
  for insert to authenticated
  with check (public.has_permission('notifications.send'));
create policy campaigns_update on public.notification_campaigns
  for update to authenticated using (public.has_permission('notifications.send'))
  with check (public.has_permission('notifications.send'));
create policy campaigns_delete on public.notification_campaigns
  for delete to authenticated using (public.has_permission('notifications.send'));

drop policy if exists product_categories_write on public.product_categories;
create policy product_categories_insert on public.product_categories
  for insert with check (public.is_vendor_owner(vendor_id));
create policy product_categories_update on public.product_categories
  for update using (public.is_vendor_owner(vendor_id))
  with check (public.is_vendor_owner(vendor_id));
create policy product_categories_delete on public.product_categories
  for delete using (public.is_vendor_owner(vendor_id));

drop policy if exists option_groups_write on public.product_option_groups;
create policy option_groups_insert on public.product_option_groups
  for insert with check (exists (
    select 1 from public.products p
     where p.id = product_id and public.is_vendor_owner(p.vendor_id)));
create policy option_groups_update on public.product_option_groups
  for update using (exists (
    select 1 from public.products p
     where p.id = product_id and public.is_vendor_owner(p.vendor_id)))
  with check (exists (
    select 1 from public.products p
     where p.id = product_id and public.is_vendor_owner(p.vendor_id)));
create policy option_groups_delete on public.product_option_groups
  for delete using (exists (
    select 1 from public.products p
     where p.id = product_id and public.is_vendor_owner(p.vendor_id)));

drop policy if exists options_write on public.product_options;
create policy options_insert on public.product_options
  for insert with check (exists (
    select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
     where g.id = group_id and public.is_vendor_owner(p.vendor_id)));
create policy options_update on public.product_options
  for update using (exists (
    select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
     where g.id = group_id and public.is_vendor_owner(p.vendor_id)))
  with check (exists (
    select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
     where g.id = group_id and public.is_vendor_owner(p.vendor_id)));
create policy options_delete on public.product_options
  for delete using (exists (
    select 1 from public.product_option_groups g
      join public.products p on p.id = g.product_id
     where g.id = group_id and public.is_vendor_owner(p.vendor_id)));

drop policy if exists products_write on public.products;
create policy products_insert on public.products
  for insert with check (public.is_vendor_owner(vendor_id));
create policy products_update on public.products
  for update using (public.is_vendor_owner(vendor_id))
  with check (public.is_vendor_owner(vendor_id));
create policy products_delete on public.products
  for delete using (public.is_vendor_owner(vendor_id));

drop policy if exists service_areas_admin_all on public.service_areas;
create policy service_areas_insert on public.service_areas
  for insert to authenticated with check (public.has_permission('content.manage'));
create policy service_areas_update on public.service_areas
  for update to authenticated using (public.has_permission('content.manage'))
  with check (public.has_permission('content.manage'));
create policy service_areas_delete on public.service_areas
  for delete to authenticated using (public.has_permission('content.manage'));

drop policy if exists support_templates_admin_write on public.support_templates;
create policy support_templates_insert on public.support_templates
  for insert to authenticated with check (public.has_permission('support.handle'));
create policy support_templates_update on public.support_templates
  for update to authenticated using (public.has_permission('support.handle'))
  with check (public.has_permission('support.handle'));
create policy support_templates_delete on public.support_templates
  for delete to authenticated using (public.has_permission('support.handle'));

drop policy if exists vendor_categories_admin_all on public.vendor_categories;
create policy vendor_categories_insert on public.vendor_categories
  for insert to authenticated with check (public.has_permission('catalog.manage'));
create policy vendor_categories_update on public.vendor_categories
  for update to authenticated using (public.has_permission('catalog.manage'))
  with check (public.has_permission('catalog.manage'));
create policy vendor_categories_delete on public.vendor_categories
  for delete to authenticated using (public.has_permission('catalog.manage'));

drop policy if exists "Vendors can manage their schedule" on public.vendor_schedules;
create policy vendor_schedules_insert on public.vendor_schedules
  for insert with check (exists (
    select 1 from public.vendors v
     where v.id = vendor_id and v.owner_id = (select auth.uid())));
create policy vendor_schedules_update on public.vendor_schedules
  for update using (exists (
    select 1 from public.vendors v
     where v.id = vendor_id and v.owner_id = (select auth.uid())))
  with check (exists (
    select 1 from public.vendors v
     where v.id = vendor_id and v.owner_id = (select auth.uid())));
create policy vendor_schedules_delete on public.vendor_schedules
  for delete using (exists (
    select 1 from public.vendors v
     where v.id = vendor_id and v.owner_id = (select auth.uid())));

-- Merged for the same reason as drivers. Approval status, commission, delivery
-- fee and billing model are guarded by trg_guard_vendor_platform_terms, which
-- raises PLATFORM_TERMS_ADMIN_ONLY — so an owner updating their own row still
-- cannot approve themselves or rewrite their own terms.
drop policy if exists vendors_admin_all on public.vendors;
drop policy if exists vendors_update_own on public.vendors;
drop policy if exists vendors_insert_own on public.vendors;
create policy vendors_insert on public.vendors
  for insert
  with check (owner_id = (select auth.uid()) or public.is_admin());
create policy vendors_update on public.vendors
  for update
  using (owner_id = (select auth.uid()) or public.is_admin())
  with check (owner_id = (select auth.uid()) or public.is_admin());
create policy vendors_delete on public.vendors
  for delete to authenticated using (public.is_admin());
