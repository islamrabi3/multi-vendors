import '../models/address.dart';
import '../supabase_client.dart';

class AddressRepository {
  Future<List<Address>> fetchAddresses() async {
    final data = await supabase
        .from('addresses')
        .select()
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return data.map(Address.fromMap).toList();
  }

  Future<Address> saveAddress(Map<String, dynamic> values, {String? id}) async {
    final userId = supabase.auth.currentUser!.id;
    if (values['is_default'] == true) {
      await supabase
          .from('addresses')
          .update({'is_default': false}).eq('user_id', userId);
    }
    final query = id == null
        ? supabase.from('addresses').insert({...values, 'user_id': userId})
        : supabase.from('addresses').update(values).eq('id', id);
    final data = await query.select().single();
    return Address.fromMap(data);
  }

  Future<void> deleteAddress(String id) =>
      supabase.from('addresses').delete().eq('id', id);
}
