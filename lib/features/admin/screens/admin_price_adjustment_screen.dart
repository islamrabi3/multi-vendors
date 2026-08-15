import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

/// Moves menu prices across the marketplace in one action.
///
/// A platform-wide price change used to mean asking every store to re-enter its
/// menu, which is a change that never actually lands. This does it in one write
/// and records what it did, so a run applied to the wrong scope is undone by
/// running its inverse rather than by restoring a backup.
///
/// Three guards, because the blast radius is the whole catalogue: the number of
/// items in scope is shown before the button, the confirm dialog repeats the
/// change in words, and the server floors every price so a large cut cannot
/// take anything to zero.
class AdminPriceAdjustmentScreen extends StatefulWidget {
  const AdminPriceAdjustmentScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  State<AdminPriceAdjustmentScreen> createState() =>
      _AdminPriceAdjustmentScreenState();
}

enum _Mode { percent, fixed }

enum _Scope { all, vendor, category }

class _AdminPriceAdjustmentScreenState
    extends State<AdminPriceAdjustmentScreen> {
  final _repository = AdminRepository();
  final _valueController = TextEditingController();

  _Mode _mode = _Mode.percent;
  _Scope _scope = _Scope.all;
  bool _increase = true;

  List<VendorCategory> _categories = const [];
  List<Vendor> _vendors = const [];
  String? _categoryId;
  String? _vendorId;

  int? _affected;
  bool _counting = false;
  bool _applying = false;
  List<Map<String, dynamic>> _history = const [];

  @override
  void initState() {
    super.initState();
    _loadPickers();
    _refreshCount();
    _loadHistory();
  }

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  Future<void> _loadPickers() async {
    try {
      final categories = await _repository.fetchVendorCategories();
      final vendors = await _repository.fetchVendors();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _vendors = vendors;
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _repository.fetchPriceAdjustments();
      if (!mounted) return;
      setState(() => _history = rows);
    } catch (_) {
      // History is a record, not the tool. Losing it must not block a run.
    }
  }

  /// The count is the one number that makes this safe to press, so it is
  /// re-read on every scope change rather than only before applying.
  Future<void> _refreshCount() async {
    setState(() => _counting = true);
    try {
      final count = await _repository.priceScopeCount(
        scope: _scope.name,
        vendorId: _scope == _Scope.vendor ? _vendorId : null,
        categoryId: _scope == _Scope.category ? _categoryId : null,
      );
      if (!mounted) return;
      setState(() {
        _affected = count;
        _counting = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _affected = null;
        _counting = false;
      });
    }
  }

  /// Signed: the UI asks for a direction and a magnitude because "-10" typed
  /// into a box is easy to mean and easy to mistype.
  double? get _signedValue {
    final magnitude = double.tryParse(_valueController.text.trim());
    if (magnitude == null || magnitude <= 0) return null;
    if (_mode == _Mode.percent && magnitude >= 100 && !_increase) return null;
    return _increase ? magnitude : -magnitude;
  }

  bool get _scopeChosen => switch (_scope) {
    _Scope.all => true,
    _Scope.vendor => _vendorId != null,
    _Scope.category => _categoryId != null,
  };

  String _summary(BuildContext context) {
    final l10n = context.l10n;
    final value = _signedValue;
    final amount = value == null
        ? '—'
        : _mode == _Mode.percent
        ? '${value.abs().toStringAsFixed(value.abs() % 1 == 0 ? 0 : 2)}%'
        : formatMoney(value.abs());
    final target = switch (_scope) {
      _Scope.all => l10n.scopeAllProducts,
      _Scope.vendor => _vendorName ?? l10n.scopeOneStore,
      _Scope.category => _categoryName ?? l10n.scopeOneCategory,
    };
    return _increase
        ? l10n.priceIncreaseSummary(amount, target)
        : l10n.priceDecreaseSummary(amount, target);
  }

  String? get _vendorName {
    for (final vendor in _vendors) {
      if (vendor.id == _vendorId) return vendor.name;
    }
    return null;
  }

  String? get _categoryName {
    for (final category in _categories) {
      if (category.id == _categoryId) return category.name;
    }
    return null;
  }

  Future<void> _apply() async {
    final value = _signedValue;
    if (value == null || !_scopeChosen) return;
    final l10n = context.l10n;

    final confirmed = await showConfirmDialog(
      context: context,
      title: l10n.priceAdjustment,
      message: l10n.priceAdjustConfirm(_summary(context), _affected ?? 0),
      confirmLabel: l10n.apply,
      cancelLabel: l10n.cancel,
      tone: AppDialogTone.danger,
      icon: Icons.price_change_outlined,
    );
    if (!confirmed || !mounted) return;

    setState(() => _applying = true);
    try {
      final result = await _repository.adjustPrices(
        mode: _mode.name,
        value: value,
        scope: _scope.name,
        vendorId: _scope == _Scope.vendor ? _vendorId : null,
        categoryId: _scope == _Scope.category ? _categoryId : null,
      );
      if (!mounted) return;
      showSnack(context, l10n.pricesUpdated(result.products));
      _valueController.clear();
      await _loadHistory();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final body = ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.gutter,
        AppSpace.md,
        AppSpace.gutter,
        40,
      ),
      children: [
        _Card(
          title: l10n.adjustmentType,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_Mode>(
                segments: [
                  ButtonSegment(
                    value: _Mode.percent,
                    label: Text(
                      l10n.percentage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: const Icon(Icons.percent_rounded),
                  ),
                  ButtonSegment(
                    value: _Mode.fixed,
                    label: Text(
                      l10n.fixedAmount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: const Icon(Icons.attach_money_rounded),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: (values) =>
                    setState(() => _mode = values.first),
              ),
              const SizedBox(height: AppSpace.md),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text(
                      l10n.increase,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: const Icon(Icons.trending_up_rounded),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text(
                      l10n.decrease,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    icon: const Icon(Icons.trending_down_rounded),
                  ),
                ],
                selected: {_increase},
                onSelectionChanged: (values) =>
                    setState(() => _increase = values.first),
              ),
              const SizedBox(height: AppSpace.md),
              TextField(
                controller: _valueController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _mode == _Mode.percent
                      ? l10n.percentValue
                      : l10n.amountValue,
                  suffixText: _mode == _Mode.percent ? '%' : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _Card(
          title: l10n.appliesTo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RadioGroup<_Scope>(
                groupValue: _scope,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _scope = value);
                  _refreshCount();
                },
                child: Column(
                  children: [
                    for (final scope in _Scope.values)
                      RadioListTile<_Scope>(
                        value: scope,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          switch (scope) {
                            _Scope.all => l10n.scopeAllProducts,
                            _Scope.vendor => l10n.scopeOneStore,
                            _Scope.category => l10n.scopeOneCategory,
                          },
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (_scope == _Scope.vendor)
                DropdownButtonFormField<String>(
                  initialValue: _vendorId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.store),
                  items: [
                    for (final vendor in _vendors)
                      DropdownMenuItem(
                        value: vendor.id,
                        child: Text(
                          vendor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _vendorId = value);
                    _refreshCount();
                  },
                ),
              if (_scope == _Scope.category)
                DropdownButtonFormField<String>(
                  initialValue: _categoryId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.category),
                  items: [
                    for (final category in _categories)
                      DropdownMenuItem(
                        value: category.id,
                        child: Text(
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    setState(() => _categoryId = value);
                    _refreshCount();
                  },
                ),
              const SizedBox(height: AppSpace.sm),
              Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _counting
                          ? l10n.counting
                          : l10n.productsInScope(_affected ?? 0),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          decoration: BoxDecoration(
            color: AppColors.warmFill,
            borderRadius: BorderRadius.circular(AppRadii.lg),
          ),
          child: Text(
            _summary(context),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        FilledButton.icon(
          onPressed: _applying || _signedValue == null || !_scopeChosen
              ? null
              : _apply,
          icon: _applying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.check_rounded),
          label: Text(
            l10n.applyToAllProducts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxl),
          Text(l10n.recentAdjustments, style: AppType.heading(17)),
          const SizedBox(height: AppSpace.sm),
          for (final row in _history) _HistoryRow(row: row),
        ],
      ],
    );

    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(AppSpace.xl), child: body);
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/price-adjustment',
        sections: adminManageWebSections(context),
        pageTitle: l10n.priceAdjustment,
        child: Padding(padding: const EdgeInsets.all(AppSpace.xl), child: body),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.priceAdjustment)),
      body: body,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppType.heading(15)),
          const SizedBox(height: AppSpace.md),
          child,
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final mode = row['mode'] as String? ?? 'percent';
    final value = ((row['value'] as num?) ?? 0).toDouble();
    final affected = ((row['affected_count'] as num?) ?? 0).toInt();
    final at = DateTime.tryParse(row['created_at'] as String? ?? '')?.toLocal();
    final label = mode == 'percent'
        ? '${value > 0 ? '+' : ''}${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}%'
        : '${value > 0 ? '+' : '-'}${formatMoney(value.abs())}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SoftBadge(
            label: label,
            fill: value >= 0 ? AppColors.successFill : AppColors.dangerFill,
            ink: value >= 0 ? AppColors.successInk : AppColors.dangerInk,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              context.l10n.productsUpdatedCount(affected),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          if (at != null)
            Text(
              '${at.day}/${at.month} ${TimeOfDay.fromDateTime(at).format(context)}',
              style: const TextStyle(
                fontSize: 11.5,
                color: AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }
}
