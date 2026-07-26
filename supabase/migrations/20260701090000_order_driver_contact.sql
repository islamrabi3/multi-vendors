-- Expose the assigned driver's name + phone to the order's customer.
-- profiles RLS is select-own only, so customers cannot read the driver row
-- directly. This SECURITY DEFINER function returns the contact only to the
-- customer who owns the order (and only once a driver is assigned).
create or replace function public.order_driver_contact(p_order_id uuid)
returns table (full_name text, phone text)
language sql
security definer
set search_path = public
as $$
  select pr.full_name, pr.phone
  from public.orders o
  join public.profiles pr on pr.id = o.driver_id
  where o.id = p_order_id
    and o.customer_id = auth.uid()
    and o.driver_id is not null;
$$;

grant execute on function public.order_driver_contact(uuid) to authenticated;
