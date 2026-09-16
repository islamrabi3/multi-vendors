import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/utils/email.dart';

/// The signup form used to accept anything with an `@` in it and let the auth
/// server do the refusing — which it did with a message the app could only
/// show as a generic failure. These are the addresses people actually mistype.
void main() {
  group('isValidEmail', () {
    test('accepts ordinary addresses', () {
      expect(isValidEmail('sara@example.com'), isTrue);
      expect(isValidEmail('a.b+tag@mail.co.uk'), isTrue);
      expect(isValidEmail('  sara@example.com  '), isTrue);
    });

    test('refuses what the auth server would refuse', () {
      expect(isValidEmail('sara@'), isFalse);
      expect(isValidEmail('@example.com'), isFalse);
      expect(isValidEmail('sara@example'), isFalse, reason: 'no dot in domain');
      expect(isValidEmail('sara @example.com'), isFalse);
      expect(isValidEmail('sara@example..com'), isFalse);
      expect(isValidEmail('sara@-example.com'), isFalse);
      expect(isValidEmail('sara'), isFalse);
      expect(isValidEmail(''), isFalse);
      expect(isValidEmail(null), isFalse);
    });
  });

  test('normalizeEmail trims and lowercases', () {
    expect(normalizeEmail('  Sara@Example.COM '), 'sara@example.com');
  });
}
