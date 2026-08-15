import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/tokens.dart';
import '../../../core/widgets/brand_logo.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// First-launch intro. Shown once (persisted flag), then never again.
class AppOnboarding {
  static const _key = 'onboarding_seen_v1';
  static bool seen = true;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    seen = prefs.getBool(_key) ?? false;
  }

  static Future<void> markSeen() async {
    seen = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, true);
  }
}

/// What one page shows.
///
/// A hero glyph in a brand tile plus two or three satellite chips, over a soft
/// painted backdrop. Illustration rather than stock photography, for the same
/// reason the image placeholder is a glyph: every real food picture in this app
/// is a vendor's own upload, and shipping decorative food photos here would
/// promise a catalogue the app does not have on first launch.
class _Page {
  const _Page({
    required this.hero,
    required this.title,
    required this.body,
    required this.satellites,
    required this.accent,
  });

  final IconData hero;
  final String title;
  final String body;

  /// Small floating chips around the hero. Each one names a concrete thing the
  /// app does, so the page reads as features rather than decoration.
  final List<(IconData, String)> satellites;

  /// Tints the backdrop, so the four pages are distinguishable at a glance
  /// while staying inside the brand's two colours.
  final Color accent;
}

class AppOnboardingScreen extends StatefulWidget {
  const AppOnboardingScreen({super.key});

  @override
  State<AppOnboardingScreen> createState() => _AppOnboardingScreenState();
}

