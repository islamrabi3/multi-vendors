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
