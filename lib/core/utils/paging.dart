import 'package:supabase_flutter/supabase_flutter.dart';

/// Rows fetched per page by the paged admin/vendor lists.
///
/// One constant so the repository `.range()` window, the "no more results"
/// check (`page.length == kPageSize`) and the scroll trigger always agree.
const kPageSize = 25;

/// Where the next page of an append-only feed starts: the last row already
/// shown. Keyed on `(created_at, id)` rather than an offset, so a row written
/// while the customer scrolls never shifts the page boundary and shows up
/// twice.
typedef FeedCursor = ({DateTime createdAt, String id});

extension FeedCursorFilter<T> on PostgrestFilterBuilder<T> {
  /// Keeps only rows strictly older than [cursor] in `created_at desc, id desc`
  /// order. Pair with `.order('created_at').order('id')`, both descending.
  PostgrestFilterBuilder<T> olderThan(FeedCursor? cursor) {
    if (cursor == null) return this;
    final ts = cursor.createdAt.toUtc().toIso8601String();
    return or('created_at.lt.$ts,and(created_at.eq.$ts,id.lt.${cursor.id})');
  }
}
