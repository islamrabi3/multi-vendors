import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/utils/money.dart';
import 'home_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Store filters, edited on a local copy so the list behind the sheet does not
/// churn on every tap. Returns null when the customer backs out, so the caller
/// can tell "cancelled" from "cleared everything".
/// [canSortByDistance] is false while the customer has no pinned address or no
/// store has coordinates; the "nearest" option is then hidden rather than
/// offered as a sort that would silently do nothing.
Future<VendorFilters?> showVendorFiltersSheet(
  BuildContext context,
  VendorFilters current, {
  bool canSortByDistance = false,
}) {
  return showModalBottomSheet<VendorFilters>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _VendorFiltersSheet(
      initial: current,
      canSortByDistance: canSortByDistance,
    ),
  );
}

class _VendorFiltersSheet extends StatefulWidget {
  const _VendorFiltersSheet({
    required this.initial,
    required this.canSortByDistance,
  });

  final VendorFilters initial;
  final bool canSortByDistance;

  @override
  State<_VendorFiltersSheet> createState() => _VendorFiltersSheetState();
}

class _VendorFiltersSheetState extends State<_VendorFiltersSheet> {
  late VendorFilters _draft = widget.initial;

  /// Delivery-fee ceilings offered as chips. Null is "any".
  static const _feeSteps = <double?>[null, 10, 20, 30];

  /// Rating floors offered as chips. Null is "any".
  static const _ratingSteps = <double?>[null, 3, 4, 4.5];

  String _sortLabel(BuildContext context, VendorSort sort) => switch (sort) {
        VendorSort.recommended => context.l10n.sortRecommended,
        VendorSort.nearest => context.l10n.sortNearest,
        VendorSort.rating => context.l10n.sortRating,
        VendorSort.deliveryFee => context.l10n.sortDeliveryFee,
        VendorSort.prepTime => context.l10n.sortPrepTime,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpace.xl,
          right: AppSpace.xl,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(context.l10n.filters, style: AppType.heading(19)),
                  ),
                  if (_draft.activeCount > 0)
                    TextButton(
                      onPressed: () =>
                          setState(() => _draft = const VendorFilters()),
                      child: Text(context.l10n.clearAll),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.md),

              _SectionLabel(context.l10n.sortBy),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final sort in VendorSort.values.where((s) =>
                      s != VendorSort.nearest || widget.canSortByDistance))
                    _Chip(
                      label: _sortLabel(context, sort),
                      selected: _draft.sort == sort,
                      onTap: () => setState(
                          () => _draft = _draft.copyWith(sort: sort)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),

              _SectionLabel(context.l10n.showOnly),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  _Chip(
                    label: context.l10n.openStoresOnly,
                    icon: Icons.storefront_outlined,
                    selected: _draft.openOnly,
                    onTap: () => setState(() =>
                        _draft = _draft.copyWith(openOnly: !_draft.openOnly)),
                  ),
                  _Chip(
                    label: context.l10n.freeDeliveryOnly,
                    icon: Icons.delivery_dining_outlined,
                    selected: _draft.freeDeliveryOnly,
                    onTap: () => setState(() => _draft = _draft.copyWith(
                        freeDeliveryOnly: !_draft.freeDeliveryOnly)),
                  ),
                  _Chip(
                    label: context.l10n.favoritesOnly,
                    icon: Icons.favorite_border,
                    selected: _draft.favoritesOnly,
                    onTap: () => setState(() => _draft = _draft.copyWith(
                        favoritesOnly: !_draft.favoritesOnly)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),

              _SectionLabel(context.l10n.maxDeliveryFee),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final fee in _feeSteps)
                    _Chip(
                      label: fee == null
                          ? context.l10n.any
                          : '≤ ${formatMoney(fee)}',
                      selected: _draft.maxDeliveryFee == fee,
                      onTap: () => setState(() => _draft = fee == null
                          ? _draft.copyWith(clearMaxDeliveryFee: true)
                          : _draft.copyWith(maxDeliveryFee: fee)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),

              _SectionLabel(context.l10n.minimumRating),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: [
                  for (final rating in _ratingSteps)
                    _Chip(
                      label: rating == null
                          ? context.l10n.any
                          : '${rating.toStringAsFixed(rating % 1 == 0 ? 0 : 1)}+',
                      icon: rating == null ? null : Icons.star_rounded,
                      selected: _draft.minRating == rating,
                      onTap: () => setState(() => _draft = rating == null
                          ? _draft.copyWith(clearMinRating: true)
                          : _draft.copyWith(minRating: rating)),
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.xxl),

              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                onPressed: () => Navigator.pop(context, _draft),
                child: Text(context.l10n.showResults),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: AppColors.textFaint)),
      );
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md + 2, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.surface,
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15,
                  color: selected ? Colors.white : AppColors.textSecondary),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : AppColors.ink)),
          ],
        ),
      ),
    );
  }
}
