import 'package:flutter/material.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../app/tokens.dart';
import '../models/finance.dart';
import '../utils/money.dart';
import '../utils/settlement_format.dart';
import 'common.dart' show SoftBadge;
import 'settlement_receipt.dart' show shareSettlementReceipt;

/// Turns a ledger type into something a human reads.
///
/// Falls back to the raw enum name rather than a placeholder: the server can
/// gain a type before the app ships, and `online_collection` on screen is far
/// more useful to whoever is debugging than "Other".
String ledgerTypeLabel(BuildContext context, String type) {
  final l10n = context.l10n;
  return switch (type) {
    'driver_earning' => l10n.deliveryFeesTotal,
    'driver_tip' => l10n.tips,
    'cash_collection' => l10n.cashCollectedLabel,
    'online_collection' => l10n.cardCollected,
    'driver_settlement' || 'vendor_settlement' => l10n.settlementsTitle,
    'driver_deposit' => l10n.requestDeposit,
    'vendor_earning' => l10n.itemSales,
    'platform_commission' => l10n.platformCommission,
    'platform_delivery_margin' => l10n.deliveryFeesTotal,
    'platform_discount' => l10n.platformFundedDiscounts,
    'refund' => l10n.refunds,
    'bonus' => l10n.bonus,
    'penalty' => l10n.penalty,
    'adjustment' => l10n.adjustments,
    'reversal' => l10n.reversal,
    _ => type.replaceAll('_', ' '),
  };
}

/// The two numbers that matter on any wallet, side by side.
///
/// Which one is emphasised depends on which way the balance points: a driver
/// holding cash needs to see the debt, a store needs to see the payable. The
/// other is still shown, at rest, so the pair always reads as one position
/// rather than two unrelated figures.
class WalletHeadline extends StatelessWidget {
  const WalletHeadline({super.key, required this.wallet, this.onDark = false});

  final WalletSummary wallet;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final owes = wallet.owesMoney;
    final amount = owes ? wallet.cashDue : wallet.payable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: AppColors.brandGradient,
          stops: AppColors.brandGradientStops,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            owes ? l10n.cashDue : l10n.owedToYou,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              formatMoney(amount),
              style: AppType.mono(
                30,
                color: Colors.white,
                weight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            owes ? l10n.youOweExplainer : l10n.owedToYouExplainer,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: Colors.white.withValues(alpha: 0.78),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled money figure, for the grids the finance screens are built from.
class MoneyTile extends StatelessWidget {
  const MoneyTile({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.tone,
  });

  final String label;
  final String value;
  final bool emphasis;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      this.label,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11.5,
        // 1.5 is the theme's body height and is generous for a label;
        // tightening it buys most of the room back.
        height: 1.25,
        color: AppColors.textMuted,
      ),
    );
    final amount = FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        value,
        maxLines: 1,
        style: AppType.mono(
          emphasis ? 22 : 19,
          color: tone ?? AppColors.ink,
          weight: emphasis ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    );
    // Figure first, label under it. A finance dashboard is read by scanning
    // the numbers and only then checking what they are — leading with an
    // 11.5px muted caption puts the least useful line where the eye lands.
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [amount, const SizedBox(height: 3), label],
    );

    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      // Keep this column non-flexed. A MoneyTile is used both in a bounded
      // SliverGrid cell and directly as a ListView child; flex children in
      // the latter receive unbounded height and trigger a render assertion.
      // Scale the complete content for unusually short grid cells, while
      // retaining a normal shrink-wrapped column in a list.
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.hasBoundedHeight
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: content,
              )
            : content,
      ),
    );
  }
}

/// One party's open request, however it was opened — free or early/fee-based
/// — shown in place of every action card while it waits on an admin. A party
/// can only ever have one at a time (the server refuses a second), so
/// there's never a choice to make between showing this and an action card.
class PendingSettlementTile extends StatelessWidget {
  const PendingSettlementTile({super.key, required this.pending});

  final Settlement pending;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.amberInk.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hourglass_top_rounded, color: AppColors.amberInk),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (pending.isEarly) ...[
                      const Icon(
                        Icons.bolt_rounded,
                        size: 15,
                        color: AppColors.amberInk,
                      ),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      formatMoney(pending.amount),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppColors.amberInk,
                      ),
                    ),
                  ],
                ),
                Text(
                  l10n.settlementRequestPending,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.amberInk.withValues(alpha: 0.85),
                  ),
                ),
                if (pending.isEarly) ...[
                  const SizedBox(height: AppSpace.sm),
                  const Divider(height: 1, color: AppColors.amberInk),
                  const SizedBox(height: AppSpace.sm),
                  _feeBreakdown(context, pending, tone: AppColors.amberInk),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The free, wait-for-admin way to cash out a positive balance — offered
/// alongside a paid option (vendor's/driver's Early Payout, [EarlyPayoutCard])
/// that goes through the same queue but costs a fee for earlier review.
class SettlementRequestCard extends StatelessWidget {
  const SettlementRequestCard({
    super.key,
    required this.title,
    required this.hint,
    required this.payable,
    required this.busy,
    required this.onRequest,
  });

  final String title;
  final String hint;
  final double payable;
  final bool busy;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    if (payable <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_outlined,
            size: 20,
            color: AppColors.textSecondary,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.heading(14)),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          OutlinedButton(
            onPressed: busy ? null : onRequest,
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(title),
          ),
        ],
      ),
    );
  }
}

