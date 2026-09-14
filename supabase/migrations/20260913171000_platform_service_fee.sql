-- A platform service fee on every order, set by admins only.
--
-- One settings row holds the rule (a fixed amount or a percentage of the
-- subtotal, optionally capped). place_order snapshots the fee onto the order,
-- the total includes it — so card, wallet and cash all collect it — and
-- settlement books it as platform revenue.

create table if not exists public.platform_settings (
  id smallint primary key default 1 check (id = 1),
  service_fee_type text not null default 'fixed'
    check (service_fee_type in ('fixed', 'percent')),
  service_fee_value numeric(10, 2) not null default 0
    check (service_fee_value >= 0),
  service_fee_max numeric(10, 2) check (service_fee_max is null or service_fee_max >= 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);

insert into public.platform_settings (id) values (1) on conflict (id) do nothing;

alter table public.platform_settings enable row level security;

-- Customers see the fee at checkout before they place the order.
drop policy if exists platform_settings_read on public.platform_settings;
create policy platform_settings_read on public.platform_settings
  for select to anon, authenticated using (true);

revoke insert, update, delete on public.platform_settings from anon, authenticated;

alter table public.orders
  add column if not exists service_fee numeric(10, 2) not null default 0;

create or replace function public.compute_service_fee(p_subtotal numeric)
returns numeric
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((
    select round(
      case
        when s.service_fee_type = 'percent' then
          least(
            greatest(p_subtotal, 0) * s.service_fee_value / 100.0,
            coalesce(s.service_fee_max, 'infinity'::numeric)
          )
        else s.service_fee_value
      end, 2)
    from public.platform_settings s
    where s.id = 1
  ), 0);
$$;

grant execute on function public.compute_service_fee(numeric) to anon, authenticated;

create or replace function public.admin_set_service_fee(
  p_type text,
  p_value numeric,
  p_max numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('finance.adjust') then
    raise exception 'FORBIDDEN';
  end if;
  if p_type not in ('fixed', 'percent') then
    raise exception 'INVALID_FEE_TYPE';
  end if;
  if p_value is null or p_value < 0 or (p_type = 'percent' and p_value > 100) then
    raise exception 'INVALID_AMOUNT';
  end if;

  update public.platform_settings set
    service_fee_type = p_type,
    service_fee_value = p_value,
    service_fee_max = case when p_type = 'percent' then p_max else null end,
    updated_at = now(),
    updated_by = auth.uid()
  where id = 1;

  perform public.log_admin_action('settings.service_fee', 'platform_settings', null,
    jsonb_build_object('type', p_type, 'value', p_value, 'max', p_max));
end;
$$;

revoke all on function public.admin_set_service_fee(text, numeric, numeric) from public, anon;
grant execute on function public.admin_set_service_fee(text, numeric, numeric) to authenticated;

-- place_order and finance_settle_order are patched in place rather than
-- restated, so this migration cannot silently revert any other change made
-- to them. Each patch asserts its anchor was found.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef(
    'public.place_order(uuid, payment_method, text, text, order_type, timestamptz)'::regprocedure);

  n := replace(d,
    'v_delivery_fee numeric := 0;',
    'v_delivery_fee numeric := 0;
  v_service_fee numeric := 0;');
  if n = d then raise exception 'place_order: declare anchor missing'; end if;
  d := n;

  n := replace(d,
    '  insert into public.orders (',
    '  v_service_fee := public.compute_service_fee(v_subtotal);

  insert into public.orders (');
  if n = d then raise exception 'place_order: insert anchor missing'; end if;
  d := n;

  n := replace(d,
    'subtotal, delivery_fee, discount, total,',
    'subtotal, delivery_fee, service_fee, discount, total,');
  if n = d then raise exception 'place_order: column anchor missing'; end if;
  d := n;

  n := replace(d,
    'v_subtotal, v_delivery_fee, v_discount,
    greatest(v_subtotal - v_discount + v_delivery_fee, 0),',
    'v_subtotal, v_delivery_fee, v_service_fee, v_discount,
    greatest(v_subtotal - v_discount + v_delivery_fee, 0) + v_service_fee,');
  if n = d then raise exception 'place_order: values anchor missing'; end if;
  d := n;

  execute d;

  d := pg_get_functiondef('public.finance_settle_order(uuid)'::regprocedure);

  n := replace(d,
    '  -- A platform-funded discount is money the platform never collected but the',
    '  perform public.finance_post(
    ''platform'', null, ''platform_service_fee'', coalesce(v_order.service_fee, 0),
    ''credit'', p_order_id, v_order.order_number, ''Service fee'', ''{}''::jsonb,
    v_key || ''service_fee'');

  -- A platform-funded discount is money the platform never collected but the');
  if n = d then raise exception 'finance_settle_order: anchor missing'; end if;
  d := n;

  n := replace(d,
    '''delivery_margin'', v_delivery_margin,',
    '''delivery_margin'', v_delivery_margin,
    ''service_fee'', coalesce(v_order.service_fee, 0),');
  if n = d then raise exception 'finance_settle_order: result anchor missing'; end if;
  d := n;

  execute d;
end
$patch$;
