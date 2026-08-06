-- Collapse duplicate permissive policies.
--
-- Permissive policies on the same table and command are OR'd together, so the
-- weakest one decides. Two of these were only a wasted evaluation per row.
-- The third was a hole:
--
--   "Participants can insert order chat" required nothing but
--   auth.uid() = sender_id, which cancelled chat_messages_send's real check
--   (not blocked, and can actually see the order). A blocked user could keep
--   chatting, and any signed-in user could post into any order's thread by
--   knowing its id.
--
-- Verified after applying: the same insert now raises
-- "new row violates row-level security policy for table chat_messages".

-- 1. The dangerous duplicate. chat_messages_send remains and is the only
--    INSERT policy on the table.
drop policy if exists "Participants can insert order chat" on public.chat_messages;

-- 2. Redundant reads already covered by the surviving policy on each table.
drop policy if exists "Drivers can view their tips" on public.driver_tips;
drop policy if exists "Users can view their loyalty history" on public.loyalty_history;

-- 3. Three tables carried a separate "admins can read everything" policy
--    beside the owner policy. One OR'd expression evaluates once instead of
--    twice and reads the same.
drop policy if exists "Admins can view all drivers" on public.drivers;
drop policy if exists "Drivers can view own record" on public.drivers;
create policy drivers_read on public.drivers
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

drop policy if exists "Admins can view all profiles" on public.profiles;
drop policy if exists "Users can view own profile" on public.profiles;
create policy profiles_read on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or public.is_admin());

-- Orders keeps its full shape: the customer always sees their own order, while
-- the store, the assigned driver and the pickup pool only see it once a Paymob
-- order is actually paid.
drop policy if exists "Admins can view all orders" on public.orders;
drop policy if exists "Order participants can view" on public.orders;
create policy orders_read on public.orders
  for select to authenticated
  using (
    public.is_admin()
    or customer_id = (select auth.uid())
    or (
      (payment_method <> 'paymob' or payment_status = 'paid')
      and (
        driver_id = (select auth.uid())
        or public.is_vendor_owner(vendor_id)
        or (status = 'ready_for_pickup'
            and driver_id is null
            and public.is_online_driver())
      )
    )
  );
