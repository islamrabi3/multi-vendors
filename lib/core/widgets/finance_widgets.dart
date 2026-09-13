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
    'driver_deposit' => l10n.cashHandedOver,
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

IconData ledgerTypeIcon(String type) => switch (type) {
  'driver_earning' => Icons.two_wheeler_rounded,
  'driver_tip' => Icons.volunteer_activism_rounded,
  'cash_collection' => Icons.payments_rounded,
  'online_collection' => Icons.credit_card_rounded,
  'driver_settlement' || 'vendor_settlement' => Icons.account_balance_rounded,
  'driver_deposit' => Icons.move_to_inbox_rounded,
  'vendor_earning' => Icons.storefront_rounded,
  'platform_commission' => Icons.percent_rounded,
  'platform_delivery_margin' => Icons.local_shipping_rounded,
  'platform_discount' => Icons.local_offer_rounded,
  'refund' => Icons.undo_rounded,
  'bonus' => Icons.card_giftcard_rounded,
  'penalty' => Icons.gavel_rounded,
  'adjustment' => Icons.tune_rounded,
  'reversal' => Icons.history_rounded,
  _ => Icons.receipt_long_rounded,
};

/// "Today", "Yesterday" or the date — the header over one day of activity.
String financeDayLabel(BuildContext context, DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return context.l10n.today;
  if (diff == 1) return context.l10n.yesterday;
  return '${value.day}/${value.month}/${value.year}';
}

/// An amount that never pushes its row into overflow: capped at a share of the
/// row's width and scaled down past that, so `EGP 1,234,567.89` in a narrow
/// Arabic row shrinks instead of striping the screen.
class _FitAmount extends StatelessWidget {
  const _FitAmount({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(maxWidth: maxWidth),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerEnd,
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Hero
// ---------------------------------------------------------------------------

/// A button placed inside a [FinanceHero].
class FinanceHeroAction {
  const FinanceHeroAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
}

enum FinanceHeroTone { brand, warning, calm }

/// The one number a money screen is about, with the one thing to do about it
/// directly underneath. Every financial screen opens with this card so the
/// same question — "where do I stand, and what do I do?" — is answered in the
/// same place for every role.
class FinanceHero extends StatelessWidget {
  const FinanceHero({
    super.key,
    required this.eyebrow,
    required this.amount,
    this.caption,
    this.tone = FinanceHeroTone.brand,
    this.action,
    this.secondaryAction,
    this.footer,
  });

  final String eyebrow;
  final String amount;
  final String? caption;
  final FinanceHeroTone tone;
  final FinanceHeroAction? action;
  final FinanceHeroAction? secondaryAction;

  /// Optional content under the actions, e.g. a small stat row.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final decoration = switch (tone) {
      FinanceHeroTone.brand => const BoxDecoration(
        gradient: LinearGradient(
          colors: AppColors.brandGradient,
          stops: AppColors.brandGradientStops,
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      FinanceHeroTone.warning => const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.inkElevated, AppColors.ink],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
      ),
      FinanceHeroTone.calm => const BoxDecoration(color: AppColors.ink),
    };
    final accent = tone == FinanceHeroTone.warning
        ? AppColors.rating
        : AppColors.onDarkPistachio;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.lg,
      ),
      decoration: decoration.copyWith(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.raised,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  eyebrow,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              amount,
              maxLines: 1,
              style: AppType.mono(
                34,
                color: Colors.white,
                weight: FontWeight.w800,
              ),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              caption!,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (action != null || secondaryAction != null) ...[
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                if (action != null)
                  Expanded(child: _HeroButton(action: action!, primary: true)),
                if (action != null && secondaryAction != null)
                  const SizedBox(width: AppSpace.sm),
                if (secondaryAction != null)
                  Expanded(
                    child: _HeroButton(
                      action: secondaryAction!,
                      primary: action == null,
                    ),
                  ),
              ],
            ),
          ],
          if (footer != null) ...[const SizedBox(height: AppSpace.md), footer!],
        ],
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({required this.action, required this.primary});

  final FinanceHeroAction action;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final child = action.busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: primary ? AppColors.primary : Colors.white,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 19),
              const SizedBox(width: AppSpace.sm),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
    );
    const text = TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800);
    if (primary) {
      return FilledButton(
        onPressed: action.busy ? null : action.onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primaryDark,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.35),
          disabledForegroundColor: AppColors.primaryDark.withValues(alpha: 0.6),
          minimumSize: const Size.fromHeight(50),
          shape: shape,
          textStyle: text,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: action.busy ? null : action.onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.45)),
        minimumSize: const Size.fromHeight(50),
        shape: shape,
        textStyle: text,
      ),
      child: child,
    );
  }
}

