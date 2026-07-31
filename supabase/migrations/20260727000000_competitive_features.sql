-- Migration for Competitive Features (HungerStation & Talabat Parity)

-- 1. New Enums
do $$ begin
  create type public.order_type as enum ('delivery', 'pickup', 'scheduled');
exception
  when duplicate_object then null;
end $$;

do $$ begin
  create type public.wallet_transaction_type as enum ('deposit', 'payment', 'refund', 'cashback', 'tip');
exception
  when duplicate_object then null;
end $$;

-- 2. New Tables

-- Wallets
create table if not exists public.wallets (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  balance numeric(10, 2) not null default 0.00 check (balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Wallet Transactions
create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  type public.wallet_transaction_type not null,
  amount numeric(10, 2) not null,
  reference_id text,
  description text,
  created_at timestamptz not null default now()
);

-- Loyalty Points
create table if not exists public.loyalty_points (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  points int not null default 0 check (points >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.loyalty_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  points_change int not null,
  action text not null,
  created_at timestamptz not null default now()
);

-- Chat Messages (Customer <-> Driver / Support)
create table if not exists public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  message text not null,
  image_url text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

-- Driver Tips
create table if not exists public.driver_tips (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders (id) on delete cascade,
  driver_id uuid not null references public.profiles (id) on delete cascade,
  amount numeric(10, 2) not null check (amount > 0),
  created_at timestamptz not null default now()
);

-- Vendor Operating Schedules
create table if not exists public.vendor_schedules (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  day_of_week int not null check (day_of_week between 0 and 6),
  open_time text not null default '09:00',
  close_time text not null default '23:00',
  is_closed boolean not null default false,
  unique (vendor_id, day_of_week)
);

-- 3. Extend Existing Tables

alter table public.orders 
  add column if not exists order_type public.order_type not null default 'delivery',
  add column if not exists scheduled_at timestamptz,
  add column if not exists driver_tip numeric(10, 2) not null default 0.00,
  add column if not exists wallet_amount_used numeric(10, 2) not null default 0.00,
  add column if not exists delivery_proof_url text,
  add column if not exists delivery_otp text;

alter table public.vendors
  add column if not exists is_busy boolean not null default false,
  add column if not exists extra_prep_minutes int not null default 0,
  add column if not exists commission_rate numeric(5, 2) not null default 10.00,
  add column if not exists delivery_radius_km double precision not null default 10.0;

-- 4. RPC Functions

-- Process Wallet Payment / Deduction
create or replace function public.process_wallet_payment(
  p_user_id uuid,
  p_amount numeric,
  p_reference_id text
)
returns boolean
language plpgsql
security definer
as $$
declare
  v_current_balance numeric;
begin
  select balance into v_current_balance
  from public.wallets
  where user_id = p_user_id;

  if not found or v_current_balance < p_amount then
    raise exception 'Insufficient wallet balance';
  end if;

  update public.wallets
  set balance = balance - p_amount,
      updated_at = now()
  where user_id = p_user_id;

  insert into public.wallet_transactions (user_id, type, amount, reference_id, description)
  values (p_user_id, 'payment', -p_amount, p_reference_id, 'Used balance for order payment');

  return true;
end;
$$;

-- Top Up Wallet
create or replace function public.top_up_wallet(
  p_user_id uuid,
  p_amount numeric
)
returns boolean
language plpgsql
security definer
as $$
begin
  insert into public.wallets (user_id, balance, updated_at)
  values (p_user_id, p_amount, now())
  on conflict (user_id)
  do update set balance = public.wallets.balance + p_amount,
                updated_at = now();

  insert into public.wallet_transactions (user_id, type, amount, reference_id, description)
  values (p_user_id, 'deposit', p_amount, 'TOPUP_' || extract(epoch from now())::text, 'Wallet Top-Up');

  return true;
end;
$$;

-- Earn Loyalty Points
create or replace function public.earn_loyalty_points(
  p_user_id uuid,
  p_points int,
  p_action text
)
returns int
language plpgsql
security definer
as $$
declare
  v_new_total int;
begin
  insert into public.loyalty_points (user_id, points, updated_at)
  values (p_user_id, p_points, now())
  on conflict (user_id)
  do update set points = public.loyalty_points.points + p_points,
                updated_at = now()
  returning points into v_new_total;

  insert into public.loyalty_history (user_id, points_change, action)
  values (p_user_id, p_points, p_action);

  return v_new_total;
end;
$$;

-- Enable Realtime for Chat Messages
do $$ begin
  alter publication supabase_realtime add table public.chat_messages;
exception
  when duplicate_object then null;
  when others then null;
end $$;

-- 5. RLS Policies

alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.loyalty_points enable row level security;
alter table public.loyalty_history enable row level security;
alter table public.chat_messages enable row level security;
alter table public.driver_tips enable row level security;
alter table public.vendor_schedules enable row level security;

-- Wallets policy
drop policy if exists "Users can view their own wallet" on public.wallets;
drop policy if exists "Users can manage their own wallet" on public.wallets;
create policy "Users can manage their own wallet" on public.wallets
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "Users can view their own wallet transactions" on public.wallet_transactions;
drop policy if exists "Users can manage their own wallet transactions" on public.wallet_transactions;
create policy "Users can manage their own wallet transactions" on public.wallet_transactions
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Loyalty policy
drop policy if exists "Users can view their own loyalty points" on public.loyalty_points;
create policy "Users can view their own loyalty points" on public.loyalty_points
  for select using (auth.uid() = user_id);

drop policy if exists "Users can view their own loyalty history" on public.loyalty_history;
create policy "Users can view their own loyalty history" on public.loyalty_history
  for select using (auth.uid() = user_id);

-- Chat messages policy
drop policy if exists "Participants can view order chat" on public.chat_messages;
create policy "Participants can view order chat" on public.chat_messages
  for select using (
    exists (
      select 1 from public.orders o
      where o.id = chat_messages.order_id
        and (o.customer_id = auth.uid() or o.driver_id = auth.uid() or o.vendor_id in (
          select v.id from public.vendors v where v.owner_id = auth.uid()
        ))
    )
  );

drop policy if exists "Participants can insert order chat" on public.chat_messages;
create policy "Participants can insert order chat" on public.chat_messages
  for insert with check (auth.uid() = sender_id);

-- Driver tips policy
drop policy if exists "Drivers can view their tips" on public.driver_tips;
create policy "Drivers can view their tips" on public.driver_tips
  for select using (auth.uid() = driver_id or exists (
    select 1 from public.orders o where o.id = driver_tips.order_id and o.customer_id = auth.uid()
  ));

drop policy if exists "Customers can insert driver tips" on public.driver_tips;
create policy "Customers can insert driver tips" on public.driver_tips
  for insert with check (auth.uid() in (
    select customer_id from public.orders where id = order_id
  ));

-- Vendor schedules policy
drop policy if exists "Anyone can view vendor schedules" on public.vendor_schedules;
create policy "Anyone can view vendor schedules" on public.vendor_schedules
  for select using (true);

drop policy if exists "Vendors can manage their schedule" on public.vendor_schedules;
create policy "Vendors can manage their schedule" on public.vendor_schedules
  for all using (
    exists (
      select 1 from public.vendors v
      where v.id = vendor_schedules.vendor_id and v.owner_id = auth.uid()
    )
  );
