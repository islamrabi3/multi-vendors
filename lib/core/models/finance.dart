import 'package:equatable/equatable.dart';

/// Postgres `numeric` arrives as a number over PostgREST but as a string from
/// some transports, so neither is assumed.
double money(Object? value) => switch (value) {
  num n => n.toDouble(),
  String s => double.tryParse(s) ?? 0,
  _ => 0,
};

DateTime? _time(Object? value) =>
    value == null ? null : DateTime.tryParse(value as String)?.toLocal();

/// Which party an account or a ledger row belongs to.
enum LedgerOwner {
  driver,
  vendor,
  platform;

  static LedgerOwner from(String? name) => switch (name) {
    'vendor' => LedgerOwner.vendor,
    'platform' => LedgerOwner.platform,
    _ => LedgerOwner.driver,
  };
}

/// One party's financial position.
///
/// [balance] carries the whole story and the rest is derived from it. The sign
/// convention is the owner's point of view: negative means they are holding
/// money that is not theirs, positive means the platform owes them. Callers
/// should use [cashDue] and [payable] rather than reading the sign, so the
/// convention lives in one place.
class WalletSummary extends Equatable {
  const WalletSummary({
    required this.ownerType,
    this.ownerId,
    this.currency = 'EGP',
    this.balance = 0,
    this.cashDue = 0,
    this.payable = 0,
    this.pendingBalance = 0,
    this.cashCollected = 0,
    this.cashSettled = 0,
    this.totalEarnings = 0,
    this.totalDeposited = 0,
    this.totalAdjustments = 0,
    this.totalSettlements = 0,
    this.lastSettlementAt,
  });

  final LedgerOwner ownerType;
  final String? ownerId;
  final String currency;

  /// The single running account. Everything else on this object is a view of
  /// it or a supporting total.
  final double balance;

  /// Money the owner is holding and owes back. Zero when they owe nothing.
  final double cashDue;

  /// Money the platform owes them. Zero when it owes nothing.
  final double payable;

  final double pendingBalance;
  final double cashCollected;
  final double cashSettled;
  final double totalEarnings;
  final double totalDeposited;
  final double totalAdjustments;
  final double totalSettlements;
  final DateTime? lastSettlementAt;

  bool get owesMoney => cashDue > 0;

  factory WalletSummary.fromMap(Map<String, dynamic> map) => WalletSummary(
    ownerType: LedgerOwner.from(map['owner_type'] as String?),
    ownerId: map['owner_id'] as String?,
    currency: (map['currency'] as String?) ?? 'EGP',
    balance: money(map['balance']),
    cashDue: money(map['cash_due']),
    payable: money(map['payable']),
    pendingBalance: money(map['pending_balance']),
    cashCollected: money(map['cash_collected']),
    cashSettled: money(map['cash_settled']),
    totalEarnings: money(map['total_earnings']),
    totalDeposited: money(map['total_deposited']),
    totalAdjustments: money(map['total_adjustments']),
    totalSettlements: money(map['total_settlements']),
    lastSettlementAt: _time(map['last_settlement_at']),
  );

  @override
  List<Object?> get props => [
    ownerType,
    ownerId,
    balance,
    cashDue,
    payable,
    cashCollected,
    totalEarnings,
    totalSettlements,
  ];
}

/// One line of the ledger.
class LedgerEntry extends Equatable {
  const LedgerEntry({
    required this.id,
    required this.type,
    required this.amount,
    required this.isCredit,
    required this.status,
    required this.createdAt,
    this.orderId,
    this.reference,
    this.description,
    this.reversesId,
  });

  final String id;

  /// The raw enum name, e.g. `cash_collection`. Kept as text rather than a
  /// Dart enum: the server may gain a type before the app ships, and an
  /// unknown value should render as itself rather than crash a statement.
  final String type;

  /// Always positive; [isCredit] carries the sign.
  final double amount;
  final bool isCredit;
  final String status;
  final DateTime createdAt;
  final String? orderId;
  final String? reference;
  final String? description;

  /// Set on a reversal row, pointing at what it cancelled.
  final String? reversesId;

  double get signedAmount => isCredit ? amount : -amount;
  bool get isReversed => status == 'reversed';
  bool get isPosted => status == 'posted';

