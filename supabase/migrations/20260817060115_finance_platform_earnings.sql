-- What the platform actually made, as opposed to what its ledger account
-- happens to hold.
--
-- `platform_revenue` sums every signed amount on the platform's own account,
-- and that account is a clearing account: customer money lands in it and
-- leaves again as vendor and driver settlements. It therefore trends to zero
-- as settlements complete — on this project it reads exactly 0.00 all-time
-- while the business has in fact earned 586.05. Shown as "platform net" it
-- reads as "we made nothing", which is the opposite of true.
--
-- Earnings are the four types the platform keeps: commission, its share of
-- delivery, early-settlement fees, less the discounts it funded itself.
-- Settlements, deposits and online collections are money in transit and are
-- deliberately excluded.
create or replace function public.admin_finance_overview(
  p_start timestamptz default null, p_end timestamptz default null)
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare v jsonb;
begin
  if not public.has_permission('reports.view') then raise exception 'FORBIDDEN'; end if;

  with t as (
    select * from public.ledger_transactions
    where status = 'posted'
      and (p_start is null or created_at >= p_start)
      and (p_end is null or created_at <= p_end)
  ), o as (
    select * from public.orders
    where status = 'delivered'
      and (p_start is null or created_at >= p_start)
      and (p_end is null or created_at <= p_end)
  ), paid_online as (
    select o.id,
           o.total,
           coalesce(pi.channel, 'card') as channel
    from o
    left join public.payment_intents pi
      on pi.order_id = o.id and pi.status = 'paid'
    where o.payment_method = 'paymob'
  )
  select jsonb_build_object(
    'total_orders', (select count(*) from o),
    'cash_orders', (select count(*) from o where payment_method = 'cod'),
    'online_orders', (select count(*) from o where payment_method <> 'cod'),

    'cod_revenue', (select coalesce(sum(total), 0) from o
                    where payment_method = 'cod'),
    'card_revenue', (select coalesce(sum(total), 0) from paid_online
                     where channel = 'card'),
    'mobile_wallet_revenue', (select coalesce(sum(total), 0) from paid_online
                              where channel = 'wallet'),
    'app_wallet_revenue', (select coalesce(sum(total), 0) from o
                           where payment_method = 'wallet'),
    'gross_revenue', (select coalesce(sum(total), 0) from o),

    'card_orders', (select count(*) from paid_online where channel = 'card'),
    'mobile_wallet_orders', (select count(*) from paid_online
                             where channel = 'wallet'),
    'app_wallet_orders', (select count(*) from o where payment_method = 'wallet'),

    'cash_collected', (select coalesce(sum(amount), 0) from t where type = 'cash_collection'),
    'driver_earnings', (select coalesce(sum(amount), 0) from t
                        where type in ('driver_earning', 'driver_tip')),
    'vendor_earnings', (select coalesce(sum(amount), 0) from t where type = 'vendor_earning'),
    'platform_commission', (select coalesce(sum(amount), 0) from t
                            where type = 'platform_commission'),
    'platform_delivery_margin', (select coalesce(sum(amount), 0) from t
                                 where type = 'platform_delivery_margin'),
    'platform_discounts', (select coalesce(sum(amount), 0) from t
                           where type = 'platform_discount'),
    'early_settlement_fees', (select coalesce(sum(signed_amount), 0) from t
                              where owner_type = 'platform'
                                and type = 'early_settlement_fee'),

    -- The bottom line an operator means by "what did we make".
    'platform_earnings', (select coalesce(sum(signed_amount), 0) from t
                          where owner_type = 'platform'
                            and type in ('platform_commission',
                                         'platform_delivery_margin',
                                         'early_settlement_fee',
                                         'platform_discount')),

    -- Kept for the reconciliation tab: the clearing balance should sit near
    -- zero, and a number drifting away from it means settlements are behind.
    'platform_revenue', (select coalesce(sum(signed_amount), 0) from t
                         where owner_type = 'platform'),
    'settlements', (select coalesce(sum(amount), 0) from t
                    where type in ('driver_settlement', 'vendor_settlement')),
    'deposits', (select coalesce(sum(amount), 0) from t where type = 'driver_deposit'),
    'refunds', (select coalesce(sum(amount), 0) from t where type = 'refund'),
    'adjustments', (select coalesce(sum(signed_amount), 0) from t
                    where type in ('adjustment', 'bonus', 'penalty')),
    'driver_cash_due', (select coalesce(sum(public.wallet_cash_due(balance)), 0)
                        from public.finance_wallets where owner_type = 'driver'),
    'vendor_payable', (select coalesce(sum(public.wallet_payable(balance)), 0)
                       from public.finance_wallets where owner_type = 'vendor'),
    'pending_deposits', (select count(*) from public.deposit_requests where status = 'pending'),
    'unsettled_orders', (select count(*) from public.orders
                         where status = 'delivered' and settlement_status <> 'settled')
  ) into v;
  return v;
end;
$$;;
