import 'dart:convert';
import 'dart:typed_data';

// Both packages export a top-level `excel`, so each is namespaced rather than
// relying on whichever wins.
import 'package:csv/csv.dart' as csv_lib;
import 'package:excel/excel.dart' as xlsx;

import '../repositories/menu_import_repository.dart';

/// Turns a CSV or Excel price list into the same shape the AI extractor
/// returns.
///
/// Deliberately not routed through the model. A spreadsheet is already
/// structured: parsing it is exact, instant and free, whereas asking a vision
/// model to read one costs money and introduces transcription errors into
/// numbers that are already machine-readable. The model is for photographs and
/// PDFs, where there is genuinely nothing else to do.
///
/// Headers are matched loosely, because a shop's own export will not use our
/// column names. Anything it cannot map is reported rather than guessed at.
class MenuSheetParser {
  MenuSheetParser._();

  /// Column aliases, lowercased and stripped of spaces and underscores.
  ///
  /// Order matters within the map: the longer, more specific fields are tried
  /// before the ones whose names are prefixes of them, so `description_ar`
  /// cannot be claimed by `description`.
  static const _aliases = <String, List<String>>{
    'name_ar': ['namear', 'arabicname', 'arabic', 'الاسمبالعربية'],
    'description_ar': ['descriptionar', 'arabicdescription', 'الوصفبالعربية'],
    'category': ['category', 'section', 'group', 'type', 'القسم', 'الفئة'],
    'name': ['name', 'item', 'product', 'title', 'itemname', 'الصنف', 'الاسم'],
    'description': ['description', 'desc', 'details', 'الوصف'],
    'price': [
      'price',
      'cost',
      'amount',
      'value',
      'السعر',
      'سعر',
    ],
    // One row per size is how most shops write a menu with sizes; without
    // this the same dish arrives three times.
    'size': ['size', 'variant', 'option', 'الحجم', 'المقاس'],
  };

  static String _normalise(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '').trim();

  /// Maps each column index to a known field, or leaves it unmapped.
  ///
  /// Matched by prefix rather than exactly. A shop's own export writes
  /// `price_egp`, `item_name`, `unit price` — all of which used to match
  /// nothing, and a menu with no price column became a menu where every item
  /// costs zero.
  static Map<String, int> _headerMap(List<String> header) {
    final map = <String, int>{};
    final taken = <int>{};

    bool claim(String field, bool Function(String cell, String alias) matches) {
      for (var i = 0; i < header.length; i++) {
        if (taken.contains(i)) continue;
        final cell = _normalise(header[i]);
        if (cell.isEmpty) continue;
        for (final alias in _aliases[field]!) {
          if (matches(cell, alias)) {
            map[field] = i;
            taken.add(i);
            return true;
          }
        }
      }
      return false;
    }

    // Exact names first, across every field, so a file that does name its
    // columns our way is never out-guessed by a loose match on another.
    for (final field in _aliases.keys) {
      claim(field, (cell, alias) => cell == alias);
    }
    for (final field in _aliases.keys) {
      if (map.containsKey(field)) continue;
      claim(
        field,
        (cell, alias) => cell.startsWith(alias) || cell.endsWith(alias),
      );
    }
    return map;
  }

