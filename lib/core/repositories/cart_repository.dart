import '../models/cart_item.dart';
import '../models/product.dart';
import '../supabase_client.dart';
import 'catalog_repository.dart';

/// Server-side cart persistence. The cart lives in the CartCubit; this
/// repository mirrors it to the `carts` tables so it survives app restarts.
class CartRepository {
  CartRepository({CatalogRepository? catalog})
      : _catalog = catalog ?? CatalogRepository();

  final CatalogRepository _catalog;

  Future<void> saveCart(String vendorId, List<CartItem> items) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (items.isEmpty) {
      await supabase.from('carts').delete().eq('user_id', userId);
      return;
    }

    final cart = await supabase
        .from('carts')
        .upsert({'user_id': userId, 'vendor_id': vendorId},
            onConflict: 'user_id')
        .select()
        .single();
    final cartId = cart['id'] as String;

    await supabase.from('cart_items').delete().eq('cart_id', cartId);
    await supabase.from('cart_items').insert([
      for (final item in items)
        {
          'cart_id': cartId,
          'product_id': item.product.id,
          'quantity': item.quantity,
          'notes': item.notes,
          'selected_options': [
            for (final option in item.selectedOptions)
              {'option_id': option.id, 'group_id': option.groupId},
          ],
        },
    ]);
  }

  Future<(String vendorId, List<CartItem> items)?> loadCart() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final cart = await supabase
        .from('carts')
        .select('id, vendor_id, cart_items(*)')
        .eq('user_id', userId)
        .maybeSingle();
    if (cart == null) return null;

    final rows = (cart['cart_items'] as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;

    final products = await _catalog.fetchProductsByIds(
      rows.map((r) => r['product_id'] as String).toSet().toList(),
    );
    final productsById = {for (final p in products) p.id: p};

    final items = <CartItem>[];
    for (final row in rows) {
      final product = productsById[row['product_id']];
      if (product == null) continue;
      final optionIds = ((row['selected_options'] as List?) ?? [])
          .map((o) => (o as Map)['option_id'] as String)
          .toSet();
      final options = [
        for (final group in product.optionGroups)
          for (final option in group.options)
            if (optionIds.contains(option.id)) option,
      ];
      items.add(CartItem(
        product: product,
        quantity: ((row['quantity'] as num?) ?? 1).toInt(),
        selectedOptions: options,
        notes: row['notes'] as String?,
      ));
    }

    if (items.isEmpty) return null;
    return (cart['vendor_id'] as String, items);
  }

  Future<Product?> productForRestore(String productId) =>
      _catalog.fetchProductsByIds([productId]).then(
          (list) => list.isEmpty ? null : list.first);
}
