-- Approving a settlement request never moves real money by itself — there is
-- no payout API wired up (Paymob here is collection-only: it takes a
-- customer's card, it does not disburse to a vendor's or driver's bank
-- account). "Approve" always meant "I already sent this outside the app,
-- record it" — same as `admin_record_settlement` always has. The one thing
-- that was actually wrong: `admin_review_settlement_request` reused
-- `notify_settlement`'s driver branch unchanged, and that branch was written
-- for the opposite event (a driver handing cash *in*, e.g. a deposit or a
-- cash-due settlement). A driver who requested a *payout* and got approved
-- was told "we recorded your cash handed in" — the wrong direction entirely.
--
-- Fixes that by giving the driver branch a distinct 'payout' copy, and
-- passing that kind from `admin_review_settlement_request`'s approve branch
-- (harmless for the vendor side: 'payout' isn't 'early' or 'rejected', so it
-- falls through to the same "you have been paid" text the vendor branch
-- already used by default).

create or replace function public.notify_settlement(
  p_owner_type public.ledger_owner_type, p_owner_id uuid,
  p_amount numeric, p_kind text default 'settlement')
returns void language plpgsql security definer set search_path = public
as $$
declare v_user uuid; v_title text; v_body text; v_route text;
begin
  if p_owner_type = 'driver' then
    v_user := p_owner_id;
    v_route := '/driver-app/wallet';
    if p_kind = 'rejected' then
      v_title := 'Settlement request declined';
      v_body := 'Your request for ' || to_char(p_amount, 'FM999999990.00')
             || ' EGP was declined. Contact support for details.';
    elsif p_kind = 'payout' then
      v_title := 'You have been paid';
      v_body := to_char(p_amount, 'FM999999990.00') || ' EGP has been settled.';
    else
      v_title := 'Settlement recorded';
      v_body := 'We have recorded ' || to_char(p_amount, 'FM999999990.00')
             || ' EGP handed in. Your balance is up to date.';
    end if;
  elsif p_owner_type = 'vendor' then
    select owner_id into v_user from public.vendors where id = p_owner_id;
    v_route := '/vendor-app/dashboard';
    if p_kind = 'early' then
      v_title := 'Early payout sent';
      v_body := to_char(p_amount, 'FM999999990.00')
             || ' EGP is on its way to you today.';
    elsif p_kind = 'rejected' then
      v_title := 'Settlement request declined';
      v_body := 'Your request for ' || to_char(p_amount, 'FM999999990.00')
             || ' EGP was declined. Contact support for details.';
    else
      v_title := 'You have been paid';
      v_body := to_char(p_amount, 'FM999999990.00') || ' EGP has been settled.';
    end if;
  else
    return;
  end if;

  if v_user is null then return; end if;

  insert into public.notifications (user_id, title, body, type, route)
  values (v_user, v_title, v_body, 'settlement', v_route);
end;
$$;

revoke all on function public.notify_settlement(
  public.ledger_owner_type, uuid, numeric, text) from public, anon, authenticated;

create or replace function public.admin_review_settlement_request(
  p_settlement_id uuid, p_approve boolean, p_notes text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare
  v_row public.settlements%rowtype;
  v_txn uuid;
  v_type public.ledger_entry_type;
  v_party_direction public.ledger_direction;
  v_key text;
  v_balance numeric;
begin
  if not public.has_permission('finance.settle') then raise exception 'FORBIDDEN'; end if;

  select * into v_row from public.settlements where id = p_settlement_id for update;
  if not found then raise exception 'REQUEST_NOT_FOUND'; end if;
  -- Reviewing twice must not post the ledger twice.
  if v_row.status <> 'pending' then raise exception 'ALREADY_REVIEWED'; end if;

  if p_approve then
    v_type := case v_row.owner_type
      when 'driver' then 'driver_settlement'::public.ledger_entry_type
      else 'vendor_settlement'::public.ledger_entry_type end;

    v_party_direction := 'debit'::public.ledger_direction;

    v_key := 'settlement_request:' || p_settlement_id::text;

    v_txn := public.finance_post(
      v_row.owner_type, v_row.owner_id, v_type, v_row.amount, v_party_direction,
      null, v_row.reference, coalesce(p_notes, v_row.notes, 'Settlement'),
      jsonb_build_object('method', v_row.method, 'settlement_id', p_settlement_id),
      v_key);

    if v_txn is null then raise exception 'SETTLEMENT_NOT_RECORDED'; end if;

    perform public.finance_post(
      'platform', null, v_type, v_row.amount, 'credit'::public.ledger_direction,
      null, v_row.reference, 'Settlement counterparty',
      jsonb_build_object('method', v_row.method, 'counterparty_of', v_txn),
      v_key || ':platform');

    update public.settlements set
      status = 'completed', completed_at = now(), approved_by = auth.uid(),
      transaction_id = v_txn, notes = coalesce(p_notes, notes)
    where id = p_settlement_id;

    -- 'payout' — this RPC's rows are always money paid out, never cash
    -- handed in, regardless of owner_type.
    perform public.notify_settlement(
      v_row.owner_type, v_row.owner_id, v_row.amount, 'payout');
  else
    update public.settlements set
      status = 'cancelled', approved_by = auth.uid(), notes = coalesce(p_notes, notes)
    where id = p_settlement_id;

    perform public.notify_settlement(
      v_row.owner_type, v_row.owner_id, v_row.amount, 'rejected');
  end if;

  select balance into v_balance from public.finance_wallets
  where owner_type = v_row.owner_type and owner_id = v_row.owner_id;

  return jsonb_build_object(
    'settlement_id', p_settlement_id, 'approved', p_approve,
    'transaction_id', v_txn, 'balance', v_balance,
    'cash_due', public.wallet_cash_due(v_balance),
    'payable', public.wallet_payable(v_balance));
end;
$$;

revoke all on function public.admin_review_settlement_request(uuid, boolean, text)
  from public, anon;
grant execute on function public.admin_review_settlement_request(uuid, boolean, text)
  to authenticated;
