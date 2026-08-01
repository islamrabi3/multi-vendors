import 'package:equatable/equatable.dart';

/// One support conversation between a user and the platform.
///
/// Separate from the per-order chat: support has to exist when there is no
/// order to attach it to.
class SupportThread extends Equatable {
  const SupportThread({
    required this.id,
    required this.userId,
    required this.subject,
    required this.status,
    required this.lastMessageAt,
    this.userName,
    this.userRole,
  });

  final String id;
  final String userId;
  final String subject;

  /// `open` | `resolved`. Any user reply reopens the thread, so a resolved one
  /// cannot go stale while the customer is still talking.
  final String status;
  final DateTime lastMessageAt;

  /// Joined for the admin inbox only; null on the user's own side.
  final String? userName;
  final String? userRole;

  bool get isOpen => status == 'open';

  factory SupportThread.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'];
    return SupportThread(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      subject: (map['subject'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'open',
      lastMessageAt: DateTime.parse(map['last_message_at'] as String),
      userName: profile is Map
          ? ((profile['full_name'] as String?)?.trim().isNotEmpty == true
              ? profile['full_name'] as String
              : null)
          : null,
      userRole: profile is Map ? profile['role'] as String? : null,
    );
  }

  @override
  List<Object?> get props =>
      [id, userId, subject, status, lastMessageAt, userName, userRole];
}

class SupportMessage extends Equatable {
  const SupportMessage({
    required this.id,
    required this.threadId,
    required this.senderId,
    required this.isFromAdmin,
    required this.message,
    required this.createdAt,
    this.isAutomated = false,
    this.attachmentPath,
    this.attachmentName,
    this.attachmentType,
  });

  final String id;
  final String threadId;
  final String senderId;

  /// Denormalised on the row so bubble alignment needs no join per message.
  final bool isFromAdmin;

  /// A canned answer to a template, not an agent typing. Shown as such, so a
  /// customer is never left thinking a person already read their thread.
  final bool isAutomated;
  final String message;
  final DateTime createdAt;

  /// Object key in the `chat-attachments` bucket. The bucket is private, so
  /// this is a path to be signed at render, never a usable URL.
  final String? attachmentPath;
  final String? attachmentName;

  /// `image` | `file`, or null when the message is text only.
  final String? attachmentType;

  bool get hasAttachment => attachmentPath != null;
  bool get isImageAttachment => attachmentType == 'image';

  factory SupportMessage.fromMap(Map<String, dynamic> map) => SupportMessage(
        id: map['id'] as String,
        threadId: map['thread_id'] as String,
        senderId: map['sender_id'] as String,
        isFromAdmin: (map['is_from_admin'] as bool?) ?? false,
        isAutomated: (map['is_automated'] as bool?) ?? false,
        message: (map['message'] as String?) ?? '',
        createdAt: DateTime.parse(map['created_at'] as String),
        attachmentPath: map['attachment_url'] as String?,
        attachmentName: map['attachment_name'] as String?,
        attachmentType: map['attachment_type'] as String?,
      );

  @override
  List<Object?> get props => [
        id,
        threadId,
        senderId,
        isFromAdmin,
        isAutomated,
        message,
        createdAt,
        attachmentPath,
        attachmentName,
        attachmentType,
      ];
}

/// A one-tap reason a customer can open a support thread with.
///
/// The label and the canned answer both live on the server so support can
/// reword them without an app release, and both languages ship on the row so
/// the reply matches the language the customer is reading in.
class SupportTemplate extends Equatable {
  const SupportTemplate({
    required this.key,
    required this.labelEn,
    required this.labelAr,
    required this.hasReply,
  });

  final String key;
  final String labelEn;
  final String labelAr;

  /// False for the "something else" row, which posts no automatic answer and
  /// leaves the thread waiting for an agent.
  final bool hasReply;

  String label(String languageCode) =>
      languageCode == 'ar' && labelAr.trim().isNotEmpty ? labelAr : labelEn;

  factory SupportTemplate.fromMap(Map<String, dynamic> map) => SupportTemplate(
        key: map['key'] as String,
        labelEn: (map['label_en'] as String?) ?? '',
        labelAr: (map['label_ar'] as String?) ?? '',
        hasReply: map['reply_en'] != null || map['reply_ar'] != null,
      );

  @override
  List<Object?> get props => [key, labelEn, labelAr, hasReply];
}
