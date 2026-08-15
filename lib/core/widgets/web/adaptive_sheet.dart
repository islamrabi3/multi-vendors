import 'package:flutter/material.dart';

import '../../../app/tokens.dart';

/// A modal that is a bottom sheet on a phone and a centred dialog on a wide
/// web window.
///
/// A sheet that slides up from the bottom edge is a thumb affordance: it puts
/// the controls where the hand already is. On a 1400px desktop window that
/// same sheet is a wide, short band pinned to the bottom of the screen, far
/// from the pointer and far from the row that opened it — the single loudest
/// "this is a phone app in a browser tab" tell left in the console once the
/// sidebar persists. Same content, same result type, laid out where a desktop
/// user is already looking.
///
/// Callers keep their existing shape: this returns the same `Future<T?>` the
/// sheet did, completing with whatever `Navigator.pop` was given.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,

  /// Matches `showModalBottomSheet`'s parameter of the same name, and is
  /// ignored in the dialog layout (which is always scroll-capable).
  bool isScrollControlled = true,

  /// The grab handle only means something on a sheet that can be dragged;
  /// the dialog drops it and relies on the barrier and Escape instead.
  bool showDragHandle = false,
  Color? backgroundColor,
  ShapeBorder? shape,

  /// How wide the dialog is allowed to grow. Forms want less than a table
  /// picker does, so the caller decides.
  double maxWidth = 560,
}) {
  if (!AppBreakpoints.isWebWide(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      backgroundColor: backgroundColor,
      shape: shape,
      builder: builder,
    );
  }

  return showDialog<T>(
    context: context,
    barrierColor: AppColors.ink.withValues(alpha: 0.32),
    builder: (context) => Dialog(
      backgroundColor: backgroundColor ?? AppColors.canvas,
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(AppSpace.xl),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          // Sheets are written to sit against a bottom edge and size
          // themselves to their content; capping the height rather than
          // filling it keeps a three-field form from becoming a full-height
          // column of whitespace, while still letting a long list scroll.
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Material(
          color: Colors.transparent,
          // Sheet bodies routinely start with a `SafeArea`/`Padding` sized
          // for a phone's bottom inset. Inside a dialog there is no inset to
          // avoid, and `MediaQuery.viewInsets` still carries the keyboard —
          // which the dialog handles itself — so both are zeroed here rather
          // than every call site being rewritten.
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpace.lg),
                child: builder(context),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
