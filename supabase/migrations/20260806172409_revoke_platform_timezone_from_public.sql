-- Revoking from `anon` and `authenticated` alone did nothing: Postgres grants
-- EXECUTE to PUBLIC on every new function, and both roles inherit it from
-- there. The PUBLIC grant is the one that has to go.
revoke execute on function public.platform_timezone() from public, anon, authenticated;
