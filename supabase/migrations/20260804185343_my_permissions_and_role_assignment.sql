-- What the signed-in admin may do, so the app can hide what they cannot.
--
-- Hiding is courtesy only; every one of these is enforced server-side too.
-- `*` means unrestricted, which is what an admin with no role assigned gets.
create or replace function public.my_permissions()
returns text[]
language sql
stable
security definer
set search_path = public
as $$
  select case
    when p.role <> 'admin' then '{}'::text[]
    when p.admin_role_id is null then array['*']
    else coalesce(r.permissions, '{}'::text[])
  end
  from public.profiles p
  left join public.admin_roles r on r.id = p.admin_role_id
  where p.id = auth.uid();
$$;

grant execute on function public.my_permissions() to authenticated;

-- Assigning a role to a member of staff.
--
-- Separate from the profiles table's own update policy: `admin_role_id` is
-- the one column on a profile that must never be self-served, or a restricted
-- admin would simply clear their own role and become unrestricted.
create or replace function public.admin_assign_role(
  p_user_id uuid,
  p_role_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('staff.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id = auth.uid() then
    -- Otherwise the last unrestricted admin can lock themselves out, or a
    -- restricted one can promote themselves.
    raise exception 'CANNOT_CHANGE_OWN_ROLE';
  end if;
  if not exists (select 1 from public.profiles
                 where id = p_user_id and role = 'admin') then
    raise exception 'NOT_AN_ADMIN';
  end if;

  update public.profiles set admin_role_id = p_role_id where id = p_user_id;

  perform public.log_admin_action('staff.assign_role', 'profile', p_user_id,
    jsonb_build_object('role_id', p_role_id));
end;
$$;

revoke execute on function public.admin_assign_role(uuid, uuid) from public, anon;
grant execute on function public.admin_assign_role(uuid, uuid) to authenticated;

-- Promoting an existing user to staff. Only an unrestricted admin may do it:
-- creating admins is how a limited account would escalate itself.
create or replace function public.admin_grant_staff(
  p_user_id uuid,
  p_role_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and admin_role_id is null
      and not is_blocked and deleted_at is null
  ) then
    raise exception 'FORBIDDEN';
  end if;

  update public.profiles
  set role = 'admin', admin_role_id = p_role_id, role_confirmed = true
  where id = p_user_id;

  perform public.log_admin_action('staff.grant', 'profile', p_user_id,
    jsonb_build_object('role_id', p_role_id));
end;
$$;

revoke execute on function public.admin_grant_staff(uuid, uuid) from public, anon;
grant execute on function public.admin_grant_staff(uuid, uuid) to authenticated;

-- Deleting a role must not silently promote everyone holding it: the column
-- is `on delete set null`, which would make them unrestricted. This refuses
-- while anybody still holds it.
create or replace function public.admin_delete_role(p_role_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('staff.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if exists (select 1 from public.profiles where admin_role_id = p_role_id) then
    raise exception 'ROLE_IN_USE';
  end if;

  delete from public.admin_roles where id = p_role_id;
  perform public.log_admin_action('staff.delete_role', 'admin_role', p_role_id);
end;
$$;

revoke execute on function public.admin_delete_role(uuid) from public, anon;
grant execute on function public.admin_delete_role(uuid) to authenticated;
