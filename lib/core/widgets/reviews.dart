import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/tokens.dart';
import '../models/review.dart';
import '../utils/l10n_extension.dart';

/// Five stars, filled to [rating]. Read-only; the editable version lives in
/// the review sheet, where a tap has to mean something.
class RatingStars extends StatelessWidget {
  const RatingStars({
    super.key,
    required this.rating,
    this.size = 14,
    this.color = AppColors.rating,
  });

  final num rating;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var star = 1; star <= 5; star++)
          Icon(
            // Half stars matter on an average: 4.5 rendered as four full stars
            // reads as a worse store than it is.
            rating >= star
                ? Icons.star_rounded
                : rating >= star - 0.5
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: size,
            color: color,
          ),
      ],
    );
  }
}

/// The average, the count, and the shape of the distribution behind them.
class RatingSummary extends StatelessWidget {
  const RatingSummary({super.key, required this.breakdown});

  final RatingBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              breakdown.average.toStringAsFixed(1),
              style: AppType.display(34),
            ),
            RatingStars(rating: breakdown.average, size: 15),
            const SizedBox(height: 4),
            Text(
              l10n.basedOnReviews(breakdown.total),
              style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
            ),
          ],
        ),
        const SizedBox(width: AppSpace.xl),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var star = 5; star >= 1; star--)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        child: Text('$star',
                            style: AppType.mono(11,
                                color: AppColors.textMuted)),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          child: LinearProgressIndicator(
                            value: breakdown.share(star),
                            minHeight: 6,
                            backgroundColor: AppColors.neutralFill,
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.rating),
                          ),
                        ),
                      ),
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

/// One review. Used on the store page and in the vendor's own inbox, which
/// only differ by whether the order id is worth showing.
class ReviewTile extends StatelessWidget {
  const ReviewTile({super.key, required this.review, this.dense = false});

  final Review review;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: EdgeInsets.only(bottom: dense ? AppSpace.sm : AppSpace.md),
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
              Expanded(
                child: Text(
                  // A closed account comes back with no name rather than the
                  // scrubbed placeholder the profile now holds.
                  review.customerName ?? l10n.anonymous,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
              RatingStars(rating: review.rating, size: 14),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            DateFormat.yMMMd(Localizations.localeOf(context).toString())
                .format(review.createdAt),
            style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
          ),
          if (review.hasComment) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              review.comment!,
              style: const TextStyle(
                  fontSize: 13.5, height: 1.45, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// The star row a customer actually taps.
class RatingInput extends StatelessWidget {
  const RatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 38,
  });

  /// 0 means "not rated yet", which is how the driver rating stays optional.
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var star = 1; star <= 5; star++)
          IconButton(
            onPressed: () => onChanged(star),
            visualDensity: VisualDensity.compact,
            icon: Icon(
              star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: AppColors.rating,
            ),
          ),
      ],
    );
  }
}
