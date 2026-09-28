import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

/// The building blocks every desktop console page (admin and store) is made
/// of, so thirty pages read as one product rather than thirty screens.
///
/// A page is a [ConsolePage]: a header that says what the page is for and
/// holds its main action, an optional toolbar (search, filters), then the
/// content — [ConsolePanel]s, [ConsoleStat]s, a `WebTable`. Nothing here
/// knows about data; each page brings its own.

/// How wide a page's content runs.
enum ConsoleWidth {
  /// Tables, boards and dashboards: use the screen.
  wide(1440),

  /// Mixed pages: a detail view, a report.
  regular(1180),

  /// Forms and settings: a line of labels and fields should not stretch
  /// across a monitor.
  form(820);

  const ConsoleWidth(this.maxWidth);
  final double maxWidth;
}

/// One console page: header, optional toolbar, body.
class ConsolePage extends StatelessWidget {
  const ConsolePage({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
    this.toolbar,
    required this.children,
    this.width = ConsoleWidth.wide,
    this.onRefresh,
  });

  final String title;

  /// One sentence: what this page is for, in the operator's words.
  final String? description;

  /// Right-aligned in the header. The first is the page's main action.
  final List<Widget> actions;

  /// Search and filters, directly above the content they narrow.
  final Widget? toolbar;

  final List<Widget> children;
  final ConsoleWidth width;

  /// Offered as pull-to-refresh on touch and a header button on desktop.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 48),
      children: [
        Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConsoleHeader(
                  title: title,
                  description: description,
                  actions: [
                    if (onRefresh != null)
                      IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).refreshIndicatorSemanticLabel,
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        color: AppColors.textSecondary,
                      ),
                    ...actions,
                  ],
                ),
                if (toolbar != null) ...[
                  const SizedBox(height: AppSpace.xl),
                  toolbar!,
                ],
                const SizedBox(height: AppSpace.xl),
                ...children,
              ],
            ),
          ),
        ),
      ],
    );
    return onRefresh == null
        ? list
        : RefreshIndicator(
            color: AppColors.primary,
            onRefresh: onRefresh!,
            child: list,
          );
  }
}

/// A page's title line: the name, one sentence under it, the actions across.
class ConsoleHeader extends StatelessWidget {
  const ConsoleHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
  });

  final String title;
  final String? description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    // Inside a tab the tab already names the page: keep what it is for and
    // its action, drop the second title.
    if (ConsoleTabScope.of(context)) {
      final note = description == null
          ? const SizedBox.shrink()
          : Text(
              description!,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            );
      if (actions.isEmpty) return note;
      return Row(
        children: [
          Expanded(child: note),
          const SizedBox(width: AppSpace.lg),
          Wrap(spacing: AppSpace.sm, children: actions),
        ],
      );
    }
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: AppType.display(26)),
        if (description != null) ...[
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              description!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ],
    );
    if (actions.isEmpty) return text;
    // Full width whatever the parent aligns to, so the actions reach the
    // far edge rather than sitting beside the title.
    return SizedBox(width: double.infinity, child: _headerWrap(text));
  }

  Widget _headerWrap(Widget text) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      runSpacing: AppSpace.md,
      spacing: AppSpace.lg,
      children: [
        text,
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        ),
      ],
    );
  }
}

