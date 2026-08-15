import '../models/finance.dart';
import '../supabase_client.dart';

/// The app's whole financial surface.
///
/// Every write is an RPC. The tables themselves grant nothing but `SELECT`, so
/// there is deliberately no method here that updates a balance — the server
/// would refuse it, and the ledger is the only thing allowed to move money.
class FinanceRepository {
  // ===== Positions =====

  /// One party's position. A driver may ask for their own, a store owner for
  /// theirs, an admin for anyone's.
  Future<WalletSummary> walletSummary({
    required LedgerOwner ownerType,
    String? ownerId,
  }) async {
    final data = await supabase.rpc(
      'finance_wallet_summary',
      params: {'p_owner_type': ownerType.name, 'p_owner_id': ownerId},
    );
    return WalletSummary.fromMap((data as Map).cast<String, dynamic>());
  }

  /// The signed-in driver's own position.
  Future<WalletSummary> myDriverWallet() => walletSummary(
    ownerType: LedgerOwner.driver,
    ownerId: supabase.auth.currentUser?.id,
  );

  Future<WalletSummary> vendorWallet(String vendorId) =>
      walletSummary(ownerType: LedgerOwner.vendor, ownerId: vendorId);

  // ===== The ledger itself =====

  /// One party's statement, newest first.
  ///
  /// Paged rather than fetched whole: a busy driver accumulates a row per
  /// order and this is the screen they open most.
  Future<List<LedgerEntry>> ledger({
    required LedgerOwner ownerType,
    String? ownerId,
    int limit = 30,
    int offset = 0,
  }) async {
    var query = supabase
        .from('ledger_transactions')
        .select()
        .eq('owner_type', ownerType.name);
    if (ownerId != null) query = query.eq('owner_id', ownerId);
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(LedgerEntry.fromMap)
        .toList();
  }

  Future<List<LedgerEntry>> myDriverLedger({int limit = 30, int offset = 0}) =>
      ledger(
        ownerType: LedgerOwner.driver,
        ownerId: supabase.auth.currentUser?.id,
        limit: limit,
        offset: offset,
      );

  /// Everything one order produced — the audit view for a disputed order.
  Future<List<LedgerEntry>> ledgerForOrder(String orderId) async {
    final rows = await supabase
        .from('ledger_transactions')
        .select()
        .eq('order_id', orderId)
        .order('created_at');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(LedgerEntry.fromMap)
        .toList();
  }

  // ===== Settlements =====

  /// The signed-in driver's own past hand-overs.
  Future<List<Settlement>> myDriverSettlements({
    int limit = 30,
    int offset = 0,
  }) => settlements(
    ownerType: LedgerOwner.driver,
    ownerId: supabase.auth.currentUser?.id,
    limit: limit,
    offset: offset,
  );

  Future<List<Settlement>> settlements({
    LedgerOwner? ownerType,
    String? ownerId,
    String? status,
    int limit = 30,
    int offset = 0,
  }) async {
    var query = supabase.from('settlements').select();
    if (ownerType != null) query = query.eq('owner_type', ownerType.name);
    if (ownerId != null) query = query.eq('owner_id', ownerId);
    if (status != null) query = query.eq('status', status);
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(Settlement.fromMap)
        .toList();
  }

  /// Every settlement still waiting on an admin, across both parties — the
  /// admin's "Requests" tab.
  Future<List<Settlement>> pendingSettlementRequests({int limit = 50}) =>
      settlements(status: 'pending', limit: limit);

  /// A store asking to be paid out, rather than cashing out early for a fee.
  /// Nothing moves until [reviewSettlementRequest] approves it.
  Future<String> requestVendorSettlement({
    required String vendorId,
    String method = 'bank_transfer',
    String? reference,
    String? notes,
  }) async {
    final id = await supabase.rpc(
      'vendor_request_settlement',
      params: {
        'p_vendor_id': vendorId,
        'p_method': method,
        'p_reference': reference,
        'p_notes': notes,
      },
    );
    return id as String;
  }

  /// The signed-in driver asking to be paid their earned balance out.
  Future<String> requestDriverSettlement({
    String method = 'bank_transfer',
    String? reference,
    String? notes,
  }) async {
    final id = await supabase.rpc(
      'driver_request_settlement',
      params: {'p_method': method, 'p_reference': reference, 'p_notes': notes},
    );
    return id as String;
  }

