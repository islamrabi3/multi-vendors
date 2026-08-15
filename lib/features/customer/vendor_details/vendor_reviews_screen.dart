import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/review.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/reviews.dart';
import '../../../core/utils/l10n_extension.dart';

/// Every review of one store, newest first.
///
/// Reached from the store page, which only shows the three most recent: a
/// rating with nothing readable behind it tells a customer very little.
class VendorReviewsScreen extends StatefulWidget {
  const VendorReviewsScreen({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  final String vendorId;
  final String vendorName;

  @override
  State<VendorReviewsScreen> createState() => _VendorReviewsScreenState();
}

class _VendorReviewsScreenState extends State<VendorReviewsScreen> {
  static const _pageSize = 20;

  final _repo = ReviewRepository();
  final _scroll = ScrollController();
  final _reviews = <Review>[];

  RatingBreakdown _breakdown = RatingBreakdown.empty;
  Object? _error;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.fetchVendorReviews(widget.vendorId, limit: _pageSize),
        _repo.fetchBreakdown(widget.vendorId),
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
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.fetchVendorReviews(
        widget.vendorId,
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
      // The page already has content; a failed *next* page is a message, not
      // an error screen replacing what the customer is reading.
      showFailure(context, error, onRetry: _loadMore);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.ratingsAndReviews)),
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
                  Text(widget.vendorName, style: AppType.heading(17)),
                  const SizedBox(height: AppSpace.lg),
                  RatingSummary(breakdown: _breakdown),
                  const SizedBox(height: AppSpace.xl),
                  if (_reviews.isEmpty)
                    EmptyView(
                      message: l10n.noReviewsYet,
                      icon: Icons.reviews_outlined,
                    )
                  else
                    for (final review in _reviews) ReviewTile(review: review),
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
