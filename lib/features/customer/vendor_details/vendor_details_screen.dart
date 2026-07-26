import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../cart/cart_cubit.dart';
import 'product_sheet.dart';
import 'vendor_details_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

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
                message: context.l10n.couldNotLoadThisStore,
                onRetry: context.read<VendorDetailsCubit>().load);
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 180,
                pinned: true,
                backgroundColor: AppColors.canvas,
                surfaceTintColor: Colors.transparent,
                foregroundColor: AppColors.ink,
                automaticallyImplyLeading: false,
                leadingWidth: 60,
                leading: _CircleButton(
                  icon: Icons.chevron_left,
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: AppNetworkImage(
                      url: vendor.coverUrl, width: double.infinity),
                ),
                actions: [
                  _CircleButton(
                    icon: state.isFavorite
                        ? Icons.favorite
                        : Icons.favorite_border,
                    iconColor: state.isFavorite ? Colors.red : AppColors.ink,
                    onPressed:
                        context.read<VendorDetailsCubit>().toggleFavorite,
                  ),
                  const SizedBox(width: 8),
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
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
              message: context.l10n.menuComingSoon, icon: Icons.menu_book_outlined),
        ),
    ];
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.iconColor = AppColors.ink,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: Colors.white.withValues(alpha: 0.92),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 22, color: iconColor),
            ),
          ),
        ),
      ),
    );
  }
}

class _VendorHeader extends StatelessWidget {
  const _VendorHeader({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return Container(
      transform: Matrix4.translationValues(0, -22, 0),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
                child: AppNetworkImage(
                    url: vendor.logoUrl,
                    height: 58,
                    width: 58,
                    borderRadius: BorderRadius.circular(16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(vendor.name,
                        style: Theme.of(context).textTheme.headlineMedium),
                    if (vendor.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(vendor.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  value: vendor.ratingCount == 0
                      ? 'New'
                      : vendor.ratingAvg.toStringAsFixed(1),
                  label: vendor.ratingCount == 0
                      ? 'ratings'
                      : '${vendor.ratingCount} ratings',
                  star: vendor.ratingCount > 0,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _StatTile(
                    value: '${vendor.avgPrepMinutes}′', label: 'delivery'),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _StatTile(
                  value: formatMoney(vendor.deliveryFee),
                  label: vendor.minOrderAmount > 0
                      ? 'fee · min ${vendor.minOrderAmount.toStringAsFixed(0)}'
                      : 'delivery fee',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label, this.star = false});

  final String value;
  final String label;
  final bool star;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (star) ...[
                const Icon(Icons.star_rounded,
                    size: 15, color: AppColors.rating),
                const SizedBox(width: 3),
              ],
              Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink)),
            ],
          ),
          const SizedBox(height: 1),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.vendor, required this.product});

  final Vendor vendor;
  final Product product;

  @override
  Widget build(BuildContext context) {
    final hasDesc = product.description?.isNotEmpty ?? false;
    return InkWell(
      onTap: vendor.isOpen
          ? () => showProductSheet(context, vendor, product)
          : () => showSnack(context, context.l10n.thisStoreIsCurrentlyClosed),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(product.name,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.ink)),
                  if (hasDesc) ...[
                    const SizedBox(height: 3),
                    Text(product.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 7),
                  PriceText(formatMoney(product.price)),
                ],
              ),
            ),
            const SizedBox(width: 13),
            Stack(
              clipBehavior: Clip.none,
              children: [
                AppNetworkImage(
                    url: product.imageUrl,
                    height: 84,
                    width: 84,
                    borderRadius: BorderRadius.circular(15)),
                if (vendor.isOpen)
                  Positioned(
                    bottom: -9,
                    right: -6,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.primaryGlow,
                      ),
                      child: const Icon(Icons.add,
                          size: 18, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: InkWell(
              onTap: () => context.push('/cart'),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Container(
                height: 54,
                padding: const EdgeInsets.only(left: 18, right: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  boxShadow: AppShadows.primaryGlow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text('${cart.itemCount}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13)),
                        ),
                        const SizedBox(width: 10),
                        Text(context.l10n.viewCart,
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                      ],
                    ),
                    PriceText(formatMoney(cart.subtotal),
                        size: 15, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
