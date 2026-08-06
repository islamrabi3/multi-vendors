-- 1. A driver could approve themselves.
--
-- drivers_update lets a driver write their own row, with no guard on which
-- columns. Verified against the live database: a pending driver set
-- approval_status = 'active' in one REST call and was on the road, with the
-- documents never reviewed. That is the whole point of the review queue.
--
-- The columns an admin owns are now guarded in a trigger rather than in the
-- policy, so a driver keeps being able to write the rest of their own row
-- (vehicle type, location, and the document paths below).
create or replace function public.guard_driver_admin_columns()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if (new.approval_status is distinct from old.approval_status
      or new.approved_at is distinct from old.approved_at
      or new.rejection_reason is distinct from old.rejection_reason)
     and not public.is_admin()
  then
    raise exception 'DRIVER_APPROVAL_ADMIN_ONLY';
  end if;
  return new;
end;
$$;

revoke execute on function public.guard_driver_admin_columns()
  from anon, authenticated, public;

drop trigger if exists trg_guard_driver_admin_columns on public.drivers;
create trigger trg_guard_driver_admin_columns
  before update on public.drivers
  for each row execute function public.guard_driver_admin_columns();

-- 2. The signup form collects four documents; the table had columns for two.
--    Both sides of an ID are what actually verifies it -- a front alone shows a
--    photo and a name, and the expiry and issuing details are on the back.
alter table public.drivers
  add column if not exists id_card_back_url text,
  add column if not exists license_back_url text;

-- 3. Re-uploading a document replaces the object, which is an UPDATE on
--    storage.objects. Only INSERT was granted, so a driver correcting a blurry
--    photo failed on the second attempt.
drop policy if exists driver_docs_own_update on storage.objects;
create policy driver_docs_own_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
