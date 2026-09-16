import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/ui_kit.dart';
import '../../../core/widgets/web/adaptive_sheet.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import '../../auth/auth_cubit.dart';
import 'admin_create_account_screen.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;

enum DriverFilter { all, pending, active, suspended }

/// The reviewer-facing name of a document column.
String documentLabel(BuildContext context, String column) => switch (column) {
  'id_card_url' => context.l10n.idFront,
  'id_card_back_url' => context.l10n.idBack,
  'license_url' => context.l10n.licenseFront,
  'license_back_url' => context.l10n.licenseBack,
  _ => column,
};

/// One place both the mobile card and the web row read a driver's status
/// from, so the three colours and three labels can't drift apart between
/// them the way they had — the mobile card used `Colors.red` for suspended
/// while the web row used the kit's `AppColors.dangerInk`.
({String label, Color fill, Color ink}) driverStatusTone(
  BuildContext context,
  DriverAccount driver,
) {
  final l10n = context.l10n;
  if (driver.isPending) {
    return (
      label: l10n.statusPending,
      fill: AppColors.amberFill,
      ink: AppColors.amberInk,
    );
  }
  if (driver.isApproved) {
    return (
      label: l10n.statusApproved,
      fill: AppColors.successFill,
      ink: AppColors.successInk,
    );
  }
  return (
    label: l10n.statusSuspended,
    fill: AppColors.dangerFill,
    ink: AppColors.dangerInk,
  );
}

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  List<DriverAccount> _drivers = const [];
  DriverFilter _filter = DriverFilter.all;
  String _query = '';
  String? _busyId;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.fetchDrivers();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _drivers = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _uploadDoc(DriverAccount driver, String docType) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() => _busyId = driver.id);
    try {
      await _repo.uploadDriverDocument(
        driverId: driver.id,
        docType: docType,
        bytes: bytes,
        filename: file.name,
      );
      if (!mounted) return;
      showSnack(context, context.l10n.documentUploaded);
      await _load();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  void _onDocumentBoxTap(
    DriverAccount driver,
    String docTitle,
    String docType,
    String? imageUrl,
  ) {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      showAdaptiveSheet(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.remove_red_eye_outlined),
                title: Text(context.l10n.viewDocument(docTitle)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImagePreview('${driver.name} - $docTitle', imageUrl);
                },
              ),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(context.l10n.uploadReplaceDocument(docTitle)),
                onTap: () {
                  Navigator.pop(ctx);
                  _uploadDoc(driver, docType);
                },
              ),
            ],
          ),
        ),
      );
    } else {
      _uploadDoc(driver, docType);
    }
  }

  /// The finance/documents view — "how much do they owe, how much are they
  /// owed" had no screen at all before this, for either role.
  void _openDetail(DriverAccount driver) =>
      context.push('/admin-app/drivers/${driver.id}');

  Future<void> _setStatus(DriverAccount driver, String status) async {
    final l10n = context.l10n;
    String? reason;
    if (status == 'suspended') {
      final controller = TextEditingController();
      final confirmed = await showFormDialog<bool>(
        context: context,
        title: l10n.rejectSuspendDriver,
        icon: Icons.block_rounded,
        tone: AppDialogTone.danger,
        contentBuilder: (_) => TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.rejectionReasonHint),
        ),
        submitLabel: l10n.reject,
        cancelLabel: l10n.cancel,
        onSubmit: (_) async => true,
      );
      if (confirmed != true || !mounted) return;
      reason = controller.text.trim();
    }

    setState(() => _busyId = driver.id);
    try {
      await _repo.setDriverStatus(driver.id, status, reason: reason);
      if (!mounted) return;
      showSnack(context, switch (status) {
        'active' => l10n.driverApproved,
        'suspended' => l10n.driverSuspendedToast,
        _ => l10n.driverRejected,
      });
      await _load();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  List<DriverAccount> get _visibleDrivers {
    final byStatus = switch (_filter) {
      DriverFilter.all => _drivers,
      DriverFilter.pending => _drivers.where((d) => d.isPending),
      DriverFilter.active => _drivers.where((d) => d.isApproved),
      DriverFilter.suspended => _drivers.where((d) => d.isSuspended),
    };
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return byStatus.toList();
    return byStatus
        .where(
          (d) =>
              d.name.toLowerCase().contains(query) ||
              (d.phone?.toLowerCase().contains(query) ?? false),
        )
        .toList();
  }

  void _showImagePreview(String title, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title, style: const TextStyle(fontSize: 16)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            Flexible(
              child: InteractiveViewer(child: AppNetworkImage(url: imageUrl)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final webWide = AppBreakpoints.isWebWide(context);
    final canApprove = context.watch<AuthCubit>().state.can('drivers.approve');
    final pendingCount = _drivers.where((d) => d.isPending).length;
    final activeCount = _drivers.where((d) => d.isApproved).length;
    final suspendedCount = _drivers.where((d) => d.isSuspended).length;

    final filterBar = AppFilterBar(
      // The default gutter padding is right for the plain mobile Scaffold
      // body below, which has none of its own; the embedded/web branches
      // already sit inside a full page padding, so this would double it.
      padding: widget.embedded || webWide
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
      children: [
        AppFilterChip(
          label: l10n.all,
          count: _drivers.length,
          selected: _filter == DriverFilter.all,
          onTap: () => setState(() => _filter = DriverFilter.all),
        ),
        AppFilterChip(
          label: l10n.statusPending,
          count: pendingCount,
          selected: _filter == DriverFilter.pending,
          onTap: () => setState(() => _filter = DriverFilter.pending),
        ),
        AppFilterChip(
          label: l10n.statusApproved,
          count: activeCount,
          selected: _filter == DriverFilter.active,
          onTap: () => setState(() => _filter = DriverFilter.active),
        ),
        AppFilterChip(
          label: l10n.statusSuspended,
          count: suspendedCount,
          selected: _filter == DriverFilter.suspended,
          onTap: () => setState(() => _filter = DriverFilter.suspended),
        ),
      ],
    );

    // Creating a driver is approving one, so it needs the same permission.
    Future<void> newDriver() async {
      final created = await AdminCreateAccountScreen.open(
        context,
        NewAccountKind.driver,
      );
      if (created == true) _load();
    }

    final newDriverButton = canApprove
        ? FilledButton.icon(
            onPressed: newDriver,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: Text(l10n.addDriverAccount),
          )
        : null;

    final searchField = _drivers.length > 5
        ? Padding(
            padding: EdgeInsets.symmetric(
              horizontal: widget.embedded || webWide ? 0 : AppSpace.gutter,
            ),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.searchByName,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )
        : null;

    final body = _loading
        ? const _DriversSkeleton()
        : _error != null
        ? FailureView(error: _error!, onRetry: _load)
        : webWide
        ? _WebDriversTable(
            drivers: _visibleDrivers,
            busyId: _busyId,
            canApprove: canApprove,
            onDocumentTap: _onDocumentBoxTap,
            onSetStatus: _setStatus,
            onOpenDetail: _openDetail,
          )
        : _MobileList(
            drivers: _visibleDrivers,
            busyId: _busyId,
            canApprove: canApprove,
            onDocumentTap: _onDocumentBoxTap,
            onSetStatus: _setStatus,
            onOpenDetail: _openDetail,
          );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (newDriverButton != null) ...[
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: newDriverButton,
              ),
              const SizedBox(height: AppSpace.md),
            ],
            filterBar,
            if (searchField != null) ...[
              const SizedBox(height: AppSpace.sm),
              searchField,
            ],
            const SizedBox(height: AppSpace.lg),
            Expanded(child: body),
          ],
        ),
      );
    }

    if (webWide) {
      return WebPageChrome(
        forStaff: true,
        activeId: 'manage:/admin-app/drivers',
        sections: adminManageWebSections(context),
        pageTitle: l10n.driverApprovals,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (newDriverButton != null) ...[
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: newDriverButton,
                ),
                const SizedBox(height: AppSpace.md),
              ],
              filterBar,
              if (searchField != null) ...[
                const SizedBox(height: AppSpace.sm),
                searchField,
              ],
              const SizedBox(height: AppSpace.lg),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(l10n.driverApprovals),
        actions: [
          if (canApprove)
            IconButton(
              tooltip: l10n.addDriverAccount,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              onPressed: newDriver,
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: AppSpace.sm),
            filterBar,
            if (searchField != null) ...[
              const SizedBox(height: AppSpace.sm),
              searchField,
            ],
            Expanded(
              child: RefreshIndicator(onRefresh: _load, child: body),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shaped like the real cards, so the list doesn't jump when drivers land.
class _DriversSkeleton extends StatelessWidget {
  const _DriversSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonTheme(
    child: SkeletonList(
      padding: const EdgeInsets.all(AppSpace.gutter),
      itemCount: 4,
      separator: const SizedBox(height: AppSpace.md),
      itemBuilder: (_) => const Skeleton.box(height: 220, radius: AppRadii.lg),
    ),
  );
}

/// Mobile/narrow: a full card per driver, with an inline strip of document
/// thumbnails and the approve/suspend actions right below them — everything
/// a reviewer needs is on one card, nothing behind another tap.
class _MobileList extends StatelessWidget {
  const _MobileList({
    required this.drivers,
    required this.busyId,
    required this.canApprove,
    required this.onDocumentTap,
    required this.onSetStatus,
    required this.onOpenDetail,
  });

  final List<DriverAccount> drivers;
  final String? busyId;
  final bool canApprove;
  final void Function(DriverAccount driver) onOpenDetail;
  final void Function(
    DriverAccount driver,
    String docTitle,
    String docType,
    String? imageUrl,
  )
  onDocumentTap;
  final void Function(DriverAccount driver, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    if (drivers.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          EmptyView(
            message: context.l10n.noDriverApplications,
            icon: Icons.two_wheeler_outlined,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpace.gutter),
      itemCount: drivers.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpace.md),
      itemBuilder: (context, index) {
        final driver = drivers[index];
        final isBusy = busyId == driver.id;
        final status = driverStatusTone(context, driver);
        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(
              color: driver.isPending
                  ? AppColors.attentionBorder
                  : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => onOpenDetail(driver),
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: AppColors.warmFill,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.two_wheeler_rounded,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                            ),
                          ),
                          if (driver.phone != null)
                            Text(
                              driver.phone!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          const SizedBox(height: 2),
                          // Whether this application is even reviewable yet.
                          Text(
                            context.l10n.documentsOnFile(
                              driver.documents
                                  .where((d) => d.url != null)
                                  .length,
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color:
                                  driver.documents.every((d) => d.url != null)
                                  ? AppColors.successInk
                                  : AppColors.amberInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    SoftBadge(
                      label: status.label,
                      fill: status.fill,
                      ink: status.ink,
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textFaint,
                    ),
                  ],
                ),
              ),
              const Divider(height: AppSpace.xl, color: AppColors.borderSoft),
              Text(
                '${context.l10n.vehicleLabel}: ${driver.vehicleType ?? '—'}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                context.l10n.submittedDocuments,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              // All four, because both sides are what verifies a document: a
              // front shows a photo and a name, while the expiry and issuing
              // details are on the back.
              if (!driver.hasAnyDocument)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                  child: Text(
                    context.l10n.noDocumentsUploaded,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                )
              else
                // Horizontal: four documents side by side is how a reviewer
                // compares them, and stacking them pushes the approve
                // buttons off the screen.
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: driver.documents.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: AppSpace.md),
                    itemBuilder: (context, i) {
                      final doc = driver.documents[i];
                      final label = documentLabel(context, doc.column);
                      return SizedBox(
                        width: 150,
                        child: _DocumentBox(
                          title: label,
                          imageUrl: doc.url,
                          onTap: () =>
                              onDocumentTap(driver, label, doc.column, doc.url),
                        ),
                      );
                    },
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              if (isBusy)
                const Center(child: ButtonSpinner())
              // Approving and suspending are both `drivers.approve`; a role
              // with only `drivers.view` sees the list and no buttons.
              else if (canApprove)
                Row(
                  children: [
                    if (!driver.isApproved)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => onSetStatus(driver, 'active'),
                          icon: const Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          label: Text(context.l10n.approve),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.successInk,
                          ),
                        ),
                      ),
                    if (!driver.isApproved && !driver.isSuspended)
                      const SizedBox(width: AppSpace.sm),
                    if (!driver.isSuspended)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onSetStatus(driver, 'suspended'),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(
                            driver.isApproved
                                ? context.l10n.suspend
                                : context.l10n.reject,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.dangerInk,
                            side: const BorderSide(color: AppColors.dangerInk),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Web/wide: a name/vehicle/documents/status row per driver — the card's
/// document strip and approve/reject buttons compressed into columns and a
/// trailing action slot, the same shape [admin_deposits_screen.dart] uses for
/// its approval queue.
class _WebDriversTable extends StatelessWidget {
  const _WebDriversTable({
    required this.drivers,
    required this.busyId,
    required this.canApprove,
    required this.onDocumentTap,
    required this.onSetStatus,
    required this.onOpenDetail,
  });

  final List<DriverAccount> drivers;
  final String? busyId;
  final bool canApprove;
  final void Function(DriverAccount driver) onOpenDetail;
  final void Function(
    DriverAccount driver,
    String docTitle,
    String docType,
    String? imageUrl,
  )
  onDocumentTap;
  final void Function(DriverAccount driver, String status) onSetStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      child: WebTable(
        trailingWidth: 190,
        emptyState: EmptyView(
          message: l10n.noDriverApplications,
          icon: Icons.two_wheeler_outlined,
        ),
        columns: [
          WebTableColumn(label: l10n.driversTab, flex: 3),
          WebTableColumn(label: l10n.vehicleLabel, flex: 2),
          WebTableColumn(label: l10n.submittedDocuments, flex: 2),
          WebTableColumn(label: l10n.statusPending, width: 90),
          const WebTableColumn(label: '', width: 190),
        ],
        rows: [
          for (final driver in drivers)
            WebTableRow.aligned(
              trailingWidth: 190,
              onTap: () => onOpenDetail(driver),
              columns: [
                WebTableColumn(label: '', flex: 3),
                WebTableColumn(label: '', flex: 2),
                WebTableColumn(label: '', flex: 2),
                const WebTableColumn(label: '', width: 90),
                const WebTableColumn(label: '', width: 190),
              ],
              cells: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 15,
                      backgroundColor: AppColors.warmFill,
                      child: Icon(
                        Icons.two_wheeler_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            driver.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (driver.phone != null)
                            Text(
                              driver.phone!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                Text(
                  driver.vehicleType ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textSecondary,
                  ),
                ),
                driver.hasAnyDocument
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < driver.documents.length; i++) ...[
                            _DocumentDot(
                              label: documentLabel(
                                context,
                                driver.documents[i].column,
                              ),
                              hasImage: driver.documents[i].url != null,
                              onTap: () => onDocumentTap(
                                driver,
                                documentLabel(
                                  context,
                                  driver.documents[i].column,
                                ),
                                driver.documents[i].column,
                                driver.documents[i].url,
                              ),
                            ),
                            if (i != driver.documents.length - 1)
                              const SizedBox(width: 4),
                          ],
                        ],
                      )
                    : Text(
                        l10n.noDocumentsUploaded,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                Builder(
                  builder: (context) {
                    final status = driverStatusTone(context, driver);
                    return SoftBadge(
                      label: status.label,
                      fill: status.fill,
                      ink: status.ink,
                    );
                  },
                ),
              ],
              trailing: busyId == driver.id
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : !canApprove
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!driver.isSuspended)
                          _MiniButton(
                            label: driver.isApproved
                                ? l10n.suspend
                                : l10n.reject,
                            tone: AppColors.dangerInk,
                            onTap: () => onSetStatus(driver, 'suspended'),
                          ),
                        if (!driver.isApproved && !driver.isSuspended)
                          const SizedBox(width: 6),
                        if (!driver.isApproved)
                          _MiniButton(
                            label: l10n.approve,
                            tone: AppColors.successInk,
                            filled: true,
                            onTap: () => onSetStatus(driver, 'active'),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.tone,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final Color tone;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? tone : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            border: filled ? null : Border.all(color: tone),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: filled ? Colors.white : tone,
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, tappable stand-in for [_DocumentBox] sized for a table row
/// instead of a 150px-wide card.
class _DocumentDot extends StatelessWidget {
  const _DocumentDot({
    required this.label,
    required this.hasImage,
    required this.onTap,
  });

  final String label;
  final bool hasImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hasImage ? AppColors.successFill : AppColors.neutralFill,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hasImage
                  ? AppColors.successInk.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          child: Icon(
            hasImage ? Icons.check_rounded : Icons.upload_rounded,
            size: 14,
            color: hasImage ? AppColors.successInk : AppColors.textMuted,
          ),
        ),
      ),
    );
  }
}

class _DocumentBox extends StatelessWidget {
  const _DocumentBox({required this.title, this.imageUrl, required this.onTap});

  final String title;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.canvas,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: hasImage ? AppColors.primary : AppColors.border,
            width: hasImage ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  AppNetworkImage(url: imageUrl),
                  PositionedDirectional(
                    bottom: 0,
                    start: 0,
                    end: 0,
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.55),
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.badge_outlined, color: AppColors.textFaint),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.notUploaded,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.dangerInk,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
