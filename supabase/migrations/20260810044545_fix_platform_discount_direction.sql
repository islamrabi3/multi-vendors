-- `platform_discount` must be a debit, not a credit.
--
-- Deriving it from the invariant, with
-- `total = vendor_net + driver_earning + commission + margin - platform_discount`:
--
--   holder(-total) + driver_earning + vendor_net + commission + margin + X = 0
--   => X = -platform_discount
--
-- so the discount reduces the platform's balance. Credited instead, every
-- discounted order left the ledger out of balance by twice the discount.
-- Rather than re-send the whole body, this rewrites the one line, which is
-- also a smaller thing to review.
--
-- The preceding migration in this repo already carries the corrected
-- direction, so on a rebuild from scratch this finds nothing to change and
-- says so. It is kept because the deployed database did go through the wrong
-- version, and dropping it would leave that database with no record of the
-- correction.
do $$
declare
  v_src text;
begin
  select pg_get_functiondef(p.oid) into v_src
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'finance_settle_order';

  if position('''platform_discount'', v_platform_discount, ''credit''' in v_src) = 0 then
    raise notice 'already a debit; nothing to do';
    return;
  end if;

  v_src := replace(
    v_src,
    '''platform_discount'', v_platform_discount, ''credit''',
    '''platform_discount'', v_platform_discount, ''debit''');

  execute v_src;
end $$;
