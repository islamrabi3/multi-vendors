import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/tokens.dart';
import '../../../core/models/platform_config.dart';
import '../../../core/repositories/platform_settings_repository.dart';
import '../../../core/services/platform_config_service.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../../../core/widgets/web/console.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../auth/auth_cubit.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

/// How the whole platform prices delivery, and which currency it runs in.
///
/// Both change what every customer is charged, so both need `finance.adjust`
/// — the server refuses anyone else, and without it this page is read-only.
class AdminPlatformSettingsScreen extends StatefulWidget {
  const AdminPlatformSettingsScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  State<AdminPlatformSettingsScreen> createState() =>
      _AdminPlatformSettingsScreenState();
}

class _AdminPlatformSettingsScreenState
    extends State<AdminPlatformSettingsScreen> {
  final _repo = PlatformSettingsRepository();

  final _baseFee = TextEditingController();
  final _baseKm = TextEditingController();
  final _perKm = TextEditingController();

  String _mode = DeliveryFeeRule.storeMode;
  DeliveryFeeRule _saved = const DeliveryFeeRule();
  List<AppCurrency> _currencies = const [];
  String _activeCode = 'EGP';
  bool _loading = true;
  bool _savingDelivery = false;
  String? _busyCurrency;

  @override
  void initState() {
    super.initState();
    for (final c in [_baseFee, _baseKm, _perKm]) {
      c.addListener(() => setState(() {}));
    }
    _load();
  }

  @override
  void dispose() {
    _baseFee.dispose();
    _baseKm.dispose();
    _perKm.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await PlatformConfigService.instance.refresh();
      final currencies = await _repo.currencies();
      if (!mounted) return;
      final config = PlatformConfigService.instance.current;
      setState(() {
        _saved = config.delivery;
        _mode = config.delivery.mode;
        _baseFee.text = trimZeros(config.delivery.baseFee);
        _baseKm.text = trimZeros(config.delivery.baseKm);
        _perKm.text = trimZeros(config.delivery.perKmFee);
        _currencies = currencies;
        _activeCode = config.currency.code;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailure(context, error);
    }
  }

  double? _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  /// The rule as typed, or null while a number is missing or negative.
  DeliveryFeeRule? get _draft {
    if (_mode == DeliveryFeeRule.storeMode) {
      return DeliveryFeeRule(
        baseFee: _saved.baseFee,
        baseKm: _saved.baseKm,
        perKmFee: _saved.perKmFee,
      );
    }
    final base = _num(_baseFee), km = _num(_baseKm), perKm = _num(_perKm);
    if (base == null || km == null || perKm == null) return null;
    if (base < 0 || km < 0 || perKm < 0) return null;
    return DeliveryFeeRule(
      mode: DeliveryFeeRule.distanceMode,
      baseFee: base,
      baseKm: km,
      perKmFee: perKm,
    );
  }

  Future<void> _saveDelivery() async {
    final rule = _draft;
    if (rule == null) return;
    setState(() => _savingDelivery = true);
    try {
      await _repo.setDeliveryPricing(rule);
      await PlatformConfigService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _saved = rule;
        _savingDelivery = false;
      });
      showSnack(context, context.l10n.deliveryPricingSaved);
    } catch (error) {
      if (!mounted) return;
      setState(() => _savingDelivery = false);
      showFailure(context, error);
    }
  }

  Future<void> _useCurrency(AppCurrency currency) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.switchCurrencyTitle(currency.code),
      message: l10n.switchCurrencyMessage,
      confirmLabel: l10n.switchCurrencyConfirm(currency.code),
      cancelLabel: l10n.cancel,
      icon: Icons.currency_exchange_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyCurrency = currency.code);
    try {
      await _repo.setCurrency(currency.code);
      await PlatformConfigService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _activeCode = currency.code;
        _busyCurrency = null;
      });
      showSnack(context, l10n.currencySwitched(currency.code));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyCurrency = null);
      showFailure(context, error);
    }
  }

  Future<void> _deleteCurrency(AppCurrency currency) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.deleteCurrencyTitle(currency.code),
      message: l10n.deleteCurrencyMessage,
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      tone: AppDialogTone.danger,
      icon: Icons.delete_outline_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() => _busyCurrency = currency.code);
    try {
      await _repo.deleteCurrency(currency.code);
      if (!mounted) return;
      setState(() {
        _currencies = _currencies
            .where((c) => c.code != currency.code)
            .toList();
        _busyCurrency = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyCurrency = null);
      showFailure(context, error);
    }
  }

  Future<void> _editCurrency([AppCurrency? existing]) async {
    final saved = await showDialog<AppCurrency>(
      context: context,
      builder: (_) => _CurrencyDialog(existing: existing),
    );
    if (saved == null || !mounted) return;
    setState(() => _busyCurrency = saved.code);
    try {
      await _repo.saveCurrency(saved);
      final currencies = await _repo.currencies();
      await PlatformConfigService.instance.refresh();
      if (!mounted) return;
      setState(() {
        _currencies = currencies;
        _busyCurrency = null;
      });
      showSnack(context, context.l10n.currencySaved(saved.code));
    } catch (error) {
      if (!mounted) return;
      setState(() => _busyCurrency = null);
      showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canEdit = context.watch<AuthCubit>().state.can('finance.adjust');

    final Widget body = _loading
        ? const LoadingView()
        : ConsolePage(
            title: l10n.platformSettings,
            description: l10n.platformSettingsDescription,
            width: ConsoleWidth.form,
            children: [
              if (!canEdit) ...[
                ConsolePanel(
                  tone: ConsoleTone.warn,
                  child: Text(
                    l10n.platformSettingsReadOnly,
                    style: const TextStyle(color: AppColors.amberInk),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              _deliveryPanel(context, canEdit),
              const SizedBox(height: AppSpace.xl),
              _currencyPanel(context, canEdit),
            ],
          );

    if (widget.embedded) return body;
    if (AppBreakpoints.isWebWide(context)) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/platform-settings',
        sections: adminManageWebSections(context),
        pageTitle: l10n.platformSettings,
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.platformSettings)),
      body: SafeArea(top: false, child: body),
    );
  }

  Widget _deliveryPanel(BuildContext context, bool canEdit) {
    final l10n = context.l10n;
    final draft = _draft;
    final byDistance = _mode == DeliveryFeeRule.distanceMode;
    final dirty = draft != null && draft != _saved;

    Widget amountField(
      TextEditingController controller, {
      required String suffix,
    }) => SizedBox(
      width: 200,
      child: TextField(
        controller: controller,
        enabled: canEdit,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(isDense: true, suffixText: suffix),
      ),
    );

    return ConsolePanel(
      title: l10n.deliveryPricing,
      subtitle: l10n.deliveryPricingHint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConsoleFieldRow(
            label: l10n.deliveryPricingMode,
            help: byDistance
                ? l10n.deliveryModeDistanceHelp
                : l10n.deliveryModeStoreHelp,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: DeliveryFeeRule.storeMode,
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(l10n.deliveryModeStore),
                  ),
                  ButtonSegment(
                    value: DeliveryFeeRule.distanceMode,
                    icon: const Icon(Icons.route_rounded, size: 18),
                    label: Text(l10n.deliveryModeDistance),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: canEdit
                    ? (s) => setState(() => _mode = s.first)
                    : null,
              ),
            ),
          ),
          if (byDistance) ...[
            const Divider(height: 32, color: AppColors.borderSoft),
            ConsoleFieldRow(
              label: l10n.deliveryBaseFee,
              help: l10n.deliveryBaseFeeHelp,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: amountField(_baseFee, suffix: currencySymbol),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            ConsoleFieldRow(
              label: l10n.deliveryBaseKm,
              help: l10n.deliveryBaseKmHelp,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: amountField(_baseKm, suffix: l10n.km),
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            ConsoleFieldRow(
              label: l10n.deliveryPerKm,
              help: l10n.deliveryPerKmHelp,
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: amountField(
                  _perKm,
                  suffix: '$currencySymbol / ${l10n.km}',
                ),
              ),
            ),
            if (draft != null) ...[
              const Divider(height: 32, color: AppColors.borderSoft),
              ConsoleFieldRow(
                label: l10n.deliveryExamples,
                help: l10n.deliveryExamplesHelp,
                child: Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final km in <double>[
                      3,
                      draft.baseKm,
                      draft.baseKm + 2.5,
                      draft.baseKm + 10,
                    ])
                      _ExampleChip(
                        label: l10n.deliveryExample(trimZeros(km)),
                        value: formatMoney(draft.feeFor(storeFee: 0, km: km)),
                      ),
                  ],
                ),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.md),
                child: Text(
                  l10n.deliveryPricingInvalid,
                  style: const TextStyle(color: AppColors.dangerInk),
                ),
              ),
          ],
          if (canEdit) ...[
            const SizedBox(height: AppSpace.xl),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.icon(
                onPressed: dirty && !_savingDelivery ? _saveDelivery : null,
                icon: _savingDelivery
                    ? const ButtonSpinner(size: 16)
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(l10n.saveDeliveryPricing),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _currencyPanel(BuildContext context, bool canEdit) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return ConsolePanel(
      title: l10n.currency,
      subtitle: l10n.currencyHint,
      trailing: canEdit
          ? TextButton.icon(
              onPressed: _busyCurrency == null ? () => _editCurrency() : null,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.addCurrency),
            )
          : null,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final currency in _currencies)
            _CurrencyRow(
              currency: currency,
              language: language,
              active: currency.code == _activeCode,
              busy: _busyCurrency == currency.code,
              canEdit: canEdit && _busyCurrency == null,
              onUse: () => _useCurrency(currency),
              onEdit: () => _editCurrency(currency),
              onDelete: () => _deleteCurrency(currency),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(
                    l10n.currencyPaymentsNote,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.canvas,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          const SizedBox(height: 2),
          Text(value, style: AppType.mono(14)),
        ],
      ),
    );
  }
}

