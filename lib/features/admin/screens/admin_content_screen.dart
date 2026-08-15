import 'package:flutter/material.dart';

import '../../../app/tokens.dart';
import '../../../core/models/app_content.dart';
import '../../../core/repositories/app_content_repository.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/skeleton.dart' show ButtonSpinner;
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
import '../../customer/profile/content_page_screen.dart' show iconForPlatform;
import 'package:multi_vendor/core/utils/l10n_extension.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import '../../../core/widgets/web/adaptive_sheet.dart';

/// Terms, privacy, about and the social footer — all editable here so wording
/// changes never wait on an app release.
class AdminContentScreen extends StatefulWidget {
  const AdminContentScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

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

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _editPage(AppContent page) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _PageEditor(page: page, repo: _repo),
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _editLink([AppLink? link]) async {
    final saved = await showAdaptiveSheet<bool>(
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
    final webWide = AppBreakpoints.isWebWide(context);

    final body = FutureBuilder<({List<AppContent> pages, List<AppLink> links})>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingView();
        }
        if (snap.hasError) {
          return FailureView(error: snap.error!, onRetry: _reload);
        }
        final data = snap.data!;
        // A settings-style row of one title plus one status line reads
        // as broken stretched full-bleed across a monitor — wide screens
        // get a compact table instead, same rows and actions.
        if (webWide) {
          return _WebContentTables(
            pages: data.pages,
            links: data.links,
            onEditPage: _editPage,
            onAddLink: () => _editLink(),
            onEditLink: _editLink,
            onDeleteLink: _deleteLink,
          );
        }
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
                    ? (page.isEmpty
                          ? l10n.contentNotAvailableYet
                          : l10n.published)
                    : l10n.draft,
                // An unpublished or empty page is the one an operator
                // needs to notice, so it is the one that gets the warm
                // tint.
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
                  message: l10n.socialLinks,
                  icon: Icons.link_outlined,
                ),
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
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.dangerInk,
                    ),
                    onPressed: () => _deleteLink(link),
                  ),
                ),
          ],
        );
      },
    );

    if (widget.embedded) {
      return Padding(padding: const EdgeInsets.all(AppSpace.xl), child: body);
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/content',
        sections: adminManageWebSections(context),
        pageTitle: l10n.content,
        child: Padding(padding: const EdgeInsets.all(AppSpace.xl), child: body),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.content)),
      body: body,
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpace.xs,
      AppSpace.sm,
      AppSpace.xs,
      AppSpace.sm,
    ),
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

/// The desktop counterpart to the compact mobile settings rows above.
/// Keeping pages and footer links in separate tables makes the two content
/// types immediately scannable while retaining the same edit/delete actions.
class _WebContentTables extends StatelessWidget {
  const _WebContentTables({
    required this.pages,
    required this.links,
    required this.onEditPage,
    required this.onAddLink,
    required this.onEditLink,
    required this.onDeleteLink,
  });

  final List<AppContent> pages;
  final List<AppLink> links;
  final ValueChanged<AppContent> onEditPage;
  final VoidCallback onAddLink;
  final ValueChanged<AppLink> onEditLink;
  final ValueChanged<AppLink> onDeleteLink;

