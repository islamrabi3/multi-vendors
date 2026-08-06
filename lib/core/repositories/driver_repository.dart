import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Driver presence and live GPS sharing.
///
/// Per-second tracking goes over a Realtime broadcast channel
/// (`order-tracking:{orderId}`) so the database is not hammered with writes;
/// `drivers.current_lat/lng` is refreshed on a slow cadence for dispatch use.
/// Where a driver stands with the platform, from their own side.
class DriverVerification {
  const DriverVerification({
    required this.approvalStatus,
    required this.onFile,
    this.rejectionReason,
  });

  final String approvalStatus;
  final String? rejectionReason;

  /// The document columns that already hold a path.
  final Set<String> onFile;

  static const columns = [
    'id_card_url',
    'id_card_back_url',
    'license_url',
    'license_back_url',
  ];

  bool has(String column) => onFile.contains(column);

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'active';
  bool get isRejected => approvalStatus == 'rejected';
  bool get isSuspended => approvalStatus == 'suspended';

  bool get isComplete => columns.every(onFile.contains);

  /// Nothing to do until an admin looks: everything is in and under review.
  bool get isAwaitingReview => isComplete && isPending;

  /// The driver has to act — documents missing, or a rejection to answer.
  bool get needsAttention => !isComplete || isRejected;

  factory DriverVerification.fromMap(Map<String, dynamic> map) =>
      DriverVerification(
        approvalStatus: (map['approval_status'] as String?) ?? 'pending',
        rejectionReason: map['rejection_reason'] as String?,
        onFile: {
          for (final column in columns)
            if ((map[column] as String?)?.isNotEmpty ?? false) column,
        },
      );
}

class DriverRepository {
  /// The applicant's own verification state: where they are in review, and
  /// which of the four documents are on file.
  ///
  /// Read from the driver's own row, so it reflects an admin's decision the
  /// next time the screen is opened — including a rejection reason, which is
  /// the only way the driver learns what to fix.
  Future<DriverVerification> fetchVerification() async {
    final data = await supabase
        .from('drivers')
        .select(
          'approval_status, rejection_reason,'
          ' id_card_url, id_card_back_url, license_url, license_back_url',
        )
        .eq('id', supabase.auth.currentUser!.id)
        .maybeSingle();
    return DriverVerification.fromMap(data ?? const {});
  }

  /// The same state, live.
  ///
  /// An admin's decision lands on the driver's screen as it is made, instead
  /// of the driver having to leave and reopen the page to find out they were
  /// approved. Uploading a document is also a change to this row, so the
  /// screen reflects a submission without being told to reload.
  Stream<DriverVerification> watchVerification() => supabase
      .from('drivers')
      .stream(primaryKey: ['id'])
      .eq('id', supabase.auth.currentUser!.id)
      .map(
        (rows) => rows.isEmpty
            ? const DriverVerification(approvalStatus: 'pending', onFile: {})
            : DriverVerification.fromMap(rows.first),
      );

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
