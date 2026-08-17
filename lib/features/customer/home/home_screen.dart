import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/banner_item.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/repositories/offers_repository.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/category_emoji.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/ad_slot.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/messages_button.dart';
import '../../../core/widgets/notification_bell.dart';
import '../../../core/widgets/interstitial_ad.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/vendor_card.dart';
import 'home_cubit.dart';
import 'vendor_filters_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(
        CatalogRepository(),
        AddressRepository(),
        FavoritesRepository(),
      ),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  @override
  void initState() {
    super.initState();
    // After the first frame, so the takeover lands on a drawn home page rather
    // than on a blank one — and only once per launch, which
    // `InterstitialAds.maybeShow` enforces for every campaign at once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      InterstitialAds.maybeShow(context, repository: OffersRepository());
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<HomeCubit, HomeState>(
          builder: (context, state) {
            if (state.loading) return _HomeSkeleton(state: state);
            if (state.error != null && state.vendors.isEmpty) {
              return ErrorView(
                message: context.l10n.couldNotLoadStores,
                onRetry: cubit.load,
              );
            }
            final vendors = state.visibleVendors;
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: cubit.load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  _Header(key: const ValueKey('home_header'), state: state),
                  _SearchBar(
                    key: const ValueKey('home_search_bar'),
                    filters: state.filters,
                  ),
                  _Offers(offers: state.banners),
                  // A second surface, between the rails rather than at the
                  // top: empty until somebody buys it, so it costs nothing.
                  const AdSlot(placement: AdPlacement.homeInline),
                  _CategoryRail(state: state),
                  _VendorRail(
                    title: context.l10n.recommended,
                    icon: Icons.auto_awesome_rounded,
                    vendors: cubit.state.recommendedVendors,
                  ),
                  _VendorRail(
                    title: context.l10n.nearbyRestaurants,
                    icon: Icons.near_me_rounded,
                    vendors: cubit.state.nearbyVendors,
                    showDistance: true,
                  ),
                  _StoresHeader(count: vendors.length),
                  if (vendors.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          EmptyView(
                            // "Nothing nearby" and "your filters are too tight"
                            // need different words, and only the second one has
                            // a fix the customer can act on.
                            message: state.filters.activeCount > 0
                                ? context.l10n.noStoresMatchFilters
                                : context.l10n.noStoresFound,
                            icon: Icons.storefront_outlined,
                          ),
                          if (state.filters.activeCount > 0) ...[
                            const SizedBox(height: AppSpace.lg),
                            OutlinedButton.icon(
                              onPressed: cubit.clearFilters,
                              icon: const Icon(
                                Icons.filter_alt_off_outlined,
                                size: 18,
                              ),
                              label: Text(context.l10n.clearAll),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    for (final vendor in vendors)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: _HomeVendorCard(vendor: vendor),
                      ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ===== Header: deliver-to + notification bell =====
class _Header extends StatelessWidget {
  const _Header({super.key, required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.sm,
        AppSpace.gutter,
        8,
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.push('/addresses'),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: AppColors.warmFill,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                context.l10n.deliverTo,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                  color: AppColors.primary,
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 1),
                          _DeliverToLabel(state: state),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          const MessagesButton(),
          const SizedBox(width: 8),
          const NotificationBell(),
        ],
      ),
    );
  }
}


// ===== Search bar =====
/// Not a field — a button that opens the search page.
///
/// Typing here used to search the home page in place, which put the answers
/// below the banners, the category rail and two promoted rails: the customer
/// typed, saw nothing change, and had to scroll to find out whether it had
/// worked. It also rebuilt the entire page on every keystroke. The bar keeps
/// its exact look so the tap reads as it growing into a screen.
class _SearchBar extends StatelessWidget {
  const _SearchBar({super.key, this.filters});

  /// Null while the page is still on its skeleton — the filter button is inert
  /// then, because there is nothing to filter yet.
  final VendorFilters? filters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 6),
      child: Container(
        height: 52,
        padding: const EdgeInsetsDirectional.only(start: 16, end: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => context.push('/search'),
                child: Row(
                  children: [
                    const Icon(
                      Icons.search_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.l10n.searchStoresDishes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          color: AppColors.textFaint,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _FilterButton(filters: filters),
          ],
        ),
      ),
    );
  }
}

/// Opens the store filters and shows how many are active, so the customer can
/// tell a short list from an empty neighbourhood without opening the sheet.
class _FilterButton extends StatelessWidget {
  const _FilterButton({required this.filters});

  final VendorFilters? filters;

  @override
  Widget build(BuildContext context) {
    final active = filters?.activeCount ?? 0;
    final enabled = filters != null;
    return GestureDetector(
      onTap: enabled
          ? () async {
              final cubit = context.read<HomeCubit>();
              final result = await showVendorFiltersSheet(
                context,
                filters!,
                canSortByDistance: cubit.state.canSortByDistance,
              );
              if (result != null) cubit.applyFilters(result);
            }
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 38,
            width: 38,
            decoration: BoxDecoration(
              color: active > 0 ? AppColors.primary : AppColors.warmFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.tune_rounded,
              size: 20,
              color: active > 0 ? Colors.white : AppColors.primary,
            ),
          ),
          if (active > 0)
            PositionedDirectional(
              top: -4,
              end: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                  border: Border.all(color: AppColors.surface, width: 1.5),
                ),
                child: Text(
                  '$active',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ===== Offers section (data-driven carousel) =====
class _Offers extends StatefulWidget {
  const _Offers({required this.offers});

  final List<BannerItem> offers;

  @override
  State<_Offers> createState() => _OffersState();
}

class _OffersState extends State<_Offers> {
  int _currentPage = 0;
  late final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.offers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
      child: Column(
        children: [
          SizedBox(
            height: 136,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.offers.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _OfferCard(offer: widget.offers[i]),
            ),
          ),
          const SizedBox(height: 10),
          if (widget.offers.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.offers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: i == _currentPage ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _currentPage
                          ? AppColors.primary
                          : AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final BannerItem offer;

  bool get _hasImage => offer.imageUrl.trim().isNotEmpty;

  void _handleTap(BuildContext context) {
    // Counted server-side: these numbers are what the slot is sold on, so a
    // client that could write them directly could inflate them.
    OffersRepository().recordEvent(offer.id, click: true);
    switch (offer.type) {
      case BannerType.vendor:
        if (offer.vendorId?.isNotEmpty ?? false) {
          context.push('/vendors/${offer.vendorId}');
        } else {
          _showEventDialog(context);
        }
      case BannerType.coupon:
        if (offer.code?.isNotEmpty ?? false) {
          _showCouponDialog(context);
        } else {
          _showEventDialog(context);
        }
      case BannerType.event:
        _showEventDialog(context);
    }
  }

  /// Coupon banner: real coupon terms (value, min order, expiry) fetched
  /// live, plus a copy-to-clipboard chip for the code.
  Future<void> _showCouponDialog(BuildContext context) async {
    final code = offer.code!;
    Map<String, dynamic>? coupon;
    try {
      coupon = await supabase
          .from('coupons')
          .select(
            'discount_type, value, min_order_amount, max_discount, expires_at',
          )
          .eq('code', code)
          .maybeSingle();
    } catch (_) {
      // Terms are decorative here; the dialog still shows the code.
    }
    if (!context.mounted) return;

    final lines = <String>[];
    if (coupon != null) {
      final isPercent = coupon['discount_type'] == 'percentage';
      final value = ((coupon['value'] as num?) ?? 0).toDouble();
      final minOrder = ((coupon['min_order_amount'] as num?) ?? 0).toDouble();
      final maxDiscount = (coupon['max_discount'] as num?)?.toDouble();
      lines.add(
        isPercent
            ? '${value.toStringAsFixed(0)}% ${context.l10n.off}'
            : '${formatMoney(value)} ${context.l10n.off}',
      );
      if (maxDiscount != null) {
        lines.add('${context.l10n.max} ${formatMoney(maxDiscount)}');
      }
      if (minOrder > 0) {
        lines.add('${context.l10n.min} ${formatMoney(minOrder)}');
      }
    }
    if (offer.subtitle?.isNotEmpty ?? false) lines.add(offer.subtitle!);

    showInfoDialog(
      context: context,
      title: offer.title ?? context.l10n.offerDetails,
      icon: Icons.local_offer_rounded,
      // The code IS the payload of this dialog, so it is the artwork — and it
      // copies on tap, which is what the copy glyph has always promised.
      artwork: _CouponArtwork(code: code, terms: lines),
      dismissLabel: context.l10n.back,
    );
  }

  /// Event / announcement banner: artwork plus the promo copy.
  void _showEventDialog(BuildContext context) {
    showInfoDialog(
      context: context,
      title: offer.title ?? context.l10n.offerDetails,
      icon: _hasImage ? null : Icons.campaign_rounded,
      artwork: _hasImage
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: AppNetworkImage(
                url: offer.imageUrl,
                height: 120,
                width: double.infinity,
              ),
            )
          : null,
      message: (offer.subtitle?.isNotEmpty ?? false) ? offer.subtitle : null,
      dismissLabel: context.l10n.back,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _handleTap(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
          height: 136,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: AppShadows.card,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primaryLight, AppColors.primaryDark],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The admin's artwork is always the backdrop when present.
              if (_hasImage)
                AppNetworkImage(
                  url: offer.imageUrl,
                  height: 136,
                  width: double.infinity,
                )
              else
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              // Readability scrim + promo copy over the image.
              if (offer.title?.isNotEmpty ?? false)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                  decoration: _hasImage
                      ? const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xDD1E1519), Color(0x331E1519)],
                          ),
                        )
                      : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        offer.title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.display(
                          22,
                          color: Colors.white,
                        ).copyWith(height: 1.05),
                      ),
                      if (offer.subtitle?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(
                          offer.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                      if (offer.type == BannerType.coupon &&
                          (offer.code?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: AppShadows.card,
                          ),
                          child: Text(
                            '${context.l10n.promoCodeLabel} · ${offer.code!}',
                            style: AppType.mono(
                              12,
                              color: AppColors.primaryDark,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Category chips =====
/// The kinds of shop the marketplace sells — Food, Groceries, Pharmacies,
/// Stores — as a horizontal strip of artwork.
///
/// Tapping one opens its own page rather than filtering this one in place. The
/// chips it replaces could only ever narrow the single list underneath them,
/// which is the wrong shape once "Groceries" and "Food" are different shops
/// with different sub-categories: a customer picking Food wants the cuisines
/// inside it, not a shorter version of the page they were already on.
class _CategoryRail extends StatelessWidget {
  const _CategoryRail({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final categories = state.topCategories;
    if (categories.isEmpty) return const SizedBox.shrink();
    final language = Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 10),
          child: Text(context.l10n.shopByCategory, style: AppType.heading(17)),
        ),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) =>
                _CategoryTile(category: categories[i], language: language),
          ),
        ),
      ],
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.language});

  final VendorCategory category;
  final String language;

  @override
  Widget build(BuildContext context) {
    final image = category.imageUrl;
    return SizedBox(
      width: 78,
      // GestureDetector, not InkWell: a rectangular ripple around rounded
      // artwork read as a glitch, and the page transition is the feedback.
      child: GestureDetector(
        onTap: () => context.push('/categories/${category.id}'),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: image != null && image.isNotEmpty
                  ? AppNetworkImage(url: image, height: 72, width: 78)
                  : Container(
                      width: 78,
                      height: 72,
                      alignment: Alignment.center,
                      color: AppColors.warmFill,
                      child: Text(
                        emojiFor(category.name).trim(),
                        style: const TextStyle(fontSize: 30),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            // Flexible so the label can never push this Column past the rail's
            // fixed height: its line box depends on the font, the locale and
            // the text scale, and a point over budget would overflow.
            Flexible(
              child: Text(
                category.label(language),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Stores section header =====
class _StoresHeader extends StatelessWidget {
  const _StoresHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    // Sorting now lives in the filter sheet next to the search field, so the
    // header carries the result count instead — it is the one thing that
    // changes as filters are applied.
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(context.l10n.storesNearYou, style: AppType.display(19)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.neutralFill,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              context.l10n.storesCount(count),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Vendor card =====
/// A shortcut section above the full store list.
///
/// Used for both the admin's promoted picks and the nearest open stores. A
/// separate section rather than pinned rows in the main list: neither promotion
/// nor proximity should quietly reorder a list the customer believes is ranked
/// on merit. Renders nothing when its section is empty, so an ungeofenced
/// platform or one with no promoted stores simply shows the plain list.
class _VendorRail extends StatelessWidget {
  const _VendorRail({
    required this.title,
    required this.icon,
    required this.vendors,
    this.showDistance = false,
  });

  final String title;
  final IconData icon;
  final List<Vendor> vendors;

  /// The nearby rail leads with distance; the recommended one has no reason to.
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    if (vendors.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
          child: Row(
            children: [
              Icon(icon, size: 19, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(17),
                ),
              ),
              if (showDistance)
                Builder(
                  builder: (context) {
                    final km = context.read<HomeCubit>().state.distanceToVendor(
                      vendors.first,
                    );
                    if (km == null) return const SizedBox.shrink();
                    return Text(
                      '${km < 10 ? km.toStringAsFixed(1) : km.round()} '
                      '${context.l10n.kmUnit}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMuted,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        for (final vendor in vendors)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: _HomeVendorCard(vendor: vendor),
          ),
      ],
    );
  }
}

/// The shared store row, wired to the home page's own favourites state.
///
/// The card itself takes the heart as a value and a callback so it can be
/// reused by the category pages, which own that state through a different
/// cubit; this wrapper is the only place that knows about [HomeCubit].
class _HomeVendorCard extends StatelessWidget {
  const _HomeVendorCard({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    final isFavorite = context.select<HomeCubit, bool>(
      (c) => c.state.favoriteVendorIds.contains(vendor.id),
    );
    return VendorCard(
      vendor: vendor,
      isFavorite: isFavorite,
      onToggleFavorite: () => cubit.toggleFavorite(vendor.id),
      // Only real once the customer has a pinned address and the store has
      // coordinates; null otherwise, and the card leaves the distance out.
      distanceKm: cubit.state.distanceToVendor(vendor),
    );
  }
}

/// The real address this order would go to.
///
/// Until the fetch lands this is a skeleton line, not a plausible-looking
/// placeholder: "Home · 12 Tahrir St" was a lie the moment it shipped, and a
/// user who trusts it sends their food to a street they have never lived on.
class _DeliverToLabel extends StatelessWidget {
  const _DeliverToLabel({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    if (!state.addressLoaded) {
      return const Skeleton.line(widthFactor: 0.55, height: 15);
    }
    final address = state.deliverToAddress;
    if (address == null) {
      // No address yet: say so, and make the whole header row the way to fix it
      // (the enclosing InkWell already routes to /addresses).
      return Text(
        context.l10n.addADeliveryAddress,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppType.heading(15, color: AppColors.primaryDark),
      );
    }
    return Text(
      '${address.label} · ${address.summary}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.heading(15),
    );
  }
}

/// Tappable coupon code — the artwork of the coupon info dialog.
class _CouponArtwork extends StatelessWidget {
  const _CouponArtwork({required this.code, required this.terms});

  final String code;
  final List<String> terms;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.amberFill,
          borderRadius: BorderRadius.circular(AppRadii.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final copied = context.l10n.codeCopied;
              await Clipboard.setData(ClipboardData(text: code));
              messenger.showSnackBar(SnackBar(content: Text(copied)));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md + 2,
                vertical: AppSpace.md - 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(code, style: AppType.mono(16, color: AppColors.ink)),
                  const Icon(
                    Icons.copy_rounded,
                    size: 18,
                    color: AppColors.amberInk,
                  ),
                ],
              ),
            ),
          ),
        ),
        for (final line in terms) ...[
          const SizedBox(height: AppSpace.sm),
          Text(
            line,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}

/// Home while the store list loads.
///
/// The header and the search field need no data, so they stay live and
/// interactive — a user who opened the app to search should not have to wait for
/// banners to land first.
class _HomeSkeleton extends StatelessWidget {
  const _HomeSkeleton({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
        children: [
          _Header(key: const ValueKey('home_header'), state: state),
          const _SearchBar(key: ValueKey('home_search_bar')),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 10, 22, 6),
            child: Skeleton.box(height: 136, radius: 22),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.sm,
              AppSpace.gutter,
              AppSpace.xs,
            ),
            child: SizedBox(
              height: 38,
              child: Row(
                children: [
                  Skeleton(width: 64, height: 38, radius: AppRadii.md),
                  SizedBox(width: 9),
                  Skeleton(width: 104, height: 38, radius: AppRadii.md),
                  SizedBox(width: 9),
                  Skeleton(width: 88, height: 38, radius: AppRadii.md),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md + 2,
              AppSpace.gutter,
              AppSpace.sm,
            ),
            child: Skeleton.line(widthFactor: 0.45, height: 20),
          ),
          SkeletonList(
            scrollable: false,
            itemCount: 3,
            separator: const SizedBox(height: 14),
            itemBuilder: (_) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: 22),
              child: _VendorCardSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors [VendorCard]: 92px thumbnail, title line, meta line.
class _VendorCardSkeleton extends StatelessWidget {
  const _VendorCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
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
                SizedBox(height: 8),
                Skeleton.line(widthFactor: 0.35, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
