-- Security pass finding: `compute_coupon_discount` takes `p_user_id` as a
-- *direct, caller-supplied* parameter (default null, falling back to
-- `auth.uid()` only when omitted) and was reachable by `anon` — meaning
-- anyone, signed in or not, could call it over REST with an arbitrary user
-- id and learn from the exception it raises whether that person has already
-- used a given coupon (`COUPON_ALREADY_USED`) or placed an order before
-- (`COUPON_FIRST_ORDER_ONLY`). A real per-user information leak, if a modest
-- one — the app itself never calls this function directly, only through
-- `preview_coupon`, which pins `p_user_id` to the caller's own `auth.uid()`
-- and cannot be used to probe anyone else.
revoke all on function public.compute_coupon_discount(
  text, uuid, numeric, numeric, uuid) from anon, authenticated;;
