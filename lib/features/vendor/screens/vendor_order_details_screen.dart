import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

class VendorOrderDetailsScreen extends StatefulWidget {
  const VendorOrderDetailsScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<VendorOrderDetailsScreen> createState() =>
      _VendorOrderDetailsScreenState();
}

class _VendorOrderDetailsScreenState extends State<VendorOrderDetailsScreen> {
  final _repository = OrderRepository();
  AppOrder? _order;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final order = await _repository.fetchOrder(widget.orderId);
      if (mounted) setState(() => _order = order);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    return Scaffold(
      appBar: AppBar(title: Text(order?.orderNumber ?? 'Order')),
      body: _error != null
          ? ErrorView(message: readableError(_error!), onRetry: _load)
          : order == null
              ? const LoadingView()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                            DateFormat('d MMM y, h:mm a')
                                .format(order.createdAt),
                            style: Theme.of(context).textTheme.bodyMedium),
                        OrderStatusChip(status: order.status),
                      ],
                    ),
                    const Divider(height: 32),
                    Text('Items',
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final item in order.items)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Text('${item.quantity}x',
                            style: Theme.of(context).textTheme.titleSmall),
                        title: Text(item.productName),
                        subtitle: item.optionNames.isEmpty
                            ? null
                            : Text(item.optionNames.join(', ')),
                        trailing: Text(formatMoney(item.lineTotal)),
                      ),
                    if (order.customerNotes?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text('Note: ${order.customerNotes}'),
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                    Text('Customer',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(order.customerName ?? 'Customer'),
                    if (order.customerPhone != null)
                      Text(order.customerPhone!),
                    const SizedBox(height: 4),
                    Text(order.addressSummary,
                        style: Theme.of(context).textTheme.bodySmall),
                    const Divider(height: 32),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(formatMoney(order.total),
                            style: Theme.of(context).textTheme.titleLarge),
                      ],
                    ),
                    Text(
                      order.isCod
                          ? 'Cash on delivery — collect on handover'
                          : 'Paid online: ${order.paymentStatus}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
    );
  }
}
