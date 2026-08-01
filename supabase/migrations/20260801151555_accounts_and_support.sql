-- Account lifecycle and the support inbox.
--
-- Three things that all hang off "who is this user and can they still act":
-- self-service deletion, admin blocking, and a support thread that is not
-- attached to any one order.

-- ---------------------------------------------------------------------------
-- 1. Blocking.
--
-- A blocked account keeps its history — orders and payouts still have to
-- reconcile — but cannot act. The check lives in is_blocked() so every policy
-- and RPC consults one definition.
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists is_blocked boolean not null default false,
  add column if not exists blocked_reason text,
  add column if not exists blocked_at timestamptz,
  add column if not exists deleted_at timestamptz;

comment on column public.profiles.deleted_at is
  'Set when the user deletes their own account. The row survives so past '
  'orders keep a customer, but the account can no longer sign in or act.';

create or replace function public.is_blocked()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid()
      and (is_blocked or deleted_at is not null)
  );
$$;

grant execute on function public.is_blocked() to authenticated;

-- Blocking has to reach the two things that cost real money: placing an order
-- and claiming a delivery.
create or replace function public.is_online_driver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.drivers d
    join public.profiles p on p.id = d.id
    where d.id = auth.uid()
      and d.is_online
      and d.approval_status = 'active'
      and not p.is_blocked
      and p.deleted_at is null
  );
$$;

