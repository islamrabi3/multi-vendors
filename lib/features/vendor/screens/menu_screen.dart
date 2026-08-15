import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

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
import '../../../core/widgets/web/adaptive_sheet.dart';

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
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _language => Localizations.localeOf(context).languageCode;

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  /// Create or rename a section. Deleting is offered here too, since the only
  /// place a vendor thinks about a section is while looking at its name.
  Future<void> _editCategory(
    BuildContext context, {
    ProductCategory? category,
  }) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    final controller = TextEditingController(text: category?.name);
    final controllerAr = TextEditingController(text: category?.nameAr);
    final isNew = category == null;

    String? nameArVal;

    final String? result = await AppDialogs.showFormDialog<String>(
      context: context,
      title: isNew ? l10n.newSection : l10n.renameSection,
      subtitle: isNew
          ? l10n.addCategorySectionDesc
          : l10n.modifyCategoryNameDesc,
      icon: isNew ? Icons.create_new_folder_rounded : Icons.edit_note_rounded,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: '${l10n.sectionName} · ${l10n.english}',
              hintText: l10n.sectionHint,
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
              labelText: '${l10n.sectionName} · ${l10n.arabic}',
              prefixIcon: const Icon(Icons.translate_rounded),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
            ),
          ),
        ],
      ),
      primaryText: l10n.save,
      onPrimaryPressed: (dialogContext) {
        nameArVal = controllerAr.text.trim();
        Navigator.pop(dialogContext, controller.text.trim());
      },
      secondaryText: l10n.cancel,
    );

    if (result != null && result.isNotEmpty) {
      await cubit.saveCategory(result, nameAr: nameArVal, id: category?.id);
    }
    Future.delayed(const Duration(milliseconds: 500), () {
      controller.dispose();
      controllerAr.dispose();
    });
  }

  /// Deleting a section is destructive enough to confirm, and the outcome —
  /// the items survive — is not obvious, so the dialog says it.
  Future<void> _deleteCategory(
    BuildContext context,
    ProductCategory category,
  ) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: category.displayName(_language),
      message: l10n.deleteSectionConfirm,
      confirmText: l10n.delete,
      cancelText: l10n.cancel,
    );
    if (confirmed != true) return;
    if (await cubit.deleteCategory(category.id) && context.mounted) {
      showSnack(context, l10n.sectionDeleted);
    }
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

  Future<void> _deleteProduct(BuildContext context, Product product) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: product.displayName(_language),
      message: l10n.deleteItemConfirm,
      confirmText: l10n.delete,
      cancelText: l10n.cancel,
    );
    if (confirmed != true) return;
    if (await cubit.deleteProduct(product.id) && context.mounted) {
      showSnack(context, l10n.itemDeleted);
    }
  }

  Future<void> _duplicateProduct(BuildContext context, Product product) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    if (await cubit.duplicateProduct(product.id) && context.mounted) {
      showSnack(context, l10n.itemDuplicated);
    }
  }

  /// Moving an item between sections is the one edit common enough to deserve
  /// its own sheet rather than a trip through the full editor.
  Future<void> _moveProduct(BuildContext context, Product product) async {
    final cubit = context.read<MenuCubit>();
    final state = cubit.state;
    final l10n = context.l10n;
    final chosen = await showAdaptiveSheet<_MoveTarget>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget row(String label, String? id) => ListTile(
          title: Text(label),
          trailing: id == product.categoryId
              ? const Icon(Icons.check_rounded, color: AppColors.primary)
              : null,
          onTap: () => Navigator.pop(sheetContext, _MoveTarget(id)),
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpace.xl,
                  0,
                  AppSpace.xl,
                  AppSpace.md,
                ),
                child: Text(l10n.moveToSection, style: AppType.heading(17)),
              ),
              for (final category in state.categories)
                row(category.displayName(_language), category.id),
              row(l10n.uncategorized, null),
            ],
          ),
        );
      },
    );
    if (chosen == null || chosen.id == product.categoryId) return;
    await cubit.moveProduct(product.id, chosen.id);
  }

  /// Drag-to-reorder for sections, plus rename and delete in the same place.
  Future<void> _manageSections(BuildContext context) async {
    final cubit = context.read<MenuCubit>();
    await showAdaptiveSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: _ManageSectionsSheet(
          onRename: (category) => _editCategory(context, category: category),
          onDelete: (category) => _deleteCategory(context, category),
          onAdd: () => _editCategory(context),
        ),
      ),
    );
  }

  Future<void> _setSectionAvailability(
    BuildContext context,
    bool available,
  ) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    final categoryId = cubit.state.showUncategorized
        ? null
        : cubit.state.selectedCategoryId;
    if (await cubit.setSectionAvailability(
          categoryId: categoryId,
          available: available,
        ) &&
        context.mounted) {
      showSnack(context, l10n.saved);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final split = AppBreakpoints.isSplit(constraints.maxWidth);
          return BlocConsumer<MenuCubit, MenuState>(
            // A failed save now says what went wrong instead of throwing into
            // nothing. The full-screen error view is reserved for a menu that
            // could not load at all.
            listenWhen: (p, c) => p.error != c.error && c.error != null,
            listener: (context, state) => showFailure(
              context,
              state.error!,
              onRetry: context.read<MenuCubit>().load,
            ),
            builder: (context, state) {
              final failedToLoad =
                  state.error != null &&
                  state.categories.isEmpty &&
                  state.products.isEmpty;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    state: state,
                    search: _search,
                    onAddItem: () => _openEditor(context),
                    onAddSection: () => _editCategory(context),
                    onManageSections: () => _manageSections(context),
                    onBulkAvailability: (available) =>
                        _setSectionAvailability(context, available),
                  ),
                  if (state.loading)
                    const Expanded(child: LoadingView())
                  else if (failedToLoad)
                    Expanded(
                      child: FailureView(
                        error: state.error!,
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
                            width: 268,
                            child: _SectionRail(
                              state: state,
                              language: _language,
                              onEdit: (c) =>
                                  _editCategory(context, category: c),
                              onDelete: (c) => _deleteCategory(context, c),
                              onManage: () => _manageSections(context),
                            ),
                          ),
                          const VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: AppColors.border,
                          ),
                          Expanded(child: _body(context, state, grid: true)),
                        ],
                      ),
                    )
                  else ...[
                    _SectionChips(state: state, language: _language),
                    Expanded(child: _body(context, state, grid: false)),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _body(BuildContext context, MenuState state, {required bool grid}) {
    final items = state.visibleProducts(_language);
    if (items.isEmpty) {
      return _EmptyResult(
        state: state,
        onClear: context.read<MenuCubit>().clearFilters,
      );
    }

    // Dragging only makes sense against the order being written: with a search
    // or a different sort applied, the list on screen is not the menu's order,
    // and a drop would renumber rows the vendor cannot see.
    final canReorder =
        state.sort == MenuSort.manual && state.query.trim().isEmpty && !grid;

    Widget tileFor(Product product, {Key? key}) => _ProductTile(
      key: key,
      product: product,
      language: _language,
      draggable: canReorder,
      onEdit: () => _openEditor(context, product: product),
      onDuplicate: () => _duplicateProduct(context, product),
      onMove: () => _moveProduct(context, product),
      onDelete: () => _deleteProduct(context, product),
    );

    if (grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 460,
          mainAxisExtent: 104,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: items.length,
        itemBuilder: (context, i) => tileFor(items[i]),
      );
    }

    if (!canReorder) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) => tileFor(items[i]),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
      itemCount: items.length,
      buildDefaultDragHandles: false,
      proxyDecorator: (child, _, _) => Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: child,
      ),
      onReorder: (from, to) {
        final moved = [...items];
        moved.insert(to > from ? to - 1 : to, moved.removeAt(from));
        context.read<MenuCubit>().reorderProducts(moved);
      },
      itemBuilder: (context, i) => Padding(
        key: ValueKey(items[i].id),
        padding: const EdgeInsets.only(bottom: 12),
        child: ReorderableDelayedDragStartListener(
          index: i,
          child: tileFor(items[i]),
        ),
      ),
    );
  }
}

