import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../supabase_client.dart';

/// One person who works in a store without owning it.
class VendorStaffMember {
  const VendorStaffMember({
    required this.userId,
    required this.name,
    required this.permissions,
    this.email,
  });

  final String userId;
  final String name;
  final String? email;
  final List<String> permissions;

  bool can(String key) => permissions.contains(key);

  factory VendorStaffMember.fromMap(Map<String, dynamic> map) =>
      VendorStaffMember(
        userId: map['user_id'] as String,
        name:
            (map['profiles'] as Map?)?['full_name'] as String? ??
            (map['full_name'] as String?) ??
            '',
        permissions: ((map['permissions'] as List?) ?? const [])
            .map((e) => '$e')
            .toList(),
      );
}

/// The store's own staff list: who works here and what they may do.
///
/// Every write goes through a security-definer RPC that checks the caller
/// owns the store, so a staff account cannot promote itself by calling these.
class VendorStaffRepository {
  /// Keys a store owner can grant. `finance` is deliberately not one of them:
  /// money stays with the owner.
  static const permissionKeys = ['orders', 'menu', 'reviews', 'settings'];

  Future<List<VendorStaffMember>> fetchStaff(String vendorId) async {
    final rows = await supabase
        .from('vendor_staff')
        .select('user_id, full_name, permissions, profiles(full_name)')
        .eq('vendor_id', vendorId)
        .order('created_at');
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(VendorStaffMember.fromMap)
        .toList();
  }

  /// Creates the login and attaches it to the caller's store in one call.
  Future<void> createStaff({
    required String email,
    required String password,
    required String fullName,
    required List<String> permissions,
  }) async {
    try {
      final response = await supabase.functions.invoke(
        'vendor-create-staff',
        body: {
          'email': email.trim(),
          'password': password,
          'full_name': fullName.trim(),
          'permissions': permissions,
        },
      );
      final data = (response.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['error'] != null) throw Exception(data['error']);
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      throw Exception(code ?? 'CREATE_FAILED');
    }
  }

  Future<void> setPermissions(String userId, List<String> permissions) =>
      supabase.rpc(
        'vendor_set_staff_permissions',
        params: {'p_user_id': userId, 'p_permissions': permissions},
      );

  /// Takes the account out of the store. The login survives as a customer
  /// account, so nobody is left with a sign-in that opens nothing.
  Future<void> removeStaff(String userId) =>
      supabase.rpc('vendor_remove_staff', params: {'p_user_id': userId});
}
