-- Three things that all needed server support:
--   1. a block that a running session actually notices,
--   2. canned support replies,
--   3. attachments on both chats.

-- ---------------------------------------------------------------------------
-- 1. Blocking reaches a live session.
--
-- Every policy already consults is_blocked(), but the app only ever read the
-- profile row at sign-in: a user who was blocked mid-session kept the screens
-- they were on and met raw "violates row-level security policy" errors instead
-- of being told anything. Publishing `profiles` lets the client subscribe to
-- its own row and react the moment the flag flips.
--
-- Realtime honours RLS, and profiles_select_own limits a subscriber to their
-- own row, so this exposes nothing new.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
  -- The support thread row is streamed by the chat screen for its status, and
  -- was never published either, so "resolved" only appeared on a reopen.
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'support_threads'
  ) then
    alter publication supabase_realtime add table public.support_threads;
  end if;
end $$;

-- Realtime sends the whole row on update; the profile row carries a phone
-- number and an FCM token, and REPLICA IDENTITY FULL would put the *old* row
-- on the wire too. Default (primary key) identity is what we want here.
alter table public.profiles replica identity default;

-- ---------------------------------------------------------------------------
-- 2. Support reply templates.
--
-- The common cases answer themselves. A template is one tap for the customer
-- and posts the platform's standard answer immediately, so nobody waits on an
-- admin for "where is my order". Anything else is the "other" path, which
-- posts no auto-reply and leaves the thread in the queue for a human.
-- ---------------------------------------------------------------------------
create table if not exists public.support_templates (
  key text primary key,
  sort_order int not null default 0,
  label_en text not null,
  label_ar text not null,
  -- Null reply = no automatic answer; the thread waits for an admin.
  reply_en text,
  reply_ar text,
  is_active boolean not null default true
);

alter table public.support_templates enable row level security;

drop policy if exists support_templates_read on public.support_templates;
create policy support_templates_read on public.support_templates
  for select to authenticated using (is_active);

drop policy if exists support_templates_admin_write on public.support_templates;
create policy support_templates_admin_write on public.support_templates
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

insert into public.support_templates
  (key, sort_order, label_en, label_ar, reply_en, reply_ar)
values
  ('order_delayed', 10, 'Order delayed', 'تأخر الطلب',
   'Sorry about the wait. Your order is still with the store or on its way — '
   'the live status on the order screen is always the current one. If it has '
   'not moved in 15 minutes, reply here and an agent will take over.',
   'نعتذر عن التأخير. طلبك ما زال لدى المتجر أو في الطريق إليك، ويمكنك متابعة '
   'الحالة اللحظية من شاشة الطلب. إذا لم تتغير الحالة خلال ١٥ دقيقة، اكتب لنا '
   'هنا وسيتابع معك أحد موظفي الدعم.'),
  ('driver_issue', 20, 'Driver issue', 'مشكلة مع المندوب',
   'Thanks for telling us. We have logged this against the delivery. If the '
   'driver cannot reach you, the order returns to the store and you are not '
   'charged. Add any detail here and an agent will follow it up.',
   'شكرًا لإبلاغنا. تم تسجيل الملاحظة على هذه التوصيلة. إذا تعذّر على المندوب '
   'الوصول إليك يعود الطلب إلى المتجر ولا يتم خصم أي مبلغ. أضف أي تفاصيل هنا '
   'وسيتابعها أحد موظفي الدعم.'),
  ('system_issue', 30, 'System issue', 'مشكلة في التطبيق',
   'Sorry for the trouble. Closing and reopening the app clears most of these. '
   'If it keeps happening, describe what you were doing — a screenshot helps — '
   'and we will look into it.',
   'نأسف لهذه المشكلة. إغلاق التطبيق وفتحه من جديد يحل معظم هذه الحالات. إذا '
   'تكررت المشكلة، اكتب لنا ماذا كنت تفعل — وصورة للشاشة تساعدنا كثيرًا — '
   'وسنقوم بفحصها.'),
  ('other', 99, 'Something else', 'شيء آخر', null, null)
on conflict (key) do update set
  sort_order = excluded.sort_order,
  label_en = excluded.label_en,
  label_ar = excluded.label_ar,
  reply_en = excluded.reply_en,
  reply_ar = excluded.reply_ar,
  is_active = excluded.is_active;

