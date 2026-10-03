-- Platform settings reach apps that are already open.
--
-- The maintenance gate has subscribed to platform_settings since it was
-- written, but the table was never added to the realtime publication, so the
-- switch only reached a phone that restarted. The currency and delivery
-- pricing now ride the same channel, and so does the currency list.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'platform_settings'
  ) then
    alter publication supabase_realtime add table public.platform_settings;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public'
      and tablename = 'currencies'
  ) then
    alter publication supabase_realtime add table public.currencies;
  end if;
end
$$;
