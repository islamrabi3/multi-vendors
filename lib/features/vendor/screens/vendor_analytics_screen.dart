import 'package:flutter/material.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/widgets/common.dart';

import 'package:multi_vendor/core/utils/l10n_extension.dart';

class VendorAnalyticsScreen extends StatefulWidget {
  const VendorAnalyticsScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<VendorAnalyticsScreen> createState() => _VendorAnalyticsScreenState();
}

class _VendorAnalyticsScreenState extends State<VendorAnalyticsScreen> {
  final VendorAdminRepository _vendorRepo = VendorAdminRepository();
  Map<String, dynamic>? _analytics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    final data = await _vendorRepo.fetchAnalytics(widget.vendorId);
    setState(() {
      _analytics = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.storeAnalyticsAndReports),
      ),
      body: _isLoading
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16,
                    16 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: context.l10n.totalRevenue,
                          value: '${((_analytics?['total_revenue'] as num?) ?? 0).toStringAsFixed(2)} EGP',
                          icon: Icons.attach_money,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: context.l10n.deliveredOrders,
                          value: '${_analytics?['total_delivered'] ?? 0}',
                          icon: Icons.check_circle_outline,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.performanceOverview,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          ListTile(
                            leading: const Icon(Icons.star, color: Colors.amber),
                            title: Text(context.l10n.averageStoreRating),
                            trailing: const Text('4.8 / 5.0', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const Divider(),
                          ListTile(
                            leading: const Icon(Icons.timer, color: Colors.orange),
                            title: Text(context.l10n.avgPreparationTime),
                            trailing: Text(context.l10n.twentyMins, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
