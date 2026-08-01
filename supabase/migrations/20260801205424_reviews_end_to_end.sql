-- Reviews, end to end.
--
-- A customer could already leave a rating and it moved the store's average,
-- but nothing else in the platform used it: no one could read a review back —
-- not the next customer, not the store it was about, not an admin — the
-- driver could not be rated at all, and the same order could be reviewed
-- repeatedly, each time moving the average again.

-- ---------------------------------------------------------------------------
-- 1. One review per order.
-- ---------------------------------------------------------------------------
create unique index if not exists reviews_order_unique on public.reviews (order_id);

-- ---------------------------------------------------------------------------
-- 2. A single insert policy.
--
-- There were two, and RLS ORs permissive policies together: the one that
-- checked the order was delivered was cancelled out by the one that did not,
-- so an order could be reviewed the moment it was placed. This is the two of
-- them merged, which is what both were separately trying to say.
-- ---------------------------------------------------------------------------
drop policy if exists reviews_insert_own on public.reviews;
drop policy if exists reviews_insert_own_delivered on public.reviews;
create policy reviews_insert_own on public.reviews
  for insert to authenticated
  with check (
    customer_id = auth.uid()
    and not public.is_blocked()
    and exists (
      select 1 from public.orders o
      where o.id = reviews.order_id
        and o.customer_id = auth.uid()
        and o.status = 'delivered'
    )
  );

-- A customer may correct their own review; the rating is recomputed either
-- way, so an edit cannot inflate an average.
drop policy if exists reviews_update_own on public.reviews;
create policy reviews_update_own on public.reviews
  for update to authenticated
  using (customer_id = auth.uid() and not public.is_blocked())
  with check (customer_id = auth.uid());

-- ---------------------------------------------------------------------------
-- 3. Rating the driver.
--
-- Separate columns rather than a separate table: it is the same act, on the
-- same screen, about the same order, and a customer who liked the food and
-- not the delivery has to be able to say so.
-- ---------------------------------------------------------------------------
alter table public.reviews
  add column if not exists driver_id uuid references public.profiles(id),
  add column if not exists driver_rating int
    check (driver_rating is null or driver_rating between 1 and 5),
  add column if not exists driver_comment text;

alter table public.drivers
  add column if not exists rating_avg numeric(3,2) not null default 0,
  add column if not exists rating_count integer not null default 0;

