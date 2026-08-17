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
    // The orphan bucket has no category id, and passing null for it meant
    // "the whole menu" — so marking this group sold out took every item the
    // store sells down with it. It gets its own call.
    final ok = cubit.state.showUncategorized
        ? await cubit.setUncategorizedAvailability(available)
        : await cubit.setSectionAvailability(
            categoryId: cubit.state.selectedCategoryId,
            available: available,
          );
    if (ok && context.mounted) showSnack(context, l10n.saved);
  }

  /// Empties the orphan bucket.
  ///
  /// The one bulk action on this screen that destroys anything, so it names
  /// the count and says plainly that the items go — unlike deleting a section,
  /// which keeps them. Those two live next to each other in the UI and a
  /// vendor will read one expecting the other.
  Future<void> _deleteUncategorized(BuildContext context) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    final count = cubit.state.uncategorized.length;
    if (count == 0) return;

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: l10n.uncategorized,
      message: l10n.deleteUncategorizedConfirm(count),
      confirmText: l10n.delete,
      cancelText: l10n.cancel,
    );
    if (confirmed != true) return;
    if (await cubit.deleteUncategorized() && context.mounted) {
      showSnack(context, l10n.itemsDeleted(count));
    }
  }

  /// The non-destructive way out of the same bucket: file the whole group
  /// under an existing section instead of deleting it.
  Future<void> _moveUncategorized(BuildContext context) async {
    final cubit = context.read<MenuCubit>();
    final state = cubit.state;
    final l10n = context.l10n;
    final count = state.uncategorized.length;
    if (count == 0) return;
    if (state.categories.isEmpty) {
      showSnack(context, l10n.addASectionThenYourFirstProduct);
      return;
    }

    final chosen = await showAdaptiveSheet<_MoveTarget>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
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
              child: Text(
                l10n.moveItemsToSection(count),
                style: AppType.heading(17),
              ),
            ),
            for (final category in state.categories)
              ListTile(
                title: Text(category.displayName(_language)),
                onTap: () =>
                    Navigator.pop(sheetContext, _MoveTarget(category.id)),
              ),
          ],
        ),
      ),
    );
    final target = chosen?.id;
    if (target == null) return;
    if (await cubit.moveUncategorizedTo(target) && context.mounted) {
      showSnack(context, l10n.saved);
    }
  }

  /// Files every picked item under one section.
  ///
  /// "No section" is offered here, unlike in the whole-bucket move, because a
  /// vendor emptying a section they are about to delete has a real reason to
  /// want it.
  Future<void> _moveSelected(BuildContext context) async {
    final cubit = context.read<MenuCubit>();
    final state = cubit.state;
    final l10n = context.l10n;
    final count = state.selection.length;

    final chosen = await showAdaptiveSheet<_MoveTarget>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
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
              child: Text(
                l10n.moveItemsToSection(count),
                style: AppType.heading(17),
              ),
            ),
            for (final category in state.categories)
              ListTile(
                title: Text(category.displayName(_language)),
                onTap: () =>
                    Navigator.pop(sheetContext, _MoveTarget(category.id)),
              ),
            ListTile(
              title: Text(l10n.uncategorized),
              onTap: () => Navigator.pop(sheetContext, const _MoveTarget(null)),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    if (await cubit.moveSelectedTo(chosen.id) && context.mounted) {
      showSnack(context, l10n.saved);
    }
  }

  Future<void> _deleteSelected(BuildContext context) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    final count = cubit.state.selection.length;
    if (count == 0) return;

    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: l10n.selectedCount(count),
      message: l10n.deleteItemsConfirm(count),
      confirmText: l10n.delete,
      cancelText: l10n.cancel,
    );
    if (confirmed != true) return;
    if (await cubit.deleteSelected() && context.mounted) {
      showSnack(context, l10n.itemsDeleted(count));
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
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selection replaces the header rather than stacking under
                  // it: while items are picked, searching and adding are not
                  // what the vendor is doing, and leaving both on screen makes
                  // the count compete with the title for the same row.
                  if (state.selecting)
                    _SelectionBar(
                      state: state,
                      visible: state.visibleProducts(_language),
                      onMove: () => _moveSelected(context),
                      onDelete: () => _deleteSelected(context),
                    )
                  else
                    _Header(
                      state: state,
                      search: _search,
                      onAddItem: () => _openEditor(context),
                      onAddSection: () => _editCategory(context),
                      onManageSections: () => _manageSections(context),
                      onBulkAvailability: (available) =>
                          _setSectionAvailability(context, available),
                      onDeleteUncategorized: () =>
                          _deleteUncategorized(context),
                      onMoveUncategorized: () => _moveUncategorized(context),
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
                              onDeleteUncategorized: () =>
                                  _deleteUncategorized(context),
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

              // Back gesture and Escape leave selection mode before they leave
              // the screen — the standard contract for a mode, and the reason
              // a vendor can experiment with picking items without worrying
              // about being thrown out of the menu.
              return PopScope(
                canPop: !state.selecting,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop) context.read<MenuCubit>().clearSelection();
                },
                child: body,
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
        onAddItem: () => _openEditor(context),
      );
    }

    // Dragging only makes sense against the order being written: with a search
    // or a different sort applied, the list on screen is not the menu's order,
    // and a drop would renumber rows the vendor cannot see. Picking items is a
    // third reason not to: a long-press cannot both start a drag and start a
    // selection.
    final canReorder =
        state.sort == MenuSort.manual &&
        state.query.trim().isEmpty &&
        !state.selecting &&
        !grid;

    // Only worth printing when the list is not already filtered to one
    // section — under a section heading it would repeat that heading on every
    // single row.
    final showSection = state.selectedCategoryId == null;
    final sectionNames = {
      for (final c in state.categories) c.id: c.displayName(_language),
    };

    Widget tileFor(Product product, {Key? key}) => _ProductTile(
      key: key,
      product: product,
      language: _language,
      draggable: canReorder,
      selecting: state.selecting,
      selected: state.selection.contains(product.id),
      sectionName: showSection
          ? (sectionNames[product.categoryId] ?? context.l10n.uncategorized)
          : null,
      onEdit: () => _openEditor(context, product: product),
      onDuplicate: () => _duplicateProduct(context, product),
      onMove: () => _moveProduct(context, product),
      onDelete: () => _deleteProduct(context, product),
      onToggleSelect: () =>
          context.read<MenuCubit>().toggleSelected(product.id),
    );

    if (grid) {
      return GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 460,
          // Tall enough for the tile's own content (58px image + 12px padding
          // top and bottom) with room for a larger system text scale. A cell
          // sized exactly to the design's own line heights overflows the
          // moment a device asks for bigger text.
          mainAxisExtent: 112,
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
    required this.onDeleteUncategorized,
    required this.onMoveUncategorized,
  });

  final MenuState state;
  final TextEditingController search;
  final VoidCallback onAddItem;
  final VoidCallback onAddSection;
  final VoidCallback onManageSections;
  final ValueChanged<bool> onBulkAvailability;
  final VoidCallback onDeleteUncategorized;
  final VoidCallback onMoveUncategorized;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<MenuCubit>();
    final language = Localizations.localeOf(context).languageCode;
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
                    // title. Under a filter they describe the whole menu
                    // rather than the list on screen, so the count of what is
                    // actually showing takes over.
                    Text(
                      state.isFiltered
                          ? l10n.showingOfTotal(
                              state.visibleProducts(language).length,
                              state.products.length,
                            )
                          : l10n.menuStats(
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
                onDeleteUncategorized: onDeleteUncategorized,
                onMoveUncategorized: onMoveUncategorized,
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

/// What the header becomes while items are picked.
///
/// Everything here acts on the set: the two availability calls are the reason
/// the mode exists (an evening's sold-out list is ten taps, not ten round
/// trips), and move and delete are the same operations the single-item menu
/// offers, applied at once.
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.state,
    required this.visible,
    required this.onMove,
    required this.onDelete,
  });

  final MenuState state;

  /// The rows currently on screen — what "select all" means, since selecting
  /// items hidden behind a filter would be a promise the vendor cannot check.
  final List<Product> visible;

  final VoidCallback onMove;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<MenuCubit>();
    final count = state.selection.length;
    final allPicked =
        visible.isNotEmpty &&
        visible.every((p) => state.selection.contains(p.id));

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 10,
        12,
        10,
      ),
      decoration: const BoxDecoration(
        color: AppColors.warmFill,
        border: Border(bottom: BorderSide(color: AppColors.primaryLight)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.cancel,
                onPressed: cubit.clearSelection,
                icon: const Icon(Icons.close_rounded),
                color: AppColors.ink,
              ),
              Expanded(
                child: Text(
                  l10n.selectedCount(count),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.heading(16),
                ),
              ),
              TextButton(
                onPressed: () => cubit.toggleSelectAll(visible),
                child: Text(allPicked ? l10n.clearFilters : l10n.selectAll),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Horizontally scrollable so four labelled actions survive a 320px
          // phone in Arabic without any of them being cut in half.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _action(
                  context,
                  Icons.check_circle_outline_rounded,
                  l10n.markAllAvailable,
                  () => _availability(context, true),
                ),
                const SizedBox(width: 8),
                _action(
                  context,
                  Icons.remove_shopping_cart_outlined,
                  l10n.markAllSoldOut,
                  () => _availability(context, false),
                ),
                const SizedBox(width: 8),
                _action(
                  context,
                  Icons.drive_file_move_outline,
                  l10n.moveToSection,
                  onMove,
                ),
                const SizedBox(width: 8),
                _action(
                  context,
                  Icons.delete_outline_rounded,
                  l10n.delete,
                  onDelete,
                  danger: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _availability(BuildContext context, bool available) async {
    final cubit = context.read<MenuCubit>();
    final l10n = context.l10n;
    if (await cubit.setSelectedAvailability(available) && context.mounted) {
      showSnack(context, l10n.saved);
    }
  }

  Widget _action(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed, {
    bool danger = false,
  }) {
    final ink = danger ? AppColors.dangerInk : AppColors.ink;
    return OutlinedButton.icon(
      onPressed: state.busy ? null : onPressed,
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: AppColors.surface,
        side: BorderSide(
          color: danger ? AppColors.dangerInk : AppColors.border,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
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
    required this.onDeleteUncategorized,
    required this.onMoveUncategorized,
  });

  final MenuState state;
  final VoidCallback onAddSection;
  final VoidCallback onManageSections;
  final ValueChanged<bool> onBulkAvailability;
  final VoidCallback onDeleteUncategorized;
  final VoidCallback onMoveUncategorized;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<MenuCubit>();
    // "Section" here means whatever the list is currently showing, so the
    // wording changes when nothing is filtered. The orphan bucket counts as a
    // section for this purpose even though its id is null — it is a group of
    // items on screen, not the whole menu.
    final wholeMenu =
        state.selectedCategoryId == null && !state.showUncategorized;
    final orphans = state.uncategorized.length;
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
        // Only while the bucket has anything in it. It is not a section, so it
        // never appears in Manage sections and these are the only ways to
        // clear it other than one item at a time.
        if (orphans > 0) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: onMoveUncategorized,
            child: _menuRow(
              Icons.drive_file_move_outline,
              l10n.moveUncategorizedAction(orphans),
            ),
          ),
          PopupMenuItem(
            value: onDeleteUncategorized,
            child: _menuRow(
              Icons.delete_sweep_outlined,
              l10n.deleteUncategorizedAction(orphans),
              tone: AppColors.dangerInk,
            ),
          ),
        ],
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

  Widget _menuRow(IconData icon, String label, {Color? tone}) => Row(
    children: [
      Icon(icon, size: 18, color: tone ?? AppColors.textSecondary),
      const SizedBox(width: AppSpace.md),
      Flexible(
        child: Text(label, style: TextStyle(color: tone)),
      ),
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
    required this.onDeleteUncategorized,
  });

  final MenuState state;
  final String language;
  final ValueChanged<ProductCategory> onEdit;
  final ValueChanged<ProductCategory> onDelete;
  final VoidCallback onManage;

  /// The orphan bucket gets the same hover-delete every real section has.
  /// Without it the one group a vendor most wants to clear was the only row
  /// on the rail with no way to act on it.
  final VoidCallback onDeleteUncategorized;

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
            // No rename: there is nothing to name. Deleting here removes the
            // items themselves, which the confirm dialog spells out, because
            // the identical control one row up keeps them.
            onDelete: onDeleteUncategorized,
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
  const _EmptyResult({
    required this.state,
    required this.onClear,
    required this.onAddItem,
  });

  final MenuState state;
  final VoidCallback onClear;
  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Three situations, and the way out of each one is different. Telling all
    // three "no items" and stopping there left the commonest of them — an
    // empty section the vendor just created — with nothing to press.
    final searching = state.query.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off_rounded
                  : Icons.lunch_dining_outlined,
              size: 52,
              color: AppColors.textFaint,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              searching ? l10n.noMatchingItems : l10n.sectionHasNoItems,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.lg),
            if (searching)
              TextButton(onPressed: onClear, child: Text(l10n.clearFilters))
            else
              // An empty section wants an item in it, not its filter cleared.
              FilledButton.icon(
                onPressed: onAddItem,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(l10n.addItem),
              ),
          ],
        ),
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
    required this.selecting,
    required this.selected,
    required this.sectionName,
    required this.onEdit,
    required this.onDuplicate,
    required this.onMove,
    required this.onDelete,
    required this.onToggleSelect,
  });

  final Product product;
  final String language;

  /// Shows the grab handle. The listener itself is installed by the list, so
  /// the tile does not need to know its own index.
  final bool draggable;

  /// The screen is picking items for a bulk action. Tap picks instead of
  /// opening the editor, and the per-item controls step aside — a switch and
  /// an overflow menu on a row that is also a checkbox is three different
  /// answers to what a tap means.
  final bool selecting;
  final bool selected;

  /// Which section the item is filed under, shown only when the list is not
  /// already filtered to one. Without it "All" is a flat list of names with no
  /// way to tell a duplicate in two sections apart.
  final String? sectionName;

  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onToggleSelect;

  @override
  Widget build(BuildContext context) =>
      HoverBuilder(builder: (context, hovered) => _tile(context, hovered));

  Widget _tile(BuildContext context, bool hovered) {
    final l10n = context.l10n;
    final available = product.isAvailable;
    return Container(
      decoration: BoxDecoration(
        // A sold-out item is still a real item the vendor edits, so it keeps
        // full-strength text; the old blanket 0.72 opacity also dimmed the
        // badge that said why. A tinted ground carries the state instead.
        color: selected
            ? AppColors.warmFill
            : available
            ? AppColors.surface
            : AppColors.neutralFill,
        border: Border.all(
          color: selected
              ? AppColors.primary
              : hovered
              ? AppColors.primaryLight
              : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: AppShadows.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: selecting ? onToggleSelect : onEdit,
            // The way in to selection mode. Deliberately not a hover-only
            // checkbox: this screen is used on phones more than on desktops.
            onLongPress: selecting ? null : onToggleSelect,
            child: Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                12,
                12,
                selecting ? 12 : 4,
                12,
              ),
              child: Row(
                children: [
                  if (selecting)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 6),
                      child: Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 22,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textFaint,
                      ),
                    )
                  else if (draggable)
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
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                product.displayName(language),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                            if (!available) ...[
                              const SizedBox(width: 6),
                              const _SoldOutBadge(),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        // One line, in the order the facts are asked for: what
                        // it costs, how many choices it carries, where it
                        // lives. It ellipsises rather than wrapping, so the
                        // tile keeps one height whatever the item is called.
                        Row(
                          children: [
                            PriceText(formatMoney(product.price), size: 13.5),
                            Flexible(
                              child: Text(
                                [
                                  if (product.optionGroups.isNotEmpty)
                                    l10n.optionGroupsCount(
                                      product.optionGroups.length,
                                    ),
                                  ?sectionName,
                                ].map((part) => ' \u00b7 $part').join(),
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
                        ),
                      ],
                    ),
                  ),
                  if (!selecting) ...[
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
                        PopupMenuItem(
                          value: onToggleSelect,
                          child: _row(
                            Icons.checklist_rounded,
                            l10n.selectItems,
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
                ],
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
