import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/notification_service.dart';

class ReportRepository {
  final SupabaseClient _client;
  ReportRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<void> submitReport({
    required String subject,
    required String description,
    String? orderId,
    String? vendorId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    await _client.from('customer_reports').insert({
      'user_id': userId,
      'subject': subject,
      'description': description,
      'order_id': orderId,
      'vendor_id': vendorId,
      'status': 'pending',
    });
  }

  Future<List<Map<String, dynamic>>> fetchReports({String? status}) async {
    var query = _client
        .from('customer_reports')
        .select('*, orders(order_number), vendors(name)');

    if (status != null && status != 'all') {
      query = query.eq('status', status);
    }

    final res = await query.order('created_at', ascending: false);
    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<void> resolveReport({
    required String reportId,
    required String userId,
    required String replyMessage,
  }) async {
    await _client.from('customer_reports').update({
      'status': 'resolved',
      'admin_reply': replyMessage,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);

    // Send push / in-app notification to customer
    try {
      NotificationService.instance.sendNotificationToUser(
        userId: userId,
        title: 'Report Resolution Update 💬',
        body: replyMessage,
        data: {'report_id': reportId, 'status': 'resolved'},
      );
    } catch (_) {}
  }
}
