// One codebase, several clients. This is the one command that knows how a
// client's build is put together, so nobody has to remember the flags.
//
//   dart run tool/client.dart list
//   dart run tool/client.dart new acme --name "Acme Eats" --bundle com.acme.eats
//   dart run tool/client.dart run acme
//   dart run tool/client.dart build acme apk|appbundle|ios|web [flutter args…]
//   dart run tool/client.dart deploy acme
//
// A client is a folder in flavors/ (what the Dart code needs: name, colours,
// backend, Firebase) plus an entry in flavorizr.yaml (what Android and iOS
// need: app name, bundle id, icon, Firebase files). See flavors/README.md.
import 'dart:convert';
import 'dart:io';

const _flavorsDir = 'flavors';
const _template = 'kitchenin';

Never _fail(String message) {
  stderr.writeln(message);
  exit(64);
}

String _definesPath(String id) => '$_flavorsDir/$id/dart_defines.json';

Map<String, dynamic> _defines(String id) {
  final file = File(_definesPath(id));
  if (!file.existsSync()) {
    _fail('No client "$id". Known: ${_clients().join(', ')}');
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

List<String> _clients() => [
  for (final entry in Directory(_flavorsDir).listSync())
    if (entry is Directory &&
        File('${entry.path}/dart_defines.json').existsSync())
      entry.uri.pathSegments.where((s) => s.isNotEmpty).last,
]..sort();

Future<int> _exec(String command, List<String> args) async {
  stdout.writeln('\$ $command ${args.join(' ')}');
  final process = await Process.start(
    command,
    args,
    mode: ProcessStartMode.inheritStdio,
    runInShell: true,
  );
  return process.exitCode;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _fail('Usage: dart run tool/client.dart <list|new|run|build|deploy> …');
  }
  switch (args.first) {
    case 'list':
      for (final id in _clients()) {
        final d = _defines(id);
        stdout.writeln('$id\t${d['BRAND_DISPLAY_NAME']}\t${d['SUPABASE_URL']}');
      }
    case 'new':
      _new(args.skip(1).toList());
    case 'run':
      if (args.length < 2) _fail('Usage: run <client> [flutter args…]');
      exit(
        await _exec('flutter', [
          'run',
          '--flavor',
          args[1],
          '--dart-define-from-file=${_definesPath(args[1])}',
          ...args.skip(2),
        ]),
      );
    case 'build':
      if (args.length < 3) {
        _fail(
          'Usage: build <client> <apk|appbundle|ios|ipa|web> [flutter args…]',
        );
      }
      exit(await _build(args[1], args[2], args.skip(3).toList()));
    case 'deploy':
      if (args.length < 2) _fail('Usage: deploy <client>');
      exit(await _deploy(args[1]));
    default:
      _fail('Unknown command "${args.first}".');
  }
}

Future<int> _build(String id, String target, List<String> extra) async {
  _defines(id);
  final code = await _exec('flutter', [
    'build',
    target,
    // Web has no native flavors; the client's file is all it needs.
    if (target != 'web') ...['--flavor', id],
    '--dart-define-from-file=${_definesPath(id)}',
    ...extra,
  ]);
  if (code == 0 && target == 'web') _brandWebBuild(id);
  return code;
}

/// The web shell (tab title, install name, icons, the files that tie shared
/// links to the installed app) is static HTML, which no dart-define reaches.
/// So it is rewritten in the build output, never in web/ itself.
void _brandWebBuild(String id) {
  final defines = _defines(id);
  final name = '${defines['BRAND_NAME']}';

  final index = File('build/web/index.html');
  index.writeAsStringSync(
    index
        .readAsStringSync()
        .replaceFirst(RegExp(r'<title>[^<]*</title>'), '<title>$name</title>')
        .replaceFirstMapped(
          RegExp(r'(<meta name="apple-mobile-web-app-title" content=")[^"]*'),
          (m) => '${m[1]}$name',
        ),
  );

  final manifestFile = File('build/web/manifest.json');
  final manifest =
      jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
  manifest['name'] = name;
  manifest['short_name'] = name;
  manifestFile.writeAsStringSync(
    const JsonEncoder.withIndent('    ').convert(manifest),
  );

  // Anything in flavors/<client>/web/ replaces the file of the same path:
  // favicon.png, icons/, .well-known/assetlinks.json, and so on.
  final overrides = Directory('$_flavorsDir/$id/web');
  if (overrides.existsSync()) {
    for (final entry in overrides.listSync(recursive: true)) {
      if (entry is! File) continue;
      final target = File(
        'build/web/${entry.path.substring(overrides.path.length + 1)}',
      );
      target.parent.createSync(recursive: true);
      entry.copySync(target.path);
    }
  }
  stdout.writeln('Branded build/web for $id ($name).');
}

Future<int> _deploy(String id) async {
  final project = '${_defines(id)['FIREBASE_PROJECT_ID'] ?? ''}';
  if (project.isEmpty) _fail('$id has no FIREBASE_PROJECT_ID.');
  final built = await _build(id, 'web', ['--release']);
  if (built != 0) return built;
  return _exec('firebase', [
    'deploy',
    '--only',
    'hosting',
    '--project',
    project,
  ]);
}

void _new(List<String> args) {
  String? option(String flag) {
    final at = args.indexOf(flag);
    return at >= 0 && at + 1 < args.length ? args[at + 1] : null;
  }

  if (args.isEmpty || args.first.startsWith('--')) {
    _fail('Usage: new <id> --name "Display Name" --bundle com.example.app');
  }
  final id = args.first;
  final name = option('--name');
  final bundle = option('--bundle');
  // The id becomes a Gradle flavor, an Xcode scheme and a folder name.
  if (!RegExp(r'^[a-z][a-z0-9]{1,29}$').hasMatch(id)) {
    _fail(
      'The id must be 2-30 lowercase letters and digits, starting with a letter.',
    );
  }
  if (name == null || bundle == null) {
    _fail('Both --name and --bundle are required.');
  }
  if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(bundle)) {
    _fail('"$bundle" is not a valid bundle id (e.g. com.acme.eats).');
  }
  final dir = Directory('$_flavorsDir/$id');
  if (dir.existsSync()) _fail('flavors/$id already exists.');

  Directory('${dir.path}/firebase').createSync(recursive: true);
  Directory('${dir.path}/web').createSync();
  File('$_flavorsDir/$_template/icon.png').copySync('${dir.path}/icon.png');

  // Start from the template's keys so none is forgotten; blank out everything
  // that belongs to somebody else's backend, so a half-configured client
  // fails loudly instead of quietly talking to another client's data.
  final defines = _defines(_template);
  for (final key in defines.keys.toList()) {
    if (key.startsWith('FIREBASE_') ||
        key.startsWith('SUPABASE_') ||
        key == 'GOOGLE_MAPS_API_KEY' ||
        key == 'FCM_VAPID_KEY' ||
        key == 'BRAND_LINK_ORIGIN' ||
        key == 'BRAND_LOGO_ASSET') {
      defines[key] = '';
    }
  }
  defines['BRAND_ID'] = id;
  defines['BRAND_NAME'] = name.replaceAll(' ', '');
  defines['BRAND_DISPLAY_NAME'] = name;
  defines['BRAND_WORDMARK_LEAD'] = name;
  defines['BRAND_WORDMARK_ACCENT'] = '';
  defines['FIREBASE_IOS_BUNDLE_ID'] = bundle;
  File(_definesPath(id)).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(defines)}\n',
  );

  File('flavorizr.yaml').writeAsStringSync('''
  $id:
    app:
      name: "$name"
      icon: "flavors/$id/icon.png"
    android:
      applicationId: "$bundle"
      firebase:
        config: "flavors/$id/firebase/google-services.json"
    ios:
      bundleId: "$bundle"
      firebase:
        config: "flavors/$id/firebase/GoogleService-Info.plist"
''', mode: FileMode.append);

  stdout.writeln('''
Created flavors/$id and added it to flavorizr.yaml.

Before it can be built, in flavors/$id/:
  1. dart_defines.json  fill in SUPABASE_URL, SUPABASE_ANON_KEY, every
                        FIREBASE_* value, BRAND_LINK_ORIGIN and the colours.
  2. firebase/          add google-services.json and GoogleService-Info.plist
                        from the client's Firebase project.
  3. icon.png           replace with the client's 1024x1024 app icon.
  4. web/               optional: favicon.png, icons/, .well-known/.

Then generate the native side and build:
  dart pub global run flutter_flavorizr -f
  dart run tool/client.dart build $id apk
''');
}
