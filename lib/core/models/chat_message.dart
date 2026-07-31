import 'package:equatable/equatable.dart';

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.id,
    required this.orderId,
    required this.senderId,
    required this.message,
    required this.createdAt,
    this.imageUrl,
    this.isRead = false,
    this.senderName,
  });

  final String id;
  final String orderId;
  final String senderId;
  final String message;
  final String? imageUrl;
  final bool isRead;
  final DateTime createdAt;
  final String? senderName;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    final sender = map['profiles'];
    return ChatMessage(
      id: map['id'] as String,
      orderId: map['order_id'] as String,
      senderId: map['sender_id'] as String,
      message: map['message'] as String,
      imageUrl: map['image_url'] as String?,
      isRead: (map['is_read'] as bool?) ?? false,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      senderName: sender is Map ? sender['full_name'] as String? : null,
    );
  }

  @override
  List<Object?> get props => [id, orderId, senderId, message, createdAt, isRead];
}
