-- Closes money-integrity gaps confirmed against the live schema.
--
-- 1. `orders_read` let a vendor/driver see a `wallet` order before the wallet
--    debit ran — its guard was `payment_method <> 'paymob' or paid`, which
--    treats every non-Paymob method as pre-approved. `place_order` inserts
--    the order first and the client debits the wallet in a second call, so a
--    dropped connection between the two left an order visible and workable
--    with nothing ever collected for it.
-- 2. `place_order` priced whatever was in `cart_items` without checking it
--    against the cart's own vendor, and resolved chosen options with no check
--    that they belonged to the product being bought, were available, were
--    picked at most once, or respected their group's min/max. A client that
--    writes `cart_items` directly (RLS lets a customer manage their own cart)
--    could bill a different store's fee schedule, attach another product's
--    option, repeat a discount option to push the price down, or skip a
--    required paid choice.
-- 3. `payment_intents.order_id` cascaded on delete. A card order stuck in a
--    web-view redirect could be deleted by `discard_unpaid_order` while
--    Paymob's webhook was still in flight; the cascade took the intent with
--    it, so a later `settle_payment_intent` call found nothing, and a card
--    already charged had no order, intent or payment row left to reconcile.
-- 4. `discard_unpaid_order` deleted the order without giving back the stock
--    `place_order` had already taken, so every abandoned or failed card
--    checkout on a stock-tracked item shrank the shelf for good.
--    `settle_payment_intent`'s failure branch had the same gap: it leaves the
--    order `pending` on purpose (the header comment explains why), so the
--    cancel trigger that normally restores stock never fires for it either.
-- 5. `reviews_insert_own` checked that the order belonged to the reviewer and
--    was delivered, but not that `vendor_id`/`driver_id` on the review
--    matched that order — one delivered order let a customer review any
--    store or driver. `reviews_update_own` then let those columns be moved
--    to a different store or driver after the fact.

-- 1. Wallet (and any future non-card method) must be paid before it is
--    visible to the store, a driver, or the pool. -1--------------------------
drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
for select
using (
  is_admin()
  or customer_id = (select auth.uid())
  or (
    (payment_method = 'cod' or payment_status = 'paid')
    and (
      driver_id = (select auth.uid())
      or is_vendor_owner(vendor_id)
      or (status = 'ready_for_pickup' and driver_id is null and is_online_driver())
    )
  )
);

