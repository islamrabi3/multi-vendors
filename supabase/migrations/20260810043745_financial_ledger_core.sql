-- Ledger-first money for a cash-on-delivery marketplace.
--
-- The existing `wallets` / `wallet_transactions` pair is the *customer's*
-- store credit — `pay_order_with_wallet` spends it and `place_order` records
-- it as `wallet_amount_used`. It is untouched here. This is a separate,
-- party-scoped system for the three balances a COD marketplace actually has to
-- track: what a driver owes in collected cash, what a store is owed, and what
-- the platform earned.
--
-- ## The one rule
--
-- `finance_wallets` holds no truth. Every figure on it is a cached sum of
-- `ledger_transactions`, maintained by trigger and rebuildable from scratch by
-- `finance_rebuild_wallet()`. Nothing anywhere writes a balance directly.
--
-- ## Sign convention
--
--   credit — the owner's balance goes up (the platform owes them more, or they
--            owe the platform less)
--   debit  — the owner's balance goes down (they owe the platform more)
--
-- `balance = sum(signed_amount)`. For a driver a negative balance is cash they
-- are holding and owe back; a positive balance is money the platform owes
-- them. Worked against the brief's own example:
--
--   CASH_COLLECTION   debit  340  ->  -340
--   DRIVER_EARNING    credit  30  ->  -310   (the driver owes 310)
--   DRIVER_SETTLEMENT credit 310  ->     0
--
-- A single running account per party, rather than separate "earnings" and
-- "cash due" columns that have to be kept consistent with each other. Keeping
-- them apart is what lets a driver's earnings be counted twice — once as an
-- available balance and again as an offset against the cash.

do $$ begin
  create type public.ledger_owner_type as enum ('driver', 'vendor', 'platform');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ledger_direction as enum ('credit', 'debit');
exception when duplicate_object then null; end $$;

