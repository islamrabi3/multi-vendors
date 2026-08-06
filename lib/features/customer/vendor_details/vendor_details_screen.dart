import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/models/banner_item.dart' show AdPlacement;
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../cart/cart_cubit.dart';
import 'product_quantity_control.dart';
import 'product_sheet.dart';
import 'vendor_details_cubit.dart';
import 'vendor_reviews_preview.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class VendorDetailsScreen extends StatelessWidget {
  const VendorDetailsScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => VendorDetailsCubit(
        CatalogRepository(),
        FavoritesRepository(),
        vendorId,
      ),
      child: const _VendorDetailsView(),
    );
  }
}

class _VendorDetailsView extends StatefulWidget {
  const _VendorDetailsView();

  @override
  State<_VendorDetailsView> createState() => _VendorDetailsViewState();
}

class _VendorDetailsViewState extends State<_VendorDetailsView> {
  /// One key per rendered section, so tapping a chip can scroll to it.
  final _sectionKeys = <String, GlobalKey>{};
  final _chipsController = ScrollController();

  @override
  void dispose() {
    _chipsController.dispose();
    super.dispose();
  }

  void _jumpToSection(String id) {
    final target = _sectionKeys[id]?.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      // Leaves the pinned app bar clear of the heading.
      alignment: 0.08,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<VendorDetailsCubit, VendorDetailsState>(
        builder: (context, state) {
          if (state.loading) return const _VendorDetailsSkeleton();
          final vendor = state.vendor;
          if (vendor == null) {
            return ErrorView(
              message: context.l10n.couldNotLoadThisStore,
              onRetry: context.read<VendorDetailsCubit>().load,
            );
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
                  // arrow_back carries matchTextDirection, so it points the
                  // right way in Arabic without a manual flip.
                  icon: Icons.arrow_back,
                  onPressed: () => context.pop(),
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: AppNetworkImage(
                    url: vendor.coverUrl,
                    width: double.infinity,
                  ),
                ),
                actions: [
                  _CircleButton(
                    icon: state.isFavorite
                        ? Icons.favorite
                        : Icons.favorite_border,
                    iconColor: state.isFavorite
                        ? AppColors.dangerInk
                        : AppColors.ink,
                    onPressed: context
                        .read<VendorDetailsCubit>()
                        .toggleFavorite,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              SliverToBoxAdapter(child: _VendorHeader(vendor: vendor)),
              const SliverToBoxAdapter(
                child: AdSlot(
                  placement: AdPlacement.vendorTop,
                  height: 110,
                  margin: EdgeInsets.fromLTRB(16, 4, 16, 0),
                ),
              ),
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
    BuildContext context,
    VendorDetailsState state,
    Vendor vendor,
  ) {
    final language = Localizations.localeOf(context).languageCode;
    final sections = <_MenuSection>[
      for (final category in state.menuCategories)
        if (state.productsIn(category.id).isNotEmpty)
          _MenuSection(
            id: category.id,
            title: category.displayName(language),
            products: state.productsIn(category.id),
          ),
      if (state.uncategorized.isNotEmpty)
        _MenuSection(
          id: '__uncategorized__',
          title: context.l10n.other,
          products: state.uncategorized,
        ),
    ];

    if (sections.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            message: context.l10n.menuComingSoon,
            icon: Icons.menu_book_outlined,
          ),
        ),
      ];
    }

    // Keys are rebuilt from the current sections so a menu refresh cannot
    // leave a chip pointing at a heading that no longer exists.
    _sectionKeys
      ..removeWhere((id, _) => !sections.any((s) => s.id == id))
      ..addEntries(
        sections
            .where((s) => !_sectionKeys.containsKey(s.id))
            .map((s) => MapEntry(s.id, GlobalKey())),
      );

    return [
      // A pinned rail so a long menu is always one tap from any section.
      if (sections.length > 1)
        SliverPersistentHeader(
          pinned: true,
          delegate: _SectionChipsHeader(
            height: 56,
            child: _SectionChips(
              sections: sections,
              controller: _chipsController,
              onTap: _jumpToSection,
            ),
          ),
        ),
      for (final section in sections)
        SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                key: _sectionKeys[section.id],
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            SliverList.builder(
              itemCount: section.products.length,
              itemBuilder: (context, index) => _ProductTile(
                vendor: vendor,
                product: section.products[index],
              ),
            ),
          ],
        ),
      // Under the menu rather than above it: the customer came to order, and
      // what other people said is what they read while deciding.
      SliverToBoxAdapter(
        child: VendorReviewsPreview(
          vendorId: vendor.id,
          vendorName: vendor.name,
        ),
      ),
    ];
  }
}

