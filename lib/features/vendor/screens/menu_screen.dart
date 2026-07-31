import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/tokens.dart';
import '../../../core/models/product.dart';
import '../../../core/repositories/catalog_repository.dart';
import '../../../core/repositories/vendor_admin_repository.dart';
import '../../../core/utils/money.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';
import '../menu_cubit.dart';
import 'product_editor_screen.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vendor = context.read<AuthCubit>().state.vendor;
    if (vendor == null) return const LoadingView();
    return BlocProvider(
      create: (_) =>
          MenuCubit(CatalogRepository(), VendorAdminRepository(), vendor.id),
      child: const _MenuView(),
    );
  }
}

class _MenuView extends StatefulWidget {
  const _MenuView();

  @override
  State<_MenuView> createState() => _MenuViewState();
}

class _MenuViewState extends State<_MenuView> {
  // null = "All" filter.
  String? _filterCategoryId;

  Future<void> _editCategory(
    BuildContext context, {
    ProductCategory? category,
  }) async {
    final cubit = context.read<MenuCubit>();
    final controller = TextEditingController(text: category?.name);
    final controllerAr = TextEditingController(text: category?.nameAr);
    final isNew = category == null;

    final String? result = await AppDialogs.showFormDialog<String>(
      context: context,
      title: isNew ? context.l10n.newSection : context.l10n.renameSection,
      subtitle: isNew
          ? context.l10n.addCategorySectionDesc
          : context.l10n.modifyCategoryNameDesc,
      icon: isNew ? Icons.create_new_folder_rounded : Icons.edit_note_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText:
                  '${context.l10n.sectionName} · ${context.l10n.english}',
              hintText: context.l10n.sectionHint,
              prefixIcon: const Icon(Icons.category_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          // Optional: the Arabic UI falls back to the canonical name.
          TextField(
            controller: controllerAr,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: '${context.l10n.sectionName} · ${context.l10n.arabic}',
              prefixIcon: const Icon(Icons.translate_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
            ),
          ),
        ],
      ),
      primaryText: context.l10n.save,
      onPrimaryPressed: () => Navigator.pop(context, controller.text.trim()),
      secondaryText: isNew ? context.l10n.cancel : null,
      destructiveText: !isNew ? context.l10n.delete : null,
      onDestructivePressed: !isNew
          ? () {
              Navigator.pop(context);
              cubit.deleteCategory(category.id);
              if (_filterCategoryId == category.id) {
                setState(() => _filterCategoryId = null);
              }
            }
          : null,
    );

