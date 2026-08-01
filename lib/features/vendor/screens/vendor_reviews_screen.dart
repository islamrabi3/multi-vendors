import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/review.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/reviews.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../auth/auth_cubit.dart';

/// What customers said about this store.
///
/// Ratings already moved the store's average, but the store itself could not
/// read a single one of them — so a run of one-star reviews was invisible to
/// the only person who could act on it.
class VendorReviewsScreen extends StatefulWidget {
  const VendorReviewsScreen({super.key});

  @override
  State<VendorReviewsScreen> createState() => _VendorReviewsScreenState();
}

class _VendorReviewsScreenState extends State<VendorReviewsScreen> {
  static const _pageSize = 30;

  final _repo = ReviewRepository();
  final _scroll = ScrollController();
  final _reviews = <Review>[];

  RatingBreakdown _breakdown = RatingBreakdown.empty;
  String? _vendorId;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vendorId = context.read<AuthCubit>().state.vendor?.id;
      _load();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loadingMore || _loading) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load() async {
    final vendorId = _vendorId;
    if (vendorId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
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
    if (vendorId == null) return;
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.reviewsInbox)),
      body: _loading
          ? const LoadingView()
          : _error != null
              ? FailureView(error: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(AppSpace.lg),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadii.xl),
                        ),
                        child: RatingSummary(breakdown: _breakdown),
                      ),
                      const SizedBox(height: AppSpace.xl),
                      if (_reviews.isEmpty)
                        EmptyView(
                          message: l10n.noReviewsYet,
                          icon: Icons.reviews_outlined,
                        )
                      else
                        for (final review in _reviews)
                          ReviewTile(review: review),
                      if (_loadingMore)
                        const Padding(
                          padding: EdgeInsets.all(AppSpace.lg),
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }
}
