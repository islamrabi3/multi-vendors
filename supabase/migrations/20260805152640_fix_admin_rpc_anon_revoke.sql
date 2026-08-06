-- The previous migration revoked the admin RPCs from `anon` and anon still
-- reached them: EXECUTE was granted to PUBLIC, which anon inherits, so a
-- revoke aimed at the role alone removes nothing. The grant has to come off
-- PUBLIC and go back on explicitly.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'admin\_%'
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
  end loop;
end $$;
