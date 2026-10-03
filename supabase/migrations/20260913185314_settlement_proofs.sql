-- Proof of payment on settlements. An admin paying a store or taking a
-- driver's cash attaches a receipt photo, and the party can see it.
alter table public.settlements add column if not exists proof_url text;

insert into storage.buckets (id, name, public)
values ('settlement-proofs', 'settlement-proofs', false)
on conflict (id) do nothing;

-- Paths are `<owner_type>/<owner_id>/<file>`.
drop policy if exists settlement_proofs_admin_all on storage.objects;
create policy settlement_proofs_admin_all on storage.objects
  for all to authenticated
  using (bucket_id = 'settlement-proofs' and public.has_permission('finance.settle'))
  with check (bucket_id = 'settlement-proofs' and public.has_permission('finance.settle'));

drop policy if exists settlement_proofs_party_read on storage.objects;
create policy settlement_proofs_party_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'settlement-proofs'
    and (
      ((storage.foldername(name))[1] = 'driver'
        and (storage.foldername(name))[2] = (select auth.uid())::text)
      or ((storage.foldername(name))[1] = 'vendor'
        and exists (
          select 1 from public.vendors v
          where v.id::text = (storage.foldername(name))[2]
            and v.owner_id = (select auth.uid())
        ))
      or public.is_admin()
    )
  );

create or replace function public.admin_attach_settlement_proof(
  p_settlement_id uuid,
  p_path text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.settlements%rowtype;
begin
  if not public.has_permission('finance.settle') then
    raise exception 'FORBIDDEN';
  end if;
  select * into v_row from public.settlements where id = p_settlement_id;
  if not found then raise exception 'NOT_FOUND'; end if;
  -- The file must sit in this settlement's own party folder.
  if p_path is null
     or p_path not like v_row.owner_type::text || '/' || v_row.owner_id::text || '/%' then
    raise exception 'INVALID_PROOF_PATH';
  end if;
  update public.settlements set proof_url = p_path where id = p_settlement_id;
end;
$$;

revoke all on function public.admin_attach_settlement_proof(uuid, text) from public, anon;
grant execute on function public.admin_attach_settlement_proof(uuid, text) to authenticated;
