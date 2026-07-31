-- Bilingual catalogue.
--
-- `name`/`description` stay the canonical (Latin/English) text every existing
-- query already reads, so nothing breaks. The Arabic columns are additive and
-- the app falls back to the canonical text when a translation is missing —
-- important because vendors add items by hand in one language.
alter table public.products
  add column if not exists name_ar text,
  add column if not exists description_ar text;

alter table public.product_categories
  add column if not exists name_ar text;

-- Menu import, now bilingual and admin-callable.
--
-- Admins run the AI menu extraction on a vendor's behalf, so ownership alone
-- is too narrow a check. Categories are still matched by name so a re-import
-- never duplicates a section, and items keep image_url null until someone
-- uploads a real photo.
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
  v_name_ar text;
  v_item_name text;
  v_item_name_ar text;
  v_price numeric;
  v_sort int;
  v_item_sort int;
  v_categories_added int := 0;
  v_items_added int := 0;
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
