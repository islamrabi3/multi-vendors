-- Vendor/driver-initiated settlement requests, awaiting admin approval.
--
-- Two ways money already moves: `vendor_request_early_settlement` (instant,
-- self-service, a fee buys the speed) and `admin_record_settlement` (admin
-- logs that a transfer already happened outside the app). Neither has a
-- waiting state — there was no way for a vendor or driver to say "please pay
-- me" and have an admin approve it before the money moves. This adds that
-- third path, reusing `public.settlements.status = 'pending'` (defined but
-- unused until now) as the request itself: a pending row holds no ledger
-- postings, and admin approval is the only thing that posts them.

create or replace function public.vendor_request_settlement(
  p_vendor_id uuid, p_method text default 'bank_transfer',
  p_reference text default null, p_notes text default null)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_payable numeric; v_id uuid;
begin
  if not (public.is_vendor_owner(p_vendor_id) or public.is_admin()) then
    raise exception 'FORBIDDEN';
  end if;

  -- Locks the wallet so a double tap cannot open two requests for the same
  -- balance.
  perform 1 from public.finance_wallets
  where owner_type = 'vendor' and owner_id = p_vendor_id for update;

  if exists (
    select 1 from public.settlements
    where owner_type = 'vendor' and owner_id = p_vendor_id and status = 'pending'
  ) then
    raise exception 'REQUEST_ALREADY_PENDING';
  end if;

  select public.wallet_payable(balance) into v_payable
  from public.finance_wallets where owner_type = 'vendor' and owner_id = p_vendor_id;

  if v_payable is null or v_payable <= 0 then
    raise exception 'NOTHING_TO_SETTLE';
  end if;

  -- No `finance_post`, no `transaction_id`, no `approved_by` — a request
  -- moves nothing until `admin_review_settlement_request` approves it.
  insert into public.settlements (
    owner_type, owner_id, amount, method, status, reference, notes, created_by
  ) values (
    'vendor', p_vendor_id, round(v_payable, 2), p_method, 'pending',
    p_reference, p_notes, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.vendor_request_settlement(uuid, text, text, text)
  from public, anon;
grant execute on function public.vendor_request_settlement(uuid, text, text, text)
  to authenticated;

create or replace function public.driver_request_settlement(
  p_method text default 'bank_transfer', p_reference text default null,
  p_notes text default null)
returns uuid language plpgsql security definer set search_path = public
as $$
declare v_payable numeric; v_id uuid;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED'; end if;
  if not exists (select 1 from public.drivers where id = auth.uid()) then
    raise exception 'NOT_A_DRIVER';
  end if;

  perform 1 from public.finance_wallets
  where owner_type = 'driver' and owner_id = auth.uid() for update;

  if exists (
    select 1 from public.settlements
    where owner_type = 'driver' and owner_id = auth.uid() and status = 'pending'
  ) then
    raise exception 'REQUEST_ALREADY_PENDING';
  end if;

  select public.wallet_payable(balance) into v_payable
  from public.finance_wallets where owner_type = 'driver' and owner_id = auth.uid();

  if v_payable is null or v_payable <= 0 then
    raise exception 'NOTHING_TO_SETTLE';
  end if;

  insert into public.settlements (
    owner_type, owner_id, amount, method, status, reference, notes, created_by
  ) values (
    'driver', auth.uid(), round(v_payable, 2), p_method, 'pending',
    p_reference, p_notes, auth.uid()
  ) returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.driver_request_settlement(text, text, text)
  from public, anon;
grant execute on function public.driver_request_settlement(text, text, text)
  to authenticated;

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
    -- Posting logic borrows `admin_record_settlement`'s shape (same file
    -- family, `20260810133008_settlement_notifications.sql`) but NOT its
    -- direction rule. That function is called for two opposite real-world
    -- events depending on which admin screen invokes it: a driver handing
    -- cash *in* (credit — their debt shrinks) or a store being paid *out*
    -- (debit — what they're owed shrinks). This RPC only ever approves a row
    -- `vendor_request_settlement`/`driver_request_settlement` created, and
    -- both of those refuse to open a request unless `wallet_payable > 0` —
    -- i.e. every row here is a payout, never a cash-in. So the party is
    -- always debited, regardless of owner_type; only the ledger entry's
    -- *label* differs by party.
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

    -- The platform always takes the mirror of a payout: it paid the money
    -- out, so it credits its own account for the amount it no longer holds.
    perform public.finance_post(
      'platform', null, v_type, v_row.amount, 'credit'::public.ledger_direction,
      null, v_row.reference, 'Settlement counterparty',
      jsonb_build_object('method', v_row.method, 'counterparty_of', v_txn),
      v_key || ':platform');

    update public.settlements set
      status = 'completed', completed_at = now(), approved_by = auth.uid(),
      transaction_id = v_txn, notes = coalesce(p_notes, notes)
    where id = p_settlement_id;

    perform public.notify_settlement(v_row.owner_type, v_row.owner_id, v_row.amount);
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

-- `notify_settlement` gains a 'rejected' branch, additive only — every
-- existing caller (`admin_record_settlement`, `vendor_request_early_settlement`,
-- and the approve branch above) keeps passing its own p_kind or none, and gets
-- exactly the same copy as before. Rest of the body is byte-for-byte the
-- `20260810133008_settlement_notifications.sql` version.
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
