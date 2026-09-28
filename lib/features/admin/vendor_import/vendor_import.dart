import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csv_lib;
import 'package:excel/excel.dart' as xlsx;

import '../../../core/models/vendor.dart';

/// Many stores at once, from a spreadsheet or a JSON file.
///
/// Each row becomes exactly what the "New store" form would have sent to
/// `admin-create-account`, so a bulk import is held to the same rules as one
/// store typed in by hand. This file only reads and checks; the screen sends.

/// One store read from the file, and what is wrong with it if anything.
class VendorImportRow {
  VendorImportRow({
    required this.line,
    required this.email,
    required this.password,
    required this.passwordGenerated,
    required this.ownerName,
    required this.phone,
    required this.username,
    required this.storeName,
    required this.description,
    required this.categoryId,
    required this.categoryLabel,
    required this.address,
    required this.lat,
    required this.lng,
    required this.minOrder,
    required this.prepMinutes,
    required this.deliveryFee,
    required this.deliveryRadiusKm,
    required this.billingModel,
    required this.commissionRate,
    required this.subscriptionFee,
    required this.logoUrl,
    required this.coverUrl,
    required this.problems,
  });

  /// The row's number as the person sees it in their file (header is 1).
  final int line;
  final String email;
  final String password;

  /// The file gave no password, so one was made up; it goes in the results
  /// file so the store can be told how to sign in.
  final bool passwordGenerated;
  final String ownerName;
  final String? phone;
  final String? username;
  final String storeName;
  final String? description;
  final String? categoryId;
  final String categoryLabel;
  final String address;
  final double? lat;
  final double? lng;
  final double? minOrder;
  final int? prepMinutes;
  final double? deliveryFee;
  final double? deliveryRadiusKm;
  final String billingModel;
  final double? commissionRate;
  final double? subscriptionFee;
  final String? logoUrl;
  final String? coverUrl;

  /// Machine codes, shown in words by the screen. Empty means ready to send.
  final List<VendorImportProblem> problems;

  bool get ready => problems.isEmpty;

  /// The `vendor` block `admin-create-account` expects.
  Map<String, dynamic> get store => {
    'name': storeName,
    'description': ?description,
    'category_id': categoryId,
    'phone': ?phone,
    'address_text': address,
    'lat': lat,
    'lng': lng,
    'min_order_amount': ?minOrder,
    'avg_prep_minutes': ?prepMinutes,
    'delivery_fee': ?deliveryFee,
    'delivery_radius_km': ?deliveryRadiusKm,
    'billing_model': billingModel,
    'commission_rate': ?commissionRate,
    'subscription_fee': ?subscriptionFee,
    'logo_url': ?logoUrl,
    'cover_url': ?coverUrl,
  };
}

enum VendorImportProblem {
  missingEmail,
  badEmail,
  duplicateEmail,
  shortPassword,
  missingOwner,
  missingStoreName,
  unknownCategory,
  missingAddress,
  missingLocation,
}

class VendorImportException implements Exception {
  const VendorImportException(this.code);

  /// `IMPORT_EMPTY`, `IMPORT_UNREADABLE`, `IMPORT_NO_EMAIL_COLUMN`.
  final String code;

  @override
  String toString() => code;
}

class VendorImport {
  VendorImport._();

  /// Columns in the template, in order. Anything else in a file is ignored.
  static const templateHeader = [
    'store_name',
    'category',
    'owner_name',
    'email',
    'password',
    'phone',
    'username',
    'address',
    'lat',
    'lng',
    'map_link',
    'description',
    'delivery_fee',
    'min_order',
    'prep_minutes',
    'delivery_radius_km',
    'billing_model',
    'commission_rate',
    'subscription_fee',
    'logo_url',
    'cover_url',
  ];

  static const _templateExample = [
    'Burger Lab',
    'Burgers',
    'Ahmed Ali',
    'owner@burgerlab.com',
    '',
    '01000000000',
    'burgerlab',
    '12 Tahrir Square, Cairo',
    '30.0444',
    '31.2357',
    '',
    'Smash burgers and fries',
    '20',
    '100',
    '20',
    '10',
    'commission',
    '10',
    '',
    '',
    '',
  ];

