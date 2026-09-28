import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:multi_vendor/core/utils/time_format.dart';
import 'package:flutter/services.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/console.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
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
  String? _categoryId;

  /// Held as the full row rather than just an id — unlike categories, which
  /// are few enough to keep the whole list in memory, the store picker below
  /// searches the server, so nothing else on screen has the chosen store's
  /// name to look up once the search results are gone.
  Vendor? _vendor;
  String? get _vendorId => _vendor?.id;

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
      if (!mounted) return;
      setState(() => _categories = categories);
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
      _Scope.all => l10n.scopeAllProductsInline,
      _Scope.vendor => _vendorName ?? l10n.scopeOneStore,
      _Scope.category => _categoryName ?? l10n.scopeOneCategory,
    };
    return _increase
        ? l10n.priceIncreaseSummary(amount, target)
        : l10n.priceDecreaseSummary(amount, target);
  }

  String? get _vendorName => _vendor?.name;

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

    final typeSegments = SegmentedButton<_Mode>(
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
      onSelectionChanged: (values) => setState(() => _mode = values.first),
    );
    final directionSegments = SegmentedButton<bool>(
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
      onSelectionChanged: (values) => setState(() => _increase = values.first),
    );
    final valueField = TextField(
      controller: _valueController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        labelText: _mode == _Mode.percent
            ? l10n.percentValue
            : l10n.amountValue,
        suffixText: _mode == _Mode.percent ? '%' : currencySymbol,
      ),
    );
    final scopePicker = Column(
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
                  dense: true,
                  title: Text(
                    switch (scope) {
                      _Scope.all => l10n.scopeAllProducts,
                      _Scope.vendor => l10n.scopeOneStore,
                      _Scope.category => l10n.scopeOneCategory,
                    },
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ],
          ),
        ),
        if (_scope == _Scope.vendor) ...[
          const SizedBox(height: AppSpace.sm),
          _VendorSearchField(
            repository: _repository,
            selected: _vendor,
            onSelected: (vendor) {
              setState(() => _vendor = vendor);
              _refreshCount();
            },
          ),
        ],
        if (_scope == _Scope.category) ...[
          const SizedBox(height: AppSpace.sm),
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
        ],
      ],
    );
    final ready = !_applying && _signedValue != null && _scopeChosen;
    final applyButton = FilledButton.icon(
      onPressed: ready ? _apply : null,
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
    );

    if (webWide) {
      final page = _webPage(
        typeSegments: typeSegments,
        directionSegments: directionSegments,
        valueField: valueField,
        scopePicker: scopePicker,
        applyButton: applyButton,
      );
      if (widget.embedded) return page;
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/price-adjustment',
        sections: adminManageWebSections(context),
        pageTitle: l10n.priceAdjustment,
        child: page,
      );
    }

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
              typeSegments,
              const SizedBox(height: AppSpace.md),
              directionSegments,
              const SizedBox(height: AppSpace.md),
              valueField,
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md),
        _Card(
          title: l10n.appliesTo,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              scopePicker,
              const SizedBox(height: AppSpace.sm),
              _ScopeCount(counting: _counting, affected: _affected),
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
            _signedValue == null ? l10n.enterAmountFirst : _summary(context),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryDark,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(height: AppSpace.md),
        applyButton,
        if (_history.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxl),
          Text(l10n.recentAdjustments, style: AppType.heading(17)),
          const SizedBox(height: AppSpace.sm),
          for (final row in _history) _HistoryRow(row: row),
        ],
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.priceAdjustment)),
      body: body,
    );
  }

  /// Desktop: the change on the left, what it will do on the right — kept in
  /// view while the form is filled in — and the record of past runs below.
  Widget _webPage({
    required Widget typeSegments,
    required Widget directionSegments,
    required Widget valueField,
    required Widget scopePicker,
    required Widget applyButton,
  }) {
    final l10n = context.l10n;
    final value = _signedValue;

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConsolePanel(
          title: l10n.adjustmentType,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConsoleFieldRow(label: l10n.typeColumn, child: typeSegments),
              const SizedBox(height: AppSpace.lg),
              ConsoleFieldRow(
                label: l10n.directionLabel,
                child: directionSegments,
              ),
              const SizedBox(height: AppSpace.lg),
              ConsoleFieldRow(
                label: l10n.howMuchLabel,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(width: 220, child: valueField),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        ConsolePanel(
          title: l10n.appliesTo,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: scopePicker,
        ),
      ],
    );

    final preview = ConsolePanel(
      title: l10n.previewLabel,
      tone: value == null ? ConsoleTone.plain : ConsoleTone.brand,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            value == null ? l10n.enterAmountFirst : _summary(context),
            style: TextStyle(
              fontSize: value == null ? 14 : 16,
              height: 1.4,
              fontWeight: value == null ? FontWeight.w500 : FontWeight.w700,
              color: value == null ? AppColors.textSecondary : AppColors.ink,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: AppSpace.md),
          _ScopeCount(counting: _counting, affected: _affected, large: true),
          const SizedBox(height: AppSpace.lg),
          applyButton,
          const SizedBox(height: AppSpace.md),
          Text(
            l10n.priceAdjustGuard,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );

    final columns = [
      WebTableColumn(label: l10n.changeColumn, width: 130),
      WebTableColumn(label: l10n.scopeColumn, flex: 3),
      WebTableColumn(label: l10n.byColumn, flex: 2),
      WebTableColumn(label: l10n.whenColumn, width: 190),
      WebTableColumn(label: l10n.productsColumn, width: 100, numeric: true),
    ];
    final language = Localizations.localeOf(context).languageCode;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 48),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  form,
                  const SizedBox(height: AppSpace.lg),
                  preview,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: form),
                const SizedBox(width: AppSpace.lg),
                SizedBox(width: 360, child: preview),
              ],
            );
          },
        ),
        if (_history.isNotEmpty) ...[
          const SizedBox(height: AppSpace.xxl),
          Text(l10n.recentAdjustments, style: AppType.heading(17)),
          const SizedBox(height: AppSpace.md),
          WebTable(
            columns: columns,
            trailingWidth: 0,
            rows: [
              for (final row in _history)
                WebTableRow.aligned(
                  columns: columns,
                  trailingWidth: 0,
                  cells: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _ChangeBadge(row: row),
                    ),
                    Text(
                      _historyScope(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                    ),
                    Text(
                      (row['profiles'] as Map?)?['full_name'] as String? ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      switch (DateTime.tryParse(
                        row['created_at'] as String? ?? '',
                      )?.toLocal()) {
                        final at? =>
                          '${DateFormat.yMMMd(language).format(at)} · ${formatClock(context, at)}',
                        null => '—',
                      },
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${((row['affected_count'] as num?) ?? 0).toInt()}',
                      style: AppType.mono(13.5, weight: FontWeight.w600),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// What a past run touched, by name where the row still has one.
  String _historyScope(Map<String, dynamic> row) {
    final l10n = context.l10n;
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    return switch (row['scope'] as String?) {
      'vendor' =>
        (row['vendors'] as Map?)?['name'] as String? ?? l10n.scopeOneStore,
      'category' => switch (row['vendor_categories'] as Map?) {
        final c? =>
          (arabic ? c['name_ar'] as String? : null) ??
              c['name'] as String? ??
              l10n.scopeOneCategory,
        null => l10n.scopeOneCategory,
      },
      _ => l10n.scopeAllProducts,
    };
  }
}

/// How many products the change reaches — the number that makes it safe to
/// press apply.
class _ScopeCount extends StatelessWidget {
  const _ScopeCount({
    required this.counting,
    required this.affected,
    this.large = false,
  });

  final bool counting;
  final int? affected;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Icon(
          Icons.inventory_2_outlined,
          size: large ? 18 : 16,
          color: AppColors.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            counting ? l10n.counting : l10n.productsInScope(affected ?? 0),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: large ? 14 : 12.5,
              color: large ? AppColors.ink : AppColors.textMuted,
              fontWeight: large ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),
      ],
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

/// A past run's change, signed and coloured by direction.
class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final mode = row['mode'] as String? ?? 'percent';
    final value = ((row['value'] as num?) ?? 0).toDouble();
    final label = mode == 'percent'
        ? '${value > 0 ? '+' : ''}${value.toStringAsFixed(value % 1 == 0 ? 0 : 2)}%'
        : '${value > 0 ? '+' : '-'}${formatMoney(value.abs())}';
    return SoftBadge(
      label: label,
      fill: value >= 0 ? AppColors.successFill : AppColors.dangerFill,
      ink: value >= 0 ? AppColors.successInk : AppColors.dangerInk,
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
              '${at.day}/${at.month} ${formatClock(context, at)}',
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

/// Type-ahead in place of a dropdown of every store.
///
/// A `DropdownButtonFormField` loaded every vendor up front and rendered them
/// all in one scrollable menu — fine at a dozen stores, unusable at a
/// thousand, and it paid the full list's payload on every visit to this
/// screen even when a category-scoped run never looked at it. This searches
/// the server instead, the same `fetchVendorsPage` the main vendors list
/// already pages through.
class _VendorSearchField extends StatefulWidget {
  const _VendorSearchField({
    required this.repository,
    required this.selected,
    required this.onSelected,
  });

  final AdminRepository repository;
  final Vendor? selected;
  final ValueChanged<Vendor?> onSelected;

  @override
  State<_VendorSearchField> createState() => _VendorSearchFieldState();
}

class _VendorSearchFieldState extends State<_VendorSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  List<Vendor> _results = const [];
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    if (widget.selected != null) _controller.text = widget.selected!.name;
    _focusNode.addListener(() {
      // Losing focus with nothing picked clears the typed text, so the field
      // never shows a query that was never turned into a selection.
      if (!_focusNode.hasFocus && widget.selected == null) {
        _controller.clear();
      }
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(_VendorSearchField old) {
    super.didUpdateWidget(old);
    // The scope radio above can be switched away and back, remembering the
    // last pick — this keeps the field in sync when that happens externally.
    if (widget.selected?.id != old.selected?.id) {
      _controller.text = widget.selected?.name ?? '';
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    widget.onSelected(null);
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() => _results = const []);
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await widget.repository.fetchVendorsPage(
        limit: 20,
        offset: 0,
        search: value,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    });
  }

  void _pick(Vendor vendor) {
    _focusNode.unfocus();
    setState(() {
      _controller.text = vendor.name;
      _results = const [];
    });
    widget.onSelected(vendor);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onChanged,
          decoration: InputDecoration(
            labelText: l10n.store,
            hintText: l10n.searchByName,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : widget.selected != null
                ? IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _results = const []);
                      widget.onSelected(null);
                    },
                  )
                : null,
          ),
        ),
        // Only while the field is actually focused: without this, the stale
        // result list from a search flashed back on screen the next time this
        // widget rebuilt for an unrelated reason (the count refreshing).
        if (_focusNode.hasFocus && _results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 4),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.md),
              boxShadow: AppShadows.card,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _results.length,
              itemBuilder: (context, i) {
                final vendor = _results[i];
                return ListTile(
                  dense: true,
                  leading: const Icon(
                    Icons.storefront_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                  title: Text(
                    vendor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _pick(vendor),
                );
              },
            ),
          ),
      ],
    );
  }
}
