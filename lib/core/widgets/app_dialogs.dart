import 'package:flutter/material.dart';

import '../../app/tokens.dart';
import 'common.dart' show readableError;
import 'skeleton.dart' show ButtonSpinner;

/// How loud a dialog is. Drives the medallion colours and the primary button.
///
/// `danger` is for actions that destroy something the user cannot get back —
/// not for "are you sure?" in general. Over-using it means the one dialog that
/// really is destructive reads like all the others.
enum AppDialogTone { neutral, primary, danger }

const _kMaxWidth = 420.0;
const _kActionHeight = 48.0;
const _kInsetPadding =
    EdgeInsets.symmetric(horizontal: AppSpace.xxl, vertical: 40);

({Color fill, Color ink}) _palette(AppDialogTone tone) => switch (tone) {
      AppDialogTone.primary => (
          fill: AppColors.warmFill,
          ink: AppColors.primary
        ),
      AppDialogTone.danger => (
          fill: AppColors.dangerFill,
          ink: AppColors.dangerInk
        ),
      AppDialogTone.neutral => (
          fill: AppColors.neutralFill,
          ink: AppColors.textSecondary
        ),
    };

// ===========================================================================
// Confirm
// ===========================================================================

/// A yes/no question. Resolves to true only if the user pressed confirm — a
/// barrier tap, a back gesture and cancel all resolve to false, so callers
/// never have to null-check.
///
/// [confirmLabel] and [cancelLabel] are required on purpose: defaulting them to
/// English shipped `Confirm` / `Cancel` to Arabic users.
///
/// Pass [onConfirm] to run the work *inside* the dialog: the primary button
/// spins, the actions disable, and the dialog only pops once the future
/// completes. Omit it to just get the answer back.
Future<bool> showConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  AppDialogTone tone = AppDialogTone.primary,
  IconData? icon,
  Future<void> Function()? onConfirm,
}) =>
    _confirm(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      tone: tone,
      icon: icon,
      onConfirm: onConfirm,
    );

/// The implementation both [showConfirmDialog] and the legacy
/// `AppDialogs.showConfirmDialog` call. Private because inside that class the
/// bare name `showConfirmDialog` resolves to its own static member, not here.
Future<bool> _confirm({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  required String cancelLabel,
  AppDialogTone tone = AppDialogTone.primary,
  IconData? icon,
  Future<void> Function()? onConfirm,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: onConfirm == null,
    builder: (_) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      tone: tone,
      icon: icon,
      onConfirm: onConfirm,
    ),
  );
  return result ?? false;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.tone,
    required this.icon,
    required this.onConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final AppDialogTone tone;
  final IconData? icon;
  final Future<void> Function()? onConfirm;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _confirm() async {
    final work = widget.onConfirm;
    if (work == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DialogShell(
      busy: _busy,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.icon != null) ...[
            Center(child: _Medallion(icon: widget.icon!, tone: widget.tone)),
            const SizedBox(height: AppSpace.lg),
          ],
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: AppType.heading(19),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_error != null) _InlineError(_error!),
          const SizedBox(height: AppSpace.xxl),
          _ActionRow(
            busy: _busy,
            cancelLabel: widget.cancelLabel,
            onCancel: () => Navigator.pop(context, false),
            submitLabel: widget.confirmLabel,
            onSubmit: _confirm,
            tone: widget.tone,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Form — dialog and sheet share one contract
// ===========================================================================

/// A dialog that collects input.
///
/// [contentBuilder] receives a `rebuild` callback: call it from a chip or toggle
/// inside the form to repaint the dialog without hoisting state into the caller.
///
/// [onSubmit] is awaited *while the dialog stays up*:
///  * returns a value ⇒ the dialog pops with it;
///  * returns null ⇒ the dialog stays open (treat as "not valid yet");
///  * **throws ⇒ the message shows inline above the actions and everything the
///    user typed survives.** Popping first and then doing the async work loses
///    the whole form on any failure — the one moment the user most needs it.
Future<T?> showFormDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  required Widget Function(void Function() rebuild) contentBuilder,
  required String submitLabel,
  required Future<T?> Function() onSubmit,
  String? cancelLabel,
  String? destructiveLabel,
  Future<void> Function()? onDestructive,
}) =>
    _form<T>(
      context: context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      tone: tone,
      contentBuilder: contentBuilder,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      cancelLabel: cancelLabel,
      destructiveLabel: destructiveLabel,
      onDestructive: onDestructive,
    );

