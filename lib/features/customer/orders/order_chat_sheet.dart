import 'package:flutter/material.dart';
import '../../../app/tokens.dart';
import '../../../core/models/chat_message.dart';
import '../../../core/repositories/chat_repository.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/ui_kit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class OrderChatSheet extends StatefulWidget {
  const OrderChatSheet({
    super.key,
    required this.orderId,
    this.embedded = false,
  });

  final String orderId;

  /// Rendered as a full page rather than a sheet: it then fills its parent and
  /// drops the rounded sheet cap, which would otherwise float inside a
  /// Scaffold below an AppBar.
  final bool embedded;

  @override
  State<OrderChatSheet> createState() => _OrderChatSheetState();
}

class _OrderChatSheetState extends State<OrderChatSheet> {
  final ChatRepository _chatRepo = ChatRepository();
  final TextEditingController _msgController = TextEditingController();

  void _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();
    await _chatRepo.sendMessage(orderId: widget.orderId, message: text);
  }

  @override
  Widget build(BuildContext context) {
    final sheetCap = widget.embedded
        ? null
        : const BorderRadius.vertical(top: Radius.circular(AppRadii.xxl));
    return Container(
      height: widget.embedded
          ? null
          : MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: sheetCap,
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.neutralFill,
              borderRadius: sheetCap,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline,
                        color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      context.l10n.liveChat,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatRepo.streamMessages(widget.orderId),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const _ChatSkeleton();
                final messages = snapshot.data!;
                if (messages.isEmpty) {
                  return Center(
                    child: Text(
                      context.l10n.noMessagesYet,
                      style: const TextStyle(color: AppColors.textMuted),
                    ),
                  );
                }
                final currentUserId = _chatRepo.currentUserId;
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == currentUserId;
                    final timeStr =
                        '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';

                    return Align(
                      alignment: isMe
                          ? AlignmentDirectional.centerEnd
                          : AlignmentDirectional.centerStart,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppColors.primary
                              : AppColors.warmFill,
                          borderRadius: BorderRadiusDirectional.only(
                            topStart: const Radius.circular(16),
                            topEnd: const Radius.circular(16),
                            // The clipped corner points back at its author.
                            bottomStart: isMe
                                ? const Radius.circular(16)
                                : const Radius.circular(4),
                            bottomEnd: isMe
                                ? const Radius.circular(4)
                                : const Radius.circular(16),
                          ).resolve(Directionality.of(context)),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: isMe
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Text(
                              msg.message,
                              style: TextStyle(
                                fontSize: 14.5,
                                color: isMe ? Colors.white : AppColors.ink,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: isMe
                                    ? Colors.white.withValues(alpha: 0.75)
                                    : AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.of(context).padding.bottom > 0 ? 8 : 12,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgController,
                      decoration: InputDecoration(
                        hintText: context.l10n.typeYourMessage,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppRadii.xxl),
                          borderSide:
                              const BorderSide(color: AppColors.border),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: IconButton(
                      icon: const DirectionalIcon(Icons.send,
                          color: Colors.white),
                      onPressed: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The thread while the first page streams in: alternating bubbles, so the
/// shape of a conversation is legible before a single word arrives.
class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  static const _widths = [0.62, 0.44, 0.7];

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.md),
        children: [
          for (var i = 0; i < _widths.length; i++)
            Align(
              alignment: i.isEven
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              child: FractionallySizedBox(
                widthFactor: _widths[i],
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpace.xs),
                  child: Skeleton(height: 44, radius: AppRadii.lg),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-page wrapper around [OrderChatSheet].
///
/// A tapped chat notification has to open the thread from a cold start, where
/// there is no screen underneath to present a sheet from — so the same widget
/// is also reachable as its own route.
class OrderChatScreen extends StatelessWidget {
  const OrderChatScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(title: Text(context.l10n.chat)),
      body: SafeArea(child: OrderChatSheet(orderId: orderId, embedded: true)),
    );
  }
}
