import 'package:flutter/foundation.dart';

import '../errors/app_failure.dart';
import '../models/banner_item.dart';
import '../supabase_client.dart';

/// Bumped whenever an ad is created, edited or removed.
///
/// Ad surfaces fetch once when they mount, which is right — a slot must not
/// re-query on every rebuild. The cost is that a slot already on screen keeps
/// showing an ad that has just been deleted until something remounts it. This
/// notifier closes that gap for the device that made the change, which is the
/// one that will look for it immediately.
///
/// It says nothing to other devices: their slots refresh on their next fetch.
final adsRevision = ValueNotifier<int>(0);

/// Ad slots — creation, scheduling and reporting.
///
/// Backed by the `banners` table, which every existing banner already lives
/// in. Writes are gated server-side by the banners_insert/update/delete
/// policies, which require the `ads.manage` permission rather than merely
/// being an admin.
class OffersRepository {
  /// All offers including inactive — admins only (RLS).
  Future<List<BannerItem>> fetchAll() async {
    final data = await supabase
        .from('banners')
        .select()
        .order('sort_order', ascending: true);
    return (data as List).map((e) => BannerItem.fromMap(e)).toList();
  }

  Future<void> create({
    required String imageUrl,
    required BannerType type,
    AdPlacement placement = AdPlacement.homeCarousel,
    String? title,
    String? subtitle,
    String? code,
    String? vendorId,
    String? videoUrl,
    String? linkUrl,
    String? advertiser,
    String audience = 'all',
    DateTime? startsAt,
    DateTime? endsAt,
    int sortOrder = 0,
  }) async {
    await supabase.from('banners').insert({
      'image_url': imageUrl,
      'banner_type': type.name,
      'placement': placement.wire,
      // A video ad still carries an image: it is the poster, and the fallback
      // wherever autoplay is refused.
      'media_type': (videoUrl?.isNotEmpty ?? false) ? 'video' : 'image',
      'video_url': ?_clean(videoUrl),
      'link_url': ?_clean(linkUrl),
      'advertiser': ?_clean(advertiser),
      'audience': audience,
      'starts_at': startsAt?.toUtc().toIso8601String(),
      'ends_at': endsAt?.toUtc().toIso8601String(),
      'title': ?_clean(title),
      'subtitle': ?_clean(subtitle),
      'code': ?_clean(code),
      'vendor_id': ?_clean(vendorId),
      'sort_order': sortOrder,
      'is_active': true,
    });
    adsRevision.value++;
  }

  /// What the customer app renders for one surface.
  ///
  /// The schedule and audience rules are applied server-side so an ad cannot
  /// run early or late because a phone's clock is wrong.
  Future<List<BannerItem>> activeAds(
    AdPlacement placement, {
    bool isNewCustomer = false,
  }) async {
    final data = await supabase.rpc(
      'active_ads',
      params: {
        'p_placement': placement.wire,
        'p_is_new_customer': isNewCustomer,
      },
    );
    return (data as List)
        .map((e) => BannerItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Whether the signed-in customer has ever had an order served, for the
  /// new-customer audience.
  Future<bool> isNewCustomer() async {
    final data = await supabase.rpc('is_new_customer');
    return (data as bool?) ?? false;
  }

  /// Counted server-side because the numbers are billable: a client that can
  /// write them directly can inflate them. Fire and forget — an ad that fails
  /// to record a view must still render.
  Future<void> recordEvent(String adId, {required bool click}) async {
    try {
      await supabase.rpc(
        'record_ad_event',
        params: {'p_ad_id': adId, 'p_event': click ? 'click' : 'impression'},
      );
    } catch (_) {
      // Reporting is not worth interrupting a customer for.
    }
  }

  Future<void> update(String id, Map<String, dynamic> values) async {
    final rows = await supabase
        .from('banners')
        .update(values)
        .eq('id', id)
        .select('id');
    _requireWrite(rows);
    adsRevision.value++;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> setActive(String id, bool active) async {
    final rows = await supabase
        .from('banners')
        .update({'is_active': active})
        .eq('id', id)
        .select('id');
    _requireWrite(rows);
    adsRevision.value++;
  }

  Future<void> delete(String id) async {
    final rows = await supabase
        .from('banners')
        .delete()
        .eq('id', id)
        .select('id');
    _requireWrite(rows);
    adsRevision.value++;
  }

  /// Turns a write that changed nothing into an error.
  ///
  /// PostgREST reports an RLS refusal on update and delete as success with
  /// zero rows, not as a 403 — the row simply is not visible to the policy. A
  /// caller that only awaits the future therefore shows "deleted" over an ad
  /// that is still there. Asking for the affected rows back is what makes the
  /// difference observable.
  static void _requireWrite(dynamic rows) {
    if (rows is List && rows.isEmpty) {
      throw const AppFailure(kind: FailureKind.permission, code: 'NO_ROWS');
    }
  }
}
