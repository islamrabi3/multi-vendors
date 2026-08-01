-- Search that finds food, not just shop signs.
--
-- The customer search was `vendors.name ilike '%q%'` and nothing else, so
-- typing "burger" found a store called Burger Lab and missed every restaurant
-- that sells one. Nothing searched the menu, and nothing searched Arabic.
create extension if not exists pg_trgm;

-- Trigram indexes turn the leading-wildcard ILIKE below into an index scan;
-- without them this gets slower with every store and item added.
create index if not exists vendors_name_trgm_idx
  on public.vendors using gin (name gin_trgm_ops);
create index if not exists products_name_trgm_idx
  on public.products using gin (name gin_trgm_ops);
create index if not exists products_name_ar_trgm_idx
  on public.products using gin (name_ar gin_trgm_ops);

-- Stores matching a query by their own name or by something on their menu.
--
-- Security definer keeps the plan stable across the joins; every row returned
-- is one `vendors_read` already makes public, and the same active / approved /
-- owner-not-blocked conditions are repeated here rather than assumed.
create or replace function public.search_vendors(
  p_query text,
  p_category_id uuid default null,
  p_limit int default 40
)
returns table (
  id uuid,
  matched_products text[]
)
language sql
stable
security definer
set search_path = public
as $$
  with needle as (
    select '%' || trim(coalesce(p_query, '')) || '%' as pattern
  ),
  matches as (
    select v.id,
           -- What on the menu matched, so the card can say *why* it is here.
           array_remove(array_agg(distinct p.name) filter (
             where p.name ilike (select pattern from needle)
                or p.name_ar ilike (select pattern from needle)
           ), null) as matched_products,
           bool_or(
             p.name ilike (select pattern from needle)
             or p.name_ar ilike (select pattern from needle)
           ) as product_match
    from public.vendors v
    left join public.products p
      on p.vendor_id = v.id and p.is_available
    where v.is_active
      and v.approval_status = 'active'
      and public.is_owner_active(v.owner_id)
      and (p_category_id is null or v.category_id = p_category_id)
    group by v.id
  )
  select m.id,
         -- Three examples is enough to explain a match; the rest would be a
         -- wall of text on a card.
         m.matched_products[1:3]
  from matches m
  join public.vendors v on v.id = m.id
  where trim(coalesce(p_query, '')) = ''
     or v.name ilike (select pattern from needle)
     or coalesce(m.product_match, false)
  order by
    -- A store whose own name matches is what the customer meant; one that
    -- merely stocks the item comes after it.
    (v.name ilike (select pattern from needle)) desc,
    v.is_open desc,
    v.rating_avg desc
  limit greatest(1, least(p_limit, 60));
$$;

grant execute on function public.search_vendors(text, uuid, int)
  to anon, authenticated;

-- Individual dishes, for the "items" half of a search result.
create or replace function public.search_products(
  p_query text,
  p_limit int default 30
)
returns table (
  id uuid,
  vendor_id uuid,
  vendor_name text,
  name text,
  name_ar text,
  image_url text,
  price numeric
)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.vendor_id, v.name, p.name, p.name_ar, p.image_url, p.price
  from public.products p
  join public.vendors v on v.id = p.vendor_id
  where p.is_available
    and v.is_active
    and v.approval_status = 'active'
    and public.is_owner_active(v.owner_id)
    and trim(coalesce(p_query, '')) <> ''
    and (p.name ilike '%' || trim(p_query) || '%'
         or p.name_ar ilike '%' || trim(p_query) || '%')
  order by v.is_open desc, v.rating_avg desc, p.price
  limit greatest(1, least(p_limit, 50));
$$;

grant execute on function public.search_products(text, int) to anon, authenticated;
