import 'dart:math';

class RoutingService {
  /// Calculate Haversine distance in kilometers between two coordinates.
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }

  /// Estimate driving time in minutes based on distance (assumes 30 km/h avg speed in city)
  static int estimateDeliveryMinutes(double distanceKm, {int basePrepTime = 20}) {
    final travelTimeMinutes = ((distanceKm / 30.0) * 60).round();
    return basePrepTime + travelTimeMinutes;
  }

  /// Validate if location is within delivery radius
  static bool isWithinRadius({
    required double customerLat,
    required double customerLng,
    required double vendorLat,
    required double vendorLng,
    required double radiusKm,
  }) {
    final dist = calculateDistanceKm(customerLat, customerLng, vendorLat, vendorLng);
    return dist <= radiusKm;
  }
}
