import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../app/tokens.dart';
import '../../core/models/chat_conversation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/models/order.dart';
import '../../core/models/profile.dart';
import '../../core/repositories/report_repository.dart';
import '../auth/auth_cubit.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/repositories/notifications_repository.dart';
import '../../core/utils/l10n_extension.dart';
import '../../core/utils/time_format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/count_badge.dart';
import '../customer/orders/order_chat_sheet.dart';

/// Every conversation this person has, in one inbox: the chat on each order
/// (with the driver, the customer or the store) and their support thread.
///
/// Each row leads with the order number, because a driver on a busy shift —
/// or a customer with two deliveries on the way — has to know which order a
/// message is about before reading it.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _repo = ChatRepository();
  List<ChatConversation>? _items;
  Object? _error;
  StreamSubscription<int>? _unreadSub;

  /// Swiped away but still inside the Undo window — kept out of any reload.
  final Set<String> _pendingHide = {};

  @override
  void initState() {
    super.initState();
    _load();
    // Any new message or read anywhere reshuffles the list.
    _unreadSub = _repo.watchUnread().skip(1).listen((_) => _load());
  }

  @override
  void dispose() {
    _unreadSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.fetchConversations();
      if (!mounted) return;
      setState(() {
        _items = items.where((c) => !_pendingHide.contains(c.orderId)).toList();
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _open(ChatConversation c) async {
    // On a wide screen the thread opens over the inbox instead of replacing
    // it, the way a desktop messenger does.
    if (AppBreakpoints.isWebWide(context)) {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 480,
            height: 620,
            child: OrderChatSheet(orderId: c.orderId, embedded: true),
          ),
        ),
      );
    } else {
      await context.push('/order/${c.orderId}/chat');
    }
    _load();
  }

  /// Swipe either way to remove. The row goes at once; the server call waits
  /// out the Undo window, so an accidental swipe costs nothing.
  Widget _dismissible(ChatConversation c) {
    final l10n = context.l10n;
    Widget background(AlignmentGeometry alignment) => Container(
      color: AppColors.dangerInk,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.delete_outline_rounded, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            l10n.remove,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
    return Dismissible(
      key: ValueKey('conversation-${c.orderId}'),
      background: background(AlignmentDirectional.centerStart),
      secondaryBackground: background(AlignmentDirectional.centerEnd),
      onDismissed: (_) => _remove(c),
      child: _ConversationTile(conversation: c, onTap: () => _open(c)),
    );
  }

  Future<void> _remove(ChatConversation c) async {
    final l10n = context.l10n;
    final before = _items ?? const <ChatConversation>[];
    final index = before.indexWhere((x) => x.orderId == c.orderId);
    _pendingHide.add(c.orderId);
    setState(() {
      _items = [...before]..removeWhere((x) => x.orderId == c.orderId);
    });

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final closed = messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.conversationRemoved(c.orderNumber)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: l10n.undo, onPressed: () {}),
      ),
    );
    final reason = await closed.closed;

    // Leaving the screen before the snackbar closes still removes it: only
    // an explicit Undo keeps the conversation.
    if (reason == SnackBarClosedReason.action && mounted) {
      _pendingHide.remove(c.orderId);
      setState(() {
        final restored = [...?_items];
        restored.insert(index.clamp(0, restored.length), c);
        _items = restored;
      });
      return;
    }
    try {
      await _repo.hideConversation(c.orderId);
      _pendingHide.remove(c.orderId);
    } catch (error) {
      _pendingHide.remove(c.orderId);
      if (!mounted) return;
      showFailure(context, error);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = _items;

    Widget body;
    if (items == null && _error != null) {
      body = FailureView(error: _error!, onRetry: _load);
    } else if (items == null) {
      body = const LoadingView();
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            const _SupportRow(),
            if (context.read<AuthCubit>().state.profile?.role ==
                UserRole.customer) ...[
              const SizedBox(height: AppSpace.sm),
              const _ComplaintsRow(),
            ],
            const SizedBox(height: AppSpace.lg),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
              child: Text(
                l10n.orderChats,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            if (items.isNotEmpty)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: Text(
                  l10n.swipeToRemoveHint,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textFaint,
                  ),
                ),
              ),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyView(
                  message: l10n.noConversationsYet,
                  icon: Icons.forum_outlined,
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 72,
                          color: AppColors.borderSoft,
                        ),
                      _dismissible(items[i]),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.messagesTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: body,
        ),
      ),
    );
  }
}

