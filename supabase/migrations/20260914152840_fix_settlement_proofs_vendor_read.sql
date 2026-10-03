-- The vendor branch compared the folder against storage.foldername(v.name) —
-- the store's display name — instead of the object's path, so no store owner
-- could ever read the proof of a payment made to them.
drop policy if exists settlement_proofs_party_read on storage.objects;
create policy settlement_proofs_party_read on storage.objects
  for select using (
    bucket_id = 'settlement-proofs'
    and (
      (
        (storage.foldername(objects.name))[1] = 'driver'
        and (storage.foldername(objects.name))[2] = (select auth.uid())::text
      )
      or (
        (storage.foldername(objects.name))[1] = 'vendor'
        and exists (
          select 1 from public.vendors v
          where v.id::text = (storage.foldername(objects.name))[2]
            and v.owner_id = (select auth.uid())
        )
      )
      or public.is_admin()
    )
  );
