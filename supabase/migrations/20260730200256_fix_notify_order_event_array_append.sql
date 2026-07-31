-- Two fixes to the order-notification trigger, both of which broke writes.
--
-- 1. `text[] || 'literal'` makes Postgres resolve the array||array form of the
--    operator and parse the literal as an array, failing with "malformed array
--    literal: status_change". Because the trigger runs inside the UPDATE's
--    transaction, that aborted the write — no role could change an order's
--    status at all.
-- 2. Even with that fixed, a notification fault (pg_net unavailable, a bad
--    config row) would still abort the order write. Notifications are a
--    side effect and must never be able to do that, so the dispatch is now
--    wrapped and downgraded to a warning.
create or replace function public.notify_order_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_events text[] := array[]::text[];
  v_event text;
  v_url text;
  v_secret text;
begin
  select value into v_url from private.app_config where key = 'notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    -- An unpaid card order is still a draft: RLS hides it from the vendor, so
    -- announcing it would be wrong. It is announced once it is paid.
    if new.payment_method = 'paymob' and new.payment_status <> 'paid' then
      return null;
    end if;
    v_events := array['new_order'::text];
  else
    if new.payment_method = 'paymob'
       and new.payment_status = 'paid'
       and old.payment_status <> 'paid' then
      v_events := array['new_order'::text];
    end if;

    if new.status is distinct from old.status then
      v_events := v_events || 'status_change'::text;
      if new.status = 'ready_for_pickup' and new.driver_id is null then
        v_events := v_events || 'ready_for_pickup'::text;
      end if;
      if new.status in ('cancelled', 'rejected') then
        v_events := v_events || 'order_cancelled'::text;
      end if;
    end if;

    if new.driver_id is not null
       and old.driver_id is distinct from new.driver_id then
      v_events := v_events || 'driver_assigned'::text;
    end if;
  end if;

  if array_length(v_events, 1) is null then
    return null;
  end if;

  -- Fire and forget: a push must never delay or fail the transaction.
  begin
    foreach v_event in array v_events loop
      perform net.http_post(
        url := v_url,
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-notify-secret', v_secret
        ),
        body := jsonb_build_object('order_id', new.id, 'event', v_event)
      );
    end loop;
  exception when others then
    raise warning 'notify_order_event failed for order %: %', new.id, sqlerrm;
  end;

  return null;
end;
$$;

-- Same protection for the complaint trigger: a failed push must not stop a
-- customer from filing a report or an admin from resolving one.
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
begin
  select value into v_url from private.app_config where key = 'report_notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    v_event := 'new_report';
  elsif new.status = 'resolved' and old.status <> 'resolved' then
    v_event := 'report_resolved';
  elsif new.admin_reply is not null
        and old.admin_reply is distinct from new.admin_reply then
    v_event := 'report_replied';
  else
    return null;
  end if;

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
