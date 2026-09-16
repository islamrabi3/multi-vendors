import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../models/vendor.dart';
import '../utils/category_emoji.dart';
import '../utils/l10n_extension.dart';
import '../utils/money.dart';
import 'common.dart';

/// A titled, horizontally scrolling row of stores — the home page's
/// "Recommended" and "Nearest" rails and a category's recommended picks.
///
/// Takes favourites and distance as callbacks so each page wires it to its
/// own cubit.
class StoreRail extends StatelessWidget {
  const StoreRail({
    super.key,
    required this.title,
    required this.vendors,
    required this.icon,
    this.subtitle,
    this.isFavorite,
    this.onToggleFavorite,
    this.distanceKm,
    this.padding = const EdgeInsets.fromLTRB(22, 22, 22, 12),
    this.gutter = 22,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final List<Vendor> vendors;
  final bool Function(Vendor vendor)? isFavorite;
  final void Function(Vendor vendor)? onToggleFavorite;
  final double? Function(Vendor vendor)? distanceKm;
  final EdgeInsets padding;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.warmFill,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.heading(17),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          // Exactly the card: photo, gap, then the name and meta lines, which
          // grow with the system text size.
          height:
              StoreRailCard.imageHeight +
              10 +
              MediaQuery.textScalerOf(context).scale(58),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: gutter),
            itemCount: vendors.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final vendor = vendors[i];
              return StoreRailCard(
                vendor: vendor,
                isFavorite: isFavorite?.call(vendor) ?? false,
                onToggleFavorite: onToggleFavorite == null
                    ? null
                    : () => onToggleFavorite!(vendor),
                distanceKm: distanceKm?.call(vendor),
              );
            },
          ),
        ),
      ],
    );
  }
}

class StoreRailCard extends StatelessWidget {
  const StoreRailCard({
    super.key,
    required this.vendor,
    required this.isFavorite,
    this.onToggleFavorite,
    this.distanceKm,
    this.fullWidth = false,
  });

  final Vendor vendor;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  /// Shown on the card when set — the "nearest" rail passes it, others don't.
  final double? distanceKm;

  /// Fills the row instead of the rail's fixed card width, for the stacked
  /// list on the home page. Same card, one per line.
  final bool fullWidth;

  static const width = 250.0;
  static const imageHeight = 136.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final km = distanceKm;
    final open = vendor.isOpenNow();
    final free = vendor.deliveryFee == 0;
    final logo = vendor.logoUrl;

    final cardWidth = fullWidth ? double.infinity : width;

    return SizedBox(
      width: cardWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push('/vendors/${vendor.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: fullWidth ? 170 : imageHeight,
              width: cardWidth,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    child: AppNetworkImage(
                      url: vendor.coverUrl,
                      height: fullWidth ? 170 : imageHeight,
                      width: cardWidth,
                    ),
                  ),
                  if (!open)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.5),
                        child: Center(
                          child: Text(
                            l10n.closedNow,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    top: 10,
                    end: 10,
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      elevation: 1,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onToggleFavorite,
                        child: Padding(
                          padding: const EdgeInsets.all(7),
                          child: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 18,
                            color: isFavorite
                                ? AppColors.primary
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 10,
                    start: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Text(
                        [
                          if (km != null)
                            '${km < 10 ? km.toStringAsFixed(1) : km.round()} ${l10n.kmUnit}',
                          l10n.minutesRange(
                            vendor.totalPrepMinutes,
                            vendor.totalPrepMinutes + 10,
                          ),
                        ].join(' · '),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
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
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: AppColors.rating,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            vendor.ratingCount > 0
                                ? vendor.ratingAvg.toStringAsFixed(1)
                                : l10n.newStoreBadge,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '· ${free ? l10n.freeDelivery : l10n.deliveryFeeLabel(formatMoney(vendor.deliveryFee))}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: free
                                    ? AppColors.successInk
                                    : AppColors.textMuted,
                                fontWeight: free
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
