import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/vendor.dart';
import 'package:multi_vendor/features/admin/vendor_import/vendor_import.dart';

void main() {
  const categories = [
    VendorCategory(id: 'cat-burgers', name: 'Burgers', nameAr: 'برجر'),
    VendorCategory(id: 'cat-pizza', name: 'Pizza', nameAr: 'بيتزا'),
  ];

  Uint8List csvOf(String text) => Uint8List.fromList(utf8.encode(text));

  test('the template reads back as a valid store', () {
    final records = VendorImport.readRecords(
      VendorImport.templateCsv(),
      'stores.csv',
    );
    final rows = VendorImport.validate(
      records,
      categories: categories,
      random: Random(1),
    );
    expect(rows.single.ready, isTrue);
    expect(rows.single.categoryId, 'cat-burgers');
    expect(rows.single.passwordGenerated, isTrue);
    expect(rows.single.password, hasLength(12));
  });

  test('loose Arabic and English headers, a maps link, and problems', () {
    final bytes = csvOf(
      'اسم المتجر,التصنيف,Email,Address,Location,Password\n'
      'كشري التحرير,بيتزا,a@b.com,وسط البلد,'
      '"https://www.google.com/maps/place/x/@30.0444,31.2357,17z",secret123\n'
      ',Tacos,a@b.com,,,short\n',
    );
    final rows = VendorImport.validate(
      VendorImport.readRecords(bytes, 'x.csv'),
      categories: categories,
    );
    expect(rows[0].ready, isTrue);
    expect(rows[0].categoryId, 'cat-pizza');
    expect(rows[0].lat, 30.0444);
    expect(rows[0].lng, 31.2357);
    expect(rows[0].line, 2);
    expect(
      rows[1].problems,
      containsAll([
        VendorImportProblem.duplicateEmail,
        VendorImportProblem.shortPassword,
        VendorImportProblem.missingStoreName,
        VendorImportProblem.unknownCategory,
        VendorImportProblem.missingAddress,
        VendorImportProblem.missingLocation,
      ]),
    );
  });

  test('JSON, as a list or wrapped in an object', () {
    final list = jsonEncode([
      {
        'store_name': 'Burger Lab',
        'category': 'cat-burgers',
        'email': 'x@y.com',
        'address': 'Cairo',
        'lat': 30.1,
        'lng': 31.2,
      },
    ]);
    for (final text in [list, '{"stores": $list}']) {
      final rows = VendorImport.validate(
        VendorImport.readRecords(csvOf(text), 'stores.json'),
        categories: categories,
      );
      expect(rows.single.ready, isTrue);
      expect(rows.single.store['lat'], 30.1);
    }
  });

  test('a file without an email column is refused as a whole', () {
    expect(
      () => VendorImport.readRecords(csvOf('name,city\nA,B\n'), 'a.csv'),
      throwsA(isA<VendorImportException>()),
    );
  });

  test('maps links in their common shapes', () {
    expect(
      VendorImport.coordinatesFromLink('https://maps.google.com/?q=29.9,31.1'),
      (lat: 29.9, lng: 31.1),
    );
    expect(VendorImport.coordinatesFromLink('.../data=!3d30.5!4d31.5'), (
      lat: 30.5,
      lng: 31.5,
    ));
    expect(VendorImport.coordinatesFromLink('30.01, 31.02'), (
      lat: 30.01,
      lng: 31.02,
    ));
    expect(VendorImport.coordinatesFromLink('no coordinates'), isNull);
  });
}
