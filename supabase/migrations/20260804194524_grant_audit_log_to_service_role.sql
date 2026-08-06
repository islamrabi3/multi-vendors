-- The staff-creation edge function runs as service_role and records what it
-- did. EXECUTE was revoked from PUBLIC when the function was created, and
-- service_role is not a member of that, so it needs the grant explicitly —
-- otherwise creating a staff account silently leaves no audit entry.
grant execute on function public.log_admin_action(text, text, uuid, jsonb)
  to service_role;
