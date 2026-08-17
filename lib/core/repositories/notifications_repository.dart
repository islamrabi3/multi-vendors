import '../supabase_client.dart';

/// The in-app inbox every role shares — `public.notifications`. One row per
/// alert, written by security-definer functions only (announcements,
/// settlement events, and so on), read by whoever it names.
class NotificationsRepository {
  /// How many the signed-in user has not yet opened the inbox to see.
  ///
  /// A `count`-only select rather than fetching the rows: the bell needs a
  /// number, not the list, and every shell that shows the bell would
  /// otherwise be paying for the full page just to badge an icon.
  Future<int> unreadCount() =>
      supabase.from('notifications').count().eq('is_read', false);

  /// Live unread count. `notifications` is on the realtime publication
  /// already (see the `notifications_inbox` migration), so a badge can update
  /// the moment a row lands instead of only on the next screen open.
  ///
  /// [type] narrows to one row type — the messages button wants only
  /// `'support'` rows, so a settlement notice does not light up an icon whose
  /// whole point is "you have a reply waiting".
  Stream<int> watchUnreadCount({String? type}) {
    return supabase
        .from('notifications')
        .stream(primaryKey: ['id'])
        // RLS already scopes this to the caller's own rows; the stream filter
        // just avoids recounting the whole table client-side on every change.
        .map(
          (rows) => rows
              .where(
                (r) =>
                    r['is_read'] == false && (type == null || r['type'] == type),
              )
              .length,
        );
  }
}
