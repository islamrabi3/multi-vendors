import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';

class AuthRepository {
  Stream<AuthState> get onAuthStateChange => supabase.auth.onAuthStateChange;

  Session? get currentSession => supabase.auth.currentSession;
  User? get currentUser => supabase.auth.currentUser;

  Future<void> signIn({required String email, required String password}) =>
      supabase.auth.signInWithPassword(email: email, password: password);

  /// Returns true when a session was created immediately (email confirmation
  /// disabled); false when the user must confirm their email first.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required UserRole role,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone, 'role': role.name},
    );
    return response.session != null;
  }

  Future<void> signOut() => supabase.auth.signOut();

  /// Browser-based OAuth. The provider must be enabled in the Supabase
  /// dashboard (Auth > Providers) and the redirect scheme registered in
  /// AndroidManifest.xml / Info.plist. supabase_flutter completes the
  /// session from the deep-link callback automatically.
  ///
  /// inAppBrowserView = Chrome Custom Tabs / SFSafariViewController: renders
  /// inside the app but stays a real system browser surface. A plain WebView
  /// is not an option — Google rejects OAuth from embedded web views
  /// (403: disallowed_useragent).
  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? null : 'io.supabase.multivendor://login-callback',
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    );
  }

  Future<void> signInWithApple() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: kIsWeb ? null : 'io.supabase.multivendor://login-callback',
      authScreenLaunchMode:
          kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
    );
  }

  /// Settles the role of a social sign-up — either the one picked on the signup
  /// screen, or the one answered in the role picker on first launch.
  ///
  /// Identity providers carry no role, so a Google/Apple account is created as
  /// an unconfirmed customer. The RPC only accepts customer/vendor/driver and
  /// only while the account is brand-new, so this can never reach admin nor
  /// convert an established account.
  Future<void> setSignupRole(UserRole role) =>
      supabase.rpc('set_signup_role', params: {'p_role': role.name});

  /// Self-service edit of the fields a user owns. `role` is rejected by a
  /// database trigger, so this cannot be widened by accident.
  Future<Profile> updateMyProfile({
    required String fullName,
    String? phone,
  }) async {
    final data = await supabase
        .from('profiles')
        .update({
          'full_name': fullName,
          'phone': (phone == null || phone.isEmpty) ? null : phone,
        })
        .eq('id', currentUser!.id)
        .select()
        .single();
    return Profile.fromMap(data);
  }

  /// The three counters on the profile header. Each is a server-side count —
  /// RLS already scopes orders and favourites to this user — so nothing has to
  /// be downloaded just to be counted.
  Future<({int orders, int favorites, int points})> fetchMyStats() async {
    final userId = currentUser?.id;
    if (userId == null) return (orders: 0, favorites: 0, points: 0);
    final results = await Future.wait<Object?>([
      supabase.from('orders').count().eq('customer_id', userId),
      supabase.from('favorites').count().eq('user_id', userId),
      supabase
          .from('loyalty_points')
          .select('points')
          .eq('user_id', userId)
          .maybeSingle(),
    ]);
    final loyalty = results[2] as Map<String, dynamic>?;
    return (
      orders: results[0] as int,
      favorites: results[1] as int,
      points: ((loyalty?['points'] as num?) ?? 0).toInt(),
    );
  }

  Future<Profile?> fetchMyProfile() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final data = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return data == null ? null : Profile.fromMap(data);
  }

  Future<Vendor?> fetchMyVendor() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final data = await supabase
        .from('vendors')
        .select()
        .eq('owner_id', userId)
        .maybeSingle();
    return data == null ? null : Vendor.fromMap(data);
  }

  Future<Vendor> createVendor(Map<String, dynamic> values) async {
    final data = await supabase
        .from('vendors')
        .insert({...values, 'owner_id': currentUser!.id})
        .select()
        .single();
    return Vendor.fromMap(data);
  }
}
