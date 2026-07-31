-- ---------------------------------------------------------------------------
-- 1. Stores may not work orders until approved either.
--
-- RLS already hides an unapproved store from customers, but update_order_status
-- only checked ownership — a suspended store could still accept and prepare
-- orders placed before the suspension.
-- ---------------------------------------------------------------------------
create or replace function public.is_vendor_owner(p_vendor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.vendors
    where id = p_vendor_id
      and owner_id = auth.uid()
      and approval_status = 'active'
  );
$$;

-- ---------------------------------------------------------------------------
-- 2. Chat messages notify the other party, server-side.
--
-- Firing from the sender's app meant the push was lost whenever the sender
-- backgrounded the app before the request finished, and the recipient's name
-- and order number had to be fetched by the client that could not read them.
-- ---------------------------------------------------------------------------
create or replace function public.notify_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  select value into v_url from private.app_config where key = 'chat_notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  -- A push must never be able to block a message from being stored.
  begin
    perform net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-notify-secret', v_secret
      ),
      body := jsonb_build_object('message_id', new.id)
    );
  exception when others then
    raise warning 'notify_chat_message failed for %: %', new.id, sqlerrm;
  end;

  return null;
end;
$$;

drop trigger if exists trg_notify_chat_message on public.chat_messages;
create trigger trg_notify_chat_message
  after insert on public.chat_messages
  for each row execute function public.notify_chat_message();
