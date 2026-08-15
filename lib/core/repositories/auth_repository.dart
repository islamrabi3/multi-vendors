import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/pending_policy.dart';
import '../models/profile.dart';
import '../models/vendor.dart';
import '../supabase_client.dart';

/// What currently stands between the user and closing their account.
class AccountDeletionBlockers {
  const AccountDeletionBlockers({
    required this.activeOrders,
    required this.walletBalance,
  });

  /// Orders still in flight — as customer, driver, or through a store they own.
  final int activeOrders;

  /// Money that would be forfeited. Not a blocker on its own; the user is
  /// asked to confirm it.
  final double walletBalance;

  bool get hasActiveOrders => activeOrders > 0;
  bool get hasBalance => walletBalance > 0;
}

/// The identity documents a driver applicant uploads.
///
/// Keyed by the column each one lands in, so the upload loop and the review
/// queue cannot disagree about which photo is which.
class DriverDocuments {
  const DriverDocuments({
    this.idCardFront,
    this.idCardBack,
    this.licenseFront,
    this.licenseBack,
  });

  final XFile? idCardFront;
  final XFile? idCardBack;
  final XFile? licenseFront;
  final XFile? licenseBack;

  Map<String, XFile?> get byColumn => {
    'id_card_url': idCardFront,
    'id_card_back_url': idCardBack,
    'license_url': licenseFront,
    'license_back_url': licenseBack,
  };

  bool get isNotEmpty => byColumn.values.any((f) => f != null);

