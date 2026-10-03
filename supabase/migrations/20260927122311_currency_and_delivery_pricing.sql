-- The platform's currency, and how delivery is priced.
--
-- Currency: amounts have always been bare numbers, with "EGP" written into
-- the app. An operator launching in another market needs to say what those
-- numbers are. The platform runs in one currency at a time — there is no
-- conversion, and switching relabels every amount rather than repricing it —
-- chosen from a list the admin keeps. EGP stays the default.
--
-- Delivery: until now each store charged its own flat fee. An operator can
-- now price it by distance instead: a base fee covers the first stretch
-- (10 km unless changed), and every started kilometre past that adds a set
-- rate. The distance is straight-line from the store to the delivery pin,
-- the same measure the service-area check already uses.

-- ---------------------------------------------------------------------------
-- Currencies
-- ---------------------------------------------------------------------------
create table if not exists public.currencies (
  code text primary key check (code ~ '^[A-Z]{3}$'),
  name text not null check (btrim(name) <> ''),
  name_ar text,
  -- Shown before the amount. Defaults to the code in the app when blank.
  symbol text not null check (btrim(symbol) <> ''),
  -- Used on the Arabic UI when set; otherwise [symbol].
  symbol_ar text,
  decimals smallint not null default 2 check (decimals between 0 and 3),
  created_at timestamptz not null default now()
);

alter table public.currencies enable row level security;

drop policy if exists currencies_read on public.currencies;
create policy currencies_read on public.currencies
  for select using (true);

insert into public.currencies (code, name, name_ar, symbol, symbol_ar, decimals)
values
  ('EGP', 'Egyptian Pound', 'جنيه مصري', 'EGP', null, 2),
  ('SAR', 'Saudi Riyal', 'ريال سعودي', 'SAR', null, 2)
on conflict (code) do nothing;

alter table public.platform_settings
  add column if not exists currency_code text not null default 'EGP'
    references public.currencies (code);

-- ---------------------------------------------------------------------------
-- Delivery pricing
-- ---------------------------------------------------------------------------
alter table public.platform_settings
  add column if not exists delivery_fee_mode text not null default 'store'
    check (delivery_fee_mode in ('store', 'distance')),
  add column if not exists delivery_base_fee numeric not null default 0
    check (delivery_base_fee >= 0),
  add column if not exists delivery_base_km numeric not null default 10
    check (delivery_base_km >= 0),
  add column if not exists delivery_per_km_fee numeric not null default 0
    check (delivery_per_km_fee >= 0);

comment on column public.platform_settings.delivery_fee_mode is
  'store: each store''s own flat delivery_fee. distance: delivery_base_fee '
  'for the first delivery_base_km, plus delivery_per_km_fee for every '
  'started kilometre beyond.';

