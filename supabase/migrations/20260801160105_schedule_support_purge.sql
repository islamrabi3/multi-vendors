create extension if not exists pg_cron with schema extensions;

-- Hourly rather than daily: the requirement is "gone after 24 hours", and a
-- daily job would leave a message alive for up to 48.
select cron.unschedule('purge-resolved-support')
where exists (select 1 from cron.job where jobname = 'purge-resolved-support');

select cron.schedule(
  'purge-resolved-support',
  '7 * * * *',
  $$select public.purge_resolved_support_messages();$$
);
