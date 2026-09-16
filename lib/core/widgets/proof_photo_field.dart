import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/tokens.dart';
import '../utils/l10n_extension.dart';

/// A photo the user picked, held in memory until the form is submitted.
typedef PickedProof = ({String name, Uint8List bytes});

/// Lets the user take a photo or pick one they already have — a transfer
/// screenshot is in the gallery, a paper receipt is in their hand. The web has
/// no camera to offer, so it goes straight to the file picker.
///
/// Returns null when nothing was chosen, including when the source is not
/// available on this device (a simulator has no camera).
Future<PickedProof?> pickProofPhoto(BuildContext context) async {
  final source = kIsWeb
      ? ImageSource.gallery
      : await showModalBottomSheet<ImageSource>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) {
            final l10n = sheetContext.l10n;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const _SourceIcon(Icons.photo_library_rounded),
                      title: Text(l10n.chooseFromGallery),
                      onTap: () =>
                          Navigator.pop(sheetContext, ImageSource.gallery),
                    ),
                    ListTile(
                      leading: const _SourceIcon(Icons.photo_camera_rounded),
                      title: Text(l10n.takePhoto),
                      onTap: () =>
                          Navigator.pop(sheetContext, ImageSource.camera),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  if (source == null) return null;
  try {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 80,
    );
    if (picked == null) return null;
    return (name: picked.name, bytes: await picked.readAsBytes());
  } catch (_) {
    return null;
  }
}

class _SourceIcon extends StatelessWidget {
  const _SourceIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 40,
    height: 40,
    decoration: BoxDecoration(
      color: AppColors.warmFill,
      borderRadius: BorderRadius.circular(AppRadii.md),
    ),
    child: Icon(icon, color: AppColors.primary, size: 20),
  );
}

/// The "attach receipt" tile used by every money hand-over form.
class ProofPhotoField extends StatelessWidget {
  const ProofPhotoField({
    super.key,
    required this.proof,
    required this.onPick,
    required this.onClear,
    this.title,
    this.hint,
    this.required = false,
  });

  final PickedProof? proof;
  final VoidCallback onPick;
  final VoidCallback onClear;
  final String? title;
  final String? hint;
  final bool required;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bytes = proof?.bytes;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: bytes == null ? AppColors.canvas : AppColors.successFill,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(
            color: bytes == null
                ? AppColors.border
                : AppColors.successInk.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.sm),
              child: SizedBox(
                width: 56,
                height: 56,
                child: bytes == null
                    ? const ColoredBox(
                        color: AppColors.warmFill,
                        child: Icon(
                          Icons.add_a_photo_rounded,
                          color: AppColors.primary,
                        ),
                      )
                    : Image.memory(bytes, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bytes == null
                        ? '${title ?? l10n.attachProofPhoto}${required ? ' *' : ''}'
                        : l10n.changePhoto,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hint ?? l10n.attachProofHint,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (bytes != null)
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: onClear,
              ),
          ],
        ),
      ),
    );
  }
}
