import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/locale_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../brand_logo.dart';
import '../messages_button.dart';
import '../notification_bell.dart';

/// One row in a [WebShellFrame] sidebar.
class WebNavItem {
  const WebNavItem({
    required this.id,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selectedIcon,
  });

  /// Compared against [WebShellFrame.activeId] to decide the highlight —
  /// a plain string rather than a route, so a flat-routed page (which has
  /// no branch index of its own) can still claim the section it belongs to.
  final String id;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final VoidCallback onTap;
}

/// A group of [WebNavItem]s under an optional uppercase header. A `null`
/// [title] renders as ungrouped, flush against the sidebar's pinned top
/// section.
class WebNavSection {
  const WebNavSection({this.title, required this.items});

  final String? title;
  final List<WebNavItem> items;
}

/// The persistent desktop chrome every admin/vendor web screen sits inside:
/// a fixed sidebar (brand mark, grouped navigation) and a slim top bar,
/// wrapping a content area capped at [maxContentWidth] so tables and forms
/// don't stretch edge-to-edge on a monitor.
///
/// Deliberately dumb about auth — [onSignOut] is a plain callback so this
/// widget has no dependency on `AuthCubit` and can serve both the admin and
/// vendor sides.
class WebShellFrame extends StatelessWidget {
  const WebShellFrame({
    super.key,
    required this.activeId,
    required this.sections,
    required this.child,
    required this.pageTitle,
    this.onSignOut,
    this.maxContentWidth = 1200,
    this.forStaff = false,
  });

  final String activeId;
  final List<WebNavSection> sections;
  final Widget child;
  final String pageTitle;
  final VoidCallback? onSignOut;
  final double maxContentWidth;

  /// True in the admin console: the top bar's messages icon badges the
  /// support queue (threads waiting on staff) rather than the vendor
  /// console's "replies waiting for me" count — the same distinction
  /// [MessagesButton.staff] draws.
  final bool forStaff;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Row(
        // Without this the Row centres its children on the cross axis, and
        // the sidebar — whose height is just its scroll view's content —
        // floats as a short box in the middle of the window with dead space
        // above and below it. The admin's twenty-odd rows overflow the
        // viewport and hid this; the vendor's eight made it obvious.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Sidebar(activeId: activeId, sections: sections),
          const VerticalDivider(
            width: 1,
            thickness: 1,
            color: AppColors.border,
          ),
          Expanded(
            child: Column(
              children: [
                _TopBar(
                  title: pageTitle,
                  onSignOut: onSignOut,
                  forStaff: forStaff,
                ),
                const Divider(height: 1, thickness: 1, color: AppColors.border),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxContentWidth),
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps [child] in [WebShellFrame] only on a wide web tab
/// (`AppBreakpoints.isWebWide`); returns [child] unchanged everywhere else.
/// Lets a screen that is routed as a flat push — outside any
/// `StatefulNavigationShell` branch — opt into looking like part of the
/// persistent shell on web, without the router having to know about it.
class WebPageChrome extends StatelessWidget {
  const WebPageChrome({
    super.key,
    required this.activeId,
    required this.sections,
    required this.pageTitle,
    required this.child,
    this.onSignOut,
    this.maxContentWidth = 1200,
    this.forStaff = false,
  });

  final String activeId;
  final List<WebNavSection> sections;
  final String pageTitle;
  final Widget child;
  final VoidCallback? onSignOut;
  final double maxContentWidth;
  final bool forStaff;

  @override
  Widget build(BuildContext context) {
    if (!AppBreakpoints.isWebWide(context)) return child;
    return WebShellFrame(
      activeId: activeId,
      sections: sections,
      pageTitle: pageTitle,
      onSignOut: onSignOut,
      maxContentWidth: maxContentWidth,
      forStaff: forStaff,
      child: child,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.activeId, required this.sections});

  final String activeId;
  final List<WebNavSection> sections;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Same height as [_TopBar], so the rule under the brand and the
          // rule under the page title are one continuous line across the
          // window. Outside the scroll view: the brand stays put while a
          // long list of destinations scrolls beneath it.
          const SizedBox(
            height: 64,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  KitchenInMark(size: 28),
                  SizedBox(width: AppSpace.sm),
                  Text(
                    'Kitchen IN',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final section in sections) ...[
                    if (section.title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                        child: Text(
                          section.title!.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                    for (final item in section.items)
                      _SidebarItem(item: item, selected: item.id == activeId),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({required this.item, required this.selected});

  final WebNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? AppColors.warmFill : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(
                  selected ? (item.selectedIcon ?? item.icon) : item.icon,
                  size: 19,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? AppColors.primary : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title, this.onSignOut, this.forStaff = false});

  final String title;
  final VoidCallback? onSignOut;
  final bool forStaff;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl),
      color: AppColors.surface,
      child: Row(
        children: [
          Text(title, style: AppType.heading(18)),
          const Spacer(),
          // Two different questions, two icons: "is there anything new"
          // (mixed feed — settlements, announcements, support replies) versus
          // "do I have a message waiting" (support only). Neither console had
          // either entry point before; a settlement event or a support reply
          // left no trace once its push was dismissed.
          if (forStaff)
            const MessagesButton.staff(compact: true)
          else
            const MessagesButton(compact: true),
          const SizedBox(width: AppSpace.sm),
          const NotificationBell(compact: true),
          const SizedBox(width: AppSpace.sm),
          // On a phone the language lives in Settings, which every role has.
          // The consoles do not — an admin's settings are the Manage hub, a
          // vendor's are store settings — so on web the switch belongs in the
          // one bar that is on screen no matter which page you are on.
          const _LanguageToggle(),
          const SizedBox(width: AppSpace.sm),
          if (onSignOut != null)
            PopupMenuButton<void>(
              tooltip: '',
              offset: const Offset(0, 44),
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  onTap: onSignOut,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.logout_rounded,
                        size: 18,
                        color: AppColors.dangerInk,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Text(
                        context.l10n.signOut,
                        style: const TextStyle(color: AppColors.dangerInk),
                      ),
                    ],
                  ),
                ),
              ],
              child: const CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.primary,
                child: Icon(
                  Icons.person_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Flips between the two languages the app ships, in one press.
///
/// A two-item dropdown is a menu for a decision that has no third option, so
/// this shows the language you would get rather than the one you are in —
/// pressing "العربية" gives you Arabic. `LocaleCubit.setLocale` persists the
/// choice and mirrors it onto the profile, so the server also composes push
/// notifications in the right language.
class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle();

  @override
  Widget build(BuildContext context) {
    final isArabic = context.watch<LocaleCubit>().state.languageCode == 'ar';
    final nextLabel = isArabic ? 'English' : 'العربية';

    return Tooltip(
      message: context.l10n.changeLanguage,
      child: Material(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: () => context.read<LocaleCubit>().setLocale(
            Locale(isArabic ? 'en' : 'ar'),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.language_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  nextLabel,
                  // The label is always in the language it switches to, so it
                  // has to be laid out in that language's direction rather
                  // than the surrounding page's.
                  textDirection: isArabic
                      ? TextDirection.ltr
                      : TextDirection.rtl,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
