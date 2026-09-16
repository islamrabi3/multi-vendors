import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import '../utils/l10n_extension.dart';

/// The "Soon" pill on a category that is announced but not open yet.
class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: AppColors.amberFill,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: AppColors.amberInk.withValues(alpha: 0.35)),
      ),
      child: Text(
        context.l10n.soonLabel,
        style: TextStyle(
          fontSize: compact ? 9.5 : 10.5,
          fontWeight: FontWeight.w800,
          height: 1.1,
          color: AppColors.amberInk,
        ),
      ),
    );
  }
}

/// Tapping a coming-soon category explains why nothing opens.
void showComingSoonMessage(BuildContext context, String categoryName) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(context.l10n.categoryComingSoonMessage(categoryName)),
      ),
    );
}
