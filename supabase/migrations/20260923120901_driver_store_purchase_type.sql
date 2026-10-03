-- A driver paying the store at the counter, on an order no store is running.
-- Its own migration: a new enum value cannot be used in the transaction that
-- adds it.
alter type public.ledger_entry_type add value if not exists 'driver_store_purchase';
