-- Everything waiting on a member of staff, in one round trip, for the badges
-- on the admin console. Each count is only returned to someone who can act
-- on it, so a badge never points at a screen the viewer cannot use.
create or replace function public.admin_action_counts()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select case when not public.is_admin() then '{}'::jsonb else
  jsonb_strip_nulls(jsonb_build_object(
    -- Open conversations whose latest message is from the customer: the
    -- ones actually waiting for a reply, not every open thread.
    'support_awaiting', case when public.has_permission('support.handle') then (
      select count(*) from public.support_threads t
      where t.status = 'open'
        and coalesce((
          select m.is_from_admin from public.support_messages m
          where m.thread_id = t.id
          order by m.created_at desc limit 1
        ), false) = false
    ) end,
    'reports_pending', case when public.has_permission('support.handle') then (
      select count(*) from public.customer_reports where status <> 'resolved'
    ) end,
    'vendors_pending', case when public.has_permission('vendors.view') then (
      select count(*) from public.vendors where approval_status = 'pending'
    ) end,
    'drivers_pending', case when public.has_permission('drivers.view') then (
      select count(*) from public.drivers where approval_status = 'pending'
    ) end,
    'settlement_requests', case when public.has_permission('finance.settle') then (
      select count(*) from public.settlements where status = 'pending'
    ) end,
    'deposits_pending', case when public.has_permission('finance.settle') then (
      select count(*) from public.deposit_requests where status = 'pending'
    ) end,
    'orders_attention', case when public.has_permission('orders.view') then (
      select count(*) from public.orders
      where status in ('pending', 'accepted', 'preparing', 'ready_for_pickup')
        and (payment_method <> 'paymob' or payment_status = 'paid')
        and created_at < now() - interval '30 minutes'
    ) end
  )) end;
$$;

revoke all on function public.admin_action_counts() from public, anon;
grant execute on function public.admin_action_counts() to authenticated;

-- Let the badges update live when money requests arrive, like the rest.
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'deposit_requests') then
    alter publication supabase_realtime add table public.deposit_requests;
  end if;
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'settlements') then
    alter publication supabase_realtime add table public.settlements;
  end if;
end $$;