class _AppOnboardingScreenState extends State<AppOnboardingScreen>
    with TickerProviderStateMixin {
  final _controller = PageController();
  int _page = 0;

  /// Drives the slow drift of the backdrop blobs. One controller for the whole
  /// screen — the pages share a backdrop, so they should share its motion.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    _drift.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AppOnboarding.markSeen();
    if (!mounted) return;
    context.go('/login');
  }

  void _next() => _controller.nextPage(
    duration: const Duration(milliseconds: 340),
    curve: Curves.easeOutCubic,
  );

  List<_Page> _pages(BuildContext context) {
    final l10n = context.l10n;
    return [
      _Page(
        hero: Icons.storefront_rounded,
        title: l10n.onboardingTitle1,
        body: l10n.onboardingBody1,
        accent: AppColors.primary,
        satellites: [
          (Icons.restaurant_rounded, l10n.categoriesTab),
          (Icons.local_grocery_store_rounded, l10n.scopeOneStore),
          (Icons.search_rounded, l10n.searchStoresDishes),
        ],
      ),
      _Page(
        hero: Icons.delivery_dining_rounded,
        title: l10n.onboardingTitle2,
        body: l10n.onboardingBody2,
        accent: AppColors.pistachioInk,
        satellites: [
          (Icons.my_location_rounded, l10n.deliverTo),
          (Icons.access_time_filled_rounded, l10n.minutesShort(30)),
        ],
      ),
      _Page(
        hero: Icons.account_balance_wallet_rounded,
        title: l10n.onboardingTitle3,
        body: l10n.onboardingBody3,
        accent: AppColors.primaryLight,
        satellites: [
          (Icons.payments_rounded, l10n.cod),
          (Icons.credit_card_rounded, l10n.cardPaid),
          (Icons.local_offer_rounded, l10n.promos),
        ],
      ),
      _Page(
        hero: Icons.event_available_rounded,
        title: l10n.onboardingTitle4,
        body: l10n.onboardingBody4,
        accent: AppColors.primaryDark,
        satellites: [
          (Icons.event_rounded, l10n.orderTypeScheduled),
          (Icons.storefront_rounded, l10n.pickupFromBranch),
        ],
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = _pages(context);
    final last = _page == pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Stack(
        children: [
          // Behind everything, and shared across pages, so swiping moves the
          // content over a continuous scene rather than four separate ones.
          Positioned.fill(
            child: AnimatedBuilder(
              animation: Listenable.merge([_drift, _controller]),
              builder: (context, _) => CustomPaint(
                painter: _Backdrop(
                  drift: _drift.value,
                  accent: pages[_page.clamp(0, pages.length - 1)].accent,
                ),
              ),
            ),
          ),
          SafeArea(
            // The painted backdrop stays full-bleed — it is a scene, and it
            // reads correctly at any width. Only the foreground is capped:
            // a hero glyph and two lines of copy spread across 1400px stop
            // being a layout and start being a gap.
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: AppBreakpoints.isWebWide(context)
                      ? 560
                      : double.infinity,
                ),
                child: Column(
                  children: [
                    _TopBar(showSkip: !last, onSkip: _finish),
                    Expanded(
                      child: PageView.builder(
                        controller: _controller,
                        itemCount: pages.length,
                        onPageChanged: (i) => setState(() => _page = i),
                        itemBuilder: (context, i) => _PageView(page: pages[i]),
                      ),
                    ),
                    _Dots(count: pages.length, index: _page),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 12),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(54),
                        ),
                        onPressed: last ? _finish : _next,
                        child: Text(last ? l10n.getStarted : l10n.next),
                      ),
                    ),
                    // Moved here off the splash, which is where it belongs: this is
                    // the screen that asks the question, so it should carry both
                    // answers.
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: 12 + MediaQuery.paddingOf(context).bottom * 0.2,
                      ),
                      child: TextButton(
                        onPressed: _finish,
                        child: Text(l10n.iAlreadyHaveAnAccount),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.showSkip, required this.onSkip});

  final bool showSkip;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 0),
      child: Row(
        children: [
          // Flexible: at a large text scale the wordmark grows, and a rigid
          // lockup pushed Skip 39px off the right edge.
          const Flexible(child: KitchenInLockup(markSize: 28, fontSize: 16)),
          const SizedBox(width: 8),
          // Kept in the layout when hidden, so the lockup does not jump
          // sideways on the last page.
          Opacity(
            opacity: showSkip ? 1 : 0,
            child: IgnorePointer(
              ignoring: !showSkip,
              child: TextButton(
                onPressed: onSkip,
                child: Text(
                  context.l10n.skip,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    // Centred when there is room, scrollable when there is not. A fixed column
    // here overflowed by 184px on a 568pt phone at the 1.3x text scale the app
    // allows — and the one screen a new user cannot avoid is the worst place
    // to ship striped bars.
    return LayoutBuilder(
      builder: (context, constraints) {
        // The illustration is the first thing to give up space: the words are
        // what the page is for.
        final heroScale = constraints.maxHeight < 380 ? 0.72 : 1.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Hero(page: page, scale: heroScale),
                SizedBox(height: 32 * heroScale),
                Text(
                  page.title,
                  textAlign: TextAlign.center,
                  style: AppType.display(constraints.maxHeight < 380 ? 22 : 25),
                ),
                const SizedBox(height: 12),
                Text(
                  page.body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The hero tile with its satellite chips arranged around it.
///
/// A fixed 260x220 box: the chips are positioned, and letting them reflow with
/// the text would have them land on top of the tile at some sizes.
class _Hero extends StatelessWidget {
  const _Hero({required this.page, this.scale = 1});

  final _Page page;

  /// Shrinks the whole illustration on a short screen.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final tile = 132 * scale;
    return SizedBox(
      width: 260 * scale,
      height: 220 * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: tile,
            height: tile,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [page.accent, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(42 * scale),
              boxShadow: [
                BoxShadow(
                  color: page.accent.withValues(alpha: 0.30),
                  blurRadius: 28,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Icon(page.hero, size: 58 * scale, color: Colors.white),
          ),
          for (final (i, satellite) in page.satellites.indexed)
            _satellite(i, page.satellites.length, satellite),
        ],
      ),
    );
  }

  /// Chips ride a circle around the tile, spread across the arc rather than
  /// the whole ring — a chip directly below the tile would collide with the
  /// title beneath it.
  Widget _satellite(int index, int total, (IconData, String) satellite) {
    final t = total == 1 ? 0.5 : index / (total - 1);
    final angle = math.pi * (0.82 + 1.36 * t);
    return Align(
      alignment: Alignment(math.cos(angle) * 1.02, math.sin(angle) * 0.86),
      child: _Chip(icon: satellite.$1, label: satellite.$2),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.borderSoft),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            width: i == index ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: i == index ? AppColors.primary : AppColors.borderStrong,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ],
      ],
    );
  }
}

/// Two soft blobs drifting behind the content.
///
/// Painted rather than assets so they take the page's accent colour, and kept
/// under 0.10 alpha so they never compete with the text on top of them.
class _Backdrop extends CustomPainter {
  const _Backdrop({required this.drift, required this.accent});

  /// 0..1, ping-ponged by the controller.
  final double drift;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final travel = (drift - 0.5) * 2;

    void blob(Offset centre, double radius, double alpha) {
      canvas.drawCircle(
        centre,
        radius,
        Paint()..color = accent.withValues(alpha: alpha),
      );
    }

    blob(
      Offset(size.width * 0.86 + travel * 18, size.height * 0.12 - travel * 14),
      130,
      0.09,
    );
    blob(
      Offset(size.width * 0.08 - travel * 16, size.height * 0.46 + travel * 20),
      96,
      0.07,
    );
  }

  @override
  bool shouldRepaint(_Backdrop old) =>
      old.drift != drift || old.accent != accent;
}
