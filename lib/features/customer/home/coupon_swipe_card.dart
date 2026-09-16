import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/tokens.dart';
import '../../../core/models/coupon.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/swipe_to_confirm.dart';

/// The home page's promo codes, behind a swipe.
///
/// A row that simply listed codes was read past; a swipe is a small deliberate
/// act, and what it opens is the codes themselves rather than another screen.
/// The card is drawn as a ticket — notched sides, a dashed tear line — so it
/// reads as something to be torn off rather than another banner.
class CouponSwipeCard extends StatefulWidget {
  const CouponSwipeCard({super.key, required this.coupons});

  final List<Coupon> coupons;

  @override
  State<CouponSwipeCard> createState() => _CouponSwipeCardState();
}

class _CouponSwipeCardState extends State<CouponSwipeCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 4),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _TicketShape(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_activity_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.couponsCardTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.heading(16, color: Colors.white),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            l10n.couponsCardSubtitle(widget.coupons.length),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_open)
                      IconButton(
                        tooltip: l10n.showLess,
                        onPressed: () => setState(() => _open = false),
                        icon: const Icon(Icons.expand_less_rounded),
                        color: Colors.white,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!_open)
                  SwipeToConfirm(
                    label: l10n.swipeForDiscount,
                    color: Colors.white,
                    icon: Icons.card_giftcard_rounded,
                    height: 52,
                    onConfirmed: () => setState(() => _open = true),
                  )
                else ...[
                  const _TearLine(),
                  const SizedBox(height: 12),
                  for (var i = 0; i < widget.coupons.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _CouponRow(coupon: widget.coupons[i]),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card itself: brand gradient, rounded, with a notch bitten out of each
/// side so it reads as a torn ticket rather than a plain box.
class _TicketShape extends StatelessWidget {
  const _TicketShape({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primaryLight, AppColors.primary],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          child,
          // The two notches, painted in the page colour.
          const PositionedDirectional(start: -9, top: 62, child: _Notch()),
          const PositionedDirectional(end: -9, top: 62, child: _Notch()),
        ],
      ),
    );
  }
}

class _Notch extends StatelessWidget {
  const _Notch();

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: const BoxDecoration(
      color: AppColors.canvas,
      shape: BoxShape.circle,
    ),
  );
}

/// The perforation between the card's head and its codes.
class _TearLine extends StatelessWidget {
  const _TearLine();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dash = 6.0;
        final count = (constraints.maxWidth / (dash * 2)).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            count,
            (_) => Container(
              width: dash,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.45),
            ),
          ),
        );
      },
    );
  }
}

/// One code on the opened ticket: what it is worth, and the code itself as a
/// white stub that copies on tap.
class _CouponRow extends StatelessWidget {
  const _CouponRow({required this.coupon});

  final Coupon coupon;

  String _worth(BuildContext context) {
    final l10n = context.l10n;
    if (coupon.isFreeDelivery) return l10n.couponTypeFreeDelivery;
    return coupon.isPercentage
        ? '${coupon.value.toStringAsFixed(0)}% ${l10n.off}'
        : '${formatMoney(coupon.value)} ${l10n.off}';
  }

  String _terms(BuildContext context) {
    final l10n = context.l10n;
    return [
      if (coupon.isPercentage && coupon.maxDiscount != null)
        '${l10n.max} ${formatMoney(coupon.maxDiscount!)}',
      if (coupon.minOrderAmount > 0)
        '${l10n.min} ${formatMoney(coupon.minOrderAmount)}',
      if (coupon.firstOrderOnly) l10n.couponFirstOrderOnly,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final terms = _terms(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final copied = context.l10n.codeCopied;
          await Clipboard.setData(ClipboardData(text: coupon.code));
          HapticFeedback.selectionClick();
          messenger
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text('$copied  ${coupon.code}')));
        },
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon.title?.trim().isNotEmpty ?? false
                          ? coupon.title!
                          : _worth(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.heading(14.5, color: Colors.white),
                    ),
                    if (terms.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        terms,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      coupon.code,
                      style: AppType.mono(
                        13,
                        color: AppColors.primaryDark,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.copy_rounded,
                          size: 10,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          l10n.storeOfferTapToCopy,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
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
    );
  }
}
