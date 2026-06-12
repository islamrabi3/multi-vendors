import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/product.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';
import '../menu_cubit.dart';
import 'product_editor_screen.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendor = context.read<AuthCubit>().state.vendor;
    if (vendor == null) return const LoadingView();
    return BlocProvider(
      create: (_) => MenuCubit(
          CatalogRepository(), VendorAdminRepository(), vendor.id),
      child: const _MenuView(),
    );
  }
}

class _MenuView extends StatelessWidget {
  const _MenuView();

  Future<void> _editCategory(BuildContext context,
      {ProductCategory? category}) async {
    final cubit = context.read<MenuCubit>();
    final controller = TextEditingController(text: category?.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(category == null ? 'New section' : 'Rename section'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Section name'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await cubit.saveCategory(name, id: category?.id);
    }
  }

  Future<void> _openEditor(BuildContext context, {Product? product}) async {
    final cubit = context.read<MenuCubit>();
    await context.push('/vendor-app/product-editor',
        extra: ProductEditorArgs(
          vendorId: cubit.vendorId,
          categories: cubit.state.categories,
          product: product,
        ));
    cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Menu'),
        actions: [
          IconButton(
            tooltip: 'Add section',
            onPressed: () => _editCategory(context),
            icon: const Icon(Icons.create_new_folder_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Product'),
      ),
      body: BlocBuilder<MenuCubit, MenuState>(
        builder: (context, state) {
          if (state.loading) return const LoadingView();
          if (state.error != null) {
            return ErrorView(
                message: 'Could not load the menu.',
                onRetry: context.read<MenuCubit>().load);
          }
          if (state.categories.isEmpty && state.products.isEmpty) {
            return const EmptyView(
              message: 'Add a section, then your first product',
              icon: Icons.menu_book_outlined,
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final category in state.categories) ...[
                ListTile(
                  title: Text(category.name,
                      style: Theme.of(context).textTheme.titleMedium),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => action == 'rename'
                        ? _editCategory(context, category: category)
                        : context
                            .read<MenuCubit>()
                            .deleteCategory(category.id),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Rename')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ),
                for (final product in state.productsIn(category.id))
                  _ProductTile(
                      product: product,
                      onEdit: () => _openEditor(context, product: product)),
              ],
              if (state.uncategorized.isNotEmpty) ...[
                ListTile(
                  title: Text('Other',
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                for (final product in state.uncategorized)
                  _ProductTile(
                      product: product,
                      onEdit: () => _openEditor(context, product: product)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onEdit});

  final Product product;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: AppNetworkImage(
          url: product.imageUrl,
          height: 44,
          width: 44,
          borderRadius: BorderRadius.circular(8)),
      title: Text(product.name),
      subtitle: Text(formatMoney(product.price)),
      onTap: onEdit,
      trailing: Switch(
        value: product.isAvailable,
        onChanged: (_) =>
            context.read<MenuCubit>().toggleAvailability(product),
      ),
    );
  }
}
