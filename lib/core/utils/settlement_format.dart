import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../app/tokens.dart';

/// Human label for a settlement's lifecycle state.
String settlementStatusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  return switch (status) {
    'completed' => l10n.settlementCompleted,
    'cancelled' => l10n.cancelled,
    _ => l10n.pending,
  };
}

/// Human label for how a settlement moved — the same two methods the record
/// form offers, plus the raw value for anything recorded outside the app.
String settlementMethodLabel(BuildContext context, String method) {
  final l10n = context.l10n;
  return switch (method) {
    'cash' => l10n.settlementMethodCash,
    'bank_transfer' => l10n.settlementMethodBank,
    _ => method.replaceAll('_', ' '),
  };
}

(Color fill, Color ink) settlementStatusTone(String status) => switch (status) {
  'completed' => (AppColors.successFill, AppColors.successInk),
  'cancelled' => (AppColors.dangerFill, AppColors.dangerInk),
  _ => (AppColors.amberFill, AppColors.amberInk),
};

String formatSettlementDateTime(BuildContext context, DateTime value) =>
    '${value.day}/${value.month}/${value.year} · '
    '${TimeOfDay.fromDateTime(value).format(context)}';
