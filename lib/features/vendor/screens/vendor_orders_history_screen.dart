import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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

  /// The day on screen. Opens on today — the question a shop asks first —
  /// and moves one day at a time or jumps via the calendar.
  late DateTime _day = _dateOnly(DateTime.now());

  /// null = every finished order; true = completed only; false = cancelled
  /// or rejected only.
  bool? _completedOnly;

  static bool _isCancelled(AppOrder o) =>
      o.status == OrderStatus.cancelled || o.status == OrderStatus.rejected;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday => _day == _dateOnly(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<AppOrder>> _page(int offset) => _repository.fetchVendorOrdersPage(
    vendorId: widget.vendorId,
    limit: kPageSize,
    offset: offset,
    from: _day,
    to: _day.add(const Duration(days: 1)),
  );

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final requested = _day;
    try {
      final page = await _page(0);
      // The day changed while this was loading; its own load will land.
      if (!mounted || requested != _day) return;
      setState(() {
        _orders
          ..clear()
          ..addAll(page);
        _hasMore = page.length == kPageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || requested != _day) return;
      setState(() {
        _error = errorText(context, error);
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final requested = _day;
    try {
      final page = await _page(_orders.length);
      if (!mounted || requested != _day) return;
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

  void _setDay(DateTime day) {
    final next = _dateOnly(day);
    if (next.isAfter(_dateOnly(DateTime.now()))) return;
    setState(() {
      _day = next;
      _completedOnly = null;
    });
    _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) _setDay(picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final yesterday = _dateOnly(
      DateTime.now().subtract(const Duration(days: 1)),
    );
    final dayLabel = _isToday
        ? l10n.today
        : _day == yesterday
        ? l10n.yesterday
        : DateFormat.yMMMEd(language).format(_day);

    final counted = _orders.where(
      (o) =>
          o.status != OrderStatus.cancelled && o.status != OrderStatus.rejected,
    );
    final takings = counted.fold<double>(0, (sum, o) => sum + o.subtotal);
    final cancelled = _orders.length - counted.length;

    final dayBar = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.previousDay,
              // chevron_left mirrors itself in RTL, so "previous" stays on
              // the reading-start side.
              icon: const Icon(Icons.chevron_left_rounded),
              onPressed: () => _setDay(_day.subtract(const Duration(days: 1))),
            ),
            Expanded(
              child: InkWell(
                onTap: _pickDay,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          dayLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.heading(15),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.nextDay,
              icon: const Icon(Icons.chevron_right_rounded),
              onPressed: _isToday
                  ? null
                  : () => _setDay(_day.add(const Duration(days: 1))),
            ),
          ],
        ),
      ),
    );

    final summary = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        AppSpace.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(label: l10n.orders, value: '${counted.length}'),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            flex: 2,
            child: _SummaryTile(
              label: l10n.takings,
              value: formatMoney(takings),
              emphasis: true,
            ),
          ),
          if (cancelled > 0) ...[
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: _SummaryTile(
                label: l10n.cancelled,
                value: '$cancelled',
                tone: AppColors.dangerInk,
              ),
            ),
          ],
        ],
      ),
    );

    Widget list;
    if (_loading) {
      list = const LoadingView();
    } else if (_error != null) {
      list = ErrorView(message: _error!, onRetry: _load);
    } else if (_orders.isEmpty) {
      list = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          EmptyView(
            message: l10n.noOrdersOnDay,
            icon: Icons.receipt_long_outlined,
          ),
          if (_isToday) ...[
            const SizedBox(height: AppSpace.md),
            Center(
              child: TextButton.icon(
                onPressed: _pickDay,
                icon: const Icon(Icons.calendar_month_rounded, size: 18),
                label: Text(l10n.pickAnotherDay),
              ),
            ),
          ],
        ],
      );
    } else {
      final shown = _completedOnly == null
          ? _orders
          : _orders.where((o) => _isCancelled(o) != _completedOnly).toList();
      list = InfiniteScroll(
        onLoadMore: _loadMore,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: shown.length + 1,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (context, i) => i == shown.length
              ? PagingFooter(loading: _loadingMore, hasMore: _hasMore)
              : _OrderRow(order: shown[i]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded ? null : AppBar(title: Text(l10n.ordersHistory)),
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        // Centred and capped on the web: a day's orders stretched across a
        // 1200px pane put the amount a long way from the order it belongs to.
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                dayBar,
                if (!_loading && _error == null && _orders.isNotEmpty) ...[
                  summary,
                  if (cancelled > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpace.gutter,
                        0,
                        AppSpace.gutter,
                        AppSpace.sm,
                      ),
                      child: Row(
                        children: [
                          for (final (value, label) in [
                            (null, l10n.all),
                            (true, l10n.completedOrders),
                            (false, l10n.cancelled),
                          ]) ...[
                            ChoiceChip(
                              label: Text(label),
                              selected: _completedOnly == value,
                              onSelected: (_) =>
                                  setState(() => _completedOnly = value),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                ],
                Expanded(child: list),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    this.emphasis = false,
    this.tone = AppColors.ink,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasis ? AppColors.warmFill : AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: emphasis ? Colors.transparent : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: AppType.mono(16, color: tone, weight: FontWeight.w800),
            ),
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
                      '${formatClock(context, order.createdAt)}'
                      ' · ${context.l10n.itemsCount(order.items.fold(0, (n, i) => n + i.quantity))}',
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
