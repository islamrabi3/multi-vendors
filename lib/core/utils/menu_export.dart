import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csv_lib;
import 'package:excel/excel.dart' as xlsx;

import '../models/product.dart';

/// A store's menu as a spreadsheet, in the columns [MenuSheetParser] reads —
/// so an exported menu can be edited in Excel and imported straight back, to
/// the same store or another.
///
/// One row per dish, or one per size when a dish has a single required
/// choice (small / medium / large): that is how the importer turns rows back
/// into a size choice. Any other options are written, readably, into an
/// `extras` column the importer leaves alone.
class MenuExport {
  MenuExport._();

  static const header = [
    'category',
    'category_ar',
    'name',
    'name_ar',
    'description',
    'description_ar',
    'size',
    'price',
    'available',
    'extras',
  ];

  /// The sheet as rows, header first. Dishes follow the menu's own order:
  /// section by section, then uncategorised dishes last.
  static List<List<Object>> rows({
    required List<ProductCategory> categories,
    required List<Product> products,
  }) {
    final byCategory = <String?, List<Product>>{};
    for (final product in products) {
      byCategory.putIfAbsent(product.categoryId, () => []).add(product);
    }
    final ordered = [
      for (final category in categories)
        for (final product in byCategory[category.id] ?? const <Product>[])
          (category: category, product: product),
      for (final product in products.where(
        (p) =>
            p.categoryId == null ||
            !categories.any((c) => c.id == p.categoryId),
      ))
        (category: null, product: product),
    ];

    final out = <List<Object>>[header];
    for (final (:category, :product) in ordered) {
      final sizeGroup = _sizeGroupOf(product);
      final extras = product.optionGroups
          .where((g) => g != sizeGroup)
          .map(_describeGroup)
          .where((text) => text.isNotEmpty)
          .join('; ');
      List<Object> row(String size, double price) => [
        category?.name ?? '',
        category?.nameAr ?? '',
        product.name,
        product.nameAr ?? '',
        product.description ?? '',
        product.descriptionAr ?? '',
        size,
        _money(price),
        product.isAvailable ? 'yes' : 'no',
        extras,
      ];
      if (sizeGroup == null) {
        out.add(row('', product.price));
      } else {
        for (final option in sizeGroup.options) {
          out.add(row(option.name, product.price + option.priceDelta));
        }
      }
    }
    return out;
  }

  /// UTF-8 with a byte-order mark: without it Excel opens an Arabic CSV as
  /// mojibake.
  static Uint8List csv(List<List<Object>> rows) {
    final text = csv_lib.Csv().encode(rows);
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
  }

  static Uint8List excel(List<List<Object>> rows, {String sheet = 'Menu'}) {
    final book = xlsx.Excel.createExcel();
    final defaultSheet = book.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != sheet) {
      book.rename(defaultSheet, sheet);
    }
    final target = book[sheet];
    for (final row in rows) {
      target.appendRow([
        for (final cell in row)
          cell is num
              ? xlsx.DoubleCellValue(cell.toDouble())
              : xlsx.TextCellValue('$cell'),
      ]);
    }
    return Uint8List.fromList(book.encode() ?? const <int>[]);
  }

  /// The one required, pick-exactly-one group — sizes — or null.
  static ProductOptionGroup? _sizeGroupOf(Product product) {
    final single = product.optionGroups
        .where(
          (g) => g.minSelect == 1 && g.maxSelect == 1 && g.options.length > 1,
        )
        .toList();
    return single.length == 1 ? single.first : null;
  }

  static String _describeGroup(ProductOptionGroup group) {
    if (group.options.isEmpty) return '';
    final options = group.options
        .map(
          (o) => o.priceDelta == 0
              ? o.name
              : '${o.name} (${o.priceDelta > 0 ? '+' : ''}${_money(o.priceDelta)})',
        )
        .join(', ');
    return '${group.name}: $options';
  }

  static num _money(double value) {
    final rounded = (value * 100).roundToDouble() / 100;
    return rounded == rounded.roundToDouble() ? rounded.toInt() : rounded;
  }
}
