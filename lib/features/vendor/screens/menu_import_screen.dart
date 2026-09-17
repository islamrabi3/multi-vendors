import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/menu_import_repository.dart';
import '../../../core/utils/menu_sheet_parser.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

/// One option group under an item in the review list.
///
/// Sizes and extras arrive as real choices now rather than a line of text in
/// the description, so they have to be visible before import: a wrong size
/// price is a wrong charge on every order of that dish.
class _OptionGroupRow extends StatelessWidget {
  const _OptionGroupRow({required this.group, required this.onRemove});

  final ExtractedOptionGroup group;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            group.isRequired
                ? Icons.radio_button_checked_rounded
                : Icons.add_circle_outline_rounded,
            size: 14,
            color: AppColors.textFaint,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.label,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    for (final option in group.options)
                      option.priceDelta == 0
                          ? option.label
                          : '${option.label} +${formatMoney(option.priceDelta)}',
                  ].join('  ·  '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 14, color: AppColors.textFaint),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

/// A file, photos or a link -> structured menu -> editable review -> import.
///
/// Three routes in, deliberately. A spreadsheet is parsed on the device
/// because it is already structured and a model would only add cost and
/// transcription errors to numbers that are already exact. Photos and PDFs go
/// to the extractor, because there they are the only way to read the thing.
/// A link goes to the extractor too, but the server fetches it: only the
/// server can decide which addresses it is willing to request.
/// Pops with `true` when items were imported so the menu can reload.
class MenuImportScreen extends StatefulWidget {
  const MenuImportScreen({super.key, required this.vendorId});

  final String vendorId;

  @override
  State<MenuImportScreen> createState() => _MenuImportScreenState();
}

enum _Step { pick, extracting, review, importing }

class _MenuImportScreenState extends State<MenuImportScreen> {
  final _repo = MenuImportRepository();
  final _picker = ImagePicker();

  _Step _step = _Step.pick;
  final List<({Uint8List bytes, String mimeType})> _images = [];
  final _url = TextEditingController();
  List<ExtractedCategory> _menu = [];

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  static const _maxImages = 5;

  /// A spreadsheet is already structured, so it is parsed here rather than
  /// sent to the model: exact, instant, free, and it cannot mis-read a price
  /// that was already a number. PDFs and photos still go to the extractor,
  /// because for those there is nothing else to do.
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv', 'xlsx', 'xls', 'pdf'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;

    final extension = (file.extension ?? '').toLowerCase();

    if (extension == 'pdf') {
      // Handed to the extractor like a photo; the function decides how to read
      // it. Counts against the same limit, because it costs the same.
      setState(() {
        _images.add((bytes: bytes, mimeType: 'application/pdf'));
      });
      return;
    }

