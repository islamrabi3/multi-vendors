-- Order chat as conversations: per-user read state, an inbox listing, and an
-- unread count that respects who is actually part of the conversation.
--
-- `chat_messages.is_read` was a single flag shared by everyone on the order,
-- so the store opening a thread cleared the customer's unread badge too.
-- Read state is now tracked per person.

create table if not exists public.chat_reads (
  order_id uuid not null references public.orders(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_read_at timestamptz not null default now(),
  primary key (order_id, user_id)
);

alter table public.chat_reads enable row level security;
drop policy if exists chat_reads_own on public.chat_reads;
create policy chat_reads_own on public.chat_reads
  for select to authenticated using (user_id = (select auth.uid()));

-- Who is in an order's conversation. The store counts once it has spoken in
-- the thread, or while no driver is assigned yet (the customer can only be
-- talking to the store then) — otherwise every customer/driver "I'm at the
-- door" would ping the kitchen.
create or replace function public.chat_participant(p_order public.orders)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select p_order.customer_id = auth.uid()
      or p_order.driver_id = auth.uid()
      or (
        exists (select 1 from public.vendors v
                where v.id = p_order.vendor_id and v.owner_id = auth.uid())
        and (
          p_order.driver_id is null
          or exists (select 1 from public.chat_messages m
                     where m.order_id = p_order.id and m.sender_id = auth.uid())
        )
      );
$$;

create or replace function public.mark_order_chat_read(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_view_order(p_order_id) then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.chat_reads (order_id, user_id, last_read_at)
  values (p_order_id, auth.uid(), now())
  on conflict (order_id, user_id) do update set last_read_at = excluded.last_read_at;
end;
$$;

-- Unread messages from others, in one order or across every conversation.
create or replace function public.my_unread_chat_count(p_order_id uuid default null)
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.chat_messages m
  join public.orders o on o.id = m.order_id
  left join public.chat_reads r on r.order_id = m.order_id and r.user_id = auth.uid()
  where (p_order_id is null or m.order_id = p_order_id)
    and m.sender_id <> auth.uid()
    and m.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)
    -- Nothing older than a month counts as waiting.
    and m.created_at > now() - interval '30 days'
    and public.chat_participant(o);
$$;

create or replace function public.my_order_conversations(p_limit integer default 50)
returns table (
  order_id uuid,
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
  with mine as (
    select o.*
    from public.orders o
    where public.chat_participant(o)
      and exists (select 1 from public.chat_messages m where m.order_id = o.id)
  ),
  last_msg as (
    select distinct on (m.order_id)
      m.order_id, m.message, m.sender_id, m.created_at,
      (m.attachment_url is not null or m.image_url is not null) as has_attachment
    from public.chat_messages m
    join mine on mine.id = m.order_id
    order by m.order_id, m.created_at desc
  )
  select
    o.id,
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
      else 'support'
    end,
    l.sender_id = auth.uid(),
    (
      select count(*)::int from public.chat_messages m2
      left join public.chat_reads r
        on r.order_id = m2.order_id and r.user_id = auth.uid()
      where m2.order_id = o.id
        and m2.sender_id <> auth.uid()
        and m2.created_at > coalesce(r.last_read_at, '-infinity'::timestamptz)
    )
  from mine o
  join last_msg l on l.order_id = o.id
  left join public.vendors v on v.id = o.vendor_id
  left join public.profiles p on p.id = l.sender_id
  order by l.created_at desc
  limit greatest(1, least(p_limit, 100));
$$;

revoke all on function public.chat_participant(public.orders) from public, anon, authenticated;
revoke all on function public.my_unread_chat_count(uuid) from public, anon;
revoke all on function public.my_order_conversations(integer) from public, anon;
grant execute on function public.my_unread_chat_count(uuid) to authenticated;
grant execute on function public.my_order_conversations(integer) to authenticated;
