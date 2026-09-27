import 'package:flutter/widgets.dart';

import '../models/vendor.dart';
import '../services/platform_config_service.dart';
import 'l10n_extension.dart';
import 'money.dart';

/// What delivery from [vendor] costs, as far as it can be known here.
///
/// Priced the way the platform is set to (see `DeliveryFeeRule`). With
/// distance pricing and no [km] — the customer has not said where the order
/// is going — the base fee is only the least it can be, so [isFrom] is true
/// and the UI says "from".
({double fee, bool isFrom}) deliveryFeeQuote(Vendor vendor, {double? km}) {
  final rule = PlatformConfigService.instance.current.delivery;
  if (!rule.byDistance) return (fee: vendor.deliveryFee, isFrom: false);
  if (km != null) {
    return (
      fee: rule.feeFor(storeFee: vendor.deliveryFee, km: km),
      isFrom: false,
    );
  }
  return (fee: rule.baseFee, isFrom: rule.perKmFee > 0);
}

/// Whether delivery from [vendor] is certainly free.
bool isFreeDelivery(Vendor vendor, {double? km}) {
  final quote = deliveryFeeQuote(vendor, km: km);
  return quote.fee == 0 && !quote.isFrom;
}

/// "Free delivery", "EGP 20 delivery" or "from EGP 20 delivery".
String deliveryFeeText(BuildContext context, Vendor vendor, {double? km}) {
  final l10n = context.l10n;
  final quote = deliveryFeeQuote(vendor, km: km);
  if (quote.fee == 0 && !quote.isFrom) return l10n.freeDelivery;
  final amount = formatMoney(quote.fee);
  return quote.isFrom
      ? l10n.deliveryFeeFrom(amount)
      : l10n.deliveryFeeLabel(amount);
}

/// Just the amount, for a place that already says "Delivery fee" beside it:
/// "Free delivery", "EGP 20" or "from EGP 20".
String deliveryFeeAmountText(
  BuildContext context,
  Vendor vendor, {
  double? km,
}) {
  final l10n = context.l10n;
  final quote = deliveryFeeQuote(vendor, km: km);
  if (quote.fee == 0 && !quote.isFrom) return l10n.freeDelivery;
  final amount = formatMoney(quote.fee);
  return quote.isFrom ? l10n.fromAmount(amount) : amount;
}
