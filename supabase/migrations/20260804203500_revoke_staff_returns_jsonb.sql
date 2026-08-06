-- Return jsonb rather than a bare text scalar.
--
-- Every other RPC in this project that hands a value back returns jsonb or a
-- number; this one was the odd one out, and a scalar `text` return is the one
-- shape whose JSON encoding is worth not having to think about. The body is
-- otherwise unchanged from 20260804201724.
drop function if exists public.admin_revoke_staff(uuid);

create function public.admin_revoke_staff(p_user_id uuid)
returns jsonb
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

  return jsonb_build_object('restored_role', v_role::text);
end;
$$;

revoke execute on function public.admin_revoke_staff(uuid) from public, anon;
grant execute on function public.admin_revoke_staff(uuid) to authenticated;
