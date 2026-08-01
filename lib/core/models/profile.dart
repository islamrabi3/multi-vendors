import 'package:equatable/equatable.dart';

enum UserRole {
  customer,
  vendor,
  driver,
  admin;

  static UserRole fromName(String? name) => UserRole.values.firstWhere(
        (r) => r.name == name,
        orElse: () => UserRole.customer,
      );
}

class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.phone,
    this.avatarUrl,
    this.roleConfirmed = true,
    this.isBlocked = false,
    this.blockedReason,
    this.isClosed = false,
  });

  final String id;
  final String fullName;
  final UserRole role;
  final String? phone;
  final String? avatarUrl;

  /// Suspended by an admin. The account still exists and can be restored.
  final bool isBlocked;
  final String? blockedReason;

  /// Closed for good — by the user or by an admin. The row survives so past
  /// orders still resolve a customer, but the account cannot be used.
  final bool isClosed;

  /// Either state means this session must not be allowed to do anything.
  bool get isLockedOut => isBlocked || isClosed;

  /// False while a social sign-up has not answered the role picker yet. Google
  /// and Apple carry no role, so those accounts land on `customer` by default
  /// and must be asked before they are let into the app.
  final bool roleConfirmed;

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        fullName: (map['full_name'] as String?) ?? '',
        role: UserRole.fromName(map['role'] as String?),
        phone: map['phone'] as String?,
        avatarUrl: map['avatar_url'] as String?,
        roleConfirmed: (map['role_confirmed'] as bool?) ?? true,
        isBlocked: (map['is_blocked'] as bool?) ?? false,
        blockedReason: map['blocked_reason'] as String?,
        isClosed: map['deleted_at'] != null,
      );

  @override
  List<Object?> get props => [
        id,
        fullName,
        role,
        phone,
        avatarUrl,
        roleConfirmed,
        isBlocked,
        blockedReason,
        isClosed,
      ];
}
