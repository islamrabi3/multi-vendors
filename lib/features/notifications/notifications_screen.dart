import 'dart:async';

import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/tokens.dart';
import '../support/messages_screen.dart' show conversationPreview;
import '../customer/orders/order_chat_sheet.dart';
import '../../core/repositories/chat_repository.dart';
import '../../core/models/chat_conversation.dart';
import '../../core/models/order.dart';
import '../../core/repositories/notifications_repository.dart' show inboxCutoff;
import '../../core/utils/l10n_extension.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/web/adaptive_sheet.dart';

/// One line of the inbox, from either source: a stored notification row, or
/// an order whose status changed.
class _InboxItem {
  const _InboxItem({
    required this.id,
    required this.createdAt,
    this.title,
    this.body,
    this.route,
    this.unread = false,
    this.orderId,
    this.orderNumber,
    this.storeName,
    this.status,
    this.type,
    this.conversation,
  });

  final String id;
  final DateTime createdAt;
  final String? title;
  final String? body;
  final String? route;
  final bool unread;
  final String? type;

  final String? orderId;
  final String? orderNumber;
  final String? storeName;
  final OrderStatus? status;

  /// Set for a new order-chat message; its order and preview come from here.
  final ChatConversation? conversation;

  bool get isChat => conversation != null;

  /// Which of the order's conversations this row belongs to.
  String? get chatThread => conversation?.thread;
  bool get isOrder => orderId != null && !isChat;
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.embedded = false});

  /// Drawn inside the web bell's dropdown: no app bar of its own, and a
  /// tapped row opens over the dropdown instead of navigating away.
  final bool embedded;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const _pageSize = 10;

  final SupabaseClient _client = Supabase.instance.client;
  final List<_InboxItem> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _markedRead = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = _items.isEmpty;
      _error = null;
    });
    try {
      final page = await _fetchPage(before: null);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _hasMore = page.hasMore;
        _loading = false;
      });
      // Opening the screen is what marks them read; the bell's unread count
      // would otherwise never clear. The highlight above is from before this.
      if (!_markedRead) {
        _markedRead = true;
        unawaited(_client.rpc('mark_notifications_read').catchError((_) {}));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _fetchPage(before: _items.last.createdAt);
      if (!mounted) return;
      final seen = _items.map((i) => i.id).toSet();
      setState(() {
        _items.addAll(page.items.where((i) => !seen.contains(i.id)));
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Ten at a time across both sources. Each source is asked for up to ten
  /// older than the cursor, the two are merged newest first, and only the
  /// first ten are kept — whatever was cut is older than the new cursor, so
  /// the next page picks it up again.
  Future<({List<_InboxItem> items, bool hasMore})> _fetchPage({
    required DateTime? before,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return (items: const <_InboxItem>[], hasMore: false);
    final cursor = before?.toUtc().toIso8601String();
    // Everything older than a day has dropped out of the inbox.
    final since = inboxCutoff().toIso8601String();

    var inboxQuery = _client
        .from('notifications')
        .select('id, title, body, type, route, is_read, created_at')
        .gte('created_at', since);
    if (cursor != null) inboxQuery = inboxQuery.lt('created_at', cursor);

    var ordersQuery = _client
        .from('orders')
        .select('id, order_number, status, updated_at, vendors(name)')
        .or('customer_id.eq.$userId,driver_id.eq.$userId')
        .gte('updated_at', since);
    if (cursor != null) ordersQuery = ordersQuery.lt('updated_at', cursor);

    final results = await Future.wait([
      inboxQuery.order('created_at', ascending: false).limit(_pageSize),
      ordersQuery.order('updated_at', ascending: false).limit(_pageSize),
    ]);
    final inbox = results[0] as List;
    final orders = results[1] as List;

    // New messages from someone else on an order, as one row per
    // conversation. Only on the first page: a conversation is a single row
    // whose time moves, not a history to page through.
    final cutoff = inboxCutoff().toLocal();
    final chats = before != null
        ? const <ChatConversation>[]
        : await ChatRepository()
              .fetchConversations(limit: 20)
              .then(
                (all) => all
                    .where((c) => !c.lastFromMe && c.lastAt.isAfter(cutoff))
                    .toList(),
              )
              .catchError((Object _) => const <ChatConversation>[]);

    final merged = <_InboxItem>[
      for (final n in inbox)
        _InboxItem(
          id: n['id'] as String,
          title: n['title'] as String?,
          body: n['body'] as String?,
          route: n['route'] as String?,
          type: n['type'] as String?,
          unread: n['is_read'] == false,
          createdAt: DateTime.parse(n['created_at'] as String).toLocal(),
        ),
      for (final o in orders)
        _InboxItem(
          id: 'order-${o['id']}-${o['updated_at']}',
          orderId: o['id'] as String,
          orderNumber: '${o['order_number'] ?? ''}',
          storeName: (o['vendors'] as Map?)?['name'] as String?,
          status: OrderStatus.fromName(o['status'] as String?),
          createdAt: DateTime.parse(o['updated_at'] as String).toLocal(),
        ),
      for (final c in chats)
        _InboxItem(
          id: 'chat-${c.orderId}-${c.lastAt.millisecondsSinceEpoch}',
          orderId: c.orderId,
          orderNumber: c.orderNumber,
          conversation: c,
          unread: c.unread > 0,
          createdAt: c.lastAt,
        ),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final hasMore =
        merged.length > _pageSize ||
        inbox.length == _pageSize ||
        orders.length == _pageSize;
    return (items: merged.take(_pageSize).toList(), hasMore: hasMore);
  }

  void _open(_InboxItem item) {
    if (item.isChat) {
      if (widget.embedded || AppBreakpoints.isWebWide(context)) {
        showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 480,
              height: 620,
              child: OrderChatSheet(
                orderId: item.orderId!,
                thread: item.chatThread ?? 'vendor',
                embedded: true,
              ),
            ),
          ),
        ).then((_) => _refresh());
      } else {
        context
            .push(
              '/order/${item.orderId}/chat'
              '?thread=${item.chatThread ?? 'vendor'}',
            )
            .then((_) => _refresh());
      }
      return;
    }
    // On the web the feed is a dropdown: an order update opens as a detail
    // card over it rather than taking the page somewhere else.
    if (item.isOrder && !widget.embedded) {
      context.push('/order/${item.orderId}');
      return;
    }
    // Every row opens — an announcement with no link used to be a dead tap,
    // which on the staff consoles was every single one of them.
    showAdaptiveSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      maxWidth: 480,
      builder: (_) => _NotificationDetails(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget body;
    if (_loading) {
      body = const _NotificationsSkeleton();
    } else if (_error != null && _items.isEmpty) {
      body = FailureView(error: _error!, onRetry: _refresh);
    } else if (_items.isEmpty) {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.6,
              child: EmptyView(
                message: l10n.noNotificationsLast24h,
                icon: Icons.notifications_none_rounded,
              ),
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: InfiniteScroll(
          onLoadMore: _loadMore,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 10),
                child: Text(
                  l10n.notificationsLast24h,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
              // One card, rows divided — an inbox, not a stack of tall
              // separate cards that spread a few words across a wide screen.
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 68,
                          color: AppColors.borderSoft,
                        ),
                      _NotificationTile(
                        item: _items[i],
                        onTap: () => _open(_items[i]),
                      ),
                    ],
                  ],
                ),
              ),
              PagingFooter(loading: _loadingMore, hasMore: _hasMore),
            ],
          ),
        ),
      );
    }

    if (widget.embedded) {
      return Material(color: AppColors.canvas, child: body);
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.notifications)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: body,
        ),
      ),
    );
  }
}

