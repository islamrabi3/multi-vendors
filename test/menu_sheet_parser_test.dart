import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/utils/menu_sheet_parser.dart';

/// A mis-mapped column here does not fail loudly — it imports a whole
/// catalogue with the wrong prices, which somebody discovers when a customer
/// is charged the wrong amount. These pin the mapping and the number parsing.
void main() {
  Uint8List csv(String text) => Uint8List.fromList(utf8.encode(text));

  group('csv', () {
    test('maps our own column names', () {
      final menu = MenuSheetParser.parseCsv(
        csv(
          'category,name,name_ar,description,price\n'
          'Burgers,Cheeseburger,تشيز برجر,With cheddar,85.50\n'
          'Burgers,Double,دبل,,120\n'
          'Drinks,Cola,كولا,,20\n',
        ),
      );

      expect(menu.length, 2);
      expect(menu.first.name, 'Burgers');
      expect(menu.first.items.length, 2);
      expect(menu.first.items.first.name, 'Cheeseburger');
      expect(menu.first.items.first.nameAr, 'تشيز برجر');
      expect(menu.first.items.first.price, 85.50);
      expect(menu.last.name, 'Drinks');
    });

    test("maps a shop's own header names, not just ours", () {
      // Nobody's export says "name_ar". Loose matching is the whole point.
      final menu = MenuSheetParser.parseCsv(
        csv(
          'Section,Item Name,Arabic Name,Cost\n'
          'Grills,Kofta,كفتة,150\n',
        ),
      );
      expect(menu.single.name, 'Grills');
      expect(menu.single.items.single.name, 'Kofta');
      expect(menu.single.items.single.nameAr, 'كفتة');
      expect(menu.single.items.single.price, 150);
    });

    test('reads a price with a currency on it, and Arabic digits', () {
      final menu = MenuSheetParser.parseCsv(
        csv('name,price\nA,EGP 45.75\nB,٢٥\nC,\n'),
      );
      final items = menu.single.items;
      expect(items[0].price, 45.75);
      expect(items[1].price, 25);
      // Unreadable becomes zero rather than throwing, matching the AI path.
      expect(items[2].price, 0);
    });

    test('survives a UTF-8 BOM, which Excel always writes', () {
      // Left in place the BOM joins the first header cell and "name" stops
      // matching, which would reject the whole file.
      final menu = MenuSheetParser.parseCsv(csv('﻿name,price\nA,10\n'));
      expect(menu.single.items.single.name, 'A');
    });

    test('quoted fields containing commas stay one field', () {
      final menu = MenuSheetParser.parseCsv(
        csv('name,description,price\n"Mix, large","Rice, meat and salad",90\n'),
      );
      expect(menu.single.items.single.name, 'Mix, large');
      expect(menu.single.items.single.description, 'Rice, meat and salad');
      expect(menu.single.items.single.price, 90);
    });

    test('rows with no name are padding and are skipped', () {
      final menu = MenuSheetParser.parseCsv(csv('name,price\nA,10\n,\nB,20\n'));
      expect(menu.single.items.length, 2);
    });

    test('items with no category land in one default section', () {
      final menu = MenuSheetParser.parseCsv(csv('name,price\nA,10\nB,20\n'));
      expect(menu.single.name, 'Menu');
      expect(menu.single.items.length, 2);
    });

    test('a file with no name column is refused, not guessed at', () {
      // Importing a catalogue from columns we could not identify would be
      // worse than saying no.
      expect(
        () => MenuSheetParser.parseCsv(csv('foo,bar\n1,2\n')),
        throwsA(isA<MenuSheetException>()),
      );
    });

    test('a header with no rows under it is refused', () {
      expect(
        () => MenuSheetParser.parseCsv(csv('name,price\n')),
        throwsA(isA<MenuSheetException>()),
      );
    });
  });

  /// A real shop's export: `price_egp` rather than `price`, `item` rather than
  /// `name`, and one row for every size. Every price imported as zero, because
  /// a header had to equal an alias exactly and `priceegp` equalled none — so
  /// no price column was found at all and every lookup returned "".
  group('a shop export with sized rows', () {
    Uint8List sheet() => csv(
      'category,item,description,size,price_egp,popular\n'
      'قسم البيتزا,بيتزا مارجريتا,صوص + موزاريلا,صغير,90,\n'
      'قسم البيتزا,بيتزا مارجريتا,صوص + موزاريلا,وسط,110,\n'
      'قسم البيتزا,بيتزا مارجريتا,صوص + موزاريلا,كبير,135,\n'
      'قسم البيتزا,بيتزا نصين,اختيار نوعين,صغير,-,\n'
      'قسم البيتزا,بيتزا نصين,اختيار نوعين,وسط,135,\n'
      'قسم البيتزا,بيتزا نصين,اختيار نوعين,كبير,155,\n'
      'إضافات البيتزا,إضافة زيتون,,,10,\n'
      'إضافات البيتزا,إضافة جبنة,,,15,\n'
      'إضافات البيتزا,إضافة زيتون,,,10,\n'
      'قسم الشاورما,شاورما كبير,,,85,yes\n',
    );

    test('reads a price column the shop named itself', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final zero = [
        for (final category in menu)
          for (final item in category.items)
            if (item.price == 0) '${category.name}/${item.name}',
      ];
      expect(zero, isEmpty, reason: 'price_egp is a price column');
    });

    test('three size rows are one dish with a size choice', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final pizza = menu.firstWhere((c) => c.name == 'قسم البيتزا');
      final margherita = pizza.items.where(
        (i) => i.name == 'بيتزا مارجريتا',
      );
      expect(margherita.length, 1);
      expect(margherita.single.price, 90, reason: 'the cheapest size');
      // The description says what is on the pizza, and nothing about sizes.
      expect(margherita.single.description, 'صوص + موزاريلا');

      final sizes = margherita.single.options.single;
      expect(sizes.label, 'Size', reason: "named after the file's own column");
      expect(sizes.minSelect, 1, reason: 'a size must be chosen');
      expect(sizes.maxSelect, 1, reason: 'exactly one');
      expect(
        sizes.options.map((o) => '${o.label} ${o.priceDelta}').toList(),
        ['صغير 0.0', 'وسط 20.0', 'كبير 45.0'],
        reason: 'priced as the difference from the cheapest size',
      );
    });

    test('a dish sold in one size gains no choice', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final shawarma = menu.firstWhere((c) => c.name == 'قسم الشاورما');
      expect(shawarma.items.single.options, isEmpty);
    });

    test('a size the file left unpriced is not offered', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final pizza = menu.firstWhere((c) => c.name == 'قسم البيتزا');
      final half = pizza.items.firstWhere((i) => i.name == 'بيتزا نصين');
      expect(
        half.options.single.options.map((o) => o.label),
        ['وسط', 'كبير'],
        reason: '"-" is a gap in the export, not a size on sale',
      );
    });

    test('an unpriced size does not become the price', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final pizza = menu.firstWhere((c) => c.name == 'قسم البيتزا');
      final half = pizza.items.firstWhere((i) => i.name == 'بيتزا نصين');
      expect(half.price, 135, reason: '"-" is not a price');
    });

    test('an unsized row keeps its own price', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final shawarma = menu.firstWhere((c) => c.name == 'قسم الشاورما');
      expect(shawarma.items.single.price, 85);
      expect(shawarma.items.single.description, isEmpty);
    });

    test('a line written twice is one item', () {
      final menu = MenuSheetParser.parseCsv(sheet());
      final extras = menu.firstWhere((c) => c.name == 'إضافات البيتزا');
      expect(extras.items.where((i) => i.name == 'إضافة زيتون').length, 1);
      expect(extras.items.length, 2);
    });
  });
}
