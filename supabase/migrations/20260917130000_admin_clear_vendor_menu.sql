-- Empties a store's whole catalogue in one call.
--
-- A menu imported from the wrong source, or against the wrong shop, leaves an
-- operator deleting a few hundred items by hand. This is the undo for that.
--
-- Deliberately one statement per table rather than a loop: the whole thing is
-- one transaction, so the menu is either gone or untouched, never half of it.
-- Deleting a product cascades to its option groups and options; order_items
-- keep their snapshot of the name and price and only lose the link, so order
-- history and every settled figure survive intact. Live carts holding one of
-- these products do lose those lines — the product genuinely no longer exists
-- to be bought.
create or replace function public.admin_clear_vendor_menu(p_vendor_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_products int;
  v_categories int;
begin
  -- Not is_vendor_owner: this is an operator's tool, and a shop that wants
  -- its own menu gone can delete its sections in its own editor.
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;
  if not exists (select 1 from public.vendors where id = p_vendor_id) then
    raise exception 'NOT_FOUND';
  end if;

  with removed as (
    delete from public.products where vendor_id = p_vendor_id returning 1
  )
  select count(*) into v_products from removed;

  with removed as (
    delete from public.product_categories
    where vendor_id = p_vendor_id returning 1
  )
  select count(*) into v_categories from removed;

  -- Emptying a shop's catalogue is not something that should be deniable.
  perform public.log_admin_action(
    'vendor.clear_menu',
    'vendor',
    p_vendor_id,
    jsonb_build_object('products', v_products, 'categories', v_categories)
  );

  return jsonb_build_object(
    'products_deleted', v_products,
    'categories_deleted', v_categories
  );
end;
$$;

revoke execute on function public.admin_clear_vendor_menu(uuid) from anon;
grant execute on function public.admin_clear_vendor_menu(uuid) to authenticated;