/// Shared implementation — see [_confirm] for why this is not the public name.
Future<T?> _form<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  required Widget Function(void Function() rebuild) contentBuilder,
  required String submitLabel,
  required Future<T?> Function() onSubmit,
  String? cancelLabel,
  String? destructiveLabel,
  Future<void> Function()? onDestructive,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _FormBody<T>(
      title: title,
      subtitle: subtitle,
      icon: icon,
      tone: tone,
      contentBuilder: contentBuilder,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      cancelLabel: cancelLabel,
      destructiveLabel: destructiveLabel,
      onDestructive: onDestructive,
      asSheet: false,
    ),
  );
}

/// [showFormDialog]'s contract, rendered as a bottom sheet — for forms that want
/// keyboard-adjacent placement, or simply belong at the bottom edge on a phone.
/// Replaces hand-rolled sheet scaffolds so the anatomy lives in one place.
Future<T?> showFormSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  required Widget Function(void Function() rebuild) contentBuilder,
  required String submitLabel,
  required Future<T?> Function() onSubmit,
  String? cancelLabel,
  String? destructiveLabel,
  Future<void> Function()? onDestructive,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: AppColors.surface,
    builder: (_) => _FormBody<T>(
      title: title,
      subtitle: subtitle,
      icon: icon,
      tone: tone,
      contentBuilder: contentBuilder,
      submitLabel: submitLabel,
      onSubmit: onSubmit,
      cancelLabel: cancelLabel,
      destructiveLabel: destructiveLabel,
      onDestructive: onDestructive,
      asSheet: true,
    ),
  );
}

class _FormBody<T> extends StatefulWidget {
  const _FormBody({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.tone,
    required this.contentBuilder,
    required this.submitLabel,
    required this.onSubmit,
    required this.cancelLabel,
    required this.destructiveLabel,
    required this.onDestructive,
    required this.asSheet,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final AppDialogTone tone;
  final Widget Function(void Function() rebuild) contentBuilder;
  final String submitLabel;
  final Future<T?> Function() onSubmit;
  final String? cancelLabel;
  final String? destructiveLabel;
  final Future<void> Function()? onDestructive;
  final bool asSheet;

  @override
  State<_FormBody<T>> createState() => _FormBodyState<T>();
}

class _FormBodyState<T> extends State<_FormBody<T>> {
  bool _busy = false;
  String? _error;

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await widget.onSubmit();
      if (!mounted) return;
      if (value == null) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context, value);
    } catch (error) {
      if (!mounted) return;
      // Stay up: the user's input is not ours to throw away.
      setState(() {
        _busy = false;
        _error = readableError(error);
      });
    }
  }

  Future<void> _destruct() async {
    final work = widget.onDestructive;
    if (work == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = readableError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.icon != null) ...[
              _Medallion(icon: widget.icon!, tone: widget.tone, size: 44),
              const SizedBox(width: AppSpace.md + 2),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title, style: AppType.heading(19)),
                  if (widget.subtitle != null) ...[
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      widget.subtitle!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.xl),
        widget.contentBuilder(_rebuild),
        if (_error != null) _InlineError(_error!),
        const SizedBox(height: AppSpace.xxl),
        _ActionRow(
          busy: _busy,
          cancelLabel: widget.cancelLabel,
          onCancel: () => Navigator.pop(context),
          submitLabel: widget.submitLabel,
          onSubmit: _submit,
          tone: widget.tone,
        ),
        if (widget.destructiveLabel != null) ...[
          const SizedBox(height: AppSpace.xs),
          // Full width, below the row — never shoulder-to-shoulder with Save,
          // where a mis-tap destroys what the user just finished editing.
          SizedBox(
            height: _kActionHeight,
            child: TextButton(
              onPressed: _busy ? null : _destruct,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.dangerInk,
              ),
              child: Text(widget.destructiveLabel!),
            ),
          ),
        ],
      ],
    );

    if (!widget.asSheet) {
      return _DialogShell(busy: _busy, child: content);
    }
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: AppSpace.xxl,
            right: AppSpace.xxl,
            top: AppSpace.xxl,
            bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpace.xxl,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kMaxWidth),
              child: SingleChildScrollView(child: content),
            ),
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// Info
// ===========================================================================

/// A dialog with nothing to decide — an offer's terms, an announcement.
/// One button, and it just closes.
Future<void> showInfoDialog({
  required BuildContext context,
  required String title,
  String? message,
  IconData? icon,
  AppDialogTone tone = AppDialogTone.primary,
  Widget? artwork,
  required String dismissLabel,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _DialogShell(
      busy: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (icon != null) ...[
            Center(child: _Medallion(icon: icon, tone: tone)),
            const SizedBox(height: AppSpace.lg),
          ],
          Text(title, textAlign: TextAlign.center, style: AppType.heading(19)),
          if (artwork != null) ...[
            const SizedBox(height: AppSpace.lg),
            artwork,
          ],
          if (message != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(dialogContext).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpace.xxl),
          SizedBox(
            height: _kActionHeight,
            child: FilledButton(
              style: _submitStyle(tone),
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dismissLabel),
            ),
          ),
        ],
      ),
    ),
  );
}

