/// One order's chat, as the Messages inbox lists it.
class ChatConversation {
  const ChatConversation({
    required this.orderId,
    required this.orderNumber,
    required this.orderStatus,
    required this.lastAt,
    required this.lastSenderRole,
    required this.lastFromMe,
    required this.unread,
    this.vendorName,
    this.vendorLogoUrl,
    this.lastMessage,
    this.lastHasAttachment = false,
    this.lastSenderName,
  });

  final String orderId;
  final String orderNumber;
  final String orderStatus;
  final String? vendorName;
  final String? vendorLogoUrl;
  final String? lastMessage;
  final bool lastHasAttachment;
  final DateTime lastAt;
  final String? lastSenderName;

  /// `customer` | `driver` | `vendor` | `support`.
  final String lastSenderRole;
  final bool lastFromMe;
  final int unread;

  factory ChatConversation.fromMap(Map<String, dynamic> map) =>
      ChatConversation(
        orderId: map['order_id'] as String,
        orderNumber: (map['order_number'] as String?) ?? '',
        orderStatus: (map['order_status'] as String?) ?? '',
        vendorName: map['vendor_name'] as String?,
        vendorLogoUrl: map['vendor_logo_url'] as String?,
        lastMessage: map['last_message'] as String?,
        lastHasAttachment: (map['last_has_attachment'] as bool?) ?? false,
        lastAt: DateTime.parse(map['last_at'] as String).toLocal(),
        lastSenderName: map['last_sender_name'] as String?,
        lastSenderRole: (map['last_sender_role'] as String?) ?? 'customer',
        lastFromMe: (map['last_from_me'] as bool?) ?? false,
        unread: ((map['unread'] as num?) ?? 0).toInt(),
      );
}
