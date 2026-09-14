import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../repositories/chat_repository.dart';

/// Puts a live unread count on whatever opens an order's chat, so a new
/// message from the driver or the customer is noticed without opening it.
class ChatUnreadBadge extends StatefulWidget {
  const ChatUnreadBadge({
    super.key,
    required this.orderId,
    required this.child,
    this.top = -6,
    this.end = -6,
  });

  final String orderId;
  final Widget child;
  final double top;
  final double end;

  @override
  State<ChatUnreadBadge> createState() => _ChatUnreadBadgeState();
}

class _ChatUnreadBadgeState extends State<ChatUnreadBadge> {
  late final Stream<int> _unread = ChatRepository().watchUnread(widget.orderId);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _unread,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            widget.child,
            if (count > 0)
              PositionedDirectional(
                top: widget.top,
                end: widget.end,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(count),
                  tween: Tween(begin: 0.6, end: 1),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 20),
                    height: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: AppColors.dangerInk,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
