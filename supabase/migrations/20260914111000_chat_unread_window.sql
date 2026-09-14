-- Per-conversation unread uses the same 30-day window as the total, so the
-- inbox and the badge never disagree; read state is published so a badge
-- clears on every device the moment a thread is opened on one.
do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.my_order_conversations(integer)'::regprocedure);
  n := replace(d,
    'and m2.created_at > coalesce(r.last_read_at, ''-infinity''::timestamptz)',
    'and m2.created_at > coalesce(r.last_read_at, ''-infinity''::timestamptz)
        and m2.created_at > now() - interval ''30 days''');
  if n = d then raise exception 'anchor missing'; end if;
  execute n;
end
$patch$;

do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and tablename = 'chat_reads') then
    alter publication supabase_realtime add table public.chat_reads;
  end if;
end $$;