  factory LedgerEntry.fromMap(Map<String, dynamic> map) => LedgerEntry(
    id: map['id'] as String,
    type: (map['type'] as String?) ?? 'adjustment',
    amount: money(map['amount']),
    isCredit: (map['direction'] as String?) == 'credit',
    status: (map['status'] as String?) ?? 'posted',
    createdAt: _time(map['created_at']) ?? DateTime.now(),
    orderId: map['order_id'] as String?,
    reference: map['reference'] as String?,
    description: map['description'] as String?,
    reversesId: map['reverses_id'] as String?,
  );

  @override
  List<Object?> get props => [id, type, amount, isCredit, status, createdAt];
}

/// A recorded hand-over of money, in either direction.
class Settlement extends Equatable {
  const Settlement({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.amount,
    required this.method,
    required this.status,
    required this.createdAt,
    this.fee = 0,
    this.reference,
    this.notes,
    this.completedAt,
  });

  final String id;
  final LedgerOwner ownerType;
  final String ownerId;

  /// What the party ends up with — always net of [fee].
  final double amount;

  /// The locked-in cost of an early cash-out. Zero for a free settlement;
  /// whether a row is "early" is exactly `fee > 0`, no separate flag.
  final double fee;
  final String method;
  final String status;
  final DateTime createdAt;
  final String? reference;
  final String? notes;
  final DateTime? completedAt;

  bool get isEarly => fee > 0;

  /// What the party was owed before the fee — [amount] plus [fee], both
  /// already-correct numbers off the row, just added back together for
  /// display.
  double get grossAmount => amount + fee;

  factory Settlement.fromMap(Map<String, dynamic> map) => Settlement(
    id: map['id'] as String,
    ownerType: LedgerOwner.from(map['owner_type'] as String?),
    ownerId: (map['owner_id'] as String?) ?? '',
    amount: money(map['amount']),
    fee: money(map['fee']),
    method: (map['method'] as String?) ?? 'cash',
    status: (map['status'] as String?) ?? 'completed',
    createdAt: _time(map['created_at']) ?? DateTime.now(),
    reference: map['reference'] as String?,
    notes: map['notes'] as String?,
    completedAt: _time(map['completed_at']),
  );

  @override
  List<Object?> get props => [id, ownerType, ownerId, amount, fee, status];
}

/// A driver's claim to have paid money in, awaiting review.
///
/// Nothing is credited until an admin approves it — a request is a claim, not
/// money.
class DepositRequest extends Equatable {
  const DepositRequest({
    required this.id,
    required this.driverId,
    required this.amount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    this.driverName,
    this.reference,
    this.proofUrl,
    this.notes,
    this.reviewedAt,
  });

  final String id;
  final String driverId;
  final String? driverName;
  final double amount;
  final String paymentMethod;
  final String status;
  final DateTime createdAt;
  final String? reference;
  final String? proofUrl;
  final String? notes;
  final DateTime? reviewedAt;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';

  factory DepositRequest.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return DepositRequest(
      id: map['id'] as String,
      driverId: map['driver_id'] as String,
      driverName: profile is Map ? profile['full_name'] as String? : null,
      amount: money(map['amount']),
      paymentMethod: (map['payment_method'] as String?) ?? 'bank_transfer',
      status: (map['status'] as String?) ?? 'pending',
      createdAt: _time(map['created_at']) ?? DateTime.now(),
      reference: map['reference'] as String?,
      proofUrl: map['proof_url'] as String?,
      notes: map['notes'] as String?,
      reviewedAt: _time(map['reviewed_at']),
    );
  }

  @override
  List<Object?> get props => [id, driverId, amount, status];
}

/// One party's row in the admin's balances list.
class PartyBalance extends Equatable {
  const PartyBalance({
    required this.ownerId,
    required this.name,
    required this.balance,
    required this.cashDue,
    required this.payable,
    this.cashCollected = 0,
    this.totalEarnings = 0,
    this.totalSettlements = 0,
    this.lastSettlementAt,
  });

  final String ownerId;
  final String name;
  final double balance;
  final double cashDue;
  final double payable;
  final double cashCollected;
  final double totalEarnings;
  final double totalSettlements;
  final DateTime? lastSettlementAt;

  factory PartyBalance.fromMap(Map<String, dynamic> map) => PartyBalance(
    // The two RPCs name the id column after the party they list.
    ownerId: (map['driver_id'] ?? map['vendor_id']) as String,
    name: (map['driver_name'] ?? map['vendor_name'] ?? '—') as String,
    balance: money(map['balance']),
    cashDue: money(map['cash_due']),
    payable: money(map['payable']),
    cashCollected: money(map['cash_collected']),
    totalEarnings: money(map['total_earnings']),
    totalSettlements: money(map['total_settlements']),
    lastSettlementAt: _time(map['last_settlement_at']),
  );

