-- Promo codes that can only be used the number of times they are meant to be.
--
-- The only limit was a global `used_count`, so one customer could redeem the
-- same code on every order they placed: nothing recorded *who* had used it.
-- There was also no start date, no notion of a new-customer offer, and no way
-- to give away delivery. A cancelled order kept its redemption too, quietly
-- burning a use of a limited campaign.

alter type discount_type add value if not exists 'free_delivery';

alter table public.coupons
  -- Campaigns are scheduled, not switched on by hand at midnight.
  add column if not exists starts_at timestamptz,
  -- The fix: null means unlimited, 1 is the sane default for a promo code.
  add column if not exists per_user_limit int default 1
    check (per_user_limit is null or per_user_limit > 0),
  add column if not exists first_order_only boolean not null default false,
  -- Shown to the customer instead of a bare code.
  add column if not exists title text,
  add column if not exists title_ar text,
  -- Lets a campaign be listed on the offers page rather than only work when
  -- typed in exactly.
  add column if not exists is_public boolean not null default false;

-- Existing codes keep the behaviour they were created with, so this migration
-- does not silently tighten a live campaign.
update public.coupons set per_user_limit = null where per_user_limit = 1;

-- Who redeemed what. The per-user rule is unenforceable without it, and it is
-- also the only audit trail of a campaign's cost.
create table if not exists public.coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  -- One redemption per order, enforced: a retried checkout must not count
  -- twice.
  order_id uuid not null unique references public.orders(id) on delete cascade,
  discount numeric(10,2) not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists coupon_redemptions_user_idx
  on public.coupon_redemptions (coupon_id, user_id);

alter table public.coupon_redemptions enable row level security;

drop policy if exists coupon_redemptions_read on public.coupon_redemptions;
create policy coupon_redemptions_read on public.coupon_redemptions
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

-- Written only by place_order, which is security definer.
drop policy if exists coupon_redemptions_admin on public.coupon_redemptions;
create policy coupon_redemptions_admin on public.coupon_redemptions
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- `used_count` becomes a cache of the ledger rather than a number anybody
-- increments by hand, so it cannot drift from what was actually redeemed.
create or replace function public.sync_coupon_used_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.coupons c
  set used_count = (
    select count(*) from public.coupon_redemptions r
    where r.coupon_id = c.id
  )
  where c.id = coalesce(new.coupon_id, old.coupon_id);
  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_sync_coupon_used_count on public.coupon_redemptions;
create trigger trg_sync_coupon_used_count
  after insert or delete on public.coupon_redemptions
  for each row execute function public.sync_coupon_used_count();

-- Backfill the ledger from orders that already carry a coupon, so existing
-- counts and per-user history survive.
insert into public.coupon_redemptions (coupon_id, user_id, order_id, discount)
select o.coupon_id, o.customer_id, o.id, o.discount
from public.orders o
where o.coupon_id is not null
  and o.status not in ('cancelled', 'rejected')
on conflict (order_id) do nothing;

update public.coupons c
set used_count = (
  select count(*) from public.coupon_redemptions r where r.coupon_id = c.id
);

-- A cancelled or rejected order gives the use back. Without this a customer
-- whose order the store refused had spent their one-time code for nothing.
create or replace function public.release_coupon_on_cancel()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status in ('cancelled', 'rejected')
     and old.status is distinct from new.status then
    delete from public.coupon_redemptions where order_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_release_coupon_on_cancel on public.orders;
create trigger trg_release_coupon_on_cancel
  after update of status on public.orders
  for each row execute function public.release_coupon_on_cancel();
