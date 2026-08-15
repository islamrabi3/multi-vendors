-- Stock, for the shops that have any.
--
-- A restaurant does not run out of koshari in a way worth modelling: it flips
-- an item off the menu when the kitchen stops making it, and `is_available`
-- already says that. A pharmacy or a grocery has a countable number of boxes
-- on a shelf, and selling the last one has to stop the next customer buying
-- it — which nothing here could express.
--
-- So tracking is opt-in per product, defaulted per store. `is_available` keeps
-- its meaning ("we are selling this at all"); `stock_quantity` answers "how
-- many are left", and a tracked product with none left is out of stock without
-- the vendor having to remember to flip anything.

alter table public.vendors
  -- The default for new products in this store. A pharmacy turns it on once
  -- rather than per item.
  add column if not exists tracks_inventory boolean not null default false;

alter table public.products
  add column if not exists track_stock boolean not null default false,
  add column if not exists stock_quantity int not null default 0,
  -- Zero disables the warning; anything above it is "tell me before it runs
  -- out", which is the whole reason a shop wants this.
  add column if not exists low_stock_threshold int not null default 0;

alter table public.products drop constraint if exists products_stock_not_negative;
alter table public.products
  add constraint products_stock_not_negative check (stock_quantity >= 0);

create index if not exists products_low_stock_idx
  on public.products (vendor_id)
  where track_stock and stock_quantity <= low_stock_threshold;

-- Whether a customer can actually buy this right now. One definition, used by
-- the catalogue, the cart and `place_order`, so a product cannot look buyable
-- on one screen and be refused on the next.
create or replace function public.product_is_sellable(
  p_is_available boolean, p_track_stock boolean, p_stock_quantity int)
returns boolean language sql immutable set search_path = ''
as $$
  select coalesce(p_is_available, false)
     and (not coalesce(p_track_stock, false) or coalesce(p_stock_quantity, 0) > 0);
$$;

grant execute on function public.product_is_sellable(boolean, boolean, int)
  to authenticated, anon;

-- Every movement of stock, and why.
--
-- The same reasoning as the money ledger: a shop that cannot explain why it
-- has 3 left instead of 5 cannot trust the number, and "someone edited it" is
-- not an explanation.
create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  vendor_id uuid not null references public.vendors (id) on delete cascade,
  order_id uuid references public.orders (id) on delete set null,
  -- Signed: negative is stock leaving, positive is stock arriving back or
  -- being restocked.
  delta int not null,
  quantity_after int not null,
  -- 'sale' | 'restock' | 'correction' | 'order_cancelled'
  reason text not null default 'correction',
  note text,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists stock_movements_product_idx
  on public.stock_movements (product_id, created_at desc);
create index if not exists stock_movements_vendor_idx
  on public.stock_movements (vendor_id, created_at desc);

alter table public.stock_movements enable row level security;

drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements
  for select to authenticated
  using (public.is_admin() or public.is_vendor_owner(vendor_id));

revoke all on public.stock_movements from anon, authenticated;
grant select on public.stock_movements to authenticated;

-- Moves stock and records why, in one place.
--
-- `p_delta` adjusts relative to what is there; `p_set_to` replaces it. The
-- relative form is what a sale uses and is safe under concurrency; the
-- absolute form is for a stock count, where the shop has just looked at the
-- shelf and the previous number is irrelevant.
create or replace function public.vendor_adjust_stock(
  p_product_id uuid, p_delta int default null, p_set_to int default null,
  p_reason text default 'correction', p_note text default null,
  p_order_id uuid default null)
returns int language plpgsql security definer set search_path = public
as $$
declare v_product public.products%rowtype; v_new int;
begin
  -- Locked, so two sales of the last unit cannot both succeed.
  select * into v_product from public.products where id = p_product_id for update;
  if not found then raise exception 'PRODUCT_NOT_FOUND'; end if;

  if not (public.is_vendor_owner(v_product.vendor_id) or public.is_admin()) then
    raise exception 'FORBIDDEN';
  end if;
  if (p_delta is null) = (p_set_to is null) then
    raise exception 'PASS_EITHER_DELTA_OR_SET_TO';
  end if;

  v_new := coalesce(p_set_to, v_product.stock_quantity + p_delta);
  if v_new < 0 then raise exception 'INSUFFICIENT_STOCK'; end if;

  update public.products
  set stock_quantity = v_new,
      -- Counting stock in implies the shop wants it counted.
      track_stock = case when p_set_to is not null then true else track_stock end
  where id = p_product_id;

  insert into public.stock_movements (
    product_id, vendor_id, order_id, delta, quantity_after, reason, note, created_by
  ) values (
    p_product_id, v_product.vendor_id, p_order_id,
    v_new - v_product.stock_quantity, v_new, p_reason, p_note, auth.uid()
  );

  return v_new;
end;
$$;

revoke all on function public.vendor_adjust_stock(uuid, int, int, text, text, uuid)
  from public, anon;
grant execute on function public.vendor_adjust_stock(uuid, int, int, text, text, uuid)
  to authenticated;

-- What the store needs to deal with today.
create or replace function public.vendor_stock_alerts(p_vendor_id uuid)
returns table(product_id uuid, name text, name_ar text,
  stock_quantity int, low_stock_threshold int, is_out boolean)
language sql stable security definer set search_path = public
as $$
  select p.id, p.name, p.name_ar, p.stock_quantity, p.low_stock_threshold,
         p.stock_quantity <= 0
  from public.products p
  where p.vendor_id = p_vendor_id
    and p.track_stock and p.is_available
    and p.stock_quantity <= greatest(p.low_stock_threshold, 0)
    and (public.is_vendor_owner(p_vendor_id) or public.is_admin())
  order by p.stock_quantity, p.name;
$$;

revoke all on function public.vendor_stock_alerts(uuid) from public, anon;
grant execute on function public.vendor_stock_alerts(uuid) to authenticated;
