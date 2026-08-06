-- Wrap bare auth.uid() / auth.role() calls in RLS policies as (select ...).
--
-- Postgres treats a bare auth.uid() in a policy as volatile per row, so it is
-- re-evaluated once for every row scanned. Wrapped in a scalar subquery it
-- becomes an InitPlan: evaluated once for the whole statement. Same semantics,
-- and on the order and message tables the difference is the whole query plan.
--
-- Written as a sweep over pg_policies rather than 39 hand-written ALTERs so it
-- cannot miss one and cannot double-wrap: policies already carrying
-- "( select auth." are skipped.

do $$
declare
  pol record;
  new_qual text;
  new_check text;
  parts text[];
begin
  for pol in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (qual like '%auth.uid()%' or qual like '%auth.role()%'
            or with_check like '%auth.uid()%' or with_check like '%auth.role()%')
  loop
    -- Postgres renders stored expressions with its own spacing; match that
    -- form, not the source text, or nothing here fires.
    new_qual := replace(replace(pol.qual,
                  'auth.uid()', '( SELECT auth.uid())'),
                  'auth.role()', '( SELECT auth.role())');
    new_check := replace(replace(pol.with_check,
                  'auth.uid()', '( SELECT auth.uid())'),
                  'auth.role()', '( SELECT auth.role())');

    -- Already wrapped: a nested rewrite would produce (select (select ...)).
    new_qual := replace(new_qual,
      '( SELECT ( SELECT auth.uid()))', '( SELECT auth.uid())');
    new_check := replace(new_check,
      '( SELECT ( SELECT auth.uid()))', '( SELECT auth.uid())');

    parts := array[]::text[];
    if new_qual is not null and new_qual is distinct from pol.qual then
      parts := parts || format('using (%s)', new_qual);
    end if;
    if new_check is not null and new_check is distinct from pol.with_check then
      parts := parts || format('with check (%s)', new_check);
    end if;
    if array_length(parts, 1) is null then
      continue;
    end if;

    execute format('alter policy %I on %I.%I %s',
      pol.policyname, pol.schemaname, pol.tablename,
      array_to_string(parts, ' '));
  end loop;
end $$;
