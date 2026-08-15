-- On a card or wallet order the customer's money lands with the platform, not
-- with a driver. Without a row for that the platform looked as if it had only
-- earned its commission, while actually holding the store's and the driver's
-- money too — so the ledger balanced per-order for cash and not at all for
-- online.
--
-- Its own migration because Postgres will not let a new enum value be used in
-- the same transaction that adds it.
alter type public.ledger_entry_type add value if not exists 'online_collection';
