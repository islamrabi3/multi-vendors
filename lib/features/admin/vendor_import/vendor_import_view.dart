import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/account_onboarding_repository.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/file_save.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/web/console.dart';
import '../../../l10n/app_localizations.dart';
import 'vendor_import.dart';

/// Opens the bulk store import: beside the store list on a desktop console,
/// as its own page on a phone. Resolves true when at least one store was
/// created, so the list behind it can reload.
Future<bool> openVendorImport(BuildContext context) async {
  var created = false;
  final view = VendorImportView(onCreated: () => created = true);
  if (AppBreakpoints.isWebWide(context)) {
    await showConsoleSidePanel<void>(
      context,
      title: context.l10n.importStores,
      width: 980,
      child: view,
    );
  } else {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(title: Text(context.l10n.importStores)),
          body: SafeArea(top: false, child: view),
        ),
      ),
    );
  }
  return created;
}

enum _Stage { pick, preview, running, done }

/// Choose a file, see every row checked, create the ready ones one at a
/// time, and take away a results file with any passwords that were made up.
class VendorImportView extends StatefulWidget {
  const VendorImportView({super.key, required this.onCreated});

  final VoidCallback onCreated;

  @override
  State<VendorImportView> createState() => _VendorImportViewState();
}

class _VendorImportViewState extends State<VendorImportView> {
  final _accounts = AccountOnboardingRepository();
  List<VendorCategory> _categories = const [];
  _Stage _stage = _Stage.pick;
  String? _fileName;
  String? _error;
  List<VendorImportRow> _rows = const [];
  bool _approve = true;
  bool _showProblemsOnly = false;

  /// Row line → `created` or an error code.
  final Map<int, String> _outcome = {};

  @override
  void initState() {
    super.initState();
    AdminRepository().fetchVendorCategories().then((value) {
      if (mounted) setState(() => _categories = value);
    }).ignore();
  }

  int get _ready => _rows.where((r) => r.ready).length;
  int get _created => _outcome.values.where((v) => v == 'created').length;

  Future<void> _downloadTemplate() async {
    await saveBytesAsFile(
      fileName: 'stores-template.csv',
      bytes: VendorImport.templateCsv(),
      extensions: const ['csv'],
    );
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls', 'json'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file == null || file.bytes == null) return;
    try {
      final categories = _categories.isNotEmpty
          ? _categories
          : await AdminRepository().fetchVendorCategories();
      final rows = VendorImport.validate(
        VendorImport.readRecords(file.bytes!, file.name),
        categories: categories,
      );
      setState(() {
        _categories = categories;
        _fileName = file.name;
        _rows = rows;
        _error = null;
        _outcome.clear();
        _showProblemsOnly = false;
        _stage = _Stage.preview;
      });
    } catch (error) {
      setState(() => _error = _fileErrorText(context.l10n, error));
    }
  }

  Future<void> _run() async {
    setState(() => _stage = _Stage.running);
    for (final row in _rows.where((r) => r.ready)) {
      if (!mounted) return;
      try {
        await _accounts.createVendorAccount(
          email: row.email,
          password: row.password,
          fullName: row.ownerName,
          phone: row.phone,
          username: row.username,
          approve: _approve,
          store: row.store,
        );
        _outcome[row.line] = 'created';
        widget.onCreated();
      } catch (error) {
        _outcome[row.line] = AppFailure.from(error).code ?? 'CREATE_FAILED';
      }
      if (mounted) setState(() {});
    }
    if (mounted) setState(() => _stage = _Stage.done);
  }

