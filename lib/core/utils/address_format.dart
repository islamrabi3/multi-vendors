import 'package:flutter/material.dart';

import '../models/address.dart';
import 'l10n_extension.dart';

/// The fixed labels a customer picks from. Stored as the plain words the
/// database has always held, so older rows keep working.
enum AddressKind { home, work, other }

AddressKind addressKindOf(String label) {
  final lower = label.trim().toLowerCase();
  if (lower == 'home' || lower.contains('منزل') || lower.contains('بيت')) {
    return AddressKind.home;
  }
  if (lower == 'work' ||
      lower.contains('office') ||
      lower.contains('عمل') ||
      lower.contains('شغل') ||
      lower.contains('مكتب')) {
    return AddressKind.work;
  }
  return AddressKind.other;
}

IconData addressIcon(String label) => switch (addressKindOf(label)) {
  AddressKind.home => Icons.home_rounded,
  AddressKind.work => Icons.work_rounded,
  AddressKind.other => Icons.location_on_rounded,
};

/// "Home" and "Work" stored in English show in the app's language; a label
/// the customer typed themselves is shown as they typed it.
String addressLabelText(BuildContext context, String label) {
  final l10n = context.l10n;
  final lower = label.trim().toLowerCase();
  if (lower == 'home') return l10n.addressHome;
  if (lower == 'work') return l10n.work;
  if (lower == 'other' || lower.isEmpty) return l10n.other;
  return label;
}

/// Street, then building / floor / apartment in the app's language.
String addressSummaryText(BuildContext context, Address address) {
  final l10n = context.l10n;
  return [
    address.street,
    if (address.building?.isNotEmpty ?? false)
      l10n.buildingWithValue(address.building!),
    if (address.floor?.isNotEmpty ?? false) l10n.floorWithValue(address.floor!),
    if (address.apartment?.isNotEmpty ?? false)
      l10n.aptWithValue(address.apartment!),
  ].join('، ');
}
