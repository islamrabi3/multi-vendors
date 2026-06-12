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

/// Create/edit a product. Option groups become editable after first save
/// (they need a product id to attach to).
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

  @override
  Widget build(BuildContext context) {
    final product = _product;
    return Scaffold(
      appBar: AppBar(
        title: Text(product == null ? 'New product' : 'Edit product'),
        actions: [
          if (product != null)
            IconButton(
              tooltip: 'Delete product',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await _admin.deleteProduct(product.id);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GestureDetector(
              onTap: _uploading ? null : _pickImage,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AppNetworkImage(
                      url: _imageUrl,
                      height: 160,
                      width: double.infinity,
                      borderRadius: BorderRadius.circular(16)),
                  if (_uploading)
                    const CircularProgressIndicator()
                  else
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_outlined,
                          color: Colors.white),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Price (EGP)'),
                    validator: (v) =>
                        double.tryParse(v ?? '') == null ? 'Invalid' : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: const InputDecoration(labelText: 'Section'),
                    items: [
                      for (final category in widget.args.categories)
                        DropdownMenuItem(
                            value: category.id, child: Text(category.name)),
                    ],
                    onChanged: (value) => setState(() => _categoryId = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(product == null ? 'Create product' : 'Save changes'),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Text('Options',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: product == null ? null : _addOptionGroup,
                  icon: const Icon(Icons.add),
                  label: const Text('Group'),
                ),
              ],
            ),
            if (product == null)
              const Text('Save the product first to add options.',
                  style: TextStyle(color: Colors.grey))
            else
              for (final group in product.optionGroups)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${group.name}  '
                                '(${group.minSelect}–${group.maxSelect})',
                                style:
                                    Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add),
                              onPressed: () => _addOption(group),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () async {
                                await _admin.deleteOptionGroup(group.id);
                                await _reloadProduct();
                              },
                            ),
                          ],
                        ),
                        for (final option in group.options)
                          Row(
                            children: [
                              Expanded(child: Text(option.name)),
                              if (option.priceDelta != 0)
                                Text('+${formatMoney(option.priceDelta)}'),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () async {
                                  await _admin.deleteOption(option.id);
                                  await _reloadProduct();
                                },
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
