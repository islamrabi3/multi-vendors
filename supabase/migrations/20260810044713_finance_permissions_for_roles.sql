-- The two new permission keys the ledger checks.
--
-- An admin with no role passes everything (`has_permission` is deliberately
-- permissive for the owner), so this only matters for scoped staff. The
-- existing "Finance" role already carries `wallets.adjust` and
-- `payments.refund`, which is the same job, so it gains both; nobody else
-- does. Settling and adjusting move real money and are not something an
-- operations or catalogue role should acquire by accident.
update public.admin_roles
set permissions = (
  select array(select distinct unnest(permissions || array['finance.settle', 'finance.adjust']))
)
where 'wallets.adjust' = any(permissions);
