import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/banner_item.dart' show AdPlacement;
import '../../../core/models/product.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../cart/cart_cubit.dart';
import 'product_quantity_control.dart';
import 'product_sheet.dart';
import 'store_offers_strip.dart';
import 'vendor_details_cubit.dart';
import 'vendor_reviews_preview.dart';
import 'vendor_reviews_screen.dart';

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
  static const _coverHeight = 210.0;
  static const _chipsHeight = 58.0;

  final _scroll = ScrollController();
  final _chipsController = ScrollController();
  final _searchController = TextEditingController();

  /// One key per rendered section heading (scroll target) and per chip (so
  /// the active chip can be brought into view).
  final _sectionKeys = <String, GlobalKey>{};
  final _chipKeys = <String, GlobalKey>{};
  List<String> _sectionOrder = const [];

  String? _activeSection;
  bool _collapsed = false;
  bool _searching = false;
  String _query = '';

  /// True while a chip tap is animating the page, so the scroll spy does not
  /// flick the highlight through every section on the way.
  bool _jumping = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _chipsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final collapsed = _scroll.offset > _coverHeight - kToolbarHeight - 40;
    if (collapsed != _collapsed) setState(() => _collapsed = collapsed);
    if (_jumping || _searching) return;

    // The section whose heading has passed under the pinned bars is the one
    // being read.
    final line =
        MediaQuery.paddingOf(context).top + kToolbarHeight + _chipsHeight + 24;
    String? current;
    for (final id in _sectionOrder) {
      final box =
          _sectionKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) break;
      if (box.localToGlobal(Offset.zero).dy <= line) {
        current = id;
      } else {
        break;
      }
    }
    current ??= _sectionOrder.isEmpty ? null : _sectionOrder.first;
    if (current != _activeSection) {
      setState(() => _activeSection = current);
      _revealChip(current);
    }
  }

  void _revealChip(String? id) {
    final box = _chipKeys[id]?.currentContext?.findRenderObject();
    if (box == null || !_chipsController.hasClients) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _chipsController.position;
    final target = viewport
        .getOffsetToReveal(box, 0.5)
        .offset
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _chipsController.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _jumpToSection(String id) async {
    final target = _sectionKeys[id]?.currentContext;
    if (target == null) return;
    setState(() {
      _activeSection = id;
      _jumping = true;
    });
    _revealChip(id);
    await Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
      alignment: 0.12,
    );
    if (mounted) _jumping = false;
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _searchController.clear();
        _query = '';
      }
    });
    if (_searching && _scroll.hasClients) {
      // Straight to the menu, so results are not hidden under the cover.
      final menuTop = _coverHeight - kToolbarHeight;
      if (_scroll.offset < menuTop) {
        _scroll.animateTo(
          menuTop + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
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
            controller: _scroll,
            slivers: [
              _appBar(context, state, vendor),
              SliverToBoxAdapter(child: _VendorHeader(vendor: vendor)),
              SliverToBoxAdapter(child: StoreOffersStrip(vendorId: vendor.id)),
              const SliverToBoxAdapter(
                child: AdSlot(
                  placement: AdPlacement.vendorTop,
                  height: 110,
                  margin: EdgeInsets.fromLTRB(16, 12, 16, 0),
                ),
              ),
              ..._menuSlivers(context, state, vendor),
              const SliverPadding(padding: EdgeInsets.only(bottom: 110)),
            ],
          );
        },
      ),
      bottomNavigationBar: const _CartBar(),
    );
  }

  Widget _appBar(
    BuildContext context,
    VendorDetailsState state,
    Vendor vendor,
  ) {
    return SliverAppBar(
      expandedHeight: _coverHeight,
      pinned: true,
      backgroundColor: _collapsed ? AppColors.surface : AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      automaticallyImplyLeading: false,
      leadingWidth: 60,
      leading: _CircleButton(
        // arrow_back carries matchTextDirection, so it points the right way
        // in Arabic without a manual flip.
        icon: Icons.arrow_back,
        flat: _collapsed,
        onPressed: () => context.pop(),
      ),
      // The store's name appears in the bar once the cover has scrolled away,
      // so the customer never loses track of whose menu this is.
      title: AnimatedOpacity(
        opacity: _collapsed ? 1 : 0,
        duration: const Duration(milliseconds: 180),
        child: Text(
          vendor.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.heading(17),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            AppNetworkImage(url: vendor.coverUrl, width: double.infinity),
            // Keeps the round buttons readable over a bright photo.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Color(0x66000000), Color(0x00000000)],
                ),
              ),
            ),
            if (!vendor.isOpenNow())
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: AppSpace.sm,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      context.l10n.closedNow,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            // A rounded lip drawn inside the cover itself, so the page reads
            // as a sheet pulled over the photo without anything overlapping
            // the pinned bar.
            const PositionedDirectional(
              start: 0,
              end: 0,
              bottom: -1,
              height: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.canvas,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (state.products.isNotEmpty)
          _CircleButton(
            icon: _searching ? Icons.close_rounded : Icons.search_rounded,
            flat: _collapsed,
            onPressed: _toggleSearch,
          ),
        _CircleButton(
          icon: state.isFavorite
              ? Icons.favorite_rounded
              : Icons.favorite_border_rounded,
          iconColor: state.isFavorite ? AppColors.primary : AppColors.ink,
          flat: _collapsed,
          onPressed: context.read<VendorDetailsCubit>().toggleFavorite,
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  List<Widget> _menuSlivers(
    BuildContext context,
    VendorDetailsState state,
    Vendor vendor,
  ) {
    final l10n = context.l10n;
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
          title: l10n.other,
          products: state.uncategorized,
        ),
    ];

    if (sections.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            message: l10n.menuComingSoon,
            icon: Icons.menu_book_outlined,
          ),
        ),
      ];
    }

    // Keys follow the current sections, so a live menu refresh cannot leave a
    // chip pointing at a heading that no longer exists.
    _sectionOrder = [for (final s in sections) s.id];
    for (final keys in [_sectionKeys, _chipKeys]) {
      keys
        ..removeWhere((id, _) => !_sectionOrder.contains(id))
        ..addEntries(
          _sectionOrder
              .where((id) => !keys.containsKey(id))
              .map((id) => MapEntry(id, GlobalKey())),
        );
    }
    final active = _activeSection ?? sections.first.id;

    if (_searching) {
      final query = _query.trim().toLowerCase();
      final matches = query.isEmpty
          ? const <Product>[]
          : [
              for (final section in sections)
                for (final product in section.products)
                  if (product
                          .displayName(language)
                          .toLowerCase()
                          .contains(query) ||
                      (product
                              .displayDescription(language)
                              ?.toLowerCase()
                              .contains(query) ??
                          false))
                    product,
            ];
      return [
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBar(
            height: _chipsHeight,
            child: _MenuSearchField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              onClose: _toggleSearch,
            ),
          ),
        ),
        if (query.isEmpty)
          const SliverToBoxAdapter(child: SizedBox(height: 240))
        else if (matches.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: EmptyView(
                message: l10n.noResultsFor(_query.trim()),
                icon: Icons.search_off_rounded,
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: _MenuCard(
              title: l10n.itemsCount(matches.length),
              children: [
                for (final product in matches)
                  _ProductTile(vendor: vendor, product: product),
              ],
            ),
          ),
      ];
    }

    return [
      if (sections.length > 1)
        SliverPersistentHeader(
          pinned: true,
          delegate: _PinnedBar(
            height: _chipsHeight,
            child: _SectionChips(
              sections: sections,
              activeId: active,
              chipKeys: _chipKeys,
              controller: _chipsController,
              onTap: _jumpToSection,
            ),
          ),
        ),
      for (final section in sections)
        SliverToBoxAdapter(
          child: _MenuCard(
            key: _sectionKeys[section.id],
            title: section.title,
            count: section.products.length,
            children: [
              for (final product in section.products)
                _ProductTile(vendor: vendor, product: product),
            ],
          ),
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

/// A menu section: heading, then its items as one card with hairline
/// dividers — reads as a menu page rather than loose rows on the canvas.
class _MenuCard extends StatelessWidget {
  const _MenuCard({
    super.key,
    required this.title,
    required this.children,
    this.count,
  });

  final String title;
  final int? count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 10),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.heading(18),
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    context.l10n.itemsCount(count!),
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      indent: 14,
                      endIndent: 14,
                      color: AppColors.borderSoft,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionChips extends StatelessWidget {
  const _SectionChips({
    required this.sections,
    required this.activeId,
    required this.chipKeys,
    required this.controller,
    required this.onTap,
  });

  final List<_MenuSection> sections;
  final String activeId;
  final Map<String, GlobalKey> chipKeys;
  final ScrollController controller;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: controller,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: sections.length,
      separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
      itemBuilder: (context, i) {
        final section = sections[i];
        final active = section.id == activeId;
        return Center(
          key: chipKeys[section.id],
          child: Material(
            color: active ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              onTap: () => onTap(section.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(
                    color: active ? AppColors.ink : AppColors.border,
                  ),
                ),
                child: Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: active ? Colors.white : AppColors.ink,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MenuSearchField extends StatelessWidget {
  const _MenuSearchField({
    required this.controller,
    required this.onChanged,
    required this.onClose,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: TextField(
        controller: controller,
        autofocus: true,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: context.l10n.searchMenuHint,
          isDense: true,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
        ),
      ),
    );
  }
}

class _PinnedBar extends SliverPersistentHeaderDelegate {
  const _PinnedBar({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.canvas,
        border: overlaps
            ? const Border(bottom: BorderSide(color: AppColors.borderSoft))
            : null,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  @override
  bool shouldRebuild(_PinnedBar oldDelegate) => true;
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.iconColor = AppColors.ink,
    this.flat = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final Color iconColor;

  /// Over the cover it is a white disc; once the bar is solid it drops the
  /// disc and reads as an ordinary toolbar icon.
  final bool flat;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: flat
              ? Colors.transparent
              : Colors.white.withValues(alpha: 0.94),
          shape: const CircleBorder(),
          elevation: flat ? 0 : 1,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: 40,
              height: 40,
              child: Icon(icon, size: 21, color: iconColor),
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

  static const _logoSize = 64.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final open = vendor.isOpenNow();
    final closing = vendor.closingTime();
    final free = vendor.deliveryFee == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Nothing here reaches up into the cover: the pinned app bar paints
          // over the slivers after it, so an overlapping logo was hidden.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: _logoSize,
                height: _logoSize,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borderSoft),
                  boxShadow: AppShadows.card,
                ),
                child: AppNetworkImage(
                  url: vendor.logoUrl,
                  height: _logoSize - 8,
                  width: _logoSize - 8,
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vendor.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.display(22).copyWith(height: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (!open)
                          SoftBadge(
                            label: l10n.closedNow,
                            fill: AppColors.neutralFill,
                            ink: AppColors.textMuted,
                            icon: Icons.schedule_rounded,
                          )
                        else if (closing != null)
                          SoftBadge(
                            label: l10n.openUntil(
                              formatClockText(context, closing),
                            ),
                            fill: AppColors.successFill,
                            ink: AppColors.successInk,
                            icon: Icons.schedule_rounded,
                          ),
                        if (vendor.isSubscription)
                          SoftBadge(
                            label: l10n.proPartner,
                            fill: AppColors.warmFill,
                            ink: AppColors.primaryDark,
                            icon: Icons.verified_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (vendor.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(
              vendor.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
          // One card, three facts, divided — instead of three boxed
          // tiles competing with each other.
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _InfoFact(
                      icon: Icons.star_rounded,
                      iconColor: AppColors.rating,
                      value: vendor.ratingCount == 0
                          ? l10n.newStoreBadge
                          : vendor.ratingAvg.toStringAsFixed(1),
                      label: vendor.ratingCount == 0
                          ? l10n.ratings
                          : l10n.ratingsCountLabel(vendor.ratingCount),
                      onTap: vendor.ratingCount == 0
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => VendorReviewsScreen(
                                  vendorId: vendor.id,
                                  vendorName: vendor.name,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.borderSoft),
                  Expanded(
                    child: _InfoFact(
                      icon: Icons.schedule_rounded,
                      iconColor: AppColors.primary,
                      value: l10n.minutesRange(
                        vendor.totalPrepMinutes,
                        vendor.totalPrepMinutes + 10,
                      ),
                      label: l10n.deliveryTimeLabel,
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AppColors.borderSoft),
                  Expanded(
                    child: _InfoFact(
                      icon: Icons.delivery_dining_rounded,
                      iconColor: free
                          ? AppColors.successInk
                          : AppColors.primary,
                      value: free
                          ? l10n.freeDelivery
                          : formatMoney(vendor.deliveryFee),
                      label: l10n.deliveryFee,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (vendor.minOrderAmount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Icons.shopping_bag_outlined,
                  size: 15,
                  color: AppColors.textFaint,
                ),
                const SizedBox(width: 6),
                Text(
                  '${l10n.minimumOrder}: ${formatMoney(vendor.minOrderAmount)}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
          if (vendor.isBusy) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.amberFill,
                borderRadius: BorderRadius.circular(AppRadii.md),
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
                      l10n.busyStoreNotice,
                      style: const TextStyle(
                        color: AppColors.amberInk,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
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

class _InfoFact extends StatelessWidget {
  const _InfoFact({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: iconColor),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textFaint,
                    ),
                  ),
                ),
                if (onTap != null)
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: AppColors.textFaint,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.vendor, required this.product});

  final Vendor vendor;
  final Product product;

  static const _imageSize = 92.0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final description = product.displayDescription(language);
    final open = vendor.isOpenNow();
    final soldOut = !product.isSellable;
    final hasImage = product.imageUrl?.isNotEmpty ?? false;
    final canAdd = open && !soldOut;

    final control = canAdd
        ? ProductQuantityControl(vendor: vendor, product: product)
        : null;

    return InkWell(
      onTap: soldOut
          ? null
          : open
          ? () => showProductSheet(context, vendor, product)
          : () => showSnack(context, l10n.thisStoreIsCurrentlyClosed),
      child: Opacity(
        opacity: soldOut ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: hasImage ? _imageSize : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        product.displayName(language),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          height: 1.3,
                          color: AppColors.ink,
                        ),
                      ),
                      if (description != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            height: 1.4,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          PriceText(formatMoney(product.price), size: 14.5),
                          if (soldOut) ...[
                            const SizedBox(width: 8),
                            SoftBadge(
                              label: l10n.soldOut,
                              fill: AppColors.neutralFill,
                              ink: AppColors.textMuted,
                            ),
                          ],
                          const Spacer(),
                          if (!hasImage && control != null) control,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (hasImage) ...[
                const SizedBox(width: 14),
                SizedBox(
                  width: _imageSize,
                  height: _imageSize + 10,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AppNetworkImage(
                        url: product.imageUrl,
                        height: _imageSize,
                        width: _imageSize,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      if (control != null)
                        PositionedDirectional(
                          bottom: 0,
                          end: -4,
                          // Its own tap target, separate from the row. The row
                          // means "show me this item"; this means "I want it",
                          // and once in the cart it becomes the line's stepper.
                          child: control,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
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
