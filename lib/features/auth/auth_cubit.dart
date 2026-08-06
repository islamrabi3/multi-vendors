import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthChangeEvent;
import 'package:url_launcher/url_launcher.dart' show closeInAppWebView;

import '../../core/models/profile.dart';
import '../../core/models/vendor.dart';
import '../../core/repositories/admin_roles_repository.dart';
import '../../core/repositories/auth_repository.dart';
import '../../core/services/notification_service.dart';
import 'screens/app_onboarding_screen.dart' show AppOnboarding;

enum AuthStatus { unknown, unauthenticated, authenticated }

class AppAuthState extends Equatable {
  const AppAuthState({
    this.status = AuthStatus.unknown,
    this.profile,
    this.vendor,
    this.busy = false,
    this.error,
    this.info,
    this.permissions = const [],
  });

  final AuthStatus status;
  final Profile? profile;

  /// The store owned by this user (vendor role only).
  final Vendor? vendor;
  final bool busy;
  final String? error;
  final String? info;

  /// What this admin may do. `['*']` is unrestricted; empty for every
  /// non-admin role.
  ///
  /// Only ever used to hide controls. Every action is enforced again on the
  /// server, so a stale copy of this list grants nothing.
  final List<String> permissions;

  /// True when the signed-in admin holds [key], or holds everything.
  bool can(String key) =>
      permissions.contains('*') || permissions.contains(key);

  /// A social sign-up that has not answered the role picker yet. Checked before
  /// vendor onboarding, since the answer decides whether onboarding applies.
  bool get needsRoleChoice =>
      status == AuthStatus.authenticated && profile?.roleConfirmed == false;

  bool get needsVendorOnboarding =>
      status == AuthStatus.authenticated &&
      profile?.roleConfirmed != false &&
      profile?.role == UserRole.vendor &&
      vendor == null;

  AppAuthState copyWith({
    AuthStatus? status,
    Profile? profile,
    Vendor? vendor,
    bool? busy,
    String? error,
    String? info,
    List<String>? permissions,
    bool clearMessages = false,
    bool clearVendor = false,
    bool clearProfile = false,
  }) => AppAuthState(
    status: status ?? this.status,
    profile: clearProfile ? null : (profile ?? this.profile),
    vendor: clearVendor ? null : (vendor ?? this.vendor),
    busy: busy ?? this.busy,
    error: clearMessages ? null : error,
    info: clearMessages ? null : info,
    permissions: permissions ?? this.permissions,
  );

  @override
  List<Object?> get props => [
    status,
    profile,
    vendor,
    busy,
    error,
    info,
    permissions,
  ];
}

class AuthCubit extends Cubit<AppAuthState> {
  AuthCubit(this._repository) : super(const AppAuthState()) {
    _subscription = _repository.onAuthStateChange.listen((event) async {
      final signedIn = event.event == AuthChangeEvent.signedIn;
      // OAuth runs in an in-app browser view (Custom Tab / Safari VC); once
      // the deep link lands and the session exists, close that view so the
      // user is back in the app without tapping Done.
      if (!kIsWeb && signedIn) {
        closeInAppWebView().catchError((_) {});
      }
      // The FCM token can only be written to the user's profile once a
      // session exists — at app start NotificationService runs before
      // login and its sync is a no-op.
      if (signedIn || event.event == AuthChangeEvent.initialSession) {
        NotificationService.instance.syncFcmToken();
      }
      // Must settle before _refresh, or the router would route the user to
      // the customer home before their claimed role is visible.
      if (signedIn) await _applyPendingSignupRole();
      _refresh();
    });
    _refresh();
  }

  final AuthRepository _repository;
  final AdminRolesRepository _adminRoles = AdminRolesRepository();
  StreamSubscription<dynamic>? _subscription;
  StreamSubscription<Profile?>? _profileSubscription;
  StreamSubscription<Vendor?>? _vendorSubscription;

  /// Watches the signed-in user's own profile row.
  ///
  /// Without this a block only took hold on the next cold start: the server
  /// refused the writes but the app carried on, so the user met unexplained
  /// failures — "error adding a category" on the vendor side, a review that
  /// would not post — rather than the blocked screen. The router already reads
  /// `profile.isLockedOut`, so re-emitting the row is the whole fix.
  void _watchProfile() {
    _profileSubscription?.cancel();
    _profileSubscription = _repository.watchMyProfile().listen(
      (profile) {
        if (profile == null || isClosed) return;
        if (state.status != AuthStatus.authenticated) return;
        if (profile == state.profile) return;
        // A role change has to go the long way round: the vendor record hangs
        // off it, and the shell for the new role needs it loaded.
        if (profile.role != state.profile?.role) {
          _refresh();
          return;
        }
        emit(state.copyWith(profile: profile));
      },
      // A dropped socket must not sign anyone out; the next reconnect or cold
      // start picks the row up again.
      onError: (Object error) => debugPrint('Profile watch dropped: $error'),
    );
  }

  /// Watches the owner's store row, so an approval or suspension decided by an
  /// admin reaches the dashboard while it is open rather than at next sign-in.
  void _watchVendor() {
    _vendorSubscription?.cancel();
    _vendorSubscription = _repository.watchMyVendor().listen(
      (vendor) async {
        if (vendor == null || isClosed) return;
        if (vendor == state.vendor) return;
        // The row from the socket carries no opening hours: a realtime stream
        // cannot embed a related table. Taking it as-is left the dashboard
        // flipping between "closed — outside hours" and "open" depending on
        // which of the two sources spoke last, so the event is treated as a
        // signal to re-read the whole thing.
        try {
          final full = await _repository.fetchMyVendor();
          if (isClosed || full == null) return;
          if (full == state.vendor) return;
          emit(state.copyWith(vendor: full));
        } catch (error) {
          debugPrint('Vendor re-read failed: $error');
        }
      },
      onError: (Object error) => debugPrint('Vendor watch dropped: $error'),
    );
  }

