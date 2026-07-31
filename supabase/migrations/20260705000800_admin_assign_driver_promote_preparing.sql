create or replace function public.admin_assign_driver(
  p_order_id uuid,
  p_driver_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'NOT_ADMIN';
  end if;

  update public.orders
  set driver_id = p_driver_id,
      status = case when status in ('preparing', 'ready_for_pickup')
                    then 'out_for_delivery'::public.order_status
                    else status end,
      picked_up_at = case when status in ('preparing', 'ready_for_pickup')
                          then now() else picked_up_at end,
      updated_at = now()
  where id = p_order_id;
end;
$$;;
