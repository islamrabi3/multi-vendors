import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/paging.dart';
import '../../../core/widgets/common.dart';

/// Everything the store has sold, grouped by day.
///
/// The dashboard's "past" tab answers "what happened just now"; this answers
/// "how did Tuesday go", which is the question a store actually asks. Grouped
/// by day with a running count and takings per day, because a flat list of
/// orders makes a shop owner do the addition themselves.
///
/// Takings are `subtotal`, not `total`: the delivery fee inside `total` is the
/// driver's and the platform's, and showing it here would overstate the day.
class VendorOrdersHistoryScreen extends StatefulWidget {
  const VendorOrdersHistoryScreen({
    super.key,
    required this.vendorId,
    this.embedded = false,
  });

  final String vendorId;
  final bool embedded;

  @override
  State<VendorOrdersHistoryScreen> createState() =>
      _VendorOrdersHistoryScreenState();
}

class _VendorOrdersHistoryScreenState extends State<VendorOrdersHistoryScreen> {
  final _repository = VendorAdminRepository();

  final List<AppOrder> _orders = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository.fetchVendorOrdersPage(
        vendorId: widget.vendorId,
        limit: kPageSize,
        offset: 0,
      );
      if (!mounted) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(page);
        _hasMore = page.length == kPageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = errorText(context, error);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repository.fetchVendorOrdersPage(
        vendorId: widget.vendorId,
        limit: kPageSize,
        offset: _orders.length,
      );
      if (!mounted) return;
      // An order finishing shifts every offset, so pages can overlap.
      final known = _orders.map((o) => o.id).toSet();
      setState(() {
        _orders.addAll(page.where((o) => !known.contains(o.id)));
        _hasMore = page.length == kPageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showFailure(context, error);
    }
  }

  /// Days in order, each with the orders that landed on it.
  List<(DateTime, List<AppOrder>)> get _byDay {
    final buckets = <DateTime, List<AppOrder>>{};
    for (final order in _orders) {
      final day = DateTime(
        order.createdAt.year,
        order.createdAt.month,
        order.createdAt.day,
      );
      buckets.putIfAbsent(day, () => []).add(order);
    }
    final days = buckets.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final day in days) (day, buckets[day]!)];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final grouped = _byDay;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded ? null : AppBar(title: Text(l10n.ordersHistory)),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: _loading
            ? const LoadingView()
            : _error != null
            ? ErrorView(message: _error!, onRetry: _load)
            : grouped.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  const SizedBox(height: 100),
                  EmptyView(
                    message: l10n.noOrdersOnDay,
                    icon: Icons.receipt_long_outlined,
                  ),
                ],
              )
            : InfiniteScroll(
                onLoadMore: _loadMore,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.gutter,
                    AppSpace.md,
                    AppSpace.gutter,
                    AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    for (final (day, orders) in grouped) ...[
                      _DayHeader(day: day, orders: orders),
                      for (final order in orders) _OrderRow(order: order),
                      const SizedBox(height: AppSpace.lg),
                    ],
                    PagingFooter(loading: _loadingMore, hasMore: _hasMore),
                  ],
                ),
              ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.orders});

  final DateTime day;
  final List<AppOrder> orders;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Cancelled and rejected orders are listed — the store wants to see them —
    // but they are not takings, so they are left out of the total.
    final counted = orders.where(
      (o) =>
          o.status != OrderStatus.cancelled && o.status != OrderStatus.rejected,
    );
    final takings = counted.fold<double>(0, (sum, o) => sum + o.subtotal);

    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm, top: AppSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              isToday ? l10n.today : '${day.day}/${day.month}/${day.year}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.heading(15),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${counted.length}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            formatMoney(takings),
            style: AppType.mono(14, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final AppOrder order;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: () => context.push('/vendor-app/orders/${order.id}'),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md,
            vertical: AppSpace.sm + 2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            order.orderNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.mono(13, weight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OrderTypeChip(order: order, compact: true),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${TimeOfDay.fromDateTime(order.createdAt).format(context)}'
                      ' · ${order.items.length}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(order.subtotal),
                    style: AppType.mono(13.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  OrderStatusChip(status: order.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