/// The wallet hero for a driver or a store: shows whichever way the balance
/// points, and offers the matching action — hand over cash when the party is
/// holding the platform's money, withdraw when the platform owes them.
class WalletHero extends StatelessWidget {
  const WalletHero({
    super.key,
    required this.wallet,
    this.onHandOver,
    this.onWithdraw,
    this.withdrawBusy = false,
  });

  final WalletSummary wallet;

  /// Null hides the button (e.g. stores never hand over cash).
  final VoidCallback? onHandOver;

  /// Null hides the button (e.g. a request is already in review).
  final VoidCallback? onWithdraw;
  final bool withdrawBusy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (wallet.owesMoney) {
      return FinanceHero(
        tone: FinanceHeroTone.warning,
        eyebrow: l10n.cashDue,
        amount: formatMoney(wallet.cashDue),
        caption: l10n.youOweExplainer,
        action: onHandOver == null
            ? null
            : FinanceHeroAction(
                label: l10n.requestDeposit,
                icon: Icons.move_to_inbox_rounded,
                onPressed: onHandOver,
              ),
      );
    }
    if (wallet.payable > 0) {
      return FinanceHero(
        eyebrow: l10n.owedToYou,
        amount: formatMoney(wallet.payable),
        caption: l10n.owedToYouExplainer,
        action: onWithdraw == null
            ? null
            : FinanceHeroAction(
                label: l10n.withdraw,
                icon: Icons.account_balance_rounded,
                onPressed: onWithdraw,
                busy: withdrawBusy,
              ),
      );
    }
    return FinanceHero(
      tone: FinanceHeroTone.calm,
      eyebrow: l10n.balanceLabel,
      amount: formatMoney(0),
      caption: l10n.allSettledExplainer,
    );
  }
}

// ---------------------------------------------------------------------------
// Sections and rows
// ---------------------------------------------------------------------------

/// A titled block. Every section on every money screen uses this, so the
/// rhythm (heading, 8px, card) is identical everywhere.
class FinanceSection extends StatelessWidget {
  const FinanceSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.only(top: AppSpace.xl),
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(16),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          child,
        ],
      ),
    );
  }
}

/// White bordered card whose children are separated by hairlines.
class FinanceCard extends StatelessWidget {
  const FinanceCard({
    super.key,
    required this.children,
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
  });

  final List<Widget> children;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                indent: AppSpace.lg,
                endIndent: AppSpace.lg,
                color: borderColor == AppColors.border
                    ? AppColors.borderSoft
                    : borderColor,
              ),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// One "label ··· amount" line.
