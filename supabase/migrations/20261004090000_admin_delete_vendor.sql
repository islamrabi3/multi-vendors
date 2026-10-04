-- Permanently remove a store from the admin's store list.
--
-- Suspending keeps a store and hides it; this takes it away for good: the
-- store row and everything that hangs off it (menu, categories, options,
-- schedules, staff links, coupons, banners, reviews, favourites, carts) go
-- through the existing ON DELETE CASCADE foreign keys.
--
-- A store that has ever taken an order cannot be removed. `orders` references
-- `vendors` with NO ACTION, and the order rows carry the ledger, settlements
-- and the customers' own history; deleting them to make room would rewrite
-- the money. Such a store is refused with VENDOR_HAS_ORDERS and should be
-- suspended instead.
--
-- The owner's login goes with the store when it was only ever a store login:
-- a vendor account that owns no other store and has no order history of its
-- own as a customer or driver. Anything else keeps its account.
create or replace function public.admin_delete_vendor(p_vendor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_name text;
  v_login_deleted boolean := false;
begin
  if not public.has_permission('users.delete') then
    raise exception 'FORBIDDEN';
  end if;

  select owner_id, name into v_owner, v_name
    from public.vendors
   where id = p_vendor_id
   for update;
  if not found then
    raise exception 'NOT_FOUND';
  end if;

  if exists (select 1 from public.orders where vendor_id = p_vendor_id) then
    raise exception 'VENDOR_HAS_ORDERS';
  end if;

  -- Audit first: after the delete there is nothing left to describe.
  perform public.log_admin_action(
    'vendor.delete', 'vendor', p_vendor_id,
    jsonb_build_object('name', v_name, 'owner_id', v_owner)
  );

  delete from public.vendors where id = p_vendor_id;

  if v_owner is not null
     and v_owner <> (select auth.uid())
     and exists (select 1 from public.profiles
                  where id = v_owner and role = 'vendor')
     and not exists (select 1 from public.vendors where owner_id = v_owner)
     and not exists (select 1 from public.orders
                      where customer_id = v_owner or driver_id = v_owner)
  then
    -- Something else may still point at the account (a chat, a ledger
    -- line). The store is what was asked for, so it goes regardless and the
    -- login is simply kept.
    begin
      delete from auth.users where id = v_owner;
      v_login_deleted := true;
    exception when foreign_key_violation then
      v_login_deleted := false;
    end;
  end if;

  return jsonb_build_object(
    'deleted', true,
    'vendor_id', p_vendor_id,
    'owner_login_deleted', v_login_deleted
  );
end;
$$;

revoke execute on function public.admin_delete_vendor(uuid) from public, anon;
grant execute on function public.admin_delete_vendor(uuid) to authenticated;
