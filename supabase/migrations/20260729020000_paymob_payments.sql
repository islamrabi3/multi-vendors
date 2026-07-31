-- Paymob unified-checkout settlement.
--
-- Money only ever moves here, from a SECURITY DEFINER function that the
-- service-role Edge Function calls after verifying Paymob's HMAC. Clients can
-- read their wallet and their payment intents; they can never write either.

-- ---------------------------------------------------------------------------
-- payment_intents: one row per unified-checkout session.
-- `reference` is the Paymob special_reference, so the webhook can map a
-- transaction back to the thing being paid for.
-- ---------------------------------------------------------------------------
create table if not exists public.payment_intents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('order', 'topup')),
  order_id uuid references public.orders (id) on delete cascade,
  amount numeric(10, 2) not null check (amount > 0),
  reference text not null unique,
  status text not null default 'pending' check (status in ('pending', 'paid', 'failed')),
  provider_transaction_id text,
  failure_reason text,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint payment_intents_order_required
    check (kind <> 'order' or order_id is not null)
);

create index if not exists payment_intents_user_idx
  on public.payment_intents (user_id, created_at desc);
create index if not exists payment_intents_order_idx
  on public.payment_intents (order_id);

alter table public.payment_intents enable row level security;

-- Read-only for the owner; every write goes through the service role.
drop policy if exists "Users can view their own payment intents" on public.payment_intents;
create policy "Users can view their own payment intents" on public.payment_intents
  for select using (auth.uid() = user_id);

-- Realtime so the app can watch an intent settle instead of polling blindly.
do $$ begin
  alter publication supabase_realtime add table public.payment_intents;
exception
  when duplicate_object then null;
  when undefined_object then null;
end $$;

-- ---------------------------------------------------------------------------
-- Wallets are no longer client-writable. Before this, any signed-in user could
-- UPDATE their own balance directly, which made the top-up gateway pointless.
-- ---------------------------------------------------------------------------
drop policy if exists "Users can manage their own wallet" on public.wallets;
drop policy if exists "Users can view their own wallet" on public.wallets;
create policy "Users can view their own wallet" on public.wallets
  for select using (auth.uid() = user_id);

drop policy if exists "Users can manage their own wallet transactions" on public.wallet_transactions;
drop policy if exists "Users can view their own wallet transactions" on public.wallet_transactions;
create policy "Users can view their own wallet transactions" on public.wallet_transactions
  for select using (auth.uid() = user_id);

revoke insert, update, delete on public.wallets from authenticated, anon;
revoke insert, update, delete on public.wallet_transactions from authenticated, anon;