String senderRoleLabel(BuildContext context, String role) {
  final l10n = context.l10n;
  return switch (role) {
    'driver' => l10n.driverLabel,
    'vendor' => l10n.store,
    'support' => l10n.supportChat,
    _ => l10n.customer,
  };
}

String conversationPreview(BuildContext context, ChatConversation c) {
  final l10n = context.l10n;
  final text = (c.lastMessage?.trim().isNotEmpty ?? false)
      ? c.lastMessage!.trim()
      : (c.lastHasAttachment ? '📎 ${l10n.attachment}' : '');
  final who = c.lastFromMe
      ? l10n.youLabel
      : (c.lastSenderName?.trim().isNotEmpty ?? false)
      ? '${c.lastSenderName!.trim()} (${senderRoleLabel(context, c.lastSenderRole)})'
      : senderRoleLabel(context, c.lastSenderRole);
  return '$who: $text';
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap});

  final ChatConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unread > 0;
    final status = OrderStatus.fromName(c.orderStatus);
    final roleIcon = switch (c.lastSenderRole) {
      'driver' => Icons.delivery_dining_rounded,
      'vendor' => Icons.storefront_rounded,
      _ => Icons.person_rounded,
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        color: unread ? AppColors.warmFill.withValues(alpha: 0.5) : null,
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppNetworkImage(
                  url: c.vendorLogoUrl,
                  width: 46,
                  height: 46,
                  borderRadius: BorderRadius.circular(14),
                ),
                PositionedDirectional(
                  end: -4,
                  bottom: -4,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(roleIcon, size: 12, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${context.l10n.order} ${c.orderNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontWeight: unread
                                ? FontWeight.w800
                                : FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _when(context, c.lastAt),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: unread
                              ? AppColors.primary
                              : AppColors.textFaint,
                          fontWeight: unread
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (c.vendorName != null) c.vendorName!,
                      status.localizedLabel(context),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversationPreview(context, c),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: unread ? AppColors.ink : AppColors.textMuted,
                            fontWeight: unread
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (unread) ...[
                        const SizedBox(width: 8),
                        CountBadge(count: ValueNotifier(c.unread)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _when(BuildContext context, DateTime at) {
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    if (sameDay) return formatClock(context, at);
    return DateFormat.MMMd(
      Localizations.localeOf(context).languageCode,
    ).format(at);
  }
}

/// The platform's own support thread, pinned above the order chats.
class _SupportRow extends StatefulWidget {
  const _SupportRow();

  @override
  State<_SupportRow> createState() => _SupportRowState();
}

class _SupportRowState extends State<_SupportRow> {
  late final Stream<int> _unread = NotificationsRepository().watchUnreadCount(
    type: 'support',
  );

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: () => context.push('/support'),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.warmFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.support_agent_rounded,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.helpAndSupport,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      l10n.supportInboxHint,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<int>(
                stream: _unread,
                builder: (context, snapshot) =>
                    CountBadge(count: ValueNotifier(snapshot.data ?? 0)),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The customer's complaints, badged while support has an unopened reply.
class _ComplaintsRow extends StatefulWidget {
  const _ComplaintsRow();

  @override
  State<_ComplaintsRow> createState() => _ComplaintsRowState();
}

class _ComplaintsRowState extends State<_ComplaintsRow> {
  late final Stream<int> _unread = ReportRepository().watchUnreadReplies();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: () => context.push('/complaints'),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.amberFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.report_problem_rounded,
                  color: AppColors.amberInk,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.myComplaints,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                    Text(
                      l10n.myComplaintsHint,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<int>(
                stream: _unread,
                builder: (context, snapshot) =>
                    CountBadge(count: ValueNotifier(snapshot.data ?? 0)),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
