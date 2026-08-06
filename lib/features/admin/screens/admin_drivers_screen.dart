import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app/tokens.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';
import '../../auth/auth_cubit.dart';

enum DriverFilter { all, pending, active, suspended }

class AdminDriversScreen extends StatefulWidget {
  const AdminDriversScreen({super.key});

  @override
  State<AdminDriversScreen> createState() => _AdminDriversScreenState();
}

class _AdminDriversScreenState extends State<AdminDriversScreen> {
  final _repo = AdminRepository();
  bool _loading = true;
  List<DriverAccount> _drivers = const [];
  DriverFilter _filter = DriverFilter.all;
  String? _busyId;
  String? _error;

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
        _error = e.toString();
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
      showModalBottomSheet(
        context: context,
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

  Future<void> _setStatus(DriverAccount driver, String status) async {
    String? reason;
    if (status == 'suspended') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.rejectSuspendDriver),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: context.l10n.rejectionReasonHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(context.l10n.reject),
            ),
          ],
        ),
      );
      if (reason == null) return;
    }

    setState(() => _busyId = driver.id);
    try {
      await _repo.setDriverStatus(driver.id, status, reason: reason);
      if (!mounted) return;
      showSnack(context, switch (status) {
        'active' => context.l10n.driverApproved,
        'suspended' => context.l10n.driverSuspendedToast,
        _ => context.l10n.driverRejected,
      });
      await _load();
    } catch (e) {
      if (mounted) showFailure(context, e);
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  List<DriverAccount> get _visibleDrivers {
    switch (_filter) {
      case DriverFilter.all:
        return _drivers;
      case DriverFilter.pending:
        return _drivers.where((d) => d.isPending).toList();
      case DriverFilter.active:
        return _drivers.where((d) => d.isApproved).toList();
      case DriverFilter.suspended:
        return _drivers.where((d) => d.isSuspended).toList();
    }
  }

  void _showImagePreview(String title, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(title, style: const TextStyle(fontSize: 16)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            InteractiveViewer(
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    context.l10n.couldNotLoadDocument,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canApprove = context.watch<AuthCubit>().state.can('drivers.approve');
    final pendingCount = _drivers.where((d) => d.isPending).length;
    final activeCount = _drivers.where((d) => d.isApproved).length;
    final suspendedCount = _drivers.where((d) => d.isSuspended).length;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(context.l10n.driverApprovals)),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // Filter Bar
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.gutter,
                vertical: AppSpace.sm,
              ),
              child: Row(
                children: [
                  FilterChip(
                    selectedColor: AppColors.attentionBorder,
                    label: Text(context.l10n.allWithCount(_drivers.length)),
                    selected: _filter == DriverFilter.all,
                    onSelected: (_) =>
                        setState(() => _filter = DriverFilter.all),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(context.l10n.pendingWithCount(pendingCount)),
                    selected: _filter == DriverFilter.pending,
                    selectedColor: AppColors.amberFill,
                    onSelected: (_) =>
                        setState(() => _filter = DriverFilter.pending),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(context.l10n.approvedWithCount(activeCount)),
                    selected: _filter == DriverFilter.active,
                    selectedColor: AppColors.successFill,
                    onSelected: (_) =>
                        setState(() => _filter = DriverFilter.active),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text(
                      context.l10n.suspendedWithCount(suspendedCount),
                    ),
                    selected: _filter == DriverFilter.suspended,
                    selectedColor: Colors.red.shade100,
                    onSelected: (_) =>
                        setState(() => _filter = DriverFilter.suspended),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ErrorView(message: _error!, onRetry: _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _visibleDrivers.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 80),
                                EmptyView(
                                  message: context.l10n.noDriverApplications,
                                  icon: Icons.two_wheeler_outlined,
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(AppSpace.gutter),
                              itemCount: _visibleDrivers.length,
                              itemBuilder: (context, index) {
                                final driver = _visibleDrivers[index];
                                final isBusy = _busyId == driver.id;
                                return Card(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            CircleAvatar(
                                              backgroundColor:
                                                  AppColors.warmFill,
                                              child: const Icon(
                                                Icons.two_wheeler,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    driver.name,
                                                    style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                  if (driver.phone != null)
                                                    Text(
                                                      driver.phone!,
                                                      style: TextStyle(
                                                        color: Colors
                                                            .grey
                                                            .shade600,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  const SizedBox(height: 2),
                                                  // Whether this application
                                                  // is even reviewable yet.
                                                  Text(
                                                    context.l10n
                                                        .documentsOnFile(
                                                          driver.documents
                                                              .where(
                                                                (d) =>
                                                                    d.url !=
                                                                    null,
                                                              )
                                                              .length,
                                                        ),
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          driver.documents
                                                              .every(
                                                                (d) =>
                                                                    d.url !=
                                                                    null,
                                                              )
                                                          ? AppColors.successInk
                                                          : AppColors.amberInk,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 10,
                                                    vertical: 4,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: driver.isPending
                                                    ? AppColors.amberFill
                                                    : driver.isApproved
                                                    ? AppColors.successFill
                                                    : Colors.red.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                // Not the raw column value:
                                                // "ACTIVE" is a database word,
                                                // and it was never translated.
                                                driver.isPending
                                                    ? context.l10n.statusPending
                                                    : driver.isApproved
                                                    ? context
                                                          .l10n
                                                          .statusApproved
                                                    : context
                                                          .l10n
                                                          .statusSuspended,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: driver.isPending
                                                      ? AppColors.amberInk
                                                      : driver.isApproved
                                                      ? AppColors.successInk
                                                      : Colors.red,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(height: 24),
                                        Text(
                                          '${context.l10n.vehicleLabel}: '
                                          '${driver.vehicleType ?? '—'}',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          context.l10n.submittedDocuments,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        // All four, because both sides are
                                        // what verifies a document: a front
                                        // shows a photo and a name, while the
                                        // expiry and issuing details are on
                                        // the back.
                                        if (!driver.hasAnyDocument)
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                            child: Text(
                                              context.l10n.noDocumentsUploaded,
                                              style: const TextStyle(
                                                fontSize: 12.5,
                                                color: AppColors.textMuted,
                                              ),
                                            ),
                                          )
                                        else
                                          // Horizontal: four documents side by
                                          // side is how a reviewer compares
                                          // them, and stacking them pushes the
                                          // approve buttons off the screen.
                                          SizedBox(
                                            height: 118,
                                            child: ListView.separated(
                                              scrollDirection: Axis.horizontal,
                                              itemCount:
                                                  driver.documents.length,
                                              separatorBuilder: (_, _) =>
                                                  const SizedBox(width: 12),
                                              itemBuilder: (context, i) {
                                                final doc = driver.documents[i];
                                                final label = _documentLabel(
                                                  context,
                                                  doc.column,
                                                );
                                                return SizedBox(
                                                  width: 150,
                                                  child: _DocumentBox(
                                                    title: label,
                                                    imageUrl: doc.url,
                                                    onTap: () =>
                                                        _onDocumentBoxTap(
                                                          driver,
                                                          label,
                                                          doc.column,
                                                          doc.url,
                                                        ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
                                        const SizedBox(height: 16),
                                        if (isBusy)
                                          const Center(
                                            child: CircularProgressIndicator(),
                                          )
                                        // Approving and suspending are both
                                        // `drivers.approve`; a role with only
                                        // `drivers.view` sees the list and no
                                        // buttons.
                                        else if (canApprove)
                                          Row(
                                            children: [
                                              if (!driver.isApproved)
                                                Expanded(
                                                  child: FilledButton.icon(
                                                    onPressed: () => _setStatus(
                                                      driver,
                                                      'active',
                                                    ),
                                                    icon: const Icon(
                                                      Icons
                                                          .check_circle_outline,
                                                      size: 18,
                                                    ),
                                                    label: Text(
                                                      context.l10n.approve,
                                                    ),
                                                    style:
                                                        FilledButton.styleFrom(
                                                          backgroundColor:
                                                              AppColors
                                                                  .successInk,
                                                        ),
                                                  ),
                                                ),
                                              if (!driver.isApproved &&
                                                  !driver.isSuspended)
                                                const SizedBox(width: 8),
                                              if (!driver.isSuspended)
                                                Expanded(
                                                  child: OutlinedButton.icon(
                                                    onPressed: () => _setStatus(
                                                      driver,
                                                      'suspended',
                                                    ),
                                                    icon: const Icon(
                                                      Icons.cancel_outlined,
                                                      size: 18,
                                                    ),
                                                    label: Text(
                                                      driver.isApproved
                                                          ? context.l10n.suspend
                                                          : context.l10n.reject,
                                                    ),
                                                    style:
                                                        OutlinedButton.styleFrom(
                                                          foregroundColor:
                                                              Colors.red,
                                                        ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reviewer-facing name of a document column.
String _documentLabel(BuildContext context, String column) => switch (column) {
  'id_card_url' => context.l10n.idFront,
  'id_card_back_url' => context.l10n.idBack,
  'license_url' => context.l10n.licenseFront,
  'license_back_url' => context.l10n.licenseBack,
  _ => column,
};

class _DocumentBox extends StatelessWidget {
  const _DocumentBox({required this.title, this.imageUrl, required this.onTap});

  final String title;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = imageUrl != null && imageUrl!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: hasImage ? AppColors.primary : Colors.grey.shade300,
            width: hasImage ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.broken_image, color: Colors.grey),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      color: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.badge_outlined, color: Colors.grey.shade400),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.notUploaded,
                    style: TextStyle(fontSize: 9, color: Colors.red.shade400),
                  ),
                ],
              ),
      ),
    );
  }
}
