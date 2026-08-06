-- Platform-wide price control.
--
-- The admin can move every menu price at once — by a percentage or by a flat
-- amount — across the whole marketplace, one store, or one store category.
-- Two things make this safe enough to hand to a human:
--
--   * every run is recorded with the exact multiplier/offset it applied, so a
--     mistake can be undone by running the inverse;
--   * prices are floored, never allowed to land at or below zero by a -100%
--     or a large negative offset.
--
-- Option surcharges (`product_options.price_delta`) move with a percentage
-- run, because a percentage that skipped them would silently re-weight every
-- add-on against its base item. A fixed-amount run leaves them alone: adding
-- 5 to a base price is one decision; adding 5 to each of six checkboxes is
-- not what anybody means.

create table if not exists public.price_adjustments (
  id uuid primary key default gen_random_uuid(),
  mode text not null check (mode in ('percent', 'fixed')),
  value numeric(10, 2) not null,
  scope text not null check (scope in ('all', 'vendor', 'category')),
  vendor_id uuid references public.vendors (id) on delete set null,
  category_id uuid references public.vendor_categories (id) on delete set null,
  affected_count int not null default 0,
  applied_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists price_adjustments_created_idx
  on public.price_adjustments (created_at desc);

alter table public.price_adjustments enable row level security;

-- History is admin-only, and only the RPC writes it.
drop policy if exists price_adjustments_select on public.price_adjustments;
create policy price_adjustments_select on public.price_adjustments
  for select to authenticated
  using (public.has_permission('catalog.manage'));

revoke all on public.price_adjustments from anon;

-- Applies the adjustment and returns what it touched.
--
-- `p_min_price` is the floor a price may be pushed down to; it is a parameter
-- rather than a constant because "never below 1" is a business call that
-- differs by market.
create or replace function public.admin_adjust_prices(
  p_mode text,
  p_value numeric,
  p_scope text default 'all',
  p_vendor_id uuid default null,
  p_category_id uuid default null,
  p_min_price numeric default 1
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_affected int := 0;
  v_options int := 0;
  v_id uuid;
begin
  if not public.has_permission('catalog.manage') then
    raise exception 'NOT_AUTHORISED' using errcode = '42501';
  end if;

  if p_mode not in ('percent', 'fixed') then
    raise exception 'INVALID_MODE';
  end if;
  if p_scope not in ('all', 'vendor', 'category') then
    raise exception 'INVALID_SCOPE';
  end if;
  if p_scope = 'vendor' and p_vendor_id is null then
    raise exception 'VENDOR_REQUIRED';
  end if;
  if p_scope = 'category' and p_category_id is null then
    raise exception 'CATEGORY_REQUIRED';
  end if;
  if p_value = 0 then
    raise exception 'VALUE_REQUIRED';
  end if;
  -- -100% would zero the whole menu; anything past it would go negative.
  if p_mode = 'percent' and p_value <= -100 then
    raise exception 'PERCENT_OUT_OF_RANGE';
  end if;
  if p_min_price < 0 then
    raise exception 'INVALID_FLOOR';
  end if;

  with target as (
    select p.id
    from public.products p
    join public.vendors v on v.id = p.vendor_id
    where p_scope = 'all'
       or (p_scope = 'vendor' and p.vendor_id = p_vendor_id)
       or (p_scope = 'category' and v.category_id = p_category_id)
  )
  update public.products p
     set price = greatest(
           round(
             case when p_mode = 'percent'
                  then p.price * (1 + p_value / 100.0)
                  else p.price + p_value
             end,
             2),
           p_min_price)
    from target t
   where t.id = p.id;
  get diagnostics v_affected = row_count;

  -- Surcharges ride along on a percentage run only. `price_delta` may be
  -- negative (a "no cheese, -5" option), so it is not floored the same way —
  -- scaling keeps its sign.
  if p_mode = 'percent' then
    with target as (
      select o.id
      from public.product_options o
      join public.product_option_groups g on g.id = o.group_id
      join public.products p on p.id = g.product_id
      join public.vendors v on v.id = p.vendor_id
      where p_scope = 'all'
         or (p_scope = 'vendor' and p.vendor_id = p_vendor_id)
         or (p_scope = 'category' and v.category_id = p_category_id)
    )
    update public.product_options o
       set price_delta = round(o.price_delta * (1 + p_value / 100.0), 2)
      from target t
     where t.id = o.id;
    get diagnostics v_options = row_count;
  end if;

  insert into public.price_adjustments (
    mode, value, scope, vendor_id, category_id, affected_count, applied_by
  ) values (
    p_mode, p_value, p_scope, p_vendor_id, p_category_id, v_affected, auth.uid()
  )
  returning id into v_id;

  insert into public.admin_audit_log (actor_id, action, target_type, target_id, detail)
  values (
    auth.uid(), 'catalog.prices_adjusted', 'price_adjustment', v_id,
    jsonb_build_object(
      'mode', p_mode, 'value', p_value, 'scope', p_scope,
      'vendor_id', p_vendor_id, 'category_id', p_category_id,
      'products', v_affected, 'options', v_options
    )
  );

  return jsonb_build_object(
    'id', v_id,
    'products', v_affected,
    'options', v_options
  );
end;
$$;

revoke all on function public.admin_adjust_prices(text, numeric, text, uuid, uuid, numeric) from public, anon;
grant execute on function public.admin_adjust_prices(text, numeric, text, uuid, uuid, numeric) to authenticated;

-- How many items a given scope would touch, so the admin sees the blast radius
-- before pressing the button rather than after.
create or replace function public.admin_price_scope_count(
  p_scope text default 'all',
  p_vendor_id uuid default null,
  p_category_id uuid default null
)
returns int
language sql
stable
security definer
set search_path = public
as $$
  select case when public.has_permission('catalog.manage') then (
    select count(*)::int
    from public.products p
    join public.vendors v on v.id = p.vendor_id
    where p_scope = 'all'
       or (p_scope = 'vendor' and p.vendor_id = p_vendor_id)
       or (p_scope = 'category' and v.category_id = p_category_id)
  ) else 0 end;
$$;

revoke all on function public.admin_price_scope_count(text, uuid, uuid) from public, anon;
grant execute on function public.admin_price_scope_count(text, uuid, uuid) to authenticated;
