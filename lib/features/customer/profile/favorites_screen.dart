import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/favorites_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final _repository = FavoritesRepository();
  List<Vendor>? _vendors;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  void _loadFavorites() {
    _repository.fetchFavoriteVendors().then((vendors) {
      if (mounted) setState(() => _vendors = vendors);
    }).catchError((_) {
      if (mounted) setState(() => _vendors = []);
    });
  }

  Future<void> _unfavorite(Vendor vendor) async {
    if (_busy) return;
    setState(() => _busy = true);
    final originalList = List<Vendor>.from(_vendors ?? []);
    setState(() {
      _vendors?.removeWhere((v) => v.id == vendor.id);
    });
    try {
      await _repository.setFavorite(vendor.id, false);
      if (mounted) {
        showSnack(context, 'Removed ${vendor.name} from favorites');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _vendors = originalList);
        showSnack(context, 'Failed to update favorite status', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendors = _vendors;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        elevation: 0,
        centerTitle: true,
        title: Text(
          context.l10n.favorites,
          style: AppType.heading(18, color: AppColors.ink),
        ),
        leading: IconButton(
          // arrow_back mirrors itself in RTL; the chevron variants do not.
          icon: const Icon(Icons.arrow_back, color: AppColors.ink, size: 22),
          onPressed: () => context.pop(),
        ),
      ),
      body: vendors == null
          ? const _FavoritesSkeleton()
          : vendors.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite_outline_rounded,
                          size: 64,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        context.l10n.noFavoritesYet,
                        style: AppType.heading(18, color: AppColors.ink),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'Explore shops and save your favorite places to find them quickly here!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Container(
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: FilledButton(
                          onPressed: () => context.go('/'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadii.lg),
                            ),
                          ),
                          child: const Text(
                            'Explore Restaurants',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  itemCount: vendors.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final vendor = vendors[index];
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
                                      height: 124,
                                      width: double.infinity,
                                    ),
                                    PositionedDirectional(
                                      top: 12,
                                      start: 12,
                                      child: vendor.isOpen
                                          ? SoftBadge(
                                              label: context.l10n.openNow,
                                              fill: AppColors.successFill,
                                              ink: AppColors.successInk,
                                            )
                                          : SoftBadge(
                                              label: context.l10n.closed1,
                                              fill: AppColors.neutralFill,
                                              ink: AppColors.textMuted,
                                            ),
                                    ),
                                    PositionedDirectional(
                                      top: 12,
                                      end: 12,
                                      child: GestureDetector(
                                        onTap: () => _unfavorite(vendor),
                                        child: Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.95),
                                            shape: BoxShape.circle,
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black12,
                                                blurRadius: 8,
                                                offset: Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.favorite_rounded,
                                            size: 19,
                                            color: AppColors.dangerInk,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      AppNetworkImage(
                                        url: vendor.logoUrl,
                                        height: 46,
                                        width: 46,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              vendor.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${vendor.avgPrepMinutes}–${vendor.avgPrepMinutes + 10} min'
                                              ' · ${formatMoney(vendor.deliveryFee)} delivery',
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      RatingChip(
                                        rating: vendor.ratingAvg,
                                        count: vendor.ratingCount,
                                      ),
                                    ],
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

/// Favourites while they load. Same 20px gutters and 16px separation as the
/// real list, and the same 124px cover, so nothing jumps when data lands.
class _FavoritesSkeleton extends StatelessWidget {
  const _FavoritesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: SkeletonList(
        itemCount: 4,
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, AppSpace.md, AppSpace.xl, 32),
        separator: const SizedBox(height: AppSpace.lg),
        itemBuilder: (_) => DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: AppColors.borderSoft),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Skeleton.box(height: 124, radius: AppRadii.xl),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md + 2, vertical: AppSpace.md),
                child: Row(
                  children: const [
                    Skeleton(width: 46, height: 46, radius: AppRadii.md),
                    SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton.line(widthFactor: 0.55, height: 15),
                          SizedBox(height: 6),
                          Skeleton.line(widthFactor: 0.8, height: 11),
                        ],
                      ),
                    ),
                    SizedBox(width: AppSpace.sm),
                    Skeleton(width: 52, height: 26, shape: SkeletonShape.pill),
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
