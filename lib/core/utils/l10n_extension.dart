import 'package:flutter/widgets.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';
import '../models/order.dart';

extension L10nExtension on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this)!;
}

extension OrderStatusL10n on OrderStatus {
  String localizedLabel(BuildContext context) {
    switch (this) {
      case OrderStatus.pending:
        return context.l10n.pending;
      case OrderStatus.accepted:
        return context.l10n.accepted;
      case OrderStatus.preparing:
        return context.l10n.preparing;
      case OrderStatus.readyForPickup:
        return context.l10n.readyForPickup;
      case OrderStatus.outForDelivery:
        return context.l10n.outForDelivery;
      case OrderStatus.delivered:
        return context.l10n.delivered;
      case OrderStatus.cancelled:
        return context.l10n.cancelled;
      case OrderStatus.rejected:
        return context.l10n.rejected;
    }
  }
}
