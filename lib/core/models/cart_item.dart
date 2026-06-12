import 'package:equatable/equatable.dart';

import 'product.dart';

class CartItem extends Equatable {
  const CartItem({
    required this.product,
    required this.quantity,
    this.selectedOptions = const [],
    this.notes,
  });

  final Product product;
  final int quantity;
  final List<ProductOption> selectedOptions;
  final String? notes;

  double get unitPrice =>
      product.price +
      selectedOptions.fold<double>(0, (sum, o) => sum + o.priceDelta);

  double get lineTotal => unitPrice * quantity;

  /// Two cart entries merge only if product and option selection match.
  String get signature {
    final optionIds = selectedOptions.map((o) => o.id).toList()..sort();
    return '${product.id}|${optionIds.join(',')}|${notes ?? ''}';
  }

  CartItem copyWith({int? quantity}) => CartItem(
        product: product,
        quantity: quantity ?? this.quantity,
        selectedOptions: selectedOptions,
        notes: notes,
      );

  @override
  List<Object?> get props => [product, quantity, selectedOptions, notes];
}
