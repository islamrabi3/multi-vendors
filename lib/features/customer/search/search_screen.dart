import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart' show ProductHit;
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/vendor_card.dart';
import 'search_cubit.dart';

/// A page of its own, reached by tapping the home page's search bar.
///
/// Searching in place on the home page put the answers below the banners, the
/// category rail and two promoted rails — so the customer typed, saw nothing
/// change, and scrolled to find out whether it had worked. Here the field is
/// the first thing on screen with the keyboard already up, and the space below
/// it belongs entirely to the results.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => SearchCubit(CatalogRepository(), FavoritesRepository()),
      child: const _SearchView(),
    );
  }
}

class _SearchView extends StatefulWidget {
  const _SearchView();

  @override
  State<_SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<_SearchView> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Used by the recent-search chips: the field has to show what is being
  /// searched, or the customer cannot edit it afterwards.
  void _searchFor(String query) {
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
    context.read<SearchCubit>().submit(query);
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<SearchCubit>();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _SearchField(
              controller: _controller,
              focusNode: _focus,
              onChanged: cubit.setQuery,
              onSubmitted: cubit.submit,
              onClear: () {
                _controller.clear();
                cubit.setQuery('');
                _focus.requestFocus();
              },
            ),
            Expanded(
              child: BlocBuilder<SearchCubit, SearchState>(
                builder: (context, state) => switch (state.stage) {
                  SearchStage.idle => _RecentSearches(
                    recent: state.recent,
                    onTap: _searchFor,
                    onClear: cubit.clearRecent,
                  ),
                  SearchStage.searching => const _ResultsSkeleton(),
                  SearchStage.empty => _NoResults(
                    query: state.query,
                    error: state.error,
                  ),
                  SearchStage.results => _Results(state: state),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The field, with back and clear, styled as the home page's search bar so the
/// tap that opened this page reads as the bar growing into a screen.
class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: AppColors.ink),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          ),
          Expanded(
            child: Container(
              height: 48,
              padding: const EdgeInsetsDirectional.only(start: 14, end: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search_rounded,
                    size: 21,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      // The keyboard is already up: this page exists to be
                      // typed into, and asking for one more tap to start is
                      // the whole reason inline search felt slow.
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      style: const TextStyle(
                        fontSize: 15,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w600,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: context.l10n.searchStoresDishes,
                        hintStyle: const TextStyle(
                          fontSize: 14.5,
                          color: AppColors.textFaint,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox(width: 8)
                        : IconButton(
                            onPressed: onClear,
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 19,
                              color: AppColors.textMuted,
                            ),
                          ),
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

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.recent,
    required this.onTap,
    required this.onClear,
  });

  final List<String> recent;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (recent.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: EmptyView(
          message: context.l10n.searchPrompt,
          icon: Icons.search_rounded,
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        24,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.recentSearches,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.heading(16),
              ),
            ),
            TextButton(
              onPressed: onClear,
              child: Text(context.l10n.clearAll),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xs),
        for (final query in recent)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(
              Icons.history_rounded,
              color: AppColors.textMuted,
            ),
            title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(
              Icons.north_west_rounded,
              size: 17,
              color: AppColors.textFaint,
            ),
            onTap: () => onTap(query),
          ),
      ],
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults({required this.query, this.error});

  final String query;
  final String? error;

  @override
  Widget build(BuildContext context) {
    // A failed request and an honestly empty result are different problems and
    // only one of them is the customer's spelling.
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: ErrorView(message: context.l10n.searchFailed),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(32),
      child: EmptyView(
        message: context.l10n.noResultsFor(query),
        icon: Icons.search_off_rounded,
      ),
    );
  }
}

/// Dishes first, then the stores that sell them.
///
/// Somebody typing "kofta" is looking for the food; the shops are the answer
/// underneath. Both are in one scroll rather than behind tabs, because a tab
/// the customer has to discover hides half the results.
class _Results extends StatelessWidget {
  const _Results({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 28),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (state.products.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.restaurant_menu_rounded,
            title: context.l10n.dishes,
            count: state.products.length,
          ),
          _DishStrip(hits: state.products),
        ],
        if (state.vendors.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.storefront_rounded,
            title: context.l10n.storesLabel,
            count: state.vendors.length,
          ),
          for (final vendor in state.vendors)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
              child: VendorCard(
                vendor: vendor,
                isFavorite: state.favoriteVendorIds.contains(vendor.id),
                onToggleFavorite: () =>
                    context.read<SearchCubit>().toggleFavorite(vendor.id),
                // Explains a store whose own name has nothing to do with what
                // was typed.
                menuMatches: state.menuMatches[vendor.id],
              ),
            ),
        ],
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        AppSpace.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.heading(16),
            ),
          ),
          const SizedBox(width: 6),
          Text('$count', style: AppType.mono(12, color: AppColors.textFaint)),
        ],
      ),
    );
  }
}

class _DishStrip extends StatelessWidget {
  const _DishStrip({required this.hits});

  final List<ProductHit> hits;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return SizedBox(
      height: 182,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
        itemCount: hits.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final hit = hits[i];
          return SizedBox(
            width: 152,
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                // Straight to the store: the dish is the reason to go there,
                // and adding it to a cart needs its options, which a search
                // result does not carry.
                onTap: () => context.push('/vendors/${hit.vendorId}'),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.borderSoft),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppNetworkImage(
                        url: hit.imageUrl,
                        height: 94,
                        width: double.infinity,
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Flexible(
                                child: Text(
                                  hit.displayName(language),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.2,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Flexible(
                                child: Text(
                                  hit.vendorName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.2,
                                    color: AppColors.textMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              PriceText(formatMoney(hit.price), size: 13),
                            ],
                          ),
                        ),
                      ),
                    ],
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

class _ResultsSkeleton extends StatelessWidget {
  const _ResultsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.lg,
        AppSpace.gutter,
        24,
      ),
      children: [
        for (var i = 0; i < 5; i++)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Skeleton(width: 92, height: 92, radius: AppRadii.md),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(widthFactor: 0.55, height: 16),
                      SizedBox(height: 8),
                      Skeleton.line(widthFactor: 0.85, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