-- An automatic reply is stamped `is_from_admin` so it aligns and reads as
-- support, but it is nobody's message — this separates it from an agent who
-- actually typed, both in the UI and for anyone reading the table later.
alter table public.support_messages
  add column if not exists is_automated boolean not null default false;

-- Posts the customer's chosen template and, when the template has one, the
-- platform's standard answer. Security definer because the auto-reply is
-- `is_from_admin = true`, which support_messages_send rightly refuses to a
-- customer.
create or replace function public.support_send_template(
  p_thread_id uuid,
  p_key text,
  p_locale text default 'en'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_template public.support_templates%rowtype;
  v_label text;
  v_reply text;
  v_admin_id uuid;
begin
  if v_user_id is null then
    raise exception 'UNAUTHORIZED';
  end if;
  if public.is_blocked() then
    raise exception 'ACCOUNT_BLOCKED';
  end if;
  if not exists (
    select 1 from public.support_threads
    where id = p_thread_id and user_id = v_user_id
  ) then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_template
  from public.support_templates where key = p_key and is_active;
  if not found then
    raise exception 'TEMPLATE_NOT_FOUND';
  end if;

  if p_locale = 'ar' then
    v_label := v_template.label_ar;
    v_reply := v_template.reply_ar;
  else
    v_label := v_template.label_en;
    v_reply := v_template.reply_en;
  end if;

  insert into public.support_messages (thread_id, sender_id, is_from_admin, message)
  values (p_thread_id, v_user_id, false, v_label);

  if v_reply is null then
    -- The "something else" path: no canned answer, and the touch trigger has
    -- already left the thread open for an agent to pick up.
    return;
  end if;

  -- The reply is attributed to an admin account so the row satisfies the same
  -- foreign key every other message does. With no admin on the platform yet it
  -- falls back to the thread's own user; `is_from_admin` is what the UI reads.
  select id into v_admin_id
  from public.profiles where role = 'admin' and not is_blocked
    and deleted_at is null
  order by created_at limit 1;

  insert into public.support_messages
    (thread_id, sender_id, is_from_admin, is_automated, message)
  values (p_thread_id, coalesce(v_admin_id, v_user_id), true, true, v_reply);
end;
$$;

revoke execute on function public.support_send_template(uuid, text, text)
  from public, anon;
grant execute on function public.support_send_template(uuid, text, text)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Attachments.
--
-- `chat_messages.image_url` already existed but nothing ever wrote it, and it
-- could only ever hold an image. Both chats now carry one attachment per
-- message, described well enough to render a file row without fetching it.
-- ---------------------------------------------------------------------------
alter table public.chat_messages
  add column if not exists attachment_url text,
  add column if not exists attachment_name text,
  add column if not exists attachment_type text
    check (attachment_type is null or attachment_type in ('image', 'file'));

alter table public.support_messages
  add column if not exists attachment_url text,
  add column if not exists attachment_name text,
  add column if not exists attachment_type text
    check (attachment_type is null or attachment_type in ('image', 'file'));

-- A message that is only an attachment has no text, and `message` is NOT NULL
-- on both tables — the empty string is what the client sends, so nothing here
-- needs relaxing.

-- Private bucket: a support attachment is often a receipt or a screenshot of
-- something personal, so it is served through short-lived signed URLs rather
-- than a public path. Objects are keyed by the uploader's id.
insert into storage.buckets (id, name, public)
values ('chat-attachments', 'chat-attachments', false)
on conflict (id) do nothing;

drop policy if exists "chat attachments upload own" on storage.objects;
create policy "chat attachments upload own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'chat-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
    and not public.is_blocked()
  );

-- Read is open to any signed-in user rather than to the two parties of one
-- order: storage policies cannot see which conversation an object belongs to.
-- The object key is a uuid nobody can guess, and the message row that carries
-- the key is itself behind RLS, so the key never reaches an outsider.
drop policy if exists "chat attachments read" on storage.objects;
create policy "chat attachments read" on storage.objects
  for select to authenticated
  using (bucket_id = 'chat-attachments');

drop policy if exists "chat attachments delete own" on storage.objects;
create policy "chat attachments delete own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'chat-attachments'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
