import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../brand_logo.dart';

/// The desktop shape for the screens shown before anyone is signed in.
///
/// Sign-in is one narrow column of fields. Stretched across a 1400px window it
/// reads as a phone screen someone forgot to lay out — the exact complaint
/// these screens drew. A brand panel beside a capped form is the shape every
/// hand-built web console uses, for the ordinary reason that a form wants
/// about 400px and a window has three times that to spare.
///
/// Mobile is untouched: below the web breakpoint this returns [child] exactly
/// as it was, so the phone layout that already works keeps working.
class WebAuthFrame extends StatelessWidget {
  const WebAuthFrame({
    super.key,
    required this.child,
    this.headline,
    this.subhead,
    this.maxFormWidth = 440,
  });

  final Widget child;

  /// What the brand panel says. Defaults to the product name alone, which is
  /// the right answer when the form beside it already carries the heading.
  final String? headline;
  final String? subhead;

  /// The form column's ceiling. Wider than this and the eye has to travel
  /// between a label and its field.
  final double maxFormWidth;

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isWebWide(context)) return child;

    // The brand panel is the first thing to go: below roughly 1100px the two
    // columns start fighting, and a centred form on plain canvas is a better
    // outcome than two cramped ones.
    final showBrandPanel = MediaQuery.sizeOf(context).width >= 1100;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showBrandPanel)
            Expanded(
              flex: 5,
              child: _BrandPanel(headline: headline, subhead: subhead),
            ),
          Expanded(
            flex: 6,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxFormWidth),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({this.headline, this.subhead});

  final String? headline;
  final String? subhead;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Flat brand colour rather than the three-stop gradient the splash
      // uses: this panel sits still behind a form for as long as someone
      // takes to type a password, and a gradient that size becomes the loudest
      // thing on screen.
      color: AppColors.primaryDark,
      padding: const EdgeInsets.all(56),
      // Centred on both axes. Start-aligned, the block sat against the left
      // edge of a half-width panel with the rest of it empty, which read as
      // the content having failed to lay out rather than as a deliberate
      // margin.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const KitchenInLockup(markSize: 64, fontSize: 40, onDark: true),
          if (headline != null) ...[
            const SizedBox(height: 32),
            Text(
              headline!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                height: 1.25,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
          if (subhead != null) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              // Roughly 60 characters. Past that the eye loses the start of
              // the next line.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                subhead!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.55,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
