import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wallet_transaction.dart';

class WalletRepository {
  final SupabaseClient _client;
  WalletRepository({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  Future<double> getBalance() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return 0.0;

    final res = await _client
        .from('wallets')
        .select('balance')
        .eq('user_id', userId)
        .maybeSingle();

    if (res == null) return 0.0;
    return ((res['balance'] as num?) ?? 0).toDouble();
  }

  Future<List<WalletTransaction>> getTransactions() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final res = await _client
        .from('wallet_transactions')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (res as List)
        .map((e) => WalletTransaction.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Pays an order from the wallet. Balance check, debit, ledger entry and the
  /// order's paid flag happen server-side in one transaction; throws
  /// `INSUFFICIENT_WALLET_BALANCE` when the balance is short.
  Future<bool> payOrder(String orderId) async {
    final res = await _client
        .rpc('pay_order_with_wallet', params: {'p_order_id': orderId});
    return res == true;
  }
}

// Note: there is deliberately no client-side top-up. A balance can only be
// credited by settle_payment_intent(), called by the Paymob webhook after the
// transaction's HMAC signature has been verified.
