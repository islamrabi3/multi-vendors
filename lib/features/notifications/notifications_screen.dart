import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/tokens.dart';
import '../../core/models/order.dart';
import '../../core/utils/l10n_extension.dart';
import '../../core/widgets/skeleton.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final SupabaseClient _client = Supabase.instance.client;
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Fetch recent order status changes & messages for current user
      final orders = await _client
          .from('orders')
          .select(
            'id, order_number, status, updated_at, vendor_id, vendors(name)',
          )
          .or('customer_id.eq.$userId,driver_id.eq.$userId')
          .order('updated_at', ascending: false)
          .limit(20);

      // Announcements and anything else written to the inbox. Order updates
      // are derived from the orders themselves — they need no stored row — but
      // a broadcast exists nowhere else once its push has been dismissed.
      final inbox = await _client
          .from('notifications')
          .select('id, title, body, type, route, is_read, created_at')
          .order('created_at', ascending: false)
          .limit(30);

      final list = <Map<String, dynamic>>[];

      for (final n in inbox) {
        list.add({
          'id': n['id'],
          'title': n['title'],
          'body': n['body'] ?? '',
          'route': n['route'],
          'created_at': DateTime.parse(n['created_at'] as String).toLocal(),
          'icon': Icons.campaign_rounded,
          'color': AppColors.primaryDark,
        });
      }

      for (final o in orders) {
        final status = OrderStatus.fromName(o['status'] as String?);
        final vendorName =
            (o['vendors'] as Map?)?['name'] as String? ?? 'Store';
        list.add({
          'id': o['id'],
          'title': 'Order #${o['order_number'] ?? ''} Update 🚚',
          'body': '$vendorName: Status is now ${status.label}',
          'order_id': o['id'],
          'created_at': DateTime.parse(o['updated_at'] as String).toLocal(),
          'icon': Icons.local_shipping_rounded,
          'color': AppColors.primary,
        });
      }

      // One stream, newest first, whichever source a line came from.
      list.sort(
        (a, b) => (b['created_at'] as DateTime).compareTo(
          a['created_at'] as DateTime,
        ),
      );

      setState(() {
        _notifications = list;
        _isLoading = false;
      });

      // Opening the screen is what marks them read; the bell's unread count
      // would otherwise never clear.
      unawaited(_client.rpc('mark_notifications_read').catchError((_) {}));
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(context.l10n.notifications),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: _isLoading
          ? const _NotificationsSkeleton()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadNotifications,
              child: _notifications.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  color: AppColors.warmFill,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                  size: 48,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.noNotificationsYet,
                                style: AppType.heading(
                                  18,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'You will receive status updates and alerts here.',
                                style: TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      itemCount: _notifications.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final notif = _notifications[index];
                        final date = notif['created_at'] as DateTime;
                        final dateStr =
                            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} - ${date.day}/${date.month}/${date.year}';

                        return Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(AppRadii.lg),
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppShadows.card,
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: AppColors.warmFill,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                notif['icon'] as IconData,
                                color: notif['color'] as Color,
                                size: 22,
                              ),
                            ),
                            title: Text(
                              notif['title'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: AppColors.ink,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 3),
                                Text(
                                  notif['body'] as String,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  dateStr,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textFaint,
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              final orderId = notif['order_id'] as String?;
                              if (orderId != null) {
                                context.push('/order/$orderId');
                                return;
                              }
                              // An announcement carries wherever the admin
                              // pointed it, or nothing at all — in which case
                              // the row is just something to read.
                              final route = notif['route'] as String?;
                              if (route != null && route.isNotEmpty) {
                                context.push(route);
                              }
                            },
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

/// Notifications while the feed loads. Same 16/12 padding and 8px separation as
/// the real `ListView.separated`, and the same 42px avatar.
class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: SkeletonList(
        itemCount: 6,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        separator: const SizedBox(height: AppSpace.sm),
        itemBuilder: (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: const Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.lg,
            ),
            child: Row(
              children: [
                Skeleton.circle(size: 42),
                SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(widthFactor: 0.6, height: 14),
                      SizedBox(height: 7),
                      Skeleton.line(widthFactor: 0.85, height: 12),
                      SizedBox(height: 6),
                      Skeleton.line(widthFactor: 0.4, height: 10),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
