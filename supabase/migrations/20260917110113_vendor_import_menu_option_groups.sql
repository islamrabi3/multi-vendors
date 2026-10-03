-- Imported menus keep their sizes and toppings as real options.
--
-- The importer could only create a product with one price, so a pizza sold in
-- three sizes arrived either three times over or once with
-- "صغير 120 · وسط 145 · كبير 165" pushed into its description — legible, but
-- the customer could not choose a size and every size but the cheapest was
-- charged wrong. An item may now carry `option_groups`, which become the same
-- product_option_groups and product_options the store's own editor creates.
create or replace function public.vendor_import_menu(p_vendor_id uuid, p_menu jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $function$
declare
  v_category jsonb;
  v_item jsonb;
  v_group jsonb;
  v_option jsonb;
  v_category_id uuid;
  v_product_id uuid;
  v_group_id uuid;
  v_name text;
  v_name_ar text;
  v_item_name text;
  v_item_name_ar text;
  v_group_name text;
  v_option_name text;
  v_price numeric;
  v_sort int;
  v_item_sort int;
  v_group_sort int;
  v_option_count int;
  v_categories_added int := 0;
  v_items_added int := 0;
  v_options_added int := 0;
begin
  if not (public.is_vendor_owner(p_vendor_id) or public.is_admin()) then
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
    v_name_ar := nullif(trim(coalesce(v_category->>'name_ar', '')), '');
    -- An Arabic-only menu still needs a usable canonical name.
    if v_name = '' then v_name := coalesce(v_name_ar, ''); end if;
    if v_name = '' then continue; end if;

    select id into v_category_id
    from public.product_categories
    where vendor_id = p_vendor_id
      and (lower(name) = lower(v_name)
           or (v_name_ar is not null and name_ar = v_name_ar))
    limit 1;

    if v_category_id is null then
      v_sort := v_sort + 1;
      insert into public.product_categories (vendor_id, name, name_ar, sort_order)
      values (p_vendor_id, v_name, v_name_ar, v_sort)
      returning id into v_category_id;
      v_categories_added := v_categories_added + 1;
    elsif v_name_ar is not null then
      update public.product_categories
      set name_ar = coalesce(name_ar, v_name_ar)
      where id = v_category_id;
    end if;

    select coalesce(max(sort_order), 0) into v_item_sort
    from public.products
    where vendor_id = p_vendor_id and category_id = v_category_id;

    for v_item in select * from jsonb_array_elements(v_category->'items')
    loop
      v_item_name := trim(coalesce(v_item->>'name', ''));
      v_item_name_ar := nullif(trim(coalesce(v_item->>'name_ar', '')), '');
      if v_item_name = '' then v_item_name := coalesce(v_item_name_ar, ''); end if;
      if v_item_name = '' then continue; end if;

      -- Skip items the vendor already has in this section.
      if exists (
        select 1 from public.products
        where vendor_id = p_vendor_id
          and category_id = v_category_id
          and (lower(name) = lower(v_item_name)
               or (v_item_name_ar is not null and name_ar = v_item_name_ar))
      ) then continue; end if;

      v_price := coalesce(nullif(v_item->>'price', '')::numeric, 0);
      if v_price < 0 then v_price := 0; end if;

      v_item_sort := v_item_sort + 1;
      insert into public.products
        (vendor_id, category_id, name, name_ar, description, description_ar,
         price, is_available, sort_order)
      values
        (p_vendor_id, v_category_id, v_item_name, v_item_name_ar,
         nullif(trim(coalesce(v_item->>'description', '')), ''),
         nullif(trim(coalesce(v_item->>'description_ar', '')), ''),
         v_price, true, v_item_sort)
      returning id into v_product_id;
      v_items_added := v_items_added + 1;

      -- Sizes, toppings, sauces: the choices the menu offered on this item.
      if jsonb_typeof(v_item->'option_groups') = 'array' then
        v_group_sort := 0;
        for v_group in select * from jsonb_array_elements(v_item->'option_groups')
        loop
          v_group_name := trim(coalesce(v_group->>'name', ''));
          if v_group_name = '' then continue; end if;
          if jsonb_typeof(v_group->'options') <> 'array' then continue; end if;

          select count(*) into v_option_count
          from jsonb_array_elements(v_group->'options') o
          where trim(coalesce(o->>'name', '')) <> '';
          -- A group with nothing to choose from is a heading, not a choice.
          if v_option_count = 0 then continue; end if;

          v_group_sort := v_group_sort + 1;
          insert into public.product_option_groups
            (product_id, name, min_select, max_select, sort_order)
          values (
            v_product_id,
            v_group_name,
            -- Never ask for more choices than the group can offer, and never
            -- cap it below what it requires: either makes the item
            -- unorderable, and place_order enforces both.
            least(greatest(coalesce((v_group->>'min_select')::int, 0), 0), v_option_count),
            least(greatest(coalesce((v_group->>'max_select')::int, 1), 1), v_option_count),
            v_group_sort
          )
          returning id into v_group_id;

          for v_option in select * from jsonb_array_elements(v_group->'options')
          loop
            v_option_name := trim(coalesce(v_option->>'name', ''));
            if v_option_name = '' then continue; end if;
            insert into public.product_options (group_id, name, price_delta, is_available)
            values (
              v_group_id,
              v_option_name,
              -- A negative delta would let an option discount the item, which
              -- no menu means and a crafted import could abuse.
              greatest(coalesce(nullif(v_option->>'price_delta', '')::numeric, 0), 0),
              true
            );
            v_options_added := v_options_added + 1;
          end loop;
        end loop;
      end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'categories_added', v_categories_added,
    'items_added', v_items_added,
    'options_added', v_options_added
  );
end;
$function$;
