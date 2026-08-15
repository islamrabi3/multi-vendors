import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// The two controls that say what the kitchen is doing right now.
///
/// They live here rather than inside the dashboard screen because they are
/// placed in two very different parents — the mobile header's Column and the
/// desktop strip's Row — and getting that placement wrong is not a cosmetic
/// mistake but a hard layout error (see [StoreOpenToggle.expand]). A shared,
/// public home is also what lets a test pump them in both shapes.

/// The open/closed switch.
///
/// Full-width so the store's own state is never a detail in the corner —
/// unless [expand] says otherwise.
class StoreOpenToggle extends StatelessWidget {
  const StoreOpenToggle({
    super.key,
    required this.isOpen,
    required this.busy,
    required this.onChanged,
    this.outsideHours = false,
    this.closingTime,
    this.expand = true,
  });

  /// The owner's own switch. Left as-is when the timetable closes the store, so
  /// tomorrow's opening does not need anyone to come back and flip it.
  final bool isOpen;

  /// The switch is on but today's hours have it shut anyway.
  final bool outsideHours;

  /// Today's closing time, `HH:MM`, when there is one.
  final String? closingTime;

  final bool busy;
  final ValueChanged<bool> onChanged;

  /// Whether to fill the width it is offered (the mobile header, where this
  /// is a child of a Column) or shrink to its own content (the desktop
  /// strip, where it sits at the end of a Row beside other controls).
  ///
  /// This is not cosmetic. A Row measures its non-flex children with an
  /// **unbounded** width first, and a tight flex child under an unbounded
  /// width is a hard layout error, not an overflow warning — it took the
  /// whole vendor dashboard down to a blank pane on web. Shrink-wrapping
  /// needs `MainAxisSize.min` and a loose `Flexible`, which is what
  /// `expand: false` switches to.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trading = isOpen && !outsideHours;
    final accent = trading
        ? AppColors.onDarkSuccess
        : outsideHours
        ? AppColors.amberInk
        : AppColors.navInactive;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.sm,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.inkElevated,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpace.sm),
          // Flexible, not Expanded, when shrink-wrapping: the label still
          // ellipsises if it runs out of room, but it no longer demands
          // space that an unbounded measuring pass cannot offer.
          Flexible(
            fit: expand ? FlexFit.tight : FlexFit.loose,
            child: Text(
              outsideHours
                  ? l10n.closedOutsideHours
                  : trading && closingTime != null
                  ? l10n.openUntil(closingTime!)
                  : isOpen
                  ? l10n.open
                  : l10n.closed,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          SizedBox(
            width: 44,
            height: 26,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(5),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: isOpen,
                      onChanged: onChanged,
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppColors.onDarkTrack,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Busy mode as a single press, for the web strip.
///
/// Deliberately not a second switch beside [StoreOpenToggle]: two switches in
/// a row read as equally weighted, and these are not — open/closed is the
/// store's state, busy is a temporary brake on it. A button that lights up
/// when engaged says that without a label explaining it.
///
/// Always shrink-wraps, so it is safe as a non-flex child of a Row.
class StoreBusyToggle extends StatelessWidget {
  const StoreBusyToggle({
    super.key,
    required this.isBusy,
    required this.pending,
    required this.onChanged,
  });

  final bool isBusy;
  final bool pending;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Tooltip(
      message: l10n.busyMode,
      child: Material(
        color: isBusy ? AppColors.amberFill : AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          onTap: pending ? null : () => onChanged(!isBusy),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md,
              vertical: AppSpace.sm,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              border: Border.all(
                color: isBusy ? AppColors.amberInk : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: pending
                      ? const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.amberInk,
                        )
                      : Icon(
                          Icons.local_fire_department_outlined,
                          size: 16,
                          color: isBusy
                              ? AppColors.amberInk
                              : AppColors.textMuted,
                        ),
                ),
                const SizedBox(width: 6),
                // Loose, so a caller that hands this less than its intrinsic
                // width gets an ellipsis instead of an overflow stripe.
                Flexible(
                  child: Text(
                    l10n.busyStore,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isBusy
                          ? AppColors.amberInk
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
