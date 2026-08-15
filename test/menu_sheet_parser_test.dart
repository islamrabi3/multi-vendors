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
}
