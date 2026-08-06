-- Open support threads (and pending driver applications) on the dashboard.
--
-- Support was two taps away behind the Manage tab, so a waiting customer was
-- only found by someone who went looking. It belongs with the other "needs
-- attention" counts: a thread nobody has answered is the same kind of debt as
-- an order nobody has moved.
create or replace function public.admin_dashboard_stats()
returns jsonb
language sql
stable
security definer
set search_path to 'public'
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
    'drivers_pending', (
      select count(*) from public.drivers where approval_status = 'pending'),
    'support_open', (
      select count(*) from public.support_threads where status = 'open'),
    'orders_attention', (
      select count(*) from public.orders
      where status in ('pending', 'accepted', 'preparing', 'ready_for_pickup')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at < now() - interval '30 minutes')
  ) else jsonb_build_object() end;
$$;
