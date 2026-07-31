-- Add National ID card and Driver License image URLs to drivers table
alter table public.drivers
  add column if not exists id_card_url text,
  add column if not exists license_url text;

-- Ensure foreign keys referencing service_areas cascade on delete
do $$
begin
  if exists (
    select 1 from information_schema.table_constraints 
    where constraint_name = 'vendor_service_areas_service_area_id_fkey'
  ) then
    alter table public.vendor_service_areas
      drop constraint vendor_service_areas_service_area_id_fkey;

    alter table public.vendor_service_areas
      add constraint vendor_service_areas_service_area_id_fkey
      foreign key (service_area_id) references public.service_areas(id) on delete cascade;
  end if;
end $$;
