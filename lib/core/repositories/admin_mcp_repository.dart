import '../config/app_config.dart';
import '../supabase_client.dart';

/// A key that lets Claude work the console as the admin who made it.
///
/// The key itself is not part of this: the server keeps only its hash, and
/// the one time the key is visible is the moment it is created.
class AdminMcpKey {
  const AdminMcpKey({
    required this.id,
    required this.adminId,
    required this.name,
    required this.prefix,
    required this.createdAt,
    this.ownerName,
    this.expiresAt,
    this.lastUsedAt,
    this.revokedAt,
  });

  final String id;
  final String adminId;
  final String name;

  /// The first characters of the key, enough to tell one from another.
  final String prefix;
  final String? ownerName;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final DateTime? lastUsedAt;
  final DateTime? revokedAt;

  bool get isRevoked => revokedAt != null;
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isLive => !isRevoked && !isExpired;

  factory AdminMcpKey.fromMap(Map<String, dynamic> map) => AdminMcpKey(
    id: map['id'] as String,
    adminId: map['admin_id'] as String,
    name: map['name'] as String,
    prefix: map['token_prefix'] as String,
    ownerName:
        (map['profiles'] as Map<String, dynamic>?)?['full_name'] as String?,
    createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    expiresAt: _date(map['expires_at']),
    lastUsedAt: _date(map['last_used_at']),
    revokedAt: _date(map['revoked_at']),
  );

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();
}

class AdminMcpRepository {
  /// Where Claude is pointed at: the `admin-mcp` Edge Function.
  static String get endpoint =>
      '${AppConfig.supabaseUrl}/functions/v1/admin-mcp';

  /// The command that connects Claude Code using [key].
  static String connectCommand(String key) =>
      'claude mcp add --transport http kitchen-in-admin $endpoint '
      '--header "Authorization: Bearer $key"';

  /// The caller's keys — and everybody's, for whoever manages staff. Which
  /// of the two is the row policy's decision, not this query's.
  Future<List<AdminMcpKey>> fetchKeys() async {
    // The hash column is not readable by clients, so the columns are named.
    final rows = await supabase
        .from('admin_mcp_tokens')
        .select(
          'id, admin_id, name, token_prefix, expires_at, last_used_at, '
          'revoked_at, created_at, profiles(full_name)',
        )
        .order('created_at', ascending: false);
    return [
      for (final row in rows as List)
        AdminMcpKey.fromMap(row as Map<String, dynamic>),
    ];
  }

  /// Makes a key and returns it. This is the only time it can be read.
  Future<String> createKey({required String name, required int days}) async {
    final result = await supabase.rpc(
      'admin_mcp_create_token',
      params: {'p_name': name, 'p_expires_in_days': days},
    );
    return (result as Map<String, dynamic>)['token'] as String;
  }

  Future<void> revokeKey(String id) =>
      supabase.rpc('admin_mcp_revoke_token', params: {'p_token_id': id});
}
