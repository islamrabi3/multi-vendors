-- Order chat is between the customer and the rider only.
--
-- The customer–store thread is closed: whatever the customer needs from the
-- store goes through the rider or support, so there is one person to talk to
-- about an order, not two. Existing threads stay readable as history; nobody
-- can add to them. The store still reaches the customer by phone.
alter policy chat_messages_send on public.chat_messages
  with check (
    sender_id = (select auth.uid())
    and not public.is_blocked()
    and thread <> 'vendor'
    and public.can_view_chat_thread(order_id, thread)
  );
