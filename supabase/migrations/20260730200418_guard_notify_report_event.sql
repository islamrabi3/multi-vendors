-- Recovered from the project's migration history: this was applied straight to
-- the database and never existed as a file.
--
-- Wraps the outbound push so a notification failure cannot roll back the write
-- that triggered it.

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

  -- A failed push must never stop a customer filing a report or an admin
  -- resolving one.
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
