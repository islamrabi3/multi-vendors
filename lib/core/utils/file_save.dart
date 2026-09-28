import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Hands [bytes] to the person as a file called [fileName]: a download in a
/// browser, the system "save as" sheet on a phone or desktop. Returns false
/// when they backed out of choosing where it goes.
Future<bool> saveBytesAsFile({
  required String fileName,
  required Uint8List bytes,
  required List<String> extensions,
}) async {
  final path = await FilePicker.platform.saveFile(
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: extensions,
  );
  // On the web the browser downloads the file and there is no path to give
  // back, so a null there is not a cancellation.
  return path != null || kIsWeb;
}

/// A file name that is safe on every platform, from a store's name.
String safeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .trim();
  return cleaned.isEmpty ? 'menu' : cleaned;
}
