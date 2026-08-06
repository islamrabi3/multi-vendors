-- Loyalty points were mintable by anyone.
--
-- earn_loyalty_points(p_user_id, p_points, p_action) was SECURITY DEFINER,
-- granted to authenticated, and checked nothing at all: the caller named the
-- account and the amount. One REST call credited a million points to any user
-- id. Verified against the live database before this migration.
--
-- It was also awarding to the wrong person. The client called it from
-- updateStatus() after marking an order delivered, using the *caller's* id --
-- and the caller is the driver, not the customer. Every completed delivery
-- paid the driver the customer's points.
--
-- Both problems are the same mistake: the client deciding who earns. The award
-- now happens in a trigger, from the order row, once.

-- 1. Reverse the audit probe (1,000,000 points credited during verification).
delete from public.loyalty_history where action = 'audit_probe';
update public.loyalty_points
   set points = greatest(points - 1000000, 0), updated_at = now()
 where user_id = '1a8a1b5e-3911-4c5d-9ba5-cead77ceb4ea'
   and points >= 1000000;

-- 2. Tie a reward to its order so it cannot be paid twice. Existing rows keep
--    a null order_id: they predate this and cannot be attributed.
alter table public.loyalty_history
  add column if not exists order_id uuid references public.orders(id) on delete set null;

create unique index if not exists loyalty_history_order_reward_idx
  on public.loyalty_history (order_id)
  where order_id is not null;

-- 3. Take the function away from clients. service_role keeps it for backfills
--    and admin corrections; the trigger below is SECURITY DEFINER and does not
--    need a grant.
revoke execute on function public.earn_loyalty_points(uuid, int, text) from anon, authenticated, public;

-- 4. Award on delivery, server-side, from the order itself.
create or replace function public.award_order_loyalty()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_points constant int := 10;
begin
  if new.status = 'delivered' and old.status is distinct from 'delivered' then
    -- The unique index is the real guard: a re-delivered or replayed update
    -- hits it and is swallowed here rather than paying twice.
    begin
      insert into public.loyalty_history (user_id, points_change, action, order_id)
      values (new.customer_id, v_points, 'order_reward', new.id);

      insert into public.loyalty_points (user_id, points, updated_at)
      values (new.customer_id, v_points, now())
      on conflict (user_id) do update
        set points = public.loyalty_points.points + v_points,
            updated_at = now();
    exception when unique_violation then
      null;
    end;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_award_order_loyalty on public.orders;
create trigger trg_award_order_loyalty
  after update of status on public.orders
  for each row execute function public.award_order_loyalty();

revoke execute on function public.award_order_loyalty() from anon, authenticated, public;
