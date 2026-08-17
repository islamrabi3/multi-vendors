import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

/// A desktop-shaped alert for the vendor and admin consoles.
///
/// A `SnackBar` is a phone affordance: it pins a low-contrast bar to the
/// bottom edge, which on a 1400px console is the furthest point from wherever
/// the operator is actually looking, and it holds one line of text. "New
/// order received!" told a kitchen that *something* arrived and nothing about
/// what — no number, no total, and no way to open it.
///
/// This is the same alert rewritten for a window: top corner, room for the
/// facts, and an action. It stacks, so three orders landing together are three
/// cards rather than one message replacing the last.
class WebToast {
  WebToast._();

  static final List<OverlayEntry> _entries = [];

  /// Shows [title] with optional detail and a primary action.
  ///
  /// Returns immediately; the card removes itself after [duration] unless the
  /// pointer is over it — reading a toast should not be a race against its
  /// own timer.
  static void show(
    BuildContext context, {
    required String title,
    String? detail,
    String? trailingValue,
    IconData icon = Icons.notifications_active_rounded,
    Color tone = AppColors.primary,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 8),
  }) {
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastCard(
        title: title,
        detail: detail,
        trailingValue: trailingValue,
        icon: icon,
        tone: tone,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        // Index is read at build time so the cards below close the gap when
        // one above them is dismissed, rather than leaving a hole.
        indexOf: () => _entries.indexOf(entry),
        onDismiss: () => _remove(entry),
      ),
    );

    _entries.add(entry);
    overlay.insert(entry);

    // Four is about what fits down the side of a laptop screen; past that the
    // oldest goes rather than the stack running off the bottom.
    if (_entries.length > 4) _remove(_entries.first);
  }

  static void _remove(OverlayEntry entry) {
    if (!_entries.remove(entry)) return;
    entry.remove();
    // Every surviving card's offset depends on its position in the list.
    for (final remaining in _entries) {
      remaining.markNeedsBuild();
    }
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.title,
    required this.detail,
    required this.trailingValue,
    required this.icon,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.duration,
    required this.indexOf,
    required this.onDismiss,
  });

  final String title;
  final String? detail;
  final String? trailingValue;
  final IconData icon;
  final Color tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Duration duration;
  final int Function() indexOf;
  final VoidCallback onDismiss;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..forward();

  Timer? _timer;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer(widget.duration, () {
      if (_hovered) {
        // Still being read. Check again rather than closing under the cursor.
        _startTimer();
        return;
      }
      _close();
    });
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) {
      widget.onDismiss();
      return;
    }
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.indexOf();
    // Removed mid-animation: nothing to place.
    if (index < 0) return const SizedBox.shrink();

    return PositionedDirectional(
      // Below the console's 64px top bar, aligned to the same edge as the
      // avatar menu — the corner an operator already looks to for status.
      top: 76 + index * 92.0,
      end: AppSpace.xl,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.25, 0),
          end: Offset.zero,
        ).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        ),
        child: FadeTransition(
          opacity: _controller,
          child: MouseRegion(
            onEnter: (_) => _hovered = true,
            onExit: (_) => _hovered = false,
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: AppColors.border),
                  // The one place a shadow earns its keep: this floats over
                  // the page rather than sitting in it.
                  boxShadow: AppShadows.raised,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.tone.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadii.sm),
                      ),
                      child: Icon(widget.icon, size: 19, color: widget.tone),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: AppColors.ink,
                                  ),
                                ),
                              ),
                              if (widget.trailingValue != null) ...[
                                const SizedBox(width: AppSpace.sm),
                                Text(
                                  widget.trailingValue!,
                                  style: AppType.mono(
                                    14,
                                    weight: FontWeight.w800,
                                    color: widget.tone,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (widget.detail != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.detail!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                          if (widget.actionLabel != null) ...[
                            const SizedBox(height: 4),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                onPressed: () {
                                  _close();
                                  widget.onAction?.call();
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(widget.actionLabel!),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _close,
                      icon: const Icon(Icons.close_rounded, size: 16),
                      color: AppColors.textFaint,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 28,
                        height: 28,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
