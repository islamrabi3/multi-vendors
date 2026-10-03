-- The codes on the home page, filtered to the customer looking at them.
--
-- The list used to show every live public code, so a one-per-customer code
-- stayed on the home page after it had been spent — an offer the customer
-- could only be refused. The rules here are the same ones
-- compute_coupon_discount enforces at checkout, so a code that shows can
-- always be used.
create or replace function public.my_public_coupons()
returns setof public.coupons
language sql
stable
security definer
set search_path = public
as $$
  select c.*
  from public.coupons c
  where c.is_active
    and c.is_public
    -- Store codes belong on that store's page, not on the home page.
    and c.vendor_id is null
    and (c.starts_at is null or c.starts_at <= now())
    and (c.expires_at is null or c.expires_at > now())
    and (c.usage_limit is null or c.used_count < c.usage_limit)
    -- Already spent by this customer as many times as they may.
    and (
      c.per_user_limit is null
      or (
        select count(*) from public.coupon_redemptions r
        where r.coupon_id = c.id and r.user_id = auth.uid()
      ) < c.per_user_limit
    )
    -- A welcome offer disappears the moment there is a served order.
    and (
      not c.first_order_only
      or not exists (
        select 1 from public.orders o
        where o.customer_id = auth.uid() and o.status = 'delivered'
      )
    )
  order by c.created_at desc;
$$;

revoke all on function public.my_public_coupons() from public, anon;
grant execute on function public.my_public_coupons() to authenticated;