class FinanceRow extends StatelessWidget {
  const FinanceRow({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone,
    this.note,
    this.emphasis = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final Color? tone;
  final String? note;
  final bool emphasis;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.lg,
        vertical: 13,
      ),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          children: [
            if (icon != null) ...[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (tone ?? AppColors.textSecondary).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: tone ?? AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: emphasis ? 14 : 13.5,
                      height: 1.3,
                      fontWeight: emphasis ? FontWeight.w800 : FontWeight.w600,
                      color: emphasis ? AppColors.ink : AppColors.textSecondary,
                    ),
                  ),
                  if (note != null)
                    Text(
                      note!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textFaint,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            _FitAmount(
              maxWidth: box.maxWidth * 0.45,
              child: Text(
                value,
                maxLines: 1,
                style: AppType.mono(
                  emphasis ? 16 : 14,
                  weight: emphasis ? FontWeight.w800 : FontWeight.w700,
                  color: tone ?? AppColors.ink,
                ),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: AppSpace.xs),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.textFaint,
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// Things waiting on an admin — shown right under the hero so the party
/// knows their request was received and is not lost.
class InReviewCard extends StatelessWidget {
  const InReviewCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.amberFill,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppColors.amberInk.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.md,
                AppSpace.lg,
                AppSpace.xs,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.hourglass_top_rounded,
                    size: 16,
                    color: AppColors.amberInk,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.inReview,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.amberInk,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
            const SizedBox(height: AppSpace.xs),
          ],
        ),
      ),
    );
  }
}

