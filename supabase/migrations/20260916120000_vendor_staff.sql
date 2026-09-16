-- Store staff: accounts that work inside one store without being its owner.
--
-- A cashier takes orders and edits the menu; only the owner sees money. The
-- owner's own account keeps every permission implicitly, so nothing about an
-- existing store changes until staff are added.
create table if not exists public.vendor_staff (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid not null references public.vendors(id) on delete cascade,
  -- One person works for one store: the app resolves "my store" from this.
  user_id uuid not null unique references public.profiles(id) on delete cascade,
  full_name text,
  permissions text[] not null default '{}',
  created_at timestamptz not null default now()
);

create index if not exists vendor_staff_vendor_idx on public.vendor_staff (vendor_id);

alter table public.vendor_staff enable row level security;

drop policy if exists vendor_staff_read on public.vendor_staff;
create policy vendor_staff_read on public.vendor_staff
  for select using (
    public.is_admin()
    or user_id = (select auth.uid())
    or exists (
      select 1 from public.vendors v
      where v.id = vendor_id and v.owner_id = (select auth.uid())
    )
  );

-- Written only through the RPCs below, which also keep the login in step.
drop policy if exists vendor_staff_admin_write on public.vendor_staff;
create policy vendor_staff_admin_write on public.vendor_staff
  for all using (public.is_admin()) with check (public.is_admin());

-- The store this user works in: the one they own, or the one they staff.
create or replace function public.vendor_of_user()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select v.id from public.vendors v where v.owner_id = auth.uid() limit 1),
    (select s.vendor_id from public.vendor_staff s where s.user_id = auth.uid() limit 1)
  );
$$;

-- Owner, or staff holding [p_key]. `*` is every key.
create or replace function public.is_vendor_member(p_vendor_id uuid, p_key text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_vendor_owner(p_vendor_id)
      or exists (
        select 1
        from public.vendor_staff s
        join public.vendors v on v.id = s.vendor_id
        join public.profiles p on p.id = s.user_id
        where s.vendor_id = p_vendor_id
          and s.user_id = auth.uid()
          and v.approval_status = 'active'
          and not p.is_blocked
          and p.deleted_at is null
          and (p_key = any(s.permissions) or '*' = any(s.permissions))
      );
$$;

-- One-argument wrapper so the menu policies read as they did before.
create or replace function public.can_edit_vendor_menu(p_vendor_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_vendor_member(p_vendor_id, 'menu');
$$;

grant execute on function public.vendor_of_user() to authenticated;
grant execute on function public.is_vendor_member(uuid, text) to authenticated;
grant execute on function public.can_edit_vendor_menu(uuid) to authenticated;

drop policy if exists vendors_read on public.vendors;
create policy vendors_read on public.vendors
  for select using (
    (is_active and approval_status = 'active' and public.is_owner_active(owner_id))
    or owner_id = (select auth.uid())
    or id = public.vendor_of_user()
    or public.is_admin()
  );

drop policy if exists orders_read on public.orders;
create policy orders_read on public.orders
  for select using (
    public.is_admin()
    or customer_id = (select auth.uid())
    or (
      (payment_method = 'cod' or payment_status = 'paid')
      and (
        driver_id = (select auth.uid())
        or public.is_vendor_member(vendor_id, 'orders')
        or (status = 'ready_for_pickup' and driver_id is null and public.is_online_driver())
      )
    )
  );

-- Every menu policy keeps its shape; only who counts as the store changes.
do $patch$
declare
  r record;
  n text;
begin
  for r in
    select tablename, policyname, cmd, qual, with_check
    from pg_policies
    where schemaname = 'public'
      and tablename in ('products', 'product_categories', 'product_option_groups',
                        'product_options', 'stock_movements')
      and (qual ilike '%is_vendor_owner%' or with_check ilike '%is_vendor_owner%')
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
    n := format(
      'create policy %I on public.%I for %s',
      r.policyname, r.tablename,
      case r.cmd when 'ALL' then 'all' when 'SELECT' then 'select'
                 when 'INSERT' then 'insert' when 'UPDATE' then 'update'
                 else 'delete' end
    );
    if r.qual is not null then
      n := n || ' using (' ||
        replace(r.qual, 'is_vendor_owner(', 'public.can_edit_vendor_menu(') || ')';
    end if;
    if r.with_check is not null then
      n := n || ' with check (' ||
        replace(r.with_check, 'is_vendor_owner(', 'public.can_edit_vendor_menu(') || ')';
    end if;
    execute n;
  end loop;
end
$patch$;

-- A staff member moves orders along exactly as the owner does.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef('public.update_order_status(uuid, order_status, text)'::regprocedure);
  n := replace(
    d,
    'v_is_vendor := public.is_vendor_owner(v_order.vendor_id);',
    'v_is_vendor := public.is_vendor_member(v_order.vendor_id, ''orders'');'
  );
  if n = d then
    raise exception 'update_order_status anchor not found';
  end if;
  execute n;
end
$patch$;
