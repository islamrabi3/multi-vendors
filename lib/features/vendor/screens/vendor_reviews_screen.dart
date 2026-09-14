import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tokens.dart';
import '../../../core/models/review.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/reviews.dart';
import '../../auth/auth_cubit.dart';

/// What customers said about this store.
///
/// The summary answers "how are we doing"; the filters answer "what went
/// wrong" — a store owner opens this after a bad night looking for the one
/// and two star reviews, not scrolling past the fives to find them.
class VendorReviewsScreen extends StatefulWidget {
  const VendorReviewsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<VendorReviewsScreen> createState() => _VendorReviewsScreenState();
}

enum _ReviewFilter {
  all,
  positive,
  critical,
  withComment,
  five,
  four,
  three,
  two,
  one,
}

class _VendorReviewsScreenState extends State<VendorReviewsScreen> {
  static const _pageSize = 30;

  final _repo = ReviewRepository();
  final _reviews = <Review>[];

  RatingBreakdown _breakdown = RatingBreakdown.empty;
  String? _vendorId;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  _ReviewFilter _filter = _ReviewFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vendorId = context.read<AuthCubit>().state.vendor?.id;
      _load();
    });
  }

  Future<void> _load() async {
    final vendorId = _vendorId;
    if (vendorId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = _reviews.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchMyVendorReviews(vendorId, limit: _pageSize),
        _repo.fetchBreakdown(vendorId),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews
          ..clear()
          ..addAll(results[0] as List<Review>);
        _breakdown = results[1] as RatingBreakdown;
        _hasMore = _reviews.length == _pageSize;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final vendorId = _vendorId;
    if (vendorId == null || _loadingMore || !_hasMore || _loading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.fetchMyVendorReviews(
        vendorId,
        limit: _pageSize,
        offset: _reviews.length,
      );
      if (!mounted) return;
      setState(() {
        _reviews.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showFailure(context, error, onRetry: _loadMore);
    }
  }

  bool _matches(Review r) => switch (_filter) {
    _ReviewFilter.all => true,
    _ReviewFilter.positive => r.rating >= 4,
    _ReviewFilter.critical => r.rating <= 2,
    _ReviewFilter.withComment => r.hasComment,
    _ReviewFilter.five => r.rating == 5,
    _ReviewFilter.four => r.rating == 4,
    _ReviewFilter.three => r.rating == 3,
    _ReviewFilter.two => r.rating == 2,
    _ReviewFilter.one => r.rating == 1,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget body;
    if (_loading) {
      body = const LoadingView();
    } else if (_error != null && _reviews.isEmpty) {
      body = FailureView(error: _error!, onRetry: _load);
    } else {
      body = LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          final visible = _reviews.where(_matches).toList();
          // A narrow filter over one page can come up short while older
          // pages still hold matches; fetch on until it fills or runs out.
          if (_filter != _ReviewFilter.all &&
              visible.length < 10 &&
              _hasMore &&
              !_loadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
          }
          final summary = _SummaryPanel(
            breakdown: _breakdown,
            reviews: _reviews,
          );
          final filters = _FilterBar(
            selected: _filter,
            breakdown: _breakdown,
            onSelected: (f) => setState(() => _filter = f),
          );
          final list = <Widget>[
            if (_breakdown.total == 0)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyView(
                  message: l10n.noReviewsYet,
                  icon: Icons.reviews_outlined,
                ),
              )
            else if (visible.isEmpty && !_hasMore)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: EmptyView(
                  message: l10n.noReviewsForFilter,
                  icon: Icons.filter_alt_off_outlined,
                ),
              )
            else
              for (final review in visible) _ReviewCard(review: review),
            PagingFooter(loading: _loadingMore, hasMore: _hasMore),
          ];

          final scroll = NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.axis == Axis.vertical &&
                  n.metrics.maxScrollExtent - n.metrics.pixels < 400) {
                _loadMore();
              }
              return false;
            },
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: wide
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 360, child: summary),
                                const SizedBox(width: 24),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      filters,
                                      const SizedBox(height: AppSpace.md),
                                      ...list,
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        AppSpace.gutter,
                        AppSpace.md,
                        AppSpace.gutter,
                        AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        summary,
                        const SizedBox(height: AppSpace.lg),
                        filters,
                        const SizedBox(height: AppSpace.md),
                        ...list,
                      ],
                    ),
            ),
          );
          return scroll;
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: widget.embedded ? null : AppBar(title: Text(l10n.reviewsInbox)),
      body: body,
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({required this.breakdown, required this.reviews});

  final RatingBreakdown breakdown;
  final List<Review> reviews;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final total = breakdown.total;
    final positive = total == 0
        ? 0
        : (((breakdown.counts[5] ?? 0) + (breakdown.counts[4] ?? 0)) *
                  100 /
                  total)
              .round();
    final critical = (breakdown.counts[1] ?? 0) + (breakdown.counts[2] ?? 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: RatingSummary(breakdown: breakdown),
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: Icons.sentiment_satisfied_alt_rounded,
                tone: AppColors.successInk,
                value: '$positive%',
                label: l10n.positiveReviewsShare,
              ),
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: _StatTile(
                icon: Icons.sentiment_dissatisfied_rounded,
                tone: AppColors.dangerInk,
                value: '$critical',
                label: l10n.criticalReviews,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.tone,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color tone;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: tone, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: AppType.heading(17)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.selected,
    required this.breakdown,
    required this.onSelected,
  });

  final _ReviewFilter selected;
  final RatingBreakdown breakdown;
  final ValueChanged<_ReviewFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final chips = <(_ReviewFilter, String)>[
      (_ReviewFilter.all, l10n.all),
      (_ReviewFilter.critical, l10n.criticalReviews),
      (_ReviewFilter.positive, l10n.positiveReviews),
      (_ReviewFilter.withComment, l10n.withComments),
      (_ReviewFilter.five, '5 ★'),
      (_ReviewFilter.four, '4 ★'),
      (_ReviewFilter.three, '3 ★'),
      (_ReviewFilter.two, '2 ★'),
      (_ReviewFilter.one, '1 ★'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (filter, label) = chips[i];
          final active = filter == selected;
          return ChoiceChip(
            label: Text(label),
            selected: active,
            onSelected: (_) => onSelected(filter),
          );
        },
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});

  final Review review;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final name = review.customerName ?? l10n.anonymous;
    final tone = review.rating >= 4
        ? AppColors.successInk
        : review.rating == 3
        ? AppColors.amberInk
        : AppColors.dangerInk;
    final language = Localizations.localeOf(context).languageCode;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: tone.withValues(alpha: 0.12),
                child: Text(
                  name.trim().isEmpty ? '?' : name.trim().characters.first,
                  style: TextStyle(color: tone, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      DateFormat.yMMMd(language).format(review.createdAt),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 15, color: tone),
                    const SizedBox(width: 3),
                    Text(
                      '${review.rating}',
                      style: TextStyle(
                        color: tone,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.hasComment) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              review.comment!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.ratingWithoutComment,
              style: const TextStyle(
                fontSize: 12.5,
                fontStyle: FontStyle.italic,
                color: AppColors.textFaint,
              ),
            ),
          ],
          if (review.orderId != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    context.push('/vendor-app/orders/${review.orderId}'),
                icon: const Icon(Icons.receipt_long_outlined, size: 16),
                label: Text(l10n.viewOrder),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
