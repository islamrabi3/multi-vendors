-- The finance overview shows what drivers paid stores at the counter, beside
-- what the platform owes stores in the app. Both are money leaving the
-- platform for goods; leaving one out makes a platform-run store's orders
-- look like pure margin.
do $patch$
declare
  d text;
  n text;
begin
  d := pg_get_functiondef(
    'public.admin_finance_overview(timestamptz, timestamptz)'::regprocedure);
  if d like '%driver_store_purchase%' then
    return;
  end if;

  n := replace(d,
    '    ''vendor_earnings'', (select coalesce(sum(amount), 0) from t where type = ''vendor_earning''),',
    '    ''vendor_earnings'', (select coalesce(sum(amount), 0) from t where type = ''vendor_earning''),
    ''driver_store_purchases'', (select coalesce(sum(amount), 0) from t
                                 where type = ''driver_store_purchase''),');

  if n = d then
    raise exception 'admin_finance_overview anchors not found';
  end if;
  execute n;
end
$patch$;
