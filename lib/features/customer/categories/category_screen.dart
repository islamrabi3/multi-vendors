import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/category_emoji.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/vendor_card.dart';
import 'category_cubit.dart';

/// One category: what is inside it, who the platform recommends there, and
/// every store filed under it.
///
/// Reached by tapping a kind of shop on the home page, and it is the last page
/// in the journey: the cuisines across the top filter the stores underneath in
/// place, so narrowing from Food to Pizza never costs another screen. The
/// customer can browse everything or narrow down without ever losing the list.
class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.categoryId});

  final String categoryId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Keyed by id: pushing Pizza on top of Food must build a second cubit,
      // not reuse the parent's.
      key: ValueKey(categoryId),
      create: (_) => CategoryCubit(
        CatalogRepository(),
        FavoritesRepository(),
        categoryId,
      ),
      child: const _CategoryView(),
    );
  }
}

class _CategoryView extends StatelessWidget {
  const _CategoryView();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CategoryCubit>();
    return BlocBuilder<CategoryCubit, CategoryState>(
      builder: (context, state) {
        final language = Localizations.localeOf(context).languageCode;
        final title =
            state.category?.label(language) ?? context.l10n.categoriesTab;
        // The app bar always names the parent — it is where back goes. The
        // headings below name whatever is actually on screen, which is the
        // narrowed sub-category once one is picked.
        final scopeTitle = state.selectedChild?.label(language) ?? title;
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(title: Text(title, overflow: TextOverflow.ellipsis)),
          body: switch (state) {
            CategoryState(loading: true) => const LoadingView(),
            CategoryState(error: final error?) when state.vendors.isEmpty =>
              ErrorView(message: error, onRetry: cubit.load),
            _ => RefreshIndicator(
              color: AppColors.primary,
              onRefresh: cubit.load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  if (state.children.isNotEmpty)
                    _SubcategoryStrip(
                      children: state.children,
                      selectedId: state.selectedChildId,
                      language: language,
                    ),
                  if (state.recommended.isNotEmpty)
                    _RecommendedRail(
                      vendors: state.recommended,
                      title: context.l10n.recommendedIn(scopeTitle),
                    ),
                  // Header and the open-only chip share a row: two stacked
                  // full-width rows for one short title and one chip was most
                  // of the empty band above the list.
                  _SectionHeader(
                    title: context.l10n.allStoresIn(scopeTitle),
                    count: state.visibleVendors.length,
                    openOnly: state.openOnly,
                  ),
                  if (state.visibleVendors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: EmptyView(
                        message: context.l10n.noStoresInCategory,
                        icon: Icons.storefront_outlined,
                      ),
                    )
                  else
                    for (final vendor in state.visibleVendors)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.gutter,
                        ),
                        child: VendorCard(
                          vendor: vendor,
                          isFavorite: state.favoriteVendorIds.contains(
                            vendor.id,
                          ),
                          onToggleFavorite: () => cubit.toggleFavorite(
                            vendor.id,
                          ),
                        ),
                      ),
                ],
              ),
            ),
          },
        );
      },
    );
  }
}

/// The level below, as a scrolling strip of artwork that filters the list.
///
/// A filter bar, not a menu: tapping Pizza narrows the stores underneath on the
/// same frame, and tapping it again clears. The grid this replaces pushed a
/// whole new page per tap — a route, a fetch and a back button for a change the
/// customer could already see the result of — and stacked four rows deep on a
/// parent with a dozen cuisines, so the stores started below the fold.
class _SubcategoryStrip extends StatelessWidget {
  const _SubcategoryStrip({
    required this.children,
    required this.selectedId,
    required this.language,
  });

  final List<VendorCategory> children;
  final String? selectedId;
  final String language;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CategoryCubit>();
    return SizedBox(
      // A horizontal list has to be told its height, so this is the tallest a
      // tile gets: a 71pt ring, the gap, and one label line at the 1.3x text
      // scale the app clamps to. The label below is flexible as well, so a font
      // whose line box lands a point taller ellipsises instead of overflowing.
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.sm,
          AppSpace.gutter,
          0,
        ),
        itemCount: children.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          // "All" leads, so clearing the filter is one tap and does not need
          // the customer to remember which chip they pressed.
          if (i == 0) {
            return _CategoryTile(
              label: context.l10n.all,
              icon: Icons.apps_rounded,
              selected: selectedId == null,
              onTap: () => cubit.selectChild(null),
            );
          }
          final category = children[i - 1];
          return _CategoryTile(
            label: category.label(language),
            imageUrl: category.imageUrl,
            fallbackEmoji: emojiFor(category.name).trim(),
            selected: category.id == selectedId,
            onTap: () => cubit.selectChild(category.id),
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.imageUrl,
    this.fallbackEmoji,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? imageUrl;
  final String? fallbackEmoji;
  final IconData? icon;

  static const _size = 62.0;

  @override
  Widget build(BuildContext context) {
    final image = imageUrl;
    return SizedBox(
      width: 72,
      // GestureDetector, not InkWell: the tap target is a circle of artwork,
      // and a rectangular ripple painted around it read as a glitch. The ring
      // and the coloured label are the feedback.
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // A ring rather than a tint: the artwork is the thing being
                // chosen, and colouring over it would hide what it shows.
                border: Border.all(
                  color: selected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: image != null && image.isNotEmpty
                    ? AppNetworkImage(url: image, height: _size, width: _size)
                    : Container(
                        width: _size,
                        height: _size,
                        alignment: Alignment.center,
                        color: AppColors.warmFill,
                        child: icon != null
                            ? Icon(icon, size: 26, color: AppColors.primary)
                            : Text(
                                fallbackEmoji ?? '',
                                style: const TextStyle(fontSize: 26),
                              ),
                      ),
              ),
            ),
            const SizedBox(height: 5),
            // Flexible, not fixed: the label's line box depends on the font,
            // the locale and the text scale, and any of those landing a point
            // over the budget would overflow the strip. Given the leftover
            // height it ellipsises instead.
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.2,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? AppColors.primary : AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecommendedRail extends StatelessWidget {
  const _RecommendedRail({required this.vendors, required this.title});

  final List<Vendor> vendors;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.md,
            AppSpace.gutter,
            AppSpace.xs,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(17),
                ),
              ),
            ],
          ),
        ),
        for (final vendor in vendors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: VendorCard(vendor: vendor),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.openOnly,
  });

  final String title;
  final int count;
  final bool openOnly;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        AppSpace.xs,
      ),
      child: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.display(18),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            context.l10n.storesCount(count),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textMuted,
            ),
          ),
          const Spacer(),
          // Sits on the title's row rather than a line of its own: one short
          // chip did not earn a full-width band between the heading and the
          // first store.
          FilterChip(
            selected: openOnly,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(context.l10n.openNow),
            onSelected: context.read<CategoryCubit>().setOpenOnly,
          ),
        ],
      ),
    );
  }
}
