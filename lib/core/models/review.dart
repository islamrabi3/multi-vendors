import 'package:equatable/equatable.dart';

/// One customer's rating of a store, as it is read back.
///
/// The reviewer is a display name and nothing else: `vendor_reviews` returns
/// no ids, so a review can be shown without exposing who wrote it beyond the
/// name they already put on their orders.
class Review extends Equatable {
  const Review({
    required this.id,
    required this.rating,
    required this.createdAt,
    this.comment,
    this.customerName,
    this.orderId,
  });

  final String id;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  /// Null for a closed account, which is scrubbed to a placeholder name that
  /// should not appear under a review.
  final String? customerName;

  /// Only present on the vendor's own inbox, where the store may want to look
  /// the order up.
  final String? orderId;

  bool get hasComment => (comment?.trim().isNotEmpty) ?? false;

  factory Review.fromMap(Map<String, dynamic> map) => Review(
        id: map['id'] as String,
        rating: ((map['rating'] as num?) ?? 0).toInt(),
        comment: map['comment'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
        customerName: map['customer_name'] as String?,
        orderId: map['order_id'] as String?,
      );

  @override
  List<Object?> get props =>
      [id, rating, comment, createdAt, customerName, orderId];
}

/// The counts behind a store's average, for the summary bar.
class RatingBreakdown extends Equatable {
  const RatingBreakdown({
    required this.total,
    required this.average,
    required this.counts,
  });

  final int total;
  final double average;

  /// Keyed by star, 1–5.
  final Map<int, int> counts;

  static const empty =
      RatingBreakdown(total: 0, average: 0, counts: {5: 0, 4: 0, 3: 0, 2: 0, 1: 0});

  /// Share of the total at [star], 0–1. Zero reviews is zero everywhere rather
  /// than a division by zero.
  double share(int star) => total == 0 ? 0 : (counts[star] ?? 0) / total;

  factory RatingBreakdown.fromMap(Map<String, dynamic> map) => RatingBreakdown(
        total: ((map['total'] as num?) ?? 0).toInt(),
        average: ((map['average'] as num?) ?? 0).toDouble(),
        counts: {
          5: ((map['five'] as num?) ?? 0).toInt(),
          4: ((map['four'] as num?) ?? 0).toInt(),
          3: ((map['three'] as num?) ?? 0).toInt(),
          2: ((map['two'] as num?) ?? 0).toInt(),
          1: ((map['one'] as num?) ?? 0).toInt(),
        },
      );

  @override
  List<Object?> get props => [total, average, counts];
}
