-- Restoring the basket cannot depend on the customer coming back.
--
-- `place_order` deletes the cart the moment the order row is written, which
-- is right for an order that completes. But a Paymob order is created
-- *before* the customer has paid, so a failed or abandoned payment used to
-- leave the basket destroyed and nothing to put it back.
--
-- Two paths now restore it:
--   * `discard_unpaid_order`, called by the app when the customer returns
--     from the payment page, and
--   * `settle_payment_intent`, called by the HMAC-verified webhook, which is
--     the one participant that always arrives. Close the tab, kill the app or
--     lose signal on the payment page and the webhook still rescues the cart.
--
-- The logic is extracted rather than copied: two versions of "put the cart
-- back" would drift, and the one that drifts is the one nobody is watching.

create or replace function public.restore_cart_from_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_order public.orders%rowtype;
  v_cart_id uuid;
begin
  select * into v_order from public.orders where id = p_order_id;
  if not found then return; end if;

  -- A customer who has started a new basket since placing this order keeps
  -- it. One cart per user, and replacing a newer basket with an older one
  -- would be its own bug.
  select id into v_cart_id from public.carts where user_id = v_order.customer_id;
  if v_cart_id is not null then return; end if;

  insert into public.carts (user_id, vendor_id)
  values (v_order.customer_id, v_order.vendor_id)
  returning id into v_cart_id;

  -- product_id is nullable on order_items: a line whose product has since
  -- been deleted cannot go back in a cart, so it is skipped rather than
  -- blocking the restore of everything else.
  insert into public.cart_items (cart_id, product_id, quantity, selected_options)
  select v_cart_id, oi.product_id, oi.quantity, oi.selected_options
  from public.order_items oi
  where oi.order_id = p_order_id and oi.product_id is not null;
end;
$$;

revoke execute on function public.restore_cart_from_order(uuid)
  from public, anon, authenticated;

create or replace function public.discard_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order
  from public.orders
  where id = p_order_id and customer_id = auth.uid()
  for update;

  if not found then return false; end if;
  if v_order.payment_status = 'paid' then return false; end if;
  if v_order.status <> 'pending' then return false; end if;

  if v_order.coupon_id is not null then
    update public.coupons
    set used_count = greatest(used_count - 1, 0)
    where id = v_order.coupon_id;
  end if;

  perform public.restore_cart_from_order(p_order_id);

  delete from public.orders where id = p_order_id;
  return true;
end;
$function$;

create or replace function public.settle_payment_intent(
  p_reference text,
  p_success boolean,
  p_transaction_id text default null::text,
  p_failure_reason text default null::text)
returns text
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_intent public.payment_intents%rowtype;
begin
  select * into v_intent
  from public.payment_intents
  where reference = p_reference
  for update;

  if not found then
    return 'not_found';
  end if;

  -- Already settled: replayed callback, do nothing.
  if v_intent.status <> 'pending' then
    return v_intent.status;
  end if;

  if not p_success then
    update public.payment_intents
    set status = 'failed',
        provider_transaction_id = coalesce(p_transaction_id, provider_transaction_id),
        failure_reason = p_failure_reason,
        settled_at = now()
    where id = v_intent.id;

    if v_intent.kind = 'order' then
      update public.orders
      set payment_status = 'failed'
      where id = v_intent.order_id and payment_status <> 'paid';

      -- The order is deliberately left in place: the customer may still be
      -- looking at it, and it is invisible to the restaurant while unpaid.
      -- Only the basket is given back, so a failed payment never costs the
      -- customer their selection even if they never reopen the app.
      perform public.restore_cart_from_order(v_intent.order_id);
    end if;

    return 'failed';
  end if;

  update public.payment_intents
  set status = 'paid',
      provider_transaction_id = coalesce(p_transaction_id, provider_transaction_id),
      settled_at = now()
  where id = v_intent.id;

  if v_intent.kind = 'topup' then
    insert into public.wallets (user_id, balance, updated_at)
    values (v_intent.user_id, v_intent.amount, now())
    on conflict (user_id)
    do update set balance = public.wallets.balance + v_intent.amount,
                  updated_at = now();

    insert into public.wallet_transactions (user_id, type, amount, reference_id, description)
    values (v_intent.user_id, 'deposit', v_intent.amount, p_reference, 'Wallet top-up via Paymob');
  else
    update public.orders
    set payment_status = 'paid'
    where id = v_intent.order_id;
  end if;

  return 'paid';
end;
$function$;
