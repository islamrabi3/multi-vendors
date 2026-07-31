-- Manual refunds for cancelled card orders.
--
-- There is no gateway payout yet: when a paid Paymob order is cancelled or
-- rejected, an admin presses "Refund to wallet" and the paid amount is
-- credited to the customer's wallet. The order's payment_status moves
-- paid -> refunded, and the row lock plus that status check make the refund
-- idempotent — pressing the button twice can never credit twice.

create or replace function public.admin_refund_order_to_wallet(p_order_id uuid)
returns numeric
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders%rowtype;
  v_amount numeric;
begin
  if not public.is_admin() then
    raise exception 'FORBIDDEN';
  end if;

  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'ORDER_NOT_FOUND';
  end if;

  if v_order.payment_method <> 'paymob' then
    raise exception 'NOT_A_CARD_ORDER';
  end if;
  if v_order.payment_status = 'refunded' then
    raise exception 'ALREADY_REFUNDED';
  end if;
  if v_order.payment_status <> 'paid' then
    raise exception 'ORDER_NOT_PAID';
  end if;
  if v_order.status not in ('cancelled', 'rejected') then
    raise exception 'ORDER_NOT_CANCELLED';
  end if;

  v_amount := v_order.total;

  update public.orders
  set payment_status = 'refunded'
  where id = p_order_id;

  insert into public.wallets (user_id, balance, updated_at)
  values (v_order.customer_id, v_amount, now())
  on conflict (user_id) do update
    set balance = public.wallets.balance + v_amount,
        updated_at = now();

  insert into public.wallet_transactions
    (user_id, type, amount, reference_id, description)
  values
    (v_order.customer_id, 'refund', v_amount,
     'order-' || p_order_id::text, 'Refund for cancelled order');

  return v_amount;
end;
$$;

revoke execute on function public.admin_refund_order_to_wallet(uuid)
  from public, anon;
grant execute on function public.admin_refund_order_to_wallet(uuid)
  to authenticated;
