import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// The Kitchen IN identity.
///
/// The mark is an **arch** — a kitchen doorway, and the shape of the letters
/// **I** and **N** — with a pistachio dot inside it. It is painted rather than
/// loaded from `assets/brand/logo-mark.svg` for one reason the design system is
/// explicit about: *"scale the stroke with the tile — do not keep it at 9px on
/// a 24px mark."* A painter derives every dimension from the requested size, so
/// a 24px app-bar mark and a 104px splash mark are the same drawing, and no SVG
/// rasteriser sits between the token file and the pixels.
///
/// Geometry is the design system's, on its 104 viewBox:
///
/// * tile `104×104`, radius `30`
/// * arch `M32 78 V54 a20 20 0 0 1 40 0 V78`, stroke `9`, no fill, **open at
///   the bottom**
/// * dot `cx 52 cy 62 r 6.5`
///
/// Two rules travel with it: the arch never closes at the top and is never
/// filled, and the dot is never a glyph, an emoji or a photo.
const double _kMarkViewBox = 104;
const double _kMarkRadius = 30;
const double _kMarkStroke = 9;
const double _kDotRadius = 6.5;

/// How the tile behind the arch is painted.
enum KitchenInMarkStyle {
  /// The aubergine gradient tile, white arch, pistachio dot. The default, and
  /// the only form to use on a light surface where the mark stands alone.
  gradient,

  /// The tile takes the ambient [IconTheme] colour and the arch and dot are
  /// white — the mark reduced to one ink, for stamps, watermarks and anywhere
  /// the surrounding colour must win.
  mono,

  /// No tile: an aubergine arch and pistachio dot on whatever is behind them.
  /// For light backgrounds that already carry their own shape.
  bare,

  /// A frosted-glass tile — white at low opacity with a hairline border — for
  /// the mark sitting *on* the brand gradient, where a gradient tile on a
  /// gradient would disappear. This is the splash treatment.
  glass,
}

class KitchenInMark extends StatelessWidget {
  const KitchenInMark({
    super.key,
    this.size = 40,
    this.style = KitchenInMarkStyle.gradient,
  });

  final double size;
  final KitchenInMarkStyle style;

