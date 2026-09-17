import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, FunctionException;

import '../supabase_client.dart';

/// A picked image waiting to be uploaded.
typedef PickedImage = ({String name, Uint8List bytes});

/// An admin creating a store or driver account on someone's behalf — the
/// login and everything the account needs — through the
/// `admin-create-account` edge function.
class AccountOnboardingRepository {
  /// Returns the new store's id.
  Future<String> createVendorAccount({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? username,
    required bool approve,
    required Map<String, dynamic> store,
    PickedImage? logo,
    PickedImage? cover,
  }) async {
    final logoUrl = logo == null ? null : await _uploadStoreImage('logo', logo);
    final coverUrl = cover == null
        ? null
        : await _uploadStoreImage('cover', cover);
    final data = await _invoke({
      'kind': 'vendor',
      'email': email.trim(),
      'password': password,
      'full_name': fullName.trim(),
      'phone': phone?.trim(),
      'username': username?.trim(),
      'approve': approve,
      'vendor': {...store, 'logo_url': ?logoUrl, 'cover_url': ?coverUrl},
    });
    return data['vendor_id'] as String;
  }

  /// Returns the new driver's user id. Documents are uploaded after the
  /// account exists, into the driver's own folder.
  Future<String> createDriverAccount({
    required String email,
    required String password,
    required String fullName,
    String? phone,
    String? username,
    required bool approve,
    String? vehicleType,
    Map<String, PickedImage> documents = const {},
  }) async {
    final data = await _invoke({
      'kind': 'driver',
      'email': email.trim(),
      'password': password,
      'full_name': fullName.trim(),
      'phone': phone?.trim(),
      'username': username?.trim(),
      'approve': approve,
      'driver': {'vehicle_type': ?vehicleType},
    });
    final driverId = data['user_id'] as String;

    final updates = <String, String>{};
    for (final MapEntry(key: column, value: file) in documents.entries) {
      final dot = file.name.lastIndexOf('.');
      final extension = dot == -1 ? 'jpg' : file.name.substring(dot + 1);
      // First path segment is the owner: the storage policies key off it.
      final path =
          '$driverId/$column-${DateTime.now().millisecondsSinceEpoch}.$extension';
      await supabase.storage
          .from('driver-documents')
          .uploadBinary(
            path,
            file.bytes,
            fileOptions: const FileOptions(upsert: true),
          );
      updates[column] = path;
    }
    if (updates.isNotEmpty) {
      await supabase.from('drivers').update(updates).eq('id', driverId);
    }
    return driverId;
  }

  /// What an operator needs to see about the person behind an account: the
  /// login name and the email address, neither of which is on `profiles`.
  Future<AccountLogin?> fetchLogin(String userId) async {
    final data = await supabase.rpc(
      'admin_account_login',
      params: {'p_user_id': userId},
    );
    final row = (data as List?)?.firstOrNull as Map<String, dynamic>?;
    if (row == null) return null;
    return AccountLogin(
      email: (row['email'] as String?) ?? '',
      username: (row['username'] as String?) ?? '',
      fullName: (row['full_name'] as String?) ?? '',
      phone: (row['phone'] as String?) ?? '',
    );
  }

  /// Changes the login behind a store or driver: the parts of an account that
  /// only the service role may write.
  ///
  /// Only what is passed is changed, so an operator resetting a password does
  /// not have to retype an email address to leave it alone. [phone] is the
  /// exception: passing an empty string clears it, which is why it is only
  /// sent when the caller means to write it.
  Future<List<String>> updateAccount({
    required String userId,
    String? email,
    String? password,
    String? username,
    String? fullName,
    String? phone,
  }) async {
    final data = await _invoke({
      'user_id': userId,
      'email': ?email?.trim(),
      'password': ?password,
      'username': ?username?.trim(),
      'full_name': ?fullName?.trim(),
      'phone': ?phone?.trim(),
    }, function: 'admin-update-account', failure: 'UPDATE_FAILED');
    return ((data['changed'] as List?) ?? const [])
        .map((entry) => '$entry')
        .toList();
  }

  Future<String> _uploadStoreImage(String kind, PickedImage image) async {
    final safe = image.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final path =
        'onboarding/$kind-${DateTime.now().millisecondsSinceEpoch}-$safe';
    await supabase.storage
        .from('vendor-assets')
        .uploadBinary(path, image.bytes);
    return supabase.storage.from('vendor-assets').getPublicUrl(path);
  }

  /// The function answers errors with `{error: CODE}` and a non-2xx status,
  /// which the client raises as [FunctionException]; both shapes end up as an
  /// exception carrying the code, so the UI can say which rule failed.
  Future<Map<String, dynamic>> _invoke(
    Map<String, dynamic> body, {
    String function = 'admin-create-account',
    String failure = 'CREATE_FAILED',
  }) async {
    try {
      final response = await supabase.functions.invoke(function, body: body);
      final data = (response.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['error'] != null) throw Exception(data['error']);
      return data;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['error'] : null;
      throw Exception(code ?? failure);
    }
  }
}

/// The login behind a store or driver, as an admin screen shows it.
class AccountLogin {
  const AccountLogin({
    required this.email,
    required this.username,
    required this.fullName,
    required this.phone,
  });

  final String email;
  final String username;
  final String fullName;
  final String phone;
}
