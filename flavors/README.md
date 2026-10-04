# Clients (flavors)

The app is one codebase shipped to more than one client. Each client gets its
own name, colours, app icon, bundle id, Supabase project and Firebase project.
Nothing is shared between clients at runtime: a build talks to one backend.

## What makes up a client

| Where | What it holds |
| --- | --- |
| `flavors/<id>/dart_defines.json` | Everything the Dart code needs, fixed at build time: brand name and colours, Supabase URL and key, Firebase options, link origin. |
| `flavors/<id>/firebase/` | `google-services.json` and `GoogleService-Info.plist` from the client's Firebase project. |
| `flavors/<id>/icon.png` | 1024×1024 app icon. |
| `flavors/<id>/web/` | Optional files that replace the same path in the web build: `favicon.png`, `icons/`, `.well-known/`. |
| `flavorizr.yaml` | The native half: app name, bundle id, icon and Firebase files for Android and iOS. |

The Dart side reads its values through `Brand`
(`lib/core/config/brand.dart`), `AppConfig`, `AppColors` and
`DefaultFirebaseOptions`. They are compile-time constants because the design
tokens are used in `const` widgets throughout. Their defaults are Kitchen IN's,
so a plain `flutter run` is still that app.

## Everyday commands

```sh
dart run tool/client.dart list
dart run tool/client.dart run kitchenin
dart run tool/client.dart build kitchenin apk        # or appbundle, ios, ipa, web
dart run tool/client.dart deploy kitchenin           # web build + Firebase Hosting
```

These only add the two flags every client build needs:
`--flavor <id> --dart-define-from-file=flavors/<id>/dart_defines.json`.

## Adding a client

```sh
dart run tool/client.dart new acme --name "Acme Eats" --bundle com.acme.eats
```

That creates `flavors/acme/` and adds the entry to `flavorizr.yaml`. Then:

1. Fill in `flavors/acme/dart_defines.json`. The backend and Firebase values
   start empty on purpose, so a half-configured client fails rather than
   quietly using another client's data.
2. Add the two Firebase files to `flavors/acme/firebase/`.
3. Replace `flavors/acme/icon.png`.
4. Generate the native side:
   ```sh
   dart pub global activate flutter_flavorizr 2.6.0   # once per machine
   dart pub global run flutter_flavorizr -f
   ```
5. Build: `dart run tool/client.dart build acme apk`.

flavorizr is used as a global tool rather than a dev dependency: 2.6.0 needs
`xml ^7`, and the `excel` package the app uses still needs `xml <7`.

### A client's own logo

Kitchen IN's mark is drawn in code. A client with a logo image puts it in
`assets/flavors/<id>/logo.png`, lists that folder in `pubspec.yaml` for its
flavor only, and names it in `BRAND_LOGO_ASSET`:

```yaml
  assets:
    - path: assets/flavors/acme/
      flavors:
        - acme
```

## Colours

Five brand colours are per client (`BRAND_PRIMARY`, `BRAND_PRIMARY_DARK`,
`BRAND_PRIMARY_LIGHT`, `BRAND_ACCENT`, `BRAND_ACCENT_ON_DARK`), written as
`0xAARRGGBB`. The neutrals, tints and status colours in `AppColors` are shared
by every client and were tuned to sit beside Kitchen IN's aubergine; a client
with a very different hue may want those revisited.

## What a flavor does not cover

A flavor is the app. The client's backend is separate work: a Supabase project
with the schema applied and the Edge Functions deployed, and its secrets
(Paymob, push). Until that exists there is nothing for the build to talk to.