  /// Loose column names → template column. Lowercased, with spaces,
  /// underscores and dashes removed before matching.
  static const _aliases = <String, List<String>>{
    'store_name': [
      'storename',
      'store',
      'name',
      'vendor',
      'restaurant',
      'اسمالمتجر',
      'المتجر',
      'المطعم',
    ],
    'category': ['category', 'categoryid', 'type', 'القسم', 'التصنيف'],
    'owner_name': [
      'ownername',
      'owner',
      'fullname',
      'contactname',
      'المالك',
      'اسمالمالك',
    ],
    'email': ['email', 'emailaddress', 'mail', 'البريد', 'الايميل', 'الإيميل'],
    'password': ['password', 'pass', 'كلمةالسر', 'كلمةالمرور'],
    'phone': [
      'phone',
      'mobile',
      'phonenumber',
      'tel',
      'الهاتف',
      'الموبايل',
      'التليفون',
    ],
    'username': ['username', 'login', 'اسمالمستخدم'],
    'address': ['address', 'addresstext', 'العنوان'],
    'lat': ['lat', 'latitude', 'خطالعرض'],
    'lng': ['lng', 'lon', 'long', 'longitude', 'خطالطول'],
    'map_link': [
      'maplink',
      'map',
      'googlemaps',
      'location',
      'maps',
      'الموقع',
      'الخريطة',
    ],
    'description': ['description', 'about', 'الوصف'],
    'delivery_fee': ['deliveryfee', 'delivery', 'رسومالتوصيل'],
    'min_order': [
      'minorder',
      'minimumorder',
      'minorderamount',
      'الحدالأدنى',
      'الحدالادنى',
    ],
    'prep_minutes': ['prepminutes', 'preptime', 'avgprepminutes', 'وقتالتحضير'],
    'delivery_radius_km': [
      'deliveryradiuskm',
      'radius',
      'deliveryradius',
      'نطاقالتوصيل',
    ],
    'billing_model': ['billingmodel', 'billing', 'plan', 'نظامالمحاسبة'],
    'commission_rate': ['commissionrate', 'commission', 'العمولة'],
    'subscription_fee': ['subscriptionfee', 'subscription', 'الاشتراك'],
    'logo_url': ['logourl', 'logo', 'الشعار'],
    'cover_url': ['coverurl', 'cover', 'الغلاف'],
  };

  static String _normalise(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '').trim();

  /// The template as a CSV, with one example row.
  static Uint8List templateCsv() {
    final text = csv_lib.Csv().encode([templateHeader, _templateExample]);
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
  }

  /// Reads [bytes] as CSV, Excel or JSON, judged by [fileName].
  static List<Map<String, String>> readRecords(
    Uint8List bytes,
    String fileName,
  ) {
    final name = fileName.toLowerCase();
    try {
      if (name.endsWith('.json')) return _fromJson(bytes);
      if (name.endsWith('.xlsx') || name.endsWith('.xls')) {
        return _fromTable(_excelRows(bytes));
      }
      return _fromTable(_csvRows(bytes));
    } on VendorImportException {
      rethrow;
    } catch (_) {
      throw const VendorImportException('IMPORT_UNREADABLE');
    }
  }

  static List<List<String>> _csvRows(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    return [
      for (final row in csv_lib.Csv(dynamicTyping: false).decode(text))
        [for (final cell in row) '${cell ?? ''}'.trim()],
    ];
  }

  static List<List<String>> _excelRows(Uint8List bytes) {
    final book = xlsx.Excel.decodeBytes(bytes);
    final sheet = book.tables.values.firstOrNull;
    if (sheet == null) return const [];
    return [
      for (final row in sheet.rows)
        [for (final cell in row) '${cell?.value ?? ''}'.trim()],
    ];
  }

  static List<Map<String, String>> _fromTable(List<List<String>> rows) {
    final nonEmpty = rows.where((r) => r.any((c) => c.isNotEmpty)).toList();
    if (nonEmpty.length < 2) {
      throw const VendorImportException('IMPORT_EMPTY');
    }
    final header = nonEmpty.first;
    final columns = <int, String>{};
    for (var i = 0; i < header.length; i++) {
      final key = _columnFor(header[i]);
      if (key != null && !columns.containsValue(key)) columns[i] = key;
    }
    if (!columns.containsValue('email')) {
      throw const VendorImportException('IMPORT_NO_EMAIL_COLUMN');
    }
    return [
      for (final row in nonEmpty.skip(1))
        {
          for (final entry in columns.entries)
            if (entry.key < row.length) entry.value: row[entry.key],
        },
    ];
  }

  static List<Map<String, String>> _fromJson(Uint8List bytes) {
    var decoded = jsonDecode(utf8.decode(bytes));
    // `{"stores": [...]}` as well as a bare list.
    if (decoded is Map) {
      decoded = decoded.values.firstWhere(
        (v) => v is List,
        orElse: () => const [],
      );
    }
    if (decoded is! List || decoded.isEmpty) {
      throw const VendorImportException('IMPORT_EMPTY');
    }
    return [
      for (final item in decoded.whereType<Map>())
        {
          for (final entry in item.entries)
            ?_columnFor('${entry.key}'): entry.value == null
                ? ''
                : '${entry.value}'.trim(),
        },
    ];
  }

