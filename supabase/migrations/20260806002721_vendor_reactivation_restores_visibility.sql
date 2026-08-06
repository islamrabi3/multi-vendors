-- Reactivating a suspended store left it invisible.
--
-- Suspension sets is_active = false. Reactivation then said
--   is_active = case when p_status = 'active' then is_active else false end
-- which on the way back in preserves the false it had just written. The store
-- returned to approval_status = 'active' and stayed hidden from customers for
-- good, because vendors_read requires is_active -- with nothing in the admin
-- UI to explain why, since its status now read "active".
--
-- Reactivation now undoes exactly what suspension did, both flags. A store
-- that was closed by its owner before being suspended comes back open, which
-- is one tap for them to correct -- the alternative is a store nobody can find
-- and an owner with no way to know why.
create or replace function public.admin_set_vendor_status(
  p_vendor_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  if not public.has_permission('vendors.approve') then
    raise exception 'FORBIDDEN';
  end if;
  if p_status not in ('pending', 'active', 'suspended', 'rejected') then
    raise exception 'INVALID_STATUS';
  end if;

  update public.vendors
     set approval_status = p_status,
         -- A suspended store must not keep taking orders while it argues;
         -- an approved one has to be findable and able to trade again.
         is_active = (p_status = 'active'),
         is_open = (p_status = 'active')
   where id = p_vendor_id;

  perform public.log_admin_action('vendor.status', 'vendor', p_vendor_id,
    jsonb_build_object('status', p_status));
end;
$$;
