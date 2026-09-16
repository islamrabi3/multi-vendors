-- Order lines snapshot the product name, but only the English one, so an
-- Arabic reader saw English item names on every order screen. The Arabic
-- name is snapshotted alongside it, filled from the product when the line is
-- written, so place_order and every other writer get it without changes.
alter table public.order_items add column if not exists product_name_ar text;

create or replace function public.order_items_snapshot_name_ar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.product_name_ar is null and new.product_id is not null then
    select nullif(btrim(name_ar), '') into new.product_name_ar
    from public.products where id = new.product_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_order_items_name_ar on public.order_items;
create trigger trg_order_items_name_ar
  before insert on public.order_items
  for each row execute function public.order_items_snapshot_name_ar();

-- Existing lines: the current Arabic name is the best record there is.
update public.order_items oi
set product_name_ar = nullif(btrim(p.name_ar), '')
from public.products p
where p.id = oi.product_id and oi.product_name_ar is null;
