-- `wallet` is offered as a checkout payment method by the app but was missing
-- from the enum, so place_order(..., 'wallet') failed at the cast.
-- ALTER TYPE ... ADD VALUE must not be used in the same transaction that adds
-- it, so this lives in its own migration.
alter type public.payment_method add value if not exists 'wallet';
