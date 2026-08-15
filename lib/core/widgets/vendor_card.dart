import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../app/tokens.dart';
import '../models/vendor.dart';
import '../utils/category_emoji.dart';
import '../utils/money.dart';
import 'common.dart';

/// The store row used everywhere a list of stores appears.
///
/// A compact row rather than the tall cover-photo card it replaces: at ~104pt
/// a phone screen shows six stores instead of two, which is the difference
/// between scanning a marketplace and scrolling one. The photo stays — it is
/// how a customer recognises a place — but at thumbnail size beside the facts
/// they actually choose on: rating, time, delivery fee.
///
/// Favourites are passed in rather than read from a cubit, because this card is
/// shown by the home page, the category pages and search, and each owns that
/// state differently.
class VendorCard extends StatelessWidget {
  const VendorCard({
    super.key,
    required this.vendor,
    this.isFavorite,
    this.onToggleFavorite,
    this.distanceKm,
    this.menuMatches,
    this.onTap,
  });

  final Vendor vendor;

  /// Null hides the heart entirely — for a signed-out or read-only context.
  final bool? isFavorite;
  final VoidCallback? onToggleFavorite;

  /// Shown before the prep time when the distance is actually knowable.
  final double? distanceKm;

  /// Item names that put this store in a search result. Null outside a search.
  final List<String>? menuMatches;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The timetable, not just the owner's switch: a store past its closing
    // time reads as shut here and is refused at checkout.
    final open = vendor.isOpenNow();
    final closingTime = vendor.closingTime();

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap ?? () => context.push('/vendors/${vendor.id}'),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Thumbnail(vendor: vendor, open: open),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _TitleRow(vendor: vendor),
                    const SizedBox(height: 6),
                    _MetaRow(vendor: vendor, distanceKm: distanceKm),
                    if (!open) ...[
                      const SizedBox(height: 6),
                      SoftBadge(
                        label: context.l10n.closedNow,
                        fill: AppColors.neutralFill,
                        ink: AppColors.textMuted,
                      ),
                    ] else if (vendor.isBusy) ...[
                      const SizedBox(height: 6),
                      SoftBadge(
                        label: context.l10n.busyStore,
                        fill: AppColors.amberFill,
                        ink: AppColors.amberInk,
                      ),
                    ] else if (closingTime != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        context.l10n.openUntil(closingTime),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.successInk,
                        ),
                      ),
                    ],
                    if (menuMatches != null && menuMatches!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warmFill,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          context.l10n.matchesOnMenu(menuMatches!.join(' · ')),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (isFavorite != null)
                _Heart(isFavorite: isFavorite!, onTap: onToggleFavorite),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.vendor, required this.open});

  final Vendor vendor;
  final bool open;

  static const _size = 92.0;

  static Widget _cover(String? url) =>
      AppNetworkImage(url: url, height: _size, width: _size);

  @override
  Widget build(BuildContext context) {
    final logo = vendor.logoUrl;
    return SizedBox(
      width: _size,
      height: _size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            // A shut store is greyed out; an open one is left alone.
            //
            // There is no "identity" ColorFilter, so this branches on the
            // widget rather than on the filter. Passing a transparent
            // `BlendMode.multiply` as a no-op is not one: transparent is
            // (0,0,0,0) once premultiplied, and multiplying by it zeroes every
            // channel — which rendered every open store's photo invisible.
            child: open
                ? _cover(vendor.coverUrl)
                : ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0.2126, 0.7152, 0.0722, 0, 0, //
                      0, 0, 0, 1, 0, //
                    ]),
                    child: _cover(vendor.coverUrl),
                  ),
          ),
          // The logo badge, as on the reference: the brand mark sits on the
          // dish photo rather than replacing it.
          PositionedDirectional(
            top: 6,
            start: 6,
            child: Container(
              width: 34,
              height: 34,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.borderSoft),
              ),
              alignment: Alignment.center,
              child: logo != null && logo.isNotEmpty
                  ? AppNetworkImage(url: logo, height: 34, width: 34)
                  : Text(
                      emojiFor(vendor.name).trim(),
                      style: const TextStyle(fontSize: 17),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // A paid-tier partner, which is what the badge means on the stores it
        // appears on — not a quality claim the platform cannot back.
        if (vendor.isSubscription) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              context.l10n.proPartner,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            vendor.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// The one line a customer actually compares stores on.
///
/// Built as a single ellipsised string rather than a row of chips: on a narrow
/// phone the chips wrapped onto a second line and pushed the card's height
/// past the point of showing six of them.
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.vendor, this.distanceKm});

  final Vendor vendor;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final free = vendor.deliveryFee == 0;
    final km = distanceKm;
    final parts = <String>[
      if (km != null)
        '${km < 10 ? km.toStringAsFixed(1) : km.round()} ${context.l10n.kmUnit}',
      context.l10n.minutesRange(
        vendor.totalPrepMinutes,
        vendor.totalPrepMinutes + 10,
      ),
      free
          ? context.l10n.freeDelivery
          : context.l10n.deliveryFeeLabel(formatMoney(vendor.deliveryFee)),
    ];

    return Row(
      children: [
        const Icon(Icons.star_rounded, size: 15, color: AppColors.rating),
        const SizedBox(width: 2),
        Text(
          vendor.ratingAvg.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (vendor.ratingCount > 0) ...[
          const SizedBox(width: 3),
          Text(
            '(${_compactCount(vendor.ratingCount)})',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
        ],
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '· ${parts.join(' · ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: free ? AppColors.successInk : AppColors.textMuted,
              fontWeight: free ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

/// `1240` reads as `1k+`, the way every marketplace shows a review count. The
/// exact number stops meaning anything past a few hundred.
String _compactCount(int count) {
  if (count >= 1000) return '${count ~/ 1000}k+';
  if (count >= 100) return '${(count ~/ 100) * 100}+';
  return '$count';
}

class _Heart extends StatelessWidget {
  const _Heart({required this.isFavorite, required this.onTap});

  final bool isFavorite;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        size: 21,
        color: isFavorite ? AppColors.primary : AppColors.textMuted,
      ),
    );
  }
}
