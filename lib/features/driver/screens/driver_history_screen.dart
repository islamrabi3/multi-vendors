import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/order.dart';
import '../../../core/repositories/order_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

class DriverHistoryScreen extends StatelessWidget {
  const DriverHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final repository = OrderRepository();
    return StreamBuilder<List<AppOrder>>(
      stream: repository.driverOrdersStream(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const LoadingView();
        final delivered = snapshot.data!
            .where((o) => o.status == OrderStatus.delivered)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (delivered.isEmpty) {
          return const EmptyView(
              message: 'No deliveries yet', icon: Icons.history);
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: delivered.length,
          itemBuilder: (context, index) {
            final order = delivered[index];
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6),
              child: ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: Text(order.orderNumber),
                subtitle: Text(
                    DateFormat('d MMM y, h:mm a').format(order.createdAt)),
                trailing: Text(formatMoney(order.total)),
              ),
            );
          },
        );
      },
    );
  }
}
