import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// An icon whose glyph encodes reading direction (send, next, chevrons) and so
/// must mirror in Arabic.
///
/// Only for icons that point *along the text*. A checkmark, a trash can or a
/// star must never be flipped — use a plain [Icon] for those. Icons that already
/// carry `matchTextDirection` (e.g. `Icons.arrow_back`) don't need this either.
class DirectionalIcon extends StatelessWidget {
  const DirectionalIcon(this.icon, {super.key, this.size, this.color});

  final IconData icon;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Transform.flip(
        flipX: Directionality.of(context) == TextDirection.rtl,
        child: Icon(icon, size: size, color: color),
      );
}

/// The standard surface: white, hairline border, card lift, `xl` corner.
///
/// [attention] swaps the hairline for a warm 1.5px border and lifts the shadow
/// one step — for the single card on a screen that the user must deal with
/// (an applied coupon, a failed payment). Two "attention" cards on one screen
/// means neither reads as one.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpace.lg),
    this.onTap,
    this.radius = AppRadii.xl,
    this.attention = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final double radius;
  final bool attention;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius,
        border: Border.all(
          color: attention ? AppColors.attentionBorder : AppColors.border,
          width: attention ? 1.5 : 1.0,
        ),
        boxShadow: attention ? AppShadows.raised : AppShadows.card,
      ),
      child: onTap == null
          ? Padding(padding: padding, child: child)
          // Material under the ink so the ripple is clipped to the corner
          // instead of painting a square over the border.
          : Material(
              type: MaterialType.transparency,
              borderRadius: borderRadius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                borderRadius: borderRadius,
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
    return decorated;
  }
}

/// One filter pill. Spacing is deliberately NOT its business — see [AppFilterBar].
class AppFilterChip extends StatelessWidget {
  const AppFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.md);
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            borderRadius: radius,
            border:
                selected ? null : Border.all(color: AppColors.borderSoft),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? Colors.white : AppColors.ink,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: AppSpace.xs + 2),
                Text(
                  '$count',
                  style: AppType.mono(
                    11.5,
                    color: selected ? Colors.white : AppColors.textMuted,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal strip of [AppFilterChip]s.
///
/// The BAR owns the gutters. Chips that pad themselves with
/// `EdgeInsets.only(right: 8)` leave the gap on the wrong side in Arabic and
/// strand a dangling gutter at the end of the row; a separator can't.
class AppFilterBar extends StatelessWidget {
  const AppFilterBar({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(
        AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xs),
    this.height = 54,
    this.spacing = 9,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: padding,
        itemCount: children.length,
        separatorBuilder: (_, _) => SizedBox(width: spacing),
        itemBuilder: (_, index) => children[index],
      ),
    );
  }
}

/// A number + caption tile for dark headers (driver pool, week hero).
///
/// The value is a [FittedBox] because a payout can be `0` or `12,480` and the
/// tile width is fixed by the row — it shrinks rather than clipping or wrapping.
class DarkStatTile extends StatelessWidget {
  const DarkStatTile({
    super.key,
    required this.value,
    required this.label,
    this.suffix,
  });

  final String value;
  final String label;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              ?suffix,
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small tracked caps above a block — "ACTIVE DELIVERY", "PAYMENT".
class SectionEyebrow extends StatelessWidget {
  const SectionEyebrow(this.text, {super.key, this.trailing, this.onDark = false});

  final String text;
  final Widget? trailing;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: onDark
            ? Colors.white.withValues(alpha: 0.55)
            : AppColors.textFaint,
      ),
    );
    if (trailing == null) return label;
    return Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: AppSpace.sm),
        trailing!,
      ],
    );
  }
}
