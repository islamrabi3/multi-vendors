-- Adding p_channel created a second function rather than replacing the first:
-- `create or replace` matches on signature, and a new parameter is a new
-- signature. Both then matched the edge function's five named arguments, so
-- every call raised 42725 "function is not unique" — Paymob checkout would
-- have failed outright.
--
-- The six-argument version defaults p_channel to null and is otherwise
-- byte-for-byte the old body, so dropping the five-argument one changes no
-- behaviour for any caller that never passes a channel.
drop function if exists public.open_payment_intent(uuid, text, text, numeric, uuid);;
