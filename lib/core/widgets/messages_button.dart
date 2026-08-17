import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/tokens.dart';
import '../repositories/notifications_repository.dart';
import '../repositories/support_repository.dart';

/// A visible way into support conversations, separate from [NotificationBell]
/// on purpose: the bell is a mixed feed (announcements, settlements, support
/// replies together), and "do I have a message waiting" is a different
/// question from "is there anything new" — worth its own icon and its own
/// count, the way a phone keeps Messages and Notifications apart.
class MessagesButton extends StatefulWidget {
  /// A customer/vendor/driver's own thread: badges on *their* unread staff
  /// replies, opens `/support`.
  const MessagesButton({super.key, this.compact = false, this.dark = false})
    : _forStaff = false;

  /// The admin/staff view: badges on how many threads are waiting for a
  /// reply — a queue, not an unread count — and opens the admin inbox.
  const MessagesButton.staff({super.key, this.compact = false, this.dark = false})
    : _forStaff = true;

  final bool _forStaff;
  final bool compact;
  final bool dark;

  @override
  State<MessagesButton> createState() => _MessagesButtonState();
}

class _MessagesButtonState extends State<MessagesButton> {
  late final Stream<int> _count = widget._forStaff
      ? SupportRepository().watchOpenThreadCount()
      : NotificationsRepository().watchUnreadCount(type: 'support');

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.dark ? Colors.white : AppColors.ink;
    final badgeBorder = widget.dark ? AppColors.ink : AppColors.surface;
    return StreamBuilder<int>(
      stream: _count,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return InkWell(
          onTap: () => context.push(
            widget._forStaff ? '/admin-app/support' : '/support',
          ),
          borderRadius: BorderRadius.circular(21),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.compact
                  ? Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 21,
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
                        Icons.chat_bubble_outline_rounded,
                        size: 20,
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
                      color: AppColors.primary,
                      shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: count > 9
                          ? BorderRadius.circular(AppRadii.pill)
                          : null,
                      border: Border.all(color: badgeBorder, width: 1.5),
                    ),
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