  Future<void> _downloadResults() => saveBytesAsFile(
    fileName: 'stores-import-results.csv',
    bytes: VendorImport.resultsCsv(_rows, _outcome),
    extensions: const ['csv'],
  );

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (_stage == _Stage.pick)
          ..._pickStage(context)
        else
          ..._rowsStage(context),
      ],
    );
  }

  List<Widget> _pickStage(BuildContext context) {
    final l10n = context.l10n;
    return [
      Text(
        l10n.importStoresIntro,
        style: const TextStyle(fontSize: 14, height: 1.5),
      ),
      const SizedBox(height: AppSpace.xl),
      ConsolePanel(
        title: l10n.importStep1,
        subtitle: l10n.importStep1Hint,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text(l10n.downloadTemplate),
          ),
        ),
      ),
      const SizedBox(height: AppSpace.lg),
      ConsolePanel(
        title: l10n.importStep2,
        subtitle: l10n.importStep2Hint,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DropZone(onTap: _pick),
            if (_error != null) ...[
              const SizedBox(height: AppSpace.md),
              Text(_error!, style: const TextStyle(color: AppColors.dangerInk)),
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _rowsStage(BuildContext context) {
    final l10n = context.l10n;
    final problems = _rows.length - _ready;
    final visible = _showProblemsOnly
        ? _rows.where((r) => !r.ready).toList()
        : _rows;
    final running = _stage == _Stage.running;
    final done = _stage == _Stage.done;
    final processed = _outcome.length;

    return [
      Row(
        children: [
          const Icon(Icons.description_outlined, color: AppColors.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _fileName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (_stage == _Stage.preview)
            TextButton(onPressed: _pick, child: Text(l10n.chooseAnotherFile)),
        ],
      ),
      const SizedBox(height: AppSpace.md),
      ConsoleGrid(
        minTileWidth: 180,
        maxColumns: 3,
        children: [
          ConsoleStat(
            label: l10n.importRowsReady,
            value: done ? '$_created / $_ready' : '$_ready',
            hint: done ? l10n.importCreated : null,
            icon: Icons.check_circle_outline_rounded,
            tone: _ready > 0 ? ConsoleTone.good : ConsoleTone.plain,
          ),
          ConsoleStat(
            label: l10n.importRowsWithProblems,
            value: '$problems',
            icon: Icons.error_outline_rounded,
            tone: problems > 0 ? ConsoleTone.warn : ConsoleTone.plain,
            onTap: problems == 0
                ? null
                : () => setState(() => _showProblemsOnly = !_showProblemsOnly),
            hint: problems > 0
                ? (_showProblemsOnly ? l10n.showAllRows : l10n.showOnlyProblems)
                : null,
          ),
          if (done)
            ConsoleStat(
              label: l10n.importFailed,
              value: '${processed - _created}',
              icon: Icons.cancel_outlined,
              tone: processed - _created > 0
                  ? ConsoleTone.danger
                  : ConsoleTone.plain,
            ),
        ],
      ),
      const SizedBox(height: AppSpace.lg),
      if (running || done) ...[
        LinearProgressIndicator(
          value: _ready == 0 ? 1 : processed / _ready,
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 6),
        Text(
          running
              ? l10n.importProgress(processed, _ready)
              : l10n.importFinished,
          style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: AppSpace.lg),
      ],
      Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          children: [
            for (var i = 0; i < visible.length; i++) ...[
              if (i > 0) const Divider(height: 1, color: AppColors.borderSoft),
              _RowTile(row: visible[i], outcome: _outcome[visible[i].line]),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpace.xl),
      if (_stage == _Stage.preview) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _approve,
          onChanged: (v) => setState(() => _approve = v),
          title: Text(l10n.importApproveNow),
          subtitle: Text(l10n.importApproveNowHint),
        ),
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: FilledButton.icon(
            onPressed: _ready == 0 ? null : _run,
            icon: const Icon(Icons.add_business_rounded, size: 18),
            label: Text(l10n.createNStores(_ready)),
          ),
        ),
      ],
      if (done)
        Wrap(
          alignment: WrapAlignment.end,
          spacing: AppSpace.sm,
          children: [
            OutlinedButton.icon(
              onPressed: _downloadResults,
              icon: const Icon(Icons.file_download_outlined, size: 18),
              label: Text(l10n.downloadResults),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(l10n.done),
            ),
          ],
        ),
      if (done && _rows.any((r) => r.passwordGenerated))
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Text(
            l10n.importPasswordsNote,
            textAlign: TextAlign.end,
            style: const TextStyle(fontSize: 12.5, color: AppColors.amberInk),
          ),
        ),
    ];
  }
}

String _fileErrorText(AppLocalizations l10n, Object error) =>
    switch (error is VendorImportException ? error.code : '') {
      'IMPORT_EMPTY' => l10n.importErrEmpty,
      'IMPORT_NO_EMAIL_COLUMN' => l10n.importErrNoEmail,
      _ => l10n.importErrUnreadable,
    };

String problemText(AppLocalizations l10n, VendorImportProblem problem) =>
    switch (problem) {
      VendorImportProblem.missingEmail => l10n.importProbMissingEmail,
      VendorImportProblem.badEmail => l10n.importProbBadEmail,
      VendorImportProblem.duplicateEmail => l10n.importProbDuplicateEmail,
      VendorImportProblem.shortPassword => l10n.importProbShortPassword,
      VendorImportProblem.missingOwner => l10n.importProbMissingOwner,
      VendorImportProblem.missingStoreName => l10n.importProbMissingStore,
      VendorImportProblem.unknownCategory => l10n.importProbCategory,
      VendorImportProblem.missingAddress => l10n.importProbAddress,
      VendorImportProblem.missingLocation => l10n.importProbLocation,
    };

class _DropZone extends StatelessWidget {
  const _DropZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: AppColors.borderStrong, width: 1.5),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.upload_file_rounded,
                size: 34,
                color: AppColors.primary,
              ),
              const SizedBox(height: AppSpace.sm),
              Text(l10n.chooseStoresFile, style: AppType.heading(15)),
              const SizedBox(height: 2),
              Text(
                l10n.storesFileTypes,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.outcome});

  final VendorImportRow row;
  final String? outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final created = outcome == 'created';
    final failed = outcome != null && !created;
    final Widget status = created
        ? const Icon(
            Icons.check_circle_rounded,
            color: AppColors.success,
            size: 20,
          )
        : failed
        ? const Icon(Icons.cancel_rounded, color: AppColors.dangerInk, size: 20)
        : row.ready
        ? const Icon(
            Icons.radio_button_unchecked_rounded,
            color: AppColors.textFaint,
            size: 20,
          )
        : const Icon(Icons.error_rounded, color: AppColors.amberInk, size: 20);
    final notes = failed
        ? [AppFailure(kind: FailureKind.rejected, code: outcome).message(l10n)]
        : [for (final p in row.problems) problemText(l10n, p)];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(
              '#${row.line}',
              style: AppType.mono(12, color: AppColors.textMuted),
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 1), child: status),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.storeName.isEmpty ? '—' : row.storeName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                Text(
                  [
                    if (row.email.isNotEmpty) row.email,
                    if (row.categoryLabel.isNotEmpty) row.categoryLabel,
                    if (row.address.isNotEmpty) row.address,
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                  ),
                ),
                for (final note in notes)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: failed
                            ? AppColors.dangerInk
                            : AppColors.amberInk,
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
