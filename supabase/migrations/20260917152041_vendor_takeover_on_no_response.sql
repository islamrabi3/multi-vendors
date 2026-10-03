-- A store that does not answer hands its orders to the platform.
--
-- A shop that leaves an order sitting in 'pending' is not deciding; it is
-- absent — the tablet is off, the phone is in a drawer, nobody is looking.
-- The customer waits either way. After a set number of minutes the store is
-- moved onto platform-run, where an operator accepts on its behalf and the
-- rider is dispatched without waiting for the shop.
--
-- Vendor-level rather than order-level, because a store that missed this
-- order at this hour is about to miss the next one, and an operator watching
-- the queue is a better answer than the same wait repeating. An admin can put
-- it back from the store's own page; the switch is written to the audit log
-- so it is never a mystery who did it.
alter table public.platform_settings
  add column if not exists vendor_takeover_minutes int not null default 5;

comment on column public.platform_settings.vendor_takeover_minutes is
  'Minutes a store has to accept an order before the platform takes its '
  'orders over. 0 disables the takeover entirely.';

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
    select distinct v.id, v.name, count(*) over (partition by v.id) as waiting
    from public.orders o
    join public.vendors v on v.id = o.vendor_id
    where o.status = 'pending'
      and coalesce(v.order_flow, 'vendor') <> 'platform'
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

-- Every minute: the whole point is that five minutes means five, not ten.
select cron.schedule(
  'takeover-unanswered-vendors',
  '* * * * *',
  $cron$select public.takeover_unanswered_vendors();$cron$
);