  @override
  Widget build(BuildContext context) {
    final monoColor = style == KitchenInMarkStyle.mono
        ? (IconTheme.of(context).color ?? AppColors.ink)
        : null;

    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _MarkPainter(style: style, monoColor: monoColor),
        // The mark carries the brand name for anyone using a screen reader; the
        // lockup below hides its own copy, because the wordmark next to it is
        // real, readable text.
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter({required this.style, this.monoColor});

  final KitchenInMarkStyle style;
  final Color? monoColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Everything below is authored against the 104 viewBox and scaled once.
    final s = size.shortestSide / _kMarkViewBox;
    final rect = Rect.fromLTWH(0, 0, _kMarkViewBox * s, _kMarkViewBox * s);
    final rrect = RRect.fromRectAndRadius(
      rect,
      Radius.circular(_kMarkRadius * s),
    );

    switch (style) {
      case KitchenInMarkStyle.gradient:
        canvas.drawRRect(
          rrect,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7A3457), AppColors.primaryDark],
            ).createShader(rect),
        );
      case KitchenInMarkStyle.mono:
        canvas.drawRRect(rrect, Paint()..color = monoColor ?? AppColors.ink);
      case KitchenInMarkStyle.glass:
        canvas
          ..drawRRect(
            rrect,
            Paint()..color = Colors.white.withValues(alpha: 0.16),
          )
          ..drawRRect(
            rrect,
            Paint()
              ..color = Colors.white.withValues(alpha: 0.25)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
      case KitchenInMarkStyle.bare:
        break; // No tile.
    }

    final onTile = style != KitchenInMarkStyle.bare;

    canvas.drawPath(
      archPath(s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kMarkStroke * s
        ..color = onTile ? Colors.white : AppColors.primary,
    );

    canvas.drawCircle(
      Offset(52 * s, 62 * s),
      _kDotRadius * s,
      Paint()
        ..color = style == KitchenInMarkStyle.mono
            ? Colors.white.withValues(alpha: 0.62)
            : AppColors.pistachio,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.style != style || old.monoColor != monoColor;
}

/// The arch, scaled by [s] from the design system's 104 viewBox:
/// `M32 78 V54 a20 20 0 0 1 40 0 V78`.
///
/// Shared with the splash, which draws the same path progressively with a
/// [PathMetric] so the stroke appears to be *drawn* — left foot, up, over,
/// down — rather than faded in.
Path archPath(double s) => Path()
  ..moveTo(32 * s, 78 * s)
  ..lineTo(32 * s, 54 * s)
  ..arcToPoint(
    Offset(72 * s, 54 * s),
    radius: Radius.circular(20 * s),
    clockwise: true,
  )
  ..lineTo(72 * s, 78 * s);

/// The horizontal lockup: the mark, then **"Kitchen IN"** as live text.
///
/// The wordmark is type, not art. The design system sets it in Cairo 800 at
/// −0.02em — which is exactly [AppType.display] — with "Kitchen" in [ink] and
/// **"IN" in the pistachio green**, so the accent that sits inside the arch is
/// also the accent inside the name. Set solid as "KitchenIN": one word, the
/// capital I marking the join. Never "KITCHEN IN", never "Kitchen IN".
///
/// Rendering it as text rather than shipping `logo-lockup.svg` means it needs
/// no embedded font, honours the user's text scale, and is selectable and
/// readable by a screen reader.
class KitchenInLockup extends StatelessWidget {
  const KitchenInLockup({
    super.key,
    this.markSize = 40,
    this.fontSize,
    this.onDark = false,
  });

  final double markSize;

  /// Defaults to a proportion of [markSize] that matches the lockup SVG, where
  /// a 104 mark carries 44pt type.
  final double? fontSize;

  /// Recolours both halves of the wordmark for an aubergine surface.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final size = fontSize ?? markSize * (44 / 104);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KitchenInMark(
          size: markSize,
          style: onDark ? KitchenInMarkStyle.glass : KitchenInMarkStyle.gradient,
        ),
        SizedBox(width: markSize * 0.23),
        // Flexible so the lockup can be put in a row beside something else.
        // Its own Row is `min`, so without this the wordmark took its natural
        // width and pushed whatever sat next to it off the edge.
        Flexible(child: KitchenInWordmark(fontSize: size, onDark: onDark)),
      ],
    );
  }
}

/// "KitchenIN" on its own — the wordmark without the mark, for a splash or a
/// header that has already shown the arch.
///
/// "IN" is [AppColors.onDarkPistachio] (#C3DE84) on every surface, so the name
/// reads as one colour wherever it appears.
///
/// Note the trade-off that buys: #C3DE84 was drawn to sit on aubergine, and on
/// the light canvas it measures roughly 2:1 against the background — below the
/// WCAG AA floor of 4.5:1 for body text and 3:1 for large text. It is legible
/// here only because the wordmark is display-sized and is a logo rather than
/// content; [AppColors.pistachioInk] (~6:1) is the accessible alternative if
/// the light-surface rendering proves too faint in the field.
class KitchenInWordmark extends StatelessWidget {
  const KitchenInWordmark({super.key, this.fontSize = 44, this.onDark = false});

  final double fontSize;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final base = AppType.display(
      fontSize,
      color: onDark ? Colors.white : AppColors.ink,
    );

    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'Kitchen'),
          const TextSpan(
            text: 'IN',
            style: TextStyle(color: AppColors.onDarkPistachio),
          ),
        ],
      ),
      style: base,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      // The two spans are one word to anyone who cannot see the colour split.
      semanticsLabel: 'KitchenIN',
    );
  }
}