-- The one place a delivery fee is worked out. place_order charges it; the
-- app mirrors it (DeliveryFeeRule) only to show the same number beforehand.
create or replace function public.compute_delivery_fee(
  p_vendor_id uuid,
  p_lat double precision,
  p_lng double precision
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  s public.platform_settings%rowtype;
  v public.vendors%rowtype;
  v_km double precision;
  v_extra numeric;
begin
  select * into s from public.platform_settings where id = 1;
  select * into v from public.vendors where id = p_vendor_id;
  if not found then
    raise exception 'VENDOR_NOT_FOUND';
  end if;

  if coalesce(s.delivery_fee_mode, 'store') <> 'distance' then
    return round(coalesce(v.delivery_fee, 0), 2);
  end if;

  -- Without both ends of the trip there is no distance to charge for; the
  -- base fee is the honest floor rather than refusing the order.
  if v.lat is null or v.lng is null or p_lat is null or p_lng is null then
    return round(s.delivery_base_fee, 2);
  end if;

  v_km := public.distance_km(v.lat, v.lng, p_lat, p_lng);
  -- Every started kilometre past the base distance counts as a whole one.
  v_extra := greatest(ceil(v_km - s.delivery_base_km), 0);
  return round(s.delivery_base_fee + v_extra * s.delivery_per_km_fee, 2);
end;
$$;

revoke all on function public.compute_delivery_fee(uuid, double precision, double precision)
  from public, anon;
grant execute on function public.compute_delivery_fee(uuid, double precision, double precision)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Admin controls
-- ---------------------------------------------------------------------------
create or replace function public.admin_set_delivery_pricing(
  p_mode text,
  p_base_fee numeric,
  p_base_km numeric,
  p_per_km_fee numeric
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
  if p_mode not in ('store', 'distance') then
    raise exception 'INVALID_MODE';
  end if;
  if coalesce(p_base_fee, -1) < 0
     or coalesce(p_base_km, -1) < 0
     or coalesce(p_per_km_fee, -1) < 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  update public.platform_settings set
    delivery_fee_mode = p_mode,
    delivery_base_fee = p_base_fee,
    delivery_base_km = p_base_km,
    delivery_per_km_fee = p_per_km_fee,
    updated_at = now(),
    updated_by = auth.uid()
  where id = 1;

  perform public.log_admin_action('settings.delivery_pricing', 'platform_settings', null,
    jsonb_build_object('mode', p_mode, 'base_fee', p_base_fee,
                       'base_km', p_base_km, 'per_km_fee', p_per_km_fee));
end;
$$;

create or replace function public.admin_upsert_currency(
  p_code text,
  p_name text,
  p_name_ar text,
  p_symbol text,
  p_symbol_ar text,
  p_decimals smallint
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text := upper(btrim(p_code));
begin
  if not public.has_permission('finance.adjust') then
    raise exception 'FORBIDDEN';
  end if;
  if v_code !~ '^[A-Z]{3}$' then
    raise exception 'INVALID_CURRENCY_CODE';
  end if;
  if coalesce(btrim(p_name), '') = '' then
    raise exception 'NAME_REQUIRED';
  end if;
  if p_decimals is null or p_decimals not between 0 and 3 then
    raise exception 'INVALID_AMOUNT';
  end if;

  insert into public.currencies (code, name, name_ar, symbol, symbol_ar, decimals)
  values (
    v_code,
    btrim(p_name),
    nullif(btrim(p_name_ar), ''),
    coalesce(nullif(btrim(p_symbol), ''), v_code),
    nullif(btrim(p_symbol_ar), ''),
    p_decimals
  )
  on conflict (code) do update set
    name = excluded.name,
    name_ar = excluded.name_ar,
    symbol = excluded.symbol,
    symbol_ar = excluded.symbol_ar,
    decimals = excluded.decimals;

  perform public.log_admin_action('settings.currency_saved', 'currency', null,
    jsonb_build_object('code', v_code));
end;
$$;

create or replace function public.admin_delete_currency(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('finance.adjust') then
    raise exception 'FORBIDDEN';
  end if;
  if exists (select 1 from public.platform_settings where currency_code = p_code) then
    raise exception 'CURRENCY_IN_USE';
  end if;

  delete from public.currencies where code = p_code;

  perform public.log_admin_action('settings.currency_deleted', 'currency', null,
    jsonb_build_object('code', p_code));
end;
$$;

create or replace function public.admin_set_currency(p_code text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.has_permission('finance.adjust') then
    raise exception 'FORBIDDEN';
  end if;
  if not exists (select 1 from public.currencies where code = p_code) then
    raise exception 'CURRENCY_NOT_FOUND';
  end if;

  update public.platform_settings set
    currency_code = p_code,
    updated_at = now(),
    updated_by = auth.uid()
  where id = 1;

  perform public.log_admin_action('settings.currency', 'platform_settings', null,
    jsonb_build_object('code', p_code));
end;
$$;

revoke all on function public.admin_set_delivery_pricing(text, numeric, numeric, numeric) from public, anon;
revoke all on function public.admin_upsert_currency(text, text, text, text, text, smallint) from public, anon;
revoke all on function public.admin_delete_currency(text) from public, anon;
revoke all on function public.admin_set_currency(text) from public, anon;
grant execute on function public.admin_set_delivery_pricing(text, numeric, numeric, numeric) to authenticated;
grant execute on function public.admin_upsert_currency(text, text, text, text, text, smallint) to authenticated;
grant execute on function public.admin_delete_currency(text) to authenticated;
grant execute on function public.admin_set_currency(text) to authenticated;

-- ---------------------------------------------------------------------------
-- place_order charges the fee from compute_delivery_fee
-- ---------------------------------------------------------------------------
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef(
    'public.place_order(uuid, payment_method, text, text, order_type, timestamptz)'::regprocedure);
  if d like '%compute_delivery_fee%' then
    return;
  end if;

  n := replace(d,
    '  v_delivery_fee := case when v_is_pickup then 0 else v_vendor.delivery_fee end;',
    '  v_delivery_fee := case when v_is_pickup then 0
    else public.compute_delivery_fee(v_vendor.id, v_address.lat, v_address.lng) end;');

  if n = d then
    raise exception 'place_order anchors not found';
  end if;
  execute n;
end
$patch$;
