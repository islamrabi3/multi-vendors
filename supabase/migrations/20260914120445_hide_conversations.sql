-- Swipe to remove a conversation from your own Messages list. Hidden per
-- person, and only until someone writes again: a new message brings the
-- thread back, so hiding can never make anyone miss a reply.
alter table public.chat_reads add column if not exists hidden_at timestamptz;

create or replace function public.hide_order_conversation(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_view_order(p_order_id) then
    raise exception 'FORBIDDEN';
  end if;
  insert into public.chat_reads (order_id, user_id, last_read_at, hidden_at)
  values (p_order_id, auth.uid(), now(), now())
  on conflict (order_id, user_id)
  do update set last_read_at = now(), hidden_at = now();
end;
$$;

revoke all on function public.hide_order_conversation(uuid) from public, anon;
grant execute on function public.hide_order_conversation(uuid) to authenticated;

do $patch$
declare d text; n text;
begin
  d := pg_get_functiondef('public.my_order_conversations(integer)'::regprocedure);
  n := replace(d,
    '  left join public.profiles p on p.id = l.sender_id
  order by l.created_at desc',
    '  left join public.profiles p on p.id = l.sender_id
  left join public.chat_reads hr on hr.order_id = o.id and hr.user_id = auth.uid()
  where hr.hidden_at is null or l.created_at > hr.hidden_at
  order by l.created_at desc');
  if n = d then raise exception 'anchor missing'; end if;
  execute n;
end
$patch$;
