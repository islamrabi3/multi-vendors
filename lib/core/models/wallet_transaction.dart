import 'package:equatable/equatable.dart';

class WalletTransaction extends Equatable {
  const WalletTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.referenceId,
    this.description,
  });

  final String id;
  final String userId;
  final String type; // 'deposit', 'payment', 'refund', 'cashback', 'tip'
  final double amount;
  final String? referenceId;
  final String? description;
  final DateTime createdAt;

  factory WalletTransaction.fromMap(Map<String, dynamic> map) => WalletTransaction(
        id: map['id'] as String,
        userId: map['user_id'] as String,
        type: map['type'] as String,
        amount: ((map['amount'] as num?) ?? 0).toDouble(),
        referenceId: map['reference_id'] as String?,
        description: map['description'] as String?,
        createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
      );

  @override
  List<Object?> get props => [id, userId, type, amount, createdAt, referenceId];
}
