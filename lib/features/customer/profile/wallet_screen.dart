import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import 'package:go_router/go_router.dart';
import '../../../app/tokens.dart';
import '../../../core/models/wallet_transaction.dart';
import '../../../core/repositories/payment_repository.dart';
import '../../../core/repositories/wallet_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/utils/paging.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/finance_widgets.dart';
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
  bool _hasMore = false;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _loadWallet();
  }

  Future<void> _loadWallet() async {
    try {
      final results = await Future.wait([
        _walletRepo.getBalance(),
        _walletRepo.getTransactions(),
      ]);
      if (!mounted) return;
      final txs = results[1] as List<WalletTransaction>;
      setState(() {
        _balance = results[0] as double;
        _transactions = txs;
        _hasMore = txs.length == kPageSize;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFailure(context, error, onRetry: _loadWallet);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _transactions.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final last = _transactions.last;
      final page = await _walletRepo.getTransactions(
        before: (createdAt: last.createdAt, id: last.id),
      );
      if (!mounted) return;
      setState(() {
        _transactions = [..._transactions, ...page];
        _hasMore = page.length == kPageSize;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      showFailure(context, error, onRetry: _loadMore);
    }
  }

  /// Opens Paymob's unified checkout for [amount]. The balance is credited by
  /// the webhook, never by this screen — so the money is only added once the
  /// transaction really succeeded.
  Future<void> _startTopUp(double amount, PaymobChannel channel) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final l10n = context.l10n;

    void fail(String message) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      messenger.showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.dangerInk),
      );
    }

    setState(() => _isLoading = true);

    PaymobCheckout checkout;
    try {
      checkout = await _paymentRepo.createTopUpCheckout(
        amount,
        channel: channel,
      );
    } on PaymentException catch (error) {
      fail(switch (error.code) {
        'INVALID_TOPUP_AMOUNT' => l10n.topUpInvalidAmount,
        'PAYMOB_NOT_CONFIGURED' => l10n.topUpUnavailable,
        _ => l10n.topUpOpenFailed,
      });
      return;
    } catch (error) {
      fail(l10n.topUpOpenFailed);
      return;
    }
    if (!mounted) return;

    final result = await runPaymobCheckout(
      router,
      checkout,
      payments: _paymentRepo,
    );
    if (!mounted) return;

    switch (result) {
      case PaymobFlowResult.paid:
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.topUpAdded(formatMoney(amount)))),
        );
        await _loadWallet();
      case PaymobFlowResult.cancelled:
        fail(l10n.topUpCancelled);
      case PaymobFlowResult.failed:
        fail(l10n.topUpFailed);
      case PaymobFlowResult.unresolved:
        if (!mounted) return;
        setState(() => _isLoading = false);
        messenger.showSnackBar(SnackBar(content: Text(l10n.topUpPending)));
    }
  }

  /// Amount picker. The quick-pick chips write into the text field and vice
  /// versa, which is exactly what `contentBuilder`'s `rebuild` callback is for —
  /// the dialog repaints without this screen having to hold the draft amount.
  ///
  /// The dialog's job ends at a valid amount; opening Paymob's page is this
  /// screen's job, so `onSubmit` returns the number and the webview follows.
  Future<void> _showTopUpDialog() async {
    final amount = TextEditingController(text: '100');
    // Held here rather than in the dialog so `onSubmit` can read it: the
    // dialog only ever returns the amount.
    var channel = PaymobChannel.card;
    try {
      final chosen = await showFormDialog<double>(
        context: context,
        title: context.l10n.topUpWallet,
        subtitle: context.l10n.selectTopUpAmount,
        icon: Icons.account_balance_wallet_rounded,
        // The channel (card or mobile wallet) is chosen in the form itself, so
        // the button just says pay.
        submitLabel: context.l10n.payAction,
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
              SegmentedButton<PaymobChannel>(
                expandedInsets: EdgeInsets.zero,
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: PaymobChannel.card,
                    icon: const Icon(Icons.credit_card_rounded, size: 17),
                    label: Text(
                      context.l10n.card,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: PaymobChannel.wallet,
                    icon: const Icon(Icons.smartphone_rounded, size: 17),
                    label: Text(
                      context.l10n.mobileWallet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {channel},
                onSelectionChanged: (value) {
                  channel = value.first;
                  rebuild();
                },
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.egp,
                  prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                ),
                // Keeps the chip selection in step with typed input.
                onChanged: (_) => rebuild(),
              ),
            ],
          );
        },
        onSubmit: (_) async {
          final value = double.tryParse(amount.text);
          // Null keeps the dialog open rather than silently doing nothing.
          if (value == null || value <= 0) return null;
          return value;
        },
      );
      if (chosen != null) await _startTopUp(chosen, channel);
    } finally {
      Future.delayed(const Duration(milliseconds: 500), () => amount.dispose());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.myWallet), elevation: 0),
      body: _isLoading
          ? const _WalletSkeleton()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadWallet,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  AppSpace.lg,
                  AppSpace.md,
                  AppSpace.lg,
                  AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                children: [
                  FinanceHero(
                    eyebrow: l10n.currentBalance,
                    amount: formatMoney(_balance),
                    caption: l10n.walletSpendHint,
                    action: FinanceHeroAction(
                      label: l10n.topUpWallet,
                      icon: Icons.add_rounded,
                      onPressed: _showTopUpDialog,
                    ),
                  ),
                  FinanceSection(
                    title: l10n.activityLabel,
                    child: _transactions.isEmpty
                        ? FinanceEmpty(message: l10n.noTransactions)
                        : DayGroupedList<WalletTransaction>(
                            items: _transactions,
                            dateOf: (tx) => tx.createdAt,
                            itemBuilder: (tx) => _TransactionTile(tx: tx),
                          ),
                  ),
                  if (_hasMore)
                    FinanceLoadMore(busy: _loadingMore, onPressed: _loadMore),
                ],
              ),
            ),
    );
  }
}

/// One wallet movement, labelled by what it was rather than its raw type.
class _TransactionTile extends StatelessWidget {
  const _TransactionTile({required this.tx});

  final WalletTransaction tx;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (IconData icon, String? label) = switch (tx.type) {
      'deposit' ||
      'topup' ||
      'top_up' => (Icons.add_card_rounded, l10n.walletTxTopUp),
      'payment' => (Icons.shopping_bag_rounded, l10n.walletTxPayment),
      'refund' => (Icons.undo_rounded, l10n.walletTxRefund),
      'cashback' => (Icons.redeem_rounded, l10n.walletTxCashback),
      'tip' => (Icons.volunteer_activism_rounded, l10n.walletTxTip),
      _ => (Icons.receipt_long_rounded, null),
    };
    final title = label ?? tx.description ?? tx.type.replaceAll('_', ' ');
    final time = formatClock(context, tx.createdAt);
    return FinanceTxTile(
      icon: icon,
      title: title,
      subtitle: label != null && (tx.description?.isNotEmpty ?? false)
          ? '$time · ${tx.description}'
          : time,
      amount: formatMoney(tx.amount.abs()),
      isCredit: tx.amount > 0,
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
