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

  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured => supabaseAnonKey.isNotEmpty;
}


// flutter pub get
// flutter run --dart-define=SUPABASE_ANON_KEY=sb_publishable_vDEZfX6SkbQlTmjscrYkvA_aa0Zr3Mo