-- pg_trgm was installed into `public`, so its functions and operators sit in
-- the same namespace as application objects and are exposed over PostgREST.
--
-- Safe to move here because no application function names a trigram function
-- or operator: search_products/search_vendors use ILIKE, and the GIN indexes
-- reference gin_trgm_ops by opclass, which follows the extension. Verified
-- before and after: both searches return the same rows.
create schema if not exists extensions;
grant usage on schema extensions to anon, authenticated, service_role;
alter extension pg_trgm set schema extensions;
