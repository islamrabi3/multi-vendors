-- Three ways a store's orders can run.
--
--   vendor    The store is in the app. It accepts, prepares and marks the
--             order ready; a rider collects it with the store's pickup code.
--   platform  The store is not in the app. An operator accepts the order on
--             its behalf, and accepting it is what sends it to the riders.
--             The store is never asked anything.
--   direct    Nobody accepts. The order goes to the riders the moment it can
--             be seen, and the rider who takes it deals with the customer
--             directly — buys what they asked for and brings it over.
--
-- Until now the flow was read off the store every time it was needed. That
-- made an order's rules depend on whatever the store happened to be set to at
-- that moment: switching a store mid-service changed the rules for orders
-- already half-way through, and a rider could suddenly collect an order the
-- store had only just accepted. Each order now carries the flow it was placed
-- under, and only an order nobody has touched yet (still pending) follows the
-- store when it is switched.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------
alter table public.vendors drop constraint if exists vendors_order_flow_check;
alter table public.vendors
  add constraint vendors_order_flow_check
  check (order_flow in ('vendor', 'platform', 'direct'));

alter table public.orders
  add column if not exists order_flow text not null default 'vendor';
alter table public.orders drop constraint if exists orders_order_flow_check;
alter table public.orders
  add constraint orders_order_flow_check
  check (order_flow in ('vendor', 'platform', 'direct'));

comment on column public.orders.order_flow is
  'The flow this order runs under (vendor | platform | direct), copied from '
  'the store when it is placed. Only a pending order follows the store when '
  'the store is switched.';

-- Open orders take whatever their store runs today.
update public.orders o
set order_flow = v.order_flow
from public.vendors v
where v.id = o.vendor_id
  and o.status not in ('delivered', 'cancelled', 'rejected')
  and o.order_flow is distinct from v.order_flow;

-- ---------------------------------------------------------------------------
-- Stamp the flow when the order is placed
-- ---------------------------------------------------------------------------
create or replace function public.set_order_flow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  select coalesce(v.order_flow, 'vendor') into new.order_flow
  from public.vendors v where v.id = new.vendor_id;
  new.order_flow := coalesce(new.order_flow, 'vendor');

  -- A collection order needs somebody at the counter who knows about it. A
  -- store that is not in the app does not, and there is no rider to send.
  if new.order_type = 'pickup' and new.order_flow <> 'vendor' then
    raise exception 'PICKUP_UNAVAILABLE';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_orders_order_flow on public.orders;
create trigger trg_orders_order_flow
  before insert on public.orders
  for each row execute function public.set_order_flow();

-- ---------------------------------------------------------------------------
-- Direct orders go to the riders as soon as they can be seen
-- ---------------------------------------------------------------------------
-- Replaces release_platform_run_order: a platform-run order now waits for an
-- operator to accept it, and only a direct one skips straight to the riders.
drop trigger if exists trg_release_platform_run_insert on public.orders;
drop trigger if exists trg_release_platform_run_paid on public.orders;
drop function if exists public.release_platform_run_order();

create or replace function public.release_direct_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.order_flow <> 'direct'
     or new.status <> 'pending'
     or new.order_type = 'pickup'
     -- A scheduled order waits for its slot.
     or new.released_at is null
     -- A card order is a draft until it is paid.
     or (new.payment_method = 'paymob' and new.payment_status <> 'paid') then
    return null;
  end if;

  update public.orders
  set status = 'ready_for_pickup',
      accepted_at = coalesce(accepted_at, now()),
      ready_at = coalesce(ready_at, now())
  where id = new.id
    and status = 'pending';

  return null;
end;
$$;

create trigger trg_release_direct_insert
  after insert on public.orders
  for each row execute function public.release_direct_order();

create trigger trg_release_direct_update
  after update of payment_status, released_at, order_flow on public.orders
  for each row execute function public.release_direct_order();