  /// Prices arrive as "12", "12.50", "EGP 12.50" or "١٢" depending on who
  /// exported the file. Anything unreadable becomes 0, matching how the AI
  /// path reports a price it could not make out.
  static double _price(String raw) {
    if (raw.trim().isEmpty) return 0;
    const arabicDigits = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      final arabicIndex = arabicDigits.indexOf(char);
      if (arabicIndex >= 0) {
        buffer.write(arabicIndex);
      } else if (RegExp(r'[0-9.]').hasMatch(char)) {
        buffer.write(char);
      }
    }
    return double.tryParse(buffer.toString()) ?? 0;
  }

  /// Groups rows into categories, preserving the file's order.
  static List<ExtractedCategory> _fromRows(List<List<String>> rows) {
    if (rows.isEmpty) throw const MenuSheetException.empty();

    final header = _headerMap(rows.first);
    if (!header.containsKey('name')) {
      throw const MenuSheetException.noNameColumn();
    }

    String cell(List<String> row, String field) {
      final index = header[field];
      if (index == null || index >= row.length) return '';
      return row[index].trim();
    }

    // A LinkedHashMap keeps the file's own section order, which is the order
    // the shop thinks in. Within a section, rows are collected per dish so a
    // menu written one-row-per-size becomes one item with its sizes listed.
    final categories = <String, Map<String, _Draft>>{};
    for (final row in rows.skip(1)) {
      final name = cell(row, 'name');
      // Blank rows are padding in most exports, not data.
      if (name.isEmpty) continue;

      final category = cell(row, 'category');
      final categoryKey = category.isEmpty ? 'Menu' : category;
      final description = cell(row, 'description');
      final section = categories.putIfAbsent(categoryKey, () => {});
      final draft = section.putIfAbsent(
        // Same dish, same words about it: the only thing left to differ is
        // the size. A dish that repeats with a different description is a
        // different dish and keeps its own entry.
        '$name|$description',
        () => _Draft(
          name: name,
          nameAr: cell(row, 'name_ar'),
          description: description,
          descriptionAr: cell(row, 'description_ar'),
        ),
      );
      draft.add(cell(row, 'size'), _price(cell(row, 'price')));
    }

    if (categories.isEmpty) throw const MenuSheetException.noRows();

    return [
      for (final entry in categories.entries)
        ExtractedCategory(
          name: entry.key,
          nameAr: '',
          items: [for (final draft in entry.value.values) draft.build()],
        ),
    ];
  }

  static List<ExtractedCategory> parseCsv(Uint8List bytes) {
    // Excel writes UTF-8 with a BOM; left in place it becomes part of the
    // first header cell and that column stops matching.
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);

    // `dynamicTyping: false` keeps every cell a string: a price parsed as a
    // number here would lose "12.50" to "12.5" before we format it, and an
    // item code like "0012" would lose its zeros.
    final rows = csv_lib.Csv(dynamicTyping: false).decode(text);

    return _fromRows([
      for (final row in rows) [for (final cell in row) '${cell ?? ''}'],
    ]);
  }

  static List<ExtractedCategory> parseExcel(Uint8List bytes) {
    final book = xlsx.Excel.decodeBytes(bytes);
    // The first sheet with more than a header row. A workbook often carries an
    // empty "Sheet1" in front of the real data.
    for (final sheet in book.tables.values) {
      if (sheet.rows.length < 2) continue;
      return _fromRows([
        for (final row in sheet.rows)
          [for (final cell in row) '${cell?.value ?? ''}'],
      ]);
    }
    throw const MenuSheetException.empty();
  }
}

/// One dish while its rows are still being read.
///
/// A menu with sizes arrives as several rows for the same dish. The catalogue
/// has one price per item, so the item takes the cheapest size — what the
/// customer sees as "from" — and the full list of sizes goes into the
/// description, where it is at least true and legible until somebody adds
/// proper options.
class _Draft {
  _Draft({
    required this.name,
    required this.nameAr,
    required this.description,
    required this.descriptionAr,
  });

  final String name;
  final String nameAr;
  final String description;
  final String descriptionAr;
  final List<({String size, double price})> _rows = [];

  void add(String size, double price) {
    // A size repeated with the same price is the same line written twice,
    // which some exports do. A price of its own is not.
    final duplicate = _rows.any((r) => r.size == size && r.price == price);
    if (!duplicate) _rows.add((size: size, price: price));
  }

  /// The cheapest priced size, or 0 when the file priced none of them.
  double get _from {
    final priced = _rows.where((r) => r.price > 0).map((r) => r.price);
    if (priced.isEmpty) return 0;
    return priced.reduce((a, b) => a < b ? a : b);
  }

  String _sizeLine() {
    final sized = _rows.where((r) => r.size.isNotEmpty && r.price > 0);
    if (sized.length < 2) return '';
    return sized
        .map((r) => '${r.size} ${_money(r.price)}')
        .join(' · ');
  }

  static String _money(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  ExtractedItem build() {
    final sizes = _sizeLine();
    String withSizes(String text) {
      if (sizes.isEmpty) return text;
      return text.isEmpty ? sizes : '$text\n$sizes';
    }

    return ExtractedItem(
      name: name,
      nameAr: nameAr,
      description: withSizes(description),
      // The sizes read the same in either language; repeating them is better
      // than an Arabic description that silently loses them.
      descriptionAr: descriptionAr.isEmpty && description.isEmpty
          ? sizes
          : withSizes(descriptionAr),
      price: _from,
    );
  }
}

/// A spreadsheet the parser could not use, with a reason worth showing.
class MenuSheetException implements Exception {
  const MenuSheetException.empty() : code = 'SHEET_EMPTY';
  const MenuSheetException.noNameColumn() : code = 'SHEET_NO_NAME_COLUMN';
  const MenuSheetException.noRows() : code = 'SHEET_NO_ROWS';

  final String code;

  @override
  String toString() => code;
}
