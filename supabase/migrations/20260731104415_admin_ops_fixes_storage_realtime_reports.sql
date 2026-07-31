-- Admin operations round-up: driver paperwork, live service areas, and the
-- payout numbers the admin actually settles from.
--
-- The two files immediately before this one had never reached the project, so
-- their statements are repeated here (all idempotent) — a fresh `db reset` and
-- the live project end up identical either way.

-- ---------------------------------------------------------------------------
-- 1. Driver paperwork.
--
-- An admin cannot approve a delivery account without seeing the national ID
-- and the licence, so the two images hang off the driver row.
-- ---------------------------------------------------------------------------
alter table public.drivers
  add column if not exists id_card_url text,
  add column if not exists license_url text;

comment on column public.drivers.id_card_url is
  'Storage path (not a public URL) of the national ID scan in driver-documents.';
comment on column public.drivers.license_url is
  'Storage path (not a public URL) of the driving licence scan in driver-documents.';

-- These are identity documents, so they live in a private bucket and are only
-- ever served through short-lived signed URLs. A public bucket would put a
-- guessable link to someone's ID card on the open internet.
insert into storage.buckets (id, name, public)
values ('driver-documents', 'driver-documents', false)
on conflict (id) do update set public = false;

-- Path convention: <driver_id>/<doc_type>-<epoch>.<ext>, so the first folder
-- segment is the owner and both policies can key off it.
drop policy if exists driver_docs_admin_all on storage.objects;
create policy driver_docs_admin_all on storage.objects
  for all to authenticated
  using (bucket_id = 'driver-documents' and public.is_admin())
  with check (bucket_id = 'driver-documents' and public.is_admin());

drop policy if exists driver_docs_own_read on storage.objects;
create policy driver_docs_own_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists driver_docs_own_write on storage.objects;
create policy driver_docs_own_write on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'driver-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
-- 2. Suspending an online driver must not fail.
--
-- The old trigger raised DRIVER_NOT_APPROVED *before* clearing is_online, so
-- an admin suspending a driver who happened to be on shift got an exception
-- instead of a suspension. Take them offline first, then enforce.
-- ---------------------------------------------------------------------------
create or replace function public.enforce_driver_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Losing approval takes the driver off the road immediately.
  if new.approval_status <> 'active' then
    new.is_online := false;
  end if;

  if new.is_online and new.approval_status <> 'active' then
    raise exception 'DRIVER_NOT_APPROVED';
  end if;
  return new;
end;
$$;

create or replace function public.admin_set_driver_status(
  p_driver_id uuid,
  p_status text,
  p_reason text default null
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
  if p_status not in ('pending', 'active', 'suspended') then
    raise exception 'INVALID_STATUS';
  end if;

  update public.drivers
  set approval_status = p_status,
      is_online = case when p_status <> 'active' then false else is_online end,
      approved_at = case when p_status = 'active' then now() else approved_at end,
      rejection_reason = case when p_status = 'active' then null else p_reason end
  where id = p_driver_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Service areas were never in the realtime publication.
--
-- The admin screen reads them through `.stream()`, so an added or deleted area
-- only appeared after a manual refresh.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'service_areas'
  ) then
    alter publication supabase_realtime add table public.service_areas;
  end if;
end $$;

-- A delete has to reach the client with enough of the row to match it against
-- the list; the default (primary key only) is what `.stream()` needs, but
-- being explicit keeps it from depending on the table default.
alter table public.service_areas replica identity default;

-- ---------------------------------------------------------------------------
-- 4. Settlement reports.
--
-- The app was computing these client-side from a flat 10% commission and a
-- flat 90% driver share, which does not match `vendors.commission_rate` and
-- cannot be trusted for paying anyone. Both now aggregate server-side over
-- delivered orders only.
-- ---------------------------------------------------------------------------

-- Gross sales are order subtotals: delivery fees belong to the driver, and the
-- coupon discount is a platform promotion, so neither reduces what the store
-- earned. Commission comes off each store's own rate.
create or replace function public.admin_vendor_sales_report(
  p_start timestamptz default null,
  p_end timestamptz default null
)
returns table (
  vendor_id uuid,
  vendor_name text,
  total_orders bigint,
  gross_sales numeric,
  commission_rate numeric,
  commission_fee numeric,
  net_payout numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  return query
  select
    v.id,
    v.name,
    count(o.id),
    round(coalesce(sum(o.subtotal), 0), 2),
    coalesce(v.commission_rate, 10),
    round(coalesce(sum(o.subtotal), 0) * coalesce(v.commission_rate, 10) / 100.0, 2),
    round(
      coalesce(sum(o.subtotal), 0)
      - coalesce(sum(o.subtotal), 0) * coalesce(v.commission_rate, 10) / 100.0,
      2
    )
  from public.vendors v
  join public.orders o on o.vendor_id = v.id
  where o.status = 'delivered'
    and (p_start is null or o.created_at >= p_start)
    and (p_end is null or o.created_at <= p_end)
  group by v.id, v.name, v.commission_rate
  having count(o.id) > 0
  order by 4 desc;
end;
$$;

-- Tips are read off `orders.driver_tip` only. `driver_tips` holds the same
-- money for orders tipped after delivery; summing both would pay it twice, so
-- that table stays out of the payout figure until the two are reconciled.
create or replace function public.admin_driver_payout_report(
  p_start timestamptz default null,
  p_end timestamptz default null,
  p_driver_share numeric default 90
)
returns table (
  driver_id uuid,
  driver_name text,
  delivered_orders bigint,
  delivery_fees numeric,
  tips numeric,
  net_payout numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;
  if p_driver_share < 0 or p_driver_share > 100 then
    raise exception 'INVALID_SHARE';
  end if;

  return query
  select
    p.id,
    coalesce(nullif(trim(p.full_name), ''), 'Driver'),
    count(o.id),
    round(coalesce(sum(o.delivery_fee), 0), 2),
    round(coalesce(sum(o.driver_tip), 0), 2),
    round(
      coalesce(sum(o.delivery_fee), 0) * p_driver_share / 100.0
      + coalesce(sum(o.driver_tip), 0),
      2
    )
  from public.profiles p
  join public.orders o on o.driver_id = p.id
  where o.status = 'delivered'
    and (p_start is null or o.created_at >= p_start)
    and (p_end is null or o.created_at <= p_end)
  group by p.id, p.full_name
  having count(o.id) > 0
  order by 4 desc;
end;
$$;

revoke execute on function public.admin_vendor_sales_report(timestamptz, timestamptz)
  from public, anon;
grant execute on function public.admin_vendor_sales_report(timestamptz, timestamptz)
  to authenticated;

revoke execute on function public.admin_driver_payout_report(timestamptz, timestamptz, numeric)
  from public, anon;
grant execute on function public.admin_driver_payout_report(timestamptz, timestamptz, numeric)
  to authenticated;
