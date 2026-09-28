import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/product.dart';
import 'package:multi_vendor/core/utils/menu_export.dart';
import 'package:multi_vendor/core/utils/menu_sheet_parser.dart';

void main() {
  const pizzas = ProductCategory(
    id: 'c1',
    vendorId: 'v',
    name: 'Pizza',
    nameAr: 'بيتزا',
  );
  final products = [
    const Product(
      id: 'p1',
      vendorId: 'v',
      categoryId: 'c1',
      name: 'Margherita',
      nameAr: 'مارجريتا',
      description: 'Tomato and mozzarella',
      price: 90,
      isAvailable: true,
      optionGroups: [
        ProductOptionGroup(
          id: 'g1',
          productId: 'p1',
          name: 'Size',
          minSelect: 1,
          maxSelect: 1,
          options: [
            ProductOption(id: 'o1', groupId: 'g1', name: 'S', priceDelta: 0),
            ProductOption(id: 'o2', groupId: 'g1', name: 'L', priceDelta: 45),
          ],
        ),
        ProductOptionGroup(
          id: 'g2',
          productId: 'p1',
          name: 'Extras',
          minSelect: 0,
          maxSelect: 3,
          options: [
            ProductOption(
              id: 'o3',
              groupId: 'g2',
              name: 'Olives',
              priceDelta: 10,
            ),
          ],
        ),
      ],
    ),
    const Product(
      id: 'p2',
      vendorId: 'v',
      name: 'Water',
      price: 12.5,
      isAvailable: false,
    ),
  ];

  test('a size choice becomes one row per size, extras a readable column', () {
    final rows = MenuExport.rows(categories: [pizzas], products: products);
    expect(rows.first, MenuExport.header);
    expect(rows, hasLength(4));
    expect(rows[1][6], 'S');
    expect(rows[1][7], 90);
    expect(rows[2][6], 'L');
    expect(rows[2][7], 135);
    expect(rows[1][9], 'Extras: Olives (+10)');
    // Uncategorised dishes come last, and sold-out ones say so.
    expect(rows[3][2], 'Water');
    expect(rows[3][8], 'no');
  });

  test('an exported menu imports back as the same dishes and sizes', () {
    final rows = MenuExport.rows(categories: [pizzas], products: products);
    for (final bytes in [MenuExport.csv(rows), MenuExport.excel(rows)]) {
      final parsed = bytes.first == 0xEF
          ? MenuSheetParser.parseCsv(bytes)
          : MenuSheetParser.parseExcel(bytes);
      final pizza = parsed
          .expand((c) => c.items)
          .firstWhere((i) => i.name == 'Margherita');
      expect(pizza.nameAr, 'مارجريتا');
      expect(pizza.price, 90);
      expect(pizza.options.single.options.map((o) => o.name), ['S', 'L']);
      expect(pizza.options.single.options.last.priceDelta, 45);
      expect(
        parsed.expand((c) => c.items).any((i) => i.name == 'Water'),
        isTrue,
      );
    }
  });
}
