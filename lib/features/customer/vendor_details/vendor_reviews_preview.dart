import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/review.dart';
import '../../../core/repositories/review_repository.dart';
import '../../../core/widgets/reviews.dart';
import '../../../core/utils/l10n_extension.dart';
import 'vendor_reviews_screen.dart';

/// The store page's reviews block: the distribution and the three most recent
/// comments, with a way through to the rest.
///
/// Loaded on its own rather than with the menu — the menu is what the customer
/// came for, and reviews should not hold it up or fail it.
class VendorReviewsPreview extends StatefulWidget {
  const VendorReviewsPreview({
    super.key,
    required this.vendorId,
    required this.vendorName,
  });

  final String vendorId;
  final String vendorName;

  @override
  State<VendorReviewsPreview> createState() => _VendorReviewsPreviewState();
}

class _VendorReviewsPreviewState extends State<VendorReviewsPreview> {
  final _repo = ReviewRepository();

  late Future<(List<Review>, RatingBreakdown)> _future = _load();

  Future<(List<Review>, RatingBreakdown)> _load() async {
    final results = await Future.wait([
      _repo.fetchVendorReviews(widget.vendorId, limit: 3),
      _repo.fetchBreakdown(widget.vendorId),
    ]);
    return (results[0] as List<Review>, results[1] as RatingBreakdown);
  }

  @override
  void didUpdateWidget(VendorReviewsPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vendorId != widget.vendorId) _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<(List<Review>, RatingBreakdown)>(
      future: _future,
      builder: (context, snap) {
        // Silent on failure: this block is supporting detail, and an error
        // card under the menu would be noise the customer cannot act on.
        if (snap.connectionState != ConnectionState.done || snap.hasError) {
          return const SizedBox.shrink();
        }
        final (reviews, breakdown) = snap.data!;
        if (breakdown.total == 0) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ratingsAndReviews,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpace.lg),
              RatingSummary(breakdown: breakdown),
              const SizedBox(height: AppSpace.lg),
              for (final review in reviews)
                ReviewTile(review: review, dense: true),
              if (breakdown.total > reviews.length)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => VendorReviewsScreen(
                          vendorId: widget.vendorId,
                          vendorName: widget.vendorName,
                        ),
                      ),
                    ),
                    child: Text(l10n.seeAllReviews),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
