-- reviews_order_id_key already backs the unique constraint on order_id.
-- reviews_order_unique is a second, identical index: same write cost on every
-- review, no read it can serve that the constraint index cannot. The
-- constraint's index is the one that must stay, since dropping it would take
-- the "one review per order" rule with it.
drop index if exists public.reviews_order_unique;