  /// Admin approves or declines a pending request. Approving is the only
  /// moment the money actually moves.
  Future<void> reviewSettlementRequest({
    required String settlementId,
    required bool approve,
    String? notes,
  }) => supabase.rpc(
    'admin_review_settlement_request',
    params: {
      'p_settlement_id': settlementId,
      'p_approve': approve,
      'p_notes': notes,
    },
  );

  /// Records that a driver handed cash in, or that a store was paid out.
  ///
  /// [idempotencyKey] is worth passing whenever the caller might retry: the
  /// server returns the existing row for a key it has already seen instead of
  /// recording the settlement twice.
  Future<WalletSummary> recordSettlement({
    required LedgerOwner ownerType,
    required String ownerId,
    required double amount,
    String method = 'cash',
    String? reference,
    String? notes,
    String? idempotencyKey,
  }) async {
    final data = await supabase.rpc(
      'admin_record_settlement',
      params: {
        'p_owner_type': ownerType.name,
        'p_owner_id': ownerId,
        'p_amount': amount,
        'p_method': method,
        'p_reference': reference,
        'p_notes': notes,
        'p_idempotency_key': idempotencyKey,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return WalletSummary(
      ownerType: ownerType,
      ownerId: ownerId,
      balance: money(map['balance']),
      cashDue: money(map['cash_due']),
      payable: money(map['payable']),
    );
  }

  // ===== Deposits =====

  /// The driver claims to have paid money in. Credits nothing on its own.
  Future<String> createDepositRequest({
    required double amount,
    String paymentMethod = 'bank_transfer',
    String? reference,
    String? proofUrl,
    String? notes,
  }) async {
    final id = await supabase.rpc(
      'driver_create_deposit_request',
      params: {
        'p_amount': amount,
        'p_payment_method': paymentMethod,
        'p_reference': reference,
        'p_proof_url': proofUrl,
        'p_notes': notes,
      },
    );
    return id as String;
  }

  Future<List<DepositRequest>> depositRequests({
    String? status,
    String? driverId,
    int limit = 50,
  }) async {
    var query = supabase
        .from('deposit_requests')
        .select('*, profiles!deposit_requests_driver_id_fkey(full_name)');
    if (status != null) query = query.eq('status', status);
    if (driverId != null) query = query.eq('driver_id', driverId);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(DepositRequest.fromMap)
        .toList();
  }

  Future<void> reviewDeposit({
    required String requestId,
    required bool approve,
    String? notes,
  }) => supabase.rpc(
    'admin_review_deposit',
    params: {'p_request_id': requestId, 'p_approve': approve, 'p_notes': notes},
  );

  // ===== Corrections =====

  /// A manual correction. The reason is required by the server, not just by
  /// the form: an adjustment with no stated reason is unauditable.
  Future<void> adjust({
    required LedgerOwner ownerType,
    required String ownerId,
    required double amount,
    required bool isCredit,
    required String reason,
    String type = 'adjustment',
    String? reference,
  }) => supabase.rpc(
    'admin_ledger_adjustment',
    params: {
      'p_owner_type': ownerType.name,
      'p_owner_id': ownerId,
      'p_amount': amount,
      'p_direction': isCredit ? 'credit' : 'debit',
      'p_reason': reason,
      'p_type': type,
      'p_reference': reference,
    },
  );

  /// Cancels one posted row by writing its mirror. Nothing is deleted.
  Future<void> reverseTransaction({
    required String transactionId,
    required String reason,
  }) => supabase.rpc(
    'admin_reverse_transaction',
    params: {'p_transaction_id': transactionId, 'p_reason': reason},
  );

  /// Unwinds an entire order — every row it produced — and puts it back to
  /// unsettled. For a refund or a cancellation after delivery.
  Future<int> reverseOrderSettlement({
    required String orderId,
    required String reason,
  }) async {
    final count = await supabase.rpc(
      'admin_reverse_order_settlement',
      params: {'p_order_id': orderId, 'p_reason': reason},
    );
    return (count as num?)?.toInt() ?? 0;
  }

  // ===== Admin dashboards =====

  Future<FinanceOverview> overview({DateTime? start, DateTime? end}) async {
    final data = await supabase.rpc(
      'admin_finance_overview',
      params: {
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      },
    );
    return FinanceOverview.fromMap((data as Map).cast<String, dynamic>());
  }

  Future<CashReconciliation> reconciliation({
    DateTime? start,
    DateTime? end,
  }) async {
    final data = await supabase.rpc(
      'admin_cash_reconciliation',
      params: {
        'p_start': start?.toUtc().toIso8601String(),
        'p_end': end?.toUtc().toIso8601String(),
      },
    );
    return CashReconciliation.fromMap((data as Map).cast<String, dynamic>());
  }

  Future<List<PartyBalance>> driverBalances() async {
    final rows = await supabase.rpc('admin_driver_balances');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PartyBalance.fromMap)
        .toList();
  }

  Future<List<PartyBalance>> vendorBalances() async {
    final rows = await supabase.rpc('admin_vendor_balances');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PartyBalance.fromMap)
        .toList();
  }

