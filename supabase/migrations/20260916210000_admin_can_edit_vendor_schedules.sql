-- Opening hours an admin can set.
--
-- Hours were the store owner's alone to write, which left an operator
-- onboarding a shop in person unable to enter the timetable the owner had
-- just read out to them. The store still owns its own hours; the admin is
-- added beside it, the same way they can already edit the store row itself.
drop policy if exists vendor_schedules_insert on public.vendor_schedules;
create policy vendor_schedules_insert on public.vendor_schedules
  for insert to authenticated
  with check (
    public.is_admin()
    or exists (
      select 1 from public.vendors v
      where v.id = vendor_schedules.vendor_id
        and v.owner_id = (select auth.uid())
    )
  );

drop policy if exists vendor_schedules_update on public.vendor_schedules;
create policy vendor_schedules_update on public.vendor_schedules
  for update to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.vendors v
      where v.id = vendor_schedules.vendor_id
        and v.owner_id = (select auth.uid())
    )
  )
  with check (
    public.is_admin()
    or exists (
      select 1 from public.vendors v
      where v.id = vendor_schedules.vendor_id
        and v.owner_id = (select auth.uid())
    )
  );

drop policy if exists vendor_schedules_delete on public.vendor_schedules;
create policy vendor_schedules_delete on public.vendor_schedules
  for delete to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.vendors v
      where v.id = vendor_schedules.vendor_id
        and v.owner_id = (select auth.uid())
    )
  );
