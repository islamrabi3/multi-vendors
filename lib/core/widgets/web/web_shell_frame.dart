import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/locale_cubit.dart';
import '../../../app/tokens.dart';
import '../../utils/l10n_extension.dart';
import '../brand_logo.dart';
import '../count_badge.dart';
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
    this.badge,
  });

  /// Compared against [WebShellFrame.activeId] to decide the highlight —
  /// a plain string rather than a route, so a flat-routed page (which has
  /// no branch index of its own) can still claim the section it belongs to.
  final String id;
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final VoidCallback onTap;

  /// Items waiting on the user behind this entry; hidden at zero.
  final ValueListenable<int>? badge;
}

/// A group of [WebNavItem]s under an optional header. A `null` [title]
/// renders as ungrouped, flush against the sidebar's pinned top section.
class WebNavSection {
  const WebNavSection({this.title, required this.items});

  final String? title;
  final List<WebNavItem> items;
}

/// Something the command palette can do: open a page, open an order.
class WebCommand {
  const WebCommand({
    required this.label,
    required this.icon,
    required this.onRun,
    this.detail,
  });

  final String label;
  final IconData icon;
  final VoidCallback onRun;

  /// Where it lives, or what it is: "Finance", "Order · Burger Lab".
  final String? detail;
}

/// Looks [query] up in the console's data — orders by number, stores by name
/// — for the command palette. Called only for queries of two characters or
/// more, and debounced.
typedef WebCommandSearch = Future<List<WebCommand>> Function(String query);

/// Whether the sidebar is folded down to icons. One setting for both
/// consoles, kept across sessions: an operator who wants the room once wants
/// it every time.
class _SidebarPrefs {
  _SidebarPrefs._();

  static const _key = 'web_sidebar_collapsed';
  static final collapsed = ValueNotifier<bool>(false);
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      collapsed.value = prefs.getBool(_key) ?? false;
    } catch (_) {}
  }

  static Future<void> toggle() async {
    collapsed.value = !collapsed.value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, collapsed.value);
    } catch (_) {}
  }
}

/// The persistent desktop chrome every admin/vendor web screen sits inside:
/// a sidebar (brand, grouped navigation, the signed-in account) and a slim
/// top bar (where you are, a way to jump anywhere, what is waiting), around
/// a content area capped at [maxContentWidth].
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
    this.consoleLabel,
    this.accountName,
    this.accountDetail,
    this.search,
    this.onOpenMessages,
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

  /// Under the brand: which console this is — "Admin", or the store's name.
  final String? consoleLabel;

  /// Who is signed in, and as what, for the account block at the foot of the
  /// sidebar.
  final String? accountName;
  final String? accountDetail;

  /// Data lookups the command palette offers beside the pages.
  final WebCommandSearch? search;

  /// Where the top bar's messages icon leads inside this console. Null keeps
  /// the icon's own route.
  final VoidCallback? onOpenMessages;

  List<WebCommand> _pageCommands() => [
    for (final section in sections)
      for (final item in section.items)
        WebCommand(
          label: item.label,
          icon: item.icon,
          detail: section.title,
          onRun: item.onTap,
        ),
  ];

  String? get _sectionTitle {
    for (final section in sections) {
      if (section.items.any((i) => i.id == activeId)) return section.title;
    }
    return null;
  }

  void _openPalette(BuildContext context) =>
      showWebCommandPalette(context, commands: _pageCommands(), search: search);

  @override
  Widget build(BuildContext context) {
    _SidebarPrefs.load();
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openPalette(context),
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () =>
            _openPalette(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: AppColors.canvas,
          body: Row(
            // Without this the Row centres its children on the cross axis,
            // and the sidebar floats as a short box mid-window.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: _SidebarPrefs.collapsed,
                builder: (context, collapsed, _) => _Sidebar(
                  activeId: activeId,
                  sections: sections,
                  collapsed: collapsed,
                  consoleLabel: consoleLabel,
                  accountName: accountName,
                  accountDetail: accountDetail,
                  onSignOut: onSignOut,
                ),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.border,
              ),
              Expanded(
                child: Column(
                  children: [
                    _TopBar(
                      section: _sectionTitle,
                      title: pageTitle,
                      forStaff: forStaff,
                      onOpenPalette: () => _openPalette(context),
                      onOpenMessages: onOpenMessages,
                    ),
                    const Divider(
                      height: 1,
                      thickness: 1,
                      color: AppColors.border,
                    ),
                    Expanded(
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: maxContentWidth,
                          ),
                          child: child,
                        ),
                      ),
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
  const _Sidebar({
    required this.activeId,
    required this.sections,
    required this.collapsed,
    this.consoleLabel,
    this.accountName,
    this.accountDetail,
    this.onSignOut,
  });

  final String activeId;
  final List<WebNavSection> sections;
  final bool collapsed;
  final String? consoleLabel;
  final String? accountName;
  final String? accountDetail;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 76 : 264,
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Same height as [_TopBar], so the rule under the brand and the
          // rule under the page title are one continuous line.
          SizedBox(
            height: 64,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 18),
              child: Row(
                mainAxisAlignment: collapsed
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start,
                children: [
                  const KitchenInMark(size: 30),
                  if (!collapsed) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Kitchen IN',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              height: 1.1,
                            ),
                          ),
                          if (consoleLabel != null)
                            Text(
                              consoleLabel!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
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
                  for (final (index, section) in sections.indexed) ...[
                    if (section.title != null)
                      collapsed
                          ? Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 10,
                              ),
                              child: index == 0
                                  ? const SizedBox.shrink()
                                  : const Divider(
                                      height: 1,
                                      color: AppColors.borderSoft,
                                    ),
                            )
                          : Padding(
                              padding: const EdgeInsets.fromLTRB(24, 18, 20, 6),
                              child: Text(
                                section.title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ),
                    for (final item in section.items)
                      _SidebarItem(
                        item: item,
                        selected: item.id == activeId,
                        collapsed: collapsed,
                      ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.border),
          _AccountBlock(
            collapsed: collapsed,
            name: accountName,
            detail: accountDetail,
            onSignOut: onSignOut,
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.item,
    required this.selected,
    required this.collapsed,
  });

  final WebNavItem item;
  final bool selected;
  final bool collapsed;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final selected = widget.selected;
    final icon = Icon(
      selected ? (item.selectedIcon ?? item.icon) : item.icon,
      size: 20,
      color: selected ? AppColors.primary : AppColors.textSecondary,
    );
    final Widget content = widget.collapsed
        ? SizedBox(
            height: 42,
            child: Center(
              child: item.badge == null
                  ? icon
                  : ValueListenableBuilder<int>(
                      valueListenable: item.badge!,
                      builder: (context, count, child) => Badge(
                        isLabelVisible: count > 0,
                        smallSize: 8,
                        backgroundColor: AppColors.dangerInk,
                        child: child,
                      ),
                      child: icon,
                    ),
            ),
          )
        : SizedBox(
            height: 40,
            child: Row(
              children: [
                // The active page's edge: one aubergine bar, where the eye
                // lands when scanning the list.
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: selected ? 20 : 0,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 9),
                icon,
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
                if (item.badge != null) CountBadge(count: item.badge!),
                const SizedBox(width: 10),
              ],
            ),
          );

    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          color: selected
              ? AppColors.warmFill
              : _hovered
              ? AppColors.canvas
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: content,
          ),
        ),
      ),
    );
    return widget.collapsed
        ? Tooltip(
            message: item.label,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 300),
            child: tile,
          )
        : tile;
  }
}

