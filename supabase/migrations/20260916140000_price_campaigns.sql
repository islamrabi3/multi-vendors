-- Campaign pricing: menu prices rise by the campaign's percentage while it
-- runs and fall back when it ends, and the store is still paid on its own
-- price. The difference is the platform's, which is what pays for the
-- discount the customer is being offered.
alter type public.ledger_entry_type add value if not exists 'platform_markup';
