-- Where the platform actually delivers.
--
-- The admin draws one or more circles (a centre and a radius in km); a delivery
-- address is servable when its pin falls inside any active circle. Radius is a
-- plain column, so it can be widened or narrowed at any time with no migration.

create table if not exists public.service_areas (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  name_ar text,
  lat double precision not null,
  lng double precision not null,
  radius_km numeric(6, 2) not null check (radius_km > 0 and radius_km <= 300),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_service_areas_updated_at on public.service_areas;
create trigger trg_service_areas_updated_at
  before update on public.service_areas
  for each row execute function public.set_updated_at();

alter table public.service_areas enable row level security;

-- Customers need to read them to draw the coverage circles on the address map.
drop policy if exists service_areas_read on public.service_areas;
create policy service_areas_read on public.service_areas
  for select to authenticated using (true);

drop policy if exists service_areas_admin_all on public.service_areas;
create policy service_areas_admin_all on public.service_areas
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Great-circle distance in km. Plain haversine so this carries no dependency on
-- the earthdistance/cube extensions.
create or replace function public.distance_km(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
)
returns double precision
language sql
immutable
parallel safe
as $$
  select 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
      * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- True when the point is inside any active area.
--
-- Two deliberate "allow" defaults, so switching this on cannot strand a live
-- platform:
--   * no active areas configured at all -> the platform is not geofenced yet
--     and everywhere is servable;
--   * an address saved before the map picker existed and carrying no pin ->
--     grandfathered rather than rejected.
create or replace function public.is_within_service_area(
  p_lat double precision,
  p_lng double precision
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    not exists (select 1 from public.service_areas where is_active)
    or p_lat is null
    or p_lng is null
    or exists (
      select 1 from public.service_areas a
      where a.is_active
        and public.distance_km(a.lat, a.lng, p_lat, p_lng) <= a.radius_km
    );
$$;

grant execute on function public.is_within_service_area(double precision, double precision)
  to authenticated;
grant execute on function public.distance_km(
  double precision, double precision, double precision, double precision
) to authenticated;