  /// The books in one number: the signed total across every party must be
  /// zero, because money is only ever moved between accounts and never
  /// created. Anything else is a bug, and this is what the admin's screen
  /// should be willing to shout about.
  Future<({bool balanced, double net, int unsettledOrders})>
  integrityCheck() async {
    final data = await supabase.rpc('finance_integrity_check');
    final map = (data as Map).cast<String, dynamic>();
    return (
      balanced: (map['balanced'] as bool?) ?? false,
      net: money(map['net_across_all_parties']),
      unsettledOrders: money(map['delivered_unsettled']).toInt(),
    );
  }

  /// Tips this driver has received, all time.
  ///
  /// Deliberately outside the ledger: `add_driver_tip` moves the money from
  /// the customer's in-app wallet straight into the driver's, so it is already
  /// settled and adding a ledger row would pay the driver twice. It is still
  /// their money and they expect to see it, so it is fetched separately and
  /// shown as its own figure rather than folded into the balance.
  Future<double> myTipsTotal() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return 0;
    final rows = await supabase
        .from('driver_tips')
        .select('amount')
        .eq('driver_id', userId);
    return (rows as List).cast<Map<String, dynamic>>().fold<double>(
      0,
      (sum, row) => sum + money(row['amount']),
    );
  }

  // ===== Vendor payouts =====

  /// What the store would receive and pay if it cashed out right now.
  ///
  /// Read-only, so the offer can be shown before the store commits to it —
  /// nobody should have to press the button to find out the fee.
  Future<EarlySettlementQuote> earlySettlementQuote(String vendorId) async {
    final data = await supabase.rpc(
      'vendor_early_settlement_quote',
      params: {'p_vendor_id': vendorId},
    );
    return EarlySettlementQuote.fromMap((data as Map).cast<String, dynamic>());
  }

  /// Opens a pending request to cash the store out at the quoted fee — an
  /// admin still has to approve it before anything moves, same as
  /// [requestVendorSettlement], just with a cost attached to the speed.
  ///
  /// The amount is not a parameter: the payable comes from the ledger and the
  /// fee from config, so there is nothing here for a caller to inflate.
  Future<({double fee, double netPayout})> requestEarlySettlement({
    required String vendorId,
    String method = 'bank_transfer',
    String? reference,
  }) async {
    final data = await supabase.rpc(
      'vendor_request_early_settlement',
      params: {
        'p_vendor_id': vendorId,
        'p_method': method,
        'p_reference': reference,
      },
    );
    final map = (data as Map).cast<String, dynamic>();
    return (fee: money(map['fee']), netPayout: money(map['net_payout']));
  }

  /// The driver equivalent of [earlySettlementQuote] — same fee schedule,
  /// scoped to the signed-in driver.
  Future<EarlySettlementQuote> driverEarlySettlementQuote() async {
    final data = await supabase.rpc('driver_early_settlement_quote');
    return EarlySettlementQuote.fromMap((data as Map).cast<String, dynamic>());
  }

  /// The driver equivalent of [requestEarlySettlement].
  Future<({double fee, double netPayout})> requestDriverEarlySettlement({
    String method = 'bank_transfer',
    String? reference,
  }) async {
    final data = await supabase.rpc(
      'driver_request_early_settlement',
      params: {'p_method': method, 'p_reference': reference},
    );
    final map = (data as Map).cast<String, dynamic>();
    return (fee: money(map['fee']), netPayout: money(map['net_payout']));
  }

  /// Splits any delivered orders that were missed — an outage, or orders that
  /// predate the ledger. Idempotent, so running it twice is harmless.
  Future<int> backfillSettlements() async {
    final count = await supabase.rpc('finance_backfill_settlements');
    return (count as num?)?.toInt() ?? 0;
  }
}
