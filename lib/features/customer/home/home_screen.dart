import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/banner_item.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/address_repository.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/ui_kit.dart';
import 'home_cubit.dart';
import 'vendor_filters_sheet.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          HomeCubit(CatalogRepository(), AddressRepository(), FavoritesRepository()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

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
                  message: context.l10n.couldNotLoadStores, onRetry: cubit.load);
            }
            final vendors = state.visibleVendors;
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: cubit.load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _Header(state: state),
                  _SearchBar(
                      onSubmit: cubit.setSearch, filters: state.filters),
                  _Offers(offers: state.banners),
                  _CategoryChips(state: state),
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
                              icon: const Icon(Icons.filter_alt_off_outlined,
                                  size: 18),
                              label: Text(context.l10n.clearAll),
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    for (final vendor in vendors)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                        child: _VendorCard(vendor: vendor),
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
  const _Header({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.sm, AppSpace.gutter, 6),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => context.push('/addresses'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(context.l10n.deliverTo,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: AppColors.primary)),
                      Icon(Icons.keyboard_arrow_down,
                          size: 16, color: AppColors.primary),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 18, color: AppColors.ink),
                      const SizedBox(width: 6),
                      Expanded(child: _DeliverToLabel(state: state)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          _BellButton(),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/notifications'),
      borderRadius: BorderRadius.circular(21),
      child: Stack(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.notifications_none_rounded,
                size: 20, color: AppColors.ink),
          ),
          PositionedDirectional(
            top: 9,
            end: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===== Search bar =====
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onSubmit, this.filters});

  final ValueChanged<String> onSubmit;

  /// Null while the page is still on its skeleton — the button is inert then,
  /// because there is nothing to filter yet.
  final VendorFilters? filters;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 4),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borderSoft),
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 22, color: AppColors.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                onSubmitted: onSubmit,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 15, color: AppColors.ink, fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: context.l10n.searchStoresDishes,
                  hintStyle:
                      TextStyle(fontSize: 15, color: AppColors.textFaint),
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
              final result = await showVendorFiltersSheet(context, filters!);
              if (result != null) cubit.applyFilters(result);
            }
          : null,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: active > 0
                  ? AppColors.primary
                  : AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadii.xs + 2),
            ),
            child: Icon(Icons.tune,
                size: 20,
                color: active > 0 ? Colors.white : AppColors.primary),
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
                child: Text('$active',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
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
    if (widget.offers.isEmpty) return const _PromoBanner();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
      child: Column(
        children: [
          SizedBox(
            height: 128,
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.offers.length,
              onPageChanged: (i) => setState(() => _currentPage = i),
              itemBuilder: (_, i) => _OfferCard(offer: widget.offers[i]),
            ),
          ),
          const SizedBox(height: 9),
          if (widget.offers.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.offers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    width: i == _currentPage ? 18 : 5,
                    height: 5,
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
          .select('discount_type, value, min_order_amount, max_discount, expires_at')
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
      lines.add(isPercent
          ? '${value.toStringAsFixed(0)}% ${context.l10n.off}'
          : '${formatMoney(value)} ${context.l10n.off}');
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
                  url: offer.imageUrl, height: 120, width: double.infinity),
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
          height: 128,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
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
                    height: 128,
                    width: double.infinity)
              else
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              // Readability scrim + promo copy over the image.
              if (offer.title?.isNotEmpty ?? false)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                  decoration: _hasImage
                      ? const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xCC1A1714), Color(0x331A1714)],
                          ),
                        )
                      : null,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.title!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.display(22, color: Colors.white)
                              .copyWith(height: 1.05)),
                      if (offer.subtitle?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 4),
                        Text(offer.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ],
                      if (offer.type == BannerType.coupon &&
                          (offer.code?.isNotEmpty ?? false)) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text('CODE · ${offer.code!}',
                              style: AppType.mono(12,
                                  color: AppColors.primaryDark,
                                  weight: FontWeight.w700)),
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

// ===== Promo banner (40% off) =====
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showInfoDialog(
        context: context,
        title: context.l10n.s40OffYournfirstOrder,
        message: context.l10n.useCodeEaty40ToGetThisOffer,
        icon: Icons.local_offer_rounded,
        dismissLabel: context.l10n.back,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
        child: Column(
        children: [
          Container(
            height: 128,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppShadows.card,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primaryLight, AppColors.primaryDark],
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -30,
                  top: -30,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.l10n.s40OffYournfirstOrder,
                        style: AppType.display(23, color: Colors.white)
                            .copyWith(letterSpacing: -0.24, height: 1.05)),
                    const SizedBox(height: 8),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(context.l10n.codeEaty40,
                          style: AppType.mono(12,
                              color: AppColors.primaryDark,
                              weight: FontWeight.w700)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _dot(true),
              const SizedBox(width: 5),
              _dot(false),
              const SizedBox(width: 5),
              _dot(false),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _dot(bool active) => Container(
        width: active ? 18 : 5,
        height: 5,
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.borderStrong,
          borderRadius: BorderRadius.circular(3),
        ),
      );
}

// ===== Category chips =====
class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.state});

  final HomeState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HomeCubit>();
    return AppFilterBar(
      children: [
        AppFilterChip(
          label: context.l10n.all,
          selected: state.selectedCategoryId == null,
          onTap: () => cubit.selectCategory(null),
        ),
        for (final category in state.categories)
          AppFilterChip(
            label: '${_emojiFor(category.name)}${category.name}',
            selected: state.selectedCategoryId == category.id,
            onTap: () => cubit.selectCategory(
                state.selectedCategoryId == category.id ? null : category.id),
          ),
      ],
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
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.md + 2, AppSpace.gutter, AppSpace.sm),
      child: Row(
        children: [
          Expanded(
            child:
                Text(context.l10n.storesNearYou, style: AppType.display(19)),
          ),
          Text(context.l10n.storesCount(count),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted)),
        ],
      ),
    );
  }
}

