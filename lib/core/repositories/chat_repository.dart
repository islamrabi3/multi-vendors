import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../services/attachment_service.dart';

class ChatRepository {
  final SupabaseClient _client;
  ChatRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// The two conversations an order can have: with the store, and with the
  /// rider. The customer is in both; the store and the rider see only theirs.
  static const vendorThread = 'vendor';
  static const driverThread = 'driver';

  Future<List<ChatMessage>> getMessages(
    String orderId, {
    String thread = vendorThread,
  }) async {
    final res = await _client
        .from('chat_messages')
        .select('*, profiles(full_name)')
        .eq('order_id', orderId)
        .eq('thread', thread)
        .order('created_at', ascending: true);

    return (res as List)
        .map((e) => ChatMessage.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Stream<List<ChatMessage>> streamMessages(
    String orderId, {
    String thread = vendorThread,
  }) {
    // A stream takes one filter, so the thread is applied here — the row is
    // in the payload either way.
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: true)
        .map(
          (list) => list
              .map(ChatMessage.fromMap)
              .where((m) => m.thread == thread)
              .toList(),
        );
  }

  /// Unread messages from others in one order ([orderId]) or across every
  /// conversation this user is part of (null). Recounted when a message
  /// arrives or when this user reads a thread on any device.
  Stream<int> watchUnread([String? orderId, String? thread]) {
    final me = currentUserId;
    if (me == null) return Stream.value(0);
    final controller = StreamController<int>();
    RealtimeChannel? channel;
    Timer? debounce;
    var active = true;

    Future<void> refresh() async {
      try {
        final value = await _client.rpc(
          'my_unread_chat_count',
          params: {'p_order_id': orderId, 'p_thread': thread},
        );
        if (active) controller.add(((value as num?) ?? 0).toInt());
      } catch (_) {}
    }

    void schedule() {
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 400), refresh);
    }

    controller.onListen = () {
      refresh();
      channel = _client
          .channel('chat-unread:${orderId ?? 'all'}:${_seq++}')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: orderId == null
                ? null
                : PostgresChangeFilter(
                    type: PostgresChangeFilterType.eq,
                    column: 'order_id',
                    value: orderId,
                  ),
            callback: (_) => schedule(),
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'chat_reads',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: me,
            ),
            callback: (_) => schedule(),
          )
          .subscribe((status, _) {
            if (status == RealtimeSubscribeStatus.subscribed) refresh();
          });
    };
    controller.onCancel = () async {
      active = false;
      debounce?.cancel();
      final open = channel;
      if (open != null) await _client.removeChannel(open);
      await controller.close();
    };
    return controller.stream;
  }

  static var _seq = 0;

  /// Opening the thread is reading it — for this user only.
  Future<void> markRead(String orderId, {String thread = vendorThread}) async {
    try {
      await _client.rpc(
        'mark_order_chat_read',
        params: {'p_order_id': orderId, 'p_thread': thread},
      );
    } catch (_) {
      // A badge that stays one message too long is not worth an error.
    }
  }

  /// Removes a conversation from this user's own list until someone writes
  /// in it again. Also marks it read.
  Future<void> hideConversation(
    String orderId, {
    String thread = vendorThread,
  }) => _client.rpc(
    'hide_order_conversation',
    params: {'p_order_id': orderId, 'p_thread': thread},
  );

  /// Every order conversation this user is part of, newest first.
  Future<List<ChatConversation>> fetchConversations({int limit = 50}) async {
    final rows = await _client.rpc(
      'my_order_conversations',
      params: {'p_limit': limit},
    );
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(ChatConversation.fromMap)
        .toList();
  }

  Future<void> sendMessage({
    required String orderId,
    required String message,
    String thread = vendorThread,
    String? imageUrl,
    ChatAttachment? attachment,
  }) async {
    final senderId = _client.auth.currentUser?.id;
    if (senderId == null) return;

    // The recipient's push is sent by the notify_chat_message trigger. Doing
    // it here lost the notification whenever the sender backgrounded the app
    // mid-request, and the sender's name and order number had to be read by a
    // client that RLS does not let see them.
    await _client.from('chat_messages').insert({
      'order_id': orderId,
      'sender_id': senderId,
      'thread': thread,
      'message': message,
      'image_url': imageUrl,
      if (attachment != null) ...{
        'attachment_url': attachment.path,
        'attachment_name': attachment.name,
        'attachment_type': attachment.type,
      },
    });
  }
}
