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
    'category_ar': ['categoryar', 'arabiccategory', 'sectionar'],
    'size_ar': ['sizear', 'arabicsize'],
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

  /// Which fields have an Arabic twin, and what that twin is called.
  static const _arabicOf = <String, String>{
    'name': 'name_ar',
    'description': 'description_ar',
    'category': 'category_ar',
    'size': 'size_ar',
  };

  /// How a column says which language it holds.
  ///
  /// A bilingual export writes the pair as `item_ar` / `item_en`, and both
  /// normalise to something starting with `item` — which is exactly how the
  /// Arabic column came to be read as *the* name column and the English one
  /// thrown away, leaving an Arabic-only catalogue from a file that had both.
  static const _arabicSuffixes = ['ar', 'arabic', 'ara'];
  static const _latinSuffixes = ['en', 'english', 'eng', 'latin'];

  static String _normalise(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '').trim();

  /// Maps each column index to a known field, or leaves it unmapped.
  ///
  /// Three passes, narrowest first, because a loose match made too early is
  /// how columns get stolen from one another:
  ///
  /// 1. Exact names, so a file that does use our own column names is never
  ///    out-guessed by a loose match on another.
  /// 2. A language-tagged pair — `item_ar` and `item_en` — split into the
  ///    field and its Arabic twin. This has to beat the loose pass: `itemar`
  ///    begins with `item`, so left to it the Arabic column became *the* name
  ///    column and the English one was dropped on the floor.
  /// 3. Loosely, by prefix or suffix, for the headers a shop invents:
  ///    `price_egp`, `item_name`, `unit price`.
  static Map<String, int> _headerMap(List<String> header) {
    final map = <String, int>{};
    final taken = <int>{};

    bool claim(String field, bool Function(String cell, String alias) matches) {
      for (var i = 0; i < header.length; i++) {
        if (taken.contains(i) || map.containsKey(field)) continue;
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

    for (final field in _aliases.keys) {
      claim(field, (cell, alias) => cell == alias);
    }

    // The bilingual pass. A suffix only counts when what is left in front of
    // it is a column we recognise, so `price_egp` is not read as English and
    // a `year` column is not read as Arabic.
    for (var i = 0; i < header.length; i++) {
      if (taken.contains(i)) continue;
      final cell = _normalise(header[i]);
      if (cell.isEmpty) continue;
      for (final MapEntry(key: base, value: arabic) in _arabicOf.entries) {
        final aliases = _aliases[base]!;
        String? field;
        for (final suffix in _arabicSuffixes) {
          if (cell.length > suffix.length &&
              cell.endsWith(suffix) &&
              aliases.contains(cell.substring(0, cell.length - suffix.length))) {
            field = arabic;
            break;
          }
        }
        if (field == null) {
          for (final suffix in _latinSuffixes) {
            if (cell.length > suffix.length &&
                cell.endsWith(suffix) &&
                aliases.contains(
                  cell.substring(0, cell.length - suffix.length),
                )) {
              field = base;
              break;
            }
          }
        }
        if (field != null && !map.containsKey(field)) {
          map[field] = i;
          taken.add(i);
          break;
        }
      }
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
    // An Arabic-only file names its items in Arabic and nothing else, which
    // is still a menu.
    if (!header.containsKey('name') && !header.containsKey('name_ar')) {
      throw const MenuSheetException.noNameColumn();
    }

    // The size group is named after the file's own column, so an Arabic
    // export produces "الحجم" and an English one "Size" without the parser
    // having to know which language the shop speaks. A bilingual file names
    // its columns `size_ar` / `size_en`, neither of which is a word to show a
    // customer, so those get the plain word in the language the sizes
    // themselves are written in.
    final sizeIndex = header['size'] ?? header['size_ar'];
    final bilingualSize =
        header.containsKey('size') && header.containsKey('size_ar');
    final sizeHeader = sizeIndex == null ? '' : rows.first[sizeIndex].trim();
    final taggedSize =
        RegExp(r'[_\s-]?(ar|en|arabic|english)$', caseSensitive: false)
            .hasMatch(sizeHeader);
    // A header is written to be a column heading, not read out to a
    // customer: "size" becomes "Size". Arabic has no case, so it is left
    // exactly as the shop wrote it.
    final sizeLabel = sizeHeader.isEmpty || bilingualSize || taggedSize
        ? (header.containsKey('size_ar') ? 'الحجم' : 'Size')
        : sizeHeader[0].toUpperCase() + sizeHeader.substring(1);

    String cell(List<String> row, String field) {
      final index = header[field];
      if (index == null || index >= row.length) return '';
      return row[index].trim();
    }

    // A LinkedHashMap keeps the file's own section order, which is the order
    // the shop thinks in. Within a section, rows are collected per dish so a
    // menu written one-row-per-size becomes one item with its sizes listed.
    final categories = <String, _Section>{};
    for (final row in rows.skip(1)) {
      final name = cell(row, 'name');
      final nameAr = cell(row, 'name_ar');
      // Blank rows are padding in most exports, not data.
      if (name.isEmpty && nameAr.isEmpty) continue;

      final category = cell(row, 'category');
      final categoryAr = cell(row, 'category_ar');
      // Keyed on whichever language the file actually filled in, so the two
      // halves of one bilingual section cannot become two sections.
      final categoryKey = [
        category,
        categoryAr,
      ].where((part) => part.isNotEmpty).join('|');
      final description = cell(row, 'description');
      final descriptionAr = cell(row, 'description_ar');
      final section = categories.putIfAbsent(
        categoryKey.isEmpty ? 'Menu' : categoryKey,
        () => _Section(
          name: category.isEmpty && categoryAr.isEmpty ? 'Menu' : category,
          nameAr: categoryAr,
        ),
      );
      final draft = section.items.putIfAbsent(
        // Same dish, same words about it: the only thing left to differ is
        // the size. A dish that repeats with a different description is a
        // different dish and keeps its own entry.
        '$name|$nameAr|$description|$descriptionAr',
        () => _Draft(
          name: name,
          nameAr: nameAr,
          description: description,
          descriptionAr: descriptionAr,
        ),
      );
      // The size is one choice in one language: the Arabic word when the file
      // gave one, since that is what the shop's customers read.
      final size = cell(row, 'size_ar').isNotEmpty
          ? cell(row, 'size_ar')
          : cell(row, 'size');
      draft.add(size, _price(cell(row, 'price')));
    }

    if (categories.isEmpty) throw const MenuSheetException.noRows();

    return [
      for (final section in categories.values)
        ExtractedCategory(
          name: section.name,
          nameAr: section.nameAr,
          items: [
            for (final draft in section.items.values) draft.build(sizeLabel),
          ],
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

/// One section while its rows are still being read, in both languages.
class _Section {
  _Section({required this.name, required this.nameAr});

  final String name;
  final String nameAr;
  final Map<String, _Draft> items = {};
}

/// One dish while its rows are still being read.
///
/// A menu with sizes arrives as several rows for the same dish. The product
/// carries one price, so the item is priced at its cheapest size and the
/// sizes become a required choice on it — the customer picks one and pays the
/// difference, exactly as if the store had built the options by hand.
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

  /// The sizes, as a choice the customer makes.
  ///
  /// Priced as a difference from the cheapest size, which is what the item
  /// itself now costs: small is +0, medium +25, large +45. A size the file
  /// left unpriced is dropped rather than offered at the base price — it is
  /// not a size the shop sells, it is a gap in the export.
  ExtractedOptionGroup? _sizeGroup(String label) {
    final sized = _rows.where((r) => r.size.isNotEmpty && r.price > 0).toList();
    // One size is not a choice; it is just the price.
    if (sized.length < 2) return null;
    final base = _from;
    return ExtractedOptionGroup(
      name: label,
      // Exactly one: a pizza is small or large, never both and never neither.
      minSelect: 1,
      maxSelect: 1,
      options: [
        for (final row in sized)
          ExtractedOption(name: row.size, priceDelta: row.price - base),
      ],
    );
  }

  ExtractedItem build(String sizeLabel) {
    final sizes = _sizeGroup(sizeLabel);
    return ExtractedItem(
      name: name,
      nameAr: nameAr,
      description: description,
      descriptionAr: descriptionAr,
      price: _from,
      options: [?sizes],
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
