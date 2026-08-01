import 'package:equatable/equatable.dart';

import 'product.dart' show localizedText;

/// A long-form page the operator edits from the admin app — terms, privacy,
/// about — rather than one compiled into the build.
class AppContent extends Equatable {
  const AppContent({
    required this.key,
    required this.titleEn,
    required this.bodyEn,
    this.titleAr,
    this.bodyAr,
    this.isPublished = true,
    this.updatedAt,
  });

  /// Slug: `terms`, `privacy`, `about`.
  final String key;
  final String titleEn;
  final String? titleAr;
  final String bodyEn;
  final String? bodyAr;

  /// Unpublished pages are hidden from customers but still editable by admins,
  /// so a page can be drafted before it goes live.
  final bool isPublished;
  final DateTime? updatedAt;

  String title(String languageCode) =>
      localizedText(titleEn, titleAr, languageCode);

  String body(String languageCode) =>
      localizedText(bodyEn, bodyAr, languageCode);

  /// True when there is nothing worth opening a screen for.
  bool get isEmpty => bodyEn.trim().isEmpty && (bodyAr?.trim() ?? '').isEmpty;

  factory AppContent.fromMap(Map<String, dynamic> map) => AppContent(
        key: map['key'] as String,
        titleEn: (map['title_en'] as String?) ?? '',
        titleAr: map['title_ar'] as String?,
        bodyEn: (map['body_en'] as String?) ?? '',
        bodyAr: map['body_ar'] as String?,
        isPublished: (map['is_published'] as bool?) ?? true,
        updatedAt: map['updated_at'] == null
            ? null
            : DateTime.parse(map['updated_at'] as String),
      );

  @override
  List<Object?> get props =>
      [key, titleEn, titleAr, bodyEn, bodyAr, isPublished, updatedAt];
}

/// One social or contact link in the about page footer.
class AppLink extends Equatable {
  const AppLink({
    required this.id,
    required this.platform,
    required this.url,
    this.isActive = true,
    this.sortOrder = 0,
  });

  final String id;

  /// Drives the icon; unknown values fall back to a generic link glyph, so a
  /// platform added from the admin app never renders as a blank.
  final String platform;
  final String url;
  final bool isActive;
  final int sortOrder;

  factory AppLink.fromMap(Map<String, dynamic> map) => AppLink(
        id: map['id'] as String,
        platform: ((map['platform'] as String?) ?? 'website').toLowerCase(),
        url: (map['url'] as String?) ?? '',
        isActive: (map['is_active'] as bool?) ?? true,
        sortOrder: ((map['sort_order'] as num?) ?? 0).toInt(),
      );

  @override
  List<Object?> get props => [id, platform, url, isActive, sortOrder];
}
