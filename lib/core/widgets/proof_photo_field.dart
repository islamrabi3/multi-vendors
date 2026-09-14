import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/tokens.dart';
import '../utils/l10n_extension.dart';

/// A photo the user picked, held in memory until the form is submitted.
typedef PickedProof = ({String name, Uint8List bytes});

/// Opens the camera on a phone (a receipt is photographed where it is) and
/// the file picker on the web.
Future<PickedProof?> pickProofPhoto() async {
  final picked = await ImagePicker().pickImage(
    source: kIsWeb ? ImageSource.gallery : ImageSource.camera,
    maxWidth: 1600,
    imageQuality: 80,
  );
  if (picked == null) return null;
  return (name: picked.name, bytes: await picked.readAsBytes());
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
