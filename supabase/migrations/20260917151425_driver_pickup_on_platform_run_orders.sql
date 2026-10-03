-- A rider can collect an order the platform is running.
--
-- Collecting required the order to be at 'ready_for_pickup', which only the
-- store can set. A platform-run store is not in the app at all — the admin
-- accepts and hands over on its behalf — so those orders go from 'accepted'
-- straight on, and the rider's swipe raised TRANSITION_NOT_ALLOWED against a
-- status the store was never going to leave. From the rider's side nothing
-- happened at all, and the order only ever moved when an admin moved it.
--
-- The pickup code is unchanged and still required: it is the proof the rider
-- was actually handed the food, and for these stores the admin reads it out.
create or replace function public.driver_confirm_pickup(p_order_id uuid, p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_platform_run boolean;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  if v_order.driver_id is distinct from auth.uid() then
    raise exception 'FORBIDDEN';
  end if;
  if v_order.status = 'out_for_delivery' then
    -- Already collected: a double tap is not an error.
    return;
  end if;

  select coalesce(v.order_flow, 'vendor') = 'platform'
  into v_platform_run
  from public.vendors v where v.id = v_order.vendor_id;

  -- A store that runs its own orders says when the food is ready, and nothing
  -- may be collected before it does. A store the platform runs never says so,
  -- so anything already accepted is collectable.
  if not (
    v_order.status = 'ready_for_pickup'
    or (coalesce(v_platform_run, false)
        and v_order.status in ('accepted', 'preparing'))
  ) then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> out_for_delivery', v_order.status;
  end if;

  if coalesce(btrim(p_code), '') <> coalesce(v_order.pickup_code, '') then
    raise exception 'WRONG_PICKUP_CODE';
  end if;

  update public.orders
  set status = 'out_for_delivery',
      picked_up_at = now()
  where id = p_order_id;
end;
$$;
