/// Backend configuration.
///
/// The anon key is public by design (RLS protects the data) but is injected
/// at build time so it never lives in source control:
///
///   flutter run --dart-define=SUPABASE_ANON_KEY=eyJ...
abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://dvfbeaafekqdcwxogbqc.supabase.co',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_vDEZfX6SkbQlTmjscrYkvA_aa0Zr3Mo',
  );

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;

  /// Google Places / Geocoding, used by the address picker and the admin
  /// service-area editor so a place can be found by name instead of hunted for
  /// on the map. Map tiles come from OpenStreetMap and need no key.
  ///
  /// Needs "Places API" and "Geocoding API" enabled, and the key restricted to
  /// this app's bundle id / package name. When empty the search box hides
  /// itself and picking on the map still works.
  static const googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: 'AIzaSyBQjMj30LvXkmSO9zcQhc688L6pXxB2zGk',
  );

  static bool get hasPlacesSearch => googleMapsApiKey.isNotEmpty;
}


// flutter pub get
// flutter run --dart-define=SUPABASE_ANON_KEY=sb_publishable_vDEZfX6SkbQlTmjscrYkvA_aa0Zr3Mo