class _CurrencyRow extends StatelessWidget {
  const _CurrencyRow({
    required this.currency,
    required this.language,
    required this.active,
    required this.busy,
    required this.canEdit,
    required this.onUse,
    required this.onEdit,
    required this.onDelete,
  });

  final AppCurrency currency;
  final String language;
  final bool active;
  final bool busy;
  final bool canEdit;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: active ? AppColors.warmFill : null,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? AppColors.primary : AppColors.neutralFill,
              borderRadius: BorderRadius.circular(AppRadii.xs),
            ),
            child: Text(
              currency.code,
              style: AppType.mono(
                13,
                color: active ? Colors.white : AppColors.ink,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currency.nameFor(language),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  l10n.currencyFormatPreview(
                    '${currency.symbolFor(language)} '
                    '${1234.5.toStringAsFixed(currency.decimals)}',
                  ),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(8),
              child: ButtonSpinner(size: 18),
            )
          else if (active)
            SoftBadge(
              label: l10n.inUse,
              fill: AppColors.successFill,
              ink: AppColors.successInk,
            )
          else if (canEdit)
            OutlinedButton(onPressed: onUse, child: Text(l10n.useCurrency)),
          if (canEdit && !busy) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: l10n.edit,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 19),
              color: AppColors.textSecondary,
            ),
            if (!active)
              IconButton(
                tooltip: l10n.delete,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded, size: 19),
                color: AppColors.dangerInk,
              ),
          ],
        ],
      ),
    );
  }
}

