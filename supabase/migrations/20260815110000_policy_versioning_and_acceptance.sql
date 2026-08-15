-- Terms a partner must accept, and a record of who accepted which text.
--
-- The operator can already edit `app_content` without shipping a release.
-- That is the useful half and the dangerous half: the moment the text can
-- change under someone who already agreed to it, "they accepted the terms"
-- stops meaning anything unless the *version* they accepted is recorded. So
-- acceptance is stored against a version number, and the number only moves
-- when an admin says the change was material.

alter table public.app_content
  add column if not exists version integer not null default 1,
  -- Marks a document as a gate: partners of the matching role cannot use the
  -- app until they have accepted the current version.
  add column if not exists requires_acceptance boolean not null default false,
  -- Which role is gated. Null for pages everyone merely reads (about,
  -- privacy), so those can never accidentally lock anyone out.
  add column if not exists audience public.user_role;

comment on column public.app_content.version is
  'Bumped by an admin when a change is material enough to re-ask. Editing a '
  'typo should not invalidate every signature already collected.';

create table if not exists public.policy_acceptances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  policy_key text not null references public.app_content (key) on delete cascade,
  -- The version as it stood when they pressed accept, copied rather than
  -- referenced: the whole point is that it must not follow later edits.
  version integer not null,
  accepted_at timestamptz not null default now(),
  -- What they actually agreed to, frozen. A dispute two years from now is
  -- unanswerable if the only copy of the text is the one an admin has since
  -- rewritten.
  body_en_snapshot text not null default '',
  body_ar_snapshot text not null default '',
  unique (user_id, policy_key, version)
);

create index if not exists policy_acceptances_user_idx
  on public.policy_acceptances (user_id, policy_key);

alter table public.policy_acceptances enable row level security;

-- A partner may read their own signatures and nobody else's.
drop policy if exists policy_acceptances_own on public.policy_acceptances;
create policy policy_acceptances_own on public.policy_acceptances
  for select to authenticated using (user_id = auth.uid() or public.is_admin());

-- Deliberately no insert/update/delete policy: acceptances are written only
-- by the SECURITY DEFINER function below, so a client cannot forge one for
-- another user or backdate its own.

create or replace function public.accept_policy(p_key text)
returns void language plpgsql security definer set search_path = public
as $$
declare
  v_doc public.app_content;
  v_role public.user_role;
begin
  if auth.uid() is null then raise exception 'UNAUTHORIZED'; end if;

  select * into v_doc from public.app_content where key = p_key;
  if not found then raise exception 'POLICY_NOT_FOUND'; end if;
  if not v_doc.requires_acceptance then raise exception 'POLICY_NOT_GATED'; end if;

  select role into v_role from public.profiles where id = auth.uid();
  -- Accepting someone else's terms is meaningless and would satisfy the gate
  -- for a document that was never shown.
  if v_doc.audience is not null and v_doc.audience <> v_role then
    raise exception 'POLICY_WRONG_AUDIENCE';
  end if;

  insert into public.policy_acceptances
    (user_id, policy_key, version, body_en_snapshot, body_ar_snapshot)
  values
    (auth.uid(), p_key, v_doc.version,
     coalesce(v_doc.body_en, ''), coalesce(v_doc.body_ar, ''))
  on conflict (user_id, policy_key, version) do nothing;
end;
$$;

grant execute on function public.accept_policy(text) to authenticated;

-- The one document this user still owes, or null. Returned as a row so the
-- app can render it without a second round trip.
create or replace function public.pending_policy()
returns jsonb language plpgsql stable security definer set search_path = public
as $$
declare
  v_role public.user_role;
  v jsonb;
begin
  if auth.uid() is null then return null; end if;
  select role into v_role from public.profiles where id = auth.uid();

  select jsonb_build_object(
           'key', c.key,
           'version', c.version,
           'title_en', c.title_en, 'title_ar', c.title_ar,
           'body_en', c.body_en, 'body_ar', c.body_ar
         )
    into v
  from public.app_content c
  where c.requires_acceptance
    and c.is_published
    and c.audience = v_role
    and not exists (
      select 1 from public.policy_acceptances a
      where a.user_id = auth.uid()
        and a.policy_key = c.key
        and a.version = c.version
    )
  order by c.key
  limit 1;

  return v;
end;
$$;

grant execute on function public.pending_policy() to authenticated;
