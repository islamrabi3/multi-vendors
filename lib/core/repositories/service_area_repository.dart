import '../models/service_area.dart';
import '../supabase_client.dart';

/// Delivery coverage. Reads are open to any signed-in user (the address picker
/// draws the circles); writes are admin-only by RLS.
class ServiceAreaRepository {
  /// Realtime stream of all service areas for the admin screen.
  Stream<List<ServiceArea>> serviceAreasStream() => supabase
      .from('service_areas')
      .stream(primaryKey: ['id'])
      .order('name', ascending: true)
      .map((rows) => rows.map((e) => ServiceArea.fromMap(e)).toList());

  Future<List<ServiceArea>> fetchActive() async {
    final data = await supabase
        .from('service_areas')
        .select()
        .eq('is_active', true)
        .order('name', ascending: true);
    return (data as List)
        .map((e) => ServiceArea.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Every area including the disabled ones — the admin list.
  Future<List<ServiceArea>> fetchAll() async {
    final data = await supabase
        .from('service_areas')
        .select()
        .order('is_active', ascending: false)
        .order('name', ascending: true);
    return (data as List)
        .map((e) => ServiceArea.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<ServiceArea> save({
    String? id,
    required String name,
    String? nameAr,
    required double lat,
    required double lng,
    required double radiusKm,
    required bool isActive,
  }) async {
    final values = {
      'name': name,
      'name_ar': (nameAr == null || nameAr.isEmpty) ? null : nameAr,
      'lat': lat,
      'lng': lng,
      'radius_km': radiusKm,
      'is_active': isActive,
    };
    final data = id == null
        ? await supabase.from('service_areas').insert(values).select().single()
        : await supabase
            .from('service_areas')
            .update(values)
            .eq('id', id)
            .select()
            .single();
    return ServiceArea.fromMap(data);
  }

  Future<void> setActive(String id, bool isActive) => supabase
      .from('service_areas')
      .update({'is_active': isActive}).eq('id', id);

  /// Nothing references an area by foreign key, so this is a plain delete. It
  /// used to first clear a `vendor_service_areas` join table that was never
  /// created, and that request failed on every call.
  Future<void> delete(String id) =>
      supabase.from('service_areas').delete().eq('id', id);
}