    setState(() => _step = _Step.extracting);
    try {
      final menu = extension == 'csv'
          ? MenuSheetParser.parseCsv(bytes)
          : MenuSheetParser.parseExcel(bytes);
      if (!mounted) return;
      setState(() {
        _menu = menu;
        _step = _Step.review;
      });
    } on MenuSheetException catch (error) {
      if (!mounted) return;
      setState(() => _step = _Step.pick);
      showSnack(context, switch (error.code) {
        'SHEET_NO_NAME_COLUMN' => context.l10n.spreadsheetNoNameColumn,
        _ => context.l10n.spreadsheetEmpty,
      }, error: true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _step = _Step.pick);
      showFailure(context, error);
    }
  }

  Future<void> _pickImages() async {
    final files = await _picker.pickMultiImage(
      maxWidth: 1600,
      limit: _maxImages,
    );
    if (files.isEmpty) return;
    for (final file in files.take(_maxImages - _images.length)) {
      final bytes = await file.readAsBytes();
      _images.add((bytes: bytes, mimeType: file.mimeType ?? 'image/jpeg'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _extract() => _runExtraction(
    () => _repo.extractMenu(widget.vendorId, _images),
    emptyMessage: (l10n) => l10n.noItemsExtracted,
  );

  /// Reads the menu off a page the store already publishes.
  Future<void> _extractFromUrl() => _runExtraction(
    () => _repo.extractMenuFromUrl(widget.vendorId, _url.text),
    emptyMessage: (l10n) => l10n.noItemsExtractedFromLink,
  );

  Future<void> _runExtraction(
    Future<List<ExtractedCategory>> Function() run, {
    required String Function(AppLocalizations l10n) emptyMessage,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() => _step = _Step.extracting);
    try {
      final menu = await run();
      if (!mounted) return;
      if (menu.isEmpty) {
        setState(() => _step = _Step.pick);
        showSnack(context, emptyMessage(context.l10n), error: true);
        return;
      }
      setState(() {
        _menu = menu;
        _step = _Step.review;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _step = _Step.pick);
      // A refused or unreadable link has its own reason; saying "try clearer
      // photos" for a mistyped address helps nobody.
      final l10n = context.l10n;
      showSnack(context, switch (error) {
        MenuImportException(code: 'INVALID_URL') => l10n.errInvalidUrl,
        MenuImportException(code: 'URL_NOT_ALLOWED') => l10n.errUrlNotAllowed,
        MenuImportException(code: 'URL_FETCH_FAILED') => l10n.errUrlFetchFailed,
        MenuImportException(code: 'URL_TOO_LARGE') => l10n.errUrlTooLarge,
        MenuImportException(code: 'URL_NO_CONTENT') => l10n.errUrlNoContent,
        MenuImportException(code: 'URL_NEEDS_JS') => l10n.errUrlNeedsJs,
        _ => l10n.extractionFailed,
      }, error: true);
    }
  }

  Future<void> _import() async {
    final menu = _menu.where((category) => category.items.isNotEmpty).toList();
    if (menu.isEmpty) return;
    setState(() => _step = _Step.importing);
    try {
      await _repo.importMenu(widget.vendorId, menu);
      if (!mounted) return;
      showSnack(context, context.l10n.menuImported);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _step = _Step.review);
      showFailure(context, e);
    }
  }

  /// Section names get the same two-language treatment as items — otherwise a
  /// category the model only read in one language could never be corrected,
  /// and it would show that language in both UIs forever.
  Future<void> _editCategory(ExtractedCategory category) async {
    final name = TextEditingController(text: category.name);
    final nameAr = TextEditingController(text: category.nameAr);

    final saved = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText:
                      '${sheetContext.l10n.sectionName} · ${sheetContext.l10n.english}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameAr,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText:
                      '${sheetContext.l10n.sectionName} · ${sheetContext.l10n.arabic}',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: Text(sheetContext.l10n.save),
              ),
            ],
          ),
        ),
      ),
    );

    // Either language alone is enough to keep the section.
    if (saved == true &&
        (name.text.trim().isNotEmpty || nameAr.text.trim().isNotEmpty)) {
      setState(() {
        category.name = name.text.trim();
        category.nameAr = nameAr.text.trim();
      });
    }
    name.dispose();
    nameAr.dispose();
  }

  Future<void> _editItem(ExtractedItem item) async {
    final name = TextEditingController(text: item.name);
    final nameAr = TextEditingController(text: item.nameAr);
    final price = TextEditingController(
      text: item.price == 0 ? '' : item.price.toStringAsFixed(2),
    );
    final description = TextEditingController(text: item.description);
    final descriptionAr = TextEditingController(text: item.descriptionAr);

    final saved = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: name,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText:
                      '${sheetContext.l10n.itemName} · ${sheetContext.l10n.english}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameAr,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText:
                      '${sheetContext.l10n.itemName} · ${sheetContext.l10n.arabic}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: sheetContext.l10n.priceLabel,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: description,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText:
                      '${sheetContext.l10n.descriptionOptional} · ${sheetContext.l10n.english}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionAr,
                textDirection: TextDirection.rtl,
                decoration: InputDecoration(
                  labelText:
                      '${sheetContext.l10n.descriptionOptional} · ${sheetContext.l10n.arabic}',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                child: Text(sheetContext.l10n.save),
              ),
            ],
          ),
        ),
      ),
    );

    // Either language alone is enough to keep the item.
    if (saved == true &&
        (name.text.trim().isNotEmpty || nameAr.text.trim().isNotEmpty)) {
      setState(() {
        item.name = name.text.trim();
        item.nameAr = nameAr.text.trim();
        item.price = double.tryParse(price.text.trim()) ?? item.price;
        item.description = description.text.trim();
        item.descriptionAr = descriptionAr.text.trim();
      });
    }
    name.dispose();
    nameAr.dispose();
    price.dispose();
    description.dispose();
    descriptionAr.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(context.l10n.importMenuFromPhotos)),
      body: switch (_step) {
        _Step.extracting => _busyView(context.l10n.extractingMenu),
        _Step.importing => _busyView(context.l10n.importAll),
        _Step.pick => _pickView(),
        _Step.review => _reviewView(),
      },
    );
  }

  Widget _busyView(String label) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 16),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _pickView() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.warmFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.importMenuHint,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: [
            for (var i = 0; i < _images.length; i++)
              Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    // A PDF has no thumbnail; decoding its bytes as an image
                    // would throw, so it gets an icon instead.
                    child: _images[i].mimeType == 'application/pdf'
                        ? Container(
                            color: AppColors.warmFill,
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              color: AppColors.primary,
                              size: 30,
                            ),
                          )
                        : Image.memory(_images[i].bytes, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _images.removeAt(i)),
                      child: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            if (_images.length < _maxImages)
              GestureDetector(
                onTap: _pickFile,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.upload_file_outlined,
                        color: AppColors.primary,
                        size: 30,
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          context.l10n.importFromFile,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_images.length < _maxImages)
              GestureDetector(
                onTap: _pickImages,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.add_photo_alternate_outlined,
                        color: AppColors.primary,
                        size: 30,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.addPhotos,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _images.isEmpty ? null : _extract,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          icon: const Icon(Icons.auto_awesome, size: 19),
          label: Text(context.l10n.extractMenuAction),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(child: Divider(color: AppColors.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                context.l10n.or,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textFaint,
                ),
              ),
            ),
            const Expanded(child: Divider(color: AppColors.border)),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.link_rounded, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      context.l10n.importFromLink,
                      style: AppType.heading(15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                context.l10n.menuUrlHint,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _url,
                autocorrect: false,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.url,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) =>
                    _url.text.trim().isEmpty ? null : _extractFromUrl(),
                decoration: InputDecoration(
                  labelText: context.l10n.menuUrlLabel,
                  hintText: 'https://',
                  prefixIcon: const Icon(Icons.public_rounded),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _url.text.trim().isEmpty ? null : _extractFromUrl,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: Text(context.l10n.extractFromLink),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reviewView() {
    final total = _menu.fold<int>(0, (n, c) => n + c.items.length);
    final options = _menu.fold<int>(
      0,
      (n, c) => n + c.items.fold<int>(0, (m, i) => m + i.options.length),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.reviewExtractedMenu,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                options == 0 ? '$total' : '$total · $options',
                style: AppType.mono(14, color: AppColors.primaryDark),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            children: [
              for (final category in _menu) ...[
                // Tappable for the same reason items are: both names have to be
                // fixable before the menu is committed.
                InkWell(
                  onTap: () => _editCategory(category),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(
                      top: 10,
                      bottom: 6,
                    ),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            [category.name, category.nameAr]
                                .where((part) => part.isNotEmpty)
                                .join(' · ')
                                .toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (category.isMissingTranslation)
                          const Icon(
                            Icons.translate_rounded,
                            size: 14,
                            color: AppColors.amberInk,
                          ),
                        const Icon(
                          Icons.edit_outlined,
                          size: 13,
                          color: AppColors.textFaint,
                        ),
                      ],
                    ),
                  ),
                ),
                for (final item in category.items)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          dense: true,
                          onTap: () => _editItem(item),
                          // Both names are shown so a missing translation is
                          // obvious before the menu is committed.
                          title: Text(
                            [
                              item.name,
                              item.nameAr,
                            ].where((part) => part.isNotEmpty).join('  ·  '),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle:
                              item.description.isEmpty &&
                                  item.descriptionAr.isEmpty
                              ? null
                              : Text(
                                  [item.description, item.descriptionAr]
                                      .where((part) => part.isNotEmpty)
                                      .join('  ·  '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (item.isMissingTranslation)
                                const Padding(
                                  padding: EdgeInsetsDirectional.only(end: 6),
                                  child: Icon(
                                    Icons.translate_rounded,
                                    size: 16,
                                    color: AppColors.amberInk,
                                  ),
                                ),
                              Text(
                                formatMoney(item.price),
                                style: AppType.mono(
                                  13,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: AppColors.textFaint,
                                ),
                                onPressed: () =>
                                    setState(() => category.items.remove(item)),
                              ),
                            ],
                          ),
                        ),
                        // Sizes and extras, so nothing is imported that the
                        // operator has not seen. Each group can be dropped here,
                        // which is the one correction worth making before import:
                        // the rest belongs in the product editor afterwards.
                        for (final group in item.options)
                          _OptionGroupRow(
                            group: group,
                            onRemove: () =>
                                setState(() => item.options.remove(group)),
                          ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: FilledButton.icon(
            onPressed: total == 0 ? null : _import,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            icon: const Icon(Icons.download_done_rounded, size: 20),
            label: Text('${context.l10n.importAll} ($total)'),
          ),
        ),
      ],
    );
  }
}