    if (result != null && result.isNotEmpty) {
      await cubit.saveCategory(result,
          nameAr: controllerAr.text.trim(), id: category?.id);
    }
    controller.dispose();
    controllerAr.dispose();
  }

  Future<void> _openEditor(BuildContext context, {Product? product}) async {
    final cubit = context.read<MenuCubit>();
    await context.push(
      '/vendor-app/product-editor',
      extra: ProductEditorArgs(
        vendorId: cubit.vendorId,
        categories: cubit.state.categories,
        product: product,
      ),
    );
    cubit.load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = AppBreakpoints.isSplit(constraints.maxWidth);
          return BlocBuilder<MenuCubit, MenuState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(context),
                  if (state.loading)
                    const Expanded(child: LoadingView())
                  else if (state.error != null)
                    Expanded(
                      child: ErrorView(
                        message: context.l10n.couldNotLoadTheMenu,
                        onRetry: context.read<MenuCubit>().load,
                      ),
                    )
                  else if (state.categories.isEmpty && state.products.isEmpty)
                    Expanded(
                      child: EmptyView(
                        message: context.l10n.addASectionThenYourFirstProduct,
                        icon: Icons.menu_book_outlined,
                      ),
                    )
                  else if (split)
                    // Desktop: sections become a rail beside a grid of items.
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 260,
                            child: _SectionRail(
                              state: state,
                              selectedId: _filterCategoryId,
                              onSelect: (id) =>
                                  setState(() => _filterCategoryId = id),
                              onEdit: (c) =>
                                  _editCategory(context, category: c),
                            ),
                          ),
                          const VerticalDivider(
                              width: 1, thickness: 1, color: AppColors.border),
                          Expanded(child: _productGrid(context, state)),
                        ],
                      ),
                    )
                  else ...[
                    _categoryChips(context, state),
                    Expanded(child: _productList(context, state)),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<Product> _visibleProducts(MenuState state) => _filterCategoryId == null
      ? state.products
      : state.productsIn(_filterCategoryId!);

  Widget _productGrid(BuildContext context, MenuState state) {
    final products = _visibleProducts(state);
    if (products.isEmpty) {
      return EmptyView(
        message: context.l10n.noItemsInThisSectionYet,
        icon: Icons.lunch_dining_outlined,
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 440,
        mainAxisExtent: 92,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: products.length,
      itemBuilder: (context, i) => _ProductTile(
        product: products[i],
        onEdit: () => _openEditor(context, product: products[i]),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 12,
        16,
        12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.menu,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 26,
                color: AppColors.ink,
              ),
            ),
          ),
          // AI menu extraction lives in the admin app: each run costs money and
          // rewrites a whole catalogue, so it is an operator tool.
          IconButton(
            tooltip: context.l10n.addSection,
            onPressed: () => _editCategory(context),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.surface,
              side: const BorderSide(color: AppColors.border),
            ),
            icon: const Icon(
              Icons.create_new_folder_outlined,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: () => _openEditor(context),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(
              context.l10n.addItem,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips(BuildContext context, MenuState state) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          _chip(context, label: context.l10n.all, categoryId: null),
          for (final c in state.categories)
            _chip(
              context,
              label: '${c.name} · ${state.productsIn(c.id).length}',
              categoryId: c.id,
              onLongPress: () => _editCategory(context, category: c),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required String? categoryId,
    VoidCallback? onLongPress,
  }) {
    final selected = _filterCategoryId == categoryId;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filterCategoryId = categoryId),
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? AppColors.ink : AppColors.surface,
            border: Border.all(
              color: selected ? AppColors.ink : AppColors.border,
            ),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: selected ? AppShadows.card : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _productList(BuildContext context, MenuState state) {
    final products = _visibleProducts(state);
    if (products.isEmpty) {
      return EmptyView(
        message: context.l10n.noItemsInThisSectionYet,
        icon: Icons.lunch_dining_outlined,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      itemCount: products.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) => _ProductTile(
        product: products[i],
        onEdit: () => _openEditor(context, product: products[i]),
      ),
    );
  }
}

/// Desktop menu navigation: one row per section with its item count, plus an
/// inline rename affordance (long-press is not discoverable with a mouse).
class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.state,
    required this.selectedId,
    required this.onSelect,
    required this.onEdit,
  });

  final MenuState state;
  final String? selectedId;
  final ValueChanged<String?> onSelect;
  final ValueChanged<ProductCategory> onEdit;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 24),
      children: [
        _row(
          context,
          label: context.l10n.all,
          count: state.products.length,
          id: null,
        ),
        for (final c in state.categories)
          _row(
            context,
            label: c.displayName(
                Localizations.localeOf(context).languageCode),
            count: state.productsIn(c.id).length,
            id: c.id,
            onEdit: () => onEdit(c),
          ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required int count,
    required String? id,
    VoidCallback? onEdit,
  }) {
    final selected = selectedId == id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: HoverBuilder(
        builder: (context, hovered) => InkWell(
          onTap: () => onSelect(id),
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.ink
                  : hovered
                      ? AppColors.warmFill
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
                if (onEdit != null && hovered)
                  IconButton(
                    onPressed: onEdit,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    tooltip: context.l10n.renameSection,
                    icon: Icon(Icons.edit_outlined,
                        size: 15,
                        color: selected ? Colors.white : AppColors.textMuted),
                  )
                else
                  Text(
                    '$count',
                    style: AppType.mono(12,
                        color: selected ? Colors.white : AppColors.textFaint),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onEdit});

  final Product product;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => HoverBuilder(
        builder: (context, hovered) => _tile(context, hovered),
      );

  Widget _tile(BuildContext context, bool hovered) {
    final available = product.isAvailable;
    return Opacity(
      opacity: available ? 1 : 0.7,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
              color: hovered ? AppColors.primaryLight : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: AppShadows.card,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.xl),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onEdit,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    AppNetworkImage(
                      url: product.imageUrl,
                      height: 56,
                      width: 56,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product.displayName(
                                Localizations.localeOf(context).languageCode),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              PriceText(formatMoney(product.price), size: 13.5),
                              if (!available) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(
                                      AppRadii.sm,
                                    ),
                                  ),
                                  child: Text(
                                    context.l10n.soldOut.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.red,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Switch(
                      value: available,
                      onChanged: (_) =>
                          context.read<MenuCubit>().toggleAvailability(product),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppColors.border,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
