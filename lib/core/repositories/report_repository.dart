import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/customer_report.dart';
import '../utils/live_count.dart';

/// Customer complaints and their follow-up threads.
///
/// RLS keeps a customer to their own complaints and gives admins all of them.
/// Thread messages are written only through `report_send_message`, which also
/// reopens, resolves and flags the complaint in the same transaction.
class ReportRepository {
  final SupabaseClient _client;
  ReportRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  static const _select = '*, orders(order_number), vendors(name)';

  /// Files a complaint and returns its id, so the caller can open the thread.
  Future<String?> submitReport({
    required String subject,
    required String description,
    String? orderId,
    String? vendorId,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('customer_reports')
        .insert({
          'user_id': userId,
          'subject': subject,
          'description': description,
          'order_id': orderId,
          'vendor_id': vendorId,
          'status': 'pending',
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  /// The signed-in customer's complaints, most recently active first.
  Future<List<CustomerReport>> fetchMyReports() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];
    final res = await _client
        .from('customer_reports')
        .select(_select)
        .eq('user_id', userId)
        .order('updated_at', ascending: false);
    return (res as List)
        .map((e) => CustomerReport.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// The admin queue, with each customer's name attached.
  Future<List<CustomerReport>> fetchReports({String? status}) async {
    var query = _client.from('customer_reports').select(_select);
    if (status != null && status != 'all') {
      query = query.eq('status', status);
    }
    final res = await query.order('updated_at', ascending: false);
    final rows = (res as List).cast<Map<String, dynamic>>();

    // No foreign key from reports to profiles, so names are a second read.
    final userIds = {for (final r in rows) r['user_id'] as String};
    final names = <String, String?>{};
    if (userIds.isNotEmpty) {
      try {
        final profiles = await _client
            .from('profiles')
            .select('id, full_name')
            .inFilter('id', userIds.toList());
        for (final p in profiles) {
          names[p['id'] as String] = p['full_name'] as String?;
        }
      } catch (_) {
        // Names are a label; the queue works without them.
      }
    }
    final reports = [
      for (final r in rows)
        CustomerReport.fromMap({
          ...r,
          'profiles': {'full_name': names[r['user_id']]},
        }),
    ];
    // Open before resolved; within open, the ones waiting on support first.
    reports.sort((a, b) {
      if (a.isResolved != b.isResolved) return a.isResolved ? 1 : -1;
      if (a.awaitsSupport != b.awaitsSupport) return a.awaitsSupport ? -1 : 1;
      return b.lastActivity.compareTo(a.lastActivity);
    });
    return reports;
  }

  /// One complaint, with order number and store name.
  Future<CustomerReport?> fetchReport(String id) async {
    final row = await _client
        .from('customer_reports')
        .select(_select)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : CustomerReport.fromMap(row);
  }

  /// Re-reads the complaint whenever its row changes, so a resolve or reopen
  /// on one side reaches the other while the thread is open.
  Stream<CustomerReport?> watchReport(String id) {
    final controller = StreamController<CustomerReport?>();
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final report = await fetchReport(id);
        if (!controller.isClosed) controller.add(report);
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      }
    }

    controller.onListen = () {
      refresh();
      channel = _client
          .channel('report:$id:${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'customer_reports',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: id,
            ),
            callback: (_) => refresh(),
          )
          .subscribe();
    };
    controller.onCancel = () async {
      if (channel != null) await _client.removeChannel(channel!);
      await controller.close();
    };
    return controller.stream;
  }

  /// Live thread, oldest first.
  Stream<List<ReportMessage>> messagesStream(String reportId) => _client
      .from('customer_report_messages')
      .stream(primaryKey: ['id'])
      .eq('report_id', reportId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(ReportMessage.fromMap).toList());

  /// Posts to the thread. The server decides which side the message is from;
  /// only an admin may [resolve] in the same call.
  Future<void> sendMessage({
    required String reportId,
    required String message,
    bool resolve = false,
  }) => _client.rpc(
    'report_send_message',
    params: {
      'p_report_id': reportId,
      'p_message': message,
      'p_resolve': resolve,
    },
  );

  /// Admin: reopen or close without writing anything.
  Future<void> setStatus(String reportId, String status) => _client
      .from('customer_reports')
      .update({
        'status': status,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      })
      .eq('id', reportId);

  /// Customer opened the thread: clears the "new reply" dot.
  Future<void> markRead(String reportId) =>
      _client.rpc('mark_report_read', params: {'p_report_id': reportId});

  /// Complaints with a support reply the customer has not opened yet.
  Stream<int> watchUnreadReplies() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return Stream.value(0);
    return liveCount(
      table: 'customer_reports',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      count: () => _client
          .from('customer_reports')
          .count()
          .eq('user_id', userId)
          .eq('has_unread_reply', true),
    );
  }

  /// Any change to a complaint the caller can see — the list's signal to
  /// re-fetch.
  Stream<void> watchAll() {
    final controller = StreamController<void>();
    RealtimeChannel? channel;
    controller.onListen = () {
      channel = _client
          .channel('reports:${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'customer_reports',
            callback: (_) {
              if (!controller.isClosed) controller.add(null);
            },
          )
          .subscribe();
    };
    controller.onCancel = () async {
      if (channel != null) await _client.removeChannel(channel!);
      await controller.close();
    };
    return controller.stream;
  }
}