/// Adds a currency, or edits one. The code is fixed once it exists: it is
/// what the platform setting points at.
class _CurrencyDialog extends StatefulWidget {
  const _CurrencyDialog({this.existing});

  final AppCurrency? existing;

  @override
  State<_CurrencyDialog> createState() => _CurrencyDialogState();
}

class _CurrencyDialogState extends State<_CurrencyDialog> {
  late final _code = TextEditingController(text: widget.existing?.code);
  late final _name = TextEditingController(text: widget.existing?.name);
  late final _nameAr = TextEditingController(text: widget.existing?.nameAr);
  late final _symbol = TextEditingController(text: widget.existing?.symbol);
  late final _symbolAr = TextEditingController(text: widget.existing?.symbolAr);
  late int _decimals = widget.existing?.decimals ?? 2;

  @override
  void initState() {
    super.initState();
    for (final c in [_code, _name]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _nameAr, _symbol, _symbolAr]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid =>
      RegExp(r'^[A-Z]{3}$').hasMatch(_code.text.trim().toUpperCase()) &&
      _name.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? l10n.editCurrency : l10n.addCurrency),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _code,
                enabled: !editing,
                textCapitalization: TextCapitalization.characters,
                maxLength: 3,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.currencyCode,
                  helperText: l10n.currencyCodeHelp,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: '${l10n.currencyName} · ${l10n.english}',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _nameAr,
                decoration: InputDecoration(
                  labelText: '${l10n.currencyName} · ${l10n.arabic}',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _symbol,
                      decoration: InputDecoration(
                        labelText: '${l10n.currencySymbol} · ${l10n.english}',
                        hintText: _code.text.toUpperCase(),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: TextField(
                      controller: _symbolAr,
                      decoration: InputDecoration(
                        labelText: '${l10n.currencySymbol} · ${l10n.arabic}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              DropdownButtonFormField<int>(
                initialValue: _decimals,
                decoration: InputDecoration(labelText: l10n.currencyDecimals),
                items: [
                  for (final d in const [0, 1, 2, 3])
                    DropdownMenuItem(
                      value: d,
                      child: Text('$d · ${1234.toStringAsFixed(d)}'),
                    ),
                ],
                onChanged: (v) => setState(() => _decimals = v ?? 2),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _valid
              ? () {
                  final code = _code.text.trim().toUpperCase();
                  Navigator.pop(
                    context,
                    AppCurrency(
                      code: code,
                      name: _name.text.trim(),
                      nameAr: _nameAr.text.trim(),
                      symbol: _symbol.text.trim().isEmpty
                          ? code
                          : _symbol.text.trim(),
                      symbolAr: _symbolAr.text.trim(),
                      decimals: _decimals,
                    ),
                  );
                }
              : null,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