  static String? _columnFor(String raw) {
    final n = _normalise(raw);
    if (n.isEmpty) return null;
    for (final entry in _aliases.entries) {
      if (_normalise(entry.key) == n || entry.value.contains(n)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Checks every record and resolves what can be resolved: the category by
  /// id or by name in either language, the location from lat/lng or a maps
  /// link, a password when none was given.
  static List<VendorImportRow> validate(
    List<Map<String, String>> records, {
    required List<VendorCategory> categories,
    Random? random,
  }) {
    final seen = <String>{};
    final rows = <VendorImportRow>[];
    for (var i = 0; i < records.length; i++) {
      final r = records[i];
      String text(String key) => (r[key] ?? '').trim();
      String? optional(String key) => text(key).isEmpty ? null : text(key);
      double? number(String key) =>
          double.tryParse(text(key).replaceAll(',', '.'));

      final problems = <VendorImportProblem>[];
      final email = text('email').toLowerCase();
      if (email.isEmpty) {
        problems.add(VendorImportProblem.missingEmail);
      } else if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        problems.add(VendorImportProblem.badEmail);
      } else if (!seen.add(email)) {
        problems.add(VendorImportProblem.duplicateEmail);
      }

      var password = text('password');
      final generated = password.isEmpty;
      if (generated) {
        password = generatePassword(random ?? Random.secure());
      } else if (password.length < 8) {
        problems.add(VendorImportProblem.shortPassword);
      }

      final storeName = text('store_name');
      if (storeName.isEmpty) problems.add(VendorImportProblem.missingStoreName);
      final ownerName = text('owner_name').isEmpty
          ? storeName
          : text('owner_name');
      if (ownerName.isEmpty) problems.add(VendorImportProblem.missingOwner);

      final categoryText = text('category');
      final category = _matchCategory(categoryText, categories);
      if (category == null) problems.add(VendorImportProblem.unknownCategory);

      final address = text('address');
      if (address.isEmpty) problems.add(VendorImportProblem.missingAddress);

      var lat = number('lat');
      var lng = number('lng');
      if ((lat == null || lng == null) && text('map_link').isNotEmpty) {
        final point = coordinatesFromLink(text('map_link'));
        lat = point?.lat;
        lng = point?.lng;
      }
      if (lat == null ||
          lng == null ||
          lat.abs() > 90 ||
          lng.abs() > 180 ||
          (lat == 0 && lng == 0)) {
        problems.add(VendorImportProblem.missingLocation);
      }

      final billing = text('billing_model').toLowerCase().startsWith('sub')
          ? 'subscription'
          : 'commission';

      rows.add(
        VendorImportRow(
          line: i + 2,
          email: email,
          password: password,
          passwordGenerated: generated,
          ownerName: ownerName,
          phone: optional('phone'),
          username: optional('username'),
          storeName: storeName,
          description: optional('description'),
          categoryId: category?.id,
          categoryLabel: category?.name ?? categoryText,
          address: address,
          lat: lat,
          lng: lng,
          minOrder: number('min_order'),
          prepMinutes: number('prep_minutes')?.round(),
          deliveryFee: number('delivery_fee'),
          deliveryRadiusKm: number('delivery_radius_km'),
          billingModel: billing,
          commissionRate: number('commission_rate'),
          subscriptionFee: number('subscription_fee'),
          logoUrl: optional('logo_url'),
          coverUrl: optional('cover_url'),
          problems: problems,
        ),
      );
    }
    return rows;
  }

  static VendorCategory? _matchCategory(
    String value,
    List<VendorCategory> categories,
  ) {
    if (value.isEmpty) return null;
    final n = value.trim().toLowerCase();
    for (final c in categories) {
      if (c.id == value.trim() ||
          c.name.trim().toLowerCase() == n ||
          (c.nameAr?.trim().toLowerCase() == n)) {
        return c;
      }
    }
    return null;
  }

  /// Pulls a point out of a Google Maps link: `@30.04,31.23,17z`,
  /// `?q=30.04,31.23`, `ll=`, `!3d30.04!4d31.23`, or a bare "30.04, 31.23".
  static ({double lat, double lng})? coordinatesFromLink(String link) {
    final patterns = [
      RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)'),
      RegExp(r'@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)'),
      RegExp(
        r'[?&](?:q|query|ll|destination)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)',
      ),
      RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$'),
    ];
    final decoded = Uri.decodeFull(link);
    for (final pattern in patterns) {
      final m = pattern.firstMatch(decoded);
      if (m == null) continue;
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    return null;
  }

  /// Twelve characters from an alphabet with no look-alikes (0/O, 1/l/I), so
  /// it can be read out over the phone.
  static String generatePassword(Random random) {
    const alphabet = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';
    return List.generate(
      12,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  /// What happened to each row, with the passwords that were made up, for
  /// the admin to hand to each store.
  static Uint8List resultsCsv(
    List<VendorImportRow> rows,
    Map<int, String> outcome,
  ) {
    final table = [
      ['line', 'store_name', 'email', 'password', 'result'],
      for (final row in rows)
        [
          '${row.line}',
          row.storeName,
          row.email,
          row.passwordGenerated ? row.password : '',
          outcome[row.line] ?? '',
        ],
    ];
    final text = csv_lib.Csv().encode(table);
    return Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(text)]);
  }
}
