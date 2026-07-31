-- Ask a social sign-in which role they are, and stop anyone from answering
-- "admin" behind the app's back.
--
-- Google/Apple carry no role, so handle_new_user() lands every social account
-- on 'customer' and the user was silently stuck there. We now mark those
-- accounts as unconfirmed and let the app show a role picker once.

-- 1. Which accounts still owe us a role choice.
alter table public.profiles
  add column if not exists role_confirmed boolean not null default true;

comment on column public.profiles.role_confirmed is
  'False only for social sign-ups that have not picked a role yet. The app '
  'routes those users to the role picker before anything else.';

-- 2. A password sign-up carries its role in the signup metadata and is
--    confirmed on arrival; a social sign-up has no metadata role, so it is
--    created unconfirmed.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meta_role text := nullif(new.raw_user_meta_data ->> 'role', '');
  v_role public.user_role := coalesce(v_meta_role::public.user_role, 'customer');
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
    v_meta_role is not null
  );

  if v_role = 'driver' then
    insert into public.drivers (id) values (new.id) on conflict (id) do nothing;
  end if;

  return new;
end;
$$;

-- 3. CRITICAL: profiles_update_own is a plain `auth.uid() = id` policy, so
--    until now any signed-in user could POST
--    `{"role":"admin"}` to /rest/v1/profiles and own the platform. Column-level
--    privileges cannot express "some columns yes, some no" alongside RLS here,
--    so a trigger guards the privileged columns instead. SECURITY DEFINER
--    functions run as the table owner, so the legitimate paths still pass.
create or replace function public.guard_profile_privileged_columns()
returns trigger
language plpgsql
as $$
begin
  if (new.role is distinct from old.role
      or new.role_confirmed is distinct from old.role_confirmed)
     and current_user in ('authenticated', 'anon')
  then
    raise exception 'ROLE_CHANGE_NOT_ALLOWED';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_profiles_guard_role on public.profiles;
create trigger trg_profiles_guard_role
  before update on public.profiles
  for each row execute function public.guard_profile_privileged_columns();

-- 4. The one sanctioned way to answer the picker.
--
--    Narrow on purpose: 'admin' is never selectable, the profile must still be
--    unconfirmed, and the account must be untouched (no orders, no store, no
--    wallet movement) — so this can neither escalate an established user nor be
--    replayed later.
create or replace function public.set_signup_role(p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'UNAUTHORIZED';
  end if;
  if p_role not in ('customer', 'vendor', 'driver') then
    raise exception 'ROLE_NOT_CLAIMABLE';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id and role_confirmed = false
  ) then
    raise exception 'ROLE_ALREADY_SET';
  end if;

  if exists (select 1 from public.orders where customer_id = v_user_id)
     or exists (select 1 from public.vendors where owner_id = v_user_id)
     or exists (select 1 from public.wallet_transactions where user_id = v_user_id)
  then
    raise exception 'ACCOUNT_NOT_NEW';
  end if;

  update public.profiles
  set role = p_role::public.user_role,
      role_confirmed = true
  where id = v_user_id;

  if p_role = 'driver' then
    -- Starts pending: an admin still has to approve the account.
    insert into public.drivers (id) values (v_user_id) on conflict (id) do nothing;
  end if;
end;
$$;

revoke execute on function public.set_signup_role(text) from public, anon;
grant execute on function public.set_signup_role(text) to authenticated;

-- 5. The signup screen still pre-picks a role for social sign-ups; that path
--    now also settles the confirmation flag so the picker is skipped.
create or replace function public.claim_signup_role(p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.set_signup_role(p_role);
end;
$$;

revoke execute on function public.claim_signup_role(text) from public, anon;
grant execute on function public.claim_signup_role(text) to authenticated;
