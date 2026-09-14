import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/tokens.dart';

/// A small red count that listens to [count] and hides at zero.
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.compact = false});

  final ValueListenable<int> count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: count,
      builder: (context, value, _) {
        if (value <= 0) return const SizedBox.shrink();
        return Container(
          constraints: BoxConstraints(minWidth: compact ? 18 : 22),
          height: compact ? 18 : 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.dangerInk,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
          child: Text(
            value > 99 ? '99+' : '$value',
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}

/// [child] with a [CountBadge] pinned to its top-end corner.
class WithCountBadge extends StatelessWidget {
  const WithCountBadge({
    super.key,
    required this.count,
    required this.child,
    this.top = -6,
    this.end = -8,
  });

  final ValueListenable<int>? count;
  final Widget child;
  final double top;
  final double end;

  @override
  Widget build(BuildContext context) {
    final listenable = count;
    if (listenable == null) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        PositionedDirectional(
          top: top,
          end: end,
          child: CountBadge(count: listenable, compact: true),
        ),
      ],
    );
  }
}
