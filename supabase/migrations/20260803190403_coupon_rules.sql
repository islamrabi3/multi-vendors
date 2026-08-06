-- Every rule a code can carry, checked in one place.
--
-- Each failure raises its own code so the app can say which rule was broken;
-- "this coupon is not valid" for a code that is simply not live yet is the
-- kind of message that generates support tickets.
drop function if exists public.compute_coupon_discount(text, uuid, numeric);

create or replace function public.compute_coupon_discount(
  p_code text,
  p_vendor_id uuid,
  p_subtotal numeric,
  p_delivery_fee numeric default 0,
  p_user_id uuid default null,
  out o_coupon_id uuid,
  out o_discount numeric,
  out o_free_delivery boolean,
  out o_title text
)
returns record
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_coupon public.coupons%rowtype;
  v_user_id uuid := coalesce(p_user_id, auth.uid());
  v_used_by_user int;
  v_orders_placed int;
begin
  select * into v_coupon
  from public.coupons
  where code = upper(trim(p_code));

  -- A code nobody has is indistinguishable from a code that is switched off:
  -- both are "not valid", and saying more would let anyone probe for codes.
  if not found or not v_coupon.is_active then
    raise exception 'COUPON_INVALID';
  end if;

  if v_coupon.starts_at is not null and v_coupon.starts_at > now() then
    raise exception 'COUPON_NOT_STARTED';
  end if;
  if v_coupon.expires_at is not null and v_coupon.expires_at <= now() then
    raise exception 'COUPON_EXPIRED';
  end if;
  if v_coupon.vendor_id is not null and v_coupon.vendor_id <> p_vendor_id then
    raise exception 'COUPON_WRONG_VENDOR';
  end if;
  if v_coupon.usage_limit is not null
     and v_coupon.used_count >= v_coupon.usage_limit then
    raise exception 'COUPON_EXHAUSTED';
  end if;
  if p_subtotal < v_coupon.min_order_amount then
    raise exception 'COUPON_MIN_ORDER:%', v_coupon.min_order_amount;
  end if;

  if v_user_id is not null then
    -- The rule that was missing entirely: how many times *this* customer has
    -- already used it.
    if v_coupon.per_user_limit is not null then
      select count(*) into v_used_by_user
      from public.coupon_redemptions
      where coupon_id = v_coupon.id and user_id = v_user_id;

      if v_used_by_user >= v_coupon.per_user_limit then
        raise exception 'COUPON_ALREADY_USED';
      end if;
    end if;

    if v_coupon.first_order_only then
      -- Counted over orders that were actually served: a cancelled first
      -- attempt should not cost somebody their welcome offer.
      select count(*) into v_orders_placed
      from public.orders
      where customer_id = v_user_id
        and status not in ('cancelled', 'rejected');
      if v_orders_placed > 0 then
        raise exception 'COUPON_FIRST_ORDER_ONLY';
      end if;
    end if;
  end if;

  o_coupon_id := v_coupon.id;
  o_title := coalesce(v_coupon.title, v_coupon.code);
  o_free_delivery := v_coupon.discount_type = 'free_delivery';

  if v_coupon.discount_type = 'percentage' then
    o_discount := round(p_subtotal * v_coupon.value / 100, 2);
    if v_coupon.max_discount is not null then
      o_discount := least(o_discount, v_coupon.max_discount);
    end if;
  elsif v_coupon.discount_type = 'free_delivery' then
    -- Waiving delivery is a discount of exactly the fee, so every total in
    -- the app keeps adding up without a second discount field.
    o_discount := coalesce(p_delivery_fee, 0);
  else
    o_discount := least(v_coupon.value, p_subtotal);
  end if;

  -- Never more than the order is worth.
  o_discount := least(o_discount, p_subtotal + coalesce(p_delivery_fee, 0));
end;
$$;

-- What the checkout screen calls to show the customer what a code is worth.
create or replace function public.preview_coupon(
  p_code text,
  p_vendor_id uuid,
  p_subtotal numeric
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_fee numeric;
  v record;
begin
  select delivery_fee into v_fee from public.vendors where id = p_vendor_id;

  select * into v
  from public.compute_coupon_discount(
    p_code, p_vendor_id, p_subtotal, coalesce(v_fee, 0), auth.uid());

  return jsonb_build_object(
    'discount', v.o_discount,
    'free_delivery', v.o_free_delivery,
    'title', v.o_title
  );
end;
$$;

grant execute on function public.preview_coupon(text, uuid, numeric)
  to authenticated;

-- Kept so nothing that still calls it breaks; it simply loses the delivery
-- half of a free-delivery code, which it never understood anyway.
create or replace function public.validate_coupon(
  p_code text,
  p_vendor_id uuid,
  p_subtotal numeric
)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v record;
  v_fee numeric;
begin
  select delivery_fee into v_fee from public.vendors where id = p_vendor_id;
  select * into v from public.compute_coupon_discount(
    p_code, p_vendor_id, p_subtotal, coalesce(v_fee, 0), auth.uid());
  return v.o_discount;
end;
$$;