-- ---------------------------------------------------------------------------
-- open_payment_intent: called by the Edge Function (service role) once Paymob
-- has accepted the intention. Amount for an order is read from the order row,
-- never from the client.
-- ---------------------------------------------------------------------------
create or replace function public.open_payment_intent(
  p_user_id uuid,
  p_kind text,
  p_reference text,
  p_amount numeric,
  p_order_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  insert into public.payment_intents (user_id, kind, order_id, amount, reference)
  values (p_user_id, p_kind, p_order_id, p_amount, p_reference)
  returning id into v_id;

  if p_kind = 'order' then
    update public.orders
    set payment_status = 'pending'
    where id = p_order_id and payment_status <> 'paid';
  end if;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- settle_payment_intent: the only path that credits a wallet or marks an order
-- paid. Idempotent — a replayed webhook returns the already-recorded status
-- without moving money a second time.
-- ---------------------------------------------------------------------------
create or replace function public.settle_payment_intent(
  p_reference text,
  p_success boolean,
  p_transaction_id text default null,
  p_failure_reason text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_intent public.payment_intents%rowtype;
begin
  select * into v_intent
  from public.payment_intents
  where reference = p_reference
  for update;

  if not found then
    return 'not_found';
  end if;

  -- Already settled: replayed callback, do nothing.
  if v_intent.status <> 'pending' then
    return v_intent.status;
  end if;

  if not p_success then
    update public.payment_intents
    set status = 'failed',
        provider_transaction_id = coalesce(p_transaction_id, provider_transaction_id),
        failure_reason = p_failure_reason,
        settled_at = now()
    where id = v_intent.id;

    if v_intent.kind = 'order' then
      update public.orders
      set payment_status = 'failed'
      where id = v_intent.order_id and payment_status <> 'paid';
    end if;

    return 'failed';
  end if;

  update public.payment_intents
  set status = 'paid',
      provider_transaction_id = coalesce(p_transaction_id, provider_transaction_id),
      settled_at = now()
  where id = v_intent.id;

  if v_intent.kind = 'topup' then
    insert into public.wallets (user_id, balance, updated_at)
    values (v_intent.user_id, v_intent.amount, now())
    on conflict (user_id)
    do update set balance = public.wallets.balance + v_intent.amount,
                  updated_at = now();

    insert into public.wallet_transactions (user_id, type, amount, reference_id, description)
    values (v_intent.user_id, 'deposit', v_intent.amount, p_reference, 'Wallet top-up via Paymob');
  else
    update public.orders
    set payment_status = 'paid'
    where id = v_intent.order_id;
  end if;

  return 'paid';
end;
$$;

-- Settlement is service-role only: revoking from PUBLIC drops the implicit
-- grant every role inherits, so service_role is then granted back explicitly.
revoke execute on function public.open_payment_intent(uuid, text, text, numeric, uuid)
  from public, anon, authenticated;
revoke execute on function public.settle_payment_intent(text, boolean, text, text)
  from public, anon, authenticated;
grant execute on function public.open_payment_intent(uuid, text, text, numeric, uuid)
  to service_role;
grant execute on function public.settle_payment_intent(text, boolean, text, text)
  to service_role;

-- ---------------------------------------------------------------------------
-- pay_order_with_wallet: balance check, debit, ledger entry and the order's
-- paid flag in one transaction. The client cannot do any of these itself.
-- ---------------------------------------------------------------------------
create or replace function public.pay_order_with_wallet(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_balance numeric;
begin
  select * into v_order
  from public.orders
  where id = p_order_id and customer_id = auth.uid()
  for update;

  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;
  if v_order.payment_status = 'paid' then
    return true;
  end if;

  select balance into v_balance
  from public.wallets
  where user_id = auth.uid()
  for update;

  if not found or v_balance < v_order.total then
    raise exception 'INSUFFICIENT_WALLET_BALANCE';
  end if;

  update public.wallets
  set balance = balance - v_order.total,
      updated_at = now()
  where user_id = auth.uid();

  insert into public.wallet_transactions (user_id, type, amount, reference_id, description)
  values (auth.uid(), 'payment', -v_order.total, p_order_id::text,
          'Payment for order ' || left(p_order_id::text, 8));

  update public.orders
  set payment_status = 'paid'
  where id = p_order_id;

  return true;
end;
$$;

grant execute on function public.pay_order_with_wallet(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- discard_unpaid_order: the customer abandoned or failed the payment. The
-- order row is deleted outright so nothing ever reaches the restaurant, and
-- any coupon use is handed back.
-- ---------------------------------------------------------------------------
create or replace function public.discard_unpaid_order(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
begin
  select * into v_order
  from public.orders
  where id = p_order_id and customer_id = auth.uid()
  for update;

  if not found then
    return false;
  end if;
  if v_order.payment_status = 'paid' then
    return false;
  end if;
  if v_order.status <> 'pending' then
    return false;
  end if;

  if v_order.coupon_id is not null then
    update public.coupons
    set used_count = greatest(used_count - 1, 0)
    where id = v_order.coupon_id;
  end if;

  delete from public.orders where id = p_order_id;
  return true;
end;
$$;

grant execute on function public.discard_unpaid_order(uuid) to authenticated;

-- Also drop the client-callable wallet mutators that the tightened RLS makes
-- redundant; leaving them would let any user credit their own balance.
revoke execute on function public.top_up_wallet(uuid, numeric)
  from public, anon, authenticated;
revoke execute on function public.process_wallet_payment(uuid, numeric, text)
  from public, anon, authenticated;

-- Service role keeps full read access to the new table.
grant select, insert, update on public.payment_intents to service_role;

-- ---------------------------------------------------------------------------
-- An unpaid card order must stay invisible to the restaurant and to drivers,
-- so a failed payment can never be prepared or dispatched. Enforced in RLS
-- rather than in the app's query filters, which are trivially bypassed.
-- ---------------------------------------------------------------------------
drop policy if exists "orders_read" on public.orders;
create policy "orders_read" on public.orders
  for select using (
    customer_id = auth.uid()
    or (
      (payment_method <> 'paymob' or payment_status = 'paid')
      and (
        driver_id = auth.uid()
        or public.is_vendor_owner(vendor_id)
        or (status = 'ready_for_pickup' and driver_id is null and public.is_online_driver())
      )
    )
  );
