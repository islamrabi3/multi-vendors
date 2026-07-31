-- Admins hear about new complaints, and customers hear when one is answered.
--
-- Same pattern as notify_order_event: fired by the database so it works no
-- matter which app is open, and posted to an Edge Function that resolves
-- recipients and composes the text in each recipient's language.
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

  -- Fire and forget: a push must never delay or fail the transaction.
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notify-secret', v_secret
    ),
    body := jsonb_build_object('report_id', new.id, 'event', v_event)
  );

  return null;
end;
$$;

drop trigger if exists trg_notify_report_insert on public.customer_reports;
create trigger trg_notify_report_insert
  after insert on public.customer_reports
  for each row execute function public.notify_report_event();

drop trigger if exists trg_notify_report_update on public.customer_reports;
create trigger trg_notify_report_update
  after update on public.customer_reports
  for each row execute function public.notify_report_event();
