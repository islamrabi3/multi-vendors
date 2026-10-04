-- Cancelling a card payment emptied the customer's basket.
--
-- `place_order` deletes the cart the moment the order row is written, which
-- is right for an order that completes. But a Paymob order is created
-- *before* the customer has paid, and closing the payment page calls
-- `discard_unpaid_order` — which deleted the order and rolled the coupon
-- back, and left the cart destroyed. The customer returned to a checkout
-- that said their basket was empty, with the items nowhere to be found.
--
-- Discarding now genuinely undoes the order: the cart is rebuilt from the
-- order's own lines before the order is removed.

create or replace function public.discard_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_order public.orders%rowtype;
  v_cart_id uuid;
begin
  select * into v_order
  from public.orders
  where id = p_order_id and customer_id = auth.uid()
  for update;

  if not found then
    return false;
  end if;
  if v_order.payment_status = 'paid' then
    return false;
  end if;
  if v_order.status <> 'pending' then
    return false;
  end if;

  if v_order.coupon_id is not null then
    update public.coupons
    set used_count = greatest(used_count - 1, 0)
    where id = v_order.coupon_id;
  end if;

  -- Put the basket back. A customer who has started a new cart for a
  -- different store since placing this one keeps that cart untouched: one
  -- cart per user, and silently replacing a newer basket with an older one
  -- would be its own bug.
  select id into v_cart_id from public.carts where user_id = v_order.customer_id;

  if v_cart_id is null then
    insert into public.carts (user_id, vendor_id)
    values (v_order.customer_id, v_order.vendor_id)
    returning id into v_cart_id;

    -- product_id is nullable on order_items: a line whose product has since
    -- been deleted cannot go back in a cart, so it is skipped rather than
    -- blocking the restore of everything else.
    insert into public.cart_items
      (cart_id, product_id, quantity, selected_options)
    select v_cart_id, oi.product_id, oi.quantity, oi.selected_options
    from public.order_items oi
    where oi.order_id = p_order_id
      and oi.product_id is not null;
  end if;

  delete from public.orders where id = p_order_id;
  return true;
end;
$function$;;