  @override
  List<Object?> get props => [ownerId, name, balance, cashDue, payable];
}

/// The admin's money screen for a period.
class FinanceOverview extends Equatable {
  const FinanceOverview({
    this.totalOrders = 0,
    this.cashOrders = 0,
    this.onlineOrders = 0,
    this.cardOrders = 0,
    this.mobileWalletOrders = 0,
    this.appWalletOrders = 0,
    this.grossRevenue = 0,
    this.codRevenue = 0,
    this.cardRevenue = 0,
    this.mobileWalletRevenue = 0,
    this.appWalletRevenue = 0,
    this.cashCollected = 0,
    this.driverEarnings = 0,
    this.vendorEarnings = 0,
    this.platformCommission = 0,
    this.platformDeliveryMargin = 0,
    this.platformDiscounts = 0,
    this.earlySettlementFees = 0,
    this.platformEarnings = 0,
    this.platformRevenue = 0,
    this.settlements = 0,
    this.deposits = 0,
    this.refunds = 0,
    this.adjustments = 0,
    this.driverCashDue = 0,
    this.vendorPayable = 0,
    this.pendingDeposits = 0,
    this.unsettledOrders = 0,
  });

  final int totalOrders;
  final int cashOrders;
  final int onlineOrders;
  final int cardOrders;
  final int mobileWalletOrders;
  final int appWalletOrders;

  /// What customers were charged for the period's delivered orders, split by
  /// the route the money took. The four parts sum to [grossRevenue] exactly:
  /// every delivered order is on precisely one of them, which is what makes
  /// the split safe to present as a breakdown rather than as four unrelated
  /// figures.
  final double grossRevenue;
  final double codRevenue;
  final double cardRevenue;

  /// An Egyptian mobile wallet (Vodafone Cash and friends) through Paymob —
  /// not [appWalletRevenue], which is this app's own stored balance and never
  /// touches the gateway.
  final double mobileWalletRevenue;
  final double appWalletRevenue;

  /// Of [codRevenue], how much a driver has actually handed over.
  final double cashCollected;
  final double driverEarnings;
  final double vendorEarnings;
  final double platformCommission;
  final double platformDeliveryMargin;
  final double platformDiscounts;

  /// Charged to a vendor who asked to be paid before the settlement date.
  final double earlySettlementFees;

  /// What the business actually made: commission, its share of delivery and
  /// early-settlement fees, less the discounts it funded itself.
  ///
  /// This — not [platformRevenue] — is the bottom line to show an operator.
  final double platformEarnings;

  /// The platform ledger account's net movement, which is a *clearing*
  /// balance, not a profit: customer money lands in this account and leaves
  /// again as vendor and driver settlements, so it trends to zero as
  /// settlements complete. Useful for spotting settlements falling behind
  /// (the balance drifts away from zero), misleading as a headline figure.
  final double platformRevenue;

  final double settlements;
  final double deposits;
  final double refunds;
  final double adjustments;

  /// Positions, not flows: what is owed right now regardless of the period.
  final double driverCashDue;
  final double vendorPayable;

  final int pendingDeposits;

  /// Delivered but never split. Any number above zero is a bug or an outage,
  /// not a normal state.
  final int unsettledOrders;

  factory FinanceOverview.fromMap(Map<String, dynamic> map) => FinanceOverview(
    totalOrders: money(map['total_orders']).toInt(),
    cashOrders: money(map['cash_orders']).toInt(),
    onlineOrders: money(map['online_orders']).toInt(),
    cardOrders: money(map['card_orders']).toInt(),
    mobileWalletOrders: money(map['mobile_wallet_orders']).toInt(),
    appWalletOrders: money(map['app_wallet_orders']).toInt(),
    grossRevenue: money(map['gross_revenue']),
    codRevenue: money(map['cod_revenue']),
    cardRevenue: money(map['card_revenue']),
    mobileWalletRevenue: money(map['mobile_wallet_revenue']),
    appWalletRevenue: money(map['app_wallet_revenue']),
    cashCollected: money(map['cash_collected']),
    driverEarnings: money(map['driver_earnings']),
    vendorEarnings: money(map['vendor_earnings']),
    platformCommission: money(map['platform_commission']),
    platformDeliveryMargin: money(map['platform_delivery_margin']),
    platformDiscounts: money(map['platform_discounts']),
    earlySettlementFees: money(map['early_settlement_fees']),
    platformEarnings: money(map['platform_earnings']),
    platformRevenue: money(map['platform_revenue']),
    settlements: money(map['settlements']),
    deposits: money(map['deposits']),
    refunds: money(map['refunds']),
    adjustments: money(map['adjustments']),
    driverCashDue: money(map['driver_cash_due']),
    vendorPayable: money(map['vendor_payable']),
    pendingDeposits: money(map['pending_deposits']).toInt(),
    unsettledOrders: money(map['unsettled_orders']).toInt(),
  );

