import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// Drives the shimmer for every [Skeleton] beneath it off a single ticker, so a
/// screenful of placeholders sweeps as one surface instead of a dozen
/// independently-phased ones.
///
/// Wrap the loading branch of a screen, not the whole screen: the clock stops
/// as soon as this widget leaves the tree.
class SkeletonTheme extends StatefulWidget {
  const SkeletonTheme({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// Set false to freeze the sweep (tests, or a placeholder that is not
  /// actually waiting on anything).
  final bool enabled;

  @override
  State<SkeletonTheme> createState() => _SkeletonThemeState();

  /// The ambient shimmer progress in `-1..2`, or null when there is no
  /// [SkeletonTheme] above — in which case a [Skeleton] paints its base fill.
  static Animation<double>? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_SkeletonScope>()
      ?.progress;
}

class _SkeletonThemeState extends State<SkeletonTheme>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _progress = _controller.drive(
    Tween<double>(begin: -1, end: 2).chain(
      CurveTween(curve: Curves.easeInOut),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // "Reduce motion" means reduce motion: a static base fill still reads as
    // "content is coming", and it does so without a looping animation.
    final animate =
        widget.enabled && !MediaQuery.disableAnimationsOf(context);
    if (animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
    }
    return _SkeletonScope(
      progress: animate ? _progress : null,
      child: widget.child,
    );
  }
}

class _SkeletonScope extends InheritedWidget {
  const _SkeletonScope({required this.progress, required super.child});

  final Animation<double>? progress;

  @override
  bool updateShouldNotify(_SkeletonScope oldWidget) =>
      progress != oldWidget.progress;
}

enum SkeletonShape { rect, pill, circle }

/// A single placeholder bar / tile / avatar.
///
/// Size it to the real thing it stands in for — a skeleton whose box differs
/// from the widget that replaces it makes the page jump when data lands, which
/// is worse than a spinner.
class Skeleton extends StatelessWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = AppRadii.xs,
    this.shape = SkeletonShape.rect,
  }) : _widthFactor = null;

  /// A text line. [widthFactor] mimics the ragged right edge of real copy.
  const Skeleton.line({super.key, double widthFactor = 1.0, this.height = 12})
      : width = null,
        radius = AppRadii.xs,
        shape = SkeletonShape.rect,
        _widthFactor = widthFactor;


  /// An avatar / logo tile.
  const Skeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = AppRadii.pill,
        shape = SkeletonShape.circle,
        _widthFactor = null;

  /// A cover image or card body.
  const Skeleton.box({
    super.key,
    this.width,
    this.height,
    this.radius = AppRadii.xl,
  })  : shape = SkeletonShape.rect,
        _widthFactor = null;

  final double? width;
  final double? height;
  final double radius;
  final SkeletonShape shape;
  final double? _widthFactor;

  static const _base = AppColors.borderSoft;
  static final _highlight = Color.lerp(_base, Colors.white, 0.6)!;

  BorderRadius get _borderRadius => switch (shape) {
        SkeletonShape.circle => BorderRadius.circular(AppRadii.pill),
        SkeletonShape.pill => BorderRadius.circular(AppRadii.pill),
        SkeletonShape.rect => BorderRadius.circular(radius),
      };

  @override
  Widget build(BuildContext context) {
    final progress = SkeletonTheme.maybeOf(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;

    Widget box = SizedBox(
      width: width,
      height: height,
      child: progress == null
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: _base,
                borderRadius: _borderRadius,
              ),
            )
          : AnimatedBuilder(
              animation: progress,
              builder: (context, _) => DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: _borderRadius,
                  gradient: _sweep(progress.value, rtl),
                ),
              ),
            ),
    );

    final factor = _widthFactor;
    if (factor != null && factor < 1.0) {
      box = FractionallySizedBox(
        alignment: AlignmentDirectional.centerStart,
        widthFactor: factor,
        child: box,
      );
    }
    return box;
  }

  /// The highlight always travels leading → trailing, so in Arabic it sweeps
  /// right-to-left like the text it stands in for.
  LinearGradient _sweep(double t, bool rtl) {
    final from = t - 1;
    final to = t + 1;
    return LinearGradient(
      begin: Alignment(rtl ? -from : from, 0),
      end: Alignment(rtl ? -to : to, 0),
      colors: [_base, _highlight, _base],
      stops: const [0.0, 0.5, 1.0],
    );
  }
}

/// The loading form of a list. Pass the SAME `padding` and `separator` as the
/// real `ListView` so that swapping placeholders for rows shifts nothing.
class SkeletonList extends StatelessWidget {
  const SkeletonList({
    super.key,
    required this.itemBuilder,
    this.itemCount = 6,
    this.padding,
    this.separator,
    this.scrollable = true,
  });

  final WidgetBuilder itemBuilder;
  final int itemCount;
  final EdgeInsetsGeometry? padding;
  final Widget? separator;

  /// False when this is already inside a scroll view.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final gap = separator ?? const SizedBox(height: AppSpace.md);
    final children = <Widget>[
      for (var i = 0; i < itemCount; i++) ...[
        if (i > 0) gap,
        itemBuilder(context),
      ],
    ];
    if (!scrollable) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return ListView(
      padding: padding,
      physics: const NeverScrollableScrollPhysics(),
      children: children,
    );
  }
}

/// The spinner that lives *inside* a button while its action is in flight.
///
/// Fixed box, so swapping it in for the label does not resize the button and
/// make the tap target move under the finger.
class ButtonSpinner extends StatelessWidget {
  const ButtonSpinner({super.key, this.size = 20, this.color = Colors.white});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: size,
        width: size,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
}
