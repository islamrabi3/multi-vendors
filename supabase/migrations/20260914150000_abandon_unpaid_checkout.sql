-- Backing out of Paymob left the customer with an empty cart.
--
-- place_order empties the server cart. Closing the Paymob page is meant to
-- undo that through discard_unpaid_order, but by then the checkout already
-- has a pending payment intent, and discard refused to touch an order with one
-- (so a payment still on the wire could land). Nothing was undone: the cart
-- stayed empty on the server while the app still showed the items, and the
-- next "pay" failed with CART_EMPTY. Even without a pending intent, deleting
-- the order broke on payment_intents_order_required, since the intent's
-- order_id is set null on delete.
--
-- Now an order that has been sent to Paymob is abandoned instead of deleted:
-- cancelled quietly, its stock, coupon use and cart given back, and its open
-- intents closed as CUSTOMER_CANCELLED. If Paymob does report a payment for
-- such an intent later, the money goes to the customer's in-app wallet rather
-- than disappearing, because the basket has already been returned to them.

create or replace function public.discard_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
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

  -- Serialise with settle_payment_intent: a payment that settles first wins,
  -- and this sees the order as paid above on the next call.
  perform 1 from public.payment_intents
  where order_id = p_order_id
  for update;

  if v_order.coupon_id is not null then
    update public.coupons
    set used_count = greatest(used_count - 1, 0)
    where id = v_order.coupon_id;
  end if;

  perform public.restore_order_stock(p_order_id);
  perform public.restore_cart_from_order(p_order_id);

  if exists (select 1 from public.payment_intents where order_id = p_order_id) then
    update public.payment_intents
    set status = 'failed',
        failure_reason = 'CUSTOMER_CANCELLED',
        settled_at = now()
    where order_id = p_order_id and status = 'pending';

    update public.orders
    set status = 'cancelled',
        payment_status = 'failed'
    where id = p_order_id;
  else
    delete from public.orders where id = p_order_id;
  end if;

  return true;
end;
$$;

-- A late success for a checkout the customer already backed out of.
create or replace function public.settle_payment_intent(
  p_reference text,
  p_success boolean,
  p_transaction_id text default null,
  p_failure_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intent public.payment_intents%rowtype;
  v_order_status text;
begin
  select * into v_intent
  from public.payment_intents
  where reference = p_reference
  for update;

  if not found then
    return 'not_found';
  end if;

  -- The customer closed the checkout and got their basket back, but Paymob
  -- did take the money. Keep it for them in the in-app wallet.
  if v_intent.status = 'failed'
     and v_intent.failure_reason = 'CUSTOMER_CANCELLED'
     and p_success then
    update public.payment_intents
    set status = 'paid',
        provider_transaction_id = coalesce(p_transaction_id, provider_transaction_id),
        failure_reason = 'CREDITED_TO_WALLET',
        settled_at = now()
    where id = v_intent.id;

    insert into public.wallets (user_id, balance, updated_at)
    values (v_intent.user_id, v_intent.amount, now())
    on conflict (user_id)
    do update set balance = public.wallets.balance + v_intent.amount,
                  updated_at = now();

    insert into public.wallet_transactions (user_id, type, amount, reference_id, description)
    values (v_intent.user_id, 'refund', v_intent.amount, p_reference,
            'Payment for a cancelled checkout credited to wallet');

    return 'paid';
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
      -- The basket and the stock are given back so a failed payment never
      -- costs the customer their selection or shrinks the shelf, even if
      -- they never reopen the app.
      perform public.restore_order_stock(v_intent.order_id);
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
$$;

-- An abandoned card checkout was never visible to the store, so cancelling
-- it must not announce anything to anyone.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.notify_order_event()'::regprocedure);
  n := replace(d,
    $a$  else
    if new.payment_method = 'paymob'$a$,
    $b$  else
    if new.payment_method = 'paymob'
       and new.payment_status <> 'paid'
       and new.status in ('cancelled', 'rejected') then
      return null;
    end if;

    if new.payment_method = 'paymob'$b$);
  if n = d then
    raise exception 'notify_order_event anchor not found';
  end if;
  execute n;
end
$patch$;
