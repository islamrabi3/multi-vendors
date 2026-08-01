-- Platform-level settlement figures.
--
-- The vendor and driver reports say what each party is owed; nothing said what
-- the platform itself took, or — more importantly for a cash market — how much
-- of it is sitting in drivers' pockets as COD rather than in the bank.
create or replace function public.admin_platform_report(
  p_start timestamptz default null,
  p_end timestamptz default null,
  p_driver_share numeric default 90
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v jsonb;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  select jsonb_build_object(
    'delivered_orders', count(*) filter (where o.status = 'delivered'),
    'cancelled_orders', count(*) filter (where o.status in ('cancelled', 'rejected')),
    'gross_revenue', round(coalesce(sum(o.total) filter (where o.status = 'delivered'), 0), 2),
    'item_sales', round(coalesce(sum(o.subtotal) filter (where o.status = 'delivered'), 0), 2),
    'delivery_fees', round(coalesce(sum(o.delivery_fee) filter (where o.status = 'delivered'), 0), 2),
    'discounts', round(coalesce(sum(o.discount) filter (where o.status = 'delivered'), 0), 2),
    -- Commission is per-store, so it is summed from the vendor rate rather
    -- than a flat platform percentage.
    'commission', round(coalesce(sum(
        o.subtotal * coalesce(vn.commission_rate, 10) / 100.0
      ) filter (where o.status = 'delivered'), 0), 2),
    'driver_cost', round(coalesce(sum(
        o.delivery_fee * p_driver_share / 100.0 + coalesce(o.driver_tip, 0)
      ) filter (where o.status = 'delivered'), 0), 2),
    -- Cash the drivers physically hold and still owe the platform.
    'cash_collected', round(coalesce(sum(o.total) filter (
        where o.status = 'delivered' and o.payment_method = 'cod'), 0), 2),
    'card_collected', round(coalesce(sum(o.total) filter (
        where o.status = 'delivered' and o.payment_method <> 'cod'), 0), 2),
    'average_order', round(coalesce(
        avg(o.total) filter (where o.status = 'delivered'), 0), 2)
  )
  into v
  from public.orders o
  left join public.vendors vn on vn.id = o.vendor_id
  where (p_start is null or o.created_at >= p_start)
    and (p_end is null or o.created_at <= p_end);

  return v;
end;
$$;

revoke execute on function public.admin_platform_report(timestamptz, timestamptz, numeric)
  from public, anon;
grant execute on function public.admin_platform_report(timestamptz, timestamptz, numeric)
  to authenticated;