-- ---------------------------------------------------------------------------
-- 4. Averages that cannot drift.
--
-- The old trigger folded each new rating into the running average by hand and
-- only fired on insert, so an edited or deleted review left the store holding
-- a number no set of reviews adds up to. Recomputing from the rows is a few
-- microseconds on any realistic review count and is always right.
-- ---------------------------------------------------------------------------
create or replace function public.recompute_vendor_rating(p_vendor_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.vendors v
  set rating_avg = coalesce(agg.avg_rating, 0),
      rating_count = coalesce(agg.n, 0)
  from (
    select round(avg(rating)::numeric, 2) as avg_rating, count(*) as n
    from public.reviews where vendor_id = p_vendor_id
  ) agg
  where v.id = p_vendor_id;
$$;

create or replace function public.recompute_driver_rating(p_driver_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.drivers d
  set rating_avg = coalesce(agg.avg_rating, 0),
      rating_count = coalesce(agg.n, 0)
  from (
    select round(avg(driver_rating)::numeric, 2) as avg_rating, count(*) as n
    from public.reviews
    where driver_id = p_driver_id and driver_rating is not null
  ) agg
  where d.id = p_driver_id;
$$;

create or replace function public.apply_review_to_vendor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.recompute_vendor_rating(
    coalesce(new.vendor_id, old.vendor_id));

  -- Both sides on an update: a customer can move a review from one driver to
  -- another only by the order changing hands, but the delete path needs the
  -- old id and this covers all three.
  if tg_op = 'UPDATE' and old.driver_id is distinct from new.driver_id
     and old.driver_id is not null then
    perform public.recompute_driver_rating(old.driver_id);
  end if;
  if coalesce(new.driver_id, old.driver_id) is not null then
    perform public.recompute_driver_rating(
      coalesce(new.driver_id, old.driver_id));
  end if;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_reviews_apply on public.reviews;
create trigger trg_reviews_apply
  after insert or update or delete on public.reviews
  for each row execute function public.apply_review_to_vendor();

-- Bring every store in line with the rows that actually exist; the old
-- incremental average has been running for a while.
update public.vendors v
set rating_avg = coalesce(agg.avg_rating, 0),
    rating_count = coalesce(agg.n, 0)
from (
  select vendor_id, round(avg(rating)::numeric, 2) as avg_rating, count(*) as n
  from public.reviews group by vendor_id
) agg
where v.id = agg.vendor_id;

-- ---------------------------------------------------------------------------
-- 5. Reading reviews back.
--
-- `reviews` is world-readable, but the reviewer's name lives in `profiles`,
-- which is not — so a plain select returns a wall of anonymous rows. This
-- returns the display name only, and never the reviewer's id, phone or email.
-- ---------------------------------------------------------------------------
create or replace function public.vendor_reviews(
  p_vendor_id uuid,
  p_limit int default 20,
  p_offset int default 0
)
returns table (
  id uuid,
  rating int,
  comment text,
  created_at timestamptz,
  customer_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select r.id,
         r.rating,
         r.comment,
         r.created_at,
         -- A deleted account is scrubbed to 'Deleted user'; showing that on a
         -- review is worse than showing nothing.
         case
           when p.deleted_at is not null then null
           else nullif(trim(p.full_name), '')
         end as customer_name
  from public.reviews r
  left join public.profiles p on p.id = r.customer_id
  where r.vendor_id = p_vendor_id
  order by r.created_at desc
  limit greatest(1, least(p_limit, 50)) offset greatest(0, p_offset);
$$;

grant execute on function public.vendor_reviews(uuid, int, int)
  to anon, authenticated;

-- The store's own inbox: the same rows, plus the order they came from, for
-- the vendor and for admins. A vendor that cannot read its own feedback has
-- no way to act on it.
create or replace function public.my_vendor_reviews(
  p_vendor_id uuid,
  p_limit int default 30,
  p_offset int default 0
)
returns table (
  id uuid,
  order_id uuid,
  rating int,
  comment text,
  created_at timestamptz,
  customer_name text
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_vendor_owner(p_vendor_id) and not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  return query
    select r.id, r.order_id, r.rating, r.comment, r.created_at,
           case
             when p.deleted_at is not null then null
             else nullif(trim(p.full_name), '')
           end
    from public.reviews r
    left join public.profiles p on p.id = r.customer_id
    where r.vendor_id = p_vendor_id
    order by r.created_at desc
    limit greatest(1, least(p_limit, 100)) offset greatest(0, p_offset);
end;
$$;

revoke execute on function public.my_vendor_reviews(uuid, int, int)
  from public, anon;
grant execute on function public.my_vendor_reviews(uuid, int, int)
  to authenticated;

-- How the ratings break down, for the summary bar on a store page.
create or replace function public.vendor_rating_breakdown(p_vendor_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'total', count(*),
    'average', coalesce(round(avg(rating)::numeric, 2), 0),
    'five', count(*) filter (where rating = 5),
    'four', count(*) filter (where rating = 4),
    'three', count(*) filter (where rating = 3),
    'two', count(*) filter (where rating = 2),
    'one', count(*) filter (where rating = 1)
  )
  from public.reviews where vendor_id = p_vendor_id;
$$;

grant execute on function public.vendor_rating_breakdown(uuid)
  to anon, authenticated;

create index if not exists reviews_vendor_created_idx
  on public.reviews (vendor_id, created_at desc);
create index if not exists reviews_driver_idx
  on public.reviews (driver_id) where driver_id is not null;
