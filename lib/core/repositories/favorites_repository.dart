import '../models/vendor.dart';
import '../supabase_client.dart';

class FavoritesRepository {
  Future<Set<String>> fetchFavoriteVendorIds() async {
    final data = await supabase.from('favorites').select('vendor_id');
    return data.map((row) => row['vendor_id'] as String).toSet();
  }

  Future<List<Vendor>> fetchFavoriteVendors() async {
    // Opening hours ride along, or a saved store that closed an hour ago still
    // reads as open on this page while reading as shut everywhere else.
    final data = await supabase
        .from('favorites')
        .select('vendors(*, vendor_schedules(*))');
    return data
        .map((row) => row['vendors'])
        .whereType<Map<String, dynamic>>()
        .map(Vendor.fromMap)
        .toList();
  }

  Future<void> setFavorite(String vendorId, bool favorite) async {
    final userId = supabase.auth.currentUser!.id;
    if (favorite) {
      await supabase
          .from('favorites')
          .upsert({'user_id': userId, 'vendor_id': vendorId});
    } else {
      await supabase
          .from('favorites')
          .delete()
          .eq('user_id', userId)
          .eq('vendor_id', vendorId);
    }
  }
}
