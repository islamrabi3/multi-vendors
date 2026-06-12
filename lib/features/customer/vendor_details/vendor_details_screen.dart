import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'product_sheet.dart';
import 'vendor_details_cubit.dart';

class VendorDetailsScreen extends StatelessWidget {
  const VendorDetailsScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => VendorDetailsCubit(
          CatalogRepository(), FavoritesRepository(), vendorId),
      child: const _VendorDetailsView(),
    );
  }
}

class _VendorDetailsView extends StatelessWidget {
  const _VendorDetailsView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<VendorDetailsCubit, VendorDetailsState>(
        builder: (context, state) {
          if (state.loading) return const LoadingView();
          final vendor = state.vendor;
          if (vendor == null) {
            return ErrorView(
                message: 'Could not load this store.',
                onRetry: context.read<VendorDetailsCubit>().load);
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 180,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: AppNetworkImage(
                      url: vendor.coverUrl, width: double.infinity),
                ),
                actions: [
                  IconButton(
                    onPressed:
                        context.read<VendorDetailsCubit>().toggleFavorite,
                    icon: Icon(
                      state.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: state.isFavorite ? Colors.red : null,
                    ),
                  ),
                ],
              ),
              SliverToBoxAdapter(child: _VendorHeader(vendor: vendor)),
              ..._menuSlivers(context, state, vendor),
              const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
            ],
          );
        },
      ),
      bottomNavigationBar: const _CartBar(),
    );
  }

  List<Widget> _menuSlivers(
      BuildContext context, VendorDetailsState state, Vendor vendor) {
    final sections = <(String, List<Product>)>[
      for (final category in state.menuCategories)
        (category.name, state.productsIn(category.id)),
      if (state.uncategorized.isNotEmpty) ('Other', state.uncategorized),
    ];
    return [
      for (final (title, products) in sections)
        if (products.isNotEmpty)
          SliverMainAxisGroup(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ),
            SliverList.builder(
              itemCount: products.length,
              itemBuilder: (context, index) =>
                  _ProductTile(vendor: vendor, product: products[index]),
            ),
          ]),
      if (sections.every((s) => s.$2.isEmpty))
        const SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
              message: 'Menu coming soon', icon: Icons.menu_book_outlined),
        ),
    ];
  }
}

class _VendorHeader extends StatelessWidget {
  const _VendorHeader({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppNetworkImage(
                  url: vendor.logoUrl,
                  height: 52,
                  width: 52,
                  borderRadius: BorderRadius.circular(10)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(vendor.name,
                    style: Theme.of(context).textTheme.headlineSmall),
              ),
              if (!vendor.isOpen)
                const Chip(
                  label: Text('Closed'),
                  backgroundColor: Colors.black87,
                  labelStyle: TextStyle(color: Colors.white),
                ),
            ],
          ),
          if (vendor.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 8),
            Text(vendor.description!,
                style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Info(
                  icon: Icons.star,
                  text: vendor.ratingCount == 0
                      ? 'New'
                      : '${vendor.ratingAvg.toStringAsFixed(1)} '
                          '(${vendor.ratingCount})'),
              _Info(
                  icon: Icons.timer_outlined,
                  text: '${vendor.avgPrepMinutes} min'),
              _Info(
                  icon: Icons.delivery_dining_outlined,
                  text: formatMoney(vendor.deliveryFee)),
              if (vendor.minOrderAmount > 0)
                _Info(
                    icon: Icons.shopping_basket_outlined,
                    text: 'Min ${formatMoney(vendor.minOrderAmount)}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 4),
        Text(text, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.vendor, required this.product});

  final Vendor vendor;
  final Product product;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppNetworkImage(
          url: product.imageUrl,
          height: 56,
          width: 56,
          borderRadius: BorderRadius.circular(8)),
      title: Text(product.name),
      subtitle: product.description?.isNotEmpty ?? false
          ? Text(product.description!,
              maxLines: 2, overflow: TextOverflow.ellipsis)
          : null,
      trailing: Text(formatMoney(product.price),
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
      onTap: vendor.isOpen
          ? () => showProductSheet(context, vendor, product)
          : () => showSnack(context, 'This store is currently closed.'),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CartCubit, CartState>(
      builder: (context, cart) {
        if (cart.isEmpty) return const SizedBox.shrink();
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              onPressed: () => context.push('/cart'),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}'),
                  const Text('View cart'),
                  Text(formatMoney(cart.subtotal)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
