import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_message.dart';
import '../services/attachment_service.dart';

class ChatRepository {
  final SupabaseClient _client;
  ChatRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<List<ChatMessage>> getMessages(String orderId) async {
    final res = await _client
        .from('chat_messages')
        .select('*, profiles(full_name)')
        .eq('order_id', orderId)
        .order('created_at', ascending: true);

    return (res as List)
        .map((e) => ChatMessage.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Stream<List<ChatMessage>> streamMessages(String orderId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('order_id', orderId)
        .order('created_at', ascending: true)
        .map((list) => list
            .map((e) => ChatMessage.fromMap(e))
            .toList());
  }

  Future<void> sendMessage({
    required String orderId,
    required String message,
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
