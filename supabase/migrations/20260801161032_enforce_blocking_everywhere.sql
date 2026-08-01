-- Blocking previously reached only place_order() and is_online_driver(). A
-- blocked user could still sign in, browse, fill a cart, chat, review, and — if
-- they owned a store — keep trading, because nothing else consulted the flag.

-- 1. A blocked owner's store disappears from the customer catalogue.
--    The owner can still see it (so they understand what happened), and admins
--    can still see everything.
--
--    NOTE: this version inlines a subquery over `profiles` and does not work;
--    `profiles` is itself under RLS, so the owner's row is invisible to the
--    querying customer and the check always passes. Superseded by
--    20260801161132_fix_blocked_vendor_visibility.sql, which routes the lookup
--    through a security definer helper. Kept for history.
drop policy if exists vendors_read on public.vendors;
create policy vendors_read on public.vendors
  for select to public
  using (
    (
      is_active
      and approval_status = 'active'
      and not exists (
        select 1 from public.profiles p
        where p.id = vendors.owner_id
          and (p.is_blocked or p.deleted_at is not null)
      )
    )
    or owner_id = auth.uid()
    or public.is_admin()
  );

-- 2. A blocked store owner cannot edit their own store or catalogue either.
--    is_vendor_owner() is what every vendor-side write policy consults, so one
--    change closes the menu, categories, options and store settings at once.
create or replace function public.is_vendor_owner(p_vendor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.vendors v
    join public.profiles p on p.id = v.owner_id
    where v.id = p_vendor_id
      and v.owner_id = auth.uid()
      and v.approval_status = 'active'
      and not p.is_blocked
      and p.deleted_at is null
  );
$$;

-- 3. The remaining customer-side writes.
drop policy if exists reviews_insert_own on public.reviews;
create policy reviews_insert_own on public.reviews
  for insert to authenticated
  with check (customer_id = auth.uid() and not public.is_blocked());

drop policy if exists chat_messages_send on public.chat_messages;
create policy chat_messages_send on public.chat_messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and not public.is_blocked()
    and public.can_view_order(order_id)
  );
