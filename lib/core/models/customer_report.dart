import 'package:equatable/equatable.dart';

/// A customer's complaint about an order or a store, followed up as a thread
/// of [ReportMessage]s. The original [description] stays on the complaint.
class CustomerReport extends Equatable {
  const CustomerReport({
    required this.id,
    required this.userId,
    required this.subject,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.orderId,
    this.orderNumber,
    this.vendorId,
    this.vendorName,
    this.customerName,
    this.lastMessageAt,
    this.lastMessageFromAdmin = false,
    this.hasUnreadReply = false,
  });

  final String id;
  final String userId;
  final String subject;
  final String description;

  /// `pending` or `resolved`.
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? orderId;
  final String? orderNumber;
  final String? vendorId;
  final String? vendorName;
  final String? customerName;
  final DateTime? lastMessageAt;
  final bool lastMessageFromAdmin;

  /// Support wrote something the customer has not opened yet.
  final bool hasUnreadReply;

  bool get isResolved => status == 'resolved';

  /// The customer spoke last on an open complaint — the admin's turn.
  bool get awaitsSupport =>
      !isResolved && lastMessageAt != null && !lastMessageFromAdmin;

  DateTime get lastActivity => lastMessageAt ?? updatedAt;

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  factory CustomerReport.fromMap(Map<String, dynamic> map) => CustomerReport(
    id: map['id'] as String,
    userId: map['user_id'] as String,
    subject: (map['subject'] as String?) ?? '',
    description: (map['description'] as String?) ?? '',
    status: (map['status'] as String?) ?? 'pending',
    createdAt: _date(map['created_at']) ?? DateTime.now(),
    updatedAt: _date(map['updated_at']) ?? DateTime.now(),
    orderId: map['order_id'] as String?,
    orderNumber: (map['orders'] as Map?)?['order_number']?.toString(),
    vendorId: map['vendor_id'] as String?,
    vendorName: (map['vendors'] as Map?)?['name'] as String?,
    customerName: (map['profiles'] as Map?)?['full_name'] as String?,
    lastMessageAt: _date(map['last_message_at']),
    lastMessageFromAdmin: (map['last_message_from_admin'] as bool?) ?? false,
    hasUnreadReply: (map['has_unread_reply'] as bool?) ?? false,
  );

  @override
  List<Object?> get props => [
    id,
    status,
    updatedAt,
    lastMessageAt,
    lastMessageFromAdmin,
    hasUnreadReply,
    orderNumber,
    vendorName,
    customerName,
  ];
}

class ReportMessage extends Equatable {
  const ReportMessage({
    required this.id,
    required this.reportId,
    required this.isFromAdmin,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String reportId;
  final bool isFromAdmin;
  final String message;
  final DateTime createdAt;

  factory ReportMessage.fromMap(Map<String, dynamic> map) => ReportMessage(
    id: map['id'] as String,
    reportId: map['report_id'] as String,
    isFromAdmin: (map['is_from_admin'] as bool?) ?? false,
    message: (map['message'] as String?) ?? '',
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
  );

  @override
  List<Object?> get props => [id, message];
}
