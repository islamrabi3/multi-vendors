-- Service fees are platform revenue: count them in the overview's bottom line
-- and report them on their own row. Patched in place, anchors asserted.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef(
    'public.admin_finance_overview(timestamptz, timestamptz)'::regprocedure);

  n := replace(d,
    '''platform_delivery_margin'',
                                         ''early_settlement_fee'',',
    '''platform_delivery_margin'',
                                         ''platform_service_fee'',
                                         ''early_settlement_fee'',');
  if n = d then raise exception 'overview: earnings anchor missing'; end if;
  d := n;

  n := replace(d,
    '''platform_discounts'', (select',
    '''platform_service_fees'', (select coalesce(sum(amount), 0) from t
                              where type = ''platform_service_fee''),
    ''platform_discounts'', (select');
  if n = d then raise exception 'overview: row anchor missing'; end if;
  d := n;

  execute d;
end
$patch$;