/// A titled block of related content. Panels are the only card-like surface
/// in the console; what sits inside them is flat.
class ConsolePanel extends StatelessWidget {
  const ConsolePanel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.tone = ConsoleTone.plain,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Colours the edge, for a panel that has to be noticed (a warning, a
  /// destructive zone). Plain everywhere else.
  final ConsoleTone tone;

  @override
  Widget build(BuildContext context) {
    final hasHeader = title != null || trailing != null;
    return Container(
      decoration: BoxDecoration(
        color: tone.fill ?? AppColors.surface,
        border: Border.all(color: tone.edge ?? AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (title != null)
                          Text(title!, style: AppType.heading(16)),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

/// The few colours a panel or stat may take to say something.
enum ConsoleTone {
  plain(null, null, AppColors.primary),
  good(AppColors.successFill, Color(0xFFBFE6CE), AppColors.successInk),
  warn(AppColors.amberFill, Color(0xFFF6D9A8), AppColors.amberInk),
  danger(AppColors.dangerFill, Color(0xFFF1C2BC), AppColors.dangerInk),
  brand(AppColors.warmFill, AppColors.attentionBorder, AppColors.primary);

  const ConsoleTone(this.fill, this.edge, this.ink);
  final Color? fill;
  final Color? edge;
  final Color ink;
}

/// One figure an operator watches: a label, the number, and one line of
/// context. Tappable when there is somewhere to go from it.
class ConsoleStat extends StatelessWidget {
  const ConsoleStat({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.tone = ConsoleTone.plain,
    this.onTap,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final ConsoleTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: tone.ink),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 15,
                  color: AppColors.textFaint,
                ),
            ],
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: AppType.display(
                26,
                color: tone == ConsoleTone.plain ? AppColors.ink : tone.ink,
              ),
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 2),
            Text(
              hint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ],
      ),
    );
    // Only a warning fills the tile; a good number is just a green number.
    final loud = tone == ConsoleTone.warn || tone == ConsoleTone.danger;
    return Material(
      color: loud ? tone.fill! : AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: loud ? tone.edge! : AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}

/// Lays [children] out in as many equal columns as fit at [minTileWidth],
/// up to [maxColumns]. For stat rows and grids of panels.
class ConsoleGrid extends StatelessWidget {
  const ConsoleGrid({
    super.key,
    required this.children,
    this.minTileWidth = 220,
    this.maxColumns = 4,
    this.spacing = AppSpace.lg,
  });

  final List<Widget> children;
  final double minTileWidth;
  final int maxColumns;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit =
            ((constraints.maxWidth + spacing) / (minTileWidth + spacing))
                .floor()
                .clamp(1, maxColumns);
        final width = (constraints.maxWidth - spacing * (fit - 1)) / fit;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// A settings row: what it is and why on the left, the control on the right.
/// Stacks on a narrow pane.
class ConsoleFieldRow extends StatelessWidget {
  const ConsoleFieldRow({
    super.key,
    required this.label,
    this.help,
    required this.child,
  });

  final String label;
  final String? help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        if (help != null) ...[
          const SizedBox(height: 3),
          Text(
            help!,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 620) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              text,
              const SizedBox(height: AppSpace.sm),
              child,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 260, child: text),
            const SizedBox(width: AppSpace.xxl),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

/// What an empty list says: what would be here, and what to do about it.
class ConsoleEmpty extends StatelessWidget {
  const ConsoleEmpty({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.warmFill,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: AppSpace.md),
          Text(title, textAlign: TextAlign.center, style: AppType.heading(16)),
          if (message != null) ...[
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: AppSpace.lg), action!],
        ],
      ),
    );
  }
}

/// Search and filter controls above a list. The search field takes what room
/// is left; filters and a trailing action sit beside it and wrap on a narrow
/// pane.
class ConsoleToolbar extends StatelessWidget {
  const ConsoleToolbar({
    super.key,
    this.search,
    this.filters = const [],
    this.trailing = const [],
  });

  final Widget? search;
  final List<Widget> filters;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpace.sm,
      runSpacing: AppSpace.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (search != null) SizedBox(width: 340, child: search),
        ...filters,
        ...trailing,
      ],
    );
  }
}

/// The console's search field: compact, with a clear button once there is
/// something to clear.
class ConsoleSearchField extends StatefulWidget {
  const ConsoleSearchField({
    super.key,
    required this.hint,
    required this.onChanged,
    this.initialValue = '',
  });

  final String hint;
  final ValueChanged<String> onChanged;
  final String initialValue;

  @override
  State<ConsoleSearchField> createState() => _ConsoleSearchFieldState();
}

class _ConsoleSearchFieldState extends State<ConsoleSearchField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: (value) {
        setState(() {});
        widget.onChanged(value);
      },
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hint,
        filled: true,
        fillColor: AppColors.surface,
        prefixIcon: const Icon(
          Icons.search_rounded,
          size: 19,
          color: AppColors.textMuted,
        ),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () {
                  _controller.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

/// A filter chip for a [ConsoleToolbar]: a label and, when it matters, how
/// many rows it would show.
class ConsoleFilterChip extends StatelessWidget {
  const ConsoleFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.count,
    this.tone = ConsoleTone.plain,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final int? count;
  final ConsoleTone tone;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : AppColors.textSecondary;
    final bg = selected
        ? (tone == ConsoleTone.plain ? AppColors.ink : tone.ink)
        : AppColors.surface;
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        side: BorderSide(
          color: selected ? Colors.transparent : AppColors.border,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white.withValues(alpha: 0.75)
                        : (tone == ConsoleTone.plain
                              ? AppColors.textFaint
                              : tone.ink),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Slides [child] in from the end edge over the page, for looking at one
/// thing (an order, a store) without losing the list it came from. Closes on
/// the barrier, Escape, or its own close button.
Future<T?> showConsoleSidePanel<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  double width = 620,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: AppColors.ink.withValues(alpha: 0.24),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, _) => Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Material(
        color: AppColors.canvas,
        elevation: 0,
        child: Container(
          width: width,
          height: double.infinity,
          decoration: const BoxDecoration(
            boxShadow: AppShadows.dialog,
            color: AppColors.canvas,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 64,
                color: AppColors.surface,
                padding: const EdgeInsetsDirectional.only(start: 24, end: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.heading(17),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, _, child) {
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return SlideTransition(
        position:
            Tween<Offset>(
              begin: Offset(rtl ? -0.25 : 0.25, 0),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

/// Marks a page that is shown as one tab of a larger console page, so its
/// [ConsoleHeader] shrinks to a one-line toolbar instead of repeating a title
/// the tab bar already shows.
class ConsoleTabScope extends InheritedWidget {
  const ConsoleTabScope({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConsoleTabScope>() != null;

  @override
  bool updateShouldNotify(ConsoleTabScope oldWidget) => false;
}
