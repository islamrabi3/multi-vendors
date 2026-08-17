import 'package:flutter/material.dart';

import '../../../app/splash_gate.dart';
import '../../../app/tokens.dart';
import '../../../core/widgets/brand_logo.dart';

/// The Kitchen IN splash.
///
/// The design system ships this screen as `assets/brand/splash-animated.svg`
/// and describes it as self-contained. It is rebuilt natively here for two
/// reasons: the delivered SVG carries only the *final frame* (the `<style>`
/// block its README documents is not in the file), and `flutter_svg` does not
/// run CSS keyframes even when they are present. The timeline below is the
/// README's, to the millisecond, so the two stay in step:
///
/// | at | what |
/// | --- | --- |
/// | 0 ms | the aubergine gradient paints |
/// | 60 ms | glass tile scales 0.82 → 1 and fades in (560 ms) |
/// | 420 ms | the arch stroke **draws** — left foot, up, over, down (620 ms) |
/// | 860 ms | the pistachio dot drops into the arch |
/// | 900 ms | "Kitchen IN" rises 14 px and fades in |
/// | 1040 ms | the pistachio rule wipes out from centre |
/// | 1080 ms | tagline follows |
/// | 1400 ms | loader fades out; the CTAs cross-fade in |
///
/// Every step uses [_ease]. Nothing bounces or overshoots — an overshoot curve
/// here would read as playful, and this brand is not.
const Duration _timeline = Duration(milliseconds: 1700);
const Curve _ease = Cubic(0.215, 0.61, 0.355, 1);

/// One millisecond of [_timeline], as a fraction, so the table above can be
/// transcribed in milliseconds instead of hand-computed intervals.
const double _ms = 1 / 1700;

