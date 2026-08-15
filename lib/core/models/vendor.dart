import 'package:equatable/equatable.dart';

import 'vendor_schedule.dart';

class VendorCategory extends Equatable {
  const VendorCategory({
    required this.id,
    required this.name,
    this.nameAr,
    this.imageUrl,
    this.parentId,
    this.sortOrder = 0,
  });

  final String id;
  final String name;

  /// Arabic label. Null on the many categories a vendor typed in one language;
  /// callers fall back to [name] rather than showing a blank chip.
  final String? nameAr;
  final String? imageUrl;

  /// Null on a top-level kind of shop (Food, Groceries…); set on the
  /// cuisine-level entries beneath one. The tree is exactly two deep.
  final String? parentId;
  final int sortOrder;

  bool get isTopLevel => parentId == null;

  /// The label for [languageCode], falling back to the canonical name.
  String label(String languageCode) {
    if (languageCode == 'ar') {
      final arabic = nameAr?.trim();
      if (arabic != null && arabic.isNotEmpty) return arabic;
    }
    return name;
  }

  factory VendorCategory.fromMap(Map<String, dynamic> map) => VendorCategory(
    id: map['id'] as String,
    name: map['name'] as String,
    nameAr: map['name_ar'] as String?,
    imageUrl: map['image_url'] as String?,
    parentId: map['parent_id'] as String?,
    sortOrder: ((map['sort_order'] as num?) ?? 0).toInt(),
  );

  @override
  List<Object?> get props => [id, name, nameAr, imageUrl, parentId, sortOrder];
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
    this.billingModel = 'commission',
    this.subscriptionFee = 0,
    this.commissionRate = 10.0,
    this.deliveryRadiusKm = 10.0,
    this.isRecommended = false,
    this.recommendedRank = 0,
    this.schedules = const [],
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

  /// `commission` or `subscription`. Set once at sign-up and only an admin can
  /// change it afterwards; the store cannot switch to whichever is cheaper the
  /// month it gets busy.
  final String billingModel;

  /// Charged per period on the subscription plan; zero on commission.
  final double subscriptionFee;

  bool get isSubscription => billingModel == 'subscription';
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

  /// The store's weekly opening hours, when the query asked for them.
  ///
  /// Empty means "not loaded" *or* "never configured", and both are treated
  /// the same way on purpose: an absent schedule must not shut a store that is
  /// trading. Only a row that exists for today can close one.
  final List<VendorSchedule> schedules;

  VendorSchedule? scheduleFor(int dayOfWeek) {
    for (final schedule in schedules) {
      if (schedule.dayOfWeek == dayOfWeek) return schedule;
    }
    return null;
  }

  VendorSchedule? todaySchedule([DateTime? at]) {
    final now = at ?? DateTime.now();
    return scheduleFor(dayOfWeekIndex(now));
  }

  /// Whether the store is taking orders *right now*.
  ///
  /// [isOpen] is the owner's own switch — "we have shut early" — and the
  /// schedule is the timetable on the door. Both have to agree. Everything
  /// customer-facing reads this rather than [isOpen], so a store whose closing
  /// time has passed reads as closed even if nobody flipped the switch.
  /// Mirrors `public.vendor_is_open_now`, which is what actually refuses the
  /// order.
  bool isOpenNow([DateTime? at]) {
    if (!isOpen) return false;
    final now = at ?? DateTime.now();
    final today = scheduleFor(dayOfWeekIndex(now));
    return today == null || today.containsTime(now);
  }

  /// Today's closing time as `HH:MM`, for an "open until 23:00" line. Null when
  /// the store has no hours today, is shut, or trades round the clock.
  String? closingTime([DateTime? at]) {
    final today = todaySchedule(at);
    if (today == null || today.isClosed) return null;
    if (today.openTime == today.closeTime) return null;
    return today.closeTime;
  }

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
    billingModel: (map['billing_model'] as String?) ?? 'commission',
    subscriptionFee: ((map['subscription_fee'] as num?) ?? 0).toDouble(),
    commissionRate: ((map['commission_rate'] as num?) ?? 10.0).toDouble(),
    deliveryRadiusKm: ((map['delivery_radius_km'] as num?) ?? 10.0).toDouble(),
    isRecommended: (map['is_recommended'] as bool?) ?? false,
    recommendedRank: ((map['recommended_rank'] as num?) ?? 0).toInt(),
    // Only present when the caller joined the schedule in; absent everywhere
    // else, which reads as "no restriction".
    schedules: ((map['vendor_schedules'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map(VendorSchedule.fromMap)
        .toList(),
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
    schedules,
    categoryId,
    description,
    coverUrl,
    phone,
    addressText,
    lat,
    lng,
    billingModel,
    subscriptionFee,
  ];
}
