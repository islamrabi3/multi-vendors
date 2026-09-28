import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/console.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../vendor/screens/menu_import_screen.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Admin-side AI menu import: pick a store, then run the extraction for it.
///
/// Extraction costs money per call and produces a whole catalogue in one shot,
/// so it is an operator tool rather than something every vendor can trigger.
/// The import RPC accepts an admin as well as the store's owner, and the
/// review step is identical for both.
class AdminMenuImportScreen extends StatefulWidget {
  const AdminMenuImportScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  State<AdminMenuImportScreen> createState() => _AdminMenuImportScreenState();
}

class _AdminMenuImportScreenState extends State<AdminMenuImportScreen> {
  final _repo = AdminRepository();
  late Future<List<Vendor>> _future;
  String _search = '';

  /// Desktop: the store whose menu is being built in the right-hand pane.
  Vendor? _selected;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchVendors();
  }

  void _reload() => setState(() {
    _future = _repo.fetchVendors();
  });

  Future<void> _openImport(Vendor vendor) async {
    final imported = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => MenuImportScreen(vendorId: vendor.id)),
    );
    if (imported == true && mounted) {
      showSnack(context, context.l10n.menuImported);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);

    final searchField = TextField(
      onChanged: (value) => setState(() => _search = value.trim()),
      decoration: InputDecoration(
        hintText: l10n.selectVendor,
        prefixIcon: const Icon(Icons.search),
      ),
    );

    final list = FutureBuilder<List<Vendor>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingView();
        }
        if (snap.hasError) {
          return FailureView(error: snap.error!, onRetry: _reload);
        }
        final vendors = (snap.data ?? const <Vendor>[])
            .where(
              (v) =>
                  _search.isEmpty ||
                  v.name.toLowerCase().contains(_search.toLowerCase()),
            )
            .toList();
        if (vendors.isEmpty) {
          return EmptyView(
            message: l10n.noVendorsHere,
            icon: Icons.storefront_outlined,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            AppSpace.xs,
            AppSpace.gutter,
            AppSpace.xxl,
          ),
          itemCount: vendors.length,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpace.sm),
          itemBuilder: (context, i) {
            final vendor = vendors[i];
            return Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: () => _openImport(vendor),
                leading: AppNetworkImage(
                  url: vendor.logoUrl,
                  width: 44,
                  height: 44,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                title: Text(
                  vendor.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(_statusLabel(context, vendor.approvalStatus)),
                trailing: const Icon(
                  Icons.document_scanner_outlined,
                  color: AppColors.primary,
                ),
              ),
            );
          },
        );
      },
    );

    if (webWide) {
      final page = _webPage();
      if (widget.embedded) return page;
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/menu-import',
        sections: adminManageWebSections(context),
        pageTitle: l10n.importMenuFromPhotos,
        child: page,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.importMenuFromPhotos)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md,
              AppSpace.gutter,
              AppSpace.sm,
            ),
            child: searchField,
          ),
          Expanded(child: list),
        ],
      ),
    );
  }

  /// Desktop: stores down the side, the chosen store's import beside them —
  /// the operator never leaves the console, and can move to the next store
  /// as soon as one is done.
  Widget _webPage() {
    final l10n = context.l10n;
    final selected = _selected;
    final picker = Container(
      width: 340,
      decoration: const BoxDecoration(
        border: BorderDirectional(end: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
            child: ConsoleSearchField(
              hint: l10n.searchByName,
              onChanged: (value) => setState(() => _search = value.trim()),
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: FutureBuilder<List<Vendor>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const LoadingView();
                }
                if (snap.hasError) {
                  return FailureView(error: snap.error!, onRetry: _reload);
                }
                final query = _search.toLowerCase();
                final vendors = [
                  for (final v in snap.data ?? const <Vendor>[])
                    if (query.isEmpty || v.name.toLowerCase().contains(query))
                      v,
                ];
                if (vendors.isEmpty) {
                  return ConsoleEmpty(
                    icon: Icons.storefront_outlined,
                    title: l10n.noVendorsHere,
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: vendors.length,
                  itemBuilder: (context, i) {
                    final vendor = vendors[i];
                    final isSelected = vendor.id == selected?.id;
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 1,
                      ),
                      child: Material(
                        color: isSelected
                            ? AppColors.warmFill
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          onTap: () => setState(() => _selected = vendor),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                AppNetworkImage(
                                  url: vendor.logoUrl,
                                  width: 32,
                                  height: 32,
                                  borderRadius: BorderRadius.circular(
                                    AppRadii.sm,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        vendor.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected
                                              ? AppColors.primary
                                              : AppColors.ink,
                                        ),
                                      ),
                                      Text(
                                        _statusLabel(
                                          context,
                                          vendor.approvalStatus,
                                        ),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            picker,
            Expanded(
              child: selected == null
                  ? Center(
                      child: ConsoleEmpty(
                        icon: Icons.menu_book_outlined,
                        title: l10n.chooseStoreTitle,
                        message: l10n.chooseStoreBody,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
                          child: Row(
                            children: [
                              AppNetworkImage(
                                url: selected.logoUrl,
                                width: 36,
                                height: 36,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.sm,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  selected.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.heading(18),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: MenuImportScreen(
                            // A new store starts a fresh import rather than
                            // inheriting the last one's photos.
                            key: ValueKey(selected.id),
                            vendorId: selected.id,
                            embedded: true,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A store's approval state in the reader's language.
String _statusLabel(BuildContext context, String status) => switch (status) {
  'active' => context.l10n.statusActive,
  'pending' => context.l10n.statusPending,
  'suspended' => context.l10n.statusSuspended,
  _ => status,
};
