import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/app_content.dart';
import '../../../core/repositories/app_content_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../../customer/profile/content_page_screen.dart' show iconForPlatform;
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Terms, privacy, about and the social footer — all editable here so wording
/// changes never wait on an app release.
class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({super.key});

  @override
  State<AdminContentScreen> createState() => _AdminContentScreenState();
}

class _AdminContentScreenState extends State<AdminContentScreen> {
  final _repo = AppContentRepository();
  late Future<({List<AppContent> pages, List<AppLink> links})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({List<AppContent> pages, List<AppLink> links})> _load() async {
    final results = await Future.wait([
      _repo.fetchAllContent(),
      _repo.fetchAllLinks(),
    ]);
    return (
      pages: results[0] as List<AppContent>,
      links: results[1] as List<AppLink>,
    );
  }

  void _reload() => setState(() => _future = _load());

  Future<void> _editPage(AppContent page) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => _PageEditor(page: page, repo: _repo)),
    );
    if (saved == true) _reload();
  }

  Future<void> _editLink([AppLink? link]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _LinkEditorSheet(link: link, repo: _repo),
    );
    if (saved == true) _reload();
  }

  Future<void> _deleteLink(AppLink link) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: link.platform,
      message: link.url,
      confirmText: context.l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteLink(link.id);
      _reload();
    } catch (e) {
      if (mounted) showFailure(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.content)),
      body: FutureBuilder<({List<AppContent> pages, List<AppLink> links})>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LoadingView();
          }
          if (snap.hasError) {
            return FailureView(error: snap.error!, onRetry: _reload);
          }
          final data = snap.data!;
          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpace.gutter,
              AppSpace.md,
              AppSpace.gutter,
              AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _sectionLabel(l10n.content),
              for (final page in data.pages)
                _Tile(
                  icon: switch (page.key) {
                    'terms' => Icons.gavel_outlined,
                    'privacy' => Icons.privacy_tip_outlined,
                    _ => Icons.info_outline,
                  },
                  title: page.titleEn.isEmpty ? page.key : page.titleEn,
                  subtitle: page.isPublished
                      ? (page.isEmpty ? l10n.contentNotAvailableYet : l10n.published)
                      : l10n.draft,
                  // An unpublished or empty page is the one an operator needs
                  // to notice, so it is the one that gets the warm tint.
                  attention: !page.isPublished || page.isEmpty,
                  onTap: () => _editPage(page),
                ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(child: _sectionLabel(l10n.socialLinks)),
                  TextButton.icon(
                    onPressed: () => _editLink(),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.addLink),
                  ),
                ],
              ),
              if (data.links.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
                  child: EmptyView(
                      message: l10n.socialLinks, icon: Icons.link_outlined),
                )
              else
                for (final link in data.links)
                  _Tile(
                    icon: iconForPlatform(link.platform),
                    title: link.platform,
                    subtitle: link.url,
                    dimmed: !link.isActive,
                    onTap: () => _editLink(link),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.dangerInk),
                      onPressed: () => _deleteLink(link),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xs, AppSpace.sm, AppSpace.xs, AppSpace.sm),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.textMuted,
          ),
        ),
      );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.attention = false,
    this.dimmed = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool attention;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        decoration: BoxDecoration(
          color: attention ? AppColors.warmFill : AppColors.surface,
          border: Border.all(
              color: attention ? AppColors.attentionBorder : AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: AppColors.primary),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textMuted)),
          trailing: trailing ??
              const Icon(Icons.chevron_right_rounded,
                  color: AppColors.textFaint),
        ),
      ),
    );
  }
}

/// Both languages side by side, so a page cannot be updated in English and
/// quietly left stale in Arabic.
class _PageEditor extends StatefulWidget {
  const _PageEditor({required this.page, required this.repo});

  final AppContent page;
  final AppContentRepository repo;

