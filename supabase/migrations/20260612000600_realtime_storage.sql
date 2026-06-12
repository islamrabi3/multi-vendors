-- Realtime publication + storage buckets.

-- Filtered realtime streams need full old/new rows.
alter table public.orders replica identity full;
alter table public.drivers replica identity full;

alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.drivers;

-- Public-read buckets for vendor branding and product images.
insert into storage.buckets (id, name, public)
values
  ('vendor-assets', 'vendor-assets', true),
  ('product-images', 'product-images', true)
on conflict (id) do nothing;

create policy "marketplace_assets_read" on storage.objects
  for select using (bucket_id in ('vendor-assets', 'product-images'));

create policy "marketplace_assets_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id in ('vendor-assets', 'product-images'));

create policy "marketplace_assets_update" on storage.objects
  for update to authenticated
  using (bucket_id in ('vendor-assets', 'product-images') and owner = auth.uid());

create policy "marketplace_assets_delete" on storage.objects
  for delete to authenticated
  using (bucket_id in ('vendor-assets', 'product-images') and owner = auth.uid());
