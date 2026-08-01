import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/tokens.dart';
import '../services/attachment_service.dart';
import '../utils/l10n_extension.dart';
import 'common.dart' show showSnack;

/// The three ways to attach something, shared by both chats.
enum _AttachChoice {
  photo(Icons.image_outlined),
  camera(Icons.photo_camera_outlined),
  file(Icons.attach_file_rounded);

  const _AttachChoice(this.icon);

  final IconData icon;

  String label(BuildContext context) => switch (this) {
        _AttachChoice.photo => context.l10n.attachPhoto,
        _AttachChoice.camera => context.l10n.attachCamera,
        _AttachChoice.file => context.l10n.attachFile,
      };

  Future<ChatAttachment?> pick() => switch (this) {
        _AttachChoice.photo => AttachmentService.instance.pickImage(),
        _AttachChoice.camera =>
          AttachmentService.instance.pickImage(fromCamera: true),
        _AttachChoice.file => AttachmentService.instance.pickFile(),
      };
}

/// Asks what to attach, then picks and uploads it.
///
/// Returns null when the user backs out of either step — which is the common
/// case, so callers must not treat it as a failure. A failed *upload* is
/// reported here and also returns null, since the caller has nothing to send
/// either way.
Future<ChatAttachment?> pickChatAttachment(BuildContext context) async {
  final choice = await showModalBottomSheet<_AttachChoice>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in _AttachChoice.values)
            ListTile(
              leading: Icon(option.icon),
              title: Text(option.label(sheetContext)),
              onTap: () => Navigator.pop(sheetContext, option),
            ),
        ],
      ),
    ),
  );
  if (choice == null) return null;
  try {
    return await choice.pick();
  } catch (error) {
    if (context.mounted) {
      showSnack(context, context.l10n.attachmentUploadFailed, error: true);
    }
    return null;
  }
}

/// Renders one attachment inside a chat bubble.
///
/// The bucket is private, so nothing here has a URL to start with — the path
/// is signed on first build and the signature is cached by
/// [AttachmentService], which is why a thread of twenty photos does not make
/// twenty round trips every rebuild.
class ChatAttachmentView extends StatefulWidget {
  const ChatAttachmentView({
    super.key,
    required this.path,
    required this.isImage,
    this.name,
    this.onDark = false,
  });

  final String path;
  final bool isImage;
  final String? name;

  /// Bubbles come in two colours and the file row has to stay legible on both.
  final bool onDark;

  @override
  State<ChatAttachmentView> createState() => _ChatAttachmentViewState();
}

class _ChatAttachmentViewState extends State<ChatAttachmentView> {
  late Future<String> _url = AttachmentService.instance.signedUrl(widget.path);

  @override
  void didUpdateWidget(ChatAttachmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _url = AttachmentService.instance.signedUrl(widget.path);
    }
  }

  Future<void> _open(String url) async {
    final launched = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      showSnack(context, context.l10n.attachmentOpenFailed, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) {
          return _FileRow(
            label: context.l10n.attachmentUnavailable,
            onDark: widget.onDark,
            icon: Icons.error_outline,
            onTap: null,
          );
        }
        final url = snap.data;
        if (url == null) {
          return SizedBox(
            height: widget.isImage ? 140 : 20,
            child: const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        if (!widget.isImage) {
          return _FileRow(
            label: widget.name ?? context.l10n.attachment,
            onDark: widget.onDark,
            icon: Icons.insert_drive_file_outlined,
            onTap: () => _open(url),
          );
        }
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => _ImageViewer(url: url),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.md),
            child: CachedNetworkImage(
              imageUrl: url,
              width: 220,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 220,
                height: 140,
                color: AppColors.neutralFill,
              ),
              errorWidget: (_, _, _) => _FileRow(
                label: context.l10n.attachmentUnavailable,
                onDark: widget.onDark,
                icon: Icons.broken_image_outlined,
                onTap: null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.icon,
    required this.onDark,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool onDark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onDark ? Colors.white : AppColors.ink;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: onDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.neutralFill,
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: AppSpace.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-bleed view for a tapped photo. Black, because a receipt photographed
/// in a dark restaurant is unreadable on white.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: InteractiveViewer(
          maxScale: 4,
          child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
