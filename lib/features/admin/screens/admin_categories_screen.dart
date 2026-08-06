import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../admin_categories_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class AdminCategoriesScreen extends StatelessWidget {
  const AdminCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => AdminCategoriesCubit(AdminRepository()),
      child: const _CategoriesView(),
    );
  }
}

class _CategoriesView extends StatefulWidget {
  const _CategoriesView();

  @override
  State<_CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<_CategoriesView> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(context.l10n.categoriesTab),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: BlocConsumer<AdminCategoriesCubit, AdminCategoriesState>(
          listener: (context, state) {
            if (state.error != null) {
              showFailure(context, state.error!);
            } else if (state.successMessage != null) {
              showSnack(context, state.successMessage!);
            }
          },
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 10),
                  child: Row(
                    children: [
                      Text(
                        context.l10n.categoriesTab,
                        style: AppType.display(26),
                      ),
                      const Spacer(),
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
                if (state.loading && state.categories.isEmpty)
                  const Expanded(child: LoadingView())
                else if (state.categories.isEmpty)
                  Expanded(
                    child: EmptyView(
                      message: context.l10n.noCategoriesYet,
                      icon: Icons.grid_view_rounded,
                    ),
                  )
                else
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: () =>
                          context.read<AdminCategoriesCubit>().load(),
                      child: GridView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                        physics: const AlwaysScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                              childAspectRatio: 0.85,
                            ),
                        itemCount: state.categories.length,
                        itemBuilder: (context, index) {
                          final category = state.categories[index];
                          return _CategoryCard(
                            category: category,
                            onEdit: () =>
                                _showEditor(context, category: category),
                            onDelete: () => _confirmDelete(context, category),
                            onRecommendations: () =>
                                _showRecommendations(context, category),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, {VendorCategory? category}) {
    final cubit = context.read<AdminCategoriesCubit>();
    showModalBottomSheet(
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
    showModalBottomSheet(
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
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({
    required this.category,
    required this.onEdit,
    required this.onDelete,
    required this.onRecommendations,
  });

  final VendorCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRecommendations;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (category.imageUrl != null && category.imageUrl!.isNotEmpty)
                  AppNetworkImage(url: category.imageUrl!)
                else
                  Container(
                    color: AppColors.warmFill,
                    child: const Icon(
                      Icons.grid_view_rounded,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Row(
                    children: [
                      _actionButton(
                        icon: Icons.auto_awesome_rounded,
                        color: AppColors.primary,
                        onTap: onRecommendations,
                      ),
                      const SizedBox(width: 6),
                      _actionButton(
                        icon: Icons.edit_rounded,
                        color: AppColors.ink,
                        onTap: onEdit,
                      ),
                      const SizedBox(width: 6),
                      _actionButton(
                        icon: Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        onTap: onDelete,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  category.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.isTopLevel
                      ? context.l10n.noParentTopLevel
                      : context.l10n.subCategory,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        child: Icon(icon, size: 16, color: color),
      ),
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
            isNew ? 'New Category' : 'Edit Category',
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
                        ? const CircularProgressIndicator(color: Colors.white)
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

  Future<void> _add() async {
    final promoted = _picks.map((p) => p.vendor.id).toSet();
    final available = _vendors
        .where((v) => !promoted.contains(v.id))
        .toList();
    if (available.isEmpty) return;

    final chosen = await showModalBottomSheet<Vendor>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xxl)),
      ),
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final vendor in available)
              ListTile(
                title: Text(
                  vendor.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(context, vendor),
              ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;

    setState(() => _busy = true);
    try {
      await _repository.addCategoryRecommendation(
        categoryId: widget.category.id,
        vendorId: chosen.id,
        // Appended, so adding never silently reshuffles the existing order.
        rank: _picks.length,
      );
      await _load();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Vendor vendor) async {
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
                            color: Colors.redAccent,
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
