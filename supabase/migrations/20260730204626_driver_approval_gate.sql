-- ---------------------------------------------------------------------------
-- Drivers need admin approval, exactly like stores.
--
-- Until now anyone who signed up as a driver could flip themselves online and
-- claim a real customer's order. Approval is enforced in the database, not the
-- app: `is_online_driver()` is what RLS and claim_delivery() both consult, so
-- gating it there closes every path at once.
-- ---------------------------------------------------------------------------
alter table public.drivers
  add column if not exists approval_status text not null default 'pending'
    check (approval_status in ('pending', 'active', 'suspended')),
  add column if not exists approved_at timestamptz,
  add column if not exists rejection_reason text;

-- Drivers who already existed were operating under the old open rule, so they
-- are grandfathered in — leaving them pending would lock out live accounts
-- mid-shift. Only accounts created from here on start as pending.
update public.drivers
set approval_status = 'active', approved_at = now()
where approval_status = 'pending';

create or replace function public.is_online_driver()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.drivers
    where id = auth.uid()
      and is_online
      and approval_status = 'active'
  );
$$;

-- A driver may only present themselves as online once approved. Going online
-- is a plain UPDATE from the app, so the rule lives in a trigger rather than
-- in app code.
create or replace function public.enforce_driver_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.is_online and new.approval_status <> 'active' then
    raise exception 'DRIVER_NOT_APPROVED';
  end if;
  -- Losing approval takes the driver off the road immediately.
  if new.approval_status <> 'active' then
    new.is_online := false;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_driver_approval on public.drivers;
create trigger trg_enforce_driver_approval
  before insert or update on public.drivers
  for each row execute function public.enforce_driver_approval();

-- Admin review of driver applications, mirroring admin_set_vendor_status.
create or replace function public.admin_set_driver_status(
  p_driver_id uuid,
  p_status text,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;
  if p_status not in ('pending', 'active', 'suspended') then
    raise exception 'INVALID_STATUS';
  end if;

  update public.drivers
  set approval_status = p_status,
      approved_at = case when p_status = 'active' then now() else approved_at end,
      rejection_reason = case when p_status = 'active' then null else p_reason end
  where id = p_driver_id;
end;
$$;

revoke execute on function public.admin_set_driver_status(uuid, text, text)
  from public, anon;
grant execute on function public.admin_set_driver_status(uuid, text, text)
  to authenticated;

-- Admins review applications, so they must be able to read every driver row.
drop policy if exists "drivers_admin_all" on public.drivers;
create policy "drivers_admin_all" on public.drivers
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
