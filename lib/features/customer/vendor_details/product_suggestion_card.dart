import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'product_quantity_control.dart';

/// One card in a horizontal suggestion strip.
///
/// Shared by the sheet's "goes well with" and the cart's "you might also like"
/// so the two cannot drift into looking like different features. The strip that
/// hosts it decides what tapping means: from the sheet it replaces the sheet,
/// from the cart it opens one.
class ProductSuggestionCard extends StatelessWidget {
  const ProductSuggestionCard({
    super.key,
    required this.vendor,
    required this.product,
    this.onTap,
    this.onConfigure,
    this.width = 124,
  });

  final Vendor vendor;
  final Product product;

  /// Tapping the card itself — the request to read the item, not to buy it.
  final VoidCallback? onTap;

  /// Passed to the quantity control for products that need the option sheet.
  final VoidCallback? onConfigure;

  final double width;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.borderSoft),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    AppNetworkImage(
                      url: product.imageUrl,
                      height: 82,
                      width: double.infinity,
                    ),
                    PositionedDirectional(
                      bottom: 6,
                      end: 6,
                      child: ProductQuantityControl(
                        vendor: vendor,
                        product: product,
                        compact: true,
                        onConfigure: onConfigure,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.displayName(language),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 3),
                      PriceText(formatMoney(product.price), size: 12.5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
