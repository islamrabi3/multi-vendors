import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/vendor.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
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
        // A bare list of name + status cards stretches into wasted
        // whitespace at web width, so wide screens get a dense table instead
        // — the list content and the tap target are otherwise identical.
        if (webWide) {
          return SingleChildScrollView(
            child: WebTable(
              columns: [
                WebTableColumn(label: l10n.store, flex: 3),
                WebTableColumn(label: l10n.statusLabel, flex: 1),
              ],
              rows: [
                for (final vendor in vendors)
                  WebTableRow.aligned(
                    onTap: () => _openImport(vendor),
                    columns: [
                      WebTableColumn(label: '', flex: 3),
                      WebTableColumn(label: '', flex: 1),
                    ],
                    cells: [
                      Row(
                        children: [
                          AppNetworkImage(
                            url: vendor.logoUrl,
                            width: 32,
                            height: 32,
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                          ),
                          const SizedBox(width: AppSpace.sm),
                          Expanded(
                            child: Text(
                              vendor.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        vendor.approvalStatus,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
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
                subtitle: Text(vendor.approvalStatus),
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

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            searchField,
            const SizedBox(height: AppSpace.lg),
            Expanded(child: list),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/menu-import',
        sections: adminManageWebSections(context),
        pageTitle: l10n.importMenuFromPhotos,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              searchField,
              const SizedBox(height: AppSpace.lg),
              Expanded(child: list),
            ],
          ),
        ),
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
}