-- PENDING money is visible but not counted; only POSTED moves a balance.
-- REVERSED rows stay exactly where they are and are cancelled out by a paired
-- REVERSAL row, so the trail never loses a step.
do $$ begin
  create type public.ledger_status as enum
    ('pending', 'posted', 'failed', 'cancelled', 'reversed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.ledger_entry_type as enum (
    'driver_earning', 'driver_tip', 'cash_collection', 'driver_settlement',
    'driver_deposit', 'vendor_earning', 'vendor_settlement',
    'platform_commission', 'platform_delivery_margin', 'platform_discount',
    'platform_subscription', 'refund', 'bonus', 'penalty', 'adjustment',
    'reversal'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.settlement_status as enum ('pending', 'completed', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.deposit_status as enum ('pending', 'approved', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.order_settlement_status as enum
    ('pending', 'processing', 'settled', 'failed');
exception when duplicate_object then null; end $$;

-- What actually happened with the cash at the door. Deliberately not a number
-- the driver types in.
do $$ begin
  create type public.cash_status as enum
    ('not_applicable', 'cash_pending', 'cash_collected',
     'cash_partial', 'cash_not_collected', 'cash_refunded');
exception when duplicate_object then null; end $$;

create table if not exists public.finance_wallets (
  id uuid primary key default gen_random_uuid(),
  owner_type public.ledger_owner_type not null,
  -- Null on the platform's own account: there is exactly one of it.
  owner_id uuid,
  currency text not null default 'EGP',

  -- Every column below is a cache. `finance_rebuild_wallet` recomputes all of
  -- them from the ledger, and is the definition of what they mean.
  balance numeric(14, 2) not null default 0,
  pending_balance numeric(14, 2) not null default 0,
  cash_collected numeric(14, 2) not null default 0,
  cash_settled numeric(14, 2) not null default 0,
  total_earnings numeric(14, 2) not null default 0,
  total_deposited numeric(14, 2) not null default 0,
  total_adjustments numeric(14, 2) not null default 0,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One account per party. The partial indexes are two halves of "unique
-- (owner_type, owner_id)" that also work when owner_id is null.
create unique index if not exists finance_wallets_owner_idx
  on public.finance_wallets (owner_type, owner_id) where owner_id is not null;
create unique index if not exists finance_wallets_platform_idx
  on public.finance_wallets (owner_type) where owner_id is null;

-- Money the driver is holding, as a positive number.
create or replace function public.wallet_cash_due(p_balance numeric)
returns numeric language sql immutable set search_path = ''
as $$ select greatest(-p_balance, 0); $$;

-- What the platform owes this party, as a positive number.
create or replace function public.wallet_payable(p_balance numeric)
returns numeric language sql immutable set search_path = ''
as $$ select greatest(p_balance, 0); $$;

grant execute on function public.wallet_cash_due(numeric) to authenticated;
grant execute on function public.wallet_payable(numeric) to authenticated;

create table if not exists public.ledger_transactions (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null references public.finance_wallets (id) on delete restrict,

  -- Denormalised from the wallet so every report can filter without a join.
  owner_type public.ledger_owner_type not null,
  owner_id uuid,

  order_id uuid references public.orders (id) on delete set null,
  type public.ledger_entry_type not null,

  -- Always positive. The sign lives in `direction`, so no row can be
  -- accidentally negative-and-debit and count twice.
  amount numeric(14, 2) not null check (amount >= 0),
  direction public.ledger_direction not null,
  signed_amount numeric(14, 2) generated always as (
    case when direction = 'credit' then amount else -amount end
  ) stored,

  status public.ledger_status not null default 'posted',

  reference text,
  description text,
  metadata jsonb not null default '{}'::jsonb,

  -- Reversal pairs. A wrong row is never deleted; it is marked `reversed` and
  -- a mirror row points back at it.
  reverses_id uuid references public.ledger_transactions (id) on delete restrict,

  -- The idempotency guarantee. A retry, a double tap or a re-run of a
  -- background job reuses the key and hits this unique index instead of paying
  -- anybody twice.
  idempotency_key text,

  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create unique index if not exists ledger_idempotency_idx
  on public.ledger_transactions (idempotency_key)
  where idempotency_key is not null;

create index if not exists ledger_wallet_idx
  on public.ledger_transactions (wallet_id, created_at desc);
create index if not exists ledger_owner_idx
  on public.ledger_transactions (owner_type, owner_id, created_at desc);
create index if not exists ledger_order_idx on public.ledger_transactions (order_id);
create index if not exists ledger_type_idx
  on public.ledger_transactions (type, created_at desc);

-- A posted row is history. Only the status may move, and only to `reversed`.
create or replace function public.ledger_immutability_guard()
returns trigger language plpgsql set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'LEDGER_APPEND_ONLY';
  end if;

  if old.status = 'posted' then
    if new.status not in ('posted', 'reversed') then
      raise exception 'LEDGER_POSTED_IS_FINAL';
    end if;
    if new.amount <> old.amount
       or new.direction <> old.direction
       or new.type <> old.type
       or new.wallet_id <> old.wallet_id
       or coalesce(new.order_id::text, '') <> coalesce(old.order_id::text, '') then
      raise exception 'LEDGER_POSTED_IS_IMMUTABLE';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists ledger_no_delete on public.ledger_transactions;
create trigger ledger_no_delete before delete on public.ledger_transactions
  for each row execute function public.ledger_immutability_guard();

drop trigger if exists ledger_no_edit on public.ledger_transactions;
create trigger ledger_no_edit before update on public.ledger_transactions
  for each row execute function public.ledger_immutability_guard();

-- Recomputes every cached figure on one wallet from its ledger rows. This is
-- the definition of each column, and the repair tool.
create or replace function public.finance_rebuild_wallet(p_wallet_id uuid)
returns void language sql security definer set search_path = public
as $$
  update public.finance_wallets w set
    balance = coalesce((select sum(t.signed_amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'posted'), 0),
    pending_balance = coalesce((select sum(t.signed_amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'pending'), 0),
    cash_collected = coalesce((select sum(t.amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'posted' and t.type = 'cash_collection'), 0),
    cash_settled = coalesce((select sum(t.amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'posted'
        and t.type in ('driver_settlement', 'vendor_settlement')), 0),
    total_earnings = coalesce((select sum(t.signed_amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'posted'
        and t.type in ('driver_earning', 'driver_tip', 'vendor_earning', 'bonus', 'penalty')), 0),
    total_deposited = coalesce((select sum(t.amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'posted' and t.type = 'driver_deposit'), 0),
    total_adjustments = coalesce((select sum(t.signed_amount) from public.ledger_transactions t
      where t.wallet_id = w.id and t.status = 'posted'
        and t.type in ('adjustment', 'reversal')), 0),
    updated_at = now()
  where w.id = p_wallet_id;
$$;

create or replace function public.ledger_refresh_wallet()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  perform public.finance_rebuild_wallet(coalesce(new.wallet_id, old.wallet_id));
  return null;
end;
$$;

drop trigger if exists ledger_sync_wallet on public.ledger_transactions;
create trigger ledger_sync_wallet after insert or update on public.ledger_transactions
  for each row execute function public.ledger_refresh_wallet();

create table if not exists public.settlements (
  id uuid primary key default gen_random_uuid(),
  owner_type public.ledger_owner_type not null,
  owner_id uuid not null,
  amount numeric(14, 2) not null check (amount > 0),
  method text not null default 'cash',
  status public.settlement_status not null default 'completed',
  reference text,
  notes text,
  -- The ledger row this produced, so a settlement can always be traced to the
  -- money it moved.
  transaction_id uuid references public.ledger_transactions (id) on delete set null,
  created_by uuid references public.profiles (id) on delete set null,
  approved_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists settlements_owner_idx
  on public.settlements (owner_type, owner_id, created_at desc);

create table if not exists public.deposit_requests (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles (id) on delete cascade,
  amount numeric(14, 2) not null check (amount > 0),
  payment_method text not null default 'bank_transfer',
  reference text,
  proof_url text,
  status public.deposit_status not null default 'pending',
  transaction_id uuid references public.ledger_transactions (id) on delete set null,
  reviewed_by uuid references public.profiles (id) on delete set null,
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz not null default now()
);

create index if not exists deposit_requests_driver_idx
  on public.deposit_requests (driver_id, created_at desc);
create index if not exists deposit_requests_status_idx
  on public.deposit_requests (status, created_at desc);

-- RLS - read your own, write nothing.
--
-- No role has INSERT or UPDATE on any table here. Every write goes through a
-- SECURITY DEFINER function that checks who is asking, so there is no path by
-- which a driver edits their own balance.

alter table public.finance_wallets enable row level security;
alter table public.ledger_transactions enable row level security;
alter table public.settlements enable row level security;
alter table public.deposit_requests enable row level security;

drop policy if exists finance_wallets_read on public.finance_wallets;
create policy finance_wallets_read on public.finance_wallets
  for select to authenticated using (
    public.is_admin()
    or (owner_type = 'driver' and owner_id = (select auth.uid()))
    or (owner_type = 'vendor' and public.is_vendor_owner(owner_id))
  );

drop policy if exists ledger_read on public.ledger_transactions;
create policy ledger_read on public.ledger_transactions
  for select to authenticated using (
    public.is_admin()
    or (owner_type = 'driver' and owner_id = (select auth.uid()))
    or (owner_type = 'vendor' and public.is_vendor_owner(owner_id))
  );

drop policy if exists settlements_read on public.settlements;
create policy settlements_read on public.settlements
  for select to authenticated using (
    public.is_admin()
    or (owner_type = 'driver' and owner_id = (select auth.uid()))
    or (owner_type = 'vendor' and public.is_vendor_owner(owner_id))
  );

drop policy if exists deposit_requests_read on public.deposit_requests;
create policy deposit_requests_read on public.deposit_requests
  for select to authenticated using (
    public.is_admin() or driver_id = (select auth.uid())
  );

revoke all on public.finance_wallets from anon, authenticated;
revoke all on public.ledger_transactions from anon, authenticated;
revoke all on public.settlements from anon, authenticated;
revoke all on public.deposit_requests from anon, authenticated;
grant select on public.finance_wallets to authenticated;
grant select on public.ledger_transactions to authenticated;
grant select on public.settlements to authenticated;
grant select on public.deposit_requests to authenticated;
