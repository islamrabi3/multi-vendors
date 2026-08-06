-- Repair the stores the reactivation bug already stranded.
--
-- approval_status = 'active' together with is_active = false is a state no
-- deliberate action produces: suspending sets both off, and closing an account
-- sets approval_status = 'suspended' as well. Every row in that combination
-- got there by being suspended and reactivated, and has been invisible to
-- customers ever since while showing "active" to the admin.
update public.vendors
   set is_active = true,
       is_open = true
 where approval_status = 'active'
   and is_active = false;
