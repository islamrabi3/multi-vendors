-- Deleting an account only ever anonymised it: the profile row stayed, and
-- the auth user with it, so the address could still sign in. Now the row is
-- really removed wherever the data allows.
--
-- Where it does not: orders.customer_id, orders.driver_id and orders.vendor_id
-- are all NO ACTION, so an account with any order history cannot be deleted
-- without taking the order ledger with it. That is the database protecting
-- records that are financial and legal, not an oversight, and this function
-- does not work around it. Such an account keeps the anonymised row -- no
-- name, no phone, no avatar, no push token, blocked and marked deleted -- and
-- the caller is told which of the two happened so the admin is not misled.
drop function if exists public.admin_delete_user(uuid);

create function public.admin_delete_user(p_user_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_order_count int;
begin
  if not public.has_permission('users.delete') then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id = (select auth.uid()) then
    raise exception 'CANNOT_DELETE_SELF';
  end if;
  if exists (select 1 from public.profiles
             where id = p_user_id and role = 'admin') then
    raise exception 'CANNOT_DELETE_ADMIN';
  end if;

  select count(*) into v_order_count
    from public.orders o
   where o.customer_id = p_user_id
      or o.driver_id = p_user_id
      or o.vendor_id in (select id from public.vendors where owner_id = p_user_id);

  -- Audit first: the log survives either path, and after a hard delete there
  -- is nothing left to write about.
  perform public.log_admin_action('user.delete', 'profile', p_user_id);

  if v_order_count = 0 then
    -- Cascades through profiles and everything hanging off it: wallets,
    -- addresses, favourites, the store and its menu.
    delete from auth.users where id = p_user_id;
    return jsonb_build_object('hard_deleted', true, 'orders', 0);
  end if;

  update public.vendors
     set is_active = false, is_open = false, approval_status = 'suspended'
   where owner_id = p_user_id;

  update public.drivers set is_online = false where id = p_user_id;

  update public.profiles
     set deleted_at = now(),
         is_blocked = true,
         full_name = 'Deleted user',
         phone = null,
         avatar_url = null,
         fcm_token = null
   where id = p_user_id;

  -- The account can no longer be signed into even though the row remains.
  update auth.users
     set encrypted_password = null,
         email = null,
         phone = null,
         raw_user_meta_data = '{}'::jsonb
   where id = p_user_id;

  return jsonb_build_object('hard_deleted', false, 'orders', v_order_count);
end;
$$;

revoke execute on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_delete_user(uuid)
  to authenticated, service_role;
