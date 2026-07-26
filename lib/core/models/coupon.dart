import 'package:equatable/equatable.dart';

/// A promo code. `percentage` discounts apply `value`% up to `maxDiscount`;
/// `fixed` discounts subtract `value` directly. A null `vendorId` is
/// platform-wide.
class Coupon extends Equatable {
  const Coupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.value,
    required this.minOrderAmount,
    required this.usedCount,
    required this.isActive,
    this.vendorId,
    this.maxDiscount,
    this.usageLimit,
    this.expiresAt,
  });

  final String id;
  final String code;
  final String discountType; // 'percentage' | 'fixed'
  final double value;
  final double minOrderAmount;
  final double? maxDiscount;
  final int? usageLimit;
  final int usedCount;
  final bool isActive;
  final String? vendorId;
  final DateTime? expiresAt;

  bool get isPercentage => discountType == 'percentage';
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  factory Coupon.fromMap(Map<String, dynamic> map) => Coupon(
        id: map['id'] as String,
        code: map['code'] as String,
        discountType: (map['discount_type'] as String?) ?? 'fixed',
        value: ((map['value'] as num?) ?? 0).toDouble(),
        minOrderAmount: ((map['min_order_amount'] as num?) ?? 0).toDouble(),
        maxDiscount: (map['max_discount'] as num?)?.toDouble(),
        usageLimit: (map['usage_limit'] as num?)?.toInt(),
        usedCount: ((map['used_count'] as num?) ?? 0).toInt(),
        isActive: (map['is_active'] as bool?) ?? true,
        vendorId: map['vendor_id'] as String?,
        expiresAt: map['expires_at'] == null
            ? null
            : DateTime.parse(map['expires_at'] as String).toLocal(),
      );

  @override
  List<Object?> get props =>
      [id, code, discountType, value, minOrderAmount, maxDiscount, usageLimit,
        usedCount, isActive, vendorId, expiresAt];
}
