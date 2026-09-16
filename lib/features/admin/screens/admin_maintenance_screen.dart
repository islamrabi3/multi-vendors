import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/platform_settings_repository.dart';
import '../../../core/services/maintenance_gate.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../../../core/widgets/web/web_shell_frame.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

/// Closes the platform to everyone but staff, with a message the admin writes.
///
/// Both halves matter: the switch reaches phones that are already open, and
/// the server refuses new orders while it is on, so a stale app cannot place
/// one through a screen it is still showing.
class AdminMaintenanceScreen extends StatefulWidget {
  const AdminMaintenanceScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminMaintenanceScreen> createState() => _AdminMaintenanceScreenState();
}

class _AdminMaintenanceScreenState extends State<AdminMaintenanceScreen> {
  final _repository = PlatformSettingsRepository();
  final _message = TextEditingController();
  final _messageAr = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _messageAr.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final status = await _repository.maintenanceStatus();
      if (!mounted) return;
      setState(() {
        _enabled = status.enabled;
        _message.text = status.message ?? '';
        _messageAr.text = status.messageAr ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailure(context, error);
    }
  }

  Future<void> _save({required bool enabled}) async {
    setState(() => _saving = true);
    try {
      await _repository.setMaintenanceMode(
        enabled: enabled,
        message: _message.text.trim(),
        messageAr: _messageAr.text.trim(),
      );
      await MaintenanceGate.instance.refresh();
      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _saving = false;
      });
      showSnack(
        context,
        enabled
            ? context.l10n.maintenanceOnToast
            : context.l10n.maintenanceOffToast,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final content = _loading
        ? const LoadingView()
        : ListView(
            padding: const EdgeInsets.all(AppSpace.gutter),
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: _enabled ? AppColors.dangerFill : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(
                    color: _enabled ? AppColors.dangerInk : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _enabled
                          ? Icons.build_circle_rounded
                          : Icons.check_circle_rounded,
                      color: _enabled
                          ? AppColors.dangerInk
                          : AppColors.successInk,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _enabled
                                ? l10n.maintenanceStateOn
                                : l10n.maintenanceStateOff,
                            style: AppType.heading(16),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.maintenanceScope,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              TextField(
                controller: _messageAr,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '${l10n.maintenanceMessage} · ${l10n.arabic}',
                  hintText: l10n.maintenanceBody,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _message,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: '${l10n.maintenanceMessage} · ${l10n.english}',
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              if (_enabled) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _saving ? null : () => _save(enabled: true),
                  icon: _saving
                      ? const ButtonSpinner(size: 18)
                      : const Icon(Icons.save_rounded),
                  label: Text(l10n.maintenanceSaveMessage),
                ),
                const SizedBox(height: AppSpace.sm),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: AppColors.successInk,
                    side: const BorderSide(color: AppColors.successInk),
                  ),
                  onPressed: _saving ? null : () => _save(enabled: false),
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  label: Text(l10n.maintenanceTurnOff),
                ),
              ] else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    backgroundColor: AppColors.dangerInk,
                  ),
                  onPressed: _saving ? null : () => _save(enabled: true),
                  icon: _saving
                      ? const ButtonSpinner(size: 18)
                      : const Icon(Icons.build_rounded),
                  label: Text(l10n.maintenanceTurnOn),
                ),
            ],
          );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: content,
          ),
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/maintenance',
        sections: adminManageWebSections(context),
        pageTitle: l10n.maintenanceTitle,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: content,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.maintenanceTitle)),
      body: SafeArea(top: false, child: content),
    );
  }
}
