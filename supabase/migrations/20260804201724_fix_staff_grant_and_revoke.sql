-- Removing somebody from staff has to put back what they were.
--
-- The first version set `role = 'customer'` flat. For a store owner that is
-- destructive: `is_vendor_owner()` checks the profile, so demoting them to
-- customer locks them out of their own store and orphans it. The role is
-- inferred from what the account actually owns, which also repairs accounts
-- promoted before this existed — nothing recorded their prior role.
--
-- Returns the role it restored, so the console can say which.
drop function if exists public.admin_revoke_staff(uuid);

create function public.admin_revoke_staff(p_user_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role user_role;
begin
  if not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin' and admin_role_id is null
      and not is_blocked and deleted_at is null
  ) then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_CHANGE_OWN_ROLE';
  end if;
  if not exists (select 1 from public.profiles
                 where id = p_user_id and role = 'admin') then
    raise exception 'NOT_AN_ADMIN';
  end if;

  -- What they are underneath, in the order that matters: a store owner is a
  -- vendor whatever else is true of them.
  select case
    when exists (select 1 from public.vendors where owner_id = p_user_id)
      then 'vendor'::user_role
    when exists (select 1 from public.drivers where id = p_user_id)
      then 'driver'::user_role
    else 'customer'::user_role
  end into v_role;

  update public.profiles
  set role = v_role, admin_role_id = null
  where id = p_user_id;

  perform public.log_admin_action('staff.revoke', 'profile', p_user_id,
    jsonb_build_object('restored_role', v_role));

  return v_role::text;
end;
$$;

revoke execute on function public.admin_revoke_staff(uuid) from public, anon;
grant execute on function public.admin_revoke_staff(uuid) to authenticated;

-- And stop the mistake being made again.
--
-- A store owner with admin rights can approve their own store, set their own
-- commission and promote themselves onto the customer home page. A driver can
-- approve their own account. Neither is a role anybody should be able to hand
-- out by accident from a search result.
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

  if exists (select 1 from public.vendors where owner_id = p_user_id) then
    raise exception 'CANNOT_PROMOTE_VENDOR';
  end if;
  if exists (select 1 from public.drivers where id = p_user_id) then
    raise exception 'CANNOT_PROMOTE_DRIVER';
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

-- The staff list shows what an account is underneath, so a store owner sitting
-- in the admin list is visible rather than looking like any other member of
-- staff.
drop function if exists public.admin_staff_list();

create function public.admin_staff_list()
returns table (
  id uuid,
  full_name text,
  email text,
  admin_role_id uuid,
  is_blocked boolean,
  created_at timestamptz,
  owns_vendor boolean,
  is_driver boolean
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  return query
    select p.id, p.full_name, u.email::text, p.admin_role_id, p.is_blocked,
           p.created_at,
           exists (select 1 from public.vendors v where v.owner_id = p.id),
           exists (select 1 from public.drivers d where d.id = p.id)
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.role = 'admin' and p.deleted_at is null
    order by p.full_name;
end;
$$;

revoke execute on function public.admin_staff_list() from public, anon;
grant execute on function public.admin_staff_list() to authenticated;
