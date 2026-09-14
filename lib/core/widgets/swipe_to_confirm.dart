import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/tokens.dart';

/// A track the user drags a thumb across to confirm an action that cannot be
/// undone. A plain button is too easy to hit by accident from a pocket or a
/// bumpy ride; a deliberate swipe is not.
///
/// Follows the reading direction: the thumb starts on the leading side, so in
/// Arabic it is dragged right-to-left.
class SwipeToConfirm extends StatefulWidget {
  const SwipeToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.color = AppColors.success,
    this.icon = Icons.done_all_rounded,
    this.busy = false,
    this.height = 60,
  });

  final String label;
  final VoidCallback onConfirmed;
  final Color color;
  final IconData icon;
  final bool busy;
  final double height;

  @override
  State<SwipeToConfirm> createState() => _SwipeToConfirmState();
}

class _SwipeToConfirmState extends State<SwipeToConfirm>
    with SingleTickerProviderStateMixin {
  static const _threshold = 0.82;

  late final AnimationController _reset =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 260),
      )..addListener(
        () => setState(() => _progress = _resetFrom * (1 - _reset.value)),
      );

  double _progress = 0;
  double _resetFrom = 0;

  @override
  void dispose() {
    _reset.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(SwipeToConfirm old) {
    super.didUpdateWidget(old);
    // Spring back once the action has finished, whatever its outcome, so the
    // control is usable again if the screen stays.
    if (old.busy && !widget.busy) _snapBack();
  }

  void _snapBack() {
    _resetFrom = _progress;
    _reset.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = widget.height;
        final thumb = height - 8;
        final travel = (constraints.maxWidth - thumb - 8).clamp(
          1.0,
          double.infinity,
        );
        final offset = travel * _progress;

        return Container(
          height: height,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(height / 2),
            border: Border.all(color: widget.color.withValues(alpha: 0.35)),
          ),
          child: Stack(
            children: [
              // Fill that follows the thumb.
              PositionedDirectional(
                start: 0,
                top: 0,
                bottom: 0,
                width: offset + thumb + 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsetsDirectional.only(start: thumb * 0.8),
                  child: Opacity(
                    opacity: (1 - _progress * 1.6).clamp(0.0, 1.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: widget.color,
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Transform.flip(
                          flipX: rtl,
                          child: Icon(
                            Icons.keyboard_double_arrow_right_rounded,
                            color: widget.color.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                start: 4 + offset,
                top: 4,
                child: GestureDetector(
                  onHorizontalDragUpdate: widget.busy
                      ? null
                      : (d) {
                          final delta = rtl ? -d.delta.dx : d.delta.dx;
                          setState(() {
                            _progress = (_progress + delta / travel).clamp(
                              0.0,
                              1.0,
                            );
                          });
                        },
                  onHorizontalDragEnd: widget.busy
                      ? null
                      : (_) {
                          if (_progress >= _threshold) {
                            setState(() => _progress = 1);
                            HapticFeedback.mediumImpact();
                            widget.onConfirmed();
                            // The caller may open a sheet and come back without
                            // doing anything; the thumb must not stay stuck.
                            Future.delayed(
                              const Duration(milliseconds: 600),
                              () {
                                if (mounted && !widget.busy) _snapBack();
                              },
                            );
                          } else {
                            _snapBack();
                          }
                        },
                  child: Container(
                    width: thumb,
                    height: thumb,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: widget.busy
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: widget.color,
                            ),
                          )
                        : _progress >= _threshold
                        ? Icon(widget.icon, color: widget.color)
                        // Mirrors itself in RTL (matchTextDirection).
                        : Icon(
                            Icons.arrow_forward_rounded,
                            color: widget.color,
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
