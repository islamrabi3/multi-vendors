-- The push from notify_support_message reaches a device with a live FCM
-- token; the in-app bell is what a customer sees if they had none, or opened
-- the app a day later. Same pattern as notify_settlement.
create or replace function public.notify_support_message()
returns trigger language plpgsql security definer
set search_path = public
as $$
declare
  v_url text;
  v_secret text;
  v_user uuid;
begin
  if not new.is_from_admin then
    return null;
  end if;

  select user_id into v_user from public.support_threads where id = new.thread_id;
  if v_user is not null then
    insert into public.notifications (user_id, title, body, type, route)
    values (v_user, 'Support replied',
            left(coalesce(new.message, ''), 140), 'support', '/support');
  end if;

  select value into v_url from private.app_config where key = 'support_notify_url';
  select value into v_secret from private.app_config where key = 'notify_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;

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
$$;;
