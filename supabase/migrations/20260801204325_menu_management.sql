-- Menu management for the vendor app.
--
-- The catalogue could only be created and edited one row at a time: there was
-- no way to order it, and duplicating an item with its option groups meant
-- retyping the lot. Both are the difference between a menu screen and a menu
-- *manager*.

-- ---------------------------------------------------------------------------
-- 1. Ordering.
--
-- `sort_order` existed on both tables and was read by every customer-facing
-- query, but nothing ever wrote it — so a new section or item landed at 0 and
-- the menu came back in whatever order Postgres felt like. These take the
-- whole list and renumber it, which is the only way to keep the result
-- consistent when two rows swap.
-- ---------------------------------------------------------------------------
create or replace function public.vendor_reorder_categories(
  p_vendor_id uuid,
  p_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_vendor_owner(p_vendor_id) then
    raise exception 'FORBIDDEN';
  end if;

  update public.product_categories c
  set sort_order = position.idx
  from unnest(p_ids) with ordinality as position(id, idx)
  where c.id = position.id
    -- Belt and braces: the caller owns the store, but the ids come from a
    -- client and nothing says they belong to it.
    and c.vendor_id = p_vendor_id;
end;
$$;

revoke execute on function public.vendor_reorder_categories(uuid, uuid[])
  from public, anon;
grant execute on function public.vendor_reorder_categories(uuid, uuid[])
  to authenticated;

create or replace function public.vendor_reorder_products(
  p_vendor_id uuid,
  p_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_vendor_owner(p_vendor_id) then
    raise exception 'FORBIDDEN';
  end if;

  update public.products p
  set sort_order = position.idx
  from unnest(p_ids) with ordinality as position(id, idx)
  where p.id = position.id
    and p.vendor_id = p_vendor_id;
end;
$$;

revoke execute on function public.vendor_reorder_products(uuid, uuid[])
  from public, anon;
grant execute on function public.vendor_reorder_products(uuid, uuid[])
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Duplication.
--
-- Menus are full of near-identical items — the same burger in three sizes,
-- the same pizza with four option groups. Copying them client-side would be
-- four round trips with no transaction around them, so a half-copied item
-- would survive a dropped connection.
-- ---------------------------------------------------------------------------
create or replace function public.vendor_duplicate_product(p_product_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_source public.products%rowtype;
  v_new_id uuid;
  v_group record;
  v_new_group_id uuid;
begin
  select * into v_source from public.products where id = p_product_id;
  if not found then
    raise exception 'NOT_FOUND';
  end if;
  if not public.is_vendor_owner(v_source.vendor_id) then
    raise exception 'FORBIDDEN';
  end if;

  -- The copy lands directly after its source and starts unavailable: it is a
  -- draft until the owner has edited the parts that differ, and a duplicate
  -- silently on sale at the same price is worse than no copy at all.
  insert into public.products
    (vendor_id, category_id, name, name_ar, description, description_ar,
     image_url, price, is_available, sort_order)
  values
    (v_source.vendor_id, v_source.category_id,
     v_source.name || ' (copy)',
     case when v_source.name_ar is null then null
          else v_source.name_ar || ' (نسخة)' end,
     v_source.description, v_source.description_ar,
     v_source.image_url, v_source.price, false, v_source.sort_order + 1)
  returning id into v_new_id;

  for v_group in
    select * from public.product_option_groups
    where product_id = p_product_id order by sort_order
  loop
    insert into public.product_option_groups
      (product_id, name, min_select, max_select, sort_order)
    values
      (v_new_id, v_group.name, v_group.min_select, v_group.max_select,
       v_group.sort_order)
    returning id into v_new_group_id;

    insert into public.product_options (group_id, name, price_delta, is_available)
    select v_new_group_id, name, price_delta, is_available
    from public.product_options where group_id = v_group.id;
  end loop;

  return v_new_id;
end;
$$;

revoke execute on function public.vendor_duplicate_product(uuid)
  from public, anon;
grant execute on function public.vendor_duplicate_product(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Bulk availability.
--
-- "We are out of everything in Grills tonight" is one tap, not fifteen.
-- p_category_id null means the whole catalogue.
-- ---------------------------------------------------------------------------
create or replace function public.vendor_set_section_availability(
  p_vendor_id uuid,
  p_category_id uuid,
  p_available boolean
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  if not public.is_vendor_owner(p_vendor_id) then
    raise exception 'FORBIDDEN';
  end if;

  update public.products
  set is_available = p_available
  where vendor_id = p_vendor_id
    and (p_category_id is null or category_id = p_category_id)
    and is_available is distinct from p_available;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.vendor_set_section_availability(uuid, uuid, boolean)
  from public, anon;
grant execute on function public.vendor_set_section_availability(uuid, uuid, boolean)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 4. The catalogue on the wire.
--
-- A customer sitting on a store page held whatever the menu looked like when
-- they opened it: an item sold out mid-browse still went into the cart, and
-- only failed at checkout. Publishing these lets the store page follow the
-- vendor's edits, which is the same guarantee orders already had.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'products'
  ) then
    alter publication supabase_realtime add table public.products;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'product_categories'
  ) then
    alter publication supabase_realtime add table public.product_categories;
  end if;
  -- The store's own row: opening and closing, busy mode, and the prep-time
  -- bump all already write here and none of it reached an open store page.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'vendors'
  ) then
    alter publication supabase_realtime add table public.vendors;
  end if;
end $$;

-- Sections are ordered on every read; without this the sort is a full scan of
-- the store's catalogue each time a customer opens it.
create index if not exists product_categories_vendor_sort_idx
  on public.product_categories (vendor_id, sort_order);
create index if not exists products_vendor_sort_idx
  on public.products (vendor_id, sort_order);
