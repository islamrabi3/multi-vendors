import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../app/tokens.dart';
import '../../../core/models/wallet_transaction.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/repositories/wallet_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/skeleton.dart';
import '../checkout/paymob_flow.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final WalletRepository _walletRepo = WalletRepository();
  final PaymentRepository _paymentRepo = PaymentRepository();
  double _balance = 0.0;
  List<WalletTransaction> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    setState(() => _isLoading = true);
    final balance = await _walletRepo.getBalance();
    final txs = await _walletRepo.getTransactions();
    setState(() {
      _balance = balance;
      _transactions = txs;
      _isLoading = false;
    });
  }

  /// Opens Paymob's unified checkout for [amount]. The balance is credited by
  /// the webhook, never by this screen — so the money is only added once the
  /// transaction really succeeded.
  Future<void> _startTopUp(double amount) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    void fail(String message) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(
            content: Text(message), backgroundColor: AppColors.dangerInk),
      );
    }

    setState(() => _isLoading = true);

    PaymobCheckout checkout;
    try {
      checkout = await _paymentRepo.createTopUpCheckout(amount);
    } on PaymentException catch (error) {
      fail(_topUpErrorMessage(error.code));
      return;
    } catch (error) {
      fail('Could not open the payment page: $error');
      return;
    }
    if (!mounted) return;

    final result =
        await runPaymobCheckout(router, checkout, payments: _paymentRepo);
    if (!mounted) return;

    switch (result) {
      case PaymobFlowResult.paid:
        messenger.showSnackBar(
          SnackBar(
            content: Text(
                'Added ${amount.toStringAsFixed(2)} EGP to your wallet 🎉'),
          ),
        );
        await _loadWallet();
      case PaymobFlowResult.cancelled:
        fail('Payment cancelled. Your balance was not changed.');
      case PaymobFlowResult.failed:
        fail('Payment failed. Your balance was not changed.');
      case PaymobFlowResult.unresolved:
        if (!mounted) return;
        setState(() => _isLoading = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
                'Still confirming with the bank. Pull to refresh in a moment — '
                'the balance updates once the payment is confirmed.'),
          ),
        );
    }
  }

  String _topUpErrorMessage(String code) => switch (code) {
        'INVALID_TOPUP_AMOUNT' => 'Enter an amount between 10 and 20,000 EGP.',
        'PAYMOB_NOT_CONFIGURED' =>
          'Card payments are not available right now. Try again later.',
        _ => 'Could not open the payment page. Please try again.',
      };

  /// Amount picker. The quick-pick chips write into the text field and vice
  /// versa, which is exactly what `contentBuilder`'s `rebuild` callback is for —
  /// the dialog repaints without this screen having to hold the draft amount.
  ///
  /// The dialog's job ends at a valid amount; opening Paymob's page is this
  /// screen's job, so `onSubmit` returns the number and the webview follows.
  Future<void> _showTopUpDialog() async {
    final amount = TextEditingController(text: '100');
    try {
      final chosen = await showFormDialog<double>(
        context: context,
        title: context.l10n.topUpWallet,
        subtitle: context.l10n.selectTopUpAmount,
        icon: Icons.account_balance_wallet_rounded,
        submitLabel: context.l10n.payWithPaymob,
        cancelLabel: context.l10n.cancel,
        contentBuilder: (rebuild) {
          final current = double.tryParse(amount.text);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in const [50, 100, 200, 500])
                    ChoiceChip(
                      label: Text('$preset ${context.l10n.egp}'),
                      selected: current == preset,
                      onSelected: (selected) {
                        if (!selected) return;
                        amount.text = '$preset';
                        rebuild();
                      },
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.egp,
                  prefixIcon:
                      const Icon(Icons.payments_outlined, size: 20),
                ),
                // Keeps the chip selection in step with typed input.
                onChanged: (_) => rebuild(),
              ),
            ],
          );
        },
        onSubmit: () async {
          final value = double.tryParse(amount.text);
          // Null keeps the dialog open rather than silently doing nothing.
          if (value == null || value <= 0) return null;
          return value;
        },
      );
      if (chosen != null) await _startTopUp(chosen);
    } finally {
      amount.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.myWallet),
        elevation: 0,
      ),
      body: _isLoading
          ? const _WalletSkeleton()
          : RefreshIndicator(
              onRefresh: _loadWallet,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16,
                    16 + MediaQuery.paddingOf(context).bottom),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primaryLight,
                          AppColors.primaryDark
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadii.xl),
                      boxShadow: AppShadows.raised,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.l10n.currentBalance,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_balance.toStringAsFixed(2)} EGP',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.primaryDark,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadii.md),
                                ),
                              ),
                              onPressed: _showTopUpDialog,
                              icon: const Icon(Icons.add_circle_outline),
                              label: Text(context.l10n.topUpWallet,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    context.l10n.pointsHistory,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                        child: Text(
                          context.l10n.noTransactions,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    )
                  else
                    ..._transactions.map((tx) {
                      final isPositive = tx.amount > 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isPositive
                                ? AppColors.successFill
                                : AppColors.dangerFill,
                            child: Icon(
                              isPositive
                                  ? Icons.arrow_downward
                                  : Icons.arrow_upward,
                              color: isPositive
                                  ? AppColors.successInk
                                  : AppColors.dangerInk,
                            ),
                          ),
                          title: Text(tx.description ?? tx.type),
                          subtitle: Text(
                            '${tx.createdAt.day}/${tx.createdAt.month}/${tx.createdAt.year}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: Text(
                            '${isPositive ? '+' : ''}${tx.amount.toStringAsFixed(2)} EGP',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: isPositive
                                  ? AppColors.successInk
                                  : AppColors.dangerInk,
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

/// Wallet while the balance and ledger load: the balance hero, then rows.
class _WalletSkeleton extends StatelessWidget {
  const _WalletSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.lg),
        children: [
          const Skeleton.box(height: 176, radius: AppRadii.xl),
          const SizedBox(height: AppSpace.xxl),
          const Skeleton.line(widthFactor: 0.4, height: 18),
          const SizedBox(height: AppSpace.md),
          for (var i = 0; i < 5; i++)
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpace.sm),
              child: Skeleton.box(height: 68, radius: AppRadii.md),
            ),
        ],
      ),
    );
  }
}
