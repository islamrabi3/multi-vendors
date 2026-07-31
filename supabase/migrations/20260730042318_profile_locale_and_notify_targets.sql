-- Recovered from the project's migration history: this was applied straight to
-- the database and never existed as a file.

-- Push notifications have to be written in the recipient's language, and the
-- server is the one composing them, so the app records which language each
-- user is reading the UI in.
alter table public.profiles
  add column if not exists locale text not null default 'en'
    check (locale in ('en', 'ar'));

-- Drivers and admins need to hear about orders too, so the trigger now reports
-- more than the two customer/vendor events:
--   new_order        -> vendor owner
--   status_change    -> customer
--   ready_for_pickup -> every online driver (a job is up for grabs)
--   driver_assigned  -> the assigned driver
--   order_cancelled  -> admins (an operator should notice cancellations)
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
    v_events := array['new_order'];
  else
    if new.payment_method = 'paymob'
       and new.payment_status = 'paid'
       and old.payment_status <> 'paid' then
      v_events := array['new_order'];
    end if;

    if new.status is distinct from old.status then
      v_events := v_events || 'status_change';
      if new.status = 'ready_for_pickup' and new.driver_id is null then
        v_events := v_events || 'ready_for_pickup';
      end if;
      if new.status in ('cancelled', 'rejected') then
        v_events := v_events || 'order_cancelled';
      end if;
    end if;

    if new.driver_id is not null and old.driver_id is distinct from new.driver_id then
      v_events := v_events || 'driver_assigned';
    end if;
  end if;

  if array_length(v_events, 1) is null then
    return null;
  end if;

  -- Fire and forget: a push must never delay or fail the transaction.
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

  return null;
end;
$$;
