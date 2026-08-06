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
  /// No default on purpose.
  ///
  /// A web build ships this in readable JavaScript, so a baked-in default is
  /// a key anyone can lift and bill to the project. Supply it at build time:
  ///
  ///   flutter build web --dart-define=GOOGLE_MAPS_API_KEY=AIza...
  ///
  /// Left empty the search box hides itself and picking on the map still
  /// works, so a build without it is degraded rather than broken.
  ///
  /// Restrict the key by HTTP referrer (web) and bundle id / package name
  /// (native) in the Google Cloud console regardless — shipping it at all
  /// means it is public.
  static const googleMapsApiKey = String.fromEnvironment('GOOGLE_MAPS_API_KEY');

  static bool get hasPlacesSearch => googleMapsApiKey.isNotEmpty;
}

// flutter pub get
// flutter run --dart-define=SUPABASE_ANON_KEY=sb_publishable_vDEZfX6SkbQlTmjscrYkvA_aa0Zr3Mo
