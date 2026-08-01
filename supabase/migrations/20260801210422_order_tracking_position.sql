-- The driver's last stored position for one order.
--
-- Live tracking rode entirely on a realtime broadcast from the driver's phone,
-- so a customer who opened the order between two broadcasts saw an empty map,
-- and one who opened it after the driver's app went to sleep saw nothing at
-- all. `drivers.current_lat/lng` is already written on a timer; this is the
-- customer's only way to read it, since `drivers` is not theirs to select.
create or replace function public.order_driver_position(p_order_id uuid)
returns table (lat double precision, lng double precision, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  return query
    select d.current_lat, d.current_lng, d.location_updated_at
    from public.orders o
    join public.drivers d on d.id = o.driver_id
    where o.id = p_order_id
      -- Only the parties to the order, and only while it is actually moving:
      -- a delivered order must not keep leaking where the driver is now.
      and (o.customer_id = auth.uid()
           or public.is_vendor_owner(o.vendor_id)
           or public.is_admin())
      and o.status = 'out_for_delivery'
      and d.current_lat is not null
      and d.current_lng is not null;
end;
$$;

revoke execute on function public.order_driver_position(uuid) from public, anon;
grant execute on function public.order_driver_position(uuid) to authenticated;
