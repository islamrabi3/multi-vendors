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

  // Deliberately no earnPoints(). Points are awarded by the
  // trg_award_order_loyalty trigger when an order reaches `delivered`, and the
  // earn_loyalty_points RPC is no longer granted to clients: it named both the
  // account and the amount, so any signed-in user could credit themselves any
  // balance.
}
