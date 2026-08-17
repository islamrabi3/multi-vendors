import 'package:equatable/equatable.dart';

/// Everything an admin can be given, grouped the way the console is.
///
/// Deliberately a plain list of string keys rather than an enum: the server
/// stores whatever is in `admin_roles.permissions`, so a new screen can add a
/// permission without a schema migration. This list is only what the role
/// editor offers.
class AdminPermission {
  const AdminPermission(this.key, this.group);

  final String key;

  /// Section heading in the editor.
  final String group;

  /// `*` is what an unrestricted admin holds. It is never offered in the
  /// editor — an unrestricted admin is one with no role at all.
  static const wildcard = '*';

  static const all = <AdminPermission>[
    AdminPermission('orders.view', 'orders'),
    AdminPermission('orders.cancel', 'orders'),
    AdminPermission('orders.assign', 'orders'),
    AdminPermission('vendors.view', 'vendors'),
    AdminPermission('vendors.approve', 'vendors'),
    AdminPermission('vendors.promote', 'vendors'),
    AdminPermission('vendors.terms', 'vendors'),
    AdminPermission('catalog.manage', 'catalogue'),
    AdminPermission('content.manage', 'catalogue'),
    AdminPermission('promos.manage', 'catalogue'),
    AdminPermission('ads.manage', 'catalogue'),
    AdminPermission('drivers.view', 'drivers'),
    AdminPermission('drivers.approve', 'drivers'),
    AdminPermission('users.block', 'users'),
    AdminPermission('users.delete', 'users'),
    AdminPermission('staff.manage', 'users'),
    AdminPermission('support.handle', 'support'),
    AdminPermission('notifications.send', 'support'),
    AdminPermission('reports.view', 'finance'),
    AdminPermission('payments.refund', 'finance'),
    AdminPermission('wallets.adjust', 'finance'),
    // Both were already enforced server-side and used by the Settlements and
    // Deposits nav items, but neither was offered here — so a new role could
    // not be given access to the payout screens at all, and only an
    // unrestricted admin could reach them.
    AdminPermission('finance.settle', 'finance'),
    AdminPermission('finance.adjust', 'finance'),
  ];

  static List<String> get groups {
    final seen = <String>[];
    for (final permission in all) {
      if (!seen.contains(permission.group)) seen.add(permission.group);
    }
    return seen;
  }
}

/// A named set of permissions an admin account can be put into.
class AdminRole extends Equatable {
  const AdminRole({
    required this.id,
    required this.name,
    required this.permissions,
    this.nameAr,
  });

  final String id;
  final String name;
  final String? nameAr;
  final List<String> permissions;

  String displayName(String languageCode) =>
      languageCode == 'ar' && (nameAr?.trim().isNotEmpty ?? false)
      ? nameAr!.trim()
      : name;

  bool has(String key) =>
      permissions.contains(key) ||
      permissions.contains(AdminPermission.wildcard);

  factory AdminRole.fromMap(Map<String, dynamic> map) => AdminRole(
    id: map['id'] as String,
    name: map['name'] as String,
    nameAr: map['name_ar'] as String?,
    permissions: ((map['permissions'] as List?) ?? const []).cast<String>(),
  );

  @override
  List<Object?> get props => [id, name, nameAr, permissions];
}

/// One line of the audit trail.
class AdminAuditEntry extends Equatable {
  const AdminAuditEntry({
    required this.id,
    required this.action,
    required this.createdAt,
    this.actorName,
    this.targetType,
    this.targetId,
    this.detail = const {},
  });

  final String id;

  /// Dotted verb — `user.block`, `order.refund`, `staff.assign_role`.
  final String action;
  final DateTime createdAt;
  final String? actorName;
  final String? targetType;
  final String? targetId;
  final Map<String, dynamic> detail;

  factory AdminAuditEntry.fromMap(Map<String, dynamic> map) {
    final actor = map['profiles'];
    return AdminAuditEntry(
      id: map['id'] as String,
      action: map['action'] as String,
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      actorName: actor is Map ? actor['full_name'] as String? : null,
      targetType: map['target_type'] as String?,
      targetId: map['target_id'] as String?,
      detail: (map['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  @override
  List<Object?> get props => [id, action, createdAt, actorName, targetId];
}
