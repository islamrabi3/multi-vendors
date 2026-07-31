import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

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
  late final _description =
      TextEditingController(text: widget.args.product?.description);
  late final _descriptionAr =
      TextEditingController(text: widget.args.product?.descriptionAr);
  late final _price = TextEditingController(
      text: widget.args.product?.price.toStringAsFixed(2));
  late String? _categoryId = widget.args.product?.categoryId;
  late String? _imageUrl = widget.args.product?.imageUrl;
  late bool _isAvailable = widget.args.product?.isAvailable ?? true;
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
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 1200);
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
      if (mounted) showSnack(context, readableError(error), error: true);
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
      }, id: _product?.id);
      if (!mounted) return;
      setState(() => _product = saved);
      await _reloadProduct();
      if (mounted) showSnack(context, context.l10n.productSaved);
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
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
      message: '${context.l10n.remove} "${product.name}" ${context.l10n.fromTheMenu}',
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
        showSnack(context, 'Please enter product name and valid price first', error: true);
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
    final confirmed = await showModalBottomSheet<bool>(
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
                      prefixIcon: const Icon(Icons.remove_circle_outline_rounded),
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
    final confirmed = await showModalBottomSheet<bool>(
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
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.l10n.extraPriceEgp,
                prefixIcon: const Icon(Icons.payments_outlined),
                suffixText: 'EGP',
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
    final picked = await showModalBottomSheet<String>(
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
              child: Text(context.l10n.selectSection,
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final cat in widget.args.categories)
              ListTile(
                title: Text(cat.name),
                trailing: _categoryId == cat.id
                    ? Icon(Icons.check,
                        color: Theme.of(ctx).colorScheme.primary)
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

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(product == null ? context.l10n.newProduct : context.l10n.editProduct),
        actions: [
          if (product != null)
            IconButton(
              tooltip: context.l10n.deleteProduct,
              icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            // Image picker widget
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.xl),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    AppNetworkImage(
                      url: _imageUrl,
                      height: 180,
                      width: double.infinity,
                    ),
                    Container(
                      color: _imageUrl != null
                          ? Colors.black26
                          : Colors.black45,
                      width: double.infinity,
                      height: 180,
                    ),
                    if (_uploading)
                      const Positioned.fill(
                          child: Center(child: CircularProgressIndicator(color: Colors.white)))
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
                                    ? context.l10n.tapToChangePhoto
                                    : context.l10n.tapToAddPhoto,
                                style:
                                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Basic Info Section
            _SectionLabel(context.l10n.basicInfo),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText:
                    '${context.l10n.productName} · ${context.l10n.english}',
                prefixIcon: const Icon(Icons.fastfood_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.l10n.required : null,
            ),
            const SizedBox(height: 12),
            // Optional: customers reading the other language fall back to the
            // canonical name, so a store can list items in one language only.
            TextFormField(
              controller: _nameAr,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                labelText:
                    '${context.l10n.productName} · ${context.l10n.arabic}',
                prefixIcon: const Icon(Icons.translate_rounded),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText:
                    '${context.l10n.description} · ${context.l10n.english}',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsetsDirectional.only(bottom: 40),
                  child: Icon(Icons.notes_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionAr,
              maxLines: 3,
              textDirection: TextDirection.rtl,
              decoration: InputDecoration(
                labelText:
                    '${context.l10n.description} · ${context.l10n.arabic}',
                alignLabelWithHint: true,
                prefixIcon: const Padding(
                  padding: EdgeInsetsDirectional.only(bottom: 40),
                  child: Icon(Icons.translate_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border: Border.all(color: AppColors.border),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                title: Text(context.l10n.availableForOrdering,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.ink)),
                subtitle: Text(
                  _isAvailable
                      ? context.l10n.customersCanAddThisToTheirCart
                      : context.l10n.hiddenFromCustomers,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                value: _isAvailable,
                activeThumbColor: Colors.white,
                activeTrackColor: AppColors.success,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: AppColors.border,
                onChanged: (v) => setState(() => _isAvailable = v),
              ),
            ),
            const SizedBox(height: 24),

            // Pricing & category section
            _SectionLabel(context.l10n.pricingAndCategory),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.l10n.price,
                prefixIcon: const Icon(Icons.payments_outlined),
                suffixText: 'EGP',
              ),
              validator: (v) =>
                  double.tryParse(v ?? '') == null ? context.l10n.enterAValidPrice : null,
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: widget.args.categories.isEmpty ? null : _pickCategory,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: context.l10n.section,
                  prefixIcon: const Icon(Icons.category_outlined),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  enabled: widget.args.categories.isNotEmpty,
                ),
                child: Text(
                  _selectedCategoryName ??
                      (widget.args.categories.isEmpty
                          ? context.l10n.noSectionsAddOneFirst
                          : context.l10n.selectSection),
                  style: TextStyle(
                    color: _categoryId == null
                        ? Theme.of(context).hintColor
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 28),

            // Options list
             Row(
              children: [
                _SectionLabel(context.l10n.options),
                const Spacer(),
                TextButton.icon(
                  onPressed: _saving ? null : _addOptionGroup,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(context.l10n.addGroup, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (product == null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Text(
                  context.l10n.saveProductFirstToOption,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                  textAlign: TextAlign.center,
                ),
              )
            else if (product.optionGroups.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Text(
                  context.l10n.noOptionGroupsYet,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 13.5),
                  textAlign: TextAlign.center,
                ),
              )
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
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.borderSoft)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: SafeArea(
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.lg),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
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
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(product == null ? context.l10n.createProduct : context.l10n.saveChanges,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
          ),
        ),
      ),
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
          text.toUpperCase(),
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w800,
            fontSize: 12,
            letterSpacing: 1.1,
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
                      Text(group.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        '${context.l10n.pick} ${group.minSelect}–${group.maxSelect}',
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.textMuted, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
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
                      const Icon(Icons.radio_button_unchecked_rounded,
                          size: 14, color: AppColors.textFaint),
                      const SizedBox(width: 8),
                      Expanded(child: Text(option.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.ink))),
                      if (option.priceDelta != 0)
                        Text('+${formatMoney(option.priceDelta)}',
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12.5)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 16, color: AppColors.textMuted),
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
