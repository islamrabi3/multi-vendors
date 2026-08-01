-- Intentionally a no-op.
--
-- The version of this migration that reached the project replaced place_order
-- with a wrapper delegating to `_place_order_impl`, a function that does not
-- exist — which broke ordering outright until it was noticed. It is kept here
-- only so the local history matches the project's `schema_migrations` table.
--
-- The blocked-account guard it was trying to add lives in the next migration,
-- 20260801151812_restore_place_order_with_block_guard.sql, inline with the
-- rest of place_order's preconditions. Reproducing the broken statement on a
-- fresh `db reset` would serve no purpose.

select 1;
