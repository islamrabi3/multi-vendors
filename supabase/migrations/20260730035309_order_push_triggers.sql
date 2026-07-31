-- Server-side order notifications.
--
-- Pushes used to be fired from the customer's app, which meant the vendor was
-- never told about a new order: the only call site (notifyVendorOfPaidOrder)
-- was never invoked, and for card orders the paying app is long gone by the
-- time the Paymob webhook settles the payment. Firing from a trigger makes
-- the notification independent of which client happens to be running.
create extension if not exists pg_net with schema extensions;

-- Endpoint + shared secret for the trigger. RLS is on with no policies, so
-- no client role can read this table; only SECURITY DEFINER functions and the
-- service role can. The rows are inserted out of band so no credential lives
-- in version control:
--
--   insert into private.app_config(key, value) values
--     ('notify_url', '<project>/functions/v1/order-notify'),
--     ('notify_secret', '<ORDER_NOTIFY_SECRET>');
--
-- The secret matches the ORDER_NOTIFY_SECRET function secret. With either row
-- missing the trigger is a no-op, so placing orders still works.
create schema if not exists private;

create table if not exists private.app_config (
  key text primary key,
  value text not null
);

alter table private.app_config enable row level security;

create or replace function public.notify_order_event()
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
  select value into v_url from private.app_config where key = 'notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  if tg_op = 'INSERT' then
    -- An unpaid card order is still a draft: RLS hides it from the vendor,
    -- so announcing it would be wrong. It is announced once it is paid.
    if new.payment_method = 'paymob' and new.payment_status <> 'paid' then
      return null;
    end if;
    v_event := 'new_order';
  else
    if new.payment_method = 'paymob'
       and new.payment_status = 'paid'
       and old.payment_status <> 'paid' then
      v_event := 'new_order';
    elsif new.status is distinct from old.status then
      v_event := 'status_change';
    else
      return null;
    end if;
  end if;

  -- Fire and forget: a push must never delay or fail the transaction.
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notify-secret', v_secret
    ),
    body := jsonb_build_object('order_id', new.id, 'event', v_event)
  );

  return null;
end;
$$;

drop trigger if exists trg_notify_order_insert on public.orders;
create trigger trg_notify_order_insert
  after insert on public.orders
  for each row execute function public.notify_order_event();

drop trigger if exists trg_notify_order_update on public.orders;
create trigger trg_notify_order_update
  after update on public.orders
  for each row execute function public.notify_order_event();
