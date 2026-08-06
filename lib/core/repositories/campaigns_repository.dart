import '../supabase_client.dart';

/// One broadcast, as it is stored and as it turned out.
class NotificationCampaign {
  const NotificationCampaign({
    required this.id,
    required this.title,
    required this.body,
    required this.audience,
    required this.status,
    required this.createdAt,
    this.deepLink,
    this.recipients = 0,
    this.delivered = 0,
    this.failed = 0,
    this.sentAt,
    this.error,
  });

  final String id;
  final String title;
  final String body;

  /// `all` | `customers` | `vendors` | `drivers`.
  final String audience;

  /// `draft` | `sending` | `sent` | `failed`. `sending` doubles as the lock
  /// that stops a campaign going out twice.
  final String status;
  final String? deepLink;

  /// Devices the send was attempted against, and how it went. Zero until sent.
  final int recipients;
  final int delivered;
  final int failed;

  final DateTime createdAt;
  final DateTime? sentAt;
  final String? error;

  bool get isSent => status == 'sent';
  bool get isSending => status == 'sending';
  bool get canSend => status == 'draft' || status == 'failed';

  factory NotificationCampaign.fromMap(Map<String, dynamic> map) =>
      NotificationCampaign(
        id: map['id'] as String,
        title: map['title'] as String,
        body: (map['body'] as String?) ?? '',
        audience: (map['audience'] as String?) ?? 'all',
        status: (map['status'] as String?) ?? 'draft',
        deepLink: map['deep_link'] as String?,
        recipients: ((map['recipients'] as num?) ?? 0).toInt(),
        delivered: ((map['delivered'] as num?) ?? 0).toInt(),
        failed: ((map['failed'] as num?) ?? 0).toInt(),
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        sentAt: map['sent_at'] == null
            ? null
            : DateTime.parse(map['sent_at'] as String).toLocal(),
        error: map['error'] as String?,
      );
}

/// Composing and sending platform-wide announcements.
///
/// A campaign is written as a row first and sent second: the send is an edge
/// function that walks every device token, and without the row there would be
/// nothing to show afterwards saying who it reached.
class CampaignsRepository {
  /// One page of campaigns, newest first.
  ///
  /// [sent] true returns only what has gone out; false returns everything that
  /// has not — drafts, failures, and anything mid-send. Null returns both.
  Future<List<NotificationCampaign>> fetchAll({
    int limit = 20,
    int offset = 0,
    bool? sent,
  }) async {
    var query = supabase.from('notification_campaigns').select();
    if (sent == true) {
      query = query.eq('status', 'sent');
    } else if (sent == false) {
      // 'sending' belongs here: it is not finished, and if it is stuck this is
      // the only list an admin would think to look in.
      query = query.inFilter('status', ['draft', 'failed', 'sending']);
    }
    final data = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return (data as List)
        .map((e) => NotificationCampaign.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Sending an announcement again makes a new one.
  ///
  /// The alternative — resetting the original's status — would overwrite the
  /// record of the first send, so a campaign's delivered/failed counts could
  /// never be trusted. A copy keeps each send answerable on its own.
  Future<NotificationCampaign> duplicate(NotificationCampaign source) => create(
    title: source.title,
    body: source.body,
    audience: source.audience,
    deepLink: source.deepLink,
  );

  /// How many devices an audience can actually be reached on.
  ///
  /// Devices, not accounts: somebody with notifications off cannot be reached
  /// at all, and an admin about to message "everyone" should see the real
  /// number before they press send.
  Future<int> audienceSize(String audience) async {
    final data = await supabase.rpc(
      'campaign_audience_size',
      params: {'p_audience': audience},
    );
    return ((data as num?) ?? 0).toInt();
  }

  Future<NotificationCampaign> create({
    required String title,
    required String body,
    required String audience,
    String? deepLink,
  }) async {
    final data = await supabase
        .from('notification_campaigns')
        .insert({
          'title': title.trim(),
          'body': body.trim(),
          'audience': audience,
          'deep_link': (deepLink?.trim().isEmpty ?? true)
              ? null
              : deepLink!.trim(),
          'created_by': supabase.auth.currentUser?.id,
        })
        .select()
        .single();
    return NotificationCampaign.fromMap(data);
  }

  /// Hands the campaign to the edge function, which fans it out and writes the
  /// result back onto the row.
  ///
  /// Long-running by nature — a large audience is thousands of HTTP calls — so
  /// the caller should expect this to take a while rather than assume it hung.
  Future<Map<String, dynamic>> send(String campaignId) async {
    final response = await supabase.functions.invoke(
      'send-campaign',
      body: {'campaign_id': campaignId},
    );
    final data = (response.data as Map?)?.cast<String, dynamic>() ?? const {};
    if (data['error'] != null) throw Exception(data['error']);
    return data;
  }

  Future<void> delete(String id) =>
      supabase.from('notification_campaigns').delete().eq('id', id);
}
