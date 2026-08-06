import '../models/admin_role.dart';
import '../supabase_client.dart';

/// Management roles, staff assignment, and the audit trail.
///
/// Every write here goes through a security definer RPC rather than the table:
/// `admin_role_id` is the one column on a profile that must never be
/// self-served, or a restricted admin would clear their own role and become
/// unrestricted.
class AdminRolesRepository {
  Future<List<AdminRole>> fetchRoles() async {
    final data = await supabase.from('admin_roles').select().order('name');
    return (data as List)
        .map((e) => AdminRole.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// What the signed-in admin may do. `['*']` means unrestricted.
  ///
  /// Used only to hide controls; the server enforces the same rules on every
  /// call, so a stale or tampered copy of this changes nothing.
  Future<List<String>> myPermissions() async {
    final data = await supabase.rpc('my_permissions');
    return ((data as List?) ?? const []).cast<String>();
  }

  Future<AdminRole> createRole({
    required String name,
    String? nameAr,
    required List<String> permissions,
  }) async {
    final data = await supabase
        .from('admin_roles')
        .insert({
          'name': name.trim(),
          'name_ar': (nameAr?.trim().isEmpty ?? true) ? null : nameAr!.trim(),
          'permissions': permissions,
        })
        .select()
        .single();
    return AdminRole.fromMap(data);
  }

  Future<void> updateRole(
    String id, {
    String? name,
    String? nameAr,
    List<String>? permissions,
  }) => supabase
      .from('admin_roles')
      .update({
        if (name != null) 'name': name.trim(),
        if (nameAr != null)
          'name_ar': nameAr.trim().isEmpty ? null : nameAr.trim(),
        'permissions': ?permissions,
      })
      .eq('id', id);

  /// Refuses while anybody still holds the role — the column is
  /// `on delete set null`, so deleting it would quietly make them unrestricted.
  Future<void> deleteRole(String id) =>
      supabase.rpc('admin_delete_role', params: {'p_role_id': id});

  /// [roleId] null means unrestricted.
  Future<void> assignRole(String userId, String? roleId) => supabase.rpc(
    'admin_assign_role',
    params: {'p_user_id': userId, 'p_role_id': roleId},
  );

  /// Promotes an existing user to staff. Only an unrestricted admin may call
  /// it — creating admins is how a limited account would escalate itself.
  Future<void> grantStaff(String userId, {String? roleId}) => supabase.rpc(
    'admin_grant_staff',
    params: {'p_user_id': userId, 'p_role_id': roleId},
  );

  Future<List<AdminAuditEntry>> fetchAuditLog({
    int limit = 50,
    int offset = 0,
  }) async {
    final data = await supabase
        .from('admin_audit_log')
        .select('*, profiles!admin_audit_log_actor_id_fkey(full_name)')
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => AdminAuditEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// The staff list: every admin account, the role it holds, and the address
  /// it signs in with.
  ///
  /// Goes through an RPC because the email lives in `auth.users`, which no
  /// client may read — the screen was previously showing a phone number in the
  /// email slot for want of anywhere else to get one.
  Future<List<StaffMember>> fetchStaff() async {
    final data = await supabase.rpc('admin_staff_list') as List;
    return data.cast<Map<String, dynamic>>().map(StaffMember.fromMap).toList();
  }

  /// Finds an existing account to promote. Needs at least three characters —
  /// this reads `auth.users`, and must not double as a way to page through
  /// every address on the platform.
  Future<List<StaffCandidate>> searchUsers(String query) async {
    if (query.trim().length < 3) return const [];
    final data =
        await supabase.rpc(
              'admin_search_users',
              params: {'p_query': query.trim()},
            )
            as List;
    return data
        .cast<Map<String, dynamic>>()
        .map(StaffCandidate.fromMap)
        .toList();
  }

  /// Creates a brand-new login. Goes through an edge function because it needs
  /// the Auth admin API, which needs the service role key.
  Future<void> createStaff({
    required String email,
    required String password,
    required String fullName,
    String? roleId,
  }) async {
    final response = await supabase.functions.invoke(
      'create-staff',
      body: {
        'email': email.trim(),
        'password': password,
        'full_name': fullName.trim(),
        'role_id': roleId,
      },
    );
    final data = (response.data as Map?)?.cast<String, dynamic>() ?? const {};
    if (data['error'] != null) throw Exception(data['error']);
  }

  /// Takes somebody off the staff and puts back the role they actually had —
  /// vendor if they own a store, driver if they drive, customer otherwise.
  ///
  /// Returns which role was restored, so the console can say so. Demoting a
  /// store owner to `customer` would lock them out of their own store, since
  /// `is_vendor_owner()` reads the profile role.
  Future<String> revokeStaff(String userId) async {
    final result = await supabase.rpc(
      'admin_revoke_staff',
      params: {'p_user_id': userId},
    );
    // jsonb, not a bare text scalar: an unquoted string is not valid JSON and
    // the client threw decoding it, after the change had already committed.
    if (result is Map) {
      return (result['restored_role'] as String?) ?? 'customer';
    }
    return (result as String?) ?? 'customer';
  }
}

/// One member of staff.
class StaffMember {
  const StaffMember({
    required this.id,
    required this.name,
    this.email,
    this.roleId,
    this.isBlocked = false,
    this.ownsVendor = false,
    this.isDriver = false,
  });

  final String id;
  final String name;
  final String? email;

  /// Null means unrestricted — no role, full access.
  final String? roleId;
  final bool isBlocked;

  /// This account also trades on the platform. Admin rights then let it
  /// approve, price or promote itself — worth flagging in the list, and
  /// refused outright for new grants.
  final bool ownsVendor;
  final bool isDriver;

  bool get hasConflict => ownsVendor || isDriver;

  factory StaffMember.fromMap(Map<String, dynamic> map) => StaffMember(
    id: map['id'] as String,
    name: ((map['full_name'] as String?) ?? '').trim(),
    email: map['email'] as String?,
    roleId: map['admin_role_id'] as String?,
    isBlocked: (map['is_blocked'] as bool?) ?? false,
    ownsVendor: (map['owns_vendor'] as bool?) ?? false,
    isDriver: (map['is_driver'] as bool?) ?? false,
  );
}

/// An existing account that could be promoted to staff.
class StaffCandidate {
  const StaffCandidate({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.phone,
  });

  final String id;
  final String name;

  /// What they are today — `customer`, `vendor`, `driver` or already `admin`.
  final String role;
  final String? email;
  final String? phone;

  bool get isAlreadyStaff => role == 'admin';

  /// A store owner or driver cannot be made an admin: they would be able to
  /// approve and price their own store, or approve their own driver account.
  /// The server refuses it; this is so the row can say why before it is tried.
  bool get isConflicted => role == 'vendor' || role == 'driver';

  factory StaffCandidate.fromMap(Map<String, dynamic> map) => StaffCandidate(
    id: map['id'] as String,
    name: ((map['full_name'] as String?) ?? '').trim(),
    role: (map['role'] as String?) ?? 'customer',
    email: map['email'] as String?,
    phone: map['phone'] as String?,
  );
}
