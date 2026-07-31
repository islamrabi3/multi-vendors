-- Supabase security-advisor cleanup.

-- 1. Pin search_path on functions flagged as mutable (prevents
--    search-path hijacking in SECURITY DEFINER contexts).
alter function public.set_updated_at() set search_path = public;
alter function public.set_order_number() set search_path = public;
alter function public.process_wallet_payment(uuid, numeric, text)
  set search_path = public;
alter function public.earn_loyalty_points(uuid, int, text)
  set search_path = public;
alter function public.top_up_wallet(uuid, numeric) set search_path = public;

-- 2. Anonymous visitors have no business calling mutating RPCs. Every one
--    of these already checks auth.uid() internally; revoking anon just
--    removes the exposed surface. RLS helper predicates (is_admin,
--    is_vendor_owner, is_online_driver, can_view_order) stay callable
--    because row policies evaluate them for every role.
revoke execute on function public.place_order(uuid, public.payment_method, text, text) from anon;
revoke execute on function public.update_order_status(uuid, public.order_status, text) from anon;
revoke execute on function public.claim_delivery(uuid) from anon;
revoke execute on function public.discard_unpaid_order(uuid) from anon;
revoke execute on function public.pay_order_with_wallet(uuid) from anon;
revoke execute on function public.validate_coupon(text, uuid, numeric) from anon;
revoke execute on function public.compute_coupon_discount(text, uuid, numeric) from anon;
revoke execute on function public.order_driver_contact(uuid) from anon;
revoke execute on function public.earn_loyalty_points(uuid, int, text) from anon;
revoke execute on function public.admin_assign_driver(uuid, uuid) from anon;
revoke execute on function public.admin_dashboard_stats() from anon;
revoke execute on function public.admin_set_vendor_status(uuid, text) from anon;