String _titleOf(BuildContext context, _InboxItem item) => item.isChat
    ? context.l10n.newMessageFrom(item.orderNumber ?? '')
    : item.isOrder
    ? '${context.l10n.order} #${item.orderNumber}'
    : (item.title ?? context.l10n.notifications);

String _bodyOf(BuildContext context, _InboxItem item) => item.isChat
    ? conversationPreview(context, item.conversation!)
    : item.isOrder
    ? '${item.storeName ?? context.l10n.store} · '
          '${item.status!.localizedLabel(context)}'
    : (item.body ?? '');

String _timeOf(BuildContext context, DateTime at) {
  final l10n = context.l10n;
  final diff = DateTime.now().difference(at);
  if (diff.inMinutes < 1) return l10n.justNow;
  if (diff.inHours < 1) return '${diff.inMinutes}${l10n.minutesAgo}';
  if (diff.inHours < 24) return '${diff.inHours}${l10n.hoursAgo}';
  final language = Localizations.localeOf(context).languageCode;
  return DateFormat.MMMd(language).format(at);
}

(IconData, Color, Color) _styleOf(_InboxItem item) {
  if (item.isChat) {
    return (
      Icons.chat_bubble_rounded,
      AppColors.successFill,
      AppColors.successInk,
    );
  }
  if (item.isOrder) {
    return (Icons.receipt_long_rounded, AppColors.warmFill, AppColors.primary);
  }
  return switch (item.type) {
    'settlement' => (
      Icons.account_balance_wallet_rounded,
      AppColors.successFill,
      AppColors.successInk,
    ),
    'support' => (
      Icons.support_agent_rounded,
      AppColors.amberFill,
      AppColors.amberInk,
    ),
    'complaint' => (
      Icons.report_problem_rounded,
      AppColors.dangerFill,
      AppColors.dangerInk,
    ),
    _ => (Icons.campaign_rounded, AppColors.warmFill, AppColors.primaryDark),
  };
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final _InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, fill, ink) = _styleOf(item);
    final body = _bodyOf(context, item);
    return Material(
      color: item.unread
          ? AppColors.warmFill.withValues(alpha: 0.55)
          : AppColors.surface,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: ink, size: 19),
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
                            _titleOf(context, item),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: item.unread
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 14,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _timeOf(context, item.createdAt),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: item.unread
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: item.unread
                                ? AppColors.primary
                                : AppColors.textFaint,
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.35,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (item.unread)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 10, top: 6),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
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

/// The whole message, and its link as an explicit button when there is one.
class _NotificationDetails extends StatelessWidget {
  const _NotificationDetails({required this.item});

  final _InboxItem item;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, fill, ink) = _styleOf(item);
    final route = item.isOrder ? '/order/${item.orderId}' : item.route?.trim();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: ink, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    formatDateTime(context, item.createdAt),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(_titleOf(context, item), style: AppType.heading(19)),
            if (_bodyOf(context, item).isNotEmpty) ...[
              const SizedBox(height: 8),
              SelectableText(
                _bodyOf(context, item),
                style: const TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 22),
            if (route != null && route.startsWith('/'))
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push(route);
                },
                child: Text(l10n.open),
              )
            else
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text(MaterialLocalizations.of(context).closeButtonLabel),
              ),
          ],
        ),
      ),
    );
  }
}

/// Notifications while the feed loads, shaped like the real tiles.
class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: SkeletonList(
        itemCount: 6,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        separator: const SizedBox(height: AppSpace.sm),
        itemBuilder: (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border),
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              children: [
                Skeleton.circle(size: 42),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(widthFactor: 0.6, height: 14),
                      SizedBox(height: 7),
                      Skeleton.line(widthFactor: 0.85, height: 12),
                    ],
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
