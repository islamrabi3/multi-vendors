-- Staff, with the address they actually sign in with.
--
-- `profiles` has no email column — it lives in `auth.users`, which no client
-- may read. The staff screen was falling back to showing a phone number in the
-- email slot, which is worse than showing nothing.
create or replace function public.admin_staff_list()
returns table (
  id uuid,
  full_name text,
  email text,
  admin_role_id uuid,
  is_blocked boolean,
  created_at timestamptz
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
           p.created_at
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.role = 'admin' and p.deleted_at is null
    order by p.full_name;
end;
$$;

revoke execute on function public.admin_staff_list() from public, anon;
grant execute on function public.admin_staff_list() to authenticated;

-- Finding somebody who already has an account, to promote them.
--
-- Deliberately narrow: an exact-ish match on email or phone, or a name
-- fragment, capped low. This reads `auth.users`, so it must not double as a
-- way to page through every address on the platform.
create or replace function public.admin_search_users(p_query text)
returns table (
  id uuid,
  full_name text,
  email text,
  phone text,
  role text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.has_permission('staff.manage') then
    raise exception 'FORBIDDEN';
  end if;
  if length(trim(coalesce(p_query, ''))) < 3 then
    -- Short queries would return most of the table.
    return;
  end if;

  return query
    select p.id, p.full_name, u.email::text, p.phone, p.role::text
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.deleted_at is null
      and (
        u.email ilike '%' || trim(p_query) || '%'
        or p.phone ilike '%' || trim(p_query) || '%'
        or p.full_name ilike '%' || trim(p_query) || '%'
      )
    order by p.full_name
    limit 20;
end;
$$;

revoke execute on function public.admin_search_users(text) from public, anon;
grant execute on function public.admin_search_users(text) to authenticated;

-- Taking someone off the staff. Demotes rather than deletes: their orders and
-- history are still theirs, they simply stop being an admin.
create or replace function public.admin_revoke_staff(p_user_id uuid)
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
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_CHANGE_OWN_ROLE';
  end if;

  update public.profiles
  set role = 'customer', admin_role_id = null
  where id = p_user_id;

  perform public.log_admin_action('staff.revoke', 'profile', p_user_id);
end;
$$;

revoke execute on function public.admin_revoke_staff(uuid) from public, anon;
grant execute on function public.admin_revoke_staff(uuid) to authenticated;
