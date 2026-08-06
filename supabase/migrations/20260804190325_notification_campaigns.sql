-- Broadcasts from the admin console.
--
-- Every push so far has been one event to one person, sent by a trigger. A
-- campaign is the opposite: one message to a whole audience, composed by hand.
-- It is recorded as a row first and sent second, so a send is never
-- fire-and-forget — there is something to look at afterwards that says who it
-- reached and whether it worked.
create table if not exists public.notification_campaigns (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  -- 'all' | 'customers' | 'vendors' | 'drivers'
  audience text not null default 'all'
    check (audience in ('all', 'customers', 'vendors', 'drivers')),
  -- Where tapping it should land, e.g. '/vendors/<id>'. The app already
  -- routes pushes by a `route` data key.
  deep_link text,
  status text not null default 'draft'
    check (status in ('draft', 'sending', 'sent', 'failed')),
  -- Filled in by the sender so a campaign can be judged after the fact.
  recipients int not null default 0,
  delivered int not null default 0,
  failed int not null default 0,
  error text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  sent_at timestamptz
);

create index if not exists notification_campaigns_created_idx
  on public.notification_campaigns (created_at desc);

alter table public.notification_campaigns enable row level security;

drop policy if exists campaigns_read on public.notification_campaigns;
create policy campaigns_read on public.notification_campaigns
  for select to authenticated using (public.is_admin());

-- Composing is behind its own permission; an operations admin who can answer
-- support tickets has no business messaging every user on the platform.
drop policy if exists campaigns_write on public.notification_campaigns;
create policy campaigns_write on public.notification_campaigns
  for all to authenticated
  using (public.has_permission('notifications.send'))
  with check (public.has_permission('notifications.send'));

-- Who a campaign would reach, before it is sent.
--
-- Counts devices, not accounts: a user with no FCM token cannot be reached at
-- all, and an admin about to message "everyone" should see the real number.
create or replace function public.campaign_audience_size(p_audience text)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select count(*)::int
  from public.profiles p
  where p.fcm_token is not null
    and not p.is_blocked
    and p.deleted_at is null
    and (
      p_audience = 'all'
      or (p_audience = 'customers' and p.role = 'customer')
      or (p_audience = 'vendors' and p.role = 'vendor')
      or (p_audience = 'drivers' and p.role = 'driver')
    );
$$;

grant execute on function public.campaign_audience_size(text) to authenticated;

-- The token list the sender walks. Security definer because `profiles` is
-- readable only to its owner, and revoked from clients: only the edge
-- function's service role calls it.
create or replace function public.campaign_recipients(p_audience text)
returns table (user_id uuid, fcm_token text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.fcm_token
  from public.profiles p
  where p.fcm_token is not null
    and not p.is_blocked
    and p.deleted_at is null
    and (
      p_audience = 'all'
      or (p_audience = 'customers' and p.role = 'customer')
      or (p_audience = 'vendors' and p.role = 'vendor')
      or (p_audience = 'drivers' and p.role = 'driver')
    );
$$;

revoke execute on function public.campaign_recipients(text)
  from public, anon, authenticated;

-- Also lands in each recipient's in-app notification list, so a push that was
-- swiped away is not lost.
create or replace function public.record_campaign_notifications(p_campaign_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_campaign public.notification_campaigns%rowtype;
  v_count int;
begin
  select * into v_campaign
  from public.notification_campaigns where id = p_campaign_id;
  if not found then
    raise exception 'NOT_FOUND';
  end if;

  insert into public.notifications (user_id, title, body, type, route)
  select p.id, v_campaign.title, v_campaign.body, 'announcement',
         v_campaign.deep_link
  from public.profiles p
  where not p.is_blocked
    and p.deleted_at is null
    and (
      v_campaign.audience = 'all'
      or (v_campaign.audience = 'customers' and p.role = 'customer')
      or (v_campaign.audience = 'vendors' and p.role = 'vendor')
      or (v_campaign.audience = 'drivers' and p.role = 'driver')
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke execute on function public.record_campaign_notifications(uuid)
  from public, anon;
grant execute on function public.record_campaign_notifications(uuid)
  to authenticated;
