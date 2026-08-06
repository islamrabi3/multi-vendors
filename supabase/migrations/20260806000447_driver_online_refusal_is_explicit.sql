-- Going online while unapproved failed silently.
--
-- The trigger forced is_online := false and then tested the coerced value, so
-- the raise could never fire: the update succeeded, the row stayed offline,
-- and the app -- which sets its switch optimistically and only reverts on an
-- error -- showed a driver as online while the server had them offline. They
-- then sat waiting for orders that were never going to come.
--
-- The coercion is still right for the other direction: suspending a driver who
-- is on shift has to take them off the road, not fail. The two cases are told
-- apart by who is moving what.
create or replace function public.enforce_driver_approval()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- A driver asking to go online while not approved is refused outright, so
  -- the client sees a reason instead of a write that quietly did nothing.
  if new.is_online
     and coalesce(old.is_online, false) = false
     and new.approval_status <> 'active' then
    raise exception 'DRIVER_NOT_APPROVED';
  end if;

  -- Losing approval takes the driver off the road immediately: this is an
  -- admin changing approval_status, not a driver claiming to be available.
  if new.approval_status <> 'active' then
    new.is_online := false;
  end if;

  return new;
end;
$$;

revoke execute on function public.enforce_driver_approval()
  from anon, authenticated, public;
