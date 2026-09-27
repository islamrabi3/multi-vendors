import '../supabase_client.dart';

/// One thing the console's command palette can open.
class ConsoleHit {
  const ConsoleHit({
    required this.kind,
    required this.id,
    required this.label,
    this.detail,
  });

  /// `order` or `store`.
  final String kind;
  final String id;
  final String label;
  final String? detail;
}

/// The lookups behind the command palette: orders by number, stores by name.
/// Row-level security decides what each console may find — a store only ever
/// sees its own orders.
class ConsoleSearchRepository {
  /// `%` and `_` are wildcards to `ilike`; typed ones are meant literally.
  static String _pattern(String query) =>
      '%${query.trim().replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%';

  Future<List<ConsoleHit>> orders(String query, {String? vendorId}) async {
    var request = supabase
        .from('orders')
        .select('id, order_number, status, vendors(name)')
        .ilike('order_number', _pattern(query));
    if (vendorId != null) request = request.eq('vendor_id', vendorId);
    final rows = await request.order('created_at', ascending: false).limit(6);
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        ConsoleHit(
          kind: 'order',
          id: row['id'] as String,
          label: '${row['order_number'] ?? ''}',
          detail: (row['vendors'] as Map?)?['name'] as String?,
        ),
    ];
  }

  Future<List<ConsoleHit>> stores(String query) async {
    final rows = await supabase
        .from('vendors')
        .select('id, name')
        .ilike('name', _pattern(query))
        .order('name')
        .limit(6);
    return [
      for (final row in (rows as List).cast<Map<String, dynamic>>())
        ConsoleHit(
          kind: 'store',
          id: row['id'] as String,
          label: '${row['name'] ?? ''}',
        ),
    ];
  }
}
