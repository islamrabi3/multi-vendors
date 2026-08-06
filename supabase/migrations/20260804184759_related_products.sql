-- "Goes well with", from what people actually order together.
--
-- Ranked by real co-occurrence first: two items that keep appearing on the
-- same order are a better suggestion than two items that happen to share a
-- menu section. Same-section items fill the rest, so a brand-new store with no
-- order history still gets sensible suggestions instead of an empty strip.
create or replace function public.related_products(
  p_product_id uuid,
  p_limit int default 6
)
returns table (
  id uuid,
  name text,
  name_ar text,
  image_url text,
  price numeric,
  bought_together int
)
language sql
stable
security definer
set search_path = public
as $$
  with source as (
    select p.id, p.vendor_id, p.category_id
    from public.products p
    join public.vendors v on v.id = p.vendor_id
    where p.id = p_product_id
      and v.is_active
      and v.approval_status = 'active'
  ),
  -- Every other item that has shared an order with this one.
  together as (
    select other.product_id, count(*)::int as n
    from public.order_items mine
    join public.order_items other
      on other.order_id = mine.order_id
     and other.product_id <> mine.product_id
    join public.orders o on o.id = mine.order_id
    where mine.product_id = p_product_id
      -- Cancelled orders say nothing about what goes together.
      and o.status not in ('cancelled', 'rejected')
    group by other.product_id
  )
  select p.id, p.name, p.name_ar, p.image_url, p.price,
         coalesce(t.n, 0) as bought_together
  from public.products p
  join source s on s.vendor_id = p.vendor_id
  left join together t on t.product_id = p.id
  where p.id <> p_product_id
    and p.is_available
    -- Keep it to things that are genuinely related: ordered alongside, or at
    -- least from the same part of the menu.
    and (t.n is not null or p.category_id is not distinct from s.category_id)
  order by coalesce(t.n, 0) desc, p.sort_order, p.price
  limit greatest(1, least(p_limit, 12));
$$;

grant execute on function public.related_products(uuid, int) to anon, authenticated;

-- The join above pivots on order_id; without this it is a sequential scan of
-- every order line on the platform for each product sheet opened.
create index if not exists order_items_order_product_idx
  on public.order_items (order_id, product_id);
create index if not exists order_items_product_idx
  on public.order_items (product_id);
