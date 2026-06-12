import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Driver presence and live GPS sharing.
///
/// Per-second tracking goes over a Realtime broadcast channel
/// (`order-tracking:{orderId}`) so the database is not hammered with writes;
/// `drivers.current_lat/lng` is refreshed on a slow cadence for dispatch use.
class DriverRepository {
  Future<bool> fetchIsOnline() async {
    final data = await supabase
        .from('drivers')
        .select('is_online')
        .eq('id', supabase.auth.currentUser!.id)
        .maybeSingle();
    return (data?['is_online'] as bool?) ?? false;
  }

  Future<void> setOnline(bool online) => supabase
      .from('drivers')
      .update({'is_online': online}).eq('id', supabase.auth.currentUser!.id);

  Future<void> updateStoredLocation(double lat, double lng) =>
      supabase.from('drivers').update({
        'current_lat': lat,
        'current_lng': lng,
        'location_updated_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', supabase.auth.currentUser!.id);

  RealtimeChannel trackingChannel(String orderId) =>
      supabase.channel('order-tracking:$orderId');

  Future<void> broadcastLocation(
    RealtimeChannel channel,
    double lat,
    double lng,
  ) =>
      channel.sendBroadcastMessage(
        event: 'location',
        payload: {'lat': lat, 'lng': lng},
      );
}
