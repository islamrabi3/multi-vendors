-- An operator may edit a store's menu.
--
-- Menu writes were the store's alone: its owner, or staff granted the 'menu'
-- permission. That left an operator able to import a whole catalogue for a
-- shop but unable to correct one price in it afterwards — the shop had to be
-- talked through the fix, or the import repeated.
--
-- Added here rather than in each policy because every one of them — products,
-- sections, option groups, options — already routes through this function, so
-- one definition keeps them from drifting apart.
create or replace function public.can_edit_vendor_menu(p_vendor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_admin() or public.is_vendor_member(p_vendor_id, 'menu');
$$;
