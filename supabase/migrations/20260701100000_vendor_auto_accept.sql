-- Vendors can opt into auto-accepting incoming orders (skips the manual
-- accept/reject step on the dashboard). Defaults off to preserve current
-- behaviour for existing stores.
alter table public.vendors
  add column if not exists auto_accept boolean not null default false;
