-- Real bug: a customer whose support thread staff replied to received no
-- notification of any kind. Order chat (`chat_messages`) has had a push
-- trigger since `notify_chat_message`; the support inbox (`support_messages`)
-- only ever had `touch_support_thread`, which just bumps the thread's
-- timestamp/status. Nothing told the customer their ticket had an answer.
create or replace function public.notify_support_message()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
begin
  -- Only a staff reply is worth a push; the customer's own message is not
  -- something they need to be notified about.
  if not new.is_from_admin then
    return null;
  end if;

  select value into v_url from private.app_config where key = 'support_notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

  -- A push must never be able to block the reply from being stored.
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
    raise warning 'notify_support_message failed for %: %', new.id, sqlerrm;
  end;

  return null;
end;
$$;

create trigger trg_notify_support_message
  after insert on public.support_messages
  for each row execute function public.notify_support_message();

insert into private.app_config (key, value)
values ('support_notify_url',
        'https://dvfbeaafekqdcwxogbqc.supabase.co/functions/v1/support-notify')
on conflict (key) do update set value = excluded.value;;
