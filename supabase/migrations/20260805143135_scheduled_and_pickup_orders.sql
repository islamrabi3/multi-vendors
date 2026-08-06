-- Scheduled orders and pickup.
--
-- `order_type` already had 'pickup' and 'scheduled', and `scheduled_at`
-- already existed on the order — but nothing set either, nothing read them,
-- and the checkout screen carried a comment saying there was no feature to
-- choose between. This is the product behind the columns.

-- When the store is allowed to see it.
--
-- An immediate order is released the moment it is placed. A scheduled one is
-- held back until shortly before its slot, so a store taking an order for
-- Friday does not have it sitting in their queue all week.
alter table public.orders
  add column if not exists released_at timestamptz;

-- Everything that already exists was visible the moment it was placed.
update public.orders set released_at = created_at where released_at is null;

create index if not exists orders_pending_release_idx
  on public.orders (scheduled_at)
  where released_at is null;

-- A pickup order never reaches a driver.
--
-- The pool is "everything ready_for_pickup with no driver", which is exactly
-- what a pickup order looks like while it waits on the counter — without this
-- a driver would be sent to collect an order the customer is coming for.
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
      status = 'out_for_delivery',
      picked_up_at = now()
  where id = p_order_id
    and driver_id is null
    and status = 'ready_for_pickup'
    and order_type <> 'pickup';

  v_claimed := found;
  return v_claimed;
end;
$$;

-- The customer collects, so the store is the one who closes the order.
--
-- Every other path is unchanged; this adds the single transition a pickup
-- order needs and that no role could previously make.
create or replace function public.update_order_status(
  p_order_id uuid,
  p_new_status order_status,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_is_customer boolean;
  v_is_vendor boolean;
  v_is_driver boolean;
  v_is_admin boolean;
  v_allowed boolean := false;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  v_is_customer := v_order.customer_id = auth.uid();
  v_is_vendor := public.is_vendor_owner(v_order.vendor_id);
  v_is_driver := v_order.driver_id = auth.uid();
  v_is_admin := public.is_admin();

  if v_is_vendor then
    v_allowed := (v_order.status = 'pending' and p_new_status in ('accepted', 'rejected'))
              or (v_order.status = 'accepted' and p_new_status = 'preparing')
              or (v_order.status = 'preparing' and p_new_status = 'ready_for_pickup')
              -- Pickup only: nobody else can hand the food over.
              or (v_order.order_type = 'pickup'
                  and v_order.status = 'ready_for_pickup'
                  and p_new_status = 'delivered');
  end if;

  if not v_allowed and v_is_driver then
    v_allowed := v_order.status = 'out_for_delivery' and p_new_status = 'delivered';
  end if;

  if not v_allowed and v_is_customer then
    v_allowed := v_order.status = 'pending' and p_new_status = 'cancelled';
  end if;

  if not v_allowed and v_is_admin then
    v_allowed := v_order.status not in ('delivered', 'cancelled', 'rejected')
             and p_new_status = 'cancelled';
  end if;

  if not v_allowed then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> %', v_order.status, p_new_status;
  end if;

  update public.orders
  set status = p_new_status,
      rejection_reason = case
        when p_new_status in ('rejected', 'cancelled') and p_reason is not null
          then p_reason else rejection_reason end,
      accepted_at = case when p_new_status = 'accepted' then now() else accepted_at end,
      ready_at = case when p_new_status = 'ready_for_pickup' then now() else ready_at end,
      delivered_at = case when p_new_status = 'delivered' then now() else delivered_at end,
      cancelled_at = case when p_new_status in ('cancelled', 'rejected') then now()
                          else cancelled_at end,
      payment_status = case
        when p_new_status = 'delivered' and payment_method = 'cod' then 'paid'::public.payment_status
        else payment_status end
  where id = p_order_id;
end;
$$;

-- Releases scheduled orders to the store shortly before their slot.
--
-- 45 minutes: long enough to shop, prep and cook; short enough that the
-- queue stays a queue. Runs on a schedule rather than being computed in a
-- query so the release is a row change realtime already carries — the order
-- simply appears on the vendor's dashboard.
create or replace function public.release_due_scheduled_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.orders
  set released_at = now()
  where order_type = 'scheduled'
    and released_at is null
    and status = 'pending'
    and scheduled_at is not null
    and scheduled_at <= now() + interval '45 minutes';

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.release_due_scheduled_orders()
  from public, anon, authenticated;

select cron.schedule(
  'release-scheduled-orders',
  '*/5 * * * *',
  $$select public.release_due_scheduled_orders();$$
);
