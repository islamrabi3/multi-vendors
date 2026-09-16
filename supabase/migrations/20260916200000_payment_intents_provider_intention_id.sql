-- Paymob's own id for the checkout session.
--
-- Closing the checkout page by hand leaves no signed redirect to confirm the
-- payment with, so the app had nothing to go on but the webhook — and a
-- customer who paid and then shut the page was told the payment failed while
-- the webhook was still on its way. With the intention id recorded we can ask
-- Paymob directly what happened to this checkout.
alter table public.payment_intents
  add column if not exists provider_intention_id text;
