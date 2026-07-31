// Generates the Apple Sign-In client secret (ES256 JWT) that Supabase's
// Apple provider expects in its "Secret Key" field.
//
// Usage:
//   dart run tool/generate_apple_secret.dart <TEAM_ID> <SERVICES_ID> <P8_PATH>
//
// Apple caps the secret's lifetime at 6 months — rerun this and update
// Supabase before it expires.
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

void main(List<String> args) {
  if (args.length != 3) {
    stderr.writeln(
        'Usage: dart run tool/generate_apple_secret.dart <TEAM_ID> <SERVICES_ID> <P8_PATH>');
    exit(1);
  }
  final teamId = args[0];
  final servicesId = args[1];
  final pem = File(args[2]).readAsStringSync();

  const sixMonths = Duration(days: 180);
  final jwt = JWT(
    {
      'iss': teamId,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'exp': DateTime.now().add(sixMonths).millisecondsSinceEpoch ~/ 1000,
      'aud': 'https://appleid.apple.com',
      'sub': servicesId,
    },
    header: {
      'alg': 'ES256',
      'kid': RegExp(r'AuthKey_([A-Z0-9]+)\.p8')
              .firstMatch(args[2])
              ?.group(1) ??
          (throw ArgumentError(
              'Could not read Key ID from filename; expected AuthKey_<KEYID>.p8')),
    },
  );

  final token = jwt.sign(ECPrivateKey(pem), algorithm: JWTAlgorithm.ES256);
  stdout.writeln(token);
}