  @override
  State<_PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends State<_PageEditor> {
  late final _titleEn = TextEditingController(text: widget.page.titleEn);
  late final _titleAr = TextEditingController(text: widget.page.titleAr ?? '');
  late final _bodyEn = TextEditingController(text: widget.page.bodyEn);
  late final _bodyAr = TextEditingController(text: widget.page.bodyAr ?? '');
  late bool _published = widget.page.isPublished;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_titleEn, _titleAr, _bodyEn, _bodyAr]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repo.saveContent(AppContent(
        key: widget.page.key,
        titleEn: _titleEn.text.trim(),
        titleAr: _titleAr.text.trim().isEmpty ? null : _titleAr.text.trim(),
        bodyEn: _bodyEn.text.trim(),
        bodyAr: _bodyAr.text.trim().isEmpty ? null : _bodyAr.text.trim(),
        isPublished: _published,
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFailure(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(widget.page.titleEn.isEmpty
            ? widget.page.key
            : widget.page.titleEn),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpace.gutter,
          AppSpace.md,
          AppSpace.gutter,
          AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          TextField(
            controller: _titleEn,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(labelText: l10n.englishTitle),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _titleAr,
            textDirection: TextDirection.rtl,
            decoration: InputDecoration(labelText: l10n.arabicTitle),
          ),
          const SizedBox(height: AppSpace.lg),
          TextField(
            controller: _bodyEn,
            textDirection: TextDirection.ltr,
            maxLines: 12,
            minLines: 6,
            decoration: InputDecoration(
              labelText: l10n.englishBody,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _bodyAr,
            textDirection: TextDirection.rtl,
            maxLines: 12,
            minLines: 6,
            decoration: InputDecoration(
              labelText: l10n.arabicBody,
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: SwitchListTile(
              value: _published,
              onChanged: (v) => setState(() => _published = v),
              title: Text(l10n.published,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                _published ? l10n.published : l10n.draft,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textMuted),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving ? null : _save,
            child: _saving ? const ButtonSpinner() : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}

class _LinkEditorSheet extends StatefulWidget {
  const _LinkEditorSheet({required this.link, required this.repo});

  final AppLink? link;
  final AppContentRepository repo;

  @override
  State<_LinkEditorSheet> createState() => _LinkEditorSheetState();
}

class _LinkEditorSheetState extends State<_LinkEditorSheet> {
  /// The platforms with a real icon. Free text would render as a generic link.
  static const _platforms = [
    'facebook',
    'instagram',
    'x',
    'tiktok',
    'youtube',
    'whatsapp',
    'linkedin',
    'website',
    'email',
    'phone',
  ];

  late String _platform = widget.link?.platform ?? _platforms.first;
  late final _url = TextEditingController(text: widget.link?.url ?? '');
  late bool _active = widget.link?.isActive ?? true;
  late final _sort =
      TextEditingController(text: '${widget.link?.sortOrder ?? 0}');
  bool _saving = false;

  @override
  void dispose() {
    _url.dispose();
    _sort.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (url.isEmpty) return;
    setState(() => _saving = true);
    try {
      await widget.repo.saveLink(
        id: widget.link?.id,
        platform: _platform,
        url: url,
        isActive: _active,
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showFailure(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpace.xl,
        right: AppSpace.xl,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.addLink, style: AppType.heading(17)),
          const SizedBox(height: AppSpace.lg),
          DropdownButtonFormField<String>(
            initialValue: _platform,
            decoration: InputDecoration(labelText: l10n.platform),
            items: [
              for (final p in _platforms)
                DropdownMenuItem(
                  value: p,
                  child: Row(
                    children: [
                      Icon(iconForPlatform(p), size: 18),
                      const SizedBox(width: AppSpace.sm),
                      Text(p),
                    ],
                  ),
                ),
            ],
            onChanged: (v) => setState(() => _platform = v ?? _platform),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              labelText: l10n.linkUrl,
              hintText: 'https://',
            ),
          ),
          const SizedBox(height: AppSpace.md),
          TextField(
            controller: _sort,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.sortOrder),
          ),
          const SizedBox(height: AppSpace.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _active,
            onChanged: (v) => setState(() => _active = v),
            title: Text(l10n.active,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            style:
                FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _saving ? null : _save,
            child: _saving ? const ButtonSpinner() : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