/// Identity for the move sheet's radio group.
///
/// A plain `String?` cannot be a [RadioListTile] value and also mean
/// "no section": null is what the group compares against when nothing is
/// selected, so the uncategorised row could never appear chosen.
class _MoveTarget {
  const _MoveTarget(this.id);
  final String? id;

  @override
  bool operator ==(Object other) => other is _MoveTarget && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

// -----------------------------------------------------------------------------
// Header
// -----------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({
    required this.state,
    required this.search,
    required this.onAddItem,
    required this.onAddSection,
    required this.onManageSections,
    required this.onBulkAvailability,
  });

  final MenuState state;
  final TextEditingController search;
  final VoidCallback onAddItem;
  final VoidCallback onAddSection;
  final VoidCallback onManageSections;
  final ValueChanged<bool> onBulkAvailability;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<MenuCubit>();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 12,
        16,
        8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.menu, style: AppType.display(26)),
                    const SizedBox(height: 2),
                    // The three numbers a vendor actually checks on opening
                    // this screen, rather than a subtitle that repeats the
                    // title.
                    Text(
                      l10n.menuStats(
                        state.products.length,
                        state.categories.length,
                        state.soldOutCount,
                      ),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _MenuActions(
                state: state,
                onAddSection: onAddSection,
                onManageSections: onManageSections,
                onBulkAvailability: onBulkAvailability,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: onAddItem,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  l10n.addItem,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: search,
            onChanged: cubit.search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.searchMenuHint,
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: state.query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        search.clear();
                        cubit.search('');
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadii.pill),
                borderSide: const BorderSide(color: AppColors.border),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The overflow menu: everything that is not "add an item".
class _MenuActions extends StatelessWidget {
  const _MenuActions({
    required this.state,
    required this.onAddSection,
    required this.onManageSections,
    required this.onBulkAvailability,
  });

  final MenuState state;
  final VoidCallback onAddSection;
  final VoidCallback onManageSections;
  final ValueChanged<bool> onBulkAvailability;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<MenuCubit>();
    // "Section" here means whatever the list is currently showing, so the
    // wording changes when nothing is filtered.
    final wholeMenu = state.selectedCategoryId == null;
    return PopupMenuButton<VoidCallback>(
      tooltip: l10n.manage,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (action) => action(),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: onAddSection,
          child: _menuRow(Icons.create_new_folder_outlined, l10n.addSection),
        ),
        PopupMenuItem(
          value: onManageSections,
          child: _menuRow(Icons.reorder_rounded, l10n.manageSections),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: () => onBulkAvailability(false),
          child: _menuRow(
            Icons.remove_shopping_cart_outlined,
            wholeMenu ? l10n.markAllSoldOut : l10n.markSectionSoldOut,
          ),
        ),
        PopupMenuItem(
          value: () => onBulkAvailability(true),
          child: _menuRow(
            Icons.check_circle_outline_rounded,
            wholeMenu ? l10n.markAllAvailable : l10n.markSectionAvailable,
          ),
        ),
        const PopupMenuDivider(),
        for (final sort in MenuSort.values)
          PopupMenuItem(
            value: () => cubit.setSort(sort),
            child: _menuRow(
              state.sort == sort
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              _sortLabel(context, sort),
            ),
          ),
      ],
    );
  }

  Widget _menuRow(IconData icon, String label) => Row(
    children: [
      Icon(icon, size: 18, color: AppColors.textSecondary),
      const SizedBox(width: AppSpace.md),
      Flexible(child: Text(label)),
    ],
  );
}

