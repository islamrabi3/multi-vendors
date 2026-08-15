import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';

import '../../app/tokens.dart';
import '../models/finance.dart';
import '../utils/money.dart';
import '../utils/settlement_format.dart';
import 'brand_logo.dart';

/// Renders [settlement] off-screen and hands the PNG to the share sheet.
///
/// Rendered fresh from the live record every time, never pre-generated or
/// stored — the numbers on the receipt can never drift from the ledger,
/// because there is nothing to drift: it is the ledger row itself, drawn.
Future<void> shareSettlementReceipt(
  BuildContext context,
  Settlement settlement, {
  String? partyName,
}) async {
  final l10n = context.l10n;
  final boundaryKey = GlobalKey();
  final overlay = Overlay.of(context, rootOverlay: true);

  final entry = OverlayEntry(
    builder: (overlayContext) => Positioned(
      left: -9999,
      top: 0,
      child: Material(
        color: Colors.transparent,
        child: RepaintBoundary(
          key: boundaryKey,
          child: _ReceiptCard(
            settlement: settlement,
            partyName: partyName,
            l10n: overlayContext.l10n,
          ),
        ),
      ),
    ),
  );

  overlay.insert(entry);
  try {
    // Two frames: one to lay out and paint, one to guarantee the paint has
    // actually landed before the boundary is captured.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 3);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (byteData == null) return;

    final bytes = byteData.buffer.asUint8List();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: 'settlement-${settlement.id.substring(0, 8)}.png',
            mimeType: 'image/png',
          ),
        ],
        subject: l10n.settlementDetails,
      ),
    );
  } finally {
    entry.remove();
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.settlement,
    required this.partyName,
    required this.l10n,
  });

  final Settlement settlement;
  final String? partyName;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(AppSpace.xl),
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              KitchenInMark(size: 28),
              SizedBox(width: AppSpace.sm),
              Text(
                'Kitchen IN',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xl),
          if (partyName != null && partyName!.isNotEmpty) ...[
            Text(
              partyName!,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textMuted,
              ),
            ),
            const SizedBox(height: 4),
          ],
          Row(
            children: [
              if (settlement.isEarly) ...[
                const Icon(
                  Icons.bolt_rounded,
                  size: 20,
                  color: AppColors.amberInk,
                ),
                const SizedBox(width: 2),
              ],
              Text(
                formatMoney(settlement.amount),
                style: AppType.mono(32, weight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            settlementStatusLabel(context, settlement.status),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              color: AppColors.successInk,
            ),
          ),
          if (settlement.isEarly) ...[
            const SizedBox(height: AppSpace.md),
            _row(l10n.grossAmount, formatMoney(settlement.grossAmount)),
            _row(l10n.feeLabel, '-${formatMoney(settlement.fee)}'),
          ],
          const SizedBox(height: AppSpace.xl),
          const Divider(color: AppColors.borderSoft, height: 1),
          const SizedBox(height: AppSpace.md),
          _row(
            l10n.settlementMethod,
            settlementMethodLabel(context, settlement.method),
          ),
          _row(
            l10n.settlementRecordedOn,
            '${settlement.createdAt.day}/${settlement.createdAt.month}/${settlement.createdAt.year}',
          ),
          if (settlement.completedAt != null)
            _row(
              l10n.settlementCompletedOn,
              '${settlement.completedAt!.day}/${settlement.completedAt!.month}/${settlement.completedAt!.year}',
            ),
          if (settlement.reference != null && settlement.reference!.isNotEmpty)
            _row(l10n.settlementReference, settlement.reference!),
          const SizedBox(height: AppSpace.md),
          const Divider(color: AppColors.borderSoft, height: 1),
          const SizedBox(height: AppSpace.md),
          Text(
            l10n.settlementId,
            style: const TextStyle(fontSize: 10.5, color: AppColors.textFaint),
          ),
          Text(
            settlement.id,
            style: AppType.mono(10.5, color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
