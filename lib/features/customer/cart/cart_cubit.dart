import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/models/cart_item.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/cart_repository.dart';

class CartState extends Equatable {
  const CartState({
    this.vendor,
    this.items = const [],
    this.unavailable = const [],
    this.repriced = const [],
    this.checking = false,
  });

  final Vendor? vendor;
  final List<CartItem> items;

  /// Items the store has since removed or marked sold out. They stay in the
  /// list — silently deleting somebody's cart is worse than telling them — but
  /// they are excluded from the total and block checkout.
  final List<String> unavailable;

  /// Items whose price changed since they were added. The cart shows the new
  /// price; this is what lets it say so rather than quietly charging more.
  final List<String> repriced;

  /// A freshness check is in flight.
  final bool checking;

  bool get isEmpty => items.isEmpty;
  int get itemCount => items.fold(0, (sum, i) => sum + i.quantity);

  /// Excludes anything unavailable: the number under the button has to be the
  /// number that will be charged.
  double get subtotal => items
      .where((i) => !unavailable.contains(i.product.id))
      .fold(0, (sum, i) => sum + i.lineTotal);

  bool isUnavailable(CartItem item) => unavailable.contains(item.product.id);
  bool isRepriced(CartItem item) => repriced.contains(item.product.id);

  bool get hasProblems => unavailable.isNotEmpty || repriced.isNotEmpty;

  /// Nothing orderable left once every line is unavailable.
  bool get canCheckout =>
      items.isNotEmpty && unavailable.isEmpty && subtotal > 0;

  CartState copyWith({
    Vendor? vendor,
    List<CartItem>? items,
    List<String>? unavailable,
    List<String>? repriced,
    bool? checking,
  }) =>
      CartState(
        vendor: vendor ?? this.vendor,
        items: items ?? this.items,
        unavailable: unavailable ?? this.unavailable,
        repriced: repriced ?? this.repriced,
        checking: checking ?? this.checking,
      );

  @override
  List<Object?> get props =>
      [vendor, items, unavailable, repriced, checking];
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

  /// Drops the cart locally only — used on sign-out so one user's cart never
  /// leaks into the next session. Does NOT write to the server (no session).
  void resetLocal() => emit(const CartState());

  /// Restores the cart from the server after sign-in / app restart.
  Future<void> restoreFromServer(
      Future<Vendor> Function(String vendorId) fetchVendor) async {
    if (_repository == null) return;
    try {
      final saved = await _repository.loadCart();
      if (saved == null) {
        emit(const CartState());
        return;
      }
      final (vendorId, items) = saved;
      final vendor = await fetchVendor(vendorId);
      emit(CartState(vendor: vendor, items: items));
    } catch (_) {
      // Stale carts are not worth surfacing an error for.
    }
  }

  /// Re-reads the cart's items from the catalogue and flags what changed.
  ///
  /// A cart is built from a snapshot of the menu and then sat on — sometimes
  /// for hours. Without this the first the customer heard of a sold-out item
  /// was `PRODUCT_UNAVAILABLE` at checkout, after they had entered an address
  /// and picked a payment method; a price rise was never mentioned at all,
  /// because the server recomputes totals from current prices.
  Future<void> revalidate(
      Future<List<Product>> Function(List<String> ids) fetchProducts) async {
    if (state.items.isEmpty) return;
    emit(state.copyWith(checking: true));
    try {
      final ids = state.items.map((i) => i.product.id).toSet().toList();
      final fresh = await fetchProducts(ids);
      final byId = {for (final product in fresh) product.id: product};

      final unavailable = <String>[];
      final repriced = <String>[];
      final items = <CartItem>[];
      for (final item in state.items) {
        final current = byId[item.product.id];
        if (current == null || !current.isAvailable) {
          // A product deleted outright is as unorderable as a sold-out one,
          // and the customer needs the same sentence for both.
          unavailable.add(item.product.id);
          items.add(item);
          continue;
        }
        if (current.price != item.product.price) {
          repriced.add(item.product.id);
        }
        // Carry the current product through, so the line shows what the
        // customer will actually be charged.
        items.add(item.copyWith(product: current));
      }

      if (isClosed) return;
      emit(state.copyWith(
        items: items,
        unavailable: unavailable,
        repriced: repriced,
        checking: false,
      ));
    } catch (_) {
      // Offline or a failed read: leave the cart exactly as it was. Checkout
      // still refuses anything genuinely unavailable, so this is a courtesy
      // rather than the guarantee.
      if (!isClosed) emit(state.copyWith(checking: false));
    }
  }

  /// Drops every line the store can no longer sell, in one tap.
  void removeUnavailable() {
    final keep = state.items
        .where((item) => !state.unavailable.contains(item.product.id))
        .toList();
    emit(keep.isEmpty
        ? const CartState()
        : CartState(vendor: state.vendor, items: keep, repriced: state.repriced));
    _persist();
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
