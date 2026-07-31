import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

/// `10` and `12.5` both read better without trailing zeros.
String _percent(double rate) =>
    '${rate.toStringAsFixed(rate % 1 == 0 ? 0 : 1)}%';

class _AdminReportsScreenState extends State<AdminReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController =
      TabController(length: 2, vsync: this);
  final _repo = AdminRepository();

  bool _loading = true;
  String? _error;
  List<VendorReportItem> _vendorReports = const [];
  List<DriverReportItem> _driverReports = const [];

  String _dateFilter = 'all'; // 'today', 'week', 'month', 'all'

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  DateTime? get _startDate {
    final now = DateTime.now();
    switch (_dateFilter) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case 'week':
        return now.subtract(const Duration(days: 7));
      case 'month':
        return DateTime(now.year, now.month - 1, now.day);
      default:
        return null;
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final start = _startDate;
      final vendorData = await _repo.fetchVendorSalesReport(startDate: start);
      final driverData = await _repo.fetchDriverEarningsReport(startDate: start);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _vendorReports = vendorData;
        _driverReports = driverData;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalVendorSales =
        _vendorReports.fold<double>(0, (sum, item) => sum + item.grossSales);
    final totalPlatformFees =
        _vendorReports.fold<double>(0, (sum, item) => sum + item.commissionFee);
    final totalVendorPayouts =
        _vendorReports.fold<double>(0, (sum, item) => sum + item.netPayout);

    final totalDriverFees =
        _driverReports.fold<double>(0, (sum, item) => sum + item.deliveryFeesEarned);
    final totalDriverTips =
        _driverReports.fold<double>(0, (sum, item) => sum + item.tipsEarned);
    final totalDriverPayouts =
        _driverReports.fold<double>(0, (sum, item) => sum + item.netDriverPayout);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Financial & Sales Reports'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Vendor Sales'),
            Tab(text: 'Driver Payouts'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Date Filter Bar
            Padding(
              padding: const EdgeInsets.all(AppSpace.gutter),
              child: Row(
                children: [
                  const Text(
                    'Period: ',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'today', label: Text('Today')),
                        ButtonSegment(value: 'week', label: Text('7 Days')),
                        ButtonSegment(value: 'month', label: Text('Month')),
                        ButtonSegment(value: 'all', label: Text('All Time')),
                      ],
                      selected: {_dateFilter},
                      onSelectionChanged: (set) {
                        setState(() => _dateFilter = set.first);
                        _loadData();
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? ErrorView(message: _error!, onRetry: _loadData)
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            // Vendor Sales Tab
                            RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.gutter),
                                children: [
                                  _SummaryCard(
                                    title: 'Vendor Sales Summary',
                                    metric1Title: 'Gross Sales',
                                    metric1Val: formatMoney(totalVendorSales),
                                    metric2Title: 'Platform Commission',
                                    metric2Val: formatMoney(totalPlatformFees),
                                    metric3Title: 'Net Vendor Payouts',
                                    metric3Val: formatMoney(totalVendorPayouts),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Vendor Breakdown',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_vendorReports.isEmpty)
                                    const EmptyView(
                                      message:
                                          'No delivered vendor orders found in this period.',
                                      icon: Icons.storefront_outlined,
                                    )
                                  else
                                    for (final item in _vendorReports)
                                      Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: ListTile(
                                          title: Text(item.vendorName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          subtitle: Text(
                                            'Orders: ${item.totalOrders} · '
                                            'Sales: ${formatMoney(item.grossSales)} · '
                                            'Fee (${_percent(item.commissionRate)}): '
                                            '${formatMoney(item.commissionFee)}',
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                formatMoney(item.netPayout),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.successInk,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const Text(
                                                'Net Payout',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),

                            // Driver Earnings Tab
                            RefreshIndicator(
                              onRefresh: _loadData,
                              child: ListView(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpace.gutter),
                                children: [
                                  _SummaryCard(
                                    title: 'Driver Earnings Summary',
                                    metric1Title: 'Total Delivery Fees',
                                    metric1Val: formatMoney(totalDriverFees),
                                    metric2Title: 'Platform Share',
                                    metric2Val: formatMoney(
                                        totalDriverFees +
                                            totalDriverTips -
                                            totalDriverPayouts),
                                    metric3Title: 'Net Driver Payouts',
                                    metric3Val: formatMoney(totalDriverPayouts),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Driver Breakdown',
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 8),
                                  if (_driverReports.isEmpty)
                                    const EmptyView(
                                      message:
                                          'No delivered driver orders found in this period.',
                                      icon: Icons.two_wheeler_outlined,
                                    )
                                  else
                                    for (final item in _driverReports)
                                      Card(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        child: ListTile(
                                          title: Text(item.driverName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold)),
                                          subtitle: Text(
                                            'Deliveries: ${item.deliveredOrders} · '
                                            'Fees: ${formatMoney(item.deliveryFeesEarned)} · '
                                            'Tips: ${formatMoney(item.tipsEarned)}',
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                formatMoney(
                                                    item.netDriverPayout),
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              const Text(
                                                'Net Payout',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.metric1Title,
    required this.metric1Val,
    required this.metric2Title,
    required this.metric2Val,
    required this.metric3Title,
    required this.metric3Val,
  });

  final String title;
  final String metric1Title;
  final String metric1Val;
  final String metric2Title;
  final String metric2Val;
  final String metric3Title;
  final String metric3Val;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.ink,
            ),
          ),
          const Divider(height: 20),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric1Title,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(metric1Val,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(metric2Title,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(metric2Val,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(metric3Title,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 2),
                    Text(
                      metric3Val,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.successInk,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
