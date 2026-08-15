import '../models/app_content.dart';
import '../supabase_client.dart';

/// Operator-managed pages and links.
///
/// Reads are open to anon as well as signed-in users: the terms have to be
/// reachable from the signup screen, before an account exists. Writes are
/// admin-only, enforced by RLS rather than here.
class AppContentRepository {
  /// A single page by slug, or null when it has never been published.
  Future<AppContent?> fetchContent(String key) async {
    final data = await supabase
        .from('app_content')
        .select()
        .eq('key', key)
        .maybeSingle();
    return data == null ? null : AppContent.fromMap(data);
  }

  /// Every page including drafts — the admin editor's list.
  Future<List<AppContent>> fetchAllContent() async {
    final data = await supabase.from('app_content').select().order('key', ascending: true);
    return (data as List)
        .map((e) => AppContent.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// [bumpVersion] re-asks every partner for their signature.
  ///
  /// Deliberately the admin's call rather than automatic on any edit: a
  /// corrected typo would otherwise lock every store and rider out of the app
  /// until they had re-read a document that did not meaningfully change.
  Future<void> saveContent(AppContent content, {bool bumpVersion = false}) =>
      supabase.from('app_content').update({
        'title_en': content.titleEn,
        'title_ar': content.titleAr,
        'body_en': content.bodyEn,
        'body_ar': content.bodyAr,
        'is_published': content.isPublished,
        if (bumpVersion) 'version': content.version + 1,
      }).eq('key', content.key);

  /// Active links in display order — the about page footer.
  Future<List<AppLink>> fetchLinks() async {
    final data = await supabase
        .from('app_links')
        .select()
        .eq('is_active', true)
        .order('sort_order', ascending: true);
    return (data as List)
        .map((e) => AppLink.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Including the disabled ones — the admin editor's list.
  Future<List<AppLink>> fetchAllLinks() async {
    final data =
        await supabase.from('app_links').select().order('sort_order', ascending: true);
    return (data as List)
        .map((e) => AppLink.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveLink({
    String? id,
    required String platform,
    required String url,
    required bool isActive,
    required int sortOrder,
  }) async {
    final values = {
      'platform': platform,
      'url': url,
      'is_active': isActive,
      'sort_order': sortOrder,
    };
    if (id == null) {
      await supabase.from('app_links').insert(values);
    } else {
      await supabase.from('app_links').update(values).eq('id', id);
    }
  }

  Future<void> deleteLink(String id) =>
      supabase.from('app_links').delete().eq('id', id);
}
