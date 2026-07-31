import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../config/app_config.dart';

/// One autocomplete suggestion. [lat]/[lng] are filled in by [PlaceSearchService.resolve].
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primary,
    required this.secondary,
  });

  final String placeId;
  final String primary;
  final String secondary;
}

class PlaceLocation {
  const PlaceLocation({
    required this.lat,
    required this.lng,
    required this.address,
  });

  final double lat;
  final double lng;
  final String address;
}

/// Google Places search and reverse geocoding.
///
/// Used to find a spot by name instead of panning the map to it, and to fill an
/// address in from a dropped pin. Every method degrades to null/empty rather
/// than throwing: the map picker is the real input and must keep working when
/// the key is missing, unbilled, or offline.
class PlaceSearchService {
  PlaceSearchService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  bool get isAvailable => AppConfig.hasPlacesSearch;

  Future<List<PlaceSuggestion>> autocomplete(
    String input, {
    required String languageCode,
    double? nearLat,
    double? nearLng,
  }) async {
    if (!isAvailable || input.trim().length < 3) return const [];
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': input.trim(),
      'key': AppConfig.googleMapsApiKey,
      'language': languageCode,
      if (nearLat != null && nearLng != null) 'location': '$nearLat,$nearLng',
      if (nearLat != null && nearLng != null) 'radius': '50000',
    });
    final body = await _get(uri);
    if (body == null) return const [];
    final predictions = body['predictions'];
    if (predictions is! List) return const [];
    return predictions.map((p) {
      final formatting = p['structured_formatting'];
      return PlaceSuggestion(
        placeId: (p['place_id'] as String?) ?? '',
        primary: formatting is Map
            ? (formatting['main_text'] as String?) ?? ''
            : (p['description'] as String?) ?? '',
        secondary: formatting is Map
            ? (formatting['secondary_text'] as String?) ?? ''
            : '',
      );
    }).where((s) => s.placeId.isNotEmpty).toList();
  }

  /// Turns a suggestion into coordinates.
  Future<PlaceLocation?> resolve(
    PlaceSuggestion suggestion, {
    required String languageCode,
  }) async {
    if (!isAvailable) return null;
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': suggestion.placeId,
      'fields': 'geometry,formatted_address',
      'key': AppConfig.googleMapsApiKey,
      'language': languageCode,
    });
    final body = await _get(uri);
    final location = body?['result']?['geometry']?['location'];
    if (location is! Map) return null;
    return PlaceLocation(
      lat: (location['lat'] as num).toDouble(),
      lng: (location['lng'] as num).toDouble(),
      address: (body?['result']?['formatted_address'] as String?) ??
          [suggestion.primary, suggestion.secondary]
              .where((s) => s.isNotEmpty)
              .join(', '),
    );
  }

  /// Street address for a dropped pin, so the customer does not have to type
  /// what the map already knows.
  Future<String?> reverseGeocode(
    double lat,
    double lng, {
    required String languageCode,
  }) async {
    if (!isAvailable) return null;
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'latlng': '$lat,$lng',
      'key': AppConfig.googleMapsApiKey,
      'language': languageCode,
    });
    final body = await _get(uri);
    final results = body?['results'];
    if (results is! List || results.isEmpty) return null;
    return results.first['formatted_address'] as String?;
  }

  Future<Map<String, dynamic>?> _get(Uri uri) async {
    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final status = body['status'];
      if (status != 'OK' && status != 'ZERO_RESULTS') {
        // Surfaces REQUEST_DENIED (API not enabled / key restricted) in the log
        // instead of leaving a silently empty search box.
        debugPrint('Places request failed: $status ${body['error_message']}');
        return null;
      }
      return body;
    } catch (error) {
      debugPrint('Places request error: $error');
      return null;
    }
  }
}
