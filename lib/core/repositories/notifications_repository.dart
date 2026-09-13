import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';
import '../utils/live_count.dart';

/// The in-app inbox every role shares — `public.notifications`. One row per
/// alert, written by security-definer functions only (announcements,
/// settlement events, and so on), read by whoever it names.
/// Notifications are shown for one day, then drop out of the inbox.
const inboxWindow = Duration(hours: 24);

DateTime inboxCutoff() => DateTime.now().toUtc().subtract(inboxWindow);

class NotificationsRepository {
  /// How many the signed-in user has not yet opened the inbox to see.
  ///
  /// A `count`-only select rather than fetching the rows: the bell needs a
  /// number, not the list, and every shell that shows the bell would
  /// otherwise be paying for the full page just to badge an icon.
  Future<int> unreadCount() => supabase
      .from('notifications')
      .count()
      .eq('is_read', false)
      .gte('created_at', inboxCutoff().toIso8601String());

  /// Live unread count, recounted whenever one of the caller's notification
  /// rows changes.
  ///
  /// [type] narrows to one row type — the messages button wants only
  /// `'support'` rows, so a settlement notice does not light up an icon whose
  /// whole point is "you have a reply waiting".
  Stream<int> watchUnreadCount({String? type}) {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return Stream.value(0);
    return liveCount(
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      count: () {
        // RLS scopes the count to the caller's own rows.
        var query = supabase.from('notifications').count().eq('is_read', false);
        if (type != null) {
          query = query.eq('type', type);
        } else {
          // The inbox only lists the last day, so the bell counts the same
          // window — otherwise it would badge items nobody can find.
          query = query.gte('created_at', inboxCutoff().toIso8601String());
        }
        return query;
      },
    );
  }
}
