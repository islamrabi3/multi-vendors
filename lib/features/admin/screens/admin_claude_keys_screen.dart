import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_mcp_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/time_format.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../auth/auth_cubit.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

/// Keys that let Claude work this console on the admin's behalf.
///
/// A key is the admin, as far as the server is concerned: it carries their
/// permissions and nothing more, and whatever is done with it lands in the
/// admin log under their name, marked as Claude's doing. So the page says two
/// things plainly — the key is shown once, and revoking it is immediate.
class AdminClaudeKeysScreen extends StatefulWidget {
  const AdminClaudeKeysScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminClaudeKeysScreen> createState() => _AdminClaudeKeysScreenState();
}

class _AdminClaudeKeysScreenState extends State<AdminClaudeKeysScreen> {
  final _repository = AdminMcpRepository();

  bool _loading = true;
  Object? _error;
  List<AdminMcpKey> _keys = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final keys = await _repository.fetchKeys();
      if (!mounted) return;
      setState(() {
        _keys = keys;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final request = await showDialog<({String name, int days})>(
      context: context,
      builder: (_) => const _NewKeyDialog(),
    );
    if (request == null || !mounted) return;

    try {
      final key = await _repository.createKey(
        name: request.name,
        days: request.days,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        // Closing by a stray tap outside would lose a key that cannot be
        // shown again.
        barrierDismissible: false,
        builder: (_) => _KeyRevealDialog(keyText: key),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      if ('$error'.contains('TOO_MANY_KEYS')) {
        showSnack(context, context.l10n.claudeKeyTooMany, error: true);
      } else {
        showFailure(context, error);
      }
    }
  }

  Future<void> _revoke(AdminMcpKey key) async {
    final l10n = context.l10n;
    final done = await showConfirmDialog(
      context: context,
      title: l10n.claudeKeyRevokeTitle,
      message: l10n.claudeKeyRevokeBody(key.name),
      confirmLabel: l10n.claudeKeyRevoke,
      cancelLabel: l10n.cancel,
      tone: AppDialogTone.danger,
      icon: Icons.key_off_rounded,
      onConfirm: () => _repository.revokeKey(key.id),
    );
    if (!done || !mounted) return;
    showSnack(context, l10n.claudeKeyRevokedToast);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final myId = context.watch<AuthCubit>().state.profile?.id;

    final Widget content;
    if (_loading) {
      content = const LoadingView();
    } else if (_error != null) {
      content = ErrorView(
        message: errorText(context, _error!),
        onRetry: () {
          setState(() => _loading = true);
          _load();
        },
      );
    } else {
      content = ListView(
        padding: const EdgeInsets.all(AppSpace.gutter),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.claudeKeysIntro,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                FilledButton.icon(
                  onPressed: _create,
                  icon: const Icon(Icons.add_rounded),
                  label: Text(l10n.claudeKeyCreate),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          if (_keys.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.xxl),
              child: EmptyView(
                message: l10n.claudeKeysEmpty,
                icon: Icons.key_outlined,
              ),
            )
          else
            for (final key in _keys)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: _KeyTile(
                  keyInfo: key,
                  // Somebody else's key is only ever listed for whoever
                  // manages staff; say whose it is.
                  ownerName: key.adminId == myId ? null : key.ownerName,
                  onRevoke: key.isLive ? () => _revoke(key) : null,
                ),
              ),
        ],
      );
    }

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: content,
          ),
        ),
      );
    }

    if (AppBreakpoints.isWebWide(context)) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/claude-keys',
        sections: adminManageWebSections(context),
        pageTitle: l10n.claudeKeys,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: content,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.claudeKeys)),
      body: SafeArea(top: false, child: content),
    );
  }
}

class _KeyTile extends StatelessWidget {
  const _KeyTile({required this.keyInfo, this.ownerName, this.onRevoke});

  final AdminMcpKey keyInfo;
  final String? ownerName;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final key = keyInfo;

    final (label, fill, ink) = key.isRevoked
        ? (
            l10n.claudeKeyStatusRevoked,
            AppColors.dangerFill,
            AppColors.dangerInk,
          )
        : key.isExpired
        ? (
            l10n.claudeKeyStatusExpired,
            AppColors.dangerFill,
            AppColors.dangerInk,
          )
        : (l10n.active, AppColors.successFill, AppColors.successInk);

    final details = [
      ?ownerName,
      key.lastUsedAt == null
          ? l10n.claudeKeyNeverUsed
          : l10n.claudeKeyLastUsed(formatDateTime(context, key.lastUsedAt!)),
      if (key.isLive && key.expiresAt != null)
        l10n.claudeKeyExpiresOn(formatDateTime(context, key.expiresAt!)),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            key.isLive ? Icons.key_rounded : Icons.key_off_rounded,
            color: key.isLive ? AppColors.ink : AppColors.textFaint,
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        key.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.heading(15),
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: fill,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${key.prefix}…',
                  textDirection: TextDirection.ltr,
                  style: AppType.mono(12.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  details.join(' · '),
                  style: const TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (onRevoke != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: AppColors.dangerInk),
              onPressed: onRevoke,
              child: Text(l10n.claudeKeyRevoke),
            ),
        ],
      ),
    );
  }
}

/// Asks what to call the key and how long it should last.
class _NewKeyDialog extends StatefulWidget {
  const _NewKeyDialog();

  @override
  State<_NewKeyDialog> createState() => _NewKeyDialogState();
}

class _NewKeyDialogState extends State<_NewKeyDialog> {
  final _name = TextEditingController();
  int _days = 90;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.pop(context, (name: name, days: _days));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.claudeKeyCreate),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: 60,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.claudeKeyName,
                hintText: l10n.claudeKeyNameHint,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            DropdownButtonFormField<int>(
              initialValue: _days,
              decoration: InputDecoration(labelText: l10n.claudeKeyExpiry),
              items: [
                for (final days in const [7, 30, 90, 365])
                  DropdownMenuItem(
                    value: days,
                    child: Text(l10n.claudeKeyDays(days)),
                  ),
              ],
              onChanged: (days) => setState(() => _days = days ?? _days),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _name.text.trim().isEmpty ? null : _submit,
          child: Text(l10n.claudeKeyCreate),
        ),
      ],
    );
  }
}

/// Shows a new key, once, with the command that connects Claude Code.
class _KeyRevealDialog extends StatelessWidget {
  const _KeyRevealDialog({required this.keyText});

  final String keyText;

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.copiedLabel)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final command = AdminMcpRepository.connectCommand(keyText);

    Widget box(String text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText(
        text,
        textDirection: TextDirection.ltr,
        style: AppType.mono(12.5, color: AppColors.ink),
      ),
    );

    return AlertDialog(
      title: Text(l10n.claudeKeyCreatedTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.claudeKeyCreatedBody,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              box(keyText),
              const SizedBox(height: AppSpace.lg),
              Text(l10n.claudeKeyConnect, style: AppType.heading(14)),
              const SizedBox(height: AppSpace.sm),
              box(command),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _copy(context, keyText),
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: Text(l10n.claudeKeyCopyKey),
        ),
        TextButton.icon(
          onPressed: () => _copy(context, command),
          icon: const Icon(Icons.terminal_rounded, size: 18),
          label: Text(l10n.claudeKeyCopyCommand),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
