import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

/// What the store sold, and what it will actually be paid.
///
/// The previous version summed `orders.total` and called it revenue. That
/// number includes the delivery fee — which goes to the driver and the
/// platform, never to the store — and took no account of commission, so the
/// figure was neither the store's sales nor its payout, and it was the larger
/// of the two. It also printed a hard-coded 4.8 rating and a hard-coded prep
/// time, which is worse than showing nothing.
///
/// Every figure here now comes from `vendor_settlement`, which shares its
/// commission rule with the admin's report, so the store and the platform
/// cannot see different numbers for the same period.
class VendorAnalyticsScreen extends StatefulWidget {
  const VendorAnalyticsScreen({
    super.key,
    required this.vendorId,
    this.embedded = false,
  });

  final String vendorId;
  final bool embedded;

  @override
  State<VendorAnalyticsScreen> createState() => _VendorAnalyticsScreenState();
}

/// Which stretch of trading the page is settling.
enum _Period { today, week, month, all }

class _VendorAnalyticsScreenState extends State<VendorAnalyticsScreen> {
  final _repository = VendorAdminRepository();

  VendorSettlement? _settlement;
  bool _loading = true;
  String? _error;
  _Period _period = _Period.month;

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime? get _start {
    final now = DateTime.now();
    return switch (_period) {
      _Period.today => DateTime(now.year, now.month, now.day),
      _Period.week => now.subtract(const Duration(days: 7)),
      _Period.month => now.subtract(const Duration(days: 30)),
      _Period.all => null,
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final settlement = await _repository.fetchSettlement(
        widget.vendorId,
        start: _start,
      );
      if (!mounted) return;
      setState(() {
        _settlement = settlement;
        _loading = false;
      });
    } catch (error) {
      // A failed read used to leave the spinner up for good.
      if (!mounted) return;
      setState(() {
        _error = errorText(context, error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded
          ? null
          : AppBar(title: Text(l10n.storeAnalyticsAndReports)),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.md,
            AppSpace.gutter,
            AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _PeriodPicker(
              value: _period,
              onChanged: (period) {
                setState(() => _period = period);
                _load();
              },
            ),
            const SizedBox(height: AppSpace.lg),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: LoadingView(),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: ErrorView(message: _error!, onRetry: _load),
              )
            else
              ..._body(_settlement!),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(VendorSettlement s) {
    final l10n = context.l10n;
    return [
      Row(
        children: [
          Expanded(
            child: _StatCard(
              title: l10n.itemSales,
              value: formatMoney(s.itemSales),
              icon: Icons.receipt_long_outlined,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: _StatCard(
              title: l10n.deliveredOrders,
              value: '${s.deliveredOrders}',
              icon: Icons.check_circle_outline,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
      _Card(
        title: l10n.settlement,
        children: [
          _Line(label: l10n.itemSales, value: s.itemSales),
          if (s.vendorDiscounts > 0)
            _Line(
              label: l10n.storeFundedDiscounts,
              value: -s.vendorDiscounts,
              subtle: true,
            ),
          // A subscription store pays a flat fee and no per-order cut, so
          // quoting it a percentage would be wrong in both directions.
          if (s.isSubscription)
            _Line(
              label: l10n.subscriptionPlan,
              value: -s.subscriptionFee,
              suffix: l10n.perMonthSuffix,
              subtle: true,
            )
          else
            _Line(
              label:
                  '${l10n.platformCommission} '
                  '(${s.commissionRate.toStringAsFixed(s.commissionRate % 1 == 0 ? 0 : 1)}%)',
              value: -s.commission,
              subtle: true,
            ),
          const Divider(height: AppSpace.xl, color: AppColors.borderSoft),
          _Line(label: l10n.netPayout, value: s.netPayout, emphasis: true),
          if (s.isSubscription)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.xs),
              child: Text(
                l10n.subscriptionNotDeductedNote,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.textMuted,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
      _Card(
        title: l10n.collectedForOthers,
        children: [
          _Line(
            label: l10n.deliveryFeesTotal,
            value: s.deliveryFeesCollected,
            subtle: true,
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs),
            child: Text(
              l10n.deliveryFeesNotYours,
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
      _Card(
        title: l10n.performanceOverview,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.star_rounded, color: AppColors.rating),
            title: Text(l10n.averageStoreRating),
            // Real, and honest about having no ratings yet rather than
            // printing a flattering placeholder.
            trailing: Text(
              s.ratingCount == 0
                  ? l10n.noRatingsYet
                  : '${s.ratingAvg.toStringAsFixed(1)} · ${s.ratingCount}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.timer_outlined, color: AppColors.primary),
            title: Text(l10n.avgPreparationTime),
            trailing: Text(
              l10n.minutesShort(s.avgPrepMinutes),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Divider(height: 1, color: AppColors.borderSoft),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(
              Icons.shopping_bag_outlined,
              color: AppColors.primary,
            ),
            title: Text(l10n.averageOrder),
            trailing: Text(
              formatMoney(s.averageOrder),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    ];
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.value, required this.onChanged});

  final _Period value;
  final ValueChanged<_Period> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String label(_Period p) => switch (p) {
      _Period.today => l10n.today,
      _Period.week => l10n.last7Days,
      _Period.month => l10n.last30Days,
      _Period.all => l10n.allTime,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final period in _Period.values) ...[
            ChoiceChip(
              selected: period == value,
              label: Text(label(period)),
              onSelected: (_) => onChanged(period),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppType.heading(15)),
          const SizedBox(height: AppSpace.md),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.subtle = false,
    this.emphasis = false,
    this.suffix,
  });

  final String label;
  final double value;
  final bool subtle;
  final bool emphasis;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: emphasis ? 14.5 : 13.5,
                fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
                color: subtle ? AppColors.textMuted : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${value < 0 ? '-' : ''}${formatMoney(value.abs())}${suffix ?? ''}',
            style: AppType.mono(
              emphasis ? 15 : 13.5,
              color: emphasis
                  ? AppColors.successInk
                  : subtle
                  ? AppColors.textMuted
                  : AppColors.ink,
              weight: emphasis ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: AppSpace.md),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.mono(17, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
