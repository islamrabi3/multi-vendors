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

  String get wireName =>
      _wire.entries.firstWhere((e) => e.value == this).key;

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
    this.optionNames = const [],
  });

  final String productName;
  final double unitPrice;
  final int quantity;
  final double lineTotal;
  final List<String> optionNames;

  factory OrderItem.fromMap(Map<String, dynamic> map) => OrderItem(
        productName: map['product_name'] as String,
        unitPrice: ((map['unit_price'] as num?) ?? 0).toDouble(),
        quantity: ((map['quantity'] as num?) ?? 1).toInt(),
        lineTotal: ((map['line_total'] as num?) ?? 0).toDouble(),
        optionNames: ((map['selected_options'] as List?) ?? [])
            .map((o) => (o as Map)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .toList(),
      );

  @override
  List<Object?> get props =>
      [productName, unitPrice, quantity, lineTotal, optionNames];
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

  bool get isPaid => paymentStatus == 'paid';
  bool get isCod => paymentMethod == 'cod';

  String get addressSummary {
    final a = deliveryAddress;
    return [
      a['street'],
      if ((a['building'] as String?)?.isNotEmpty ?? false) 'Bldg ${a['building']}',
      if ((a['floor'] as String?)?.isNotEmpty ?? false) 'Floor ${a['floor']}',
      if ((a['apartment'] as String?)?.isNotEmpty ?? false) 'Apt ${a['apartment']}',
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
    );
  }

  @override
  List<Object?> get props =>
      [id, status, paymentStatus, driverId, total, items, vendorName];
}
