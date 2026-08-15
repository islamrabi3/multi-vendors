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
  static const _aliases = <String, List<String>>{
    'category': ['category', 'section', 'group', 'type', 'القسم', 'الفئة'],
    'name': ['name', 'item', 'product', 'title', 'itemname', 'الصنف', 'الاسم'],
    'name_ar': ['namear', 'arabicname', 'arabic', 'الاسمبالعربية'],
    'description': ['description', 'desc', 'details', 'الوصف'],
    'description_ar': ['descriptionar', 'arabicdescription', 'الوصفبالعربية'],
    'price': ['price', 'cost', 'amount', 'value', 'السعر'],
  };

  static String _normalise(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '').trim();

  /// Maps each column index to a known field, or leaves it unmapped.
  static Map<String, int> _headerMap(List<String> header) {
    final map = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      final cell = _normalise(header[i]);
      if (cell.isEmpty) continue;
      for (final entry in _aliases.entries) {
        if (map.containsKey(entry.key)) continue;
        if (entry.value.contains(cell)) {
          map[entry.key] = i;
          break;
        }
      }
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
    // the shop thinks in.
    final categories = <String, List<ExtractedItem>>{};
    for (final row in rows.skip(1)) {
      final name = cell(row, 'name');
      // Blank rows are padding in most exports, not data.
      if (name.isEmpty) continue;

      final category = cell(row, 'category');
      final key = category.isEmpty ? 'Menu' : category;
      categories.putIfAbsent(key, () => []).add(
        ExtractedItem(
          name: name,
          nameAr: cell(row, 'name_ar'),
          description: cell(row, 'description'),
          descriptionAr: cell(row, 'description_ar'),
          price: _price(cell(row, 'price')),
        ),
      );
    }

    if (categories.isEmpty) throw const MenuSheetException.noRows();

    return [
      for (final entry in categories.entries)
        ExtractedCategory(name: entry.key, nameAr: '', items: entry.value),
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

/// A spreadsheet the parser could not use, with a reason worth showing.
class MenuSheetException implements Exception {
  const MenuSheetException.empty() : code = 'SHEET_EMPTY';
  const MenuSheetException.noNameColumn() : code = 'SHEET_NO_NAME_COLUMN';
  const MenuSheetException.noRows() : code = 'SHEET_NO_ROWS';

  final String code;

  @override
  String toString() => code;
}
