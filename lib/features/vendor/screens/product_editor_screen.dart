import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/console.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';

class ProductEditorArgs {
  const ProductEditorArgs({
    required this.vendorId,
    required this.categories,
    this.product,
  });

  final String vendorId;
  final List<ProductCategory> categories;
  final Product? product;
}

class ProductEditorScreen extends StatefulWidget {
  const ProductEditorScreen({super.key, required this.args});

  final ProductEditorArgs args;

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  final _admin = VendorAdminRepository();
  final _catalog = CatalogRepository();
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.args.product?.name);
  late final _nameAr = TextEditingController(text: widget.args.product?.nameAr);
  late final _description = TextEditingController(
    text: widget.args.product?.description,
  );
  late final _descriptionAr = TextEditingController(
    text: widget.args.product?.descriptionAr,
  );
  late final _price = TextEditingController(
    text: widget.args.product?.price.toStringAsFixed(2),
  );
  late String? _categoryId = widget.args.product?.categoryId;
  late String? _imageUrl = widget.args.product?.imageUrl;
  late bool _isAvailable = widget.args.product?.isAvailable ?? true;

  // Stock. Off by default: a kitchen does not count portions, and turning this
  // on for a restaurant would make every item silently run out.
  late bool _trackStock = widget.args.product?.trackStock ?? false;
  late final _stock = TextEditingController(
    text: '${widget.args.product?.stockQuantity ?? 0}',
  );
  late final _lowStock = TextEditingController(
    text: '${widget.args.product?.lowStockThreshold ?? 0}',
  );
  Product? _product;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _product = widget.args.product;
  }

  @override
  void dispose() {
    _stock.dispose();
    _lowStock.dispose();
    _name.dispose();
    _nameAr.dispose();
    _description.dispose();
    _descriptionAr.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _reloadProduct() async {
    final id = _product?.id;
    if (id == null) return;
    final products = await _catalog.fetchProductsByIds([id]);
    if (mounted && products.isNotEmpty) {
      setState(() => _product = products.first);
    }
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
    );
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final url = await _admin.uploadImage(
        bucket: 'product-images',
        path:
            '${widget.args.vendorId}/${DateTime.now().millisecondsSinceEpoch}_${file.name}',
        bytes: bytes,
      );
      setState(() => _imageUrl = url);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      // Blank translations are stored as null so the display fallback can
      // tell "not translated" from "translated to an empty string".
      final saved = await _admin.saveProduct({
        'vendor_id': widget.args.vendorId,
        'category_id': _categoryId,
        'name': _name.text.trim(),
        'name_ar': _nameAr.text.trim().isEmpty ? null : _nameAr.text.trim(),
        'description': _description.text.trim(),
        'description_ar': _descriptionAr.text.trim().isEmpty
            ? null
            : _descriptionAr.text.trim(),
        'price': double.parse(_price.text),
        'image_url': _imageUrl,
        'is_available': _isAvailable,
        'track_stock': _trackStock,
        // Only meaningful when tracking; sent regardless so turning tracking
        // off and on again does not resurrect a stale count.
        'stock_quantity': _trackStock
            ? (int.tryParse(_stock.text.trim()) ?? 0)
            : 0,
        'low_stock_threshold': _trackStock
            ? (int.tryParse(_lowStock.text.trim()) ?? 0)
            : 0,
      }, id: _product?.id);
      if (!mounted) return;
      setState(() => _product = saved);
      await _reloadProduct();
      if (mounted) showSnack(context, context.l10n.productSaved);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final product = _product;
    if (product == null) return;
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: context.l10n.deleteProduct,
      message:
          '${context.l10n.remove} "${product.name}" ${context.l10n.fromTheMenu}',
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed == true) {
      await _admin.deleteProduct(product.id);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  Future<void> _addOptionGroup() async {
    if (_product == null) {
      if (!_formKey.currentState!.validate()) {
        showSnack(
          context,
          'Please enter product name and valid price first',
          error: true,
        );
        return;
      }
      await _save();
      if (!mounted) return;
      if (_product == null) return;
    }
    final product = _product!;
    final nameController = TextEditingController();
    final minController = TextEditingController(text: '0');
    final maxController = TextEditingController(text: '1');
    final confirmed = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              context.l10n.newOptionGroup,
              style: AppType.heading(19, color: AppColors.ink),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.nameSizeAddons,
                prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.minSelect,
                      prefixIcon: const Icon(
                        Icons.remove_circle_outline_rounded,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: maxController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: context.l10n.maxSelect,
                      prefixIcon: const Icon(Icons.add_circle_outline_rounded),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: Text(context.l10n.add),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      await _admin.saveOptionGroup(
        productId: product.id,
        name: nameController.text.trim(),
        minSelect: int.tryParse(minController.text) ?? 0,
        maxSelect: int.tryParse(maxController.text) ?? 1,
      );
      await _reloadProduct();
    }
  }

  Future<void> _addOption(ProductOptionGroup group) async {
    final nameController = TextEditingController();
    final priceController = TextEditingController(text: '0');
    final confirmed = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          left: 20,
          right: 20,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              '${context.l10n.addOptionTo} ${group.name}',
              style: AppType.heading(19, color: AppColors.ink),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.l10n.optionName,
                prefixIcon: const Icon(Icons.label_outline_rounded),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.l10n.extraPriceEgp(currencySymbol),
                prefixIcon: const Icon(Icons.payments_outlined),
                suffixText: currencySymbol,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                    ),
                    onPressed: () => Navigator.pop(sheetContext, false),
                    child: Text(context.l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadii.lg),
                        ),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: Text(context.l10n.add),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      await _admin.saveOption(
        groupId: group.id,
        name: nameController.text.trim(),
        priceDelta: double.tryParse(priceController.text) ?? 0,
      );
      await _reloadProduct();
    }
  }

  String? get _selectedCategoryName => widget.args.categories
      .where((c) => c.id == _categoryId)
      .map((c) => c.name)
      .firstOrNull;

  Future<void> _pickCategory() async {
    final picked = await showAdaptiveSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                context.l10n.selectSection,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final cat in widget.args.categories)
              ListTile(
                title: Text(cat.name),
                trailing: _categoryId == cat.id
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, cat.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _categoryId = picked);
  }

  @override
  Widget build(BuildContext context) {
    final product = _product;
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    Widget photo({required double height}) => GestureDetector(
      onTap: _uploading ? null : _pickImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            AppNetworkImage(
              url: _imageUrl,
              height: height,
              width: double.infinity,
            ),
            Container(
              color: _imageUrl != null ? Colors.black26 : Colors.black45,
              width: double.infinity,
              height: height,
            ),
            if (_uploading)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              )
            else
              Positioned.fill(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _imageUrl != null
                            ? Icons.edit_outlined
                            : Icons.add_photo_alternate_outlined,
                        color: Colors.white,
                        size: 36,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _imageUrl != null
                            ? l10n.tapToChangePhoto
                            : l10n.tapToAddPhoto,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final nameEn = TextFormField(
      controller: _name,
      textCapitalization: TextCapitalization.words,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: '${l10n.productName} · ${l10n.english}',
        prefixIcon: const Icon(Icons.fastfood_outlined),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? l10n.required : null,
    );
    // Optional: customers reading the other language fall back to the
    // canonical name, so a store can list items in one language only.
    final nameAr = TextFormField(
      controller: _nameAr,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: '${l10n.productName} · ${l10n.arabic}',
        prefixIcon: const Icon(Icons.translate_rounded),
      ),
    );
    final descriptionEn = TextFormField(
      controller: _description,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: '${l10n.description} · ${l10n.english}',
        alignLabelWithHint: true,
        prefixIcon: const Padding(
          padding: EdgeInsetsDirectional.only(bottom: 40),
          child: Icon(Icons.notes_outlined),
        ),
      ),
    );
    final descriptionAr = TextFormField(
      controller: _descriptionAr,
      maxLines: 3,
      textDirection: TextDirection.rtl,
      decoration: InputDecoration(
        labelText: '${l10n.description} · ${l10n.arabic}',
        alignLabelWithHint: true,
        prefixIcon: const Padding(
          padding: EdgeInsetsDirectional.only(bottom: 40),
          child: Icon(Icons.translate_rounded),
        ),
      ),
    );

    Widget switchTile({
      required String title,
      required String subtitle,
      required bool value,
      required ValueChanged<bool> onChanged,
      EdgeInsetsGeometry padding = const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 2,
      ),
    }) => SwitchListTile(
      contentPadding: padding,
      // The narrow desktop column needs the explanation's second line.
      isThreeLine: padding == EdgeInsets.zero,
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          color: AppColors.ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      value: value,
      activeThumbColor: Colors.white,
      activeTrackColor: AppColors.success,
      inactiveThumbColor: Colors.white,
      inactiveTrackColor: AppColors.border,
      onChanged: onChanged,
    );

    Widget availableTile({EdgeInsetsGeometry? padding}) => switchTile(
      title: l10n.availableForOrdering,
      subtitle: _isAvailable
          ? l10n.customersCanAddThisToTheirCart
          : l10n.hiddenFromCustomers,
      value: _isAvailable,
      onChanged: (v) => setState(() => _isAvailable = v),
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );

    // Stock. A restaurant leaves this off and nothing changes; a pharmacy or
    // grocery turns it on and the item stops being orderable at zero without
    // anyone remembering to hide it.
    Widget stock({EdgeInsetsGeometry? padding, bool stacked = false}) {
      final quantity = TextFormField(
        controller: _stock,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: l10n.stockQuantity),
      );
      final threshold = TextFormField(
        controller: _lowStock,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: l10n.lowStockThreshold,
          helperText: l10n.lowStockThresholdHint,
          helperMaxLines: 2,
        ),
      );
      return Column(
        children: [
          switchTile(
            title: l10n.trackStock,
            subtitle: _trackStock ? l10n.trackStockOn : l10n.trackStockOff,
            value: _trackStock,
            onChanged: (v) => setState(() => _trackStock = v),
            padding:
                padding ??
                const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          ),
          if (_trackStock)
            Padding(
              padding: stacked
                  ? const EdgeInsets.only(top: 8)
                  : const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: stacked
                  ? Column(
                      children: [
                        quantity,
                        const SizedBox(height: 12),
                        threshold,
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(child: quantity),
                        const SizedBox(width: 12),
                        Expanded(child: threshold),
                      ],
                    ),
            ),
        ],
      );
    }

    final price = TextFormField(
      controller: _price,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: l10n.price,
        prefixIcon: const Icon(Icons.payments_outlined),
        suffixText: currencySymbol,
      ),
      validator: (v) =>
          double.tryParse(v ?? '') == null ? l10n.enterAValidPrice : null,
    );
    final section = InkWell(
      onTap: widget.args.categories.isEmpty ? null : _pickCategory,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: l10n.section,
          prefixIcon: const Icon(Icons.category_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down),
          enabled: widget.args.categories.isNotEmpty,
        ),
        child: Text(
          _selectedCategoryName ??
              (widget.args.categories.isEmpty
                  ? l10n.noSectionsAddOneFirst
                  : l10n.selectSection),
          style: TextStyle(
            color: _categoryId == null ? Theme.of(context).hintColor : null,
          ),
        ),
      ),
    );

    final addGroup = TextButton.icon(
      onPressed: _saving ? null : _addOptionGroup,
      icon: const Icon(Icons.add_rounded, size: 18),
      label: Text(
        l10n.addGroup,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    Widget optionsNote(String text) => Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
        textAlign: TextAlign.center,
      ),
    );
    final options = <Widget>[
      if (product == null)
        optionsNote(l10n.saveProductFirstToOption)
      else if (product.optionGroups.isEmpty)
        optionsNote(l10n.noOptionGroupsYet)
      else
        for (final group in product.optionGroups)
          _OptionGroupCard(
            group: group,
            onAddOption: () => _addOption(group),
            onDeleteGroup: () async {
              await _admin.deleteOptionGroup(group.id);
              await _reloadProduct();
            },
            onDeleteOption: (optionId) async {
              await _admin.deleteOption(optionId);
              await _reloadProduct();
            },
          ),
    ];
    final saveLabel = _saving
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(
            product == null ? l10n.createProduct : l10n.saveChanges,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          );

    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(product == null ? l10n.newProduct : l10n.editProduct),
        actions: [
          if (product != null)
            IconButton(
              tooltip: l10n.deleteProduct,
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              onPressed: _confirmDelete,
            ),
          if (wide) ...[
            const SizedBox(width: 8),
            FilledButton(onPressed: _saving ? null : _save, child: saveLabel),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: Form(
        key: _formKey,
        child: wide
            ? _wideBody(
                photo: photo(height: 220),
                names: [nameEn, nameAr],
                descriptions: [descriptionEn, descriptionAr],
                pricing: [price, section],
                availability: [
                  availableTile(padding: EdgeInsets.zero),
                  const Divider(height: 24, color: AppColors.borderSoft),
                  stock(padding: EdgeInsets.zero, stacked: true),
                ],
                addGroup: addGroup,
                options: options,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  photo(height: 180),
                  const SizedBox(height: 24),
                  _SectionLabel(l10n.basicInfo),
                  const SizedBox(height: 12),
                  nameEn,
                  const SizedBox(height: 12),
                  nameAr,
                  const SizedBox(height: 12),
                  descriptionEn,
                  const SizedBox(height: 12),
                  descriptionAr,
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: availableTile(),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: stock(),
                  ),
                  const SizedBox(height: 24),
                  _SectionLabel(l10n.pricingAndCategory),
                  const SizedBox(height: 12),
                  price,
                  const SizedBox(height: 12),
                  section,
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      _SectionLabel(l10n.options),
                      const Spacer(),
                      addGroup,
                    ],
                  ),
                  const SizedBox(height: 4),
                  ...options,
                ],
              ),
      ),
      bottomNavigationBar: wide
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.borderSoft)),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SafeArea(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                  ),
                  onPressed: _saving ? null : _save,
                  child: saveLabel,
                ),
              ),
            ),
    );
  }

  /// Desktop: what the dish is (names, descriptions, options) on the left;
  /// how it sells (photo, price, section, availability) on the right. Save
  /// sits in the title bar rather than in a bar across the whole window.
  Widget _wideBody({
    required Widget photo,
    required List<Widget> names,
    required List<Widget> descriptions,
    required List<Widget> pricing,
    required List<Widget> availability,
    required Widget addGroup,
    required List<Widget> options,
  }) {
    final l10n = context.l10n;
    Widget pair(List<Widget> fields) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: fields[0]),
        const SizedBox(width: 16),
        Expanded(child: fields[1]),
      ],
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 48),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConsolePanel(
                        title: l10n.basicInfo,
                        child: Column(
                          children: [
                            pair(names),
                            const SizedBox(height: 16),
                            pair(descriptions),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ConsolePanel(
                        title: l10n.options,
                        trailing: addGroup,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: options,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 360,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ConsolePanel(
                        title: l10n.photoSection,
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: photo,
                      ),
                      const SizedBox(height: 16),
                      ConsolePanel(
                        title: l10n.pricingAndCategory,
                        child: Column(
                          children: [
                            pricing[0],
                            const SizedBox(height: 16),
                            pricing[1],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      ConsolePanel(
                        title: l10n.availabilitySection,
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                        child: Column(children: availability),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.primary,
        fontWeight: FontWeight.w800,
        fontSize: 13.5,
      ),
    ),
  );
}

class _OptionGroupCard extends StatelessWidget {
  const _OptionGroupCard({
    required this.group,
    required this.onAddOption,
    required this.onDeleteGroup,
    required this.onDeleteOption,
  });

  final ProductOptionGroup group;
  final VoidCallback onAddOption;
  final VoidCallback onDeleteGroup;
  final ValueChanged<String> onDeleteOption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${context.l10n.pick} ${group.minSelect}–${group.maxSelect}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                  ),
                  tooltip: context.l10n.addOption,
                  onPressed: onAddOption,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
                  tooltip: context.l10n.deleteGroup,
                  onPressed: onDeleteGroup,
                ),
              ],
            ),
            if (group.options.isNotEmpty) ...[
              const Divider(height: 16),
              for (final option in group.options)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.radio_button_unchecked_rounded,
                        size: 14,
                        color: AppColors.textFaint,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          option.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      if (option.priceDelta != 0)
                        Text(
                          '+${formatMoney(option.priceDelta)}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: AppColors.textMuted,
                        ),
                        onPressed: () => onDeleteOption(option.id),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
