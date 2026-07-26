-- Offers: extend `banners` into rich, admin-managed promotional offers.
-- Adds title/subtitle/promo-code, an is_admin() helper, and admin write access.

alter table public.banners
  add column if not exists title text,
  add column if not exists subtitle text,
  add column if not exists code text;

-- Admin check (mirrors public.is_vendor_owner). SECURITY DEFINER so it can read
-- profiles regardless of caller RLS; only ever returns a boolean about the caller.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

-- Admins can read (incl. inactive) and add/remove offers.
-- Existing "banners_read" (using is_active) still serves anon/customers.
drop policy if exists "banners_admin_all" on public.banners;
create policy "banners_admin_all" on public.banners
  for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Enrich the seeded rows so the home Offers section has content immediately.
update public.banners
  set title = '40% off your first order',
      subtitle = 'On orders over EGP 100',
      code = 'EATY40'
  where sort_order = 1;

update public.banners
  set title = 'Free delivery weekend',
      subtitle = 'No delivery fee on all stores',
      code = 'FREEDEL'
  where sort_order = 2;
