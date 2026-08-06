-- Tipping, as money that actually moves.
--
-- The pieces existed — a `driver_tips` table, `orders.driver_tip`, and the
-- payout report already counting tips towards what a driver is owed — but the
-- only way in was a client insert policy that let a customer write any amount
-- they liked without paying a thing. The driver would then be owed money
-- nobody had collected.
--
-- A tip is now a wallet transfer: debited from the customer, credited to the
-- driver, both sides ledgered, all in one transaction.

-- One tip per order. Without this a customer could tip repeatedly, and the
-- payout report would add up every row.
create unique index if not exists driver_tips_order_unique
  on public.driver_tips (order_id);

-- The client insert path goes away entirely; the RPC below is the only writer.
drop policy if exists "Customers can add tips" on public.driver_tips;
drop policy if exists driver_tips_insert on public.driver_tips;

drop policy if exists driver_tips_read on public.driver_tips;
create policy driver_tips_read on public.driver_tips
  for select to authenticated
  using (
    driver_id = auth.uid()
    or exists (select 1 from public.orders o
               where o.id = order_id and o.customer_id = auth.uid())
    or public.is_admin()
  );

create or replace function public.add_driver_tip(
  p_order_id uuid,
  p_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_balance numeric;
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  -- A ceiling, because a mis-typed amount is a customer's whole balance gone
  -- to somebody who cannot give it back.
  if p_amount > 500 then
    raise exception 'TIP_TOO_LARGE';
  end if;

  select * into v_order from public.orders where id = p_order_id;
  if not found or v_order.customer_id <> auth.uid() then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  if v_order.driver_id is null then
    raise exception 'NO_DRIVER';
  end if;
  -- Only after the job is done: tipping up front is a bribe, and a tip on an
  -- order that is later cancelled would have to be clawed back.
  if v_order.status <> 'delivered' then
    raise exception 'ORDER_NOT_DELIVERED';
  end if;
  if exists (select 1 from public.driver_tips where order_id = p_order_id) then
    raise exception 'ALREADY_TIPPED';
  end if;

  -- Locked so two taps cannot both pass the balance check.
  select balance into v_balance
  from public.wallets where user_id = auth.uid()
  for update;

  if v_balance is null or v_balance < p_amount then
    raise exception 'INSUFFICIENT_WALLET_BALANCE';
  end if;

  update public.wallets
  set balance = balance - p_amount
  where user_id = auth.uid();

  insert into public.wallets (user_id, balance)
  values (v_order.driver_id, p_amount)
  on conflict (user_id) do update
    set balance = public.wallets.balance + p_amount;

  insert into public.wallet_transactions
    (user_id, type, amount, reference_id, description)
  values
    (auth.uid(), 'tip', -p_amount, p_order_id::text,
     'Tip for order ' || v_order.order_number),
    (v_order.driver_id, 'tip', p_amount, p_order_id::text,
     'Tip for order ' || v_order.order_number);

  insert into public.driver_tips (order_id, driver_id, amount)
  values (p_order_id, v_order.driver_id, p_amount);

  -- Mirrored onto the order because the payout report reads it there.
  update public.orders set driver_tip = p_amount where id = p_order_id;

  return jsonb_build_object('tipped', p_amount);
end;
$$;

revoke execute on function public.add_driver_tip(uuid, numeric) from public, anon;
grant execute on function public.add_driver_tip(uuid, numeric) to authenticated;
