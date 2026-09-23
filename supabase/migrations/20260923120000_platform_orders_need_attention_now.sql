-- An order waiting for an operator needs one now.
--
-- The Orders badge counts orders that have sat for half an hour: a store that
-- is slow to accept is not an emergency until then. A platform-run store's
-- order is different — no store will ever accept it, the operator is the only
-- one who can, and the customer is waiting on exactly that. So it counts from
-- the moment it can be seen.
do $patch$
declare
  f text;
  d text;
  n text;
begin
  foreach f in array array['admin_action_counts', 'admin_dashboard_stats'] loop
    d := pg_get_functiondef(format('public.%I()', f)::regprocedure);
    if d like '%order_flow%' then
      continue;
    end if;

    n := replace(d,
      'and created_at < now() - interval ''30 minutes''',
      'and (created_at < now() - interval ''30 minutes''
             or (order_flow = ''platform''
                 and status = ''pending''
                 and released_at is not null))');

    if n = d then
      raise exception '% anchors not found', f;
    end if;
    execute n;
  end loop;
end
$patch$;
