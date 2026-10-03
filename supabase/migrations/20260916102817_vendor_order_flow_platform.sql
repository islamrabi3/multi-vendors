-- Some stores are not on the platform yet: they take no orders in the app, do
-- not accept anything, and the platform buys from them on the customer's
-- behalf. Those stores run in `platform` flow — the admin owns the order from
-- start to finish, and a driver is sent without waiting for the store.
alter table public.vendors
  add column if not exists order_flow text not null default 'vendor'
  check (order_flow in ('vendor', 'platform'));

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
  if p_flow not in ('vendor', 'platform') then
    raise exception 'INVALID_FLOW';
  end if;

  update public.vendors set order_flow = p_flow where id = p_vendor_id;

  perform public.log_admin_action('vendor.order_flow', 'vendor', p_vendor_id,
    jsonb_build_object('flow', p_flow));
end;
$$;

revoke all on function public.admin_set_vendor_order_flow(uuid, text) from public, anon;
grant execute on function public.admin_set_vendor_order_flow(uuid, text) to authenticated;

-- In platform flow the admin drives every step; the store is not asked.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.update_order_status(uuid, order_status, text)'::regprocedure);
  if d like '%order_flow%' then
    return;
  end if;

  n := replace(d,
    '  v_allowed boolean := false;',
    '  v_allowed boolean := false;
  v_platform_run boolean := false;');

  n := replace(n,
    '  v_is_admin := public.is_admin();',
    '  v_is_admin := public.is_admin();

  select coalesce(v.order_flow, ''vendor'') = ''platform''
  into v_platform_run
  from public.vendors v where v.id = v_order.vendor_id;');

  n := replace(n,
    '  if not v_allowed and v_is_admin then
    v_allowed := v_order.status not in (''delivered'', ''cancelled'', ''rejected'')
             and p_new_status = ''cancelled'';
  end if;',
    '  if not v_allowed and v_is_admin then
    v_allowed := v_order.status not in (''delivered'', ''cancelled'', ''rejected'')
             and p_new_status = ''cancelled'';
    -- Platform-run store: the admin is the one accepting, preparing and
    -- handing over, because the store is not in the app at all.
    if not v_allowed and coalesce(v_platform_run, false) then
      v_allowed := v_order.status not in (''delivered'', ''cancelled'', ''rejected'');
    end if;
  end if;');

  if n = d then
    raise exception 'update_order_status anchors not found';
  end if;
  execute n;
end
$patch$;

-- A platform-run store's orders go straight to the driver pool: nothing is
-- waiting on the store to press accept.
create or replace function public.release_platform_run_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_flow text;
begin
  select coalesce(order_flow, 'vendor') into v_flow
  from public.vendors where id = new.vendor_id;

  if v_flow <> 'platform' then
    return null;
  end if;
  -- A card order is still held until it is paid; everything else is ready to
  -- be collected the moment it is placed.
  if new.payment_method = 'paymob' and new.payment_status <> 'paid' then
    return null;
  end if;
  if new.released_at is null then
    return null;
  end if;
  if new.status <> 'pending' then
    return null;
  end if;

  update public.orders
  set status = 'ready_for_pickup',
      accepted_at = coalesce(accepted_at, now()),
      ready_at = coalesce(ready_at, now())
  where id = new.id;

  return null;
end;
$$;

drop trigger if exists trg_release_platform_run_insert on public.orders;
create trigger trg_release_platform_run_insert
  after insert on public.orders
  for each row execute function public.release_platform_run_order();

drop trigger if exists trg_release_platform_run_paid on public.orders;
create trigger trg_release_platform_run_paid
  after update of payment_status, released_at on public.orders
  for each row execute function public.release_platform_run_order();