create or replace function public.admin_set_user_blocked(
  p_user_id uuid,
  p_blocked boolean,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;
  -- An admin locking themselves out would need database access to undo.
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_BLOCK_SELF';
  end if;
  if exists (select 1 from public.profiles
             where id = p_user_id and role = 'admin') then
    raise exception 'CANNOT_BLOCK_ADMIN';
  end if;

  update public.profiles
  set is_blocked = p_blocked,
      blocked_reason = case when p_blocked then p_reason else null end,
      blocked_at = case when p_blocked then now() else null end
  where id = p_user_id;

  -- A blocked driver comes off the road in the same statement.
  if p_blocked then
    update public.drivers set is_online = false where id = p_user_id;
  end if;
end;
$$;

revoke execute on function public.admin_set_user_blocked(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_set_user_blocked(uuid, boolean, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Deletion.
--
-- `orders.customer_id` and `orders.driver_id` are plain foreign keys with no
-- cascade, so a hard delete of a profile with any history simply fails — that
-- is exactly the error already sitting in this project's logs. Deletion is
-- therefore a soft close: the row stays, the identity is scrubbed.
-- ---------------------------------------------------------------------------

-- What blocks a deletion, so the app can explain rather than just refuse.
create or replace function public.account_deletion_blockers()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_active_orders int;
  v_wallet numeric;
  v_vendor_live int;
begin
  if v_user_id is null then
    raise exception 'UNAUTHORIZED';
  end if;

  select count(*) into v_active_orders
  from public.orders
  where (customer_id = v_user_id or driver_id = v_user_id)
    and status in ('pending', 'accepted', 'preparing',
                   'ready_for_pickup', 'out_for_delivery');

  select coalesce(balance, 0) into v_wallet
  from public.wallets where user_id = v_user_id;

  select count(*) into v_vendor_live
  from public.vendors v
  join public.orders o on o.vendor_id = v.id
  where v.owner_id = v_user_id
    and o.status in ('pending', 'accepted', 'preparing',
                     'ready_for_pickup', 'out_for_delivery');

  return jsonb_build_object(
    'active_orders', coalesce(v_active_orders, 0) + coalesce(v_vendor_live, 0),
    'wallet_balance', coalesce(v_wallet, 0)
  );
end;
$$;

revoke execute on function public.account_deletion_blockers() from public, anon;
grant execute on function public.account_deletion_blockers() to authenticated;

-- Closes the caller's own account.
--
-- `p_forfeit_balance` is the app passing back the answer to "you still have
-- money in your wallet, is that alright" — the balance is zeroed rather than
-- silently kept, so the ledger does not carry a claim nobody can spend.
create or replace function public.delete_own_account(
  p_forfeit_balance boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_blockers jsonb;
  v_wallet numeric;
begin
  if v_user_id is null then
    raise exception 'UNAUTHORIZED';
  end if;

  v_blockers := public.account_deletion_blockers();

  if (v_blockers ->> 'active_orders')::int > 0 then
    raise exception 'HAS_ACTIVE_ORDERS';
  end if;

  v_wallet := (v_blockers ->> 'wallet_balance')::numeric;
  if v_wallet > 0 and not p_forfeit_balance then
    raise exception 'WALLET_HAS_BALANCE';
  end if;

  if v_wallet > 0 then
    -- Logged as a `payment` because the enum has no adjustment kind and the
    -- balance is genuinely being spent down to zero, not refunded.
    insert into public.wallet_transactions
      (user_id, type, amount, reference_id, description)
    values (v_user_id, 'payment', -v_wallet, 'account_deleted',
            'Balance forfeited on account deletion');
    update public.wallets set balance = 0 where user_id = v_user_id;
  end if;

  -- A store cannot outlive its owner's account.
  update public.vendors
  set is_active = false, is_open = false, approval_status = 'suspended'
  where owner_id = v_user_id;

  update public.drivers set is_online = false where id = v_user_id;

  -- Scrub the identity but keep the row: orders reference it.
  update public.profiles
  set deleted_at = now(),
      full_name = 'Deleted user',
      phone = null,
      avatar_url = null,
      fcm_token = null
  where id = v_user_id;
end;
$$;

revoke execute on function public.delete_own_account(boolean) from public, anon;
grant execute on function public.delete_own_account(boolean) to authenticated;

-- The admin's version, which can close someone else's account.
create or replace function public.admin_delete_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'CANNOT_DELETE_SELF';
  end if;
  if exists (select 1 from public.profiles
             where id = p_user_id and role = 'admin') then
    raise exception 'CANNOT_DELETE_ADMIN';
  end if;

  update public.vendors
  set is_active = false, is_open = false, approval_status = 'suspended'
  where owner_id = p_user_id;

  update public.drivers set is_online = false where id = p_user_id;

  update public.profiles
  set deleted_at = now(),
      is_blocked = true,
      full_name = 'Deleted user',
      phone = null,
      avatar_url = null,
      fcm_token = null
  where id = p_user_id;
end;
$$;

revoke execute on function public.admin_delete_user(uuid) from public, anon;
grant execute on function public.admin_delete_user(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Support threads.
--
-- Distinct from `chat_messages`, which is bound to one order between a
-- customer and their driver. Support is the user talking to the platform, so
-- it needs to exist with no order at all.
-- ---------------------------------------------------------------------------
create table if not exists public.support_threads (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  subject text not null default '',
  status text not null default 'open' check (status in ('open', 'resolved')),
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists support_threads_user_idx
  on public.support_threads (user_id, last_message_at desc);
create index if not exists support_threads_open_idx
  on public.support_threads (last_message_at desc) where status = 'open';

create table if not exists public.support_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.support_threads(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  -- Denormalised so the customer's bubble alignment does not need a join to
  -- the sender's profile on every message.
  is_from_admin boolean not null default false,
  message text not null,
  created_at timestamptz not null default now()
);

create index if not exists support_messages_thread_idx
  on public.support_messages (thread_id, created_at);

alter table public.support_threads enable row level security;
alter table public.support_messages enable row level security;

drop policy if exists support_threads_own on public.support_threads;
create policy support_threads_own on public.support_threads
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

drop policy if exists support_threads_insert_own on public.support_threads;
create policy support_threads_insert_own on public.support_threads
  for insert to authenticated
  with check (user_id = auth.uid() and not public.is_blocked());

drop policy if exists support_threads_admin_update on public.support_threads;
create policy support_threads_admin_update on public.support_threads
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists support_messages_read on public.support_messages;
create policy support_messages_read on public.support_messages
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.support_threads t
      where t.id = thread_id and t.user_id = auth.uid()
    )
  );

-- The sender must be the caller, and `is_from_admin` must match what they
-- actually are — otherwise a customer could post a message styled as support.
drop policy if exists support_messages_send on public.support_messages;
create policy support_messages_send on public.support_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and not public.is_blocked()
    and is_from_admin = public.is_admin()
    and (
      public.is_admin()
      or exists (
        select 1 from public.support_threads t
        where t.id = thread_id and t.user_id = auth.uid()
      )
    )
  );

-- Keeps the inbox ordered by activity without the client having to write it.
create or replace function public.touch_support_thread()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.support_threads
  set last_message_at = now(),
      status = case when new.is_from_admin then status else 'open' end
  where id = new.thread_id;
  return null;
end;
$$;

drop trigger if exists trg_touch_support_thread on public.support_messages;
create trigger trg_touch_support_thread
  after insert on public.support_messages
  for each row execute function public.touch_support_thread();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'support_messages'
  ) then
    alter publication supabase_realtime add table public.support_messages;
  end if;
end $$;