/// One rendered menu section: its id doubles as the scroll-target key.
class _MenuSection {
  const _MenuSection({
    required this.id,
    required this.title,
    required this.products,
  });

  final String id;
  final String title;
  final List<Product> products;
}

class _SectionChips extends StatelessWidget {
  const _SectionChips({
    required this.sections,
    required this.controller,
    required this.onTap,
  });

  final List<_MenuSection> sections;
  final ScrollController controller;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.canvas,
      alignment: Alignment.center,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final section = sections[i];
          return Center(
            child: GestureDetector(
              onTap: () => onTap(section.id),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '${section.title}  ${section.products.length}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionChipsHeader extends SliverPersistentHeaderDelegate {
  const _SectionChipsHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      SizedBox(height: height, child: child);

  @override
  bool shouldRebuild(_SectionChipsHeader oldDelegate) =>
      oldDelegate.child != child || oldDelegate.height != height;
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
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    // The store's real state, which is the switch *and* today's
                    // hours. Nothing on this page said either, so a customer
                    // built a whole basket before checkout refused it.
                    const SizedBox(height: 4),
                    if (!vendor.isOpenNow())
                      SoftBadge(
                        label: context.l10n.closedNow,
                        fill: AppColors.neutralFill,
                        ink: AppColors.textMuted,
                        icon: Icons.schedule_rounded,
                      )
                    else if (vendor.closingTime() != null)
                      SoftBadge(
                        label: context.l10n.openUntil(vendor.closingTime()!),
                        fill: AppColors.successFill,
                        ink: AppColors.successInk,
                        icon: Icons.schedule_rounded,
                      ),
                    if (vendor.description?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 2),
                      Text(
                        vendor.description!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
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
                  value: '${vendor.totalPrepMinutes}′',
                  label: 'delivery',
                ),
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
          if (vendor.isBusy) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.amberFill,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(
                  color: AppColors.amberInk.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppColors.amberInk,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.busyStoreNotice,
                      style: const TextStyle(
                        color: AppColors.amberInk,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.value,
    required this.label,
    this.star = false,
  });

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
                const Icon(
                  Icons.star_rounded,
                  size: 15,
                  color: AppColors.rating,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
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
    final language = Localizations.localeOf(context).languageCode;
    final description = product.displayDescription(language);
    return InkWell(
      onTap: vendor.isOpenNow()
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
                  Text(
                    product.displayName(language),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
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
                  borderRadius: BorderRadius.circular(15),
                ),
                if (vendor.isOpenNow())
                  PositionedDirectional(
                    bottom: -9,
                    end: -6,
                    // Its own tap target, separate from the row. The row means
                    // "show me this item"; this means "I want it", and once it
                    // is in the cart it turns into the stepper for that line.
                    child: ProductQuantityControl(
                      vendor: vendor,
                      product: product,
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
                padding: const EdgeInsetsDirectional.only(start: 18, end: 12),
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
                          child: Text(
                            '${cart.itemCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          context.l10n.viewCart,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                    PriceText(
                      formatMoney(cart.subtotal),
                      size: 15,
                      color: Colors.white,
                    ),
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

/// The store page while its header and menu load: cover, logo + name block,
/// three stat tiles, then menu rows with their thumbnails.
class _VendorDetailsSkeleton extends StatelessWidget {
  const _VendorDetailsSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const Skeleton(height: 180, radius: 0),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.canvas,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppRadii.xxl),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                28,
                AppSpace.lg,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Skeleton(width: 58, height: 58, radius: AppRadii.lg),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Skeleton.line(widthFactor: 0.55, height: 22),
                            SizedBox(height: 6),
                            Skeleton.line(widthFactor: 0.75, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: const [
                      Expanded(
                        child: Skeleton(height: 56, radius: AppRadii.md),
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Skeleton(height: 56, radius: AppRadii.md),
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Skeleton(height: 56, radius: AppRadii.md),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xxl),
                  const Skeleton.line(widthFactor: 0.35, height: 19),
                  const SizedBox(height: AppSpace.md),
                  for (var i = 0; i < 4; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: AppSpace.xxl),
                      child: _ProductRowSkeleton(),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors `_ProductTile`: copy on the leading side, 84px thumbnail trailing.
class _ProductRowSkeleton extends StatelessWidget {
  const _ProductRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Skeleton.line(widthFactor: 0.6, height: 15),
              SizedBox(height: 7),
              Skeleton.line(widthFactor: 0.9, height: 12),
              SizedBox(height: AppSpace.md),
              Skeleton(width: 72, height: 14),
            ],
          ),
        ),
        SizedBox(width: 13),
        Skeleton(width: 84, height: 84, radius: 15),
      ],
    );
  }
}
