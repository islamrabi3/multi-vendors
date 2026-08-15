import 'package:equatable/equatable.dart';

import 'product.dart' show localizedText;

/// A document the signed-in partner must accept before continuing.
///
/// Carries the text as well as the key, so the gate screen can render without
/// a second round trip — and so the version shown is provably the version the
/// acceptance is recorded against.
class PendingPolicy extends Equatable {
  const PendingPolicy({
    required this.key,
    required this.version,
    required this.titleEn,
    required this.bodyEn,
    this.titleAr,
    this.bodyAr,
  });

  final String key;
  final int version;
  final String titleEn;
  final String? titleAr;
  final String bodyEn;
  final String? bodyAr;

  String title(String languageCode) =>
      localizedText(titleEn, titleAr, languageCode);

  String body(String languageCode) =>
      localizedText(bodyEn, bodyAr, languageCode);

  static PendingPolicy? fromMap(Map<String, dynamic>? map) {
    if (map == null) return null;
    final key = map['key'] as String?;
    if (key == null || key.isEmpty) return null;
    return PendingPolicy(
      key: key,
      version: (map['version'] as num?)?.toInt() ?? 1,
      titleEn: (map['title_en'] as String?) ?? '',
      titleAr: map['title_ar'] as String?,
      bodyEn: (map['body_en'] as String?) ?? '',
      bodyAr: map['body_ar'] as String?,
    );
  }

  @override
  List<Object?> get props => [key, version];
}
