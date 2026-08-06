import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/tokens.dart';
import '../../../core/repositories/auth_repository.dart';
import '../../../core/repositories/driver_repository.dart';
import '../../../core/supabase_client.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/common.dart';

/// Where a driver submits or replaces their verification documents.
///
/// Signup collects these, but only lands them when the account gets a session
/// immediately. With email confirmation on there is no session at signup, so
/// without this screen an applicant's documents were collected and dropped and
/// the review queue filled with requests carrying no photos.
///
/// It is also the only place a rejection can be answered: the reason is shown
/// here, and replacing a photo puts the application back in the queue.
class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key});

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  final _drivers = DriverRepository();
  final _auth = AuthRepository();

  // A stream, not a fetch: an admin's approval or rejection lands here as it
  // is made, and an upload is itself a change to this row — so submitting
  // updates the screen without a manual reload.
  late final Stream<DriverVerification> _verification = _drivers
      .watchVerification();
  final _picked = <String, XFile>{};
  bool _saving = false;

  Future<void> _pick(String column) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _picked[column] = file);
  }

  Future<void> _submit() async {
    if (_picked.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _auth.uploadDriverDocuments(
        supabase.auth.currentUser!.id,
        DriverDocuments(
          idCardFront: _picked['id_card_url'],
          idCardBack: _picked['id_card_back_url'],
          licenseFront: _picked['license_url'],
          licenseBack: _picked['license_back_url'],
        ),
      );
      if (!mounted) return;
      setState(_picked.clear);
      showSnack(context, context.l10n.documentsSubmitted);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.driverVerificationTitle)),
      body: StreamBuilder<DriverVerification>(
        stream: _verification,
        builder: (context, snap) {
          if (snap.hasError) {
            return FailureView(error: snap.error!);
          }
          final verification = snap.data;
          if (verification == null) return const LoadingView();
          return ListView(
            padding: const EdgeInsets.all(AppSpace.lg),
            children: [
              _StatusBanner(verification: verification),
              const SizedBox(height: AppSpace.lg),
              Text(
                l10n.driverDocumentsSubtitle,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Two per row: both sides of one document sit side by side, which
              // is how they are checked.
              for (var i = 0; i < DriverVerification.columns.length; i += 2)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Row(
                    children: [
                      for (final column
                          in DriverVerification.columns.skip(i).take(2)) ...[
                        Expanded(
                          child: _DocumentSlot(
                            label: _label(context, column),
                            picked: _picked[column],
                            onFile: verification.has(column),
                            onTap: () => _pick(column),
                          ),
                        ),
                        if (column != DriverVerification.columns[i + 1])
                          const SizedBox(width: AppSpace.sm),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              FilledButton(
                // Only what was picked in this visit is uploaded; a document
                // already on file is left alone rather than re-sent.
                onPressed: _saving || _picked.isEmpty ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Text(l10n.submitForReview),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _label(BuildContext context, String column) => switch (column) {
  'id_card_url' => context.l10n.idFront,
  'id_card_back_url' => context.l10n.idBack,
  'license_url' => context.l10n.licenseFront,
  'license_back_url' => context.l10n.licenseBack,
  _ => column,
};

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.verification});

  final DriverVerification verification;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (message, fill, ink, icon) = switch (verification) {
      final v when v.isApproved => (
        l10n.driverVerificationApproved,
        AppColors.successFill,
        AppColors.successInk,
        Icons.verified_rounded,
      ),
      final v when v.isRejected => (
        v.rejectionReason?.trim().isNotEmpty ?? false
            // The admin's own words: "blurry" and "wrong document" need
            // different fixes, and a generic refusal tells the driver neither.
            ? '${l10n.driverVerificationRejected}\n${v.rejectionReason}'
            : l10n.driverVerificationRejected,
        AppColors.dangerFill,
        AppColors.dangerInk,
        Icons.error_outline_rounded,
      ),
      final v when v.isSuspended => (
        l10n.driverVerificationSuspended,
        AppColors.dangerFill,
        AppColors.dangerInk,
        Icons.block_rounded,
      ),
      _ => (
        l10n.driverVerificationPending,
        AppColors.warmFill,
        AppColors.primaryDark,
        Icons.hourglass_top_rounded,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: ink),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One document slot: what is on file, or what is about to replace it.
class _DocumentSlot extends StatefulWidget {
  const _DocumentSlot({
    required this.label,
    required this.picked,
    required this.onFile,
    required this.onTap,
  });

  final String label;
  final XFile? picked;
  final bool onFile;
  final VoidCallback onTap;

  @override
  State<_DocumentSlot> createState() => _DocumentSlotState();
}

class _DocumentSlotState extends State<_DocumentSlot> {
  Uint8List? _preview;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DocumentSlot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.picked?.path != widget.picked?.path) _load();
  }

  Future<void> _load() async {
    final file = widget.picked;
    if (file == null) {
      if (mounted) setState(() => _preview = null);
      return;
    }
    try {
      final bytes = await file.readAsBytes();
      if (mounted && widget.picked?.path == file.path) {
        setState(() => _preview = bytes);
      }
    } catch (_) {
      // The slot still reads as filled; only the thumbnail is missing.
    }
  }

  @override
  Widget build(BuildContext context) {
    // A document already on file counts as done even with nothing picked now:
    // the driver is here to replace one photo, not to re-upload all four.
    final filled = widget.picked != null || widget.onFile;
    return InkWell(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        height: 104,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: filled ? AppColors.successFill : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: filled ? AppColors.success : AppColors.border,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_preview != null)
              Image.memory(_preview!, fit: BoxFit.cover)
            else
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    filled
                        ? Icons.check_circle_rounded
                        : Icons.add_a_photo_rounded,
                    size: 20,
                    color: filled ? AppColors.success : AppColors.primary,
                  ),
                  const SizedBox(height: 6),
                  if (filled && widget.picked == null)
                    Text(
                      context.l10n.onFileLabel,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppColors.successInk,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                color: _preview != null
                    ? Colors.black.withValues(alpha: 0.55)
                    : Colors.transparent,
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _preview != null ? Colors.white : AppColors.ink,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
