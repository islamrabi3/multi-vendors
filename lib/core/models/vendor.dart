import 'package:equatable/equatable.dart';

class VendorCategory extends Equatable {
  const VendorCategory({required this.id, required this.name, this.imageUrl});

  final String id;
  final String name;
  final String? imageUrl;

  factory VendorCategory.fromMap(Map<String, dynamic> map) => VendorCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        imageUrl: map['image_url'] as String?,
      );

  @override
  List<Object?> get props => [id, name, imageUrl];
}

class Vendor extends Equatable {
  const Vendor({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.isOpen,
    required this.isActive,
    required this.approvalStatus,
    required this.autoAccept,
    required this.deliveryFee,
    required this.minOrderAmount,
    required this.avgPrepMinutes,
    required this.ratingAvg,
    required this.ratingCount,
    this.categoryId,
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.phone,
    this.addressText,
    this.lat,
    this.lng,
    this.isBusy = false,
    this.extraPrepMinutes = 0,
    this.commissionRate = 10.0,
    this.deliveryRadiusKm = 10.0,
    this.isRecommended = false,
    this.recommendedRank = 0,
  });

  final String id;
  final String ownerId;
  final String name;
  final String? categoryId;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;
  final String? phone;
  final String? addressText;
  final double? lat;
  final double? lng;
  final bool isOpen;
  final bool isActive;
  final bool isBusy;
  final int extraPrepMinutes;
  final double commissionRate;
  final double deliveryRadiusKm;

  /// Promoted onto the customer home's recommended rail by an admin.
  final bool isRecommended;
  final int recommendedRank;

  /// Platform approval lifecycle: 'pending' | 'active' | 'suspended'.
  final String approvalStatus;
  final bool autoAccept;

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'active';
  bool get isSuspended => approvalStatus == 'suspended';
  final double deliveryFee;
  final double minOrderAmount;
  final int avgPrepMinutes;
  final double ratingAvg;
  final int ratingCount;

  int get totalPrepMinutes => avgPrepMinutes + (isBusy ? extraPrepMinutes : 0);

  factory Vendor.fromMap(Map<String, dynamic> map) => Vendor(
        id: map['id'] as String,
        ownerId: map['owner_id'] as String,
        name: map['name'] as String,
        categoryId: map['category_id'] as String?,
        description: map['description'] as String?,
        logoUrl: map['logo_url'] as String?,
        coverUrl: map['cover_url'] as String?,
        phone: map['phone'] as String?,
        addressText: map['address_text'] as String?,
        lat: (map['lat'] as num?)?.toDouble(),
        lng: (map['lng'] as num?)?.toDouble(),
        isOpen: (map['is_open'] as bool?) ?? false,
        isActive: (map['is_active'] as bool?) ?? true,
        approvalStatus: (map['approval_status'] as String?) ?? 'active',
        autoAccept: (map['auto_accept'] as bool?) ?? false,
        deliveryFee: ((map['delivery_fee'] as num?) ?? 0).toDouble(),
        minOrderAmount: ((map['min_order_amount'] as num?) ?? 0).toDouble(),
        avgPrepMinutes: ((map['avg_prep_minutes'] as num?) ?? 20).toInt(),
        ratingAvg: ((map['rating_avg'] as num?) ?? 0).toDouble(),
        ratingCount: ((map['rating_count'] as num?) ?? 0).toInt(),
        isBusy: (map['is_busy'] as bool?) ?? false,
        extraPrepMinutes: ((map['extra_prep_minutes'] as num?) ?? 0).toInt(),
        commissionRate: ((map['commission_rate'] as num?) ?? 10.0).toDouble(),
        deliveryRadiusKm: ((map['delivery_radius_km'] as num?) ?? 10.0).toDouble(),
        isRecommended: (map['is_recommended'] as bool?) ?? false,
        recommendedRank: ((map['recommended_rank'] as num?) ?? 0).toInt(),
      );

  @override
  List<Object?> get props => [
        id,
        name,
        isOpen,
        isActive,
        approvalStatus,
        autoAccept,
        deliveryFee,
        minOrderAmount,
        avgPrepMinutes,
        ratingAvg,
        ratingCount,
        logoUrl,
        isBusy,
        extraPrepMinutes,
        commissionRate,
        deliveryRadiusKm,
        isRecommended,
        recommendedRank,
      ];
}

