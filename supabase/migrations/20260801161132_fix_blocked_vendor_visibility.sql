-- The previous policy inlined a subquery over `profiles`, which is itself
-- under RLS: a customer can only see their own profile row, so the lookup of
-- the *owner's* row returned nothing and `not exists (...)` was always true.
-- The blocked store stayed visible to everyone.
--
-- A security definer helper reads the flag on the caller's behalf, which is
-- the only way a policy can consult a row the caller cannot see.
create or replace function public.is_owner_active(p_owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select not exists (
    select 1 from public.profiles
    where id = p_owner_id
      and (is_blocked or deleted_at is not null)
  );
$$;

grant execute on function public.is_owner_active(uuid) to anon, authenticated;

drop policy if exists vendors_read on public.vendors;
create policy vendors_read on public.vendors
  for select to public
  using (
    (
      is_active
      and approval_status = 'active'
      and public.is_owner_active(owner_id)
    )
    or owner_id = auth.uid()
    or public.is_admin()
  );
