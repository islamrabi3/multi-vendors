import 'package:equatable/equatable.dart';

/// What tapping a home-carousel banner does.
enum BannerType { coupon, vendor, event }

/// A promotional offer shown in the home Offers section and managed by admins.
/// Backed by the `banners` table (image_url + optional title/subtitle/code).
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
      );

  @override
  List<Object?> get props =>
      [id, imageUrl, type, vendorId, title, subtitle, code, isActive, sortOrder];
}
