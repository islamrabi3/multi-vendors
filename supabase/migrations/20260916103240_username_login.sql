-- Signing in with a username.
--
-- Supabase Auth only knows emails, so a username is a nickname stored on the
-- profile and swapped for its email at sign-in. Lower-cased and unique, so
-- "Eslam" and "eslam" cannot be two people.
alter table public.profiles
  add column if not exists username text;

create unique index if not exists profiles_username_key
  on public.profiles (lower(username))
  where username is not null;

create or replace function public.is_valid_username(p_username text)
returns boolean
language sql
immutable
set search_path = public
as $$
  -- Letters, digits, dot and underscore; 3-20 characters, so it can be read
  -- out and typed without ambiguity.
  select btrim(coalesce(p_username, '')) ~ '^[A-Za-z0-9._]{3,20}$';
$$;

-- Is this name free? Called before the account exists, so it must be readable
-- by anon — it answers yes/no and never reveals whose name it is.
create or replace function public.username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_valid_username(p_username)
     and not exists (
       select 1 from public.profiles
       where lower(username) = lower(btrim(p_username))
     );
$$;

-- The email behind a username, for the sign-in screen.
create or replace function public.email_for_username(p_username text)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select u.email
  from public.profiles p
  join auth.users u on u.id = p.id
  where lower(p.username) = lower(btrim(p_username))
  limit 1;
$$;

create or replace function public.set_my_username(p_username text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_username, ''));
begin
  if auth.uid() is null then
    raise exception 'UNAUTHORIZED';
  end if;
  if not public.is_valid_username(v_name) then
    raise exception 'INVALID_USERNAME';
  end if;
  if exists (
    select 1 from public.profiles
    where lower(username) = lower(v_name) and id <> auth.uid()
  ) then
    raise exception 'USERNAME_TAKEN';
  end if;

  update public.profiles set username = v_name where id = auth.uid();
end;
$$;

grant execute on function public.username_available(text) to anon, authenticated;
grant execute on function public.is_valid_username(text) to anon, authenticated;
grant execute on function public.email_for_username(text) to anon, authenticated;
grant execute on function public.set_my_username(text) to authenticated;

-- A username handed over at signup rides in the user metadata, exactly like
-- the full name and the role.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.handle_new_user()'::regprocedure);
  if d like '%username%' then
    return;
  end if;
  n := replace(d,
    'insert into public.profiles (id, full_name, phone, role, role_confirmed)',
    'insert into public.profiles (id, full_name, phone, role, role_confirmed, username)');
  n := replace(n,
    '    v_meta_role in (''customer'', ''vendor'', ''driver'')
  );',
    '    v_meta_role in (''customer'', ''vendor'', ''driver''),
    case
      when public.is_valid_username(new.raw_user_meta_data ->> ''username'')
        and not exists (
          select 1 from public.profiles
          where lower(username) = lower(btrim(new.raw_user_meta_data ->> ''username''))
        )
      then btrim(new.raw_user_meta_data ->> ''username'')
    end
  );');
  if n = d then
    raise exception 'handle_new_user anchors not found';
  end if;
  execute n;
end
$patch$;
