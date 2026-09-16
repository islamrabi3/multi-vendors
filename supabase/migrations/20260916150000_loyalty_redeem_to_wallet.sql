-- Points become money: 1000 points buy 10 EGP of wallet credit, and nothing
-- smaller can be redeemed. Until now points only accumulated, so the rewards
-- screen was a counter with no way to spend it.
alter table public.platform_settings
  add column if not exists loyalty_points_per_unit integer not null default 100,
  add column if not exists loyalty_min_redeem integer not null default 1000;

create or replace function public.loyalty_redeem_config()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'points_per_unit', coalesce((select loyalty_points_per_unit from public.platform_settings where id = 1), 100),
    'min_redeem', coalesce((select loyalty_min_redeem from public.platform_settings where id = 1), 1000)
  );
$$;

-- Spends points for wallet credit.
--
-- The whole exchange is one transaction: the balance is locked, the points
-- come off, the wallet goes up, and both ledgers get their row. A client can
-- ask for an amount but never name a price — the rate lives here.
create or replace function public.redeem_loyalty_points(p_points integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_balance integer;
  v_rate integer;
  v_min integer;
  v_credit numeric;
begin
  if v_user is null then
    raise exception 'UNAUTHORIZED';
  end if;

  select coalesce(loyalty_points_per_unit, 100), coalesce(loyalty_min_redeem, 1000)
  into v_rate, v_min
  from public.platform_settings where id = 1;
  v_rate := coalesce(v_rate, 100);
  v_min := coalesce(v_min, 1000);

  if p_points is null or p_points < v_min then
    raise exception 'BELOW_MIN_REDEEM:%', v_min;
  end if;
  -- Only whole units: half a pound of credit is not worth the rounding.
  if p_points % v_rate <> 0 then
    raise exception 'INVALID_POINTS_AMOUNT:%', v_rate;
  end if;

  select points into v_balance
  from public.loyalty_points where user_id = v_user
  for update;

  if coalesce(v_balance, 0) < p_points then
    raise exception 'NOT_ENOUGH_POINTS';
  end if;

  v_credit := round(p_points::numeric / v_rate, 2);

  update public.loyalty_points
  set points = points - p_points, updated_at = now()
  where user_id = v_user;

  insert into public.loyalty_history (user_id, points_change, action)
  values (v_user, -p_points, 'redeemed_to_wallet');

  insert into public.wallets (user_id, balance, updated_at)
  values (v_user, v_credit, now())
  on conflict (user_id) do update
    set balance = public.wallets.balance + v_credit,
        updated_at = now();

  insert into public.wallet_transactions (user_id, type, amount, description)
  values (v_user, 'reward', v_credit, 'Loyalty points redeemed');

  return jsonb_build_object(
    'points_spent', p_points,
    'credit', v_credit,
    'points_left', coalesce(v_balance, 0) - p_points
  );
end;
$$;

revoke all on function public.redeem_loyalty_points(integer) from public, anon;
grant execute on function public.redeem_loyalty_points(integer) to authenticated;
grant execute on function public.loyalty_redeem_config() to authenticated;
