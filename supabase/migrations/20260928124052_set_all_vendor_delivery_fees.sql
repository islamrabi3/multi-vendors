-- One delivery fee for every store, in one step.
--
-- With the platform pricing delivery per store, changing the fee meant
-- opening every store's page. This sets the same flat fee on all of them
-- (or only on the active ones) and returns how many changed. Orders already
-- placed keep the fee they were charged.
create or replace function public.admin_set_all_vendor_delivery_fees(
  p_fee numeric,
  p_active_only boolean default false
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  if not public.has_permission('finance.adjust') then
    raise exception 'FORBIDDEN';
  end if;
  if p_fee is null or p_fee < 0 then
    raise exception 'INVALID_AMOUNT';
  end if;

  update public.vendors
  set delivery_fee = round(p_fee, 2)
  where (not p_active_only or approval_status = 'active')
    and delivery_fee is distinct from round(p_fee, 2);
  get diagnostics v_count = row_count;

  perform public.log_admin_action('vendor.delivery_fee_all', 'vendor', null,
    jsonb_build_object('fee', p_fee, 'active_only', p_active_only,
                       'changed', v_count));
  return v_count;
end;
$$;

revoke all on function public.admin_set_all_vendor_delivery_fees(numeric, boolean) from public, anon;
grant execute on function public.admin_set_all_vendor_delivery_fees(numeric, boolean) to authenticated;
