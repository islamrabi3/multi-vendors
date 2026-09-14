-- Order chat unread badges: the reader marks the other party's messages read.
-- No UPDATE policy is added — a client could otherwise rewrite message text —
-- so this goes through a narrow function that only flips is_read.
create or replace function public.mark_order_chat_read(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_view_order(p_order_id) then
    raise exception 'FORBIDDEN';
  end if;
  update public.chat_messages
  set is_read = true
  where order_id = p_order_id
    and sender_id <> auth.uid()
    and not is_read;
end;
$$;

revoke all on function public.mark_order_chat_read(uuid) from public, anon;
grant execute on function public.mark_order_chat_read(uuid) to authenticated;

create index if not exists chat_messages_unread_idx
  on public.chat_messages (order_id)
  where not is_read;
