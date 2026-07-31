-- 1. Deleting a coupon must not be blocked by past orders that used it.
--    The order keeps its stored totals/discount; only the reference clears.
alter table public.orders drop constraint if exists orders_coupon_id_fkey;
alter table public.orders
  add constraint orders_coupon_id_fkey
    foreign key (coupon_id) references public.coupons (id) on delete set null;

-- 2. Typed home banners: each carousel item declares what tapping it does.
--    'coupon' -> show the coupon details dialog
--    'vendor' -> open the vendor page
--    'event'  -> show an announcement dialog
alter table public.banners
  add column if not exists banner_type text not null default 'event';

alter table public.banners drop constraint if exists banners_type_check;
alter table public.banners
  add constraint banners_type_check
    check (banner_type in ('coupon', 'vendor', 'event'));

-- Backfill existing rows from the fields they already carry.
update public.banners
set banner_type = case
  when vendor_id is not null then 'vendor'
  when coalesce(code, '') <> '' then 'coupon'
  else 'event'
end;
