-- Management roles.
--
-- `role = 'admin'` was all-or-nothing: every admin could block any user, move
-- money, and set a store's commission. One compromised account owned the
-- platform. Roles are created by an admin and carry a set of permissions; an
-- admin with no role assigned keeps full access, so nothing breaks the moment
-- this lands and the first owner can still do everything.

create table if not exists public.admin_roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  name_ar text,
  -- Free-form keys rather than an enum: a new screen should be able to add a
  -- permission without a migration and a deploy in lockstep.
  permissions text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.profiles
  -- Null on an admin means unrestricted — the platform owner. Ignored
  -- entirely for non-admin roles.
  add column if not exists admin_role_id uuid references public.admin_roles(id)
    on delete set null;

comment on column public.profiles.admin_role_id is
  'Which management role this admin holds. NULL on an admin = full access.';

alter table public.admin_roles enable row level security;

drop policy if exists admin_roles_read on public.admin_roles;
create policy admin_roles_read on public.admin_roles
  for select to authenticated using (public.is_admin());

drop policy if exists admin_roles_write on public.admin_roles;
create policy admin_roles_write on public.admin_roles
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- The permission check every admin RPC now goes through.
--
-- Deliberately permissive in one direction: an admin with no role is the
-- owner and passes everything. Restricting somebody is an explicit act.
create or replace function public.has_permission(p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles p
    left join public.admin_roles r on r.id = p.admin_role_id
    where p.id = auth.uid()
      and p.role = 'admin'
      and not p.is_blocked
      and p.deleted_at is null
      and (
        p.admin_role_id is null
        or p_key = any(r.permissions)
        -- A role may be granted everything without listing each key.
        or '*' = any(r.permissions)
      )
  );
$$;

grant execute on function public.has_permission(text) to authenticated;

-- Who did what. Reads are admin-only and there is no update or delete path:
-- an audit trail somebody can edit is not one.
create table if not exists public.admin_audit_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  target_type text,
  target_id uuid,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_log_created_idx
  on public.admin_audit_log (created_at desc);
create index if not exists admin_audit_log_actor_idx
  on public.admin_audit_log (actor_id, created_at desc);

alter table public.admin_audit_log enable row level security;

drop policy if exists admin_audit_read on public.admin_audit_log;
create policy admin_audit_read on public.admin_audit_log
  for select to authenticated using (public.is_admin());

-- Written only by security definer functions, never by a client.
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
  values (auth.uid(), p_action, p_target_type, p_target_id, p_detail);
$$;

revoke execute on function public.log_admin_action(text, text, uuid, jsonb)
  from public, anon, authenticated;

-- Seeded so the permission keys are discoverable rather than folklore. Names
-- match what the screens are called.
insert into public.admin_roles (name, name_ar, permissions) values
  ('Operations', 'العمليات',
   array['orders.view', 'orders.cancel', 'vendors.view', 'drivers.view',
         'support.handle', 'reports.view']),
  ('Catalogue', 'الكتالوج',
   array['vendors.view', 'vendors.approve', 'catalog.manage', 'content.manage',
         'promos.manage', 'ads.manage']),
  ('Finance', 'المالية',
   array['reports.view', 'payments.refund', 'vendors.view', 'vendors.terms',
         'wallets.adjust'])
on conflict (name) do nothing;
