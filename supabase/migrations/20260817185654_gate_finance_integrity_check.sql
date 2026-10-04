-- Security pass finding: granted to `authenticated` with no permission check
-- at all, unlike every sibling finance RPC. A regular customer could call it
-- and read platform-wide ledger health (net position across every party, how
-- many delivered orders sit unsettled) — not fund-affecting, but not
-- something a customer account should be able to read either.
create or replace function public.finance_integrity_check()
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
begin
  if not public.has_permission('reports.view') then raise exception 'FORBIDDEN'; end if;
  return (
    select jsonb_build_object(
      'net_across_all_parties', coalesce(round(sum(signed_amount), 2), 0),
      'balanced', coalesce(round(sum(signed_amount), 2), 0) = 0,
      'posted_rows', count(*) filter (where status = 'posted'),
      'wallets_out_of_sync', (
        select count(*) from public.finance_wallets w
        where w.balance <> coalesce((
          select sum(t.signed_amount) from public.ledger_transactions t
          where t.wallet_id = w.id and t.status = 'posted'), 0)
      ),
      'delivered_unsettled', (
        select count(*) from public.orders
        where status = 'delivered' and settlement_status <> 'settled')
    )
    from public.ledger_transactions
    where status = 'posted'
  );
end;
$$;

revoke all on function public.finance_integrity_check() from public, anon, authenticated;
grant execute on function public.finance_integrity_check() to authenticated;;
