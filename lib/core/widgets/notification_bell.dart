import 'package:flutter/material.dart';
import '../utils/l10n_extension.dart';
import '../../features/notifications/notifications_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../repositories/notifications_repository.dart';

/// The one bell every role shares, opening the same `/notifications` inbox.
///
/// Previously this existed only on the customer home page, and its badge was
/// a `Container` painted unconditionally — a permanent red dot with no
/// connection to whether anything was actually unread. Admin, vendor and
/// driver had no bell at all, so a settlement request or a support reply had
/// no in-app trace once its push was dismissed.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key, this.compact = false, this.dark = false});

  /// A plain icon at icon-button scale, for a bar that already has other
  /// small controls next to it — the web console top bar, sitting beside a
  /// language pill and a 34px avatar. The default is the standalone circular
  /// chip the customer home page uses, where the bell is the only thing in
  /// its corner.
  final bool compact;

  /// True on a dark background (the driver header), where the default chip's
  /// white circle would read as a mistake rather than a design. Only affects
  /// icon colour; `compact` is what changes the shape.
  final bool dark;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  /// On the web the bell drops a panel down from itself, the way a desktop
  /// site does, instead of replacing the page with a notifications screen.
  Future<void> _openDropdown(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? Size.zero;
    const panelWidth = 400.0;
    final top = origin.dy + size.height + 8;
    final maxHeight = (media.size.height - top - 16).clamp(260.0, 620.0);
    // Aligned to the bell's outer edge, kept on screen.
    final left = rtl
        ? origin.dx.clamp(8.0, media.size.width - panelWidth - 8)
        : (origin.dx + size.width - panelWidth).clamp(
            8.0,
            media.size.width - panelWidth - 8,
          );

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).closeButtonLabel,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) => Stack(
        children: [
          Positioned(
            top: top,
            left: left,
            width: panelWidth,
            height: maxHeight,
            child: Material(
              elevation: 12,
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(AppRadii.xl),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(18, 12, 6, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            dialogContext.l10n.notifications,
                            style: AppType.heading(17),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () => Navigator.of(dialogContext).pop(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.borderSoft),
                  const Expanded(child: NotificationsScreen(embedded: true)),
                ],
              ),
            ),
          ),
        ],
      ),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  final _repository = NotificationsRepository();
  late final Stream<int> _unread = _repository.watchUnreadCount();

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.dark ? Colors.white : AppColors.ink;
    final badgeBorder = widget.dark ? AppColors.ink : AppColors.surface;
    return StreamBuilder<int>(
      stream: _unread,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return InkWell(
          onTap: () =>
              kIsWeb ? _openDropdown(context) : context.push('/notifications'),
          borderRadius: BorderRadius.circular(21),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.compact
                  ? Icon(
                      Icons.notifications_none_rounded,
                      size: 22,
                      color: iconColor,
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.border),
                        boxShadow: AppShadows.card,
                      ),
                      child: Icon(
                        Icons.notifications_none_rounded,
                        size: 21,
                        color: iconColor,
                      ),
                    ),
              if (count > 0)
                PositionedDirectional(
                  top: widget.compact ? -3 : 9,
                  end: widget.compact ? -4 : 10,
                  child: Container(
                    padding: count > 9
                        ? const EdgeInsets.symmetric(horizontal: 4)
                        : EdgeInsets.zero,
                    width: count > 9 ? null : 9,
                    height: count > 9 ? 15 : 9,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.dangerInk,
                      shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: count > 9
                          ? BorderRadius.circular(AppRadii.pill)
                          : null,
                      border: Border.all(color: badgeBorder, width: 1.5),
                    ),
                    // Only shown past single digits — the plain dot already
                    // says "something's there" below that, and a two-digit
                    // number is the point where a bare dot stops being enough.
                    child: count > 9
                        ? Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                          )
                        : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
