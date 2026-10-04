/// Whose app this build is.
///
/// One codebase ships to more than one client. Everything that makes a build
/// *theirs* — the name, the colours ([AppColors]), the backend ([AppConfig])
/// and the Firebase project — is fixed at build time from that client's file
/// in `flavors/`:
///
///   flutter run --flavor kitchenin \
///     --dart-define-from-file=flavors/kitchenin/dart_defines.json
///
/// They are compile-time constants on purpose: the design tokens are used in
/// `const` widgets throughout the app, and a brand that could change at
/// runtime would mean none of them could be. The defaults are Kitchen IN's,
/// so a plain `flutter run` is still that app.
abstract final class Brand {
  /// The client's key: the folder under `flavors/` and the native flavor.
  static const id = String.fromEnvironment(
    'BRAND_ID',
    defaultValue: 'kitchenin',
  );

  /// The name as a title: the browser tab, the task switcher, share text.
  static const name = String.fromEnvironment(
    'BRAND_NAME',
    defaultValue: 'KitchenIN',
  );

  /// The name as it reads in a sentence or beside the mark.
  static const displayName = String.fromEnvironment(
    'BRAND_DISPLAY_NAME',
    defaultValue: 'Kitchen IN',
  );

  /// The wordmark is the name in two tones: [wordmarkLead] in ink, then
  /// [wordmarkAccent] in the accent colour. A name with no second tone leaves
  /// the accent empty.
  static const wordmarkLead = String.fromEnvironment(
    'BRAND_WORDMARK_LEAD',
    defaultValue: 'Kitchen',
  );
  static const wordmarkAccent = String.fromEnvironment(
    'BRAND_WORDMARK_ACCENT',
    defaultValue: 'IN',
  );

  /// A square logo image bundled with this client's build, e.g.
  /// `assets/flavors/acme/logo.png`. Empty means the mark is drawn in code,
  /// which is how Kitchen IN's arch is made.
  static const logoAsset = String.fromEnvironment('BRAND_LOGO_ASSET');

  static bool get hasLogoAsset => logoAsset.isNotEmpty;

  /// Where shared links point: the client's web app, which also opens the
  /// installed app on a phone.
  static const linkOrigin = String.fromEnvironment(
    'BRAND_LINK_ORIGIN',
    defaultValue: 'https://multi-rest-app.web.app',
  );
}
