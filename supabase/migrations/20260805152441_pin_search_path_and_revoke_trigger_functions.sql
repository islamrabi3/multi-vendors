-- 1. Pin search_path on the three functions that still resolved names against
--    the caller's. All three are SECURITY INVOKER, so this is hardening rather
--    than a live hole, but a mutable search_path on a trigger is how a
--    shadowed operator or function turns into someone else's code running.
alter function public.distance_km(double precision, double precision, double precision, double precision)
  set search_path = '';
alter function public.guard_profile_privileged_columns() set search_path = '';
alter function public.stamp_support_resolved() set search_path = '';

-- 2. Trigger functions have no business being callable over REST. Postgres
--    checks EXECUTE when the trigger is created, not when it fires, so the
--    triggers keep working.
revoke execute on function public.apply_review_to_vendor() from anon, authenticated, public;
revoke execute on function public.enforce_driver_approval() from anon, authenticated, public;
revoke execute on function public.guard_profile_privileged_columns() from anon, authenticated, public;
revoke execute on function public.guard_vendor_platform_terms() from anon, authenticated, public;
revoke execute on function public.handle_new_user() from anon, authenticated, public;
revoke execute on function public.log_order_status() from anon, authenticated, public;
revoke execute on function public.notify_chat_message() from anon, authenticated, public;
revoke execute on function public.notify_order_event() from anon, authenticated, public;
revoke execute on function public.notify_report_event() from anon, authenticated, public;
revoke execute on function public.release_coupon_on_cancel() from anon, authenticated, public;
revoke execute on function public.set_order_number() from anon, authenticated, public;
revoke execute on function public.set_updated_at() from anon, authenticated, public;
revoke execute on function public.stamp_support_resolved() from anon, authenticated, public;
revoke execute on function public.sync_coupon_used_count() from anon, authenticated, public;
revoke execute on function public.touch_support_thread() from anon, authenticated, public;

-- 3. Admin RPCs each gate themselves with has_permission/is_admin, so an anon
--    call already fails -- but it fails after doing work, and an unauthenticated
--    caller has no business reaching them at all. Signed-in staff keep access.
do $$
declare f record;
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname like 'admin\_%'
  loop
    execute format('revoke execute on function %s from anon', f.sig);
  end loop;
end $$;
