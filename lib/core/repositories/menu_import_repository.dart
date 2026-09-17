import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException;

import '../supabase_client.dart';

/// One extracted menu item, editable in the review step before import.
///
/// The extractor returns both languages for every name so the catalogue reads
/// correctly in either UI; either side may still be blank if the model could
/// not produce it, and the server falls back to whichever exists.
class ExtractedItem {
  ExtractedItem({
    required this.name,
    this.nameAr = '',
    this.description = '',
    this.descriptionAr = '',
    this.price = 0,
  });

  String name;
  String nameAr;
  String description;
  String descriptionAr;
  double price;

  /// True when the extractor gave us only one language for this item.
  bool get isMissingTranslation => name.isEmpty || nameAr.isEmpty;

  factory ExtractedItem.fromMap(Map<String, dynamic> map) => ExtractedItem(
    name: (map['name'] as String?)?.trim() ?? '',
    nameAr: (map['name_ar'] as String?)?.trim() ?? '',
    description: (map['description'] as String?)?.trim() ?? '',
    descriptionAr: (map['description_ar'] as String?)?.trim() ?? '',
    price: ((map['price'] as num?) ?? 0).toDouble(),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'name_ar': nameAr,
    'description': description,
    'description_ar': descriptionAr,
    'price': price,
  };
}

class ExtractedCategory {
  ExtractedCategory({
    required this.name,
    this.nameAr = '',
    required this.items,
  });

  String name;
  String nameAr;
  final List<ExtractedItem> items;

  /// True when the extractor gave us only one language for this section.
  bool get isMissingTranslation => name.isEmpty || nameAr.isEmpty;

  factory ExtractedCategory.fromMap(Map<String, dynamic> map) =>
      ExtractedCategory(
        name: (map['name'] as String?)?.trim() ?? '',
        nameAr: (map['name_ar'] as String?)?.trim() ?? '',
        items: ((map['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ExtractedItem.fromMap)
            // An Arabic-only menu still yields usable items.
            .where((item) => item.name.isNotEmpty || item.nameAr.isNotEmpty)
            .toList(),
      );

  Map<String, dynamic> toMap() => {
    'name': name,
    'name_ar': nameAr,
    'items': items.map((item) => item.toMap()).toList(),
  };
}

class MenuImportException implements Exception {
  const MenuImportException(this.code);
  final String code;

  @override
  String toString() => code;
}

/// Photos in -> structured menu out (extract-menu Edge Function), then a
/// single vendor_import_menu RPC creates all sections and items at once.
class MenuImportRepository {
  /// [vendorId] is checked server-side against `can_extract_menu`, so a
  /// store whose switch is off cannot extract by calling this directly.
  Future<List<ExtractedCategory>> extractMenu(
    String vendorId,
    List<({Uint8List bytes, String mimeType})> images,
  ) => _extract({
    'vendor_id': vendorId,
    'images': [
      for (final image in images)
        {'data': base64Encode(image.bytes), 'media_type': image.mimeType},
    ],
  });

  /// The same extraction, from a page the store already publishes its menu on.
  ///
  /// The link is fetched by the Edge Function rather than the device: only the
  /// server can be trusted to decide which addresses it is willing to request,
  /// and a browser could not read most of these pages cross-origin anyway.
  Future<List<ExtractedCategory>> extractMenuFromUrl(
    String vendorId,
    String url,
  ) => _extract({'vendor_id': vendorId, 'url': url.trim()});

  Future<List<ExtractedCategory>> _extract(Map<String, dynamic> body) async {
    final Object? data;
    try {
      final response = await supabase.functions.invoke(
        'extract-menu',
        body: body,
      );
      data = response.data;
    } on FunctionException catch (error) {
      // A refused link answers 400 with its reason in the body, which the
      // client throws rather than returns. Without this, every rejection read
      // as "extraction failed" and the operator never learned that the link
      // itself was the problem.
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      throw MenuImportException(code?.toString() ?? 'EXTRACTION_FAILED');
    }
    if (data is! Map) throw const MenuImportException('EXTRACTION_FAILED');
    if (data['error'] != null) {
      throw MenuImportException(data['error'].toString());
    }

    final categories = ((data['categories'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ExtractedCategory.fromMap)
        .where(
          (category) =>
              (category.name.isNotEmpty || category.nameAr.isNotEmpty) &&
              category.items.isNotEmpty,
        )
        .toList();
    return categories;
  }

  /// Returns (categoriesAdded, itemsAdded).
  Future<({int categories, int items})> importMenu(
    String vendorId,
    List<ExtractedCategory> menu,
  ) async {
    final result = await supabase.rpc(
      'vendor_import_menu',
      params: {
        'p_vendor_id': vendorId,
        'p_menu': {
          'categories': menu.map((category) => category.toMap()).toList(),
        },
      },
    );
    final map = result is Map ? result : const {};
    return (
      categories: ((map['categories_added'] as num?) ?? 0).toInt(),
      items: ((map['items_added'] as num?) ?? 0).toInt(),
    );
  }
}
