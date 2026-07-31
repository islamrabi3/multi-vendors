-- Recovered from the project's migration history: this was applied straight to
-- the database and never existed as a file, so a `db reset` would have rebuilt
-- a schema without it.
--
-- Where the order-push trigger gets its endpoint and shared secret. Both live
-- in a private schema no client role can reach, so the secret never travels
-- through PostgREST.

create schema if not exists private;

create table if not exists private.app_config (
  key text primary key,
  value text not null
);

alter table private.app_config enable row level security;

revoke all on private.app_config from anon, authenticated;

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
