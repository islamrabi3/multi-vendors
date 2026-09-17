import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

/// Keeps a phone-shaped app phone-shaped on a desktop browser.
///
/// The customer storefront and the rider app are built around one thumb and a
/// bottom bar, and that is the right shape for them — most of their traffic is
/// a phone. Opened on a monitor, though, an unconstrained phone layout does
/// not become a desktop app; it becomes a phone app pulled to two thousand
/// pixels, with a card grid four items wide, headings adrift from the text
/// under them, and a bottom navigation bar a metre from the content it
/// belongs to.
///
/// So the whole app — body, bottom bar and floating button together — is held
/// to a readable column and centred, with the page's own background either
/// side. The alternative, a rail and a spread-out desktop layout, is a
/// different product for these two roles and not one this app has.
///
/// Below [AppBreakpoints.rail] this is not in the tree at all: a phone gets
/// exactly what it got before.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.child, this.maxWidth = 620});

  final Widget child;

  /// Wider than a phone, narrower than a tablet held in two hands: enough for
  /// the store cards to keep their proportions without the eye having to
  /// travel.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppBreakpoints.rail) return child;
        return ColoredBox(
          color: AppColors.neutralFill,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              // The edges make the column deliberate rather than accidental —
              // without them it reads as a window that failed to resize.
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border.symmetric(
                    vertical: BorderSide(color: AppColors.border),
                  ),
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
