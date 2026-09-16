import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/loyalty_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/paging.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final LoyaltyRepository _loyaltyRepo = LoyaltyRepository();
  int _points = 0;
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  bool _hasMore = false;
  bool _loadingMore = false;

  /// The platform's exchange rate and floor; read once with the balance.
  int _pointsPerUnit = 100;
  int _minRedeem = 1000;
  bool _redeeming = false;

  bool get _canRedeem => _points >= _minRedeem;

  /// Points are spent in whole units, so a remainder stays on the balance.
  int get _redeemablePoints => (_points ~/ _pointsPerUnit) * _pointsPerUnit;

  double get _redeemableCredit => _redeemablePoints / _pointsPerUnit;

  @override
  void initState() {
    super.initState();
    _loadLoyalty();
  }

  static FeedCursor _cursorOf(Map<String, dynamic> row) => (
    createdAt: DateTime.parse(row['created_at'] as String),
    id: row['id'] as String,
  );

  Future<void> _loadLoyalty() async {
    try {
      final results = await Future.wait([
        _loyaltyRepo.getPoints(),
        _loyaltyRepo.getHistory(),
      ]);
      final config = await _loyaltyRepo.redeemConfig().catchError(
        (_) => (pointsPerUnit: 100, minRedeem: 1000),
      );
      if (!mounted) return;
      final history = results[1] as List<Map<String, dynamic>>;
      setState(() {
        _pointsPerUnit = config.pointsPerUnit;
        _minRedeem = config.minRedeem;
        _points = results[0] as int;
        _history = history;
        _hasMore = history.length == kPageSize;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFailure(context, error, onRetry: _loadLoyalty);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _history.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _loyaltyRepo.getHistory(
        before: _cursorOf(_history.last),
      );
      if (!mounted) return;
      setState(() {
        _history = [..._history, ...page];
        _hasMore = page.length == kPageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showFailure(context, error, onRetry: _loadMore);
    }
  }

  /// Spends the whole redeemable balance: the rate is fixed, so a form asking
  /// how much would be a decision with one sensible answer.
  Future<void> _redeem() async {
    final l10n = context.l10n;
    final points = _redeemablePoints;
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: l10n.redeemPoints,
      message: l10n.redeemRateHint(_pointsPerUnit, formatMoney(1)),
      confirmText: l10n.redeemPoints,
      cancelText: l10n.cancel,
      icon: Icons.redeem_rounded,
    );
    if (confirmed != true) return;
    setState(() => _redeeming = true);
    try {
      final credit = await _loyaltyRepo.redeem(points);
      if (!mounted) return;
      showSnack(context, l10n.redeemDone(formatMoney(credit)));
      setState(() => _redeeming = false);
      await _loadLoyalty();
    } catch (error) {
      if (!mounted) return;
      setState(() => _redeeming = false);
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.loyaltyRewards), elevation: 0),
      body: _isLoading
          ? const _LoyaltySkeleton()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadLoyalty,
              child: NotificationListener<ScrollNotification>(
                // Pages itself as the customer reaches the end; the button
                // below stays for anyone who scrolls faster than the fetch.
                onNotification: (n) {
                  if (n.metrics.pixels >= n.metrics.maxScrollExtent - 400) {
                    _loadMore();
                  }
                  return false;
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.md,
                    AppSpace.lg,
                    AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    FinanceHero(
                      eyebrow: l10n.points,
                      amount: '$_points',
                      caption: l10n.earnPointsOnOrders,
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: AppSpace.lg),
                      padding: const EdgeInsets.all(AppSpace.lg),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.redeemToWallet,
                            style: AppType.heading(15.5),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _canRedeem
                                ? l10n.redeemWorth(
                                    formatMoney(_redeemableCredit),
                                  )
                                : l10n.redeemMinHint(_minRedeem),
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const SizedBox(height: AppSpace.md),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            onPressed: _canRedeem && !_redeeming
                                ? _redeem
                                : null,
                            icon: _redeeming
                                ? const ButtonSpinner(size: 18)
                                : const Icon(Icons.redeem_rounded, size: 18),
                            label: Text(l10n.redeemPoints),
                          ),
                        ],
                      ),
                    ),
                    FinanceSection(
                      title: l10n.pointsHistory,
                      child: _history.isEmpty
                          ? FinanceEmpty(
                              message: l10n.noLoyaltyPointsYet,
                              icon: Icons.stars_rounded,
                            )
                          : DayGroupedList<Map<String, dynamic>>(
                              items: _history,
                              dateOf: (row) =>
                                  _cursorOf(row).createdAt.toLocal(),
                              itemBuilder: (row) => _HistoryTile(row: row),
                            ),
                    ),
                    if (_hasMore)
                      FinanceLoadMore(busy: _loadingMore, onPressed: _loadMore),
                  ],
                ),
              ),
            ),
    );
  }
}

/// One points movement. The server writes `action` as free text
/// ("Order #fb2f40f7 reward", or the older `order_reward`), so the label is
/// localized here and only the order reference is kept from the text.
class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.row});

  final Map<String, dynamic> row;

  static final _orderRef = RegExp(r'#([0-9A-Za-z-]+)');

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final change = ((row['points_change'] as num?) ?? 0).toInt();
    final action = (row['action'] as String?) ?? '';
    final ref = _orderRef.firstMatch(action)?.group(1);
    final isOrderReward =
        row['order_id'] != null ||
        action == 'order_reward' ||
        action.toLowerCase().contains('reward');
    final createdAt = DateTime.parse(row['created_at'] as String).toLocal();
    return FinanceTxTile(
      icon: isOrderReward ? Icons.redeem_rounded : Icons.stars_rounded,
      title: isOrderReward ? l10n.loyaltyOrderReward : action,
      subtitle: [
        formatClock(context, createdAt),
        if (ref != null) l10n.orderRef(ref),
      ].join(' · '),
      amount: l10n.pointsValue('${change.abs()}'),
      isCredit: change >= 0,
    );
  }
}

/// Loyalty while the balance and history load: the points hero, then rows.
class _LoyaltySkeleton extends StatelessWidget {
  const _LoyaltySkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          const Skeleton.box(height: 168, radius: AppRadii.xl),
          const SizedBox(height: AppSpace.xxl),
          const Skeleton.line(widthFactor: 0.4, height: 18),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < 5; i++) ...[
            Row(
              children: const [
                Skeleton.circle(size: 24),
                SizedBox(width: AppSpace.lg),
                Expanded(child: Skeleton.line(widthFactor: 0.55, height: 14)),
                SizedBox(width: AppSpace.lg),
                Skeleton(width: 64, height: 14),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
          ],
        ],
      ),
    );
  }
}
