-- One order, two conversations.
--
-- Until now every message on an order went into a single room, so the store
-- read what the customer told the rider and the rider read what the store
-- said. The customer talks to each of them about different things — a missing
-- item is the store's business, a wrong street is the rider's — and neither
-- should be reading the other's half.
--
-- Each message now carries the thread it belongs to: 'vendor' or 'driver'.
-- The customer is in both; the store sees only 'vendor', the rider only
-- 'driver'. Read marks are per thread too, so clearing one conversation does
-- not silence the other.
-- ---------------------------------------------------------------------------

alter table public.chat_messages
  add column if not exists thread text not null default 'vendor'
    check (thread in ('vendor', 'driver'));

create index if not exists chat_messages_order_thread_idx
  on public.chat_messages (order_id, thread, created_at desc);

-- Read marks key on the thread as well, so the primary key has to grow.
alter table public.chat_reads
  add column if not exists thread text not null default 'vendor'
    check (thread in ('vendor', 'driver'));

alter table public.chat_reads drop constraint if exists chat_reads_pkey;
alter table public.chat_reads
  add constraint chat_reads_pkey primary key (order_id, user_id, thread);

-- Who may see which half.
create or replace function public.can_view_chat_thread(p_order_id uuid, p_thread text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.orders o
    left join public.vendors v on v.id = o.vendor_id
    where o.id = p_order_id
      and (
        -- The customer is in both conversations; they are their own.
        o.customer_id = auth.uid()
        -- The rider only ever sees the delivery thread.
        or (p_thread = 'driver' and o.driver_id = auth.uid())
        -- The store only ever sees its own.
        or (p_thread = 'vendor' and public.is_vendor_member(o.vendor_id, 'orders'))
        or (p_thread = 'vendor' and v.owner_id = auth.uid())
      )
  );
$$;

revoke execute on function public.can_view_chat_thread(uuid, text) from anon;

drop policy if exists chat_messages_read on public.chat_messages;
create policy chat_messages_read on public.chat_messages
  for select to authenticated
  using (public.can_view_chat_thread(order_id, thread));

drop policy if exists chat_messages_send on public.chat_messages;
create policy chat_messages_send on public.chat_messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and not public.is_blocked()
    and public.can_view_chat_thread(order_id, thread)
  );

-- The thread-aware RPCs replace the thread-blind ones entirely. Both took
-- only defaulted arguments, so leaving the old signatures in place would let
-- a call that names just p_order_id resolve to the wrong one.
drop function if exists public.my_unread_chat_count(uuid);
drop function if exists public.mark_order_chat_read(uuid);
drop function if exists public.hide_order_conversation(uuid);

create or replace function public.mark_order_chat_read(
  p_order_id uuid,
  p_thread text default 'vendor'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_view_chat_thread(p_order_id, p_thread) then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.chat_reads (order_id, user_id, thread, last_read_at)
  values (p_order_id, auth.uid(), p_thread, now())
  on conflict (order_id, user_id, thread)
  do update set last_read_at = excluded.last_read_at;
end;
$$;

create or replace function public.my_unread_chat_count(
  p_order_id uuid default null,
  p_thread text default null
)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.chat_messages m
  left join public.chat_reads r
    on r.order_id = m.order_id and r.user_id = auth.uid() and r.thread = m.thread
  where (p_order_id is null or m.order_id = p_order_id)
    and (p_thread is null or m.thread = p_thread)
    and m.sender_id <> auth.uid()
    and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)
    and m.created_at > now() - interval '30 days'
    and public.can_view_chat_thread(m.order_id, m.thread);
$$;

create or replace function public.hide_order_conversation(
  p_order_id uuid,
  p_thread text default 'vendor'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_view_chat_thread(p_order_id, p_thread) then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.chat_reads (order_id, user_id, thread, last_read_at, hidden_at)
  values (p_order_id, auth.uid(), p_thread, now(), now())
  on conflict (order_id, user_id, thread)
  do update set last_read_at = excluded.last_read_at,
                hidden_at = excluded.hidden_at;
end;
$$;

-- The messages hub lists one row per conversation, not one per order, so a
-- customer with both a store and a rider to talk to sees two.
create or replace function public.my_order_conversations(p_limit integer default 50)
returns table (
  order_id uuid,
  thread text,
  order_number text,
  order_status text,
  vendor_name text,
  vendor_logo_url text,
  last_message text,
  last_has_attachment boolean,
  last_at timestamptz,
  last_sender_name text,
  last_sender_role text,
  last_from_me boolean,
  unread integer
)
language sql
stable
security definer
set search_path = public
as $$
  with rooms as (
    select distinct m.order_id, m.thread
    from public.chat_messages m
    where public.can_view_chat_thread(m.order_id, m.thread)
  ),
  last_msg as (
    select distinct on (m.order_id, m.thread)
      m.order_id, m.thread, m.message, m.sender_id, m.created_at,
      (m.attachment_url is not null or m.image_url is not null) as has_attachment
    from public.chat_messages m
    join rooms r on r.order_id = m.order_id and r.thread = m.thread
    order by m.order_id, m.thread, m.created_at desc
  )
  select
    o.id,
    l.thread,
    o.order_number,
    o.status::text,
    v.name,
    v.logo_url,
    l.message,
    l.has_attachment,
    l.created_at,
    p.full_name,
    case
      when l.sender_id = o.customer_id then 'customer'
      when l.sender_id = o.driver_id then 'driver'
      when l.sender_id = v.owner_id then 'vendor'
      when l.thread = 'vendor' then 'vendor'
      else 'driver'
    end,
    l.sender_id = auth.uid(),
    (
      select count(*)::int from public.chat_messages m2
      left join public.chat_reads r2
        on r2.order_id = m2.order_id and r2.user_id = auth.uid()
           and r2.thread = m2.thread
      where m2.order_id = o.id
        and m2.thread = l.thread
        and m2.sender_id <> auth.uid()
        and m2.created_at > coalesce(r2.last_read_at, '-infinity'::timestamptz)
        and m2.created_at > now() - interval '30 days'
    )
  from last_msg l
  join public.orders o on o.id = l.order_id
  left join public.vendors v on v.id = o.vendor_id
  left join public.profiles p on p.id = l.sender_id
  left join public.chat_reads hr
    on hr.order_id = o.id and hr.user_id = auth.uid() and hr.thread = l.thread
  where hr.hidden_at is null or l.created_at > hr.hidden_at
  order by l.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

revoke execute on function public.my_order_conversations(integer) from anon;
