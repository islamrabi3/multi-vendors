-- Resolved support conversations are purged 24h after resolution.
--
-- `last_message_at` cannot drive this: resolving posts no message, so a thread
-- resolved today but last spoken in a week ago would be purged instantly. The
-- clock starts when the status actually flips.
alter table public.support_threads
  add column if not exists resolved_at timestamptz;

comment on column public.support_threads.resolved_at is
  'When the thread was last marked resolved. Cleared on reopen so a reopened '
  'conversation is never purged mid-discussion.';

create or replace function public.stamp_support_resolved()
returns trigger
language plpgsql
as $$
begin
  if new.status = 'resolved' and old.status is distinct from 'resolved' then
    new.resolved_at := now();
  elsif new.status <> 'resolved' then
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_stamp_support_resolved on public.support_threads;
create trigger trg_stamp_support_resolved
  before update on public.support_threads
  for each row execute function public.stamp_support_resolved();

-- Backfill anything already resolved, so existing rows have a clock to run.
update public.support_threads
set resolved_at = last_message_at
where status = 'resolved' and resolved_at is null;

-- Deletes the messages only. The thread row survives as a record that the
-- conversation happened; without it the inbox would lose the history entirely.
create or replace function public.purge_resolved_support_messages()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_deleted integer;
begin
  with purged as (
    delete from public.support_messages m
    using public.support_threads t
    where m.thread_id = t.id
      and t.status = 'resolved'
      and t.resolved_at is not null
      and t.resolved_at < now() - interval '24 hours'
    returning m.id
  )
  select count(*) into v_deleted from purged;
  return v_deleted;
end;
$$;

-- Only the scheduler calls this; no client role has any business running it.
revoke execute on function public.purge_resolved_support_messages()
  from public, anon, authenticated;
