-- Two-level store categories, and per-category promoted stores.
--
-- The marketplace is no longer food-only: the home page leads with the kind of
-- shop (Food / Groceries / Pharmacies / Stores) and the cuisine-level chips
-- (Burgers, Grills, Pizza…) move underneath their parent. One table with a
-- self-reference rather than two, so an admin can add a level-two entry
-- anywhere without a schema change.
--
-- Depth is capped at two by a trigger: a grandchild would need a breadcrumb,
-- a back-stack, and a different home page, and nothing asked for one.

alter table public.vendor_categories
  add column if not exists parent_id uuid
    references public.vendor_categories (id) on delete cascade,
  add column if not exists name_ar text;

create index if not exists vendor_categories_parent_idx
  on public.vendor_categories (parent_id, sort_order);

create or replace function public.vendor_categories_depth_guard()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.parent_id is not null then
    if new.parent_id = new.id then
      raise exception 'CATEGORY_SELF_PARENT';
    end if;
    if exists (
      select 1 from public.vendor_categories
      where id = new.parent_id and parent_id is not null
    ) then
      raise exception 'CATEGORY_TOO_DEEP';
    end if;
  end if;
  -- Demoting a parent that already has children would orphan the level below.
  if new.parent_id is not null and exists (
    select 1 from public.vendor_categories where parent_id = new.id
  ) then
    raise exception 'CATEGORY_HAS_CHILDREN';
  end if;
  return new;
end;
$$;

drop trigger if exists vendor_categories_depth on public.vendor_categories;
create trigger vendor_categories_depth
  before insert or update of parent_id on public.vendor_categories
  for each row execute function public.vendor_categories_depth_guard();

-- The four top-level kinds. Fixed ids so re-running is a no-op and so the
-- seed data below can point at them.
insert into public.vendor_categories (id, name, name_ar, image_url, sort_order)
values
  ('22222222-0000-0000-0000-000000000001', 'Food', 'مطاعم',
   'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400', 1),
  ('22222222-0000-0000-0000-000000000002', 'Groceries', 'بقالة',
   'https://images.unsplash.com/photo-1542838132-92c53300491e?w=400', 2),
  ('22222222-0000-0000-0000-000000000003', 'Pharmacies', 'صيدليات',
   'https://images.unsplash.com/photo-1587854692152-cbe660dbde88?w=400', 3),
  ('22222222-0000-0000-0000-000000000004', 'Stores', 'متاجر',
   'https://images.unsplash.com/photo-1441986300917-64674bd600d8?w=400', 4)
on conflict (id) do nothing;

-- Everything that existed before this migration was a cuisine, so it becomes a
-- child of Food — except the grocery one, which has an obvious home. Only rows
-- with no parent are touched, so re-running never re-parents anything an admin
-- has since moved.
update public.vendor_categories
   set parent_id = case
     when lower(name) in ('grocery', 'groceries')
       then '22222222-0000-0000-0000-000000000002'::uuid
     else '22222222-0000-0000-0000-000000000001'::uuid
   end
 where parent_id is null
   and id not in (
     '22222222-0000-0000-0000-000000000001',
     '22222222-0000-0000-0000-000000000002',
     '22222222-0000-0000-0000-000000000003',
     '22222222-0000-0000-0000-000000000004'
   );

-- ===========================================================================
-- Promoted stores, per category
-- ===========================================================================
--
-- `vendors.is_recommended` already drives the home page's one rail. This is
-- the same idea scoped to a category page, so "our pick for Pizza" is a
-- different answer from "our pick overall". A store may be promoted in several
-- categories; `rank` orders the rail, low first.

create table if not exists public.category_recommendations (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.vendor_categories (id) on delete cascade,
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  rank int not null default 0,
  created_at timestamptz not null default now(),
  unique (category_id, vendor_id)
);

create index if not exists category_recommendations_category_idx
  on public.category_recommendations (category_id, rank);
create index if not exists category_recommendations_vendor_idx
  on public.category_recommendations (vendor_id);

alter table public.category_recommendations enable row level security;

drop policy if exists category_recommendations_select on public.category_recommendations;
create policy category_recommendations_select on public.category_recommendations
  for select to authenticated, anon using (true);

drop policy if exists category_recommendations_insert on public.category_recommendations;
create policy category_recommendations_insert on public.category_recommendations
  for insert to authenticated
  with check (public.has_permission('catalog.manage'));

drop policy if exists category_recommendations_update on public.category_recommendations;
create policy category_recommendations_update on public.category_recommendations
  for update to authenticated
  using (public.has_permission('catalog.manage'))
  with check (public.has_permission('catalog.manage'));

drop policy if exists category_recommendations_delete on public.category_recommendations;
create policy category_recommendations_delete on public.category_recommendations
  for delete to authenticated
  using (public.has_permission('catalog.manage'));

-- Every store filed under a category, following the tree: asking for a parent
-- returns the stores of all its children too, which is what tapping "Food"
-- has to mean. Ordered the same way the plain store list is — open first,
-- then rating — so the two pages agree.
create or replace function public.vendors_in_category(p_category_id uuid)
returns setof public.vendors
language sql
stable
security definer
set search_path = public
as $$
  select v.*
  from public.vendors v
  where v.is_active
    and v.approval_status = 'active'
    and (
      v.category_id = p_category_id
      or v.category_id in (
        select id from public.vendor_categories where parent_id = p_category_id
      )
    )
  order by v.is_open desc, v.rating_avg desc;
$$;

grant execute on function public.vendors_in_category(uuid) to authenticated, anon;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'category_recommendations'
  ) then
    alter publication supabase_realtime add table public.category_recommendations;
  end if;
end $$;
