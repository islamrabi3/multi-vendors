-- Complaints become a conversation.
--
-- A complaint used to be one description and, at most, one admin reply that
-- also closed it. The customer had nowhere to follow it up, add details, or
-- answer the reply they were pushed about. Each complaint now carries a thread
-- of messages; the original description stays on the complaint itself.

alter table public.customer_reports
  add column if not exists last_message_at timestamptz,
  add column if not exists last_message_from_admin boolean not null default false,
  add column if not exists customer_read_at timestamptz;

-- True while support has said something the customer has not opened yet.
alter table public.customer_reports
  add column if not exists has_unread_reply boolean
  generated always as (
    last_message_from_admin
    and last_message_at is not null
    and (customer_read_at is null or customer_read_at < last_message_at)
  ) stored;

create table if not exists public.customer_report_messages (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references public.customer_reports(id) on delete cascade,
  sender_id uuid references auth.users(id) on delete set null,
  is_from_admin boolean not null default false,
  message text not null check (length(btrim(message)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists customer_report_messages_report_idx
  on public.customer_report_messages (report_id, created_at);
create index if not exists customer_report_messages_sender_idx
  on public.customer_report_messages (sender_id);

alter table public.customer_report_messages enable row level security;

-- Readable by the complaint's owner and by admins. There is no insert policy:
-- messages are written only through report_send_message, which also keeps
-- the complaint row's status and counters in step.
drop policy if exists customer_report_messages_read on public.customer_report_messages;
create policy customer_report_messages_read on public.customer_report_messages
  for select using (
    public.is_admin()
    or exists (
      select 1 from public.customer_reports r
      where r.id = report_id and r.user_id = (select auth.uid())
    )
  );

-- Existing replies become the first message of their thread, already read.
insert into public.customer_report_messages (report_id, is_from_admin, message, created_at)
select r.id, true, r.admin_reply, r.updated_at
from public.customer_reports r
where nullif(btrim(r.admin_reply), '') is not null
  and not exists (
    select 1 from public.customer_report_messages m where m.report_id = r.id
  );

update public.customer_reports r
set last_message_at = r.updated_at,
    last_message_from_admin = true,
    customer_read_at = r.updated_at
where nullif(btrim(r.admin_reply), '') is not null
  and r.last_message_at is null;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'customer_report_messages'
  ) then
    alter publication supabase_realtime add table public.customer_report_messages;
  end if;
end $$;

-- Posts to a complaint's thread.
--
-- The customer may always write: a reply on a resolved complaint reopens it,
-- since "this is still not fixed" is exactly what they would be saying.
-- An admin may also close the complaint in the same call, so the customer
-- gets one notification ("resolved") instead of two.
create or replace function public.report_send_message(
  p_report_id uuid,
  p_message text,
  p_resolve boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_admin boolean := public.is_admin();
  v_text text := btrim(coalesce(p_message, ''));
  v_id uuid;
  v_now timestamptz := now();
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select user_id into v_owner
  from public.customer_reports where id = p_report_id
  for update;
  if v_owner is null then
    raise exception 'REPORT_NOT_FOUND';
  end if;

  -- An admin who filed a complaint as a customer still writes as support.
  if not v_admin and v_owner <> v_uid then
    raise exception 'FORBIDDEN';
  end if;
  if p_resolve and not v_admin then
    raise exception 'FORBIDDEN';
  end if;
  if length(v_text) = 0 and not p_resolve then
    raise exception 'EMPTY_MESSAGE';
  end if;
  if length(v_text) > 2000 then
    raise exception 'MESSAGE_TOO_LONG';
  end if;

  if length(v_text) > 0 then
    insert into public.customer_report_messages (report_id, sender_id, is_from_admin, message, created_at)
    values (p_report_id, v_uid, v_admin, v_text, v_now)
    returning id into v_id;
  end if;

  update public.customer_reports
  set status = case
        when p_resolve then 'resolved'
        when not v_admin then 'pending'
        else status
      end,
      admin_reply = case when v_admin and v_id is not null then v_text else admin_reply end,
      last_message_at = case when v_id is not null then v_now else last_message_at end,
      last_message_from_admin = case when v_id is not null then v_admin else last_message_from_admin end,
      -- Writing in the thread means having read it.
      customer_read_at = case when not v_admin then v_now else customer_read_at end,
      updated_at = v_now
  where id = p_report_id;

  return v_id;
end;
$$;

revoke all on function public.report_send_message(uuid, text, boolean) from public, anon;
grant execute on function public.report_send_message(uuid, text, boolean) to authenticated;

-- The customer opened the thread: clears the "new reply" dot.
create or replace function public.mark_report_read(p_report_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update public.customer_reports
  set customer_read_at = now()
  where id = p_report_id and user_id = auth.uid();
$$;

revoke all on function public.mark_report_read(uuid) from public, anon;
grant execute on function public.mark_report_read(uuid) to authenticated;

-- Push + inbox for complaint events.
--
-- One event per change, most significant first: a complaint that was just
-- resolved says so even when a closing reply came with it.
create or replace function public.notify_report_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event text;
  v_url text;
  v_secret text;
  v_locale text;
  v_title text;
  v_body text;
begin
  if tg_op = 'INSERT' then
    v_event := 'new_report';
  elsif new.status = 'resolved' and old.status <> 'resolved' then
    v_event := 'report_resolved';
  elsif new.last_message_at is distinct from old.last_message_at then
    v_event := case when new.last_message_from_admin
                    then 'report_replied' else 'report_customer_reply' end;
  elsif new.admin_reply is not null
        and old.admin_reply is distinct from new.admin_reply then
    -- Older app builds still write admin_reply directly.
    v_event := 'report_replied';
  else
    return null;
  end if;

  -- The customer's inbox keeps the event after the push is gone, and a tap
  -- opens the complaint thread.
  if v_event in ('report_replied', 'report_resolved') then
    select locale into v_locale from public.profiles where id = new.user_id;
    if v_event = 'report_resolved' then
      v_title := case when v_locale = 'ar' then 'تم حل الشكوى' else 'Complaint resolved' end;
    else
      v_title := case when v_locale = 'ar' then 'رد جديد على شكواك' else 'New reply to your complaint' end;
    end if;
    v_body := left(coalesce(nullif(new.admin_reply, ''), new.subject, ''), 140);
    insert into public.notifications (user_id, title, body, type, route)
    values (new.user_id, v_title, v_body, 'complaint', '/complaints/' || new.id);
  end if;

  select value into v_url from private.app_config where key = 'report_notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  -- A failed push must never stop a customer filing a report or an admin
  -- resolving one.
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-notify-secret', v_secret
      ),
      body := jsonb_build_object('report_id', new.id, 'event', v_event)
    );
  exception when others then
    raise warning 'notify_report_event failed for report %: %', new.id, sqlerrm;
  end;

  return null;
end;
$$;
