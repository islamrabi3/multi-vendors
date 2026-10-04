-- Gate both on `finance.settle`, the permission that already gates the
-- settlements screen this control lives on. `reports.view` was wrong: a role
-- that runs payouts but reads no reports would have hit FORBIDDEN opening its
-- own screen.
create or replace function public.admin_early_settlement_fee()
returns jsonb language plpgsql stable security definer
set search_path = public, private
as $$
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'fee_percent', public.early_settlement_fee_percent(),
    'fee_min', public.early_settlement_fee_min());
end;
$$;

create or replace function public.admin_set_early_settlement_fee(
  p_percent numeric, p_min numeric)
returns jsonb language plpgsql security definer
set search_path = public, private
as $$
declare
  v_old_percent numeric := public.early_settlement_fee_percent();
  v_old_min numeric := public.early_settlement_fee_min();
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;

  if p_percent is null or p_min is null then raise exception 'INVALID_FEE'; end if;
  if p_percent < 0 or p_percent > 100 then raise exception 'INVALID_FEE_PERCENT'; end if;
  if p_min < 0 then raise exception 'INVALID_FEE_MIN'; end if;

  insert into private.app_config (key, value)
  values ('early_settlement_fee_percent', round(p_percent, 2)::text)
  on conflict (key) do update set value = excluded.value;

  insert into private.app_config (key, value)
  values ('early_settlement_fee_min', round(p_min, 2)::text)
  on conflict (key) do update set value = excluded.value;

  perform public.log_admin_action(
    'finance.early_settlement_fee', 'config', null,
    jsonb_build_object(
      'from', jsonb_build_object('fee_percent', v_old_percent, 'fee_min', v_old_min),
      'to', jsonb_build_object('fee_percent', round(p_percent, 2), 'fee_min', round(p_min, 2))));

  return jsonb_build_object(
    'fee_percent', public.early_settlement_fee_percent(),
    'fee_min', public.early_settlement_fee_min());
end;
$$;;
