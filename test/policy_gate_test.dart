import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/pending_policy.dart';
import 'package:multi_vendor/core/models/profile.dart';
import 'package:multi_vendor/features/auth/auth_cubit.dart';

/// Terms only mean something if the gate is exact in both directions: a
/// partner who has not signed must be stopped, and one who has must not be
/// stopped again by accident. The server decides *what* is owed; this pins
/// how the app reacts to that answer.
void main() {
  const policy = PendingPolicy(
    key: 'vendor-terms',
    version: 1,
    titleEn: 'Partner Restaurant Terms',
    bodyEn: 'body',
  );

  AppAuthState stateWith({
    PendingPolicy? pending,
    AuthStatus status = AuthStatus.authenticated,
  }) => AppAuthState(
    status: status,
    profile: const Profile(
      id: 'u1',
      fullName: 'Store',
      role: UserRole.vendor,
      phone: '01000000000',
    ),
    pendingPolicy: pending,
  );

  test('an outstanding document stops the partner', () {
    expect(stateWith(pending: policy).needsPolicyAcceptance, isTrue);
  });

  test('nothing outstanding lets them through', () {
    expect(stateWith().needsPolicyAcceptance, isFalse);
  });

  test('a signed-out session is never gated', () {
    expect(
      stateWith(
        pending: policy,
        status: AuthStatus.unauthenticated,
      ).needsPolicyAcceptance,
      isFalse,
    );
  });

  test('clearing the policy is what dismisses the gate', () {
    final gated = stateWith(pending: policy);
    expect(
      gated.copyWith(clearPendingPolicy: true).needsPolicyAcceptance,
      isFalse,
    );
  });

  test('an unrelated copyWith does not silently drop the gate', () {
    // `copyWith(busy: true)` runs on every accept attempt. If it lost the
    // pending policy, a failed acceptance would let the partner straight in.
    final gated = stateWith(pending: policy);
    expect(gated.copyWith(busy: true).needsPolicyAcceptance, isTrue);
  });

  test(
    'version is part of identity, so a bumped version is a new document',
    () {
      const v2 = PendingPolicy(
        key: 'vendor-terms',
        version: 2,
        titleEn: 'Partner Restaurant Terms',
        bodyEn: 'body',
      );
      expect(policy, isNot(equals(v2)));
    },
  );

  test('the localized body falls back to English when Arabic is absent', () {
    expect(policy.body('ar'), 'body');
  });
}
