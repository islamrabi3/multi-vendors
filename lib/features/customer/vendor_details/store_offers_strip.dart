import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/tokens.dart';
import '../../../core/models/coupon.dart';
import '../../../core/repositories/coupons_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/money.dart';

/// Promo codes the admin published for this one store.
///
/// Lives only on the store page: a store-scoped code works nowhere else, so
/// advertising it anywhere else would only produce "code not valid" errors.
/// Draws nothing at all while loading, on failure, or when there are none.
class StoreOffersStrip extends StatefulWidget {
  const StoreOffersStrip({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<StoreOffersStrip> createState() => _StoreOffersStripState();
}

class _StoreOffersStripState extends State<StoreOffersStrip> {
  List<Coupon> _offers = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final offers = await CouponsRepository().fetchStoreOffers(
        widget.vendorId,
      );
      if (mounted) setState(() => _offers = offers);
    } catch (_) {
      // Decorative: the store page is complete without it.
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_offers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  Icons.local_offer_rounded,
                  size: 18,
                  color: AppColors.amberInk,
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.storeOffersTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _offers.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _OfferTicket(
                coupon: _offers[i],
                // A single offer gets the full row instead of a lonely card.
                width: _offers.length == 1
                    ? MediaQuery.sizeOf(context).width.clamp(0, 560) - 32
                    : 264,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfferTicket extends StatelessWidget {
  const _OfferTicket({required this.coupon, required this.width});

  final Coupon coupon;
  final double width;

  String _headline(BuildContext context) {
    final l10n = context.l10n;
    final title = coupon.title?.trim() ?? '';
    if (title.isNotEmpty) return title;
    if (coupon.isFreeDelivery) return l10n.couponTypeFreeDelivery;
    final value = coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}%'
        : formatMoney(coupon.value);
    return '$value ${l10n.off}';
  }

  String _terms(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return [
      if (coupon.isPercentage && coupon.maxDiscount != null)
        '${l10n.max} ${formatMoney(coupon.maxDiscount!)}',
      if (coupon.minOrderAmount > 0)
        '${l10n.min} ${formatMoney(coupon.minOrderAmount)}',
      if (coupon.firstOrderOnly) l10n.couponFirstOrderOnly,
      if (coupon.expiresAt != null)
        l10n.storeOfferExpires(
          DateFormat.MMMd(language).format(coupon.expiresAt!),
        ),
    ].join(' · ');
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final copied = context.l10n.codeCopied;
    await Clipboard.setData(ClipboardData(text: coupon.code));
    HapticFeedback.selectionClick();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$copied  ${coupon.code}')));
  }

  @override
  Widget build(BuildContext context) {
    final terms = _terms(context);
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _copy(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _headline(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      if (terms.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          terms,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.3,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // The code itself, dashed-ticket style, with the copy glyph.
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.amberInk, width: 1.2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        coupon.code,
                        style: AppType.mono(13.5, color: AppColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.copy_rounded,
                            size: 11,
                            color: AppColors.amberInk,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            context.l10n.storeOfferTapToCopy,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.amberInk,
                            ),
                          ),
                        ],
                      ),
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
