-- Maintenance mode: the platform stays up for staff and stops taking orders
-- from everyone else, with a message the admin writes.
alter table public.platform_settings
  add column if not exists maintenance_mode boolean not null default false,
  add column if not exists maintenance_message text,
  add column if not exists maintenance_message_ar text;

create or replace function public.admin_set_maintenance_mode(
  p_enabled boolean,
  p_message text default null,
  p_message_ar text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  insert into public.platform_settings (id, maintenance_mode, maintenance_message, maintenance_message_ar)
  values (1, p_enabled, nullif(btrim(p_message), ''), nullif(btrim(p_message_ar), ''))
  on conflict (id) do update
    set maintenance_mode = excluded.maintenance_mode,
        maintenance_message = excluded.maintenance_message,
        maintenance_message_ar = excluded.maintenance_message_ar;

  perform public.log_admin_action('platform.maintenance', 'platform_settings', null,
    jsonb_build_object('enabled', p_enabled));
end;
$$;

revoke all on function public.admin_set_maintenance_mode(boolean, text, text) from public, anon;
grant execute on function public.admin_set_maintenance_mode(boolean, text, text) to authenticated;

-- The server enforces it too, so a stale app cannot place an order while the
-- platform is down. Patched in place: place_order is long and owned elsewhere.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.place_order(uuid, payment_method, text, text, order_type, timestamptz)'::regprocedure);
  if d like '%MAINTENANCE_MODE%' then
    return;
  end if;
  n := replace(
    d,
    'v_is_pickup boolean := p_order_type = ''pickup'';',
    'v_is_pickup boolean := p_order_type = ''pickup'';
  v_maintenance boolean;'
  );
  n := regexp_replace(
    n,
    E'\nbegin\n',
    E'\nbegin\n  select maintenance_mode into v_maintenance from public.platform_settings where id = 1;\n  if coalesce(v_maintenance, false) and not public.is_admin() then\n    raise exception ''MAINTENANCE_MODE'';\n  end if;\n',
    ''
  );
  execute n;
end
$patch$;
