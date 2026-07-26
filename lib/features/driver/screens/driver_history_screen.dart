import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  final _repository = OrderRepository();
  final _pendingLabels = <String>{};
  Map<String, ({String name, String? logoUrl})> _labels = {};

  final List<AppOrder> _trips = [];
  List<AppOrder> _weekOrders = [];
  bool _loading = false;
  bool _loadingWeek = false;
  bool _hasMore = true;
  int _offset = 0;
  static const _limit = 15;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadWeekOrders();
    _loadNextPage();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadNextPage();
    }
  }

  Future<void> _loadWeekOrders() async {
    if (_loadingWeek) return;
    setState(() => _loadingWeek = true);
    try {
      final res = await _repository.fetchDriverCurrentWeekOrders();
      setState(() => _weekOrders = res);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingWeek = false);
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final newTrips = await _repository.fetchDriverHistory(limit: _limit, offset: _offset);
      _ensureLabels(newTrips);
      setState(() {
        _trips.addAll(newTrips);
        _offset += newTrips.length;
        _hasMore = newTrips.length == _limit;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _trips.clear();
      _offset = 0;
      _hasMore = true;
    });
    await Future.wait([
      _loadWeekOrders(),
      _loadNextPage(),
    ]);
  }

  void _ensureLabels(List<AppOrder> orders) {
    final missing = orders
        .map((o) => o.vendorId)
        .where((id) => !_labels.containsKey(id) && !_pendingLabels.contains(id))
        .toSet();
    if (missing.isEmpty) return;
    _pendingLabels.addAll(missing);
    _repository.vendorLabels(missing).then((labels) {
      if (mounted) setState(() => _labels = {..._labels, ...labels});
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingWeek && _trips.isEmpty) {
      return const LoadingView();
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _refresh,
          child: ListView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              Text(context.l10n.earnings, style: AppType.display(26)),
              const SizedBox(height: 12),
              _WeekHero(delivered: _weekOrders),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child:
                        Text(context.l10n.recentTrips, style: AppType.display(18)),
                  ),
                  Text('${_trips.length} ${context.l10n.delivered}',
                      style: const TextStyle(
                          fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
              const SizedBox(height: 10),
              if (_trips.isEmpty && !_loading)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: EmptyView(
                      message: context.l10n.noDeliveriesYet, icon: Icons.history),
                )
              else ...[
                for (final order in _trips) ...[
                  _TripTile(order: order, label: _labels[order.vendorId]),
                  const SizedBox(height: 10),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekHero extends StatelessWidget {
  const _WeekHero({required this.delivered});

  final List<AppOrder> delivered;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    // Payout (delivery fee) per weekday, Monday-first.
    final perDay = List<double>.filled(7, 0);
    for (final order in delivered) {
      final day = DateTime(order.createdAt.year, order.createdAt.month,
          order.createdAt.day);
      final index = day.difference(monday).inDays;
      if (index >= 0 && index < 7) perDay[index] += order.deliveryFee;
    }
    final weekTotal = perDay.fold<double>(0, (sum, v) => sum + v);
    final maxDay =
        perDay.fold<double>(0, (max, v) => v > max ? v : max);
    final todayIndex = now.weekday - 1;
    final dayLetters = [
      context.l10n.mondayInitial,
      context.l10n.tuesdayInitial,
      context.l10n.wednesdayInitial,
      context.l10n.thursdayInitial,
      context.l10n.fridayInitial,
      context.l10n.saturdayInitial,
      context.l10n.sundayInitial,
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.l10n.thisWeek,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Text('${context.l10n.egp} ${weekTotal.toStringAsFixed(0)}',
              style: AppType.display(34, color: Colors.white)),
          const SizedBox(height: 14),
          SizedBox(
            height: 74,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: FractionallySizedBox(
                            alignment: Alignment.bottomCenter,
                            heightFactor: maxDay == 0
                                ? 0.15
                                : 0.15 + 0.85 * (perDay[i] / maxDay),
                            child: Container(
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: i == todayIndex
                                    ? AppColors.success
                                    : const Color(0xFF3A4A40),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(dayLetters[i],
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: i == todayIndex
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                color: i == todayIndex
                                    ? const Color(0xFF5FE39B)
                                    : Colors.white
                                        .withValues(alpha: 0.5))),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({required this.order, required this.label});

  final AppOrder order;
  final ({String name, String? logoUrl})? label;

  @override
  Widget build(BuildContext context) {
    final street = order.deliveryAddress['street'] as String?;
    final title = [
      label?.name ?? context.l10n.store,
      if (street != null && street.isNotEmpty) street,
    ].join(' → ');
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.warmFill,
              borderRadius: BorderRadius.circular(11),
            ),
            clipBehavior: Clip.antiAlias,
            child: label?.logoUrl != null
                ? AppNetworkImage(url: label!.logoUrl, width: 38, height: 38)
                : const Icon(Icons.storefront,
                    size: 19, color: AppColors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                PriceText(
                  '${order.orderNumber} · '
                  '${DateFormat('d MMM, h:mm a').format(order.createdAt)}',
                  size: 11,
                  color: AppColors.textMuted,
                  weight: FontWeight.w500,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('+${order.deliveryFee.toStringAsFixed(0)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: AppColors.success)),
        ],
      ),
    );
  }
}
