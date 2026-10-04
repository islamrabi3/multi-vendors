-- The early-payout fee was a constant only a migration could change: the
-- percent and the floor live in `private.app_config`, and nothing in the
-- console could write them. Give finance staff the two knobs.
--
-- Two functions rather than a generic config editor on purpose:
-- `private.app_config` also holds `notify_secret` and the internal webhook
-- URLs, so nothing here may read or write the table by arbitrary key.

-- Reading the fee is reading a finance figure.
create or replace function public.admin_early_settlement_fee()
returns jsonb language plpgsql stable security definer
set search_path = public, private
as $$
begin
  if not public.has_permission('reports.view') then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'fee_percent', public.early_settlement_fee_percent(),
    'fee_min', public.early_settlement_fee_min());
end;
$$;

-- Changing it changes what every future payout costs, so it sits behind the
-- same permission as adjusting a wallet by hand.
create or replace function public.admin_set_early_settlement_fee(
  p_percent numeric, p_min numeric)
returns jsonb language plpgsql security definer
set search_path = public, private
as $$
declare
  v_old_percent numeric := public.early_settlement_fee_percent();
  v_old_min numeric := public.early_settlement_fee_min();
begin
  if not public.has_permission('wallets.adjust') then raise exception 'FORBIDDEN'; end if;

  if p_percent is null or p_min is null then raise exception 'INVALID_FEE'; end if;
  -- A negative fee would pay the vendor *extra* to be paid early, and a
  -- percent above 100 is not a percentage. The quote function already refuses
  -- to advance anything when the fee would swallow the balance, so a merely
  -- steep number is a business decision rather than a hole.
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
$$;

revoke all on function public.admin_early_settlement_fee() from public, anon;
revoke all on function public.admin_set_early_settlement_fee(numeric, numeric) from public, anon;
grant execute on function public.admin_early_settlement_fee() to authenticated;
grant execute on function public.admin_set_early_settlement_fee(numeric, numeric) to authenticated;;
