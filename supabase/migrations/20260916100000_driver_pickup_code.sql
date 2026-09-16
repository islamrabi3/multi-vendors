-- A six-digit code the store reads out when it hands the food over.
--
-- Claiming a delivery used to mark the order picked up in the same statement,
-- so "out for delivery" meant "a driver tapped accept", not "the driver has
-- the food". The claim now only assigns the driver; the store's code is what
-- moves the order out for delivery, which is also what stops a driver
-- collecting an order that belongs to somebody else.
alter table public.orders
  add column if not exists pickup_code text,
  add column if not exists claimed_at timestamptz;

create or replace function public.set_order_pickup_code()
returns trigger
language plpgsql
as $$
begin
  if new.pickup_code is null then
    new.pickup_code := lpad((floor(random() * 1000000))::int::text, 6, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_pickup_code on public.orders;
create trigger trg_orders_pickup_code
  before insert on public.orders
  for each row execute function public.set_order_pickup_code();

update public.orders
set pickup_code = lpad((floor(random() * 1000000))::int::text, 6, '0')
where pickup_code is null;

-- Assigns the driver and nothing else.
create or replace function public.claim_delivery(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_claimed boolean;
begin
  if not public.is_online_driver() then
    raise exception 'NOT_AN_ONLINE_DRIVER';
  end if;

  update public.orders
  set driver_id = auth.uid(),
      claimed_at = now()
  where id = p_order_id
    and driver_id is null
    and status = 'ready_for_pickup'
    and order_type <> 'pickup';

  v_claimed := found;
  return v_claimed;
end;
$$;

-- The driver types the store's code at the counter.
create or replace function public.driver_confirm_pickup(
  p_order_id uuid,
  p_code text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
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
  if v_order.status <> 'ready_for_pickup' then
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

revoke all on function public.driver_confirm_pickup(uuid, text) from public, anon;
grant execute on function public.driver_confirm_pickup(uuid, text) to authenticated;