/// The paid, faster-review way to cash out — same request→approve queue as
/// [SettlementRequestCard], just with a fee the [quote] spells out before the
/// party commits to it. Shared by vendor and driver: nothing here is
/// vendor-specific, only the [quote] and [onTake] callback the screen wires
/// up differ.
class EarlyPayoutCard extends StatelessWidget {
  const EarlyPayoutCard({super.key, required this.quote, required this.onTake});

  final EarlySettlementQuote quote;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final due = quote.nextScheduledPayout;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.event_available_rounded,
                size: 18,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  l10n.nextPayout,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(15),
                ),
              ),
              if (due != null)
                Text(
                  '${due.day}/${due.month}',
                  style: AppType.mono(14, weight: FontWeight.w800),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            l10n.earlyPayoutExplainer,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
          if (!quote.available) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              l10n.earlyPayoutUnavailable,
              style: const TextStyle(fontSize: 12, color: AppColors.textFaint),
            ),
          ] else ...[
            const SizedBox(height: AppSpace.md),
            // The cost is spelled out before the button, not after it.
            _priceLine(
              l10n.owedToYou,
              formatMoney(quote.payable),
              AppColors.ink,
            ),
            _priceLine(
              l10n.earlyPayoutFee(
                quote.feePercent.toStringAsFixed(
                  quote.feePercent % 1 == 0 ? 0 : 1,
                ),
              ),
              '-${formatMoney(quote.fee)}',
              AppColors.dangerInk,
            ),
            const Divider(height: AppSpace.lg, color: AppColors.borderSoft),
            _priceLine(
              l10n.youReceive,
              formatMoney(quote.netPayout),
              AppColors.successInk,
              emphasis: true,
            ),
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onTake,
                icon: const Icon(Icons.bolt_rounded),
                label: Text(
                  l10n.earlyPayout,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _priceLine(
  String label,
  String value,
  Color tone, {
  bool emphasis = false,
}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    children: [
      Expanded(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: emphasis ? 14 : 13,
            fontWeight: emphasis ? FontWeight.w800 : FontWeight.w500,
            color: emphasis ? AppColors.ink : AppColors.textSecondary,
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        value,
        style: AppType.mono(
          emphasis ? 15 : 13.5,
          color: tone,
          weight: emphasis ? FontWeight.w800 : FontWeight.w700,
        ),
      ),
    ],
  ),
);

/// The `Gross → Fee → Net` story behind an early settlement, shared by the
/// pending tile, the details sheet and the receipt — same three numbers off
/// the row every time. [Settlement.grossAmount] is the only derived one, and
/// it's pure addition of the other two, never a re-derivation of either.
Widget _feeBreakdown(
  BuildContext context,
  Settlement settlement, {
  required Color tone,
}) {
  final l10n = context.l10n;
  return Column(
    children: [
      _priceLine(l10n.grossAmount, formatMoney(settlement.grossAmount), tone),
      _priceLine(l10n.feeLabel, '-${formatMoney(settlement.fee)}', tone),
      _priceLine(
        l10n.youReceive,
        formatMoney(settlement.amount),
        tone,
        emphasis: true,
      ),
    ],
  );
}

/// One past hand-over in a settlement history list. Tapping opens the full
/// record — every figure and date the row itself has no room for.
class SettlementTile extends StatelessWidget {
  const SettlementTile({super.key, required this.settlement, this.partyName});

  final Settlement settlement;

  /// Printed on the receipt if the row is opened and shared. Omit for a
  /// party's own history (their own name would be redundant); pass it from
  /// an admin's cross-party list.
  final String? partyName;

  @override
  Widget build(BuildContext context) {
    final (_, ink) = settlementStatusTone(settlement.status);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      onTap: () =>
          showSettlementDetails(context, settlement, partyName: partyName),
      leading: Icon(
        settlement.status == 'cancelled'
            ? Icons.cancel_outlined
            : Icons.check_circle_outline_rounded,
        color: ink,
      ),
      title: Row(
        children: [
          if (settlement.isEarly) ...[
            const Icon(Icons.bolt_rounded, size: 15, color: AppColors.amberInk),
            const SizedBox(width: 2),
          ],
          Text(formatMoney(settlement.amount)),
        ],
      ),
      subtitle: Text(
        [
          '${settlement.createdAt.day}/${settlement.createdAt.month}',
          if (settlement.notes != null && settlement.notes!.isNotEmpty)
            settlement.notes!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: AppColors.textFaint,
      ),
    );
  }
}

/// The full record behind one [SettlementTile] — every field the server
/// stored, shown as-is. Nothing here is recomputed: the amount, dates and
/// reference are read straight off the row that was already written and
/// already reconciled server-side, so there is nothing for the sheet to get
/// wrong.
Future<void> showSettlementDetails(
  BuildContext context,
  Settlement settlement, {
  String? partyName,
}) {
  final l10n = context.l10n;
  final (fill, ink) = settlementStatusTone(settlement.status);

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
    ),
    builder: (sheetContext) => SafeArea(
      // A settlement with every optional field set (reference, notes, both
      // dates) is taller than the sheet's default max height on short
      // screens, so it scrolls rather than overflowing.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(l10n.settlementDetails, style: AppType.heading(18)),
                  if (settlement.isEarly) ...[
                    const SizedBox(width: AppSpace.sm),
                    SoftBadge(
                      label: l10n.earlySettlementTag,
                      icon: Icons.bolt_rounded,
                      fill: AppColors.amberFill,
                      ink: AppColors.amberInk,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Center(
                child: Column(
                  children: [
                    Text(
                      formatMoney(settlement.amount),
                      style: AppType.mono(30, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: AppSpace.sm),
                    SoftBadge(
                      label: settlementStatusLabel(
                        sheetContext,
                        settlement.status,
                      ),
                      fill: fill,
                      ink: ink,
                    ),
                  ],
                ),
              ),
              if (settlement.isEarly) ...[
                const SizedBox(height: AppSpace.lg),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.canvas,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: _feeBreakdown(
                    sheetContext,
                    settlement,
                    tone: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpace.xl),
              _detailRow(
                l10n.settlementMethod,
                settlementMethodLabel(sheetContext, settlement.method),
              ),
              _detailRow(
                l10n.settlementRecordedOn,
                formatSettlementDateTime(sheetContext, settlement.createdAt),
              ),
              if (settlement.completedAt != null)
                _detailRow(
                  l10n.settlementCompletedOn,
                  formatSettlementDateTime(
                    sheetContext,
                    settlement.completedAt!,
                  ),
                ),
              if (settlement.reference != null &&
                  settlement.reference!.isNotEmpty)
                _detailRow(l10n.settlementReference, settlement.reference!),
              if (settlement.notes != null && settlement.notes!.isNotEmpty)
                _detailRow(l10n.settlementNotes, settlement.notes!),
              _detailRow(l10n.settlementId, settlement.id, mono: true),
              const SizedBox(height: AppSpace.lg),
              if (settlement.status == 'completed') ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => shareSettlementReceipt(
                      sheetContext,
                      settlement,
                      partyName: partyName,
                    ),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: Text(l10n.shareReceipt),
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text(l10n.okLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _detailRow(String label, String value, {bool mono = false}) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 7),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
      ),
      const SizedBox(width: AppSpace.md),
      Flexible(
        flex: 2,
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: mono
              ? AppType.mono(12, color: AppColors.textSecondary)
              : const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink,
                ),
        ),
      ),
    ],
  ),
);

/// One line of a statement.
class LedgerTile extends StatelessWidget {
  const LedgerTile({super.key, required this.entry, this.onLongPress});

  final LedgerEntry entry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final reversed = entry.isReversed;
    // A reversed row stays visible — that is the point of an audit trail — but
    // struck through, so it cannot be mistaken for live money.
    final tone = reversed
        ? AppColors.textFaint
        : entry.isCredit
        ? AppColors.successInk
        : AppColors.dangerInk;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      onLongPress: onLongPress,
      title: Text(
        ledgerTypeLabel(context, entry.type),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          decoration: reversed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text(
        [
          if (entry.reference != null && entry.reference!.isNotEmpty)
            entry.reference!,
          '${entry.createdAt.day}/${entry.createdAt.month} '
              '${TimeOfDay.fromDateTime(entry.createdAt).format(context)}',
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
      ),
      trailing: Text(
        '${entry.isCredit ? '+' : '-'}${formatMoney(entry.amount)}',
        style: AppType.mono(
          14,
          color: tone,
          weight: FontWeight.w800,
        ).copyWith(decoration: reversed ? TextDecoration.lineThrough : null),
      ),
    );
  }
}
