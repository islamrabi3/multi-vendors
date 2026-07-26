import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/banner_item.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'home_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => HomeCubit(CatalogRepository()),
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
            if (state.loading) return const LoadingView();
            if (state.error != null && state.vendors.isEmpty) {
              return ErrorView(
                  message: context.l10n.couldNotLoadStores, onRetry: cubit.load);
            }
            return RefreshIndicator(
              color: AppColors.primary,
              onRefresh: cubit.load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  const _Header(),
                  _SearchBar(onSubmit: cubit.setSearch),
                  _Offers(offers: state.banners),
                  _CategoryChips(state: state),
                  const _StoresHeader(),
                  if (state.vendors.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(32),
                      child: EmptyView(
                          message: context.l10n.noStoresFound,
                          icon: Icons.storefront_outlined),
                    )
                  else
                    for (final vendor in state.vendors)
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
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 6),
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
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 18, color: AppColors.ink),
                      const SizedBox(width: 6),
                      Text(context.l10n.home12TahrirSt,
                          style: AppType.heading(16)),
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
    return Stack(
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
        Positioned(
          top: 9,
          right: 10,
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
    );
  }
}

// ===== Search bar =====
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onSubmit});

  final ValueChanged<String> onSubmit;

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
            Container(
              height: 36,
              width: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.tune, size: 20, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

// ===== Offers section (data-driven carousel) =====
class _Offers extends StatelessWidget {
  const _Offers({required this.offers});

  final List<BannerItem> offers;

  @override
  Widget build(BuildContext context) {
    if (offers.isEmpty) return const _PromoBanner();
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 4),
      child: Column(
        children: [
          SizedBox(
            height: 128,
            child: PageView.builder(
              itemCount: offers.length,
              itemBuilder: (_, i) => _OfferCard(offer: offers[i]),
            ),
          ),
          const SizedBox(height: 9),
          if (offers.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < offers.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Container(
                    width: i == 0 ? 18 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: i == 0
                          ? AppColors.primary
                          : const Color(0xFFE4DDD4),
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

  @override
  Widget build(BuildContext context) {
    void handleTap() {
      if (offer.vendorId != null && offer.vendorId!.isNotEmpty) {
        context.push('/vendors/${offer.vendorId}');
      } else if (offer.code != null && offer.code!.isNotEmpty) {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(offer.title ?? 'Offer Details'),
            content: Text('Use code ${offer.code} to get this offer. ${offer.subtitle ?? ''}'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(offer.title ?? 'Promo'),
            content: Text(offer.subtitle ?? 'Check out this special offer!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }

    // Image-only offer (no promo copy): show the artwork.
    if (offer.title?.isNotEmpty != true) {
      return GestureDetector(
        onTap: handleTap,
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AppNetworkImage(
              url: offer.imageUrl, height: 128, width: double.infinity),
        ),
      ),
    );
  }
  return GestureDetector(
      onTap: handleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Container(
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
                if (offer.code?.isNotEmpty ?? false) ...[
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
      onTap: () {
        showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(context.l10n.s40OffYournfirstOrder),
            content: Text(context.l10n.useCodeEaty40ToGetThisOffer),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      },
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
          color: active ? AppColors.primary : const Color(0xFFE4DDD4),
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
    return SizedBox(
      height: 54,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
        children: [
          _Chip(
            label: 'All',
            selected: state.selectedCategoryId == null,
            onTap: () => cubit.selectCategory(null),
          ),
          for (final category in state.categories)
            _Chip(
              label: '${_emojiFor(category.name)}${category.name}',
              selected: state.selectedCategoryId == category.id,
              onTap: () => cubit.selectCategory(
                  state.selectedCategoryId == category.id ? null : category.id),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 15),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: selected ? null : Border.all(color: AppColors.borderSoft),
            boxShadow: selected ? [
              BoxShadow(
                color: AppColors.ink.withValues(alpha: 0.2),
                blurRadius: 8,
                offset: const Offset(0, 3),
              )
            ] : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? Colors.white : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Stores section header =====
class _StoresHeader extends StatelessWidget {
  const _StoresHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(context.l10n.storesNearYou, style: AppType.display(19)),
          Row(
            children: [
              Text(context.l10n.sort,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
              Icon(Icons.keyboard_arrow_down,
                  size: 16, color: AppColors.primary),
            ],
          ),
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
                  Positioned(
                    top: 11,
                    left: 11,
                    child: vendor.isOpen
                        ? SoftBadge(
                            label: context.l10n.openNow,
                            fill: AppColors.successFill,
                            ink: AppColors.successInk)
                        : SoftBadge(
                            label: context.l10n.closed1,
                            fill: Color(0xFFF1ECE6),
                            ink: AppColors.textMuted),
                  ),
                  Positioned(
                    top: 11,
                    right: 11,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.95),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.favorite_border,
                          size: 18, color: AppColors.primary),
                    ),
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
                            '${vendor.avgPrepMinutes}–${vendor.avgPrepMinutes + 10} min'
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