-- 2. place_order: cart items must belong to the cart's own vendor, and every
--    chosen option must belong to the product it was chosen on. -----------
create or replace function public.place_order(
  p_address_id uuid,
  p_payment_method payment_method,
  p_coupon_code text default null,
  p_notes text default null,
  p_order_type order_type default 'delivery',
  p_scheduled_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_cart public.carts%rowtype;
  v_vendor public.vendors%rowtype;
  v_address public.addresses%rowtype;
  v_customer public.profiles%rowtype;
  v_item record;
  v_subtotal numeric := 0;
  v_discount numeric := 0;
  v_delivery_fee numeric := 0;
  v_coupon_id uuid;
  v_coupon record;
  v_order_id uuid;
  v_unit_price numeric;
  v_options_snapshot jsonb;
  v_options_delta numeric;
  v_is_pickup boolean := p_order_type = 'pickup';
  v_is_scheduled boolean := p_order_type = 'scheduled';
begin
  if public.is_blocked() then
    raise exception 'ACCOUNT_BLOCKED';
  end if;

  if v_is_scheduled then
    if p_scheduled_at is null then
      raise exception 'SCHEDULE_REQUIRED';
    end if;
    if p_scheduled_at < now() + interval '45 minutes' then
      raise exception 'SCHEDULE_TOO_SOON';
    end if;
    if p_scheduled_at > now() + interval '7 days' then
      raise exception 'SCHEDULE_TOO_FAR';
    end if;
  end if;

  select * into v_cart from public.carts where user_id = auth.uid();
  if not found then
    raise exception 'CART_EMPTY';
  end if;
  if not exists (select 1 from public.cart_items where cart_id = v_cart.id) then
    raise exception 'CART_EMPTY';
  end if;

  select * into v_vendor from public.vendors
  where id = v_cart.vendor_id and is_active and approval_status = 'active';
  if not found then
    raise exception 'VENDOR_CLOSED';
  end if;
  if not v_is_scheduled and not public.vendor_is_open_now(v_vendor.id) then
    raise exception 'VENDOR_CLOSED';
  end if;

  -- The cart names one vendor; every line in it must actually be that
  -- vendor's product. `cart_items` is client-writable, so this cannot be
  -- assumed from how the app is supposed to build the cart.
  if exists (
    select 1
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart.id and p.vendor_id <> v_cart.vendor_id
  ) then
    raise exception 'CART_VENDOR_MISMATCH';
  end if;

  select * into v_address from public.addresses
  where id = p_address_id and user_id = auth.uid();
  if not found then
    raise exception 'ADDRESS_NOT_FOUND';
  end if;

  if not v_is_pickup
     and not public.is_within_service_area(v_address.lat, v_address.lng) then
    raise exception 'OUTSIDE_SERVICE_AREA';
  end if;

  select * into v_customer from public.profiles where id = auth.uid();

  -- Priced and checked. The `for update` on the product row is what makes the
  -- stock check safe: two customers racing for the last unit serialise here.
  for v_item in
    select ci.id, ci.quantity, ci.selected_options, p.id as product_id,
           p.name as product_name, p.price, p.is_available,
           p.track_stock, p.stock_quantity
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart.id
    for update of p
  loop
    if not v_item.is_available then
      raise exception 'PRODUCT_UNAVAILABLE:%', v_item.product_name;
    end if;
    if v_item.track_stock and v_item.stock_quantity < v_item.quantity then
      -- Named so the app can tell the customer which item, and how many are
      -- actually left, rather than a bare failure.
      raise exception 'INSUFFICIENT_STOCK:%:%',
        v_item.product_name, v_item.stock_quantity;
    end if;

    -- Every chosen option must belong to this product's own option groups
    -- and be available — otherwise a client could attach a cheaper or
    -- negative-priced option lifted from another product entirely.
    if exists (
      select 1
      from jsonb_array_elements(v_item.selected_options) sel
      where not exists (
        select 1
        from public.product_options po
        join public.product_option_groups pog on pog.id = po.group_id
        where po.id = (sel ->> 'option_id')::uuid
          and pog.product_id = v_item.product_id
          and po.is_available
      )
    ) then
      raise exception 'INVALID_OPTION_FOR_PRODUCT:%', v_item.product_name;
    end if;

    -- Picked at most once — repeating a discount option's id in the request
    -- would otherwise apply its price delta more than once.
    if (
      select count(*) from jsonb_array_elements(v_item.selected_options)
    ) <> (
      select count(distinct sel ->> 'option_id')
      from jsonb_array_elements(v_item.selected_options) sel
    ) then
      raise exception 'DUPLICATE_OPTION:%', v_item.product_name;
    end if;

    -- Every group on this product must have between min_select and
    -- max_select of its options chosen — catches both a required group left
    -- empty and more picked from one group than it allows.
    if exists (
      select 1
      from public.product_option_groups pog
      left join (
        select po.group_id, count(*) as picked
        from jsonb_array_elements(v_item.selected_options) sel
        join public.product_options po on po.id = (sel ->> 'option_id')::uuid
        group by po.group_id
      ) picks on picks.group_id = pog.id
      where pog.product_id = v_item.product_id
        and (coalesce(picks.picked, 0) < pog.min_select
             or coalesce(picks.picked, 0) > pog.max_select)
    ) then
      raise exception 'OPTION_SELECTION_INVALID:%', v_item.product_name;
    end if;

    select coalesce(sum(po.price_delta), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'option_id', po.id, 'name', po.name, 'price_delta', po.price_delta
           )), '[]'::jsonb)
    into v_options_delta, v_options_snapshot
    from jsonb_array_elements(v_item.selected_options) sel
    join public.product_options po on po.id = (sel ->> 'option_id')::uuid;

    v_unit_price := v_item.price + v_options_delta;
    v_subtotal := v_subtotal + v_unit_price * v_item.quantity;
  end loop;

  if v_subtotal < v_vendor.min_order_amount then
    raise exception 'MIN_ORDER_NOT_MET:%', v_vendor.min_order_amount;
  end if;

  v_delivery_fee := case when v_is_pickup then 0 else v_vendor.delivery_fee end;

  if p_coupon_code is not null and trim(p_coupon_code) <> '' then
    select * into v_coupon
    from public.compute_coupon_discount(
      p_coupon_code, v_vendor.id, v_subtotal, v_delivery_fee, auth.uid());
    v_coupon_id := v_coupon.o_coupon_id;
    v_discount := v_coupon.o_discount;
  end if;

  insert into public.orders (
    customer_id, vendor_id, delivery_address, delivery_lat, delivery_lng,
    subtotal, delivery_fee, discount, total,
    payment_method, payment_status, coupon_id, customer_notes, order_number,
    order_type, scheduled_at, released_at
  ) values (
    auth.uid(), v_vendor.id,
    jsonb_build_object(
      'label', v_address.label, 'street', v_address.street,
      'building', v_address.building, 'floor', v_address.floor,
      'apartment', v_address.apartment, 'notes', v_address.notes,
      'customer_name', v_customer.full_name, 'customer_phone', v_customer.phone
    ),
    v_address.lat, v_address.lng,
    v_subtotal, v_delivery_fee, v_discount,
    greatest(v_subtotal - v_discount + v_delivery_fee, 0),
    p_payment_method, 'unpaid', v_coupon_id, p_notes, '',
    p_order_type,
    case when v_is_scheduled then p_scheduled_at else null end,
    case when v_is_scheduled then null else now() end
  )
  returning id into v_order_id;

  if v_coupon_id is not null then
    insert into public.coupon_redemptions (coupon_id, user_id, order_id, discount)
    values (v_coupon_id, auth.uid(), v_order_id, v_discount);
  end if;

  for v_item in
    select ci.quantity, ci.selected_options, p.id as product_id,
           p.name as product_name, p.price, p.track_stock, p.stock_quantity
    from public.cart_items ci
    join public.products p on p.id = ci.product_id
    where ci.cart_id = v_cart.id
  loop
    select coalesce(sum(po.price_delta), 0),
           coalesce(jsonb_agg(jsonb_build_object(
             'option_id', po.id, 'name', po.name, 'price_delta', po.price_delta
           )), '[]'::jsonb)
    into v_options_delta, v_options_snapshot
    from jsonb_array_elements(v_item.selected_options) sel
    join public.product_options po on po.id = (sel ->> 'option_id')::uuid;

    v_unit_price := v_item.price + v_options_delta;

    insert into public.order_items (
      order_id, product_id, product_name, unit_price, quantity,
      selected_options, line_total
    ) values (
      v_order_id, v_item.product_id, v_item.product_name, v_unit_price,
      v_item.quantity, v_options_snapshot, v_unit_price * v_item.quantity
    );

    -- Stock leaves the shelf when the order is placed, not when it is
    -- delivered: the customer has committed to it and nobody else can have it.
    if v_item.track_stock then
      update public.products
      set stock_quantity = stock_quantity - v_item.quantity
      where id = v_item.product_id;

      insert into public.stock_movements (
        product_id, vendor_id, order_id, delta, quantity_after, reason, created_by
      ) values (
        v_item.product_id, v_vendor.id, v_order_id, -v_item.quantity,
        v_item.stock_quantity - v_item.quantity, 'sale', auth.uid()
      );
    end if;
  end loop;

  delete from public.carts where id = v_cart.id;

  return v_order_id;
