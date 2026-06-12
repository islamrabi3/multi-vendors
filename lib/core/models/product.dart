import 'package:equatable/equatable.dart';

class ProductCategory extends Equatable {
  const ProductCategory({
    required this.id,
    required this.vendorId,
    required this.name,
    this.sortOrder = 0,
  });

  final String id;
  final String vendorId;
  final String name;
  final int sortOrder;

  factory ProductCategory.fromMap(Map<String, dynamic> map) => ProductCategory(
        id: map['id'] as String,
        vendorId: map['vendor_id'] as String,
        name: map['name'] as String,
        sortOrder: ((map['sort_order'] as num?) ?? 0).toInt(),
      );

  @override
  List<Object?> get props => [id, vendorId, name, sortOrder];
}

class ProductOption extends Equatable {
  const ProductOption({
    required this.id,
    required this.groupId,
    required this.name,
    required this.priceDelta,
    this.isAvailable = true,
  });

  final String id;
  final String groupId;
  final String name;
  final double priceDelta;
  final bool isAvailable;

  factory ProductOption.fromMap(Map<String, dynamic> map) => ProductOption(
        id: map['id'] as String,
        groupId: map['group_id'] as String,
        name: map['name'] as String,
        priceDelta: ((map['price_delta'] as num?) ?? 0).toDouble(),
        isAvailable: (map['is_available'] as bool?) ?? true,
      );

  @override
  List<Object?> get props => [id, groupId, name, priceDelta, isAvailable];
}

class ProductOptionGroup extends Equatable {
  const ProductOptionGroup({
    required this.id,
    required this.productId,
    required this.name,
    required this.minSelect,
    required this.maxSelect,
    this.options = const [],
  });

  final String id;
  final String productId;
  final String name;
  final int minSelect;
  final int maxSelect;
  final List<ProductOption> options;

  bool get isRequired => minSelect > 0;
  bool get isSingleChoice => maxSelect <= 1;

  factory ProductOptionGroup.fromMap(Map<String, dynamic> map) =>
      ProductOptionGroup(
        id: map['id'] as String,
        productId: map['product_id'] as String,
        name: map['name'] as String,
        minSelect: ((map['min_select'] as num?) ?? 0).toInt(),
        maxSelect: ((map['max_select'] as num?) ?? 1).toInt(),
        options: ((map['product_options'] as List?) ?? [])
            .map((o) => ProductOption.fromMap(o as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props => [id, productId, name, minSelect, maxSelect, options];
}

class Product extends Equatable {
  const Product({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.price,
    required this.isAvailable,
    this.categoryId,
    this.description,
    this.imageUrl,
    this.sortOrder = 0,
    this.optionGroups = const [],
  });

  final String id;
  final String vendorId;
  final String? categoryId;
  final String name;
  final String? description;
  final String? imageUrl;
  final double price;
  final bool isAvailable;
  final int sortOrder;
  final List<ProductOptionGroup> optionGroups;

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        vendorId: map['vendor_id'] as String,
        categoryId: map['category_id'] as String?,
        name: map['name'] as String,
        description: map['description'] as String?,
        imageUrl: map['image_url'] as String?,
        price: ((map['price'] as num?) ?? 0).toDouble(),
        isAvailable: (map['is_available'] as bool?) ?? true,
        sortOrder: ((map['sort_order'] as num?) ?? 0).toInt(),
        optionGroups: ((map['product_option_groups'] as List?) ?? [])
            .map((g) => ProductOptionGroup.fromMap(g as Map<String, dynamic>))
            .toList(),
      );

  @override
  List<Object?> get props =>
      [id, vendorId, categoryId, name, price, isAvailable, optionGroups];
}