/// Who is signed in, the one-press fold of the sidebar, and the account menu.
class _AccountBlock extends StatelessWidget {
  const _AccountBlock({
    required this.collapsed,
    this.name,
    this.detail,
    this.onSignOut,
  });

  final bool collapsed;
  final String? name;
  final String? detail;
  final VoidCallback? onSignOut;

  String get _initials {
    final parts = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '·';
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final avatar = CircleAvatar(
      radius: 17,
      backgroundColor: AppColors.primary,
      child: Text(
        _initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final menu = PopupMenuButton<void>(
      tooltip: l10n.account,
      position: PopupMenuPosition.over,
      offset: const Offset(0, -120),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: () => GoRouter.of(context).push('/change-password'),
          child: _MenuRow(icon: Icons.key_rounded, label: l10n.changePassword),
        ),
        if (onSignOut != null)
          PopupMenuItem<void>(
            onTap: onSignOut,
            child: _MenuRow(
              icon: Icons.logout_rounded,
              label: l10n.signOut,
              danger: true,
            ),
          ),
      ],
      child: collapsed
          ? Padding(padding: const EdgeInsets.all(4), child: avatar)
          : Row(
              children: [
                avatar,
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (name ?? '').trim().isEmpty ? l10n.account : name!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (detail != null)
                        Text(
                          detail!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.unfold_more_rounded,
                  size: 18,
                  color: AppColors.textFaint,
                ),
              ],
            ),
    );

    final fold = IconButton(
      tooltip: collapsed ? l10n.expandSidebar : l10n.collapseSidebar,
      onPressed: _SidebarPrefs.toggle,
      // Points the way the sidebar will move: toward its own edge to fold,
      // away from it to open — mirrored in right-to-left.
      icon: Icon(
        collapsed == (Directionality.of(context) == TextDirection.ltr)
            ? Icons.keyboard_double_arrow_right_rounded
            : Icons.keyboard_double_arrow_left_rounded,
        size: 20,
      ),
      color: AppColors.textMuted,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
      child: collapsed
          ? Column(mainAxisSize: MainAxisSize.min, children: [menu, fold])
          : Row(
              children: [
                Expanded(child: menu),
                fold,
              ],
            ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.dangerInk : AppColors.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpace.sm),
        Text(label, style: TextStyle(color: danger ? color : null)),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onOpenPalette,
    this.section,
    this.forStaff = false,
    this.onOpenMessages,
  });

