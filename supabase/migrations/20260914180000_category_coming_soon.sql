-- A category the platform is about to open: shown to customers with a
-- "Soon" badge, but not browsable yet.
alter table public.vendor_categories
  add column if not exists is_coming_soon boolean not null default false;
