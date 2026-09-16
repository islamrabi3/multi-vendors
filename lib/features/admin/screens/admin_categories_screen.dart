import 'dart:io';

import 'package:flutter/material.dart';
import 'package:multi_vendor/core/widgets/soon_badge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../admin_categories_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import '../../../core/widgets/web/adaptive_sheet.dart';

class AdminCategoriesScreen extends StatelessWidget {
  const AdminCategoriesScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminCategoriesCubit(AdminRepository()),
      child: _CategoriesView(embedded: embedded),
    );
  }
}

class _CategoriesView extends StatefulWidget {
  const _CategoriesView({required this.embedded});

  final bool embedded;

  @override
  State<_CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<_CategoriesView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final content = BlocConsumer<AdminCategoriesCubit, AdminCategoriesState>(
      listener: (context, state) {
        if (state.error != null) {
          showFailure(context, state.error!);
          return;
        }
        switch (state.event) {
          case CategoryEvent.created:
            showSnack(
              context,
              l10n.categoryCreatedMessage(state.eventCategoryName ?? ''),
            );
          case CategoryEvent.updated:
            showSnack(context, l10n.categoryUpdatedMessage);
          case CategoryEvent.deleted:
            showSnack(context, l10n.categoryDeletedMessage);
          case CategoryEvent.reordered:
            showSnack(context, l10n.categoriesReordered);
          case null:
            break;
        }
      },
      builder: (context, state) {
        final query = _query.trim().toLowerCase();
        final searching = query.isNotEmpty;
        final matches = searching
            ? state.categories
                  .where(
                    (c) =>
                        c.name.toLowerCase().contains(query) ||
                        (c.nameAr?.toLowerCase().contains(query) ?? false),
                  )
                  .toList()
            : const <VendorCategory>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
              child: Row(
                children: [
                  // The title duplicated whatever chrome already named this
                  // page — the AppBar on mobile, `WebPageChrome`'s own header
                  // on web — everywhere except `embedded`, which has no title
                  // anywhere else at all.
                  if (widget.embedded)
                    Expanded(
                      child: Text(
                        l10n.categoriesTab,
                        style: AppType.display(26),
                      ),
                    )
                  else
                    const Spacer(),
                  if (state.categories.length > 4) ...[
                    IconButton.outlined(
                      onPressed: state.categories.isEmpty
                          ? null
                          : () => _showReorder(context),
                      icon: const Icon(Icons.swap_vert_rounded),
                      tooltip: l10n.reorderCategoriesTitle,
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton.filled(
                    onPressed: () => _showEditor(context),
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
            if (state.categories.length > 6)
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: l10n.searchCategoriesHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                          )
                        : null,
                    isDense: true,
                  ),
                ),
              ),
            if (state.loading && state.categories.isEmpty)
              const Expanded(child: _CategoriesSkeleton())
            else if (state.error != null && state.categories.isEmpty)
              // Distinct from "no categories yet": a failed load previously
              // rendered identically to a store with none configured, and the
              // only sign anything went wrong was a snackbar that had already
              // disappeared by the time anyone looked.
              Expanded(
                child: FailureView(
                  error: state.error!,
                  onRetry: () => context.read<AdminCategoriesCubit>().load(),
                ),
              )
            else if (state.categories.isEmpty)
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => context.read<AdminCategoriesCubit>().load(),
                  // Scrollable even though it has one child: pull-to-refresh
                  // needs something to drag against, and a bare `EmptyView`
                  // has no scroll surface at all to catch the gesture.
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.sizeOf(context).height * 0.5,
                        child: EmptyView(
                          message: l10n.noCategoriesYet,
                          icon: Icons.grid_view_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (searching && matches.isEmpty)
              Expanded(
                child: EmptyView(
                  message: l10n.noResultsFor(_query.trim()),
                  icon: Icons.search_off_rounded,
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => context.read<AdminCategoriesCubit>().load(),
                  child: searching
                      ? ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final category = matches[index];
                            final parent = category.parentId == null
                                ? null
                                : state.categories
                                      .where((c) => c.id == category.parentId)
                                      .firstOrNull;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.lg,
                                ),
                                border: Border.all(color: AppColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: _CategoryRow(
                                category: category,
                                subtitle: parent == null
                                    ? l10n.subcategoriesCount(
                                        state.childrenOf(category.id).length,
                                      )
                                    : parent.name,
                                onEdit: () =>
                                    _showEditor(context, category: category),
                                onDelete: () =>
                                    _confirmDelete(context, category),
                                onRecommendations: () =>
                                    _showRecommendations(context, category),
                                onComingSoon: (v) => context
                                    .read<AdminCategoriesCubit>()
                                    .setComingSoon(category, v),
                              ),
                            );
                          },
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: state.topLevel.length,
                          itemBuilder: (context, index) {
                            final parent = state.topLevel[index];
                            return _CategorySection(
                              parent: parent,
                              children: state.childrenOf(parent.id),
                              onEdit: (c) => _showEditor(context, category: c),
                              onDelete: (c) => _confirmDelete(context, c),
                              onRecommendations: (c) =>
                                  _showRecommendations(context, c),
                              onComingSoon: (c, v) => context
                                  .read<AdminCategoriesCubit>()
                                  .setComingSoon(c, v),
                            );
                          },
                        ),
                ),
              ),
          ],
        );
      },
    );

    if (widget.embedded) return content;

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/categories',
        sections: adminManageWebSections(context),
        pageTitle: l10n.categoriesTab,
        child: content,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      // Default leading rather than a hand-built `arrow_back_ios`: that glyph
      // is the iOS chevron specifically and never mirrors for Arabic, where
      // `Icons.arrow_back` (which every other admin screen uses) does both
      // correctly on its own.
      appBar: AppBar(title: Text(l10n.categoriesTab)),
      body: SafeArea(top: false, bottom: false, child: content),
    );
  }

  void _showEditor(BuildContext context, {VendorCategory? category}) {
    final cubit = context.read<AdminCategoriesCubit>();
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (sheetCtx) => BlocProvider.value(
        value: cubit,
        child: _CategoryEditorSheet(category: category),
      ),
    );
  }

  /// The stores the platform pushes inside this category. Separate from the
  /// home page's single promoted rail: "our pick for Pizza" is a different
  /// answer from "our pick overall", and both are the admin's to set.
  void _showRecommendations(BuildContext context, VendorCategory category) {
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) => _CategoryRecommendationsSheet(category: category),
    );
  }

  void _confirmDelete(BuildContext context, VendorCategory category) async {
    final cubit = context.read<AdminCategoriesCubit>();
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: context.l10n.deleteCategoryTitle(category.name),
      message: context.l10n.deleteCategoryMessage,
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
      isDestructive: true,
      icon: Icons.grid_off_rounded,
    );
    if (confirmed == true) {
      cubit.deleteCategory(category.id);
    }
  }

  void _showReorder(BuildContext context) {
    final cubit = context.read<AdminCategoriesCubit>();
    showAdaptiveSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: const _ReorderCategoriesSheet(),
      ),
    );
  }
}

