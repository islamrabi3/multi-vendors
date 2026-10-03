-- Keys that let an AI tool (Claude) work the admin console on an admin's
-- behalf, through the `admin-mcp` Edge Function.
--
-- A key is not a new kind of account. It stands in for the admin who made it:
-- the function sets that admin as the caller and then goes through the same
-- RPCs and row policies the dashboard does, so a key can never do more than
-- its owner — and stops working the moment the owner is blocked, demoted or
-- deleted.

create table if not exists public.admin_mcp_tokens (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references public.profiles(id) on delete cascade,
  -- What the admin called it ("Laptop", "Claude Desktop"), so a key can be
  -- told apart from the others when one has to go.
  name text not null check (length(btrim(name)) between 1 and 60),
  -- Only the SHA-256 of the key is kept. The key itself is shown once, when
  -- it is made, and cannot be read back by anybody afterwards.
  token_hash text not null unique,
  -- The first characters, enough to recognise a key in a list.
  token_prefix text not null,
  expires_at timestamptz,
  last_used_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists admin_mcp_tokens_admin_idx
  on public.admin_mcp_tokens (admin_id, created_at desc);

alter table public.admin_mcp_tokens enable row level security;

-- An admin sees their own keys; whoever manages staff sees everybody's, the
-- same person who could take the account away altogether.
create policy admin_mcp_tokens_read on public.admin_mcp_tokens
  for select to authenticated
  using (
    (admin_id = (select auth.uid()) and public.is_admin())
    or public.has_permission('staff.manage')
  );

-- No write policy: keys are made and revoked through the functions below.
-- The hash is not readable by clients at all.
revoke all on table public.admin_mcp_tokens from anon, authenticated;
grant select (id, admin_id, name, token_prefix, expires_at, last_used_at,
              revoked_at, created_at)
  on table public.admin_mcp_tokens to authenticated;

-- Whether the current request arrived through the MCP function, and with
-- which key. The function writes these into the request claims itself; a
-- signed-in app session never carries them.
create or replace function public.mcp_request_context()
returns jsonb
language sql
stable
set search_path = public
as $$
  select case
    when c ->> 'via' = 'mcp' then jsonb_build_object(
      'via', 'claude',
      'mcp_token_id', c ->> 'mcp_token_id')
    else '{}'::jsonb
  end
  from (
    select coalesce(
      nullif(current_setting('request.jwt.claims', true), '')::jsonb,
      '{}'::jsonb) as c
  ) s;
$$;

-- Same audit trail as before, now saying when an action was Claude's doing
-- rather than somebody at the dashboard.
create or replace function public.log_admin_action(
  p_action text,
  p_target_type text default null,
  p_target_id uuid default null,
  p_detail jsonb default '{}'::jsonb
)
returns void
language sql
security definer
set search_path = public
as $$
  insert into public.admin_audit_log (actor_id, action, target_type, target_id, detail)
  values (auth.uid(), p_action, p_target_type, p_target_id,
          coalesce(p_detail, '{}'::jsonb) || public.mcp_request_context());
$$;

revoke execute on function public.log_admin_action(text, text, uuid, jsonb)
  from public, anon, authenticated;

-- Makes a key for the calling admin and returns it — the only time it is ever
-- visible.
create or replace function public.admin_mcp_create_token(
  p_name text,
  p_expires_in_days integer default 90
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(coalesce(p_name, ''));
  v_token text;
  v_id uuid;
  v_expires timestamptz;
begin
  if not exists (
    select 1 from public.profiles
    where id = v_uid and role = 'admin'
      and not is_blocked and deleted_at is null
  ) then
    raise exception 'FORBIDDEN';
  end if;
  -- A key must not be able to mint more keys: losing one would then mean
  -- losing an unknown number of them.
  if public.mcp_request_context() <> '{}'::jsonb then
    raise exception 'FORBIDDEN';
  end if;
  if length(v_name) = 0 or length(v_name) > 60 then
    raise exception 'INVALID_NAME';
  end if;
  if p_expires_in_days is null or p_expires_in_days < 1
     or p_expires_in_days > 365 then
    raise exception 'INVALID_EXPIRY';
  end if;
  if (select count(*) from public.admin_mcp_tokens
      where admin_id = v_uid and revoked_at is null
        and (expires_at is null or expires_at > now())) >= 10 then
    raise exception 'TOO_MANY_KEYS';
  end if;

  v_token := 'kin_mcp_' || encode(extensions.gen_random_bytes(32), 'hex');
  v_expires := now() + make_interval(days => p_expires_in_days);

  insert into public.admin_mcp_tokens
    (admin_id, name, token_hash, token_prefix, expires_at)
  values
    (v_uid, v_name, encode(sha256(convert_to(v_token, 'UTF8')), 'hex'),
     left(v_token, 14), v_expires)
  returning id into v_id;

  perform public.log_admin_action('mcp_token.create', 'mcp_token', v_id,
    jsonb_build_object('name', v_name, 'expires_at', v_expires));

  return jsonb_build_object(
    'id', v_id, 'token', v_token, 'expires_at', v_expires);
end;
$$;

revoke execute on function public.admin_mcp_create_token(text, integer)
  from public, anon;
grant execute on function public.admin_mcp_create_token(text, integer)
  to authenticated;

-- Ends a key at once. Its owner may, and so may whoever manages staff.
create or replace function public.admin_mcp_revoke_token(p_token_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner uuid;
begin
  select admin_id into v_owner
  from public.admin_mcp_tokens where id = p_token_id;
  if v_owner is null then
    raise exception 'NOT_FOUND';
  end if;
  if not ((v_owner = auth.uid() and public.is_admin())
          or public.has_permission('staff.manage')) then
    raise exception 'FORBIDDEN';
  end if;

  update public.admin_mcp_tokens
  set revoked_at = coalesce(revoked_at, now())
  where id = p_token_id;

  perform public.log_admin_action('mcp_token.revoke', 'mcp_token', p_token_id);
end;
$$;

revoke execute on function public.admin_mcp_revoke_token(uuid)
  from public, anon;
grant execute on function public.admin_mcp_revoke_token(uuid)
  to authenticated;

-- What the Edge Function asks before it does anything: whose key is this,
-- and is it still good? Returns nothing for a key that is unknown, revoked,
-- expired, or whose owner is no longer an admin in good standing.
create or replace function public.admin_mcp_authenticate(p_token_hash text)
returns table (token_id uuid, admin_id uuid, admin_name text, token_name text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with hit as (
    select t.id, t.admin_id, p.full_name, t.name, t.last_used_at
    from public.admin_mcp_tokens t
    join public.profiles p on p.id = t.admin_id
    where t.token_hash = p_token_hash
      and t.revoked_at is null
      and (t.expires_at is null or t.expires_at > now())
      and p.role = 'admin'
      and not p.is_blocked
      and p.deleted_at is null
  ), touched as (
    -- Once a minute is enough to answer "is this key still in use?" without
    -- writing a row for every tool call.
    update public.admin_mcp_tokens t
    set last_used_at = now()
    from hit
    where t.id = hit.id
      and (hit.last_used_at is null
           or hit.last_used_at < now() - interval '1 minute')
  )
  select hit.id, hit.admin_id, hit.full_name, hit.name from hit;
end;
$$;

-- Never callable by a client: only the function's own database connection.
revoke execute on function public.admin_mcp_authenticate(text)
  from public, anon, authenticated;
grant execute on function public.admin_mcp_authenticate(text) to service_role;

-- Coupons, ads, categories and service areas are written straight to their
-- tables (the row policies are the permission check), so nothing logged them.
-- When Claude is the one writing, that has to leave a record too.
create or replace function public.admin_mcp_log(
  p_action text,
  p_target_type text default null,
  p_target_id uuid default null,
  p_detail jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin()
     or public.mcp_request_context() = '{}'::jsonb then
    raise exception 'FORBIDDEN';
  end if;
  perform public.log_admin_action(p_action, p_target_type, p_target_id, p_detail);
end;
$$;

revoke execute on function public.admin_mcp_log(text, text, uuid, jsonb)
  from public, anon;
grant execute on function public.admin_mcp_log(text, text, uuid, jsonb)
  to authenticated;
