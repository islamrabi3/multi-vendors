import 'package:equatable/equatable.dart';

/// What tapping a home-carousel banner does.
enum BannerType { coupon, vendor, event }

/// Where an ad renders. An unknown value never renders at all, so adding one
/// to the database without a matching widget is harmless.
enum AdPlacement {
  homeCarousel('home_carousel'),
  homeInline('home_inline'),
  vendorTop('vendor_top'),
  cart('cart'),
  orderTracking('order_tracking'),

  /// Full screen, over everything, with its own close control.
  interstitial('interstitial');

  const AdPlacement(this.wire);

  final String wire;

  static AdPlacement fromWire(String? raw) => AdPlacement.values.firstWhere(
    (p) => p.wire == raw,
    orElse: () => AdPlacement.homeCarousel,
  );
}

/// A promotional slot, managed by admins and backed by the `banners` table.
///
/// Still called a banner in the database because every existing row is one;
/// what changed is that it now carries a placement, a schedule, an audience,
/// optional video, and the counters that make the space sellable.
class BannerItem extends Equatable {
  const BannerItem({
    required this.id,
    required this.imageUrl,
    this.type = BannerType.event,
    this.vendorId,
    this.title,
    this.subtitle,
    this.code,
    this.isActive = true,
    this.sortOrder = 0,
    this.placement = AdPlacement.homeCarousel,
    this.videoUrl,
    this.posterUrl,
    this.startsAt,
    this.endsAt,
    this.audience = 'all',
    this.advertiser,
    this.linkUrl,
    this.impressions = 0,
    this.clicks = 0,
    this.ctaLabel,
    this.dismissible = true,
    this.dismissAfterSeconds = 0,
    this.frequency = 'once',
    this.dismissals = 0,
  });

  final String id;
  final String imageUrl;
  final BannerType type;
  final String? vendorId;
  final String? title;
  final String? subtitle;
  final String? code;
  final bool isActive;
  final int sortOrder;

  final AdPlacement placement;

  /// Set for a video ad; [imageUrl] then holds the poster fallback.
  final String? videoUrl;
  final String? posterUrl;

  /// Null start = live now, null end = until switched off.
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// `all` | `new_customers` | `returning_customers`.
  final String audience;

  /// Who bought the slot, for the admin list.
  final String? advertiser;

  /// Where tapping goes when it is neither a coupon nor a store.
  final String? linkUrl;

  final int impressions;
  final int clicks;
  final int dismissals;

  /// Interstitials only. Null means the whole surface is the tap target and no
  /// button is drawn — right for artwork that carries its own call to action.
  final String? ctaLabel;

  /// A full-screen ad the user cannot leave is a trap, so this is true by
  /// default. False is for the rare notice that must be acknowledged.
  final bool dismissible;

  /// Seconds before the close control appears. Zero for an advert.
  final int dismissAfterSeconds;

  /// `once` | `daily` | `every_session`. Enforced on this side, because "has
  /// this person seen it" is per-install state.
  final String frequency;

  bool get isVideo => (videoUrl?.isNotEmpty ?? false);

  /// SVG artwork is rendered by a different widget from a raster image, and
  /// the URL is the only signal the database carries.
  bool get isSvg => imageUrl.toLowerCase().split('?').first.endsWith('.svg');

  /// Live right now, as the server would judge it. The server applies the
  /// same rule; this is only so the admin list can explain itself.
  bool get isLive {
    final now = DateTime.now();
    if (!isActive) return false;
    if (startsAt != null && startsAt!.isAfter(now)) return false;
    if (endsAt != null && !endsAt!.isAfter(now)) return false;
    return true;
  }

  bool get isScheduled => startsAt != null && startsAt!.isAfter(DateTime.now());
  bool get hasEnded => endsAt != null && !endsAt!.isAfter(DateTime.now());

  /// Clicks per impression. Zero impressions is zero rather than a division
  /// by zero — a brand-new ad has no rate, not an infinite one.
  double get clickRate => impressions == 0 ? 0 : clicks / impressions;

  static BannerType _typeFrom(String? raw) => switch (raw) {
    'coupon' => BannerType.coupon,
    'vendor' => BannerType.vendor,
    _ => BannerType.event,
  };

  factory BannerItem.fromMap(Map<String, dynamic> map) => BannerItem(
    id: map['id'] as String,
    imageUrl: map['image_url'] as String,
    type: _typeFrom(map['banner_type'] as String?),
    vendorId: map['vendor_id'] as String?,
    title: map['title'] as String?,
    subtitle: map['subtitle'] as String?,
    code: map['code'] as String?,
    isActive: map['is_active'] as bool? ?? true,
    sortOrder: map['sort_order'] as int? ?? 0,
    placement: AdPlacement.fromWire(map['placement'] as String?),
    videoUrl: map['video_url'] as String?,
    posterUrl: map['poster_url'] as String?,
    startsAt: map['starts_at'] == null
        ? null
        : DateTime.parse(map['starts_at'] as String).toLocal(),
    endsAt: map['ends_at'] == null
        ? null
        : DateTime.parse(map['ends_at'] as String).toLocal(),
    audience: (map['audience'] as String?) ?? 'all',
    advertiser: map['advertiser'] as String?,
    linkUrl: map['link_url'] as String?,
    impressions: ((map['impressions'] as num?) ?? 0).toInt(),
    clicks: ((map['clicks'] as num?) ?? 0).toInt(),
    ctaLabel: map['cta_label'] as String?,
    dismissible: (map['dismissible'] as bool?) ?? true,
    dismissAfterSeconds: ((map['dismiss_after_seconds'] as num?) ?? 0).toInt(),
    frequency: (map['frequency'] as String?) ?? 'once',
    dismissals: ((map['dismissals'] as num?) ?? 0).toInt(),
  );

  @override
  List<Object?> get props => [
    id,
    imageUrl,
    type,
    vendorId,
    title,
    subtitle,
    code,
    isActive,
    sortOrder,
    placement,
    videoUrl,
    startsAt,
    endsAt,
    audience,
    impressions,
    clicks,
  ];
}