String _sortLabel(BuildContext context, MenuSort sort) => switch (sort) {
  MenuSort.manual => context.l10n.sortManual,
  MenuSort.nameAsc => context.l10n.sortNameAsc,
  MenuSort.priceAsc => context.l10n.sortPriceAsc,
  MenuSort.priceDesc => context.l10n.sortPriceDesc,
};

// -----------------------------------------------------------------------------
// Section navigation
// -----------------------------------------------------------------------------

class _SectionChips extends StatelessWidget {
  const _SectionChips({required this.state, required this.language});

  final MenuState state;
  final String language;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MenuCubit>();
    final orphans = state.uncategorized.length;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Row(
        children: [
          _chip(
            context,
            label: context.l10n.all,
            count: state.products.length,
            selected:
                state.selectedCategoryId == null && !state.showUncategorized,
            onTap: () => cubit.selectCategory(null),
          ),
          for (final c in state.categories)
            _chip(
              context,
              // The chips used to show the canonical name while the desktop
              // rail showed the translated one, so the same section read
              // differently depending on the window width.
              label: c.displayName(language),
              count: state.productsIn(c.id).length,
              selected: state.selectedCategoryId == c.id,
              onTap: () => cubit.selectCategory(c.id),
            ),
          // Only exists once a deleted section has left items behind.
          if (orphans > 0)
            _chip(
              context,
              label: context.l10n.uncategorized,
              count: orphans,
              selected: state.showUncategorized,
              onTap: cubit.selectUncategorized,
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: GestureDetector(
        onTap: onTap,
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
          child: Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: AppType.mono(
                  11.5,
                  color: selected
                      ? Colors.white.withValues(alpha: 0.8)
                      : AppColors.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Desktop menu navigation: one row per section with its item count, and the
/// edit affordances a mouse can reach (long-press is not discoverable).
class _SectionRail extends StatelessWidget {
  const _SectionRail({
    required this.state,
    required this.language,
    required this.onEdit,
    required this.onDelete,
    required this.onManage,
  });

  final MenuState state;
  final String language;
  final ValueChanged<ProductCategory> onEdit;
  final ValueChanged<ProductCategory> onDelete;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<MenuCubit>();
    final orphans = state.uncategorized.length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 24),
      children: [
        _row(
          context,
          label: context.l10n.all,
          count: state.products.length,
          selected:
              state.selectedCategoryId == null && !state.showUncategorized,
          onTap: () => cubit.selectCategory(null),
        ),
        for (final c in state.categories)
          _row(
            context,
            label: c.displayName(language),
            count: state.productsIn(c.id).length,
            selected: state.selectedCategoryId == c.id,
            onTap: () => cubit.selectCategory(c.id),
            onEdit: () => onEdit(c),
            onDelete: () => onDelete(c),
          ),
        if (orphans > 0)
          _row(
            context,
            label: context.l10n.uncategorized,
            count: orphans,
            selected: state.showUncategorized,
            onTap: cubit.selectUncategorized,
          ),
        const SizedBox(height: AppSpace.md),
        TextButton.icon(
          onPressed: onManage,
          icon: const Icon(Icons.reorder_rounded, size: 17),
          label: Text(context.l10n.manageSections),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context, {
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: HoverBuilder(
        builder: (context, hovered) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 11, 6, 11),
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
                if (onEdit != null && hovered) ...[
                  _railAction(
                    Icons.edit_outlined,
                    onEdit,
                    selected,
                    context.l10n.renameSection,
                  ),
                  if (onDelete != null)
                    _railAction(
                      Icons.delete_outline_rounded,
                      onDelete,
                      selected,
                      context.l10n.delete,
                    ),
                ] else
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Text(
                      '$count',
                      style: AppType.mono(
                        12,
                        color: selected ? Colors.white : AppColors.textFaint,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _railAction(
    IconData icon,
    VoidCallback onTap,
    bool selected,
    String tooltip,
  ) => IconButton(
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
    tooltip: tooltip,
    icon: Icon(
      icon,
      size: 15,
      color: selected ? Colors.white : AppColors.textMuted,
    ),
  );
}

/// Reorder, rename, delete and add sections in one place.
class _ManageSectionsSheet extends StatelessWidget {
  const _ManageSectionsSheet({
    required this.onRename,
    required this.onDelete,
    required this.onAdd,
  });

  final ValueChanged<ProductCategory> onRename;
  final ValueChanged<ProductCategory> onDelete;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return BlocBuilder<MenuCubit, MenuState>(
      builder: (context, state) {
        final cubit = context.read<MenuCubit>();
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.8,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl,
                    0,
                    AppSpace.xl,
                    AppSpace.xs,
                  ),
                  child: Text(l10n.manageSections, style: AppType.heading(18)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.xl,
                    0,
                    AppSpace.xl,
                    AppSpace.md,
                  ),
                  child: Text(
                    l10n.reorderSections,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.lg,
                      vertical: 4,
                    ),
                    itemCount: state.categories.length,
                    onReorder: (from, to) {
                      final moved = [...state.categories];
                      moved.insert(
                        to > from ? to - 1 : to,
                        moved.removeAt(from),
                      );
                      cubit.reorderCategories(moved);
                    },
                    itemBuilder: (context, i) {
                      final category = state.categories[i];
                      return ListTile(
                        key: ValueKey(category.id),
                        contentPadding: const EdgeInsetsDirectional.only(
                          start: AppSpace.sm,
                          end: 0,
                        ),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(
                            Icons.drag_indicator_rounded,
                            color: AppColors.textFaint,
                          ),
                        ),
                        title: Text(category.displayName(language)),
                        subtitle: Text(
                          '${state.productsIn(category.id).length}',
                          style: AppType.mono(11.5, color: AppColors.textFaint),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: l10n.renameSection,
                              icon: const Icon(Icons.edit_outlined, size: 19),
                              onPressed: () => onRename(category),
                            ),
                            IconButton(
                              tooltip: l10n.delete,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 19,
                                color: AppColors.dangerInk,
                              ),
                              onPressed: () => onDelete(category),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onAdd,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(l10n.addSection),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Items
// -----------------------------------------------------------------------------

/// What the list shows when a filter or a search matches nothing — which is a
/// different situation from a store with no menu at all.
class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.state, required this.onClear});

  final MenuState state;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!state.isFiltered) {
      return EmptyView(
        message: l10n.sectionHasNoItems,
        icon: Icons.lunch_dining_outlined,
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off_rounded,
            size: 52,
            color: AppColors.textFaint,
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            state.query.trim().isEmpty
                ? l10n.sectionHasNoItems
                : l10n.noMatchingItems,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.md),
          TextButton(onPressed: onClear, child: Text(l10n.clearFilters)),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.language,
    required this.draggable,
    required this.onEdit,
    required this.onDuplicate,
    required this.onMove,
    required this.onDelete,
  });

  final Product product;
  final String language;

  /// Shows the grab handle. The listener itself is installed by the list, so
  /// the tile does not need to know its own index.
  final bool draggable;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) =>
      HoverBuilder(builder: (context, hovered) => _tile(context, hovered));

  Widget _tile(BuildContext context, bool hovered) {
    final l10n = context.l10n;
    final available = product.isAvailable;
    return Opacity(
      opacity: available ? 1 : 0.72,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(
            color: hovered ? AppColors.primaryLight : AppColors.border,
          ),
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
                padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 4, 12),
                child: Row(
                  children: [
                    if (draggable)
                      const Padding(
                        padding: EdgeInsetsDirectional.only(end: 4),
                        child: Icon(
                          Icons.drag_indicator_rounded,
                          size: 18,
                          color: AppColors.textFaint,
                        ),
                      ),
                    AppNetworkImage(
                      url: product.imageUrl,
                      height: 58,
                      width: 58,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.displayName(language),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              PriceText(formatMoney(product.price), size: 13.5),
                              if (product.optionGroups.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    l10n.optionGroupsCount(
                                      product.optionGroups.length,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textFaint,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                              if (!available) ...[
                                const SizedBox(width: 8),
                                const _SoldOutBadge(),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: available,
                      onChanged: (_) =>
                          context.read<MenuCubit>().toggleAvailability(product),
                      activeThumbColor: Colors.white,
                      activeTrackColor: AppColors.success,
                      inactiveThumbColor: Colors.white,
                      inactiveTrackColor: AppColors.border,
                    ),
                    PopupMenuButton<VoidCallback>(
                      tooltip: l10n.manage,
                      icon: const Icon(Icons.more_vert_rounded, size: 20),
                      onSelected: (action) => action(),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: onEdit,
                          child: _row(Icons.edit_outlined, l10n.edit),
                        ),
                        PopupMenuItem(
                          value: onDuplicate,
                          child: _row(
                            Icons.copy_all_outlined,
                            l10n.duplicateItem,
                          ),
                        ),
                        PopupMenuItem(
                          value: onMove,
                          child: _row(
                            Icons.drive_file_move_outline,
                            l10n.moveToSection,
                          ),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(
                          value: onDelete,
                          child: _row(
                            Icons.delete_outline_rounded,
                            l10n.deleteItem,
                            danger: true,
                          ),
                        ),
                      ],
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

  Widget _row(IconData icon, String label, {bool danger = false}) => Row(
    children: [
      Icon(
        icon,
        size: 18,
        color: danger ? AppColors.dangerInk : AppColors.textSecondary,
      ),
      const SizedBox(width: AppSpace.md),
      Text(
        label,
        style: TextStyle(color: danger ? AppColors.dangerInk : AppColors.ink),
      ),
    ],
  );
}

class _SoldOutBadge extends StatelessWidget {
  const _SoldOutBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.dangerFill,
      borderRadius: BorderRadius.circular(AppRadii.sm),
    ),
    child: Text(
      context.l10n.soldOut.toUpperCase(),
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w800,
        color: AppColors.dangerInk,
      ),
    ),
  );
}
