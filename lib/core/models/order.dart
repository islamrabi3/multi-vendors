import 'package:equatable/equatable.dart';

enum OrderStatus {
  pending,
  accepted,
  preparing,
  readyForPickup,
  outForDelivery,
  delivered,
  cancelled,
  rejected;

  static const _wire = {
    'pending': OrderStatus.pending,
    'accepted': OrderStatus.accepted,
    'preparing': OrderStatus.preparing,
    'ready_for_pickup': OrderStatus.readyForPickup,
    'out_for_delivery': OrderStatus.outForDelivery,
    'delivered': OrderStatus.delivered,
    'cancelled': OrderStatus.cancelled,
    'rejected': OrderStatus.rejected,
  };

  static OrderStatus fromName(String? name) =>
      _wire[name] ?? OrderStatus.pending;

  String get wireName => _wire.entries.firstWhere((e) => e.value == this).key;

  String get label => switch (this) {
    pending => 'Pending',
    accepted => 'Accepted',
    preparing => 'Preparing',
    readyForPickup => 'Ready for pickup',
    outForDelivery => 'Out for delivery',
    delivered => 'Delivered',
    cancelled => 'Cancelled',
    rejected => 'Rejected',
  };

  bool get isTerminal =>
      this == delivered || this == cancelled || this == rejected;
}

class OrderItem extends Equatable {
  const OrderItem({
    required this.productName,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    this.productId,
    this.optionNames = const [],
    this.optionIds = const [],
  });

  /// The line records the name and price it was bought at, so a renamed or
  /// repriced product never rewrites history. [productId] is what points back
  /// at the live product — needed to put the same thing in a cart again.
  ///
  /// Null only for rows written before the column existed.
  final String? productId;
  final String productName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;

  /// For display.
  final List<String> optionNames;

  /// For rebuilding: the option rows themselves, so a reorder brings back
  /// "extra cheese" rather than a plain burger.
  final List<String> optionIds;

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    final options = ((map['selected_options'] as List?) ?? []).cast<Map>();
    return OrderItem(
      productId: map['product_id'] as String?,
      productName: map['product_name'] as String,
      unitPrice: ((map['unit_price'] as num?) ?? 0).toDouble(),
      quantity: ((map['quantity'] as num?) ?? 1).toInt(),
      lineTotal: ((map['line_total'] as num?) ?? 0).toDouble(),
      optionNames: options
          .map((o) => o['name'] as String? ?? '')
          .where((n) => n.isNotEmpty)
          .toList(),
      optionIds: options
          .map((o) => o['option_id'] as String? ?? '')
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }

  @override
  List<Object?> get props => [
    productId,
    productName,
    unitPrice,
    quantity,
    lineTotal,
    optionNames,
  ];
}

class AppOrder extends Equatable {
  const AppOrder({
    required this.id,
    required this.orderNumber,
    required this.customerId,
    required this.vendorId,
    required this.status,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
    required this.deliveryAddress,
    this.driverId,
    this.deliveryLat,
    this.deliveryLng,
    this.customerNotes,
    this.rejectionReason,
    this.vendorName,
    this.vendorLogoUrl,
    this.items = const [],
    this.orderType = 'delivery',
    this.scheduledAt,
    this.driverTip = 0.0,
    this.walletAmountUsed = 0.0,
    this.deliveryProofUrl,
    this.deliveryOtp,
    this.releasedAt,
    this.acceptedAt,
    this.readyAt,
    this.pickedUpAt,
    this.deliveredAt,
  });

  final String id;
  final String orderNumber;
  final String customerId;
  final String vendorId;
  final String? driverId;
  final OrderStatus status;
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;
  final String paymentMethod;
  final String paymentStatus;
  final DateTime createdAt;
  final Map<String, dynamic> deliveryAddress;
  final double? deliveryLat;
  final double? deliveryLng;
  final String? customerNotes;
  final String? rejectionReason;
  final String? vendorName;
  final String? vendorLogoUrl;
  final List<OrderItem> items;
  final String orderType;
  final DateTime? scheduledAt;
  final double driverTip;
  final double walletAmountUsed;
  final String? deliveryProofUrl;
  final String? deliveryOtp;

