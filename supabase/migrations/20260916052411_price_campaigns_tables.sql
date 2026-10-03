create table if not exists public.price_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  markup_percent numeric not null check (markup_percent > 0 and markup_percent <= 100),
  scope text not null default 'all' check (scope in ('all', 'vendor', 'category')),
  vendor_id uuid references public.vendors(id) on delete cascade,
  category_id uuid references public.vendor_categories(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'scheduled'
    check (status in ('scheduled', 'active', 'ended')),
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  ended_at timestamptz
);

-- What each product cost before the campaign touched it, and what it was
-- raised to. Restoring reads this rather than recomputing, so a rounding rule
-- that changes later can never leave a price slightly wrong forever.
create table if not exists public.price_campaign_items (
  campaign_id uuid not null references public.price_campaigns(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  base_price numeric not null,
  applied_price numeric not null,
  primary key (campaign_id, product_id)
);

create index if not exists price_campaign_items_product_idx
  on public.price_campaign_items (product_id);

alter table public.price_campaigns enable row level security;
alter table public.price_campaign_items enable row level security;

drop policy if exists price_campaigns_read on public.price_campaigns;
create policy price_campaigns_read on public.price_campaigns
  for select using (public.is_admin());

drop policy if exists price_campaign_items_read on public.price_campaign_items;
create policy price_campaign_items_read on public.price_campaign_items
  for select using (public.is_admin());

-- Every order line remembers the store's own price, so the payout can be
-- computed on it however the menu price moves afterwards.
alter table public.order_items
  add column if not exists base_unit_price numeric;

alter table public.orders
  add column if not exists markup_amount numeric not null default 0;

create or replace function public.set_order_item_base_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_base numeric;
  v_applied numeric;
begin
  if new.base_unit_price is not null or new.product_id is null then
    return new;
  end if;

  select i.base_price, i.applied_price
  into v_base, v_applied
  from public.price_campaign_items i
  join public.price_campaigns c on c.id = i.campaign_id
  where i.product_id = new.product_id and c.status = 'active'
  order by c.started_at desc nulls last
  limit 1;

  -- Options are never marked up, so only the product's own uplift comes off.
  new.base_unit_price := case
    when v_base is null then new.unit_price
    else greatest(new.unit_price - (v_applied - v_base), 0)
  end;
  return new;
end;
$$;

drop trigger if exists trg_order_items_base_price on public.order_items;
create trigger trg_order_items_base_price
  before insert on public.order_items
  for each row execute function public.set_order_item_base_price();

-- The order's total uplift, kept on the order so the reports can take it off
-- the store's sales without re-reading every line.
create or replace function public.accumulate_order_markup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.orders
  set markup_amount = round(
    coalesce(markup_amount, 0)
    + (coalesce(new.unit_price, 0) - coalesce(new.base_unit_price, new.unit_price))
      * coalesce(new.quantity, 0), 2)
  where id = new.order_id;
  return null;
end;
$$;

drop trigger if exists trg_order_items_markup on public.order_items;
create trigger trg_order_items_markup
  after insert on public.order_items
  for each row execute function public.accumulate_order_markup();
