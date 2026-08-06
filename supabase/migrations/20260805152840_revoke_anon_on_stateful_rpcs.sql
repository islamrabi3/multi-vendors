-- Anonymous callers can reach every SECURITY DEFINER function granted to
-- PUBLIC. Most of them are harmless for a guest -- catalogue search, ad
-- slots, and the is_*/has_permission predicates that RLS itself evaluates as
-- anon, all of which must stay reachable or browsing breaks.
--
-- These are the ones that change state or reveal another person's details.
-- They all derive identity from auth.uid(), which is null for a guest, so they
-- would fail anyway -- but failing after taking a row lock or writing an audit
-- row is not the same as never being callable.
do $$
declare
  f record;
  targets text[] := array[
    'place_order', 'pay_order_with_wallet', 'update_order_status',
    'claim_delivery', 'discard_unpaid_order', 'mark_notifications_read',
    'order_driver_contact', 'recompute_driver_rating', 'recompute_vendor_rating',
    'campaign_audience_size', 'my_permissions', 'add_driver_tip',
    'delete_own_account', 'account_deletion_blockers', 'claim_signup_role'
  ];
begin
  for f in
    select p.oid::regprocedure as sig
      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public' and p.proname = any(targets)
  loop
    execute format('revoke execute on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated, service_role', f.sig);
  end loop;
end $$;
