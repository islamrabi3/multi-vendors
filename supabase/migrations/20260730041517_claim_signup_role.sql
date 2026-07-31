-- Lets a social sign-up keep the role the user picked on the signup screen.
--
-- Google/Apple carry no role, so handle_new_user() always lands them on
-- 'customer'. The app calls this right after the first OAuth session to apply
-- the chosen role.
--
-- Self-service role changes are a privilege-escalation risk, so this is
-- deliberately narrow:
--   * only 'vendor' or 'driver' — 'admin' can never be claimed here
--   * only from the default 'customer' role
--   * only while the account is still untouched: no orders, no wallet
--     movement, no store already owned
-- An established customer therefore cannot convert their account, and no one
-- can reach admin.
create or replace function public.claim_signup_role(p_role text)
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
  if p_role not in ('vendor', 'driver') then
    raise exception 'ROLE_NOT_CLAIMABLE';
  end if;

  if not exists (
    select 1 from public.profiles
    where id = v_user_id and role = 'customer'
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
  set role = p_role::public.user_role
  where id = v_user_id;

  -- A driver profile needs its drivers row to exist before they can go online.
  if p_role = 'driver' then
    insert into public.drivers (id)
    values (v_user_id)
    on conflict (id) do nothing;
  end if;
end;
$$;

revoke execute on function public.claim_signup_role(text) from public, anon;
grant execute on function public.claim_signup_role(text) to authenticated;
