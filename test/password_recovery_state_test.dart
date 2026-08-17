import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/features/auth/auth_cubit.dart';

/// `AuthCubit._refresh()` re-fetches the profile on every auth event and
/// rebuilds `AppAuthState` from scratch with the `AppAuthState(...)`
/// constructor — not `copyWith`. That constructor defaults every field it is
/// not given, `passwordRecovery` included.
///
/// The reset-password gate depends on that flag surviving exactly the refresh
/// that fires right after it is set (the recovery event itself triggers
/// `_refresh()`), so a state class that does not thread it through would open
/// `/reset-password` for one frame and then silently let the recovery session
/// fall through into the app as an ordinary sign-in — the bug this pins.
void main() {
  test('passwordRecovery defaults to false', () {
    expect(const AppAuthState().passwordRecovery, isFalse);
  });

  test('copyWith preserves passwordRecovery when the caller does not touch it', () {
    final flagged = const AppAuthState().copyWith(passwordRecovery: true);
    expect(flagged.passwordRecovery, isTrue);

    // The kind of incidental update `_refresh()` and other methods make —
    // busy toggles, error clears — none of which mention the flag.
    final afterUnrelatedUpdate = flagged.copyWith(busy: true);
    expect(
      afterUnrelatedUpdate.passwordRecovery,
      isTrue,
      reason: 'an update that never mentions passwordRecovery must not '
          'silently clear it',
    );
  });

  test('copyWith can still explicitly clear it', () {
    final flagged = const AppAuthState().copyWith(passwordRecovery: true);
    final cleared = flagged.copyWith(passwordRecovery: false);
    expect(cleared.passwordRecovery, isFalse);
  });
}
