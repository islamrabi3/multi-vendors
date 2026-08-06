-- Follow-up hardening on the three functions the category tree added.

-- 1. `vendors_in_category` was SECURITY DEFINER, which skipped RLS — and the
--    `vendors_read` policy carries a condition the function did not repeat:
--    `is_owner_active(owner_id)`. A store whose owner had been blocked or
--    deleted was therefore ranked into the category page's id list. Nothing
--    here needs elevated rights: `vendors` and `vendor_categories` are both
--    readable by anon under their own policies, so INVOKER is both correct and
--    the safer default.
create or replace function public.vendors_in_category(p_category_id uuid)
returns setof public.vendors
language sql
stable
security invoker
set search_path = public
as $$
  select v.*
  from public.vendors v
  where v.is_active
    and v.approval_status = 'active'
    and (
      v.category_id = p_category_id
      or v.category_id in (
        select id from public.vendor_categories where parent_id = p_category_id
      )
    )
  order by v.is_open desc, v.rating_avg desc;
$$;

grant execute on function public.vendors_in_category(uuid) to authenticated, anon;

-- 2. Pin the search_path, matching what 20260805152441 did to every other
--    function. It reads no tables, but an unpinned path is the same class of
--    finding wherever it appears.
create or replace function public.time_within_window(
  p_time time,
  p_open time,
  p_close time
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select case
    when p_open = p_close then true              -- 24 hours
    when p_close > p_open then p_time >= p_open and p_time < p_close
    else p_time >= p_open or p_time < p_close    -- spans midnight
  end;
$$;

grant execute on function public.time_within_window(time, time, time) to authenticated, anon;

-- 3. `platform_timezone` reads `private.app_config`, which is deliberately
--    unreadable by clients. It has to stay SECURITY DEFINER for
--    `vendor_is_open_now` to use it, but nothing outside the database has any
--    business calling it, so it comes off the REST surface.
revoke execute on function public.platform_timezone() from anon, authenticated;
