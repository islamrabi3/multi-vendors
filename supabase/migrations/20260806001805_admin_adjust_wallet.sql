-- Admin credit and debit of a customer wallet.
--
-- There was no path for this: top_up_wallet is service_role only (it belongs
-- to the payment webhook) and refunds only work against an existing order. A
-- goodwill credit, or clawing back one issued in error, had no route at all
-- short of editing the table by hand -- which leaves no ledger row, so the
-- customer's own wallet history would not add up to their balance.
--
-- Gated on `wallets.adjust`, which the Finance role already carries.
create or replace function public.admin_adjust_wallet(
  p_user_id uuid,
  p_amount numeric,
  p_reason text default null
)
returns numeric
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_balance numeric;
begin
  if not public.has_permission('wallets.adjust') then
    raise exception 'FORBIDDEN';
  end if;
  if p_amount is null or p_amount = 0 then
    raise exception 'INVALID_AMOUNT';
  end if;
  -- A reason is not optional on someone else's money: this is the only record
  -- of why a balance moved, and it is what the customer is shown.
  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'REASON_REQUIRED';
  end if;

  insert into public.wallets (user_id, balance)
  values (p_user_id, 0)
  on conflict (user_id) do nothing;

  -- Locked before reading: two admins crediting at once must not both write a
  -- balance computed from the same starting figure.
  select balance into v_balance
    from public.wallets where user_id = p_user_id for update;

  if v_balance + p_amount < 0 then
    raise exception 'INSUFFICIENT_BALANCE';
  end if;

  update public.wallets
     set balance = balance + p_amount, updated_at = now()
   where user_id = p_user_id
   returning balance into v_balance;

  -- The ledger row is the audit trail the customer can see; the admin log is
  -- the one that records who did it.
  insert into public.wallet_transactions (user_id, type, amount, description)
  values (
    p_user_id,
    case when p_amount > 0 then 'deposit'::wallet_transaction_type
         else 'payment'::wallet_transaction_type end,
    abs(p_amount),
    btrim(p_reason)
  );

  perform public.log_admin_action(
    case when p_amount > 0 then 'wallet.credit' else 'wallet.debit' end,
    'profile',
    p_user_id
  );

  return v_balance;
end;
$$;

revoke execute on function public.admin_adjust_wallet(uuid, numeric, text)
  from public, anon;
grant execute on function public.admin_adjust_wallet(uuid, numeric, text)
  to authenticated, service_role;