  /// When the store was allowed to see it. Null on a scheduled order that is
  /// still waiting for its slot; stamped immediately on everything else.
  final DateTime? releasedAt;

  /// When each stage actually happened. The columns have been written by the
  /// status trigger since the beginning; nothing read them back, so the
  /// customer's tracker showed which stage the order was in but never when it
  /// got there.
  final DateTime? acceptedAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;

  bool get isPaid => paymentStatus == 'paid';
  bool get isCod => paymentMethod == 'cod';
  bool get isPickup => orderType == 'pickup';

  /// Whether the store may see it yet.
  bool get isReleased => releasedAt != null;
  bool get isScheduled => orderType == 'scheduled';

  static DateTime? _time(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  String get addressSummary {
    final a = deliveryAddress;
    return [
      a['street'],
      if ((a['building'] as String?)?.isNotEmpty ?? false)
        'Bldg ${a['building']}',
      if ((a['floor'] as String?)?.isNotEmpty ?? false) 'Floor ${a['floor']}',
      if ((a['apartment'] as String?)?.isNotEmpty ?? false)
        'Apt ${a['apartment']}',
    ].whereType<String>().join(', ');
  }

  String? get customerName => deliveryAddress['customer_name'] as String?;
  String? get customerPhone => deliveryAddress['customer_phone'] as String?;

  factory AppOrder.fromMap(Map<String, dynamic> map) {
    final vendor = map['vendors'];
    return AppOrder(
      id: map['id'] as String,
      orderNumber: (map['order_number'] as String?) ?? '',
      customerId: map['customer_id'] as String,
      vendorId: map['vendor_id'] as String,
      driverId: map['driver_id'] as String?,
      status: OrderStatus.fromName(map['status'] as String?),
      subtotal: ((map['subtotal'] as num?) ?? 0).toDouble(),
      deliveryFee: ((map['delivery_fee'] as num?) ?? 0).toDouble(),
      discount: ((map['discount'] as num?) ?? 0).toDouble(),
      total: ((map['total'] as num?) ?? 0).toDouble(),
      paymentMethod: (map['payment_method'] as String?) ?? 'cod',
      paymentStatus: (map['payment_status'] as String?) ?? 'unpaid',
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      deliveryAddress:
          (map['delivery_address'] as Map?)?.cast<String, dynamic>() ?? {},
      deliveryLat: (map['delivery_lat'] as num?)?.toDouble(),
      deliveryLng: (map['delivery_lng'] as num?)?.toDouble(),
      customerNotes: map['customer_notes'] as String?,
      rejectionReason: map['rejection_reason'] as String?,
      vendorName: vendor is Map ? vendor['name'] as String? : null,
      vendorLogoUrl: vendor is Map ? vendor['logo_url'] as String? : null,
      items: ((map['order_items'] as List?) ?? [])
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList(),
      orderType: (map['order_type'] as String?) ?? 'delivery',
      scheduledAt: map['scheduled_at'] != null
          ? DateTime.parse(map['scheduled_at'] as String).toLocal()
          : null,
      driverTip: ((map['driver_tip'] as num?) ?? 0).toDouble(),
      walletAmountUsed: ((map['wallet_amount_used'] as num?) ?? 0).toDouble(),
      deliveryProofUrl: map['delivery_proof_url'] as String?,
      deliveryOtp: map['delivery_otp'] as String?,
      releasedAt: _time(map['released_at']),
      acceptedAt: _time(map['accepted_at']),
      readyAt: _time(map['ready_at']),
      pickedUpAt: _time(map['picked_up_at']),
      deliveredAt: _time(map['delivered_at']),
    );
  }

  @override
  List<Object?> get props => [
    id,
    status,
    paymentStatus,
    driverId,
    total,
    items,
    vendorName,
    orderType,
    scheduledAt,
    driverTip,
    walletAmountUsed,
    deliveryProofUrl,
    deliveryOtp,
  ];
}
