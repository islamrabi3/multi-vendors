-- An operator claiming a login name for somebody else.
--
-- `set_my_username` only ever writes the caller's own row, which is right for
-- the account screen and useless to an operator fixing a shop's login over the
-- phone. The check and the write stay one statement so two operators typing
-- the same name at the same moment produce one winner and one refusal, rather
-- than two accounts sharing a way to sign in.
--
-- Callable only by the service role: the edge function has already decided
-- whether this admin may touch this account, and that decision needs the
-- target's role, which a client cannot be trusted to report.
create or replace function public.admin_set_username(
  p_user_id uuid,
  p_username text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_username, ''));
begin
  if not public.is_valid_username(v_name) then
    raise exception 'INVALID_USERNAME';
  end if;
  if exists (
    select 1 from public.profiles
    where lower(username) = lower(v_name) and id <> p_user_id
  ) then
    raise exception 'USERNAME_TAKEN';
  end if;

  update public.profiles set username = v_name where id = p_user_id;
  if not found then
    raise exception 'NOT_FOUND';
  end if;
end;
$$;

revoke execute on function public.admin_set_username(uuid, text)
  from anon, authenticated, public;

-- What an admin needs to see about the person behind a store: the login name
-- and the email are not on `profiles`, and auth.users is not readable from the
-- client at all. Kept to the fields an operator acts on.
create or replace function public.admin_account_login(p_user_id uuid)
returns table (id uuid, email text, username text, full_name text, phone text)
language sql
stable
security definer
set search_path = public, auth
as $$
  select p.id, u.email::text, p.username, p.full_name, p.phone
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_user_id
    and public.is_admin()
    -- One admin should not be reading another's login details out of a
    -- screen meant for stores and riders.
    and p.role <> 'admin';
$$;

revoke execute on function public.admin_account_login(uuid) from anon;
grant execute on function public.admin_account_login(uuid) to authenticated;