-- ---------------------------------------------------------------------------
-- Who may move an order, per flow
-- ---------------------------------------------------------------------------
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
  v_status order_status := p_new_status;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  v_is_customer := v_order.customer_id = auth.uid();
  v_is_vendor := public.is_vendor_member(v_order.vendor_id, 'orders');
  v_is_driver := v_order.driver_id = auth.uid();
  v_is_admin := public.is_admin();

  -- Without a store in the loop there is no accepted or preparing stage: the
  -- order is either waiting for an operator or waiting for a rider. Accepting
  -- one is therefore the same thing as sending it to the riders.
  if v_order.order_flow <> 'vendor'
     and v_status in ('accepted', 'preparing') then
    v_status := 'ready_for_pickup';
  end if;

  -- The store only runs its own orders when it is the one running them.
  if v_is_vendor and v_order.order_flow = 'vendor' then
    v_allowed := (v_order.status = 'pending' and v_status in ('accepted', 'rejected'))
              or (v_order.status = 'accepted' and v_status = 'preparing')
              or (v_order.status = 'preparing' and v_status = 'ready_for_pickup')
              -- Pickup only: nobody else can hand the food over.
              or (v_order.order_type = 'pickup'
                  and v_order.status = 'ready_for_pickup'
                  and v_status = 'delivered');
  end if;

  if not v_allowed and v_is_driver then
    v_allowed := v_order.status = 'out_for_delivery' and v_status = 'delivered';
  end if;

  if not v_allowed and v_is_customer and v_status = 'cancelled' then
    v_allowed := v_order.status = 'pending'
              -- A direct order is up for grabs the moment it is placed; until
              -- a rider takes it, nobody has done anything the customer would
              -- be walking out on.
              or (v_order.order_flow = 'direct'
                  and v_order.status = 'ready_for_pickup'
                  and v_order.driver_id is null);
  end if;

  if not v_allowed and v_is_admin then
    v_allowed := v_order.status not in ('delivered', 'cancelled', 'rejected')
             and v_status = 'cancelled';
    -- No store in the loop: the operator drives every step.
    if not v_allowed and v_order.order_flow <> 'vendor' then
      v_allowed := v_order.status not in ('delivered', 'cancelled', 'rejected');
    end if;
  end if;

  if not v_allowed then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> %', v_order.status, v_status;
  end if;

  -- An order on its way has somebody carrying it.
  if v_status in ('out_for_delivery', 'delivered')
     and v_order.order_type <> 'pickup'
     and v_order.driver_id is null then
    raise exception 'NO_DRIVER_ASSIGNED';
  end if;

  update public.orders
  set status = v_status,
      rejection_reason = case
        when v_status in ('rejected', 'cancelled') and p_reason is not null
          then p_reason else rejection_reason end,
      accepted_at = case
        when v_status in ('accepted', 'ready_for_pickup')
          then coalesce(accepted_at, now()) else accepted_at end,
      ready_at = case when v_status = 'ready_for_pickup' then now() else ready_at end,
      picked_up_at = case
        when v_status = 'out_for_delivery'
          then coalesce(picked_up_at, now()) else picked_up_at end,
      delivered_at = case when v_status = 'delivered' then now() else delivered_at end,
      cancelled_at = case when v_status in ('cancelled', 'rejected') then now()
                          else cancelled_at end,
      payment_status = case
        when v_status = 'delivered' and payment_method = 'cod' then 'paid'::public.payment_status
        else payment_status end
  where id = p_order_id;

  -- Same transaction as the status change: an order cannot end up delivered
  -- but unsettled, or settled but not delivered.
  if v_status = 'delivered' then
    perform public.finance_settle_order(p_order_id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Collecting
-- ---------------------------------------------------------------------------
-- The pickup code proves the store handed the bag to this rider. Only a store
-- in the app has the code to read out; for the other two flows the rider is
-- the one buying, so there is nobody to check it against.
create or replace function public.driver_confirm_pickup(p_order_id uuid, p_code text)
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

  -- A store in the app says when the food is ready, and nothing may be
  -- collected before it does. Without a store in the loop, anything the rider
  -- holds is collectable.
  if not (
    v_order.status = 'ready_for_pickup'
    or (v_order.order_flow <> 'vendor'
        and v_order.status in ('accepted', 'preparing'))
  ) then
    raise exception 'TRANSITION_NOT_ALLOWED:% -> out_for_delivery', v_order.status;
  end if;

  if v_order.order_flow = 'vendor'
     and coalesce(btrim(p_code), '') <> coalesce(v_order.pickup_code, '') then
    raise exception 'WRONG_PICKUP_CODE';
  end if;

  update public.orders
  set status = 'out_for_delivery',
      picked_up_at = now()
  where id = p_order_id;
end;
$$;

-- An operator handing an order to a rider. For a store in the app the bag is
-- already at the counter, so the order goes straight out. Otherwise the rider
-- still has to go and buy it, so the order waits for them to collect it — and
-- a platform order still waiting for an operator counts as accepted by this.
create or replace function public.admin_assign_driver(p_order_id uuid, p_driver_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  if not public.has_permission('orders.assign') then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  if v_order.order_flow = 'vendor' then
    update public.orders
    set driver_id = p_driver_id,
        claimed_at = coalesce(claimed_at, now()),
        status = case when status = 'ready_for_pickup' then 'out_for_delivery'::order_status
                      else status end,
        picked_up_at = case when status = 'ready_for_pickup'
                            then coalesce(picked_up_at, now()) else picked_up_at end
    where id = p_order_id;
  else
    update public.orders
    set driver_id = p_driver_id,
        claimed_at = coalesce(claimed_at, now()),
        status = case
          when status in ('accepted', 'preparing') then 'ready_for_pickup'::order_status
          when status = 'pending'
               and released_at is not null
               and (payment_method <> 'paymob' or payment_status = 'paid')
            then 'ready_for_pickup'::order_status
          else status end,
        accepted_at = case when status in ('pending', 'accepted', 'preparing')
                           then coalesce(accepted_at, now()) else accepted_at end,
        ready_at = case when status in ('pending', 'accepted', 'preparing')
                        then coalesce(ready_at, now()) else ready_at end
    where id = p_order_id;
  end if;

  perform public.log_admin_action('order.assign', 'order', p_order_id,
    jsonb_build_object('driver_id', p_driver_id));
end;
$$;

-- ---------------------------------------------------------------------------
-- Switching a store
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_vendor_order_flow(
  p_vendor_id uuid,
  p_flow text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('vendors.terms') then
    raise exception 'FORBIDDEN';
  end if;
  if p_flow not in ('vendor', 'platform', 'direct') then
    raise exception 'INVALID_FLOW';
  end if;

  update public.vendors set order_flow = p_flow where id = p_vendor_id;

  -- Orders nobody has touched yet follow the store. Anything already accepted
  -- finishes the way it started. A pending order switched to direct is sent
  -- to the riders by trg_release_direct_update.
  update public.orders
  set order_flow = p_flow
  where vendor_id = p_vendor_id
    and status = 'pending'
    and order_flow <> p_flow
    -- Collection orders need a store in the app; they stay where they are.
    and order_type <> 'pickup';

  perform public.log_admin_action('vendor.order_flow', 'vendor', p_vendor_id,
    jsonb_build_object('flow', p_flow));
end;
$$;

revoke all on function public.admin_set_vendor_order_flow(uuid, text) from public, anon;
grant execute on function public.admin_set_vendor_order_flow(uuid, text) to authenticated;

-- A silent store hands its orders to the operators — including the ones it
-- is sitting on right now, which are the reason for the takeover. Only a
-- store that runs its own orders can be silent; the other two never wait on it.
create or replace function public.takeover_unanswered_vendors()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_minutes int;
  v_switched int := 0;
  v_vendor record;
begin
  select coalesce(vendor_takeover_minutes, 0) into v_minutes
  from public.platform_settings where id = 1;
  if coalesce(v_minutes, 0) <= 0 then
    return 0;
  end if;

  for v_vendor in
    select distinct v.id, count(*) over (partition by v.id) as waiting
    from public.orders o
    join public.vendors v on v.id = o.vendor_id
    where o.status = 'pending'
      and o.order_flow = 'vendor'
      and coalesce(v.order_flow, 'vendor') = 'vendor'
      -- Only orders the store could actually have seen. A card order stays
      -- invisible until it is paid, and a scheduled one until it is released;
      -- neither is the shop ignoring anything.
      and o.released_at is not null
      and o.released_at < now() - make_interval(mins => v_minutes)
      and (o.payment_method <> 'paymob' or o.payment_status = 'paid')
  loop
    update public.vendors
    set order_flow = 'platform'
    where id = v_vendor.id;

    update public.orders
    set order_flow = 'platform'
    where vendor_id = v_vendor.id
      and status = 'pending'
      and order_flow = 'vendor'
      and order_type <> 'pickup';

    insert into public.admin_audit_log (
      actor_id, action, target_type, target_id, detail
    ) values (
      -- Nobody did this: the store's silence did.
      null,
      'vendor.order_flow_taken_over',
      'vendor',
      v_vendor.id,
      jsonb_build_object(
        'reason', 'NO_RESPONSE',
        'minutes', v_minutes,
        'orders_waiting', v_vendor.waiting
      )
    );
    v_switched := v_switched + 1;
  end loop;

  return v_switched;
end;
$$;

revoke execute on function public.takeover_unanswered_vendors()
  from anon, authenticated, public;

-- ---------------------------------------------------------------------------
-- Telling the right people about a new order
-- ---------------------------------------------------------------------------
-- A platform order is announced to the operators rather than the store, and a
-- direct one is announced to the riders by its own ready_for_pickup event.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.notify_order_event()'::regprocedure);
  if d like '%new_platform_order%' then
    return;
  end if;

  n := replace(d,
    '    v_events := array[''new_order''::text];
  else',
    '    v_events := array[case new.order_flow
      when ''platform'' then ''new_platform_order''
      when ''direct'' then null
      else ''new_order'' end];
    v_events := array_remove(v_events, null);
  else');

  n := replace(n,
    '    if new.payment_method = ''paymob''
       and new.payment_status = ''paid''
       and old.payment_status <> ''paid'' then
      v_events := array[''new_order''::text];
    end if;',
    '    if new.payment_method = ''paymob''
       and new.payment_status = ''paid''
       and old.payment_status <> ''paid''
       and new.order_flow <> ''direct'' then
      v_events := array[case when new.order_flow = ''platform''
                             then ''new_platform_order'' else ''new_order'' end];
    end if;

    -- Taken over from a silent store, or switched by an operator: the order
    -- now needs somebody who was never told about it.
    if new.order_flow = ''platform''
       and old.order_flow is distinct from new.order_flow
       and new.status = ''pending'' then
      v_events := v_events || ''new_platform_order''::text;
    end if;');

  if n not like '%case new.order_flow%'
     or n not like '%old.order_flow is distinct%' then
    raise exception 'notify_order_event anchors not found';
  end if;
  execute n;
end
$patch$;
