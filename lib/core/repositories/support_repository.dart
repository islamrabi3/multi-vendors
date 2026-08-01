import '../models/support.dart';
import '../services/attachment_service.dart';
import '../supabase_client.dart';

/// Support conversations. RLS keeps a user to their own threads and gives
/// admins the whole inbox, so neither side is filtered here.
class SupportRepository {
  /// The caller's own threads, most recently active first.
  Future<List<SupportThread>> fetchMyThreads() async {
    final data = await supabase
        .from('support_threads')
        .select()
        .order('last_message_at', ascending: false);
    return (data as List)
        .map((e) => SupportThread.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// The admin inbox. Open threads first, then by activity — an admin works
  /// the queue, and a resolved thread is not the queue.
  Future<List<SupportThread>> fetchAllThreads({bool openOnly = false}) async {
    var query = supabase
        .from('support_threads')
        .select('*, profiles(full_name, role)');
    if (openOnly) query = query.eq('status', 'open');
    final data = await query.order('last_message_at', ascending: false);
    final threads = (data as List)
        .map((e) => SupportThread.fromMap(e as Map<String, dynamic>))
        .toList();
    threads.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;
      return b.lastMessageAt.compareTo(a.lastMessageAt);
    });
    return threads;
  }

  /// Live messages in a thread, oldest first.
  ///
  /// `ascending: true` is not optional here: postgrest-dart's `order()`
  /// defaults to *descending*, which rendered the conversation newest-first.
  Stream<List<SupportMessage>> messagesStream(String threadId) => supabase
      .from('support_messages')
      .stream(primaryKey: ['id'])
      .eq('thread_id', threadId)
      .order('created_at', ascending: true)
      .map((rows) => rows.map(SupportMessage.fromMap).toList());

  /// Live thread row, so a status change made by the admin reaches the other
  /// side without either of them reopening the screen.
  Stream<SupportThread?> threadStream(String threadId) => supabase
      .from('support_threads')
      .stream(primaryKey: ['id'])
      .eq('id', threadId)
      .map((rows) =>
          rows.isEmpty ? null : SupportThread.fromMap(rows.first));

  /// Reuses the caller's open thread when there is one, so a user with a
  /// running conversation does not silently start a second.
  Future<SupportThread> openOrCreateThread({String subject = ''}) async {
    final existing = await supabase
        .from('support_threads')
        .select()
        .eq('status', 'open')
        .order('last_message_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) return SupportThread.fromMap(existing);

    final created = await supabase
        .from('support_threads')
        .insert({
          'user_id': supabase.auth.currentUser!.id,
          'subject': subject,
        })
        .select()
        .single();
    return SupportThread.fromMap(created);
  }

  /// [fromAdmin] must match what the sender actually is; RLS rejects a
  /// mismatch, so a customer cannot post a message styled as support.
  Future<void> send({
    required String threadId,
    required String message,
    required bool fromAdmin,
    ChatAttachment? attachment,
  }) =>
      supabase.from('support_messages').insert({
        'thread_id': threadId,
        'sender_id': supabase.auth.currentUser!.id,
        'is_from_admin': fromAdmin,
        'message': message,
        if (attachment != null) ...{
          'attachment_url': attachment.path,
          'attachment_name': attachment.name,
          'attachment_type': attachment.type,
        },
      });

  /// The one-tap reasons offered when a thread opens.
  Future<List<SupportTemplate>> fetchTemplates() async {
    final data =
        await supabase.from('support_templates').select().order('sort_order');
    return (data as List)
        .map((e) => SupportTemplate.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Posts the chosen reason and, unless it is the "something else" row, the
  /// platform's standard answer with it.
  ///
  /// This has to be an RPC: the automatic answer is `is_from_admin = true`,
  /// which the insert policy refuses to a customer — correctly, since that is
  /// what stops anyone posting a message dressed as support.
  Future<void> sendTemplate({
    required String threadId,
    required String key,
    required String languageCode,
  }) =>
      supabase.rpc('support_send_template', params: {
        'p_thread_id': threadId,
        'p_key': key,
        'p_locale': languageCode == 'ar' ? 'ar' : 'en',
      });

  Future<void> setStatus(String threadId, String status) => supabase
      .from('support_threads')
      .update({'status': status}).eq('id', threadId);
}