Interval _at(int startMs, int durationMs) =>
    Interval(startMs * _ms, (startMs + durationMs) * _ms, curve: _ease);

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _intro =
      AnimationController(vsync: this, duration: _timeline)
        ..addStatusListener((status) {
          // The router holds the app here until this fires. Without it a cached
          // session resolved in ~200 ms and the redirect cut the arch off
          // mid-draw, so a warm start never showed the brand.
          if (status == AnimationStatus.completed) SplashGate.markIntroDone();
        });

  /// The two decorative circles drift ~40 px over 18–22 s. Separate from
  /// [_intro] because it outlives it and repeats.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  );

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // `prefers-reduced-motion: reduce` lands the final frame instantly with no
    // animation. On Flutter that signal is `disableAnimations`, and it can flip
    // while the app is open, so it is read here rather than in `initState`.
    final reduced = MediaQuery.of(context).disableAnimations;
    if (reduced == _reducedMotion &&
        (_intro.isAnimating || _intro.isCompleted)) {
      return;
    }
    _reducedMotion = reduced;

    if (reduced) {
      // Setting `value` lands the final frame without ever reporting
      // `completed`, so the gate has to be released by hand — otherwise
      // "reduce motion" would strand the app on the splash forever.
      _intro.value = 1;
      SplashGate.markIntroDone();
      _drift.stop();
      _drift.value = 0.5;
    } else {
      _intro.forward();
      _drift.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    // No BlocBuilder any more: the screen no longer changes with the auth
    // state. It plays its intro and shows a loader; the router decides when to
    // leave and where to go.
    return Scaffold(
      body: Builder(
        builder: (context) {
          return DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.brandGradient,
                stops: AppColors.brandGradientStops,
                begin: Alignment.topCenter,
                end: Alignment(0.44, 1),
              ),
            ),
            child: SizedBox.expand(
              child: Stack(
                children: [
                  _driftingCircle(
                    controller: _drift,
                    top: 76,
                    right: -122,
                    diameter: 240,
                    opacity: 0.08,
                    travel: const Offset(-40, 22),
                  ),
                  _driftingCircle(
                    controller: _drift,
                    top: 456,
                    left: -98,
                    diameter: 180,
                    opacity: 0.07,
                    travel: const Offset(38, -30),
                  ),
                  Align(
                    alignment: const Alignment(0, -0.12),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _AnimatedMark(progress: _intro),
                        const SizedBox(height: 26),
                        _RisingFade(
                          progress: _intro,
                          interval: _at(900, 300),
                          child: const KitchenInWordmark(
                            fontSize: 52,
                            onDark: true,
                          ),
                        ),
                        const SizedBox(height: 14),
                        // The rule stays as the closing beat of the intro;
                        // the tagline that used to follow it is gone.
                        _WipingRule(progress: _intro),
                      ],
                    ),
                  ),
                  // A loader and nothing else. The splash used to offer
                  // "Get started" and "I already have an account", which put
                  // the first decision of the app on top of a brand animation
                  // and duplicated the onboarding's own call to action. Where
                  // the user goes next is the router's business, and it
                  // already knows: first launch gets the onboarding, everyone
                  // else goes to login or straight to their home.
                  //
                  // It still waits for 1400 ms, so a fast auth check cannot
                  // pop a spinner in over an arch that is still drawing.
                  Positioned(
                    bottom: media.padding.bottom + 46,
                    left: 28,
                    right: 28,
                    child: FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _intro,
                        curve: _at(1400, 300),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _driftingCircle({
    required AnimationController controller,
    required double diameter,
    required double opacity,
    required Offset travel,
    double? top,
    double? left,
    double? right,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      width: diameter,
      height: diameter,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Transform.translate(
          offset: travel * controller.value,
          child: child,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
          ),
        ),
      ),
    );
  }
}

/// The glass tile, the arch that draws itself, and the dot that drops in.
class _AnimatedMark extends StatelessWidget {
  const _AnimatedMark({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final tile = CurvedAnimation(parent: progress, curve: _at(60, 560));
    final arch = CurvedAnimation(parent: progress, curve: _at(420, 620));
    final dot = CurvedAnimation(parent: progress, curve: _at(860, 200));

    return SizedBox.square(
      dimension: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FadeTransition(
            opacity: tile,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.82, end: 1).animate(tile),
              child: const _GlassTile(),
            ),
          ),
          AnimatedBuilder(
            animation: arch,
            builder: (context, _) => CustomPaint(
              size: const Size.square(104),
              painter: _ArchPainter(arch.value),
            ),
          ),
          AnimatedBuilder(
            animation: dot,
            builder: (context, child) => Opacity(
              opacity: dot.value,
              // "Drops into the arch": the dot falls the last 18 px into place
              // rather than fading in where it lands.
              child: Transform.translate(
                offset: Offset(0, -18 * (1 - dot.value)),
                child: child,
              ),
            ),
            child: CustomPaint(
              size: const Size.square(104),
              painter: const _DotPainter(),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassTile extends StatelessWidget {
  const _GlassTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 104,
      height: 104,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
    );
  }
}

/// Draws [archPath] from its left foot to [progress] along the stroke, so the
/// arch appears to be traced: up the left leg, over the top, down the right.
class _ArchPainter extends CustomPainter {
  const _ArchPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final s = size.shortestSide / 104;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * s
      ..color = Colors.white;

    final path = archPath(s);
    if (progress >= 1) {
      canvas.drawPath(path, paint);
      return;
    }

    for (final metric in path.computeMetrics()) {
      canvas.drawPath(metric.extractPath(0, metric.length * progress), paint);
    }
  }

  @override
  bool shouldRepaint(_ArchPainter old) => old.progress != progress;
}

class _DotPainter extends CustomPainter {
  const _DotPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 104;
    canvas.drawCircle(
      Offset(52 * s, 62 * s),
      6.5 * s,
      Paint()..color = AppColors.pistachio,
    );
  }

  @override
  bool shouldRepaint(_DotPainter oldDelegate) => false;
}

/// The pistachio rule under the wordmark, wiping out from the centre.
class _WipingRule extends StatelessWidget {
  const _WipingRule({required this.progress});

  final Animation<double> progress;

  @override
  Widget build(BuildContext context) {
    final wipe = CurvedAnimation(parent: progress, curve: _at(1040, 260));

    return AnimatedBuilder(
      animation: wipe,
      builder: (context, child) =>
          SizedBox(height: 3, width: 64 * wipe.value, child: child),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.pistachio,
          borderRadius: BorderRadius.all(Radius.circular(1.5)),
        ),
      ),
    );
  }
}

/// Rises 14 px and fades in — the entrance the wordmark and the tagline share.
class _RisingFade extends StatelessWidget {
  const _RisingFade({
    required this.progress,
    required this.interval,
    required this.child,
  });

  final Animation<double> progress;
  final Interval interval;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = CurvedAnimation(parent: progress, curve: interval);

    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - animation.value)),
          child: child,
        ),
        child: child,
      ),
    );
  }
}
