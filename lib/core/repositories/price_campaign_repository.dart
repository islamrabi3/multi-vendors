import '../supabase_client.dart';

/// A temporary, platform-wide price uplift.
///
/// While a campaign runs, menu prices in its scope are raised by
/// [markupPercent]; when it ends they are put back. Orders placed in between
/// still pay the store on its own price — the uplift is the platform's, and is
/// what funds the discount the customer is offered.
class PriceCampaign {
  const PriceCampaign({
    required this.id,
    required this.name,
    required this.markupPercent,
    required this.scope,
    required this.status,
    required this.startsAt,
    this.endsAt,
    this.vendorId,
    this.categoryId,
    this.vendorName,
    this.categoryName,
    this.itemCount = 0,
  });

  final String id;
  final String name;
  final double markupPercent;

  /// `all` | `vendor` | `category`.
  final String scope;

  /// `scheduled` | `active` | `ended`.
  final String status;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String? vendorId;
  final String? categoryId;
  final String? vendorName;
  final String? categoryName;

  /// How many products the campaign has raised.
  final int itemCount;

  bool get isActive => status == 'active';
  bool get isEnded => status == 'ended';

  factory PriceCampaign.fromMap(Map<String, dynamic> map) => PriceCampaign(
    id: map['id'] as String,
    name: (map['name'] as String?) ?? '',
    markupPercent: ((map['markup_percent'] as num?) ?? 0).toDouble(),
    scope: (map['scope'] as String?) ?? 'all',
    status: (map['status'] as String?) ?? 'scheduled',
    startsAt: DateTime.parse(map['starts_at'] as String).toLocal(),
    endsAt: map['ends_at'] == null
        ? null
        : DateTime.parse(map['ends_at'] as String).toLocal(),
    vendorId: map['vendor_id'] as String?,
    categoryId: map['category_id'] as String?,
    vendorName: (map['vendors'] as Map?)?['name'] as String?,
    categoryName: (map['vendor_categories'] as Map?)?['name'] as String?,
    itemCount:
        ((map['price_campaign_items'] as List?)?.firstOrNull as Map?)?['count']
            as int? ??
        0,
  );
}

class PriceCampaignRepository {
  Future<List<PriceCampaign>> fetchCampaigns() async {
    final rows = await supabase
        .from('price_campaigns')
        .select(
          'id, name, markup_percent, scope, status, starts_at, ends_at, '
          'vendor_id, category_id, vendors(name), vendor_categories(name), '
          'price_campaign_items(count)',
        )
        .order('created_at', ascending: false)
        .limit(50);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map(PriceCampaign.fromMap)
        .toList();
  }

  /// Starts now unless [startsAt] is in the future, in which case the
  /// scheduler picks it up when its time comes.
  Future<String> create({
    required String name,
    required double markupPercent,
    required String scope,
    String? vendorId,
    String? categoryId,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final id = await supabase.rpc(
      'admin_create_price_campaign',
      params: {
        'p_name': name.trim(),
        'p_markup_percent': markupPercent,
        'p_scope': scope,
        'p_vendor_id': vendorId,
        'p_category_id': categoryId,
        'p_starts_at': startsAt?.toUtc().toIso8601String(),
        'p_ends_at': endsAt?.toUtc().toIso8601String(),
        'p_start_now': startsAt == null,
      },
    );
    return '$id';
  }

  /// Puts the prices back. Returns how many were restored — a price the store
  /// changed while the campaign ran keeps its new value and is not counted.
  Future<int> end(String id) async {
    final restored = await supabase.rpc(
      'admin_end_price_campaign',
      params: {'p_id': id},
    );
    return (restored as num?)?.toInt() ?? 0;
  }
}
