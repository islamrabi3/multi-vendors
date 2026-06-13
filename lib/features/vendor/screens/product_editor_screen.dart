import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/product.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';

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
  late final _description =
      TextEditingController(text: widget.args.product?.description);
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
    _description.dispose();
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
      final saved = await _admin.saveProduct({
        'vendor_id': widget.args.vendorId,
        'category_id': _categoryId,
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'price': double.parse(_price.text),
        'image_url': _imageUrl,
        'is_available': _isAvailable,
      }, id: _product?.id);
      if (!mounted) return;
      setState(() => _product = saved);
      await _reloadProduct();
      if (mounted) showSnack(context, 'Product saved');
    } catch (error) {
      if (mounted) showSnack(context, readableError(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final product = _product;
    if (product == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete product?'),
        content: Text('Remove "${product.name}" from the menu?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _admin.deleteProduct(product.id);
      if (!mounted) return;
      Navigator.pop(context);
    }
  }

  Future<void> _addOptionGroup() async {
    final product = _product;
    if (product == null) return;
    final nameController = TextEditingController();
    final minController = TextEditingController(text: '0');
    final maxController = TextEditingController(text: '1');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New option group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration:
                  const InputDecoration(labelText: 'Name (Size, Add-ons…)'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: minController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Min select'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: maxController,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Max select'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add')),
        ],
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add option to ${group.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Option name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'Extra price (EGP)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Add')),
        ],
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
              child: Text('Select section',
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
      appBar: AppBar(
        title: Text(product == null ? 'New product' : 'Edit product'),
        actions: [
          if (product != null)
            IconButton(
              tooltip: 'Delete product',
              icon: Icon(Icons.delete_outline, color: scheme.error),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            // ── Image picker ─────────────────────────────────────────
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
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
                          child: Center(child: CircularProgressIndicator()))
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
                                    ? 'Tap to change photo'
                                    : 'Tap to add photo',
                                style:
                                    const TextStyle(color: Colors.white70),
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

            // ── Basic info ────────────────────────────────────────────
            _SectionLabel('Basic info'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Product name',
                prefixIcon: Icon(Icons.fastfood_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: EdgeInsets.only(bottom: 40),
                  child: Icon(Icons.notes_outlined),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Available for ordering'),
              subtitle: Text(
                _isAvailable
                    ? 'Customers can add this to their cart'
                    : 'Hidden from customers',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              value: _isAvailable,
              onChanged: (v) => setState(() => _isAvailable = v),
            ),
            const SizedBox(height: 16),

            // ── Pricing & category ────────────────────────────────────
            _SectionLabel('Pricing & category'),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price',
                prefixIcon: Icon(Icons.payments_outlined),
                suffixText: 'EGP',
              ),
              validator: (v) =>
                  double.tryParse(v ?? '') == null ? 'Enter a valid price' : null,
            ),
            const SizedBox(height: 12),
            // Section picker — tappable field that opens a bottom sheet
            InkWell(
              onTap: widget.args.categories.isEmpty ? null : _pickCategory,
              borderRadius: BorderRadius.circular(12),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Section',
                  prefixIcon: const Icon(Icons.category_outlined),
                  suffixIcon: const Icon(Icons.arrow_drop_down),
                  enabled: widget.args.categories.isNotEmpty,
                ),
                child: Text(
                  _selectedCategoryName ??
                      (widget.args.categories.isEmpty
                          ? 'No sections — add one first'
                          : 'Select a section'),
                  style: TextStyle(
                    color: _categoryId == null
                        ? Theme.of(context).hintColor
                        : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // ── Options ───────────────────────────────────────────────
            Row(
              children: [
                _SectionLabel('Options'),
                const Spacer(),
                TextButton.icon(
                  onPressed: product == null ? null : _addOptionGroup,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add group'),
                ),
              ],
            ),
            if (product == null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Save the product first to add option groups.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else if (product.optionGroups.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No option groups yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
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
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(product == null ? 'Create product' : 'Save changes'),
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
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
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
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                          style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        'Pick ${group.minSelect}–${group.maxSelect}',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Add option',
                  onPressed: onAddOption,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  tooltip: 'Delete group',
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
                      const Icon(Icons.radio_button_unchecked,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 8),
                      Expanded(child: Text(option.name)),
                      if (option.priceDelta != 0)
                        Text('+${formatMoney(option.priceDelta)}',
                            style: TextStyle(color: scheme.primary)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
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
