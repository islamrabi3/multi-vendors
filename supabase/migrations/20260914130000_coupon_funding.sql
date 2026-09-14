-- Who pays for a store-only promo.
--
-- Until now a coupon scoped to one store was always booked as that store's
-- own marketing spend and deducted from its payout. That is right for a code
-- the store asked for, and wrong for a promo the platform runs on a store's
-- page. The admin now says which.
alter table public.coupons
  add column if not exists funded_by text not null default 'platform'
  check (funded_by in ('platform', 'vendor'));

-- Existing store-scoped codes keep the behaviour they were created under.
update public.coupons set funded_by = 'vendor'
where vendor_id is not null and funded_by = 'platform';

do $patch$
declare
  fn text;
  d text;
  n text;
begin
  foreach fn in array array[
    'public.finance_settle_order(uuid)',
    'public.vendor_settlement(uuid, timestamptz, timestamptz)',
    'public.admin_platform_report(timestamptz, timestamptz, numeric)',
    'public.admin_vendor_sales_report(timestamptz, timestamptz)'
  ] loop
    d := pg_get_functiondef(fn::regprocedure);
    n := replace(d, 'c.vendor_id is not null',
                    '(c.vendor_id is not null and c.funded_by = ''vendor'')');
    n := replace(n, 'c.vendor_id is null',
                    '(c.vendor_id is null or c.funded_by = ''platform'')');
    if n = d then raise exception 'no coupon funding rule found in %', fn; end if;
    execute n;
  end loop;
end
$patch$;
