-- Fix driver approval trigger so suspending an online driver takes them offline cleanly
-- instead of throwing DRIVER_NOT_APPROVED exception during admin status update.

create or replace function public.enforce_driver_approval()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Losing approval takes the driver off the road immediately.
  if new.approval_status <> 'active' then
    new.is_online := false;
  end if;

  if new.is_online and new.approval_status <> 'active' then
    raise exception 'DRIVER_NOT_APPROVED';
  end if;
  return new;
end;
$$;

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
      is_online = case when p_status <> 'active' then false else is_online end,
      approved_at = case when p_status = 'active' then now() else approved_at end,
      rejection_reason = case when p_status = 'active' then null else p_reason end
  where id = p_driver_id;
end;
$$;
