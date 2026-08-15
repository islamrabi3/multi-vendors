-- A store that wants its money before the weekly payout run pays for the
-- privilege. Its own migration because Postgres will not let a new enum value
-- be used in the same transaction that adds it.
alter type public.ledger_entry_type
  add value if not exists 'early_settlement_fee';
