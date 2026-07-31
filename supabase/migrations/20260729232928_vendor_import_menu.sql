-- Bulk menu import: one call creates all sections + items extracted from
-- menu photos. Categories are matched by name (case-insensitive) so a
-- re-import never duplicates sections; items keep image_url null and the
-- app shows its default placeholder until the vendor uploads real photos.
create or replace function public.vendor_import_menu(
  p_vendor_id uuid,
  p_menu jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_category jsonb;
  v_item jsonb;
  v_category_id uuid;
  v_name text;
  v_item_name text;
  v_price numeric;
  v_sort int;
  v_item_sort int;
  v_categories_added int := 0;
  v_items_added int := 0;
begin
  if not public.is_vendor_owner(p_vendor_id) then
    raise exception 'FORBIDDEN';
  end if;
  if p_menu is null or jsonb_typeof(p_menu->'categories') <> 'array' then
    raise exception 'INVALID_MENU';
  end if;

  select coalesce(max(sort_order), 0) into v_sort
  from public.product_categories where vendor_id = p_vendor_id;

  for v_category in select * from jsonb_array_elements(p_menu->'categories')
  loop
    v_name := trim(coalesce(v_category->>'name', ''));
    if v_name = '' then continue; end if;

    select id into v_category_id
    from public.product_categories
    where vendor_id = p_vendor_id and lower(name) = lower(v_name)
    limit 1;

    if v_category_id is null then
      v_sort := v_sort + 1;
      insert into public.product_categories (vendor_id, name, sort_order)
      values (p_vendor_id, v_name, v_sort)
      returning id into v_category_id;
      v_categories_added := v_categories_added + 1;
    end if;

    select coalesce(max(sort_order), 0) into v_item_sort
    from public.products
    where vendor_id = p_vendor_id and category_id = v_category_id;

    for v_item in select * from jsonb_array_elements(v_category->'items')
    loop
      v_item_name := trim(coalesce(v_item->>'name', ''));
      if v_item_name = '' then continue; end if;

      -- Skip items the vendor already has in this section.
      if exists (
        select 1 from public.products
        where vendor_id = p_vendor_id
          and category_id = v_category_id
          and lower(name) = lower(v_item_name)
      ) then continue; end if;

      v_price := coalesce(nullif(v_item->>'price', '')::numeric, 0);
      if v_price < 0 then v_price := 0; end if;

      v_item_sort := v_item_sort + 1;
      insert into public.products
        (vendor_id, category_id, name, description, price,
         is_available, sort_order)
      values
        (p_vendor_id, v_category_id, v_item_name,
         nullif(trim(coalesce(v_item->>'description', '')), ''),
         v_price, true, v_item_sort);
      v_items_added := v_items_added + 1;
    end loop;
  end loop;

  return jsonb_build_object(
    'categories_added', v_categories_added,
    'items_added', v_items_added
  );
end;
$$;

revoke execute on function public.vendor_import_menu(uuid, jsonb)
  from public, anon;
grant execute on function public.vendor_import_menu(uuid, jsonb)
  to authenticated;
