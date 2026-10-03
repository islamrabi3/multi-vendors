-- Revenue split by how the customer actually paid, plus the money-flow
-- figures the admin money screen needs to explain a period's platform net.
--
-- Two gaps this closes:
--
-- 1. `admin_finance_overview` reported COD vs online as *counts only*. An
--    operator could see 128 cash orders and 47 online ones and still not know
--    which half of the money that was, which is the question the screen exists
--    to answer.
--
-- 2. Card and mobile wallet were indistinguishable. Both are `payment_method
--    = 'paymob'` on the order — correctly, since they settle identically —
--    so the channel is recorded on the payment intent instead, where it
--    belongs: it describes the gateway session, not the order.

-- Which Paymob integration a gateway session was opened against. Null for
-- every row written before this migration and for any client that does not
-- send a channel; reported as 'card' below, which is what those all were.
alter table public.payment_intents
  add column if not exists channel text
  check (channel is null or channel in ('card', 'wallet'));

comment on column public.payment_intents.channel is
  'Paymob integration used: card, or wallet for an Egyptian mobile wallet '
  '(Vodafone Cash / Etisalat / Orange). Null on rows predating the split.';

-- Adding a parameter makes a *new* function: `create or replace` matches on
-- signature, so the five-argument version survives alongside it. Both then
-- match the edge function's five named arguments and every call raises 42725
-- "function is not unique" — which takes Paymob checkout down completely.
-- Drop the old one first; the new body is identical once p_channel defaults
-- to null, so no caller changes behaviour.
drop function if exists public.open_payment_intent(uuid, text, text, numeric, uuid);

create or replace function public.open_payment_intent(
  p_user_id uuid,
  p_kind text,
  p_reference text,
  p_amount numeric,
  p_order_id uuid default null,
  p_channel text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.payment_intents
    (user_id, kind, order_id, amount, reference, channel)
  values
    (p_user_id, p_kind, p_order_id, p_amount, p_reference,
     case when p_channel in ('card', 'wallet') then p_channel else null end)
  returning id into v_id;

  if p_kind = 'order' then
    update public.orders
    set payment_status = 'pending'
    where id = p_order_id and payment_status <> 'paid';
  end if;

  return v_id;
end;
$$;

revoke execute on function
  public.open_payment_intent(uuid, text, text, numeric, uuid, text)
  from public, anon, authenticated;

-- The admin's money screen, for a period.
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
    -- One settled intent per order at most, so this cannot double-count an
    -- order that was retried after a failure: only the paid row joins.
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

    -- Gross taken from customers, by route. These three sum to the period's
    -- order revenue: every delivered order is exactly one of them.
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
    'platform_revenue', (select coalesce(sum(signed_amount), 0) from t
                         where owner_type = 'platform'),
    'settlements', (select coalesce(sum(amount), 0) from t
                    where type in ('driver_settlement', 'vendor_settlement')),
    'deposits', (select coalesce(sum(amount), 0) from t where type = 'driver_deposit'),
    'refunds', (select coalesce(sum(amount), 0) from t where type = 'refund'),
    'adjustments', (select coalesce(sum(signed_amount), 0) from t
                    where type in ('adjustment', 'bonus', 'penalty')),
    -- Outstanding is a position, not a flow: it is what is owed right now,
    -- across all time, so it deliberately ignores the period filter.
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
$$;
