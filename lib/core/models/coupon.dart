import 'package:equatable/equatable.dart';

/// A promo code.
///
/// `percentage` applies `value`% up to `maxDiscount`, `fixed` subtracts
/// `value`, and `free_delivery` discounts exactly the store's delivery fee so
/// every total still adds up. A null `vendorId` is platform-wide.
///
/// The limits are the part that matters: [usageLimit] caps the campaign,
/// [perUserLimit] caps one customer — which is what was missing, and why the
/// same code could be redeemed on every order somebody placed.
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
    this.perUserLimit,
    this.expiresAt,
    this.startsAt,
    this.firstOrderOnly = false,
    this.isPublic = false,
    this.title,
  });

  final String id;
  final String code;
  final String discountType; // 'percentage' | 'fixed'
  final double value;
  final double minOrderAmount;
  final double? maxDiscount;

  /// Cap across everybody. Null = unlimited.
  final int? usageLimit;

  /// Cap per customer. Null = unlimited, which is what every existing code
  /// was before this column existed.
  final int? perUserLimit;

  final int usedCount;
  final bool isActive;
  final String? vendorId;
  final DateTime? expiresAt;

  /// Scheduled campaigns: the code exists but does nothing until this passes.
  final DateTime? startsAt;

  /// A welcome offer — valid only for a customer who has never had an order
  /// served.
  final bool firstOrderOnly;

  /// Listed on the offers page rather than only working when typed exactly.
  final bool isPublic;

  /// Shown to the customer instead of the raw code.
  final String? title;

  bool get isPercentage => discountType == 'percentage';
  bool get isFreeDelivery => discountType == 'free_delivery';
  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isScheduled => startsAt != null && startsAt!.isAfter(DateTime.now());
  bool get isExhausted => usageLimit != null && usedCount >= usageLimit!;

  /// Live right now, as the server would judge it.
  bool get isLive => isActive && !isExpired && !isScheduled && !isExhausted;

  factory Coupon.fromMap(Map<String, dynamic> map) => Coupon(
    id: map['id'] as String,
    code: map['code'] as String,
    discountType: (map['discount_type'] as String?) ?? 'fixed',
    value: ((map['value'] as num?) ?? 0).toDouble(),
    minOrderAmount: ((map['min_order_amount'] as num?) ?? 0).toDouble(),
    maxDiscount: (map['max_discount'] as num?)?.toDouble(),
    usageLimit: (map['usage_limit'] as num?)?.toInt(),
    perUserLimit: (map['per_user_limit'] as num?)?.toInt(),
    usedCount: ((map['used_count'] as num?) ?? 0).toInt(),
    isActive: (map['is_active'] as bool?) ?? true,
    vendorId: map['vendor_id'] as String?,
    expiresAt: map['expires_at'] == null
        ? null
        : DateTime.parse(map['expires_at'] as String).toLocal(),
    startsAt: map['starts_at'] == null
        ? null
        : DateTime.parse(map['starts_at'] as String).toLocal(),
    firstOrderOnly: (map['first_order_only'] as bool?) ?? false,
    isPublic: (map['is_public'] as bool?) ?? false,
    title: map['title'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    code,
    discountType,
    value,
    minOrderAmount,
    maxDiscount,
    usageLimit,
    perUserLimit,
    usedCount,
    isActive,
    vendorId,
    expiresAt,
    startsAt,
    firstOrderOnly,
    isPublic,
    title,
  ];
}
