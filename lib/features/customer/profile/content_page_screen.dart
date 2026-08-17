import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/tokens.dart';
import '../../../core/models/app_content.dart';
import '../../../core/repositories/app_content_repository.dart';
import '../../../core/widgets/common.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

/// Renders whatever the admin has published under [contentKey].
///
/// Deliberately one screen for terms, privacy and about: they differ only in
/// which row the customer tapped, and the about page's extra social footer is
/// driven by data, not by a second widget tree.
class ContentPageScreen extends StatefulWidget {
  const ContentPageScreen({
    super.key,
    required this.contentKey,
    this.fallbackTitle,
    this.showLinks = false,
  });

  final String contentKey;

  /// Shown in the app bar until the body loads, so the screen never opens
  /// with an empty title.
  final String? fallbackTitle;

  /// About shows the social footer; the legal pages do not.
  final bool showLinks;

  @override
  State<ContentPageScreen> createState() => _ContentPageScreenState();
}

class _ContentPageScreenState extends State<ContentPageScreen> {
  final _repo = AppContentRepository();
  late Future<({AppContent? content, List<AppLink> links})> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<({AppContent? content, List<AppLink> links})> _load() async {
    final content = await _repo.fetchContent(widget.contentKey);
    // A failed link fetch must not blank the page it decorates.
    List<AppLink> links = const [];
    if (widget.showLinks) {
      try {
        links = await _repo.fetchLinks();
      } catch (_) {}
    }
    return (content: content, links: links);
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      showSnack(context, context.l10n.couldNotOpenLink, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: FutureBuilder<({AppContent? content, List<AppLink> links})>(
        future: _future,
        builder: (context, snap) {
          final content = snap.data?.content;
          final title = content?.title(language).trim();
          return CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: Text(
                  title == null || title.isEmpty
                      ? (widget.fallbackTitle ?? '')
                      : title,
                ),
                // Someone reading the terms or the privacy policy with a
                // question about them had no way to ask one without leaving
                // the page to hunt for the support entry point buried in
                // Profile. Signed out, this bounces to `/login` like any
                // other gated page — a real conversation needs an account —
                // but it is one visible tap away instead of a dead end.
                actions: [
                  IconButton(
                    tooltip: context.l10n.supportChat,
                    onPressed: () => context.push('/support'),
                    icon: const Icon(Icons.support_agent_rounded),
                  ),
                ],
              ),
              if (snap.connectionState != ConnectionState.done)
                const SliverFillRemaining(child: LoadingView())
              else if (snap.hasError)
                SliverFillRemaining(
                  child: FailureView(error: snap.error!, onRetry: _reload),
                )
              else if (content == null || content.isEmpty)
                SliverFillRemaining(
                  child: EmptyView(
                    message: context.l10n.contentNotAvailableYet,
                    icon: Icons.article_outlined,
                  ),
                )
              else
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppSpace.gutter,
                      AppSpace.sm,
                      AppSpace.gutter,
                      AppSpace.xxl + MediaQuery.paddingOf(context).bottom,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          content.body(language),
                          style: const TextStyle(
                            fontSize: 14.5,
                            height: 1.65,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (widget.showLinks &&
                            snap.data!.links.isNotEmpty) ...[
                          const SizedBox(height: AppSpace.xxl),
                          const Divider(color: AppColors.borderSoft),
                          const SizedBox(height: AppSpace.lg),
                          Text(
                            context.l10n.followUs,
                            style: AppType.heading(15),
                          ),
                          const SizedBox(height: AppSpace.md),
                          Wrap(
                            spacing: AppSpace.sm,
                            runSpacing: AppSpace.sm,
                            children: [
                              for (final link in snap.data!.links)
                                _LinkChip(
                                  link: link,
                                  onTap: () => _open(link.url),
                                ),
                            ],
                          ),
                        ],
                        if (content.updatedAt != null) ...[
                          const SizedBox(height: AppSpace.xl),
                          Text(
                            '${context.l10n.lastUpdated}: '
                            '${content.updatedAt!.toLocal().toString().split(' ').first}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppColors.textFaint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Icon per known platform; anything the admin invents still renders.
IconData iconForPlatform(String platform) => switch (platform) {
  'facebook' => Icons.facebook,
  'instagram' => Icons.camera_alt_outlined,
  'x' || 'twitter' => Icons.alternate_email,
  'tiktok' => Icons.music_note_outlined,
  'youtube' => Icons.play_circle_outline,
  'whatsapp' => Icons.chat_outlined,
  'linkedin' => Icons.work_outline,
  'email' => Icons.mail_outline,
  'phone' => Icons.phone_outlined,
  _ => Icons.link,
};

class _LinkChip extends StatelessWidget {
  const _LinkChip({required this.link, required this.onTap});

  final AppLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md - 2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconForPlatform(link.platform),
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                // The platform name is the label; the URL is the payload.
                link.platform.isEmpty
                    ? link.url
                    : link.platform[0].toUpperCase() +
                          link.platform.substring(1),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