  @override
  List<Object?> get props => [
    totalOrders,
    grossRevenue,
    codRevenue,
    cardRevenue,
    mobileWalletRevenue,
    appWalletRevenue,
    cashCollected,
    platformEarnings,
    platformRevenue,
    driverCashDue,
    vendorPayable,
    unsettledOrders,
  ];
}

/// Expected cash against what the ledger actually recorded.
class CashReconciliation extends Equatable {
  const CashReconciliation({
    this.expectedCash = 0,
    this.collectedCash = 0,
    this.settledCash = 0,
    this.outstandingCash = 0,
    this.difference = 0,
  });

  final double expectedCash;
  final double collectedCash;
  final double settledCash;
  final double outstandingCash;

  /// Expected minus collected. Anything other than zero means a cash order was
  /// delivered without a matching collection row — a settlement that did not
  /// run — and needs a human, not a rounding rule.
  final double difference;

  bool get hasException => difference.abs() >= 0.01;

  factory CashReconciliation.fromMap(Map<String, dynamic> map) =>
      CashReconciliation(
        expectedCash: money(map['expected_cash']),
        collectedCash: money(map['collected_cash']),
        settledCash: money(map['settled_cash']),
        outstandingCash: money(map['outstanding_cash']),
        difference: money(map['difference']),
      );

  @override
  List<Object?> get props => [
    expectedCash,
    collectedCash,
    settledCash,
    outstandingCash,
    difference,
  ];
}

/// The offer to pay a store before the weekly run.
class EarlySettlementQuote extends Equatable {
  const EarlySettlementQuote({
    this.payable = 0,
    this.fee = 0,
    this.feePercent = 0,
    this.netPayout = 0,
    this.available = false,
    this.nextScheduledPayout,
  });

  /// What the store is owed right now.
  final double payable;

  /// What the speed costs. A percentage of [payable] with a floor, so
  /// advancing a small balance is not free to the platform.
  final double fee;
  final double feePercent;

  /// What actually reaches the store.
  final double netPayout;

  /// False when there is nothing owed, or when the fee floor would swallow so
  /// much of a tiny balance that the offer is not worth making.
  final bool available;

  /// When the money would arrive anyway, at no cost.
  final DateTime? nextScheduledPayout;

  factory EarlySettlementQuote.fromMap(Map<String, dynamic> map) =>
      EarlySettlementQuote(
        payable: money(map['payable']),
        fee: money(map['fee']),
        feePercent: money(map['fee_percent']),
        netPayout: money(map['net_payout']),
        available: (map['available'] as bool?) ?? false,
        nextScheduledPayout: _time(map['next_scheduled_payout']),
      );

  /// Prices a payout locally, for previewing a fee schedule before it is
  /// saved. Never used to charge anyone: a real quote comes from the server,
  /// which reads the payable from the ledger so a client cannot inflate it.
  ///
  /// Mirrors `vendor_early_settlement_quote` / `driver_early_settlement_quote`
  /// line for line, including the refusal at the end. A preview that
  /// disagreed with the server would be worse than no preview at all.
  static EarlySettlementQuote preview({
    required double payable,
    required double percent,
    required double min,
  }) {
    var fee = payable <= 0
        ? 0.0
        : ((payable * percent / 100 * 100).roundToDouble() / 100);
    if (fee < min) fee = min;
    // The floor can exceed a small balance, and advancing less than nothing is
    // not an offer — so there simply isn't one.
    if (fee >= payable) {
      return EarlySettlementQuote(
        payable: payable,
        feePercent: percent,
        netPayout: payable,
      );
    }
    return EarlySettlementQuote(
      payable: payable,
      fee: fee,
      feePercent: percent,
      netPayout: payable - fee,
      // `fee > 0` is not redundant with the check above: a schedule of 0% with
      // no floor prices every payout at nothing, and the server treats that as
      // no offer rather than as a free one.
      available: payable > 0 && fee > 0,
    );
  }

  @override
  List<Object?> get props => [payable, fee, netPayout, available];
}
