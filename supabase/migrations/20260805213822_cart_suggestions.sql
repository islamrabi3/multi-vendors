-- "You might also like", for the cart.
--
-- related_products answers "what goes with this one item". A cart is a basket,
-- and the two differ in the ways that matter here: the ranking should consider
-- everything already in it, and nothing already in it should be suggested back.
--
-- SECURITY DEFINER because the ranking reads order_items, which a customer
-- cannot see beyond their own orders. Only product columns are returned -- no
-- order, no customer, no counts that reveal another person's basket.
create or replace function public.cart_suggestions(
  p_vendor_id uuid,
  p_exclude uuid[] default '{}',
  p_limit int default 8
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
set search_path to 'public'
as $$
  -- Items that have shared an order with anything currently in the cart.
  with together as (
    select other.product_id, count(*)::int as n
      from public.order_items mine
      join public.order_items other
        on other.order_id = mine.order_id
       and other.product_id <> mine.product_id
      join public.orders o on o.id = mine.order_id
     where mine.product_id = any(coalesce(p_exclude, '{}'::uuid[]))
       -- A cancelled order says nothing about what goes together.
       and o.status not in ('cancelled', 'rejected')
     group by other.product_id
  ),
  -- Fallback for a store with no order history, so the section is not empty on
  -- a new store.
  popular as (
    select oi.product_id, count(*)::int as n
      from public.order_items oi
      join public.orders o on o.id = oi.order_id
     where o.vendor_id = p_vendor_id
       and o.status not in ('cancelled', 'rejected')
     group by oi.product_id
  )
  select p.id, p.name, p.name_ar, p.image_url, p.price,
         coalesce(t.n, 0) as bought_together
    from public.products p
    join public.vendors v on v.id = p.vendor_id
    left join together t on t.product_id = p.id
    left join popular pop on pop.product_id = p.id
   where p.vendor_id = p_vendor_id
     and p.is_available
     and v.is_active
     and v.approval_status = 'active'
     and not (p.id = any(coalesce(p_exclude, '{}'::uuid[])))
   order by coalesce(t.n, 0) desc,
            coalesce(pop.n, 0) desc,
            p.sort_order,
            p.price
   limit greatest(1, least(p_limit, 12));
$$;

revoke execute on function public.cart_suggestions(uuid, uuid[], int) from public;
grant execute on function public.cart_suggestions(uuid, uuid[], int)
  to anon, authenticated, service_role;