end;
$function$;

-- 3. A payment_intent must outlive the order it is settling. -----------------
alter table public.payment_intents
  drop constraint if exists payment_intents_order_id_fkey,
  add constraint payment_intents_order_id_fkey
    foreign key (order_id) references public.orders(id) on delete set null;

-- 4. Stock is only ever restored once per order, from whichever path gets
--    there first (a manual cancel, a discarded draft, or a failed payment). -
alter table public.orders
  add column if not exists stock_restored_at timestamptz;

create or replace function public.restore_order_stock(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_item record;
  v_claimed boolean;
begin
  update public.orders
  set stock_restored_at = now()
  where id = p_order_id and stock_restored_at is null
  returning true into v_claimed;

  if not v_claimed then
    return;
  end if;

  for v_item in
    select oi.product_id, oi.quantity, p.track_stock, p.stock_quantity, p.vendor_id
    from public.order_items oi
    join public.products p on p.id = oi.product_id
    where oi.order_id = p_order_id and p.track_stock
  loop
    update public.products
    set stock_quantity = stock_quantity + v_item.quantity
    where id = v_item.product_id;

    insert into public.stock_movements (
      product_id, vendor_id, order_id, delta, quantity_after, reason
    ) values (
      v_item.product_id, v_item.vendor_id, p_order_id, v_item.quantity,
      v_item.stock_quantity + v_item.quantity, 'order_cancelled'
    );
  end loop;
end;
$function$;

create or replace function public.restore_stock_on_cancel()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.status not in ('cancelled', 'rejected')
     or old.status in ('cancelled', 'rejected') then
    return null;
  end if;
  perform public.restore_order_stock(new.id);
  return null;
end;
$function$;

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

  -- A card payment already on the wire for this order must be allowed to
  -- land: deleting the order out from under it left a charge with no order,
  -- intent, or payment row to reconcile against.
  if exists (
    select 1 from public.payment_intents
    where order_id = p_order_id and status = 'pending'
  ) then
    return false;
  end if;

  if v_order.coupon_id is not null then
    update public.coupons
    set used_count = greatest(used_count - 1, 0)
    where id = v_order.coupon_id;
  end if;

  perform public.restore_order_stock(p_order_id);
  perform public.restore_cart_from_order(p_order_id);

  delete from public.orders where id = p_order_id;
  return true;
end;
$function$;

create or replace function public.settle_payment_intent(
  p_reference text,
  p_success boolean,
  p_transaction_id text default null,
  p_failure_reason text default null
)
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
$function$;

-- 5. A review may only name the store and driver on the delivered order it
--    cites, and cannot be moved to a different one afterwards. --------------
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews
for insert
with check (
  customer_id = (select auth.uid())
  and not is_blocked()
  and exists (
    select 1 from public.orders o
    where o.id = reviews.order_id
      and o.customer_id = (select auth.uid())
      and o.status = 'delivered'
      and o.vendor_id = reviews.vendor_id
      and (reviews.driver_id is null or reviews.driver_id = o.driver_id)
  )
);

create or replace function public.guard_review_target()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon') and (
       new.order_id is distinct from old.order_id
    or new.vendor_id is distinct from old.vendor_id
    or new.driver_id is distinct from old.driver_id
    or new.customer_id is distinct from old.customer_id
  ) then
    raise exception 'REVIEW_TARGET_IMMUTABLE';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_guard_review_target on public.reviews;
create trigger trg_guard_review_target
  before update on public.reviews
  for each row execute function public.guard_review_target();
