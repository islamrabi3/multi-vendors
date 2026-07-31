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
  });

  final String id;
  final String fullName;
  final UserRole role;
  final String? phone;
  final String? avatarUrl;

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
      );

  @override
  List<Object?> get props =>
      [id, fullName, role, phone, avatarUrl, roleConfirmed];
}
