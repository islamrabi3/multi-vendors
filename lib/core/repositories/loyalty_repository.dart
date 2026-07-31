import 'package:supabase_flutter/supabase_flutter.dart';

class LoyaltyRepository {
  final SupabaseClient _client;
  LoyaltyRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<int> getPoints() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    final res = await _client
        .from('loyalty_points')
        .select('points')
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) return 0;
    return ((res['points'] as num?) ?? 0).toInt();
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await _client
        .from('loyalty_history')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (res as List).cast<Map<String, dynamic>>();
  }

  Future<int> earnPoints(int points, String action) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0;

    final res = await _client.rpc('earn_loyalty_points', params: {
      'p_user_id': userId,
      'p_points': points,
      'p_action': action,
    });
    return (res as num).toInt();
  }
}
