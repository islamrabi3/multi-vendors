-- The thread-aware versions take over completely.
--
-- Both overloads have every argument defaulted, so a call that names only
-- p_order_id resolves to the old thread-blind function and would count the
-- rider's messages as unread in the store's conversation. Removing the old
-- signatures leaves one answer per call.
drop function if exists public.my_unread_chat_count(uuid);
drop function if exists public.mark_order_chat_read(uuid);
drop function if exists public.hide_order_conversation(uuid);;
