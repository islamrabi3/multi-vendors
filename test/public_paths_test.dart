import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/app/router.dart';

/// The signup form links to the terms and the privacy policy directly above
/// its submit button. A signed-out visitor tapping either was redirected to
/// `/login` — the redirect only ever allowed `/login` and `/signup` while
/// unauthenticated, so the one moment those documents exist for was the one
/// moment they could not be opened.
///
/// This pins the rule rather than the wording: the set is easy to trim by
/// accident when someone tidies the router.
void main() {
  test('the legal pages are reachable without an account', () {
    for (final path in ['/terms', '/privacy', '/about']) {
      expect(
        isPubliclyReadablePath(path),
        isTrue,
        reason:
            '$path is linked from the signup form and from the database '
            'read policy, which grants anon for exactly this reason',
      );
    }
  });

  test('nothing else leaks through the signed-out gate', () {
    for (final path in [
      '/home',
      '/admin-app/overview',
      '/vendor-app/dashboard',
      '/checkout',
      '/wallet',
    ]) {
      expect(isPubliclyReadablePath(path), isFalse, reason: path);
    }
  });
}