  final String? section;
  final String title;
  final VoidCallback onOpenPalette;
  final bool forStaff;
  final VoidCallback? onOpenMessages;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 28),
      color: AppColors.surface,
      child: Row(
        children: [
          // Where you are: the group the page belongs to, then the page.
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (section != null && section != title) ...[
                  Flexible(
                    child: Text(
                      section!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.lg),
          _PaletteButton(onTap: onOpenPalette),
          const Spacer(),
          if (forStaff)
            MessagesButton.staff(compact: true, onOpen: onOpenMessages)
          else
            MessagesButton(compact: true, onOpen: onOpenMessages),
          const SizedBox(width: AppSpace.sm),
          const NotificationBell(compact: true),
          const SizedBox(width: AppSpace.sm),
          // The consoles have no Settings page of the phone kind, so the
          // language switch lives in the one bar that is always on screen.
          const _LanguageToggle(),
        ],
      ),
    );
  }
}

/// Looks like a search field, opens the command palette. Also ⌘K / Ctrl+K.
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: onTap,
        child: Container(
          width: 300,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.search_rounded,
                size: 18,
                color: AppColors.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.l10n.jumpToAnything,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  mac ? '⌘K' : 'Ctrl K',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the command palette: type to jump to any page in the sidebar, or to
/// whatever [search] finds (an order by number, a store by name).
Future<void> showWebCommandPalette(
  BuildContext context, {
  required List<WebCommand> commands,
  WebCommandSearch? search,
}) => showDialog<void>(
  context: context,
  barrierColor: AppColors.ink.withValues(alpha: 0.28),
  builder: (_) => _CommandPalette(commands: commands, search: search),
);

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.commands, this.search});

  final List<WebCommand> commands;
  final WebCommandSearch? search;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<WebCommand> _found = const [];
  bool _searching = false;
  int _index = 0;
  int _searchToken = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  List<WebCommand> get _pages {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return widget.commands;
    return widget.commands
        .where(
          (c) =>
              c.label.toLowerCase().contains(q) ||
              (c.detail?.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  List<WebCommand> get _results => [..._found, ..._pages];

  void _onChanged(String _) {
    setState(() => _index = 0);
    _debounce?.cancel();
    final q = _query.text.trim();
    if (widget.search == null || q.length < 2) {
      setState(() {
        _found = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final token = ++_searchToken;
      try {
        final found = await widget.search!(q);
        if (!mounted || token != _searchToken) return;
        setState(() {
          _found = found;
          _searching = false;
        });
      } catch (_) {
        if (!mounted || token != _searchToken) return;
        setState(() {
          _found = const [];
          _searching = false;
        });
      }
    });
  }

  void _run(WebCommand command) {
    Navigator.of(context).pop();
    command.onRun();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final results = _results;
    if (results.isEmpty) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + 1).clamp(0, results.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _index = (_index - 1).clamp(0, results.length - 1));
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      _run(results[_index.clamp(0, results.length - 1)]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Container(
        width: 620,
        constraints: const BoxConstraints(maxHeight: 520),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: AppShadows.dialog,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Focus(
            onKeyEvent: _onKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    controller: _query,
                    autofocus: true,
                    onChanged: _onChanged,
                    style: const TextStyle(fontSize: 16),
                    decoration: InputDecoration(
                      hintText: widget.search == null
                          ? l10n.jumpToPage
                          : l10n.jumpToAnythingHint,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
                const Divider(height: 1, color: AppColors.border),
                Flexible(
                  child: results.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(28),
                          child: Text(
                            _searching ? l10n.searching : l10n.nothingMatches,
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          itemCount: results.length,
                          itemBuilder: (context, i) {
                            final c = results[i];
                            final active = i == _index;
                            return InkWell(
                              onTap: () => _run(c),
                              onHover: (h) {
                                if (h) setState(() => _index = i);
                              },
                              child: Container(
                                color: active ? AppColors.warmFill : null,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 10,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      c.icon,
                                      size: 19,
                                      color: active
                                          ? AppColors.primary
                                          : AppColors.textSecondary,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        c.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: active
                                              ? AppColors.primary
                                              : AppColors.ink,
                                        ),
                                      ),
                                    ),
                                    if (c.detail != null) ...[
                                      const SizedBox(width: 12),
                                      Text(
                                        c.detail!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
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

/// Flips between the two languages the app ships, in one press.
///
/// Shows the language you would get rather than the one you are in —
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
                  // Always in the language it switches to, so laid out in
                  // that language's direction.
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
