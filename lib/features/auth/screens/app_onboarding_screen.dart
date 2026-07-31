import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/tokens.dart';
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

class AppOnboardingScreen extends StatefulWidget {
  const AppOnboardingScreen({super.key});

  @override
  State<AppOnboardingScreen> createState() => _AppOnboardingScreenState();
}

class _AppOnboardingScreenState extends State<AppOnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await AppOnboarding.markSeen();
    if (!mounted) return;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      (
        icon: Icons.storefront_rounded,
        title: context.l10n.onboardingTitle1,
        body: context.l10n.onboardingBody1,
      ),
      (
        icon: Icons.delivery_dining_rounded,
        title: context.l10n.onboardingTitle2,
        body: context.l10n.onboardingBody2,
      ),
      (
        icon: Icons.account_balance_wallet_rounded,
        title: context.l10n.onboardingTitle3,
        body: context.l10n.onboardingBody3,
      ),
    ];
    final last = _page == pages.length - 1;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextButton(
                  onPressed: _finish,
                  child: Text(context.l10n.skip,
                      style: const TextStyle(
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final page = pages[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 160,
                          height: 160,
                          decoration: BoxDecoration(
                            color: AppColors.warmFill,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(page.icon,
                              size: 72, color: AppColors.primary),
                        ),
                        const SizedBox(height: 40),
                        Text(page.title,
                            textAlign: TextAlign.center,
                            style: AppType.display(26)),
                        const SizedBox(height: 14),
                        Text(page.body,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 14.5,
                                height: 1.5,
                                color: AppColors.textSecondary)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < pages.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: i == _page ? 22 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _page
                          ? AppColors.primary
                          : const Color(0xFFE4DDD4),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 26, 28, 30),
              child: FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54)),
                onPressed: last
                    ? _finish
                    : () => _controller.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic),
                child: Text(last
                    ? context.l10n.getStarted
                    : context.l10n.next),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
