-- The four-argument place_order has to go, not just be superseded.
--
-- Adding defaults to the new one left both signatures resolvable, and the app
-- was still calling the old shape — which knows nothing about `released_at`
-- and so would have left every new order NULL, meaning invisible to the store
-- it was placed with. An overload that silently wins is worse than no
-- overload.
drop function if exists public.place_order(uuid, payment_method, text, text);
