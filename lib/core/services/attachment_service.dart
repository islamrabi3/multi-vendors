import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../supabase_client.dart';

/// One uploaded chat attachment.
///
/// [path] is the object key inside the bucket, not a URL: the bucket is
/// private, so anything displayable has to be signed first and a stored URL
/// would be dead within the hour.
class ChatAttachment {
  const ChatAttachment({
    required this.path,
    required this.name,
    required this.isImage,
  });

  final String path;
  final String name;
  final bool isImage;

  /// The value written to `attachment_type`; the check constraint on both
  /// message tables allows exactly these two.
  String get type => isImage ? 'image' : 'file';
}

/// Picking and uploading attachments for the order chat and the support chat.
///
/// Both chats want the same three things — pick, upload, show — and the
/// signing cache only pays off if it is shared, so this is a singleton rather
/// than a mixin on each screen.
class AttachmentService {
  AttachmentService._();

  static final AttachmentService instance = AttachmentService._();

  static const String bucket = 'chat-attachments';

  /// Signed URLs live an hour on the server; they are dropped here after 50
  /// minutes so a long-open thread never renders one that has just expired.
  static const Duration _signedFor = Duration(hours: 1);
  static const Duration _cacheFor = Duration(minutes: 50);

  final _picker = ImagePicker();
  final Map<String, ({String url, DateTime at})> _signed = {};

  /// Camera roll. Compressed on the way in: a modern phone photo is several
  /// megabytes and nothing in a chat bubble needs that.
  Future<ChatAttachment?> pickImage({bool fromCamera = false}) async {
    final picked = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (picked == null) return null;
    return _upload(
      bytes: await picked.readAsBytes(),
      name: picked.name,
      isImage: true,
    );
  }

  /// Any document. `withData` is required: on Android the picker otherwise
  /// hands back a content:// path this code cannot read.
  Future<ChatAttachment?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return null;
    return _upload(
      bytes: bytes,
      name: file.name,
      // An image chosen through the file picker still renders as one.
      isImage: _imageExtensions.contains(_extensionOf(file.name)),
    );
  }

  Future<ChatAttachment> _upload({
    required Uint8List bytes,
    required String name,
    required bool isImage,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final extension = _extensionOf(name);
    // The uploader's id has to be the first path segment — the storage policy
    // checks exactly that. The rest is unguessable, which is what keeps the
    // object private in a bucket every signed-in user may read from.
    final key = '$userId/${DateTime.now().microsecondsSinceEpoch}'
        '-${bytes.length}${extension.isEmpty ? '' : '.$extension'}';
    await supabase.storage.from(bucket).uploadBinary(key, bytes);
    return ChatAttachment(path: key, name: name, isImage: isImage);
  }

  /// A short-lived URL for an object, reused while it is still fresh.
  Future<String> signedUrl(String path) async {
    final hit = _signed[path];
    if (hit != null && DateTime.now().difference(hit.at) < _cacheFor) {
      return hit.url;
    }
    final url = await supabase.storage
        .from(bucket)
        .createSignedUrl(path, _signedFor.inSeconds);
    _signed[path] = (url: url, at: DateTime.now());
    return url;
  }

  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'heic'};

  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }
}