// ===== Vendor card =====
class _VendorCard extends StatelessWidget {
  const _VendorCard({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => context.push('/vendors/${vendor.id}'),
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
              Stack(
                children: [
                  AppNetworkImage(
                      url: vendor.coverUrl,
                      height: 118,
                      width: double.infinity),
                  PositionedDirectional(
                    top: 11,
                    start: 11,
                    child: !vendor.isOpen
                          ? SoftBadge(
                              label: context.l10n.closed1,
                              fill: AppColors.neutralFill,
                              ink: AppColors.textMuted)
                          : vendor.isBusy
                              ? SoftBadge(
                                  label: context.l10n.busyStore,
                                  fill: AppColors.amberFill,
                                  ink: AppColors.amberInk)
                              : SoftBadge(
                                  label: context.l10n.openNow,
                                  fill: AppColors.successFill,
                                  ink: AppColors.successInk),
                  ),
                  PositionedDirectional(
                    top: 11,
                    end: 11,
                    child: _FavoriteButton(vendorId: vendor.id),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    _LogoTile(vendor: vendor),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(vendor.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink)),
                          const SizedBox(height: 2),
                          Text(
                            '${vendor.totalPrepMinutes}–${vendor.totalPrepMinutes + 10} min'
                            ' · ${formatMoney(vendor.deliveryFee)} delivery',
                            style: const TextStyle(
                                fontSize: 12.5, color: AppColors.textMuted),
                          ),
                        ],
                      ),
                    ),
                    RatingChip(
                        rating: vendor.ratingAvg, count: vendor.ratingCount),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}

class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context) {
    final url = vendor.logoUrl;
    if (url != null && url.isNotEmpty) {
      return AppNetworkImage(
          url: url, height: 46, width: 46, borderRadius: BorderRadius.circular(12));
    }
    return Container(
      width: 46,
      height: 46,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.warmFill,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(_emojiFor(vendor.name).trim(),
          style: const TextStyle(fontSize: 22)),
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
        style: AppType.heading(16, color: AppColors.primaryDark),
      );
    }
    return Text(
      '${address.label} · ${address.summary}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.heading(16),
    );
  }
}

/// Favourite toggle on a store cover.
///
/// Wrapped in its own `Material` + `InkWell` so the tap lands here rather than
/// falling through to the card and opening the store — which is what the
/// gesture-less version used to do.
class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({required this.vendorId});

  final String vendorId;

  @override
  Widget build(BuildContext context) {
    final isFavorite = context.select<HomeCubit, bool>(
        (cubit) => cubit.state.favoriteVendorIds.contains(vendorId));
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => context.read<HomeCubit>().toggleFavorite(vendorId),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            size: 18,
            color: AppColors.primary,
          ),
        ),
      ),
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
                  horizontal: AppSpace.md + 2, vertical: AppSpace.md - 2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(code, style: AppType.mono(16, color: AppColors.ink)),
                  const Icon(Icons.copy_rounded,
                      size: 18, color: AppColors.amberInk),
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
                fontSize: 13, color: AppColors.textSecondary),
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
          _Header(state: state),
          _SearchBar(onSubmit: context.read<HomeCubit>().setSearch),
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpace.gutter, 10, AppSpace.gutter, AppSpace.xs),
            child: Skeleton.box(height: 128),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xs),
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
                AppSpace.gutter, AppSpace.md + 2, AppSpace.gutter, AppSpace.sm),
            child: Skeleton.line(widthFactor: 0.45, height: 20),
          ),
          SkeletonList(
            scrollable: false,
            itemCount: 3,
            separator: const SizedBox(height: AppSpace.md),
            itemBuilder: (_) => const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpace.gutter),
              child: _VendorCardSkeleton(),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mirrors `_VendorCard`: 118px cover, 46px logo tile, two text lines, chip.
class _VendorCardSkeleton extends StatelessWidget {
  const _VendorCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton.box(height: 118, radius: AppRadii.xl),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md + 2, vertical: AppSpace.md),
            child: Row(
              children: [
                const Skeleton(width: 46, height: 46, radius: AppRadii.md),
                const SizedBox(width: AppSpace.md),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton.line(widthFactor: 0.55, height: 15),
                      SizedBox(height: 6),
                      Skeleton.line(widthFactor: 0.8, height: 11),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Skeleton(
                    width: 52, height: 26, radius: AppRadii.pill),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Maps a cuisine/category/vendor name to a leading emoji (with trailing space).
String _emojiFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('burger')) return '🍔 ';
  if (n.contains('pizza')) return '🍕 ';
  if (n.contains('sushi') || n.contains('japan')) return '🍣 ';
  if (n.contains('salad') || n.contains('green') || n.contains('healthy')) {
    return '🥗 ';
  }
  if (n.contains('coffee') || n.contains('cafe')) return '☕ ';
  if (n.contains('dessert') || n.contains('sweet') || n.contains('bakery')) {
    return '🍰 ';
  }
  if (n.contains('chicken')) return '🍗 ';
  if (n.contains('drink') || n.contains('juice')) return '🥤 ';
  return '🍽️ ';
}
