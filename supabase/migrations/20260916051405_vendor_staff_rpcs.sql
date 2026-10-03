-- Managing staff: the owner edits permissions and removes people. Creating
-- the login itself needs the Auth admin API and lives in the
-- vendor-create-staff edge function, which calls vendor_attach_staff here.

create or replace function public.vendor_attach_staff(
  p_user_id uuid,
  p_vendor_id uuid,
  p_full_name text,
  p_permissions text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.vendors v
    where v.id = p_vendor_id and v.owner_id = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;
  if exists (select 1 from public.vendors v where v.owner_id = p_user_id) then
    raise exception 'ALREADY_A_STORE_OWNER';
  end if;

  insert into public.vendor_staff (vendor_id, user_id, full_name, permissions)
  values (p_vendor_id, p_user_id, nullif(btrim(p_full_name), ''),
          coalesce(p_permissions, '{}'))
  on conflict (user_id) do update
    set vendor_id = excluded.vendor_id,
        full_name = coalesce(excluded.full_name, public.vendor_staff.full_name),
        permissions = excluded.permissions;
end;
$$;

create or replace function public.vendor_set_staff_permissions(
  p_user_id uuid,
  p_permissions text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.vendor_staff s
    join public.vendors v on v.id = s.vendor_id
    where s.user_id = p_user_id and v.owner_id = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;

  update public.vendor_staff
  set permissions = coalesce(p_permissions, '{}')
  where user_id = p_user_id;
end;
$$;

-- Removing somebody takes their access away for good: the login stays, but it
-- is a customer account again, so it cannot open the store console or start a
-- store of its own by accident.
create or replace function public.vendor_remove_staff(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.vendor_staff s
    join public.vendors v on v.id = s.vendor_id
    where s.user_id = p_user_id and v.owner_id = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;

  delete from public.vendor_staff where user_id = p_user_id;
  update public.profiles
  set role = 'customer'::public.user_role
  where id = p_user_id and role = 'vendor'::public.user_role;
end;
$$;

-- What the signed-in user may do inside their store: `*` for an owner, the
-- staff row's keys otherwise. The app reads this once at sign-in.
create or replace function public.my_vendor_access()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case
    when exists (select 1 from public.vendors v where v.owner_id = auth.uid())
      then jsonb_build_object(
        'vendor_id', (select v.id from public.vendors v where v.owner_id = auth.uid() limit 1),
        'is_owner', true,
        'permissions', jsonb_build_array('*')
      )
    else coalesce(
      (select jsonb_build_object(
         'vendor_id', s.vendor_id,
         'is_owner', false,
         'permissions', to_jsonb(s.permissions)
       )
       from public.vendor_staff s where s.user_id = auth.uid() limit 1),
      jsonb_build_object('vendor_id', null, 'is_owner', false,
                         'permissions', jsonb_build_array())
    )
  end;
$$;

revoke all on function public.vendor_attach_staff(uuid, uuid, text, text[]) from public, anon;
revoke all on function public.vendor_set_staff_permissions(uuid, text[]) from public, anon;
revoke all on function public.vendor_remove_staff(uuid) from public, anon;
grant execute on function public.vendor_attach_staff(uuid, uuid, text, text[]) to authenticated;
grant execute on function public.vendor_set_staff_permissions(uuid, text[]) to authenticated;
grant execute on function public.vendor_remove_staff(uuid) to authenticated;
grant execute on function public.my_vendor_access() to authenticated;
