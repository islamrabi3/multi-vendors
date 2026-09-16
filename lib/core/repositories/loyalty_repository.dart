import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/paging.dart';

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

  /// One page of the caller's points history, newest first. Pass the last
  /// row shown as [before] for the next page.
  Future<List<Map<String, dynamic>>> getHistory({
    FeedCursor? before,
    int limit = kPageSize,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await _client
        .from('loyalty_history')
        .select()
        .eq('user_id', userId)
        .olderThan(before)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);

    return (res as List).cast<Map<String, dynamic>>();
  }

  /// The exchange rate and the floor, both set by the platform.
  Future<({int pointsPerUnit, int minRedeem})> redeemConfig() async {
    final data = await _client.rpc('loyalty_redeem_config');
    final map = (data as Map).cast<String, dynamic>();
    return (
      pointsPerUnit: ((map['points_per_unit'] as num?) ?? 100).toInt(),
      minRedeem: ((map['min_redeem'] as num?) ?? 1000).toInt(),
    );
  }

  /// Turns points into wallet credit. The server owns the rate and refuses
  /// anything under the floor, so the app can only ask.
  Future<double> redeem(int points) async {
    final data = await _client.rpc(
      'redeem_loyalty_points',
      params: {'p_points': points},
    );
    final map = (data as Map).cast<String, dynamic>();
    return ((map['credit'] as num?) ?? 0).toDouble();
  }

  // Deliberately no earnPoints(). Points are awarded by the
  // trg_award_order_loyalty trigger when an order reaches `delivered`, and the
  // earn_loyalty_points RPC is no longer granted to clients: it named both the
  // account and the amount, so any signed-in user could credit themselves any
  // balance.
}
