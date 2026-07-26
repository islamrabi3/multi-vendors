import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/profile.dart';
import '../../core/models/vendor.dart';
import '../../core/repositories/auth_repository.dart';

enum AuthStatus { unknown, unauthenticated, authenticated }

class AppAuthState extends Equatable {
  const AppAuthState({
    this.status = AuthStatus.unknown,
    this.profile,
    this.vendor,
    this.busy = false,
    this.error,
    this.info,
  });

  final AuthStatus status;
  final Profile? profile;

  /// The store owned by this user (vendor role only).
  final Vendor? vendor;
  final bool busy;
  final String? error;
  final String? info;

  bool get needsVendorOnboarding =>
      status == AuthStatus.authenticated &&
      profile?.role == UserRole.vendor &&
      vendor == null;

  AppAuthState copyWith({
    AuthStatus? status,
    Profile? profile,
    Vendor? vendor,
    bool? busy,
    String? error,
    String? info,
    bool clearMessages = false,
    bool clearVendor = false,
    bool clearProfile = false,
  }) =>
      AppAuthState(
        status: status ?? this.status,
        profile: clearProfile ? null : (profile ?? this.profile),
        vendor: clearVendor ? null : (vendor ?? this.vendor),
        busy: busy ?? this.busy,
        error: clearMessages ? null : error,
        info: clearMessages ? null : info,
      );

  @override
  List<Object?> get props => [status, profile, vendor, busy, error, info];
}

class AuthCubit extends Cubit<AppAuthState> {
  AuthCubit(this._repository) : super(const AppAuthState()) {
    _subscription = _repository.onAuthStateChange.listen((_) => _refresh());
    _refresh();
  }

  final AuthRepository _repository;
  StreamSubscription<dynamic>? _subscription;

  Future<void> _refresh() async {
    if (_repository.currentSession == null) {
      emit(const AppAuthState(status: AuthStatus.unauthenticated));
      return;
    }
    try {
      final profile = await _repository.fetchMyProfile();
      if (profile == null) {
        emit(const AppAuthState(status: AuthStatus.unauthenticated));
        return;
      }
      final vendor = profile.role == UserRole.vendor
          ? await _repository.fetchMyVendor()
          : null;
      emit(AppAuthState(
        status: AuthStatus.authenticated,
        profile: profile,
        vendor: vendor,
      ));
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

  /*
  Future<void> signInWithGoogle() async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      await _repository.signInWithGoogle();
      emit(state.copyWith(busy: false));
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }

  Future<void> signInWithApple() async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      await _repository.signInWithApple();
      emit(state.copyWith(busy: false));
    } catch (error) {
      emit(state.copyWith(busy: false, error: error.toString()));
    }
  }
  */

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
  }) async {
    emit(state.copyWith(busy: true, clearMessages: true));
    try {
      final hasSession = await _repository.signUp(
        email: email.trim(),
        password: password,
        fullName: fullName.trim(),
        phone: phone.trim(),
        role: role,
      );
      emit(state.copyWith(
        busy: false,
        info: hasSession
            ? null
            : 'Account created. Check your email to confirm, then sign in.',
      ));
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
    return super.close();
  }
}
