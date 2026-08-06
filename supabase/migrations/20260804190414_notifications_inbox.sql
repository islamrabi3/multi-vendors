-- An in-app notification list.
--
-- Until now the bell screen was derived entirely from the customer's orders,
-- which works for "your order is on the way" and not at all for anything else:
-- a broadcast that exists only as a push is gone the moment it is swiped away.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null default '',
  -- 'announcement' | 'order' | 'support' | 'promo'
  type text not null default 'announcement',
  -- Where tapping it goes. Null just marks it read.
  route text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists notifications_user_idx
  on public.notifications (user_id, created_at desc);
create index if not exists notifications_unread_idx
  on public.notifications (user_id) where not is_read;

alter table public.notifications enable row level security;

drop policy if exists notifications_read_own on public.notifications;
create policy notifications_read_own on public.notifications
  for select to authenticated using (user_id = auth.uid());

-- The only thing a recipient may change is whether they have read it.
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists notifications_delete_own on public.notifications;
create policy notifications_delete_own on public.notifications
  for delete to authenticated using (user_id = auth.uid());

-- Rows are written by security definer functions only; no client inserts, or
-- anyone could post an "announcement" into someone else's inbox.

create or replace function public.mark_notifications_read()
returns void
language sql
security definer
set search_path = public
as $$
  update public.notifications
  set is_read = true
  where user_id = auth.uid() and not is_read;
$$;

grant execute on function public.mark_notifications_read() to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;