  // Not `static const`: a const list cannot reach `l10n`, which is exactly
  // why these column headers stayed English while the rest of the console
  // was translated.
  static List<WebTableColumn> _pageColumnsOf(BuildContext context) => [
    WebTableColumn(label: context.l10n.pageLabel, flex: 2),
    WebTableColumn(label: context.l10n.visibilityLabel, width: 150),
  ];
  static List<WebTableColumn> _linkColumnsOf(BuildContext context) => [
    WebTableColumn(label: context.l10n.platform, width: 170),
    WebTableColumn(label: context.l10n.linkLabel, flex: 3),
    WebTableColumn(label: context.l10n.visibilityLabel, width: 110),
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        Text(l10n.content, style: AppType.heading(20)),
        const SizedBox(height: AppSpace.lg),
        WebTable(
          columns: _pageColumnsOf(context),
          rows: [
            for (final page in pages)
              WebTableRow.aligned(
                columns: _pageColumnsOf(context),
                onTap: () => onEditPage(page),
                cells: [
                  Row(
                    children: [
                      Icon(
                        _pageIcon(page.key),
                        color: AppColors.primary,
                        size: 19,
                      ),
                      const SizedBox(width: AppSpace.md),
                      Expanded(
                        child: Text(
                          page.titleEn.isEmpty ? page.key : page.titleEn,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  _StateLabel(
                    label: page.isPublished ? l10n.published : l10n.draft,
                    active: page.isPublished && !page.isEmpty,
                  ),
                ],
              ),
          ],
          emptyState: EmptyView(
            message: l10n.contentNotAvailableYet,
            icon: Icons.article_outlined,
          ),
        ),
        const SizedBox(height: AppSpace.xxl),
        Row(
          children: [
            Text(l10n.socialLinks, style: AppType.heading(20)),
            const Spacer(),
            FilledButton.icon(
              onPressed: onAddLink,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(l10n.addLink),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.lg),
        WebTable(
          columns: _linkColumnsOf(context),
          trailingWidth: 72,
          rows: [
            for (final link in links)
              WebTableRow.aligned(
                columns: _linkColumnsOf(context),
                onTap: () => onEditLink(link),
                trailingWidth: 72,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 19),
                      color: AppColors.dangerInk,
                      onPressed: () => onDeleteLink(link),
                    ),
                  ],
                ),
                cells: [
                  Row(
                    children: [
                      Icon(iconForPlatform(link.platform), size: 18),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          link.platform,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  Text(link.url, maxLines: 1, overflow: TextOverflow.ellipsis),
                  _StateLabel(label: l10n.active, active: link.isActive),
                ],
              ),
          ],
          emptyState: EmptyView(
            message: l10n.socialLinks,
            icon: Icons.link_outlined,
          ),
        ),
      ],
    );
  }

  IconData _pageIcon(String key) => switch (key) {
    'terms' => Icons.gavel_outlined,
    'privacy' => Icons.privacy_tip_outlined,
    _ => Icons.info_outline,
  };
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) => Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: active ? AppColors.successInk : AppColors.textMuted,
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
            color: attention ? AppColors.attentionBorder : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: AppColors.primary),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          trailing:
              trailing ??
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textFaint,
              ),
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

  /// Off by default. Re-asking is the disruptive choice — every store and
  /// rider is stopped at a wall of text until they sign again — so it has to
  /// be picked deliberately, not inherited from the last edit.
  bool _bumpVersion = false;
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
      await widget.repo.saveContent(
        AppContent(
          key: widget.page.key,
          titleEn: _titleEn.text.trim(),
          titleAr: _titleAr.text.trim().isEmpty ? null : _titleAr.text.trim(),
          bodyEn: _bodyEn.text.trim(),
          bodyAr: _bodyAr.text.trim().isEmpty ? null : _bodyAr.text.trim(),
          isPublished: _published,
          version: widget.page.version,
          requiresAcceptance: widget.page.requiresAcceptance,
          audience: widget.page.audience,
        ),
        bumpVersion: _bumpVersion,
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
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: Text(
          widget.page.titleEn.isEmpty ? widget.page.key : widget.page.titleEn,
        ),
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
              title: Text(
                l10n.published,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _published ? l10n.published : l10n.draft,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
            ),
          ),
          // Only the partner agreements are gated, so only they can trigger a
          // re-signature. Offering this on the About page would be noise.
          if (widget.page.requiresAcceptance) ...[
            const SizedBox(height: AppSpace.md),
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(
                  color: _bumpVersion ? AppColors.amberInk : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: SwitchListTile(
                value: _bumpVersion,
                onChanged: (v) => setState(() => _bumpVersion = v),
                title: Text(
                  l10n.requireReacceptance,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  _bumpVersion
                      ? l10n.requireReacceptanceOn(widget.page.version + 1)
                      : l10n.requireReacceptanceOff(widget.page.version),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
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
  late final _sort = TextEditingController(
    text: '${widget.link?.sortOrder ?? 0}',
  );
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
            title: Text(
              l10n.active,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            onPressed: _saving ? null : _save,
            child: _saving ? const ButtonSpinner() : Text(l10n.save),
          ),
        ],
      ),
    );
  }
}
