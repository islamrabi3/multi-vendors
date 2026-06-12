import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/cart_repository.dart';

class CartState extends Equatable {
  const CartState({this.vendor, this.items = const []});

  final Vendor? vendor;
  final List<CartItem> items;

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);
  double get subtotal => items.fold(0, (sum, i) => sum + i.lineTotal);

  @override
  List<Object?> get props => [vendor, items];
}

/// Local-first cart. Mutations apply instantly; persistence to the server is
/// best-effort so a flaky connection never blocks the UI. The repository is
/// optional to keep the cubit unit-testable without Supabase.
class CartCubit extends Cubit<CartState> {
  CartCubit({CartRepository? repository})
      : _repository = repository,
        super(const CartState());

  final CartRepository? _repository;

  /// True when [item] belongs to a different vendor than the current cart;
  /// the caller should confirm before [startNewCart].
  bool conflictsWithCart(Vendor vendor) =>
      state.vendor != null && state.vendor!.id != vendor.id;

  void addItem(Vendor vendor, CartItem item) {
    final items = List<CartItem>.of(state.items);
    final index =
        items.indexWhere((existing) => existing.signature == item.signature);
    if (index >= 0) {
      items[index] =
          items[index].copyWith(quantity: items[index].quantity + item.quantity);
    } else {
      items.add(item);
    }
    emit(CartState(vendor: vendor, items: items));
    _persist();
  }

  void startNewCart(Vendor vendor, CartItem item) {
    emit(CartState(vendor: vendor, items: [item]));
    _persist();
  }

  void updateQuantity(CartItem item, int quantity) {
    final items = List<CartItem>.of(state.items);
    final index = items.indexWhere((e) => e.signature == item.signature);
    if (index < 0) return;
    if (quantity <= 0) {
      items.removeAt(index);
    } else {
      items[index] = items[index].copyWith(quantity: quantity);
    }
    emit(items.isEmpty
        ? const CartState()
        : CartState(vendor: state.vendor, items: items));
    _persist();
  }

  void removeItem(CartItem item) => updateQuantity(item, 0);

  void clear() {
    emit(const CartState());
    _persist();
  }

  /// Restores the cart from the server after sign-in / app restart.
  Future<void> restoreFromServer(
      Future<Vendor> Function(String vendorId) fetchVendor) async {
    if (_repository == null) return;
    try {
      final saved = await _repository.loadCart();
      if (saved == null) return;
      final (vendorId, items) = saved;
      final vendor = await fetchVendor(vendorId);
      emit(CartState(vendor: vendor, items: items));
    } catch (_) {
      // Stale carts are not worth surfacing an error for.
    }
  }

  void _persist() {
    final repository = _repository;
    final vendor = state.vendor;
    if (repository == null) return;
    repository
        .saveCart(vendor?.id ?? '', vendor == null ? const [] : state.items)
        .catchError((_) {});
  }
}
