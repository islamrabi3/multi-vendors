-- Card (paymob) orders awaiting payment are drafts: RLS already hides them
-- from vendors and drivers, and the admin app hides them from its order
-- lists. The dashboard stats must not count them either, or "orders today" /
-- GMV / attention counts include orders that may never be paid.

create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when public.is_admin() then jsonb_build_object(
    'gmv_today', coalesce((
      select sum(total) from public.orders
      where status not in ('cancelled', 'rejected')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at >= date_trunc('day', now())), 0),
    'orders_today', (
      select count(*) from public.orders
      where status not in ('cancelled', 'rejected')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at >= date_trunc('day', now())),
    'vendors_active', (
      select count(*) from public.vendors where approval_status = 'active'),
    'vendors_open', (
      select count(*) from public.vendors
      where approval_status = 'active' and is_open),
    'vendors_pending', (
      select count(*) from public.vendors where approval_status = 'pending'),
    'drivers_online', (
      select count(*) from public.drivers where is_online),
    'orders_attention', (
      select count(*) from public.orders
      where status in ('pending', 'accepted', 'preparing', 'ready_for_pickup')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at < now() - interval '30 minutes')
  ) else jsonb_build_object() end;
$$;