// ===========================================================================
// Anatomy
// ===========================================================================

/// The box every dialog variant lives in: one surface, one corner, one shadow.
class _DialogShell extends StatelessWidget {
  const _DialogShell({required this.child, required this.busy});

  final Widget child;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // A dialog mid-submit must not be dismissed out from under the request.
      canPop: !busy,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: _kInsetPadding,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _kMaxWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.xxl),
              boxShadow: AppShadows.dialog,
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpace.xxl),
              child: SingleChildScrollView(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _Medallion extends StatelessWidget {
  const _Medallion({required this.icon, required this.tone, this.size = 56});

  final IconData icon;
  final AppDialogTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = _palette(tone);
    // The big centred medallion is a circle; the compact one beside a title is
    // a rounded tile, so its edge lines up with the text block next to it.
    final isCircle = size >= 56;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.fill,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(AppRadii.md),
      ),
      child: Icon(icon, color: palette.ink, size: size * 0.5),
    );
  }
}

/// Actions are always `[cancel, submit]` in code order inside a [Row] of
/// [Expanded]s — RTL flips the row for free, so the primary always lands on the
/// trailing edge where the thumb expects it, in both languages.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.busy,
    required this.cancelLabel,
    required this.onCancel,
    required this.submitLabel,
    required this.onSubmit,
    required this.tone,
  });

  final bool busy;
  final String? cancelLabel;
  final VoidCallback onCancel;
  final String submitLabel;
  final VoidCallback onSubmit;
  final AppDialogTone tone;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (cancelLabel != null) ...[
          Expanded(
            child: SizedBox(
              height: _kActionHeight,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(_kActionHeight),
                  side: const BorderSide(color: AppColors.border, width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                ),
                onPressed: busy ? null : onCancel,
                child: Text(cancelLabel!),
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
        ],
        Expanded(
          child: SizedBox(
            height: _kActionHeight,
            child: FilledButton(
              style: _submitStyle(tone),
              onPressed: busy ? null : onSubmit,
              // Swapping the label for a same-height spinner keeps the button
              // exactly where it was when the finger left it.
              child: busy ? const ButtonSpinner() : Text(submitLabel),
            ),
          ),
        ),
      ],
    );
  }
}

ButtonStyle _submitStyle(AppDialogTone tone) => FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(_kActionHeight),
      backgroundColor: tone == AppDialogTone.danger
          ? AppColors.dangerInk
          : AppColors.primary,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
    );

class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
        decoration: BoxDecoration(
          color: AppColors.dangerFill,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 17, color: AppColors.dangerInk),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: AppColors.dangerInk,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Backwards compatibility
// ===========================================================================

/// The pre-redesign entry points, kept alive because admin and vendor screens
/// still call them (and are owned by someone else this cycle). New code should
/// use the top-level functions above.
///
/// Deliberately thin: these forward straight through, so both APIs render the
/// same dialog and there is nothing to keep in sync.
class AppDialogs {
  AppDialogs._();

  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = true,
    IconData icon = Icons.warning_amber_rounded,
  }) {
    return _confirm(
      context: context,
      title: title,
      message: message,
      confirmLabel: confirmText,
      cancelLabel: cancelText,
      tone: isDestructive ? AppDialogTone.danger : AppDialogTone.primary,
      icon: icon,
    );
  }

  /// The old form dialog: content is a plain widget and the caller pops itself
  /// from `onPrimaryPressed`. Because it pops, [onSubmit] here returns null —
  /// this shell never resolves the future itself.
  static Future<T?> showFormDialog<T>({
    required BuildContext context,
    required String title,
    String? subtitle,
    IconData icon = Icons.folder_special_rounded,
    required Widget content,
    required String primaryText,
    required VoidCallback onPrimaryPressed,
    String? secondaryText,
    VoidCallback? onSecondaryPressed,
    String? destructiveText,
    VoidCallback? onDestructivePressed,
  }) {
    return _form<T>(
      context: context,
      title: title,
      subtitle: subtitle,
      icon: icon,
      contentBuilder: (_) => content,
      submitLabel: primaryText,
      cancelLabel: secondaryText,
      destructiveLabel: destructiveText,
      onDestructive: onDestructivePressed == null
          ? null
          : () async => onDestructivePressed(),
      onSubmit: () async {
        onPrimaryPressed();
        return null;
      },
    );
  }
}
