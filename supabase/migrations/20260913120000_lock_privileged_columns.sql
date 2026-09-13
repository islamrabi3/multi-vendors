-- Closes three privilege escalations reachable with the public API key.
--
-- 1. Signup could name any role. `handle_new_user` cast the client-supplied
--    `raw_user_meta_data.role` straight to `user_role`, so `{"role":"admin"}`
--    in a signup request created an unrestricted admin.
-- 2. A signed-in user could rewrite their own privileged profile columns. The
--    guard only covered `role` / `role_confirmed`, so a restricted staff
--    member could clear `admin_role_id` (becoming an owner) and a blocked user
--    could unblock themselves.
-- 3. A new store could insert itself already approved, commission-free and
--    recommended. The vendor guard ran on UPDATE only. Owners could also set
--    their own rating and switch on the platform-paid AI menu import.
--
-- Trusted SECURITY DEFINER functions (admin RPCs, rating recompute, account
-- deletion) run as their owner, so `current_user` is not `authenticated` /
-- `anon` inside them and the guards step aside. That also fixes
-- `delete_own_account` and `vendor_choose_billing_model`, which failed with
-- PLATFORM_TERMS_ADMIN_ONLY because the old vendor guard was itself SECURITY
-- DEFINER and could not tell a trusted caller from the client.

-- 1. Signup may only choose a public role. ----------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_meta_role text := nullif(new.raw_user_meta_data ->> 'role', '');
  v_role public.user_role := case
    when v_meta_role in ('customer', 'vendor', 'driver')
      then v_meta_role::public.user_role
    else 'customer'::public.user_role
  end;
begin
  insert into public.profiles (id, full_name, phone, role, role_confirmed)
  values (
    new.id,
    coalesce(
      nullif(new.raw_user_meta_data ->> 'full_name', ''),
      nullif(new.raw_user_meta_data ->> 'name', ''),
      ''
    ),
    new.raw_user_meta_data ->> 'phone',
    v_role,
    v_meta_role in ('customer', 'vendor', 'driver')
  );

  if v_role = 'driver' then
    insert into public.drivers (id) values (new.id) on conflict (id) do nothing;
  end if;

  return new;
end;
$function$;

-- 2. Profile columns only staff functions may change. -----------------------
create or replace function public.guard_profile_privileged_columns()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon') and (
       new.role is distinct from old.role
    or new.role_confirmed is distinct from old.role_confirmed
    or new.admin_role_id is distinct from old.admin_role_id
    or new.is_blocked is distinct from old.is_blocked
    or new.blocked_reason is distinct from old.blocked_reason
    or new.blocked_at is distinct from old.blocked_at
    or new.deleted_at is distinct from old.deleted_at
  ) then
    raise exception 'ROLE_CHANGE_NOT_ALLOWED';
  end if;
  return new;
end;
$function$;

-- 3. Vendor platform terms, on insert and update. ---------------------------
-- SECURITY INVOKER on purpose (see header): `current_user` must be the caller.
create or replace function public.guard_vendor_platform_terms()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if not public.is_admin() then
      -- A new store starts where the platform says, whatever the request
      -- carried. `billing_model` is the one term the owner picks at signup.
      new.approval_status := 'pending';
      new.commission_rate := 10.00;
      new.subscription_fee := 0;
      new.subscription_renews_at := null;
      new.delivery_fee := 0;
      new.is_recommended := false;
      new.recommended_rank := 0;
      new.rating_avg := 0;
      new.rating_count := 0;
      new.ai_menu_enabled := false;
      if new.billing_model is null
         or new.billing_model not in ('commission', 'subscription') then
        new.billing_model := 'commission';
      end if;
    end if;
    return new;
  end if;

  if new.delivery_fee is distinct from old.delivery_fee
     or new.commission_rate is distinct from old.commission_rate
     or new.billing_model is distinct from old.billing_model
     or new.subscription_fee is distinct from old.subscription_fee
     or new.subscription_renews_at is distinct from old.subscription_renews_at then
    if not public.has_permission('vendors.terms') then
      raise exception 'PLATFORM_TERMS_ADMIN_ONLY';
    end if;
  end if;

  if new.approval_status is distinct from old.approval_status
     or new.is_recommended is distinct from old.is_recommended
     or new.recommended_rank is distinct from old.recommended_rank
     or new.rating_avg is distinct from old.rating_avg
     or new.rating_count is distinct from old.rating_count
     or new.ai_menu_enabled is distinct from old.ai_menu_enabled then
    if not public.is_admin() then
      raise exception 'PLATFORM_TERMS_ADMIN_ONLY';
    end if;
  end if;

  return new;
end;
$function$;

drop trigger if exists trg_guard_vendor_platform_terms on public.vendors;
create trigger trg_guard_vendor_platform_terms
  before insert or update on public.vendors
  for each row execute function public.guard_vendor_platform_terms();

-- 4. Driver ratings are computed, never self-reported. ----------------------
create or replace function public.guard_driver_rating()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  if current_user in ('authenticated', 'anon')
     and (new.rating_avg is distinct from old.rating_avg
          or new.rating_count is distinct from old.rating_count)
     and not public.is_admin() then
    raise exception 'RATING_READ_ONLY';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_guard_driver_rating on public.drivers;
create trigger trg_guard_driver_rating
  before update on public.drivers
  for each row execute function public.guard_driver_rating();
