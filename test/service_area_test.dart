import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/service_area.dart';

ServiceArea _area({
  double lat = 30.0444,
  double lng = 31.2357,
  double radiusKm = 5,
}) =>
    ServiceArea(
      id: 'a1',
      name: 'Cairo',
      lat: lat,
      lng: lng,
      radiusKm: radiusKm,
    );

void main() {
  group('distanceKm', () {
    test('is zero for the same point', () {
      expect(distanceKm(30.0444, 31.2357, 30.0444, 31.2357), closeTo(0, 0.001));
    });

    test('matches a known distance (Cairo to Alexandria ~180km)', () {
      final km = distanceKm(30.0444, 31.2357, 31.2001, 29.9187);
      expect(km, closeTo(180, 10));
    });

    test('is symmetric', () {
      final a = distanceKm(30.0444, 31.2357, 31.2001, 29.9187);
      final b = distanceKm(31.2001, 29.9187, 30.0444, 31.2357);
      expect(a, closeTo(b, 0.0001));
    });
  });

  group('ServiceArea.contains', () {
    test('accepts the centre', () {
      final area = _area();
      expect(area.contains(area.lat, area.lng), isTrue);
    });

    test('rejects a point beyond the radius', () {
      // Alexandria is ~180km from the Cairo centre, well outside 5km.
      expect(_area().contains(31.2001, 29.9187), isFalse);
    });

    test('accepts a point just inside the radius', () {
      // ~1.1km north of the centre (0.01 degrees of latitude).
      expect(_area(radiusKm: 5).contains(30.0544, 31.2357), isTrue);
    });

    test('a wider radius covers what a narrow one does not', () {
      const farLat = 30.2444; // ~22km north
      expect(_area(radiusKm: 5).contains(farLat, 31.2357), isFalse);
      expect(_area(radiusKm: 30).contains(farLat, 31.2357), isTrue);
    });
  });

  group('ServiceArea.displayName', () {
    test('falls back to the English name when Arabic is missing', () {
      expect(_area().displayName('ar'), 'Cairo');
    });

    test('uses the Arabic name when present', () {
      const area = ServiceArea(
        id: 'a1',
        name: 'Cairo',
        nameAr: 'القاهرة',
        lat: 30.0444,
        lng: 31.2357,
        radiusKm: 5,
      );
      expect(area.displayName('ar'), 'القاهرة');
      expect(area.displayName('en'), 'Cairo');
    });
  });
}