/// Shaped like the real list, so it doesn't jump when the categories land.
class _CategoriesSkeleton extends StatelessWidget {
  const _CategoriesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonTheme(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: 16),
        itemBuilder: (_, _) =>
            const Skeleton.box(height: 180, radius: AppRadii.lg),
      ),
    );
  }
}

/// One kind-of-shop and its cuisines as a single bordered list: the parent
/// row on top, its sub-categories indented beneath it.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.parent,
    required this.children,
    required this.onEdit,
    required this.onDelete,
    required this.onRecommendations,
    required this.onComingSoon,
  });

  final VendorCategory parent;
  final List<VendorCategory> children;
  final ValueChanged<VendorCategory> onEdit;
  final ValueChanged<VendorCategory> onDelete;
  final ValueChanged<VendorCategory> onRecommendations;
  final void Function(VendorCategory category, bool value) onComingSoon;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CategoryRow(
            category: parent,
            subtitle: context.l10n.subcategoriesCount(children.length),
            onEdit: () => onEdit(parent),
            onDelete: () => onDelete(parent),
            onRecommendations: () => onRecommendations(parent),
            onComingSoon: (v) => onComingSoon(parent, v),
          ),
          for (final child in children) ...[
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.borderSoft,
            ),
            _CategoryRow(
              category: child,
              isChild: true,
              onEdit: () => onEdit(child),
              onDelete: () => onDelete(child),
              onRecommendations: () => onRecommendations(child),
              onComingSoon: (v) => onComingSoon(child, v),
            ),
          ],
        ],
      ),
    );
  }
}

