-- Per-store switch for AI menu extraction.
--
-- Reading a menu out of photographs costs a model call per image, so it is
-- not something every store should be able to run at will. Until now it was
-- admin-only: an operator picked a store and imported on its behalf. This
-- lets an admin hand the tool to a specific store instead, and take it back.
--
-- Default false. Existing stores gain nothing automatically, which is the
-- right default for a feature that spends money per use.
alter table public.vendors
  add column if not exists ai_menu_enabled boolean not null default false;

comment on column public.vendors.ai_menu_enabled is
  'Whether this store may run AI menu extraction itself. Admins can always '
  'import on a store''s behalf regardless of this flag.';

-- Whether the *calling* user is allowed to extract a menu for this store.
--
-- The screen hides the button when the flag is off, but hiding is courtesy:
-- the edge function calls this before spending a model call, so flipping the
-- switch off actually stops the spending rather than just the button.
create or replace function public.can_extract_menu(p_vendor_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_vendor public.vendors%rowtype;
begin
  if auth.uid() is null then return false; end if;

  select * into v_vendor from public.vendors where id = p_vendor_id;
  if not found then return false; end if;

  -- An admin importing on a store's behalf is the original flow and is not
  -- gated by the store's own switch.
  if public.is_admin() then return true; end if;

  -- Otherwise it must be this store's owner, and the switch must be on.
  return v_vendor.owner_id = auth.uid() and v_vendor.ai_menu_enabled;
end;
$$;

grant execute on function public.can_extract_menu(uuid) to authenticated;;
