import 'package:equatable/equatable.dart';

/// Picks the Arabic text when the UI is Arabic and a translation exists,
/// otherwise the canonical text. Vendors type items in one language only, so
/// falling back is the normal case rather than an error.
String localizedText(String canonical, String? arabic, String languageCode) =>
    languageCode == 'ar' && (arabic?.trim().isNotEmpty ?? false)
        ? arabic!.trim()
        : canonical;

class ProductCategory extends Equatable {
  const ProductCategory({
    required this.id,
    required this.vendorId,
    required this.name,
    this.nameAr,
    this.sortOrder = 0,
  });

  final String id;
  final String vendorId;
  final String name;
  final String? nameAr;
  final int sortOrder;

  String displayName(String languageCode) =>
      localizedText(name, nameAr, languageCode);

  factory ProductCategory.fromMap(Map<String, dynamic> map) => ProductCategory(
        id: map['id'] as String,
        vendorId: map['vendor_id'] as String,
        name: map['name'] as String,
        nameAr: map['name_ar'] as String?,
        sortOrder: ((map['sort_order'] as num?) ?? 0).toInt(),
      );

  @override
  List<Object?> get props => [id, vendorId, name, nameAr, sortOrder];
}

/// One dish in a search result.
///
/// Deliberately not a [Product]: a search hit needs the store it belongs to
/// and nothing about options or availability, and loading full products for
/// every match across the platform would be a much larger query for data the
/// result list never shows.
class ProductHit extends Equatable {
  const ProductHit({
    required this.id,
    required this.vendorId,
    required this.vendorName,
    required this.name,
    required this.price,
    this.nameAr,
    this.imageUrl,
  });

  final String id;
  final String vendorId;
  final String vendorName;
  final String name;
  final String? nameAr;
  final String? imageUrl;
  final double price;

  String displayName(String languageCode) =>
      localizedText(name, nameAr, languageCode);

  factory ProductHit.fromMap(Map<String, dynamic> map) => ProductHit(
        id: map['id'] as String,
        vendorId: map['vendor_id'] as String,
        vendorName: (map['vendor_name'] as String?) ?? '',
        name: map['name'] as String,
        nameAr: map['name_ar'] as String?,
        imageUrl: map['image_url'] as String?,
        price: ((map['price'] as num?) ?? 0).toDouble(),
      );

  @override
  List<Object?> get props =>
      [id, vendorId, vendorName, name, nameAr, imageUrl, price];
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
    this.nameAr,
    this.categoryId,
    this.description,
    this.descriptionAr,
    this.imageUrl,
    this.sortOrder = 0,
    this.optionGroups = const [],
  });

  final String id;
  final String vendorId;
  final String? categoryId;
  final String name;
  final String? nameAr;
  final String? description;
  final String? descriptionAr;
  final String? imageUrl;
  final double price;
  final bool isAvailable;
  final int sortOrder;
  final List<ProductOptionGroup> optionGroups;

  String displayName(String languageCode) =>
      localizedText(name, nameAr, languageCode);

  String? displayDescription(String languageCode) {
    final canonical = description;
    if (canonical == null || canonical.trim().isEmpty) {
      final arabic = descriptionAr?.trim();
      return (arabic?.isNotEmpty ?? false) ? arabic : null;
    }
    return localizedText(canonical, descriptionAr, languageCode);
  }

  /// Only the fields a menu edit can change without reopening the editor.
  ///
  /// A reorder is applied locally before its write lands, so the dragged row
  /// does not jump back to its old place for the length of a round trip.
  Product copyWith({int? sortOrder, bool? isAvailable, String? categoryId}) =>
      Product(
        id: id,
        vendorId: vendorId,
        categoryId: categoryId ?? this.categoryId,
        name: name,
        nameAr: nameAr,
        description: description,
        descriptionAr: descriptionAr,
        imageUrl: imageUrl,
        price: price,
        isAvailable: isAvailable ?? this.isAvailable,
        sortOrder: sortOrder ?? this.sortOrder,
        optionGroups: optionGroups,
      );

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as String,
        vendorId: map['vendor_id'] as String,
        categoryId: map['category_id'] as String?,
        name: map['name'] as String,
        nameAr: map['name_ar'] as String?,
        description: map['description'] as String?,
        descriptionAr: map['description_ar'] as String?,
        imageUrl: map['image_url'] as String?,
        price: ((map['price'] as num?) ?? 0).toDouble(),
        isAvailable: (map['is_available'] as bool?) ?? true,
        sortOrder: ((map['sort_order'] as num?) ?? 0).toInt(),
        optionGroups: ((map['product_option_groups'] as List?) ?? [])
            .map((g) => ProductOptionGroup.fromMap(g as Map<String, dynamic>))
            .toList(),
      );

  // `sortOrder` belongs here: a reorder changes nothing else about a row, and
  // without it two differently ordered lists compare equal and the rebuild
  // that would show the drag never happens.
  @override
  List<Object?> get props => [
        id,
        vendorId,
        categoryId,
        name,
        nameAr,
        description,
        descriptionAr,
        imageUrl,
        price,
        isAvailable,
        sortOrder,
        optionGroups,
      ];
}
