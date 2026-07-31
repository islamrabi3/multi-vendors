import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/common.dart';
import 'l10n_extension.dart';

/// Opens the system dialer for [phone].
///
/// Every call button in the app goes through here because a raw
/// `Uri(scheme: 'tel', path: phone)` breaks on the numbers we actually store:
/// spaces and dashes are percent-encoded into the dialled string, and on
/// Android the launch also needs `externalApplication` plus a `<queries>` entry
/// for the dialer (see AndroidManifest.xml) or it silently resolves to nothing.
Future<void> callPhone(BuildContext context, String? phone) async {
  final digits = _dialable(phone);
  if (digits == null) {
    showSnack(context, context.l10n.couldNotStartTheCall, error: true);
    return;
  }
  var launched = false;
  try {
    launched = await launchUrl(
      Uri(scheme: 'tel', path: digits),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    launched = false;
  }
  if (!launched && context.mounted) {
    showSnack(context, context.l10n.couldNotStartTheCall, error: true);
  }
}

/// Keeps only what a dialer accepts: digits, a leading +, and the DTMF
/// separators. Returns null when nothing dialable is left.
String? _dialable(String? phone) {
  if (phone == null) return null;
  final trimmed = phone.trim();
  final plus = trimmed.startsWith('+') ? '+' : '';
  final rest = trimmed.replaceAll(RegExp(r'[^0-9*#,;]'), '');
  if (rest.isEmpty) return null;
  return '$plus$rest';
}