class InReviewRow extends StatelessWidget {
  const InReviewRow({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.sm,
        ),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Icon(icon, size: 20, color: AppColors.amberInk),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              _FitAmount(
                maxWidth: box.maxWidth * 0.45,
                child: Text(
                  amount,
                  maxLines: 1,
                  style: AppType.mono(
                    14,
                    weight: FontWeight.w800,
                    color: AppColors.amberInk,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-width segmented switch — for flipping between two or three lists on
/// the same screen (activity / payouts).
class FinanceSegments<T> extends StatelessWidget {
  const FinanceSegments({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.neutralFill,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected
                        ? AppColors.surface
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                    boxShadow: value == selected ? AppShadows.card : null,
                  ),
                  child: Text(
                    labelOf(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: value == selected
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: value == selected
                          ? AppColors.ink
                          : AppColors.textMuted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

/// A list split into one card per day, each under a "Today" / date header.
class DayGroupedList<T> extends StatelessWidget {
  const DayGroupedList({
    super.key,
    required this.items,
    required this.dateOf,
    required this.itemBuilder,
  });

  final List<T> items;
  final DateTime Function(T item) dateOf;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final groups = <DateTime, List<T>>{};
    for (final item in items) {
      final d = dateOf(item);
      groups.putIfAbsent(DateTime(d.year, d.month, d.day), () => []).add(item);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              AppSpace.xs,
              AppSpace.md,
              AppSpace.xs,
              AppSpace.sm,
            ),
            child: Text(
              financeDayLabel(context, entry.key),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              ),
            ),
          ),
          FinanceCard(
            children: [for (final item in entry.value) itemBuilder(item)],
          ),
        ],
      ],
    );
  }
}

/// One money movement: icon, what it was, when, and the signed amount.
class FinanceTxTile extends StatelessWidget {
  const FinanceTxTile({
    super.key,
    required this.icon,
    required this.title,
    required this.amount,
    required this.isCredit,
    this.subtitle,
    this.struck = false,
    this.trailingBadge,
    this.onTap,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Already formatted, without a sign — the sign comes from [isCredit].
  final String amount;
  final bool isCredit;
  final bool struck;
  final Widget? trailingBadge;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tone = struck
        ? AppColors.textFaint
        : isCredit
        ? AppColors.successInk
        : AppColors.ink;
    final fill = struck
        ? AppColors.neutralFill
        : isCredit
        ? AppColors.successFill
        : AppColors.neutralFill;
    final decoration = struck ? TextDecoration.lineThrough : null;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg,
          vertical: AppSpace.md,
        ),
        child: LayoutBuilder(
          builder: (context, box) => Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
                child: Icon(
                  icon,
                  size: 19,
                  color: struck
                      ? AppColors.textFaint
                      : isCredit
                      ? AppColors.successInk
                      : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.ink,
                        decoration: decoration,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              _FitAmount(
                maxWidth: box.maxWidth * 0.45,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${isCredit ? '+' : '-'}$amount',
                      style: AppType.mono(
                        14,
                        color: tone,
                        weight: FontWeight.w800,
                      ).copyWith(decoration: decoration),
                    ),
                    if (trailingBadge != null) ...[
                      const SizedBox(height: 3),
                      trailingBadge!,
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of a statement.
class LedgerTile extends StatelessWidget {
  const LedgerTile({super.key, required this.entry, this.onLongPress});

  final LedgerEntry entry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    // A reversed row stays visible — that is the point of an audit trail — but
    // struck through, so it cannot be mistaken for live money.
    return FinanceTxTile(
      icon: ledgerTypeIcon(entry.type),
      title: ledgerTypeLabel(context, entry.type),
      subtitle: [
        TimeOfDay.fromDateTime(entry.createdAt).format(context),
        if (entry.reference != null && entry.reference!.isNotEmpty)
          entry.reference!,
      ].join(' · '),
      amount: formatMoney(entry.amount),
      isCredit: entry.isCredit,
      struck: entry.isReversed,
      onLongPress: onLongPress,
    );
  }
}

/// Statement rows grouped by day, with the empty state built in.
class LedgerActivity extends StatelessWidget {
  const LedgerActivity({super.key, required this.entries});

  final List<LedgerEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return FinanceEmpty(message: context.l10n.noTransactionsYet);
    }
    return DayGroupedList<LedgerEntry>(
      items: entries,
      dateOf: (e) => e.createdAt,
      itemBuilder: (e) => LedgerTile(entry: e),
    );
  }
}

class FinanceEmpty extends StatelessWidget {
  const FinanceEmpty({
    super.key,
    required this.message,
    this.icon = Icons.receipt_long_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSpace.sm),
      padding: const EdgeInsets.symmetric(
        vertical: 36,
        horizontal: AppSpace.lg,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 34, color: AppColors.textFaint),
          const SizedBox(height: AppSpace.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Centred "Load more" under a paged list.
class FinanceLoadMore extends StatelessWidget {
  const FinanceLoadMore({
    super.key,
    required this.busy,
    required this.onPressed,
  });

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpace.sm),
    child: Center(
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(AppSpace.sm),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : TextButton(
              onPressed: onPressed,
              child: Text(context.l10n.loadMore),
            ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Withdraw
// ---------------------------------------------------------------------------

enum WithdrawChoice { standard, faster }

/// The two ways to get paid, side by side, with every number spelled out
/// before anything is tapped. Returns the choice; the screen runs it.
Future<WithdrawChoice?> showWithdrawSheet(
  BuildContext context, {
  required double payable,
  required EarlySettlementQuote quote,
}) {
  final l10n = context.l10n;
  final due = quote.nextScheduledPayout;
  return showModalBottomSheet<WithdrawChoice>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
    ),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.xl,
          0,
          AppSpace.xl,
          AppSpace.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.withdrawOptionsTitle, style: AppType.heading(19)),
            const SizedBox(height: AppSpace.xs),
            Text(
              '${l10n.owedToYou}: ${formatMoney(payable)}',
              style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            _WithdrawOption(
              icon: Icons.event_available_rounded,
              title: l10n.standardPayout,
              description: due == null
                  ? l10n.standardPayoutDesc
                  : l10n.standardPayoutDue('${due.day}/${due.month}'),
              receive: formatMoney(payable),
              onTap: () => Navigator.pop(sheetContext, WithdrawChoice.standard),
            ),
            const SizedBox(height: AppSpace.md),
            _WithdrawOption(
              icon: Icons.bolt_rounded,
              title: l10n.fasterPayout,
              description: quote.available
                  ? l10n.fasterPayoutDesc(formatMoney(quote.fee))
                  : l10n.earlyPayoutUnavailable,
              receive: quote.available ? formatMoney(quote.netPayout) : null,
              accent: AppColors.amberInk,
              onTap: quote.available
                  ? () => Navigator.pop(sheetContext, WithdrawChoice.faster)
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}

class _WithdrawOption extends StatelessWidget {
  const _WithdrawOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.receive,
    required this.onTap,
    this.accent = AppColors.primary,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? receive;
  final VoidCallback? onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled ? AppColors.surface : AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.border, width: 1.5),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: enabled ? 0.1 : 0.05),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(
                  icon,
                  color: enabled ? accent : AppColors.textFaint,
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppType.heading(
                        15,
                        color: enabled ? AppColors.ink : AppColors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (receive != null) ...[
                const SizedBox(width: AppSpace.sm),
                _FitAmount(
                  maxWidth: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        receive!,
                        style: AppType.mono(14, weight: FontWeight.w800),
                      ),
                      Text(
                        context.l10n.youReceive,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tiles kept for dense grids (admin vendor detail)
// ---------------------------------------------------------------------------

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
    // the numbers and only then checking what they are.
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

// ---------------------------------------------------------------------------
// Settlements
// ---------------------------------------------------------------------------

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
/// details sheet and the admin request card — same three numbers off the row
/// every time.
Widget settlementFeeBreakdown(
  BuildContext context,
  Settlement settlement, {
  Color tone = AppColors.textSecondary,
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

/// One past or pending hand-over in a settlement history list. Tapping opens
/// the full record.
class SettlementTile extends StatelessWidget {
  const SettlementTile({super.key, required this.settlement, this.partyName});

  final Settlement settlement;

  /// Printed on the receipt if the row is opened and shared. Omit for a
  /// party's own history; pass it from an admin's cross-party list.
  final String? partyName;

  @override
  Widget build(BuildContext context) {
    final (fill, ink) = settlementStatusTone(settlement.status);
    return FinanceTxTile(
      icon: settlement.isEarly
          ? Icons.bolt_rounded
          : Icons.account_balance_rounded,
      title: settlementMethodLabel(context, settlement.method),
      subtitle: [
        '${settlement.createdAt.day}/${settlement.createdAt.month}/${settlement.createdAt.year}',
        if (settlement.notes != null && settlement.notes!.isNotEmpty)
          settlement.notes!,
      ].join(' · '),
      amount: formatMoney(settlement.amount),
      // Money out of the account either way; tone comes from the badge.
      isCredit: false,
      struck: settlement.status == 'cancelled',
      trailingBadge: _TinyBadge(
        label: settlementStatusLabel(context, settlement.status),
        fill: fill,
        ink: ink,
      ),
      onTap: () =>
          showSettlementDetails(context, settlement, partyName: partyName),
    );
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({
    required this.label,
    required this.fill,
    required this.ink,
  });

  final String label;
  final Color fill;
  final Color ink;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: ink),
    ),
  );
}

/// The full record behind one [SettlementTile] — every field the server
/// stored, shown as-is. Nothing here is recomputed.
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
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
    ),
    builder: (sheetContext) => SafeArea(
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
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.settlementDetails,
                      style: AppType.heading(18),
                    ),
                  ),
                  if (settlement.isEarly)
                    SoftBadge(
                      label: l10n.earlySettlementTag,
                      icon: Icons.bolt_rounded,
                      fill: AppColors.amberFill,
                      ink: AppColors.amberInk,
                    ),
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
                  child: settlementFeeBreakdown(sheetContext, settlement),
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
                OutlinedButton.icon(
                  onPressed: () => shareSettlementReceipt(
                    sheetContext,
                    settlement,
                    partyName: partyName,
                  ),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text(l10n.shareReceipt),
                ),
                const SizedBox(height: AppSpace.sm),
              ],
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(l10n.okLabel),
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
          textAlign: TextAlign.end,
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
