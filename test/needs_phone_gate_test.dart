import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/profile.dart';
import 'package:multi_vendor/features/auth/auth_cubit.dart';

/// An OAuth account arrives with a name and an email and no phone, so every
/// order it places has a customer nobody can call. `needsPhone` is the gate
/// that stops that, and the router turns it into a redirect — which makes it
/// exactly the kind of condition that traps someone on a screen forever if it
/// is wrong in either direction.
///
/// The two failure modes worth pinning: letting a rider through without a
/// number (the bug), and holding an admin hostage to a field nobody rings
/// them on (the over-correction).
void main() {
  AppAuthState stateFor({
    required UserRole role,
    String? phone,
    bool roleConfirmed = true,
    AuthStatus status = AuthStatus.authenticated,
  }) => AppAuthState(
    status: status,
    profile: Profile(
      id: 'u1',
      fullName: 'Someone',
      role: role,
      phone: phone,
      roleConfirmed: roleConfirmed,
    ),
  );

  test('a customer, vendor or driver with no phone is stopped', () {
    for (final role in [UserRole.customer, UserRole.vendor, UserRole.driver]) {
      expect(
        stateFor(role: role, phone: null).needsPhone,
        isTrue,
        reason: '$role with a null phone must be asked',
      );
      expect(
        stateFor(role: role, phone: '   ').needsPhone,
        isTrue,
        reason: '$role with a blank phone is no more reachable than a null one',
      );
    }
  });

  test('a phone on file clears the gate', () {
    expect(
      stateFor(role: UserRole.customer, phone: '01001234567').needsPhone,
      isFalse,
    );
  });

  test('an admin is never asked, even with no phone', () {
    // The console is what fixes everything else; locking it behind a field
    // nobody calls an admin about would be the worse bug.
    expect(stateFor(role: UserRole.admin, phone: null).needsPhone, isFalse);
  });

  test('the role picker comes first', () {
    // roleConfirmed == false means the role is still unanswered, and the role
    // decides whether a phone is required at all — asking in the other order
    // could demand a number from someone about to become an admin.
    expect(
      stateFor(
        role: UserRole.customer,
        phone: null,
        roleConfirmed: false,
      ).needsPhone,
      isFalse,
    );
  });

  test('a signed-out session is not asked for anything', () {
    expect(
      stateFor(
        role: UserRole.customer,
        phone: null,
        status: AuthStatus.unauthenticated,
      ).needsPhone,
      isFalse,
    );
    expect(
      stateFor(
        role: UserRole.customer,
        phone: null,
        status: AuthStatus.unknown,
      ).needsPhone,
      isFalse,
    );
  });
}
