import 'package:flutter_test/flutter_test.dart';
import 'package:multi_vendor/core/models/product.dart';
import 'package:multi_vendor/core/repositories/catalog_repository.dart';
import 'package:multi_vendor/core/repositories/vendor_admin_repository.dart';
import 'package:multi_vendor/features/vendor/menu_cubit.dart';

/// The menu screen can now pick several items and act on all of them at once.
/// Every one of those actions writes to the live menu, so the rules about what
/// is in the selection are worth pinning down: an id left over from a row that
/// no longer exists must not reach a bulk delete, and a failed write must not
/// throw away the vendor's picks.

Product _product(String id, {String? categoryId, bool available = true}) =>
    Product(
      id: id,
      vendorId: 'v1',
      name: id,
      price: 10,
      isAvailable: available,
      categoryId: categoryId,
    );

class _FakeCatalog implements CatalogRepository {
  _FakeCatalog(this.products, this.categories);

  List<Product> products;
  List<ProductCategory> categories;

  @override
  Future<List<ProductCategory>> fetchMenuCategories(String vendorId) async =>
      categories;

  @override
  Future<List<Product>> fetchProducts(
    String vendorId, {
    bool includeUnavailable = false,
  }) async => products;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

class _FakeAdmin implements VendorAdminRepository {
  final deleted = <List<String>>[];
  final availabilityCalls = <(List<String>, bool)>[];

  /// Set to make the next write blow up, the way an RLS refusal would.
  bool failNext = false;

  @override
  Future<void> deleteProducts(String vendorId, List<String> ids) async {
    if (failNext) throw Exception('DENIED');
    deleted.add(ids);
  }

  @override
  Future<void> setProductsAvailability(
    String vendorId,
    List<String> ids,
    bool available,
  ) async {
    if (failNext) throw Exception('DENIED');
    availabilityCalls.add((ids, available));
  }

  @override
  Future<void> moveProducts(
    String vendorId,
    List<String> ids,
    String? categoryId,
  ) async {
    if (failNext) throw Exception('DENIED');
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

void main() {
  late _FakeCatalog catalog;
  late _FakeAdmin admin;

  MenuCubit build(List<Product> products) {
    catalog = _FakeCatalog(products, const []);
    admin = _FakeAdmin();
    return MenuCubit(catalog, admin, 'v1');
  }

  Future<MenuCubit> loaded(List<Product> products) async {
    final cubit = build(products);
    // The constructor kicks off load(); let it land before asserting.
    await Future<void>.delayed(Duration.zero);
    return cubit;
  }

  group('selection', () {
    test('toggling the same id twice returns to no selection', () async {
      final cubit = await loaded([_product('a'), _product('b')]);
      expect(cubit.state.selecting, isFalse);

      cubit.toggleSelected('a');
      expect(cubit.state.selection, {'a'});
      expect(cubit.state.selecting, isTrue);

      cubit.toggleSelected('a');
      expect(cubit.state.selection, isEmpty);
      expect(cubit.state.selecting, isFalse);
    });

    test('select all is a toggle, not a one-way door', () async {
      final cubit = await loaded([_product('a'), _product('b')]);
      final visible = cubit.state.products;

      cubit.toggleSelectAll(visible);
      expect(cubit.state.selection, {'a', 'b'});

      // Everything already picked, so the same control clears it.
      cubit.toggleSelectAll(visible);
      expect(cubit.state.selection, isEmpty);
    });

    test('select all covers only what was passed in', () async {
      final cubit = await loaded([_product('a'), _product('b'), _product('c')]);
      // What a filtered list would hand it.
      cubit.toggleSelectAll([cubit.state.products.first]);
      expect(cubit.state.selection, {'a'});
    });

    test('a stale id never reaches the write', () async {
      final cubit = await loaded([_product('a'), _product('b')]);
      cubit.toggleSelectAll(cubit.state.products);
      expect(cubit.state.selection, {'a', 'b'});

      // 'b' disappears — deleted in another tab, or gone on the next reload.
      catalog.products = [_product('a')];
      await cubit.load();

      await cubit.deleteSelected();
      // Not {'a','b'}: PostgREST would refuse the whole statement over the row
      // that is no longer there, taking 'a' down with it.
      expect(admin.deleted, [
        ['a'],
      ]);
    });

    test('a successful bulk write clears the selection', () async {
      final cubit = await loaded([_product('a'), _product('b')]);
      cubit.toggleSelectAll(cubit.state.products);

      await cubit.setSelectedAvailability(false);
      expect(admin.availabilityCalls, hasLength(1));
      expect(admin.availabilityCalls.single.$1, ['a', 'b']);
      expect(admin.availabilityCalls.single.$2, isFalse);
      expect(cubit.state.selection, isEmpty);
    });

    test('a failed bulk write keeps the selection so it can be retried',
        () async {
      final cubit = await loaded([_product('a'), _product('b')]);
      cubit.toggleSelectAll(cubit.state.products);
      admin.failNext = true;

      final ok = await cubit.setSelectedAvailability(false);
      expect(ok, isFalse);
      expect(cubit.state.error, isNotNull);
      // The whole point: the vendor does not have to pick the same rows again.
      expect(cubit.state.selection, {'a', 'b'});
    });

    test('an empty selection is a no-op rather than a write', () async {
      final cubit = await loaded([_product('a')]);
      expect(await cubit.deleteSelected(), isTrue);
      expect(admin.deleted, isEmpty);
    });
  });

  group('the uncategorised bucket', () {
    test('covers items with no section and items pointing at a dead one',
        () async {
      final cubit = await loaded([
        _product('a', categoryId: null),
        // A section id the loaded categories do not contain.
        _product('b', categoryId: 'gone'),
        _product('c', categoryId: 'real'),
      ]);
      catalog.categories = [
        const ProductCategory(id: 'real', vendorId: 'v1', name: 'Real'),
      ];
      await cubit.load();

      expect(cubit.state.uncategorized.map((p) => p.id), ['a', 'b']);
    });

    test('deleting it sends exactly those ids', () async {
      final cubit = await loaded([
        _product('a'),
        _product('b', categoryId: 'real'),
      ]);
      catalog.categories = [
        const ProductCategory(id: 'real', vendorId: 'v1', name: 'Real'),
      ];
      await cubit.load();

      await cubit.deleteUncategorized();
      expect(admin.deleted, [
        ['a'],
      ]);
    });
  });
}