  Future<void> _refresh() async {
    if (_repository.currentSession == null) {
      _profileSubscription?.cancel();
      _profileSubscription = null;
      _vendorSubscription?.cancel();
      _vendorSubscription = null;
      emit(const AppAuthState(status: AuthStatus.unauthenticated));
      return;
    }
    try {
      final profile = await _repository.fetchMyProfile();
      if (profile == null) {
        emit(const AppAuthState(status: AuthStatus.unauthenticated));
        return;
      }
      // Someone with an account has obviously been past the intro; without
      // this a returning user whose flag never persisted sees the get-started
      // carousel flash between OAuth landing and the home screen.
      if (!AppOnboarding.seen) unawaited(AppOnboarding.markSeen());
      final vendor = profile.role == UserRole.vendor
          ? await _repository.fetchMyVendor()
          : null;
      // Only an admin has any, and a failure here must not block sign-in —
      // the console simply shows nothing rather than refusing to open.
      final permissions = profile.role == UserRole.admin
          ? await _adminRoles.myPermissions().catchError(
              (_) => const <String>[],
            )
          : const <String>[];
      emit(
        AppAuthState(
          status: AuthStatus.authenticated,
          profile: profile,
          vendor: vendor,
          permissions: permissions,
        ),
      );
      _watchProfile();
      // Only a store owner has a row to watch.
      if (vendor != null) _watchVendor();
    } catch (_) {
      // Keep whatever state we had; a transient network error on profile
      // fetch should not log the user out.
      if (state.status == AuthStatus.unknown) {
        emit(const AppAuthState(status: AuthStatus.unauthenticated));
      }
    }
  }

  Future<void> signIn(String email, String password) async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      await _repository.signIn(email: email.trim(), password: password);
      // onAuthStateChange triggers _refresh.
      emit(state.copyWith(busy: false));
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  /// Role picked on the signup screen, applied once the social sign-up lands.
  /// Null when signing in rather than signing up.
  UserRole? _pendingSignupRole;

  Future<void> signInWithGoogle({UserRole? signupRole}) async {
    _pendingSignupRole = signupRole;
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      await _repository.signInWithGoogle();
      emit(state.copyWith(busy: false));
    } catch (error) {
      _handleOAuthError(error);
    }
  }

  Future<void> signInWithApple({UserRole? signupRole}) async {
    _pendingSignupRole = signupRole;
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      await _repository.signInWithApple();
      emit(state.copyWith(busy: false));
    } catch (error) {
      _handleOAuthError(error);
    }
  }

  /// Social accounts arrive with no role, so a sign-up that already picked one
  /// on the signup screen applies it here and skips the picker. Failures are
  /// swallowed: the server rejects the claim for anything but a brand-new
  /// account, and the user is then simply asked by the picker instead.
  Future<void> _applyPendingSignupRole() async {
    final role = _pendingSignupRole;
    _pendingSignupRole = null;
    if (role == null) return;
    try {
      await _repository.setSignupRole(role);
    } catch (error) {
      debugPrint('Could not apply signup role $role: $error');
    }
  }

  /// Answer to the role picker shown after a social sign-up.
  Future<void> chooseRole(UserRole role) async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      await _repository.setSignupRole(role);
      await _refresh();
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  /// Name/phone edit from the profile screen.
  Future<bool> updateProfile({required String fullName, String? phone}) async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      final profile = await _repository.updateMyProfile(
        fullName: fullName.trim(),
        phone: phone?.trim(),
      );
      emit(state.copyWith(busy: false, profile: profile));
      return true;
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
      return false;
    }
  }

  /// Swallows the noise the OAuth launcher produces on the happy path.
  ///
  /// Closing the in-app browser once the deep link lands makes launchUrl
  /// report failure, and it lands here a moment before the session exists, so
  /// checking for a session right away is a race. Dismissing the provider
  /// page reaches the same place. Neither is worth a red toast, and a genuine
  /// configuration error is already visible on the provider's own page — so
  /// this only ever logs.
  void _handleOAuthError(Object error) {
    debugPrint('OAuth flow ended without a session yet: $error');
    emit(state.copyWith(busy: false));
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
    DriverDocuments? documents,
  }) async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      final hasSession = await _repository.signUp(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
        phone: phone.trim(),
        role: role,
        documents: documents,
      );
      emit(
        state.copyWith(
          busy: false,
          info: hasSession
              ? null
              : 'Account created. Check your email to confirm, then sign in.',
        ),
      );
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  Future<void> completeVendorOnboarding(Map<String, dynamic> values) async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      final vendor = await _repository.createVendor(values);
      emit(state.copyWith(busy: false, vendor: vendor));
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  void vendorUpdated(Vendor vendor) => emit(state.copyWith(vendor: vendor));

  Future<void> signOut() async {
    _profileSubscription?.cancel();
    _profileSubscription = null;
    _vendorSubscription?.cancel();
    _vendorSubscription = null;
    try {
      await _repository.signOut();
      // onAuthStateChange normally drives _refresh, but emit immediately so the
      // router redirects without waiting on the stream.
      emit(const AppAuthState(status: AuthStatus.unauthenticated));
    } catch (_) {
      // Even if the network sign-out fails, drop the local session.
      emit(const AppAuthState(status: AuthStatus.unauthenticated));
    }
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    _profileSubscription?.cancel();
    _vendorSubscription?.cancel();
    return super.close();
  }
}