/// A category as one list row: thumbnail, both names, and its actions.
/// Tapping the row edits it.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onRecommendations,
    required this.onComingSoon,
    this.subtitle,
    this.isChild = false,
  });

  final VendorCategory category;
  final String? subtitle;
  final bool isChild;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRecommendations;
  final ValueChanged<bool> onComingSoon;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final arabic = category.nameAr?.trim() ?? '';
    final thumb = isChild ? 38.0 : 48.0;
    final secondLine = [
      arabic.isEmpty ? l10n.noArabicName : arabic,
      ?subtitle,
    ].join(' · ');

    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: EdgeInsetsDirectional.fromSTEB(isChild ? 36 : 12, 10, 4, 10),
        child: Row(
          children: [
            if (isChild)
              const Padding(
                padding: EdgeInsetsDirectional.only(end: 10),
                child: Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 18,
                  color: AppColors.textFaint,
                ),
              ),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.md),
              child: SizedBox(
                width: thumb,
                height: thumb,
                child: (category.imageUrl?.isNotEmpty ?? false)
                    ? AppNetworkImage(url: category.imageUrl!)
                    : Container(
                        color: AppColors.warmFill,
                        child: Icon(
                          Icons.grid_view_rounded,
                          size: thumb * 0.45,
                          color: AppColors.primary,
                        ),
                      ),
              ),
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
                          category.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: isChild
                              ? const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.ink,
                                )
                              : AppType.heading(15.5),
                        ),
                      ),
                      if (category.isComingSoon) ...[
                        const SizedBox(width: 6),
                        const SoonBadge(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: arabic.isEmpty
                          ? AppColors.textFaint
                          : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Tooltip(
              message: l10n.comingSoonToggle,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 30,
                    child: FittedBox(
                      child: Switch(
                        value: category.isComingSoon,
                        onChanged: onComingSoon,
                      ),
                    ),
                  ),
                  Text(
                    l10n.soonLabel,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            _action(
              icon: Icons.auto_awesome_rounded,
              color: AppColors.primary,
              tooltip: l10n.recommendedIn(category.name),
              onTap: onRecommendations,
            ),
            _action(
              icon: Icons.edit_outlined,
              color: AppColors.textMuted,
              tooltip: l10n.edit,
              onTap: onEdit,
            ),
            _action(
              icon: Icons.delete_outline_rounded,
              color: AppColors.dangerInk,
              tooltip: l10n.delete,
              onTap: onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(icon, size: 19),
      color: color,
      visualDensity: VisualDensity.compact,
    );
  }
}

/// Reorders one sibling group at a time — the top-level list, or one
/// parent's cuisines — since `sortOrder` is only ever compared within a
/// group. Mirrors the vendor side's own manage-sections sheet.
class _ReorderCategoriesSheet extends StatefulWidget {
  const _ReorderCategoriesSheet();

  @override
  State<_ReorderCategoriesSheet> createState() =>
      _ReorderCategoriesSheetState();
}

class _ReorderCategoriesSheetState extends State<_ReorderCategoriesSheet> {
  /// Null means "the top-level list"; otherwise a parent's id.
  String? _scope;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return BlocBuilder<AdminCategoriesCubit, AdminCategoriesState>(
      builder: (context, state) {
        final cubit = context.read<AdminCategoriesCubit>();
        final parentsWithChildren = state.topLevel
            .where((p) => state.childrenOf(p.id).isNotEmpty)
            .toList();
        final scope = _scope;
        final list = scope == null ? state.topLevel : state.childrenOf(scope);

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
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
                  child: Text(
                    l10n.reorderCategoriesTitle,
                    style: AppType.heading(18),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: Text(
                    l10n.reorderCategoriesHint,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ),
                if (parentsWithChildren.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: DropdownButtonFormField<String?>(
                      initialValue: _scope,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.reorderScopeLabel,
                        prefixIcon: const Icon(Icons.account_tree_outlined),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.noParentTopLevel),
                        ),
                        for (final parent in parentsWithChildren)
                          DropdownMenuItem<String?>(
                            value: parent.id,
                            child: Text(
                              parent.label(language),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _scope = value),
                    ),
                  ),
                Flexible(
                  child: ReorderableListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    itemCount: list.length,
                    onReorder: (from, to) {
                      final moved = [...list];
                      moved.insert(
                        to > from ? to - 1 : to,
                        moved.removeAt(from),
                      );
                      cubit.reorderCategories(moved);
                    },
                    itemBuilder: (context, i) {
                      final category = list[i];
                      return ListTile(
                        key: ValueKey(category.id),
                        contentPadding: const EdgeInsetsDirectional.only(
                          start: 8,
                          end: 0,
                        ),
                        leading: ReorderableDragStartListener(
                          index: i,
                          child: const Icon(
                            Icons.drag_indicator_rounded,
                            color: AppColors.textFaint,
                          ),
                        ),
                        title: Text(
                          category.label(language),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CategoryEditorSheet extends StatefulWidget {
  const _CategoryEditorSheet({this.category});

  final VendorCategory? category;

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _nameArController;
  String? _parentId;
  XFile? _selectedImage;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.category?.name);
    _nameArController = TextEditingController(text: widget.category?.nameAr);
    _parentId = widget.category?.parentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameArController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
    );
    if (file != null) {
      setState(() => _selectedImage = file);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showSnack(context, context.l10n.categoryNameRequired, error: true);
      return;
    }

    setState(() => _busy = true);
    final cubit = context.read<AdminCategoriesCubit>();

    List<int>? imageBytes;
    String? fileExtension;
    if (_selectedImage != null) {
      imageBytes = await _selectedImage!.readAsBytes();
      fileExtension = _selectedImage!.name.split('.').last;
    }

    bool success;
    if (widget.category == null) {
      success = await cubit.createCategory(
        name: name,
        nameAr: _nameArController.text,
        parentId: _parentId,
        imageBytes: imageBytes,
        fileExtension: fileExtension,
      );
    } else {
      success = await cubit.updateCategory(
        id: widget.category!.id,
        name: name,
        nameAr: _nameArController.text,
        parentId: _parentId,
        imageBytes: imageBytes,
        fileExtension: fileExtension,
        existingImageUrl: widget.category!.imageUrl,
      );
    }

    if (mounted) {
      setState(() => _busy = false);
      if (success) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.category == null;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
            isNew ? context.l10n.newCategory : context.l10n.editCategoryTitle,
            style: AppType.heading(19, color: AppColors.ink),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _busy ? null : _pickImage,
            child: Container(
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.warmFill,
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_selectedImage != null)
                    Image.file(File(_selectedImage!.path), fit: BoxFit.cover)
                  else if (widget.category?.imageUrl != null &&
                      widget.category!.imageUrl!.isNotEmpty)
                    AppNetworkImage(url: widget.category!.imageUrl!)
                  else
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_photo_alternate_rounded,
                            color: AppColors.textMuted,
                            size: 28,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            context.l10n.selectIconBanner,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_selectedImage != null ||
                      (widget.category?.imageUrl != null &&
                          widget.category!.imageUrl!.isNotEmpty))
                    Container(
                      color: Colors.black26,
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.camera_alt_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameController,
            enabled: !_busy,
            decoration: InputDecoration(
              labelText: context.l10n.categoryNameLabel,
              prefixIcon: const Icon(Icons.label_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameArController,
            enabled: !_busy,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(
              labelText: context.l10n.categoryNameArabicLabel,
              prefixIcon: const Icon(Icons.translate_rounded),
            ),
          ),
          const SizedBox(height: 12),
          // Where it sits in the tree. "None" is the kind-of-shop level the
          // home page shows; picking a parent files it as a cuisine beneath
          // one. Only top-level categories are offered, because the database
          // refuses a third level.
          Builder(
            builder: (context) {
              final state = context.watch<AdminCategoriesCubit>().state;
              final parents = state.topLevel
                  .where((c) => c.id != widget.category?.id)
                  .toList();
              // A category that already has children cannot be demoted without
              // orphaning them, so the picker is not offered for one.
              final hasChildren =
                  widget.category != null &&
                  state.childrenOf(widget.category!.id).isNotEmpty;
              if (hasChildren) {
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.l10n.topLevelCategoryWithChildren,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                );
              }
              return DropdownButtonFormField<String?>(
                initialValue: _parentId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: context.l10n.parentCategory,
                  prefixIcon: const Icon(Icons.account_tree_outlined),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(
                      context.l10n.noParentTopLevel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  for (final parent in parents)
                    DropdownMenuItem<String?>(
                      value: parent.id,
                      child: Text(
                        parent.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _parentId = value),
              );
            },
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
                  onPressed: _busy ? null : () => Navigator.pop(context),
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
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const ButtonSpinner()
                        : Text(context.l10n.save),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Picks which stores the platform pushes at the top of one category page.
///
/// Ordered by an explicit rank rather than by rating: the whole point of a
/// promoted rail is that it is a decision, and a rail that just re-sorted the
/// list underneath it would be worth nothing to the store paying for it.
class _CategoryRecommendationsSheet extends StatefulWidget {
  const _CategoryRecommendationsSheet({required this.category});

  final VendorCategory category;

  @override
  State<_CategoryRecommendationsSheet> createState() =>
      _CategoryRecommendationsSheetState();
}

class _CategoryRecommendationsSheetState
    extends State<_CategoryRecommendationsSheet> {
  final _repository = AdminRepository();

  List<({Vendor vendor, int rank})> _picks = const [];
  List<Vendor> _vendors = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final picks = await _repository.fetchCategoryRecommendations(
        widget.category.id,
      );
      final vendors = await _repository.fetchVendors();
      if (!mounted) return;
      setState(() {
        _picks = picks;
        _vendors = vendors;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailure(context, error);
    }
  }

  /// Picks any number of stores at once, with "select all".
  Future<void> _add() async {
    final promoted = _picks.map((p) => p.vendor.id).toSet();
    // Stores filed directly under this category first: they are the likely
    // picks, and the rest stay reachable below them.
    final available = _vendors.where((v) => !promoted.contains(v.id)).toList()
      ..sort((a, b) {
        final aHere = a.categoryId == widget.category.id ? 0 : 1;
        final bHere = b.categoryId == widget.category.id ? 0 : 1;
        if (aHere != bHere) return aHere - bHere;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    if (available.isEmpty) return;

    final chosen = await showAdaptiveSheet<List<Vendor>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.canvas,
      maxWidth: 520,
      builder: (_) => _StoreMultiPicker(vendors: available),
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      var rank = _picks.length;
      for (final vendor in chosen) {
        await _repository.addCategoryRecommendation(
          categoryId: widget.category.id,
          vendorId: vendor.id,
          // Appended, so adding never silently reshuffles the existing order.
          rank: rank++,
        );
      }
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Vendor vendor) async {
    // Removing costs the store a placement it may be paying for — one tap
    // with no way back was too cheap a way to lose it by accident.
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: vendor.name,
      message: context.l10n.removeRecommendationConfirm,
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
      isDestructive: true,
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await _repository.removeCategoryRecommendation(
        categoryId: widget.category.id,
        vendorId: vendor.id,
      );
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Text(
              l10n.recommendedIn(widget.category.name),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppType.heading(18),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: LoadingView(),
              )
            else if (_picks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: EmptyView(
                  message: l10n.noRecommendationsYet,
                  icon: Icons.auto_awesome_outlined,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final pick in _picks)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: AppColors.warmFill,
                          child: Text(
                            '${pick.rank + 1}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        title: Text(
                          pick.vendor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          onPressed: _busy ? null : () => _remove(pick.vendor),
                          icon: const Icon(
                            Icons.remove_circle_outline_rounded,
                            color: AppColors.dangerInk,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy || _loading ? null : _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                l10n.addStore,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Checkbox list of stores with "select all", returning the chosen ones.
class _StoreMultiPicker extends StatefulWidget {
  const _StoreMultiPicker({required this.vendors});

  final List<Vendor> vendors;

  @override
  State<_StoreMultiPicker> createState() => _StoreMultiPickerState();
}

class _StoreMultiPickerState extends State<_StoreMultiPicker> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = _selected.length == widget.vendors.length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          children: [
            CheckboxListTile(
              value: all
                  ? true
                  : _selected.isEmpty
                  ? false
                  : null,
              tristate: true,
              onChanged: (_) => setState(() {
                if (all) {
                  _selected.clear();
                } else {
                  _selected.addAll(widget.vendors.map((v) => v.id));
                }
              }),
              title: Text(
                l10n.selectAll,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const Divider(height: 1, color: AppColors.borderSoft),
            Expanded(
              child: ListView.builder(
                itemCount: widget.vendors.length,
                itemBuilder: (context, i) {
                  final vendor = widget.vendors[i];
                  return CheckboxListTile(
                    value: _selected.contains(vendor.id),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(vendor.id);
                      } else {
                        _selected.remove(vendor.id);
                      }
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: AppNetworkImage(
                      url: vendor.logoUrl,
                      width: 40,
                      height: 40,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    title: Text(
                      vendor.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _selected.isEmpty
                    ? null
                    : () => Navigator.pop(context, [
                        for (final v in widget.vendors)
                          if (_selected.contains(v.id)) v,
                      ]),
                child: Text('${l10n.add} (${_selected.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