  /// Every document present. What a complete application looks like.
  bool get isComplete => byColumn.values.every((f) => f != null);
}

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
    DriverDocuments? documents,
  }) async {
    final response = await supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName, 'phone': phone, 'role': role.name},
    );
    final session = response.session;

    // The driver row is created by the handle_new_user trigger, so the
    // documents have somewhere to attach the moment the session exists.
    //
    // With email confirmation on there is no session yet and nothing can be
    // uploaded under the applicant's own id, so the driver is asked for them
    // again after the first sign-in — rather than them being dropped on the
    // floor, which is what happened to every applicant before this.
    if (session != null && documents != null && documents.isNotEmpty) {
      await uploadDriverDocuments(session.user.id, documents);
    }
    return session != null;
  }

  /// Stores an applicant's documents in the private bucket and records their
  /// paths on the driver row, which is what the admin review queue reads.
  ///
  /// A failed upload must not fail the signup: the account already exists by
  /// this point, so throwing would leave someone who cannot sign in and cannot
  /// retry. Whatever lands is kept and the rest is asked for again.
  Future<void> uploadDriverDocuments(
    String driverId,
    DriverDocuments documents,
  ) async {
    final updates = <String, String>{};
    for (final entry in documents.byColumn.entries) {
      final file = entry.value;
      if (file == null) continue;
      try {
        final bytes = await file.readAsBytes();
        final dot = file.name.lastIndexOf('.');
        final extension = dot == -1 ? 'jpg' : file.name.substring(dot + 1);
        // First path segment is the owner: the storage policies key off it.
        final path =
            '$driverId/${entry.key}-'
            '${DateTime.now().millisecondsSinceEpoch}.$extension';
        await supabase.storage
            .from('driver-documents')
            .uploadBinary(
              path,
              bytes,
              fileOptions: const FileOptions(upsert: true),
            );
        updates[entry.key] = path;
      } catch (_) {
        // Keep going: three documents that arrive beat none.
      }
    }
    if (updates.isEmpty) return;
    await supabase.from('drivers').update(updates).eq('id', driverId);
  }

  Future<void> signOut() => supabase.auth.signOut();

  /// What currently stands between the user and closing their account, so the
  /// app can explain rather than just refuse.
  Future<AccountDeletionBlockers> accountDeletionBlockers() async {
    final data = await supabase.rpc('account_deletion_blockers');
    final map = (data as Map).cast<String, dynamic>();
    return AccountDeletionBlockers(
      activeOrders: ((map['active_orders'] as num?) ?? 0).toInt(),
      walletBalance: double.tryParse('${map['wallet_balance'] ?? 0}') ?? 0,
    );
  }

  /// Closes the caller's own account, then ends the session.
  ///
  /// [forfeitBalance] is the user's answer to the wallet warning; the server
  /// refuses without it while a balance remains, so the money is never taken
  /// silently.
  Future<void> deleteOwnAccount({bool forfeitBalance = false}) async {
    await supabase.rpc(
      'delete_own_account',
      params: {'p_forfeit_balance': forfeitBalance},
    );
    await supabase.auth.signOut();
  }

  /// Where the provider sends the user back to.
  ///
  /// On web this has to be the origin they actually started from. Passing null
  /// made Supabase fall back to the project's single configured Site URL — so
  /// a sign-in started on the deployed site came back to `localhost:3000` and
  /// died there. `Uri.base` is the page currently open, so a dev build and the
  /// hosted one each return to themselves.
  ///
  /// Every origin used here must also be listed under Auth > URL Configuration
  /// > Redirect URLs in the Supabase dashboard, or the provider refuses it.
  ///
  /// Native keeps the deep link; there is no origin to speak of.
  static String get _oauthRedirect =>
      kIsWeb ? Uri.base.origin : 'io.supabase.multivendor://login-callback';

  /// Browser-based OAuth. The provider must be enabled in the Supabase
  /// dashboard (Auth > Providers) and the redirect scheme registered in
  /// AndroidManifest.xml / Info.plist. supabase_flutter completes the
  /// session from the callback automatically.
  ///
  /// inAppBrowserView = Chrome Custom Tabs / SFSafariViewController: renders
  /// inside the app but stays a real system browser surface. A plain WebView
  /// is not an option — Google rejects OAuth from embedded web views
  /// (403: disallowed_useragent).
  Future<void> signInWithGoogle() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: _oauthRedirect,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.inAppBrowserView,
    );
  }

  /// Only offered where it belongs — see `supportsAppleSignIn`.
  Future<void> signInWithApple() async {
    await supabase.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: _oauthRedirect,
      authScreenLaunchMode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.inAppBrowserView,
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

  /// The one policy document this partner still owes, or null.
  ///
  /// The server decides — it knows the role, the current version, and what
  /// has already been signed. Asking the client to work that out would mean
  /// trusting the client to enforce its own gate.
  Future<PendingPolicy?> fetchPendingPolicy() async {
    try {
      final data = await supabase.rpc('pending_policy');
      return PendingPolicy.fromMap(
        data == null ? null : Map<String, dynamic>.from(data as Map),
      );
    } catch (_) {
      // A failure here must not block sign-in. Worst case the gate is missed
      // for this session and applies on the next one.
      return null;
    }
  }

  Future<void> acceptPolicy(String key) =>
      supabase.rpc('accept_policy', params: {'p_key': key});

  /// The caller's own profile row, live.
  ///
  /// Blocking is enforced by RLS on every write, but the app used to read the
  /// profile once at sign-in — so an account blocked mid-session kept every
  /// screen it was on and met raw policy refusals instead of being told
  /// anything. Watching the row is what turns a block into something the user
  /// actually sees.
  Stream<Profile?> watchMyProfile() {
    final userId = currentUser?.id;
    if (userId == null) return Stream.value(null);
    return supabase
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', userId)
        .map((rows) => rows.isEmpty ? null : Profile.fromMap(rows.first));
  }

  /// Watches the signed-in owner's store row.
  ///
  /// Same reason as [watchMyProfile]: approval and suspension are decided on
  /// an admin's screen, and the store was only read at sign-in — so a vendor
  /// approved while the app was open kept seeing "waiting for verification"
  /// and kept being refused, until they signed out and back in.
  Stream<Vendor?> watchMyVendor() {
    final userId = currentUser?.id;
    if (userId == null) return Stream.value(null);
    return supabase
        .from('vendors')
        .stream(primaryKey: ['id'])
        .eq('owner_id', userId)
        .map((rows) => rows.isEmpty ? null : Vendor.fromMap(rows.first));
  }

  Future<Vendor?> fetchMyVendor() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    final data = await supabase
        // The opening hours ride along: the dashboard has to tell the owner
        // "your switch is on but you are outside today's hours", which needs
        // the timetable, not just `is_open`.
        .from('vendors')
        .select('*, vendor_schedules(*)')
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
