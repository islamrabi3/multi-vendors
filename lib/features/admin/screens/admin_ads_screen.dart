import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../app/tokens.dart';
import '../../../core/models/banner_item.dart';
import '../../../core/repositories/admin_repository.dart';
import '../../../core/repositories/offers_repository.dart';
import '../../../core/utils/l10n_extension.dart';
import '../../../core/widgets/app_dialogs.dart';
import '../../../core/widgets/common.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../auth/auth_cubit.dart';
import 'admin_manage_screen.dart' show adminManageWebSections;
import '../../../core/widgets/web/adaptive_sheet.dart';

/// Ad space: what is running, where, and how it is doing.
///
/// The banners table was one flat list that appeared in a single carousel, was
/// either on or off, and reported nothing — decoration rather than inventory.
/// This is the same rows with a placement, a schedule, an audience and
/// counters, which is what makes the space sellable.
class AdminAdsScreen extends StatefulWidget {
  const AdminAdsScreen({super.key, this.embedded = false});

  /// True when a web sidebar is already drawing the shell around this screen
  /// (`_AdminWebShell`) — skips this widget's own [WebPageChrome]/[Scaffold]
  /// and returns just the content.
  final bool embedded;

  @override
  State<AdminAdsScreen> createState() => _AdminAdsScreenState();
}

class _AdminAdsScreenState extends State<AdminAdsScreen> {
  final _repo = OffersRepository();
  late Future<List<BannerItem>> _future = _repo.fetchAll();

  // Block body, not an arrow. `setState(() => _future = ...)` returns the
  // assigned value from the closure, and a closure that returns a Future makes
  // setState throw -- so the rebuild never happened and the list stayed on
  // screen until the page was reopened.
  //
  // It also returns the future, so pull-to-refresh can hold its spinner until
  // the fetch finishes instead of ending on the same frame it started.
  Future<void> _reload() {
    final future = _repo.fetchAll();
    setState(() {
      _future = future;
    });
    return future;
  }

  Future<void> _compose() async {
    final created = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdComposer(repo: _repo),
    );
    if (created != true || !mounted) return;
    _reload();
    showSnack(context, context.l10n.adCreated);
  }

  Future<void> _delete(BannerItem ad) async {
    final confirmed = await AppDialogs.showConfirmDialog(
      context: context,
      title: ad.title ?? context.l10n.adManager,
      message: context.l10n.deleteAdConfirm,
      confirmText: context.l10n.delete,
      cancelText: context.l10n.cancel,
    );
    if (confirmed != true) return;
    try {
      await _repo.delete(ad.id);
      if (!mounted) return;
      showSnack(context, context.l10n.adDeleted);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canManage = context.select(
      (AuthCubit c) => c.state.can('ads.manage'),
    );

    final webWide = AppBreakpoints.isWebWide(context);

    final body = FutureBuilder<List<BannerItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingView();
        }
        if (snap.hasError) {
          return FailureView(error: snap.error!, onRetry: _reload);
        }
        final ads = snap.data ?? const <BannerItem>[];
        if (ads.isEmpty) {
          return EmptyView(
            message: l10n.noAdsYet,
            icon: Icons.campaign_outlined,
          );
        }
        // Grouped by surface: an operator thinks in slots, not in rows.
        final byPlacement = <AdPlacement, List<BannerItem>>{};
        for (final ad in ads) {
          byPlacement.putIfAbsent(ad.placement, () => []).add(ad);
        }
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              webWide ? 0 : AppSpace.lg,
              webWide ? 0 : AppSpace.lg,
              webWide ? 0 : AppSpace.lg,
              // Room for the floating "New ad" button on mobile; on web that
              // button sits in the header row instead, so the list can run to
              // the bottom of the pane.
              webWide ? AppSpace.xl : 96,
            ),
            children: [
              for (final placement in AdPlacement.values)
                if (byPlacement[placement] case final slotAds?) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpace.xs,
                      AppSpace.md,
                      AppSpace.xs,
                      AppSpace.sm,
                    ),
                    child: Text(
                      placementLabel(context, placement).toUpperCase(),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppColors.textFaint,
                      ),
                    ),
                  ),
                  // A placement's ads sit side by side on a laptop: a
                  // column of 96px-tall artwork cards down a 1200px window
                  // is most of the screen doing nothing.
                  _AdGroup(
                    ads: slotAds,
                    canManage: canManage,
                    onToggle: (ad) async {
                      try {
                        await _repo.setActive(ad.id, !ad.isActive);
                      } catch (error) {
                        if (context.mounted) showFailure(context, error);
                      } finally {
                        if (context.mounted) _reload();
                      }
                    },
                    onDelete: _delete,
                  ),
                ],
            ],
          ),
        );
      },
    );

    // A floating action button belongs to a Scaffold and reads as a phone
    // affordance on a desktop pane; the same action becomes an ordinary
    // button at the top of the content instead.
    Widget webContent() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canManage) ...[
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton.icon(
              onPressed: _compose,
              icon: const Icon(Icons.campaign_outlined, size: 18),
              label: Text(l10n.newAd),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
        ],
        Expanded(child: body),
      ],
    );

    if (widget.embedded) {
      return Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: webContent(),
      );
    }

    if (webWide) {
      return WebPageChrome(
        activeId: 'manage:/admin-app/ads',
        sections: adminManageWebSections(context),
        pageTitle: l10n.adManager,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: webContent(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: Text(l10n.adManager)),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: _compose,
              icon: const Icon(Icons.campaign_outlined),
              label: Text(l10n.newAd),
            )
          : null,
      body: body,
    );
  }
}

/// One placement's ads, in as many columns as the window allows.
class _AdGroup extends StatelessWidget {
  const _AdGroup({
    required this.ads,
    required this.canManage,
    required this.onToggle,
    required this.onDelete,
  });

  final List<BannerItem> ads;
  final bool canManage;
  final ValueChanged<BannerItem> onToggle;
  final ValueChanged<BannerItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 360).floor().clamp(1, 3);
        const spacing = AppSpace.sm;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final ad in ads)
              SizedBox(
                width: columns == 1 ? constraints.maxWidth : width,
                child: _AdCard(
                  ad: ad,
                  canManage: canManage,
                  onToggle: () => onToggle(ad),
                  onDelete: () => onDelete(ad),
                ),
              ),
          ],
        );
      },
    );
  }
}

String placementLabel(BuildContext context, AdPlacement placement) =>
    switch (placement) {
      AdPlacement.homeCarousel => context.l10n.placementHomeCarousel,
      AdPlacement.homeInline => context.l10n.placementHomeInline,
      AdPlacement.vendorTop => context.l10n.placementVendorTop,
      AdPlacement.cart => context.l10n.placementCart,
      AdPlacement.orderTracking => context.l10n.placementOrderTracking,
      AdPlacement.interstitial => context.l10n.placementInterstitial,
    };

class _AdCard extends StatelessWidget {
  const _AdCard({
    required this.ad,
    required this.canManage,
    required this.onToggle,
    required this.onDelete,
  });

  final BannerItem ad;
  final bool canManage;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  /// Why it is or is not running, in one badge. An operator looking at a list
  /// of ads needs that before anything else.
  ({String label, Color fill, Color ink}) _status(BuildContext context) {
    final l10n = context.l10n;
    if (ad.hasEnded) {
      return (
        label: l10n.adEnded,
        fill: AppColors.neutralFill,
        ink: AppColors.textMuted,
      );
    }
    if (ad.isScheduled) {
      return (
        label: l10n.couponScheduled,
        fill: AppColors.amberFill,
        ink: AppColors.amberInk,
      );
    }
    if (!ad.isActive) {
      return (
        label: l10n.statusDraft,
        fill: AppColors.neutralFill,
        ink: AppColors.textMuted,
      );
    }
    return (
      label: l10n.adLive,
      fill: AppColors.successFill,
      ink: AppColors.successInk,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final status = _status(context);
    final dates = [
      if (ad.startsAt != null) DateFormat.yMMMd().format(ad.startsAt!),
      if (ad.endsAt != null) DateFormat.yMMMd().format(ad.endsAt!),
    ].join(' → ');

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 16:9 rather than a fixed 96px strip. Ad artwork is designed to a
          // ratio, and letterboxing it into a band that changes shape with
          // the column width made every creative look wrong in the one place
          // the operator is meant to be judging it.
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppNetworkImage(url: ad.posterUrl ?? ad.imageUrl),
                if (ad.isVideo)
                  const PositionedDirectional(
                    top: 8,
                    start: 8,
                    child: Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                PositionedDirectional(
                  top: 8,
                  end: 8,
                  child: SoftBadge(
                    label: status.label,
                    fill: status.fill,
                    ink: status.ink,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ad.title ?? ad.advertiser ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                // The advertiser is who is being billed, so it earns its own
                // line rather than only appearing when there is no title.
                if (ad.advertiser != null && ad.title != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    ad.advertiser!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.md),
                // Views, taps and tap rate are what an ad manager exists to
                // report. They used to be one 11.5px muted sentence under the
                // title — present, but not readable at a glance, which is the
                // only way anybody actually reads them.
                Row(
                  children: [
                    _AdMetric(
                      value: _compact(ad.impressions),
                      label: l10n.adViews,
                    ),
                    _AdMetric(value: _compact(ad.clicks), label: l10n.adTaps),
                    _AdMetric(
                      value: '${(ad.clickRate * 100).toStringAsFixed(1)}%',
                      label: l10n.adTapRate,
                      // A click-through rate is the number worth comparing
                      // between creatives, so it is the one that is tinted.
                      tone: ad.clicks > 0 ? AppColors.successInk : null,
                    ),
                  ],
                ),
                if (dates.isNotEmpty) ...[
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.textFaint,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          dates,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (canManage) ...[
            const Divider(height: 1, color: AppColors.borderSoft),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.sm,
                vertical: 2,
              ),
              child: Row(
                children: [
                  // Scaled down: a full-size Switch is a phone control, and
                  // at this size it was the loudest thing on a card whose
                  // point is the artwork.
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: ad.isActive,
                      // An ended campaign cannot be switched back on — its
                      // end date has passed, and toggling would look like it
                      // worked while the server kept it hidden.
                      onChanged: ad.hasEnded ? null : (_) => onToggle(),
                    ),
                  ),
                  Text(
                    ad.isActive ? l10n.active : l10n.pausedLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ad.isActive
                          ? AppColors.successInk
                          : AppColors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: l10n.delete,
                    onPressed: onDelete,
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 19,
                      color: AppColors.dangerInk,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One headline figure in an ad card.
class _AdMetric extends StatelessWidget {
  const _AdMetric({required this.value, required this.label, this.tone});

  final String value;
  final String label;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.mono(
              15,
              weight: FontWeight.w800,
              color: tone ?? AppColors.ink,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              color: AppColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

/// 12400 -> 12.4k. A view count in the tens of thousands should not push the
/// two figures beside it off the card.
String _compact(int value) {
  if (value < 1000) return '$value';
  if (value < 1000000) {
    final k = value / 1000;
    return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
  }
  final m = value / 1000000;
  return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
}

/// Create an ad: artwork, where it goes, when it runs, who sees it.
class _AdComposer extends StatefulWidget {
  const _AdComposer({required this.repo});

  final OffersRepository repo;

  @override
  State<_AdComposer> createState() => _AdComposerState();
}

class _AdComposerState extends State<_AdComposer> {
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _code = TextEditingController();
  final _videoUrl = TextEditingController();
  final _linkUrl = TextEditingController();
  final _advertiser = TextEditingController();

  AdPlacement _placement = AdPlacement.homeCarousel;
  String _audience = 'all';
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _subtitle.dispose();
    _code.dispose();
    _videoUrl.dispose();
    _linkUrl.dispose();
    _advertiser.dispose();
    super.dispose();
  }

  Future<void> _pickArtwork() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final url = await AdminRepository().uploadAdImage(
        await picked.readAsBytes(),
        picked.name,
      );
      if (mounted) setState(() => _imageUrl = url);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final initial = (start ? _startsAt : _endsAt) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      // End of day for the end date: a campaign ending "today" should run all
      // of today, not stop the instant it was picked.
      if (start) {
        _startsAt = picked;
      } else {
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
  }

  Future<void> _save() async {
    // Artwork is required even for video: it is the poster, and the fallback
    // wherever autoplay is refused.
    if (_imageUrl == null) {
      showSnack(context, context.l10n.artworkRequired, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repo.create(
        imageUrl: _imageUrl!,
        type: _code.text.trim().isNotEmpty
            ? BannerType.coupon
            : BannerType.event,
        placement: _placement,
        title: _title.text,
        subtitle: _subtitle.text,
        code: _code.text,
        videoUrl: _videoUrl.text,
        linkUrl: _linkUrl.text,
        advertiser: _advertiser.text,
        audience: _audience,
        startsAt: _startsAt,
        endsAt: _endsAt,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      showFailure(context, error);
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
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(l10n.newAd, style: AppType.heading(18)),
            const SizedBox(height: AppSpace.md),

            // Artwork
            AspectRatio(
              aspectRatio: 16 / 7,
              child: InkWell(
                onTap: _uploading ? null : _pickArtwork,
                borderRadius: BorderRadius.circular(AppRadii.lg),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.neutralFill,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: _uploading
                      ? const Center(child: CircularProgressIndicator())
                      : _imageUrl == null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 28,
                                color: AppColors.textMuted,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                l10n.uploadArtwork,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : AppNetworkImage(url: _imageUrl, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: AppSpace.md),

            DropdownButtonFormField<AdPlacement>(
              initialValue: _placement,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.adPlacement),
              items: [
                for (final placement in AdPlacement.values)
                  DropdownMenuItem(
                    value: placement,
                    child: Text(placementLabel(context, placement)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _placement = value ?? _placement),
            ),
            const SizedBox(height: AppSpace.sm),
            TextField(
              controller: _title,
              decoration: InputDecoration(labelText: l10n.announcementTitle),
            ),
            TextField(
              controller: _subtitle,
              decoration: InputDecoration(labelText: l10n.subtitleOptional),
            ),
            TextField(
              controller: _advertiser,
              decoration: InputDecoration(labelText: l10n.advertiser),
            ),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: l10n.couponCode),
            ),
            TextField(
              controller: _videoUrl,
              decoration: InputDecoration(
                labelText: l10n.adVideoUrl,
                helperText: l10n.adVideo,
              ),
            ),
            TextField(
              controller: _linkUrl,
              decoration: InputDecoration(labelText: l10n.adLinkUrl),
            ),
            const SizedBox(height: AppSpace.md),

            DropdownButtonFormField<String>(
              initialValue: _audience,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.adAudience),
              items: [
                DropdownMenuItem(value: 'all', child: Text(l10n.audienceAll)),
                DropdownMenuItem(
                  value: 'new_customers',
                  child: Text(l10n.audienceNewCustomers),
                ),
                DropdownMenuItem(
                  value: 'returning_customers',
                  child: Text(l10n.audienceReturning),
                ),
              ],
              onChanged: (value) => setState(() => _audience = value ?? 'all'),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Expanded(
                  child: _DateField(
                    label: l10n.adStarts,
                    value: _startsAt,
                    onTap: () => _pickDate(start: true),
                    onClear: () => setState(() => _startsAt = null),
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: _DateField(
                    label: l10n.adEnds,
                    value: _endsAt,
                    onTap: () => _pickDate(start: false),
                    onClear: () => setState(() => _endsAt = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.lg),
            FilledButton(
              onPressed: _saving || _uploading ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}

/// A date the admin may set or leave empty — unset start means live now,
/// unset end means until switched off.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: value == null
              ? const Icon(Icons.event_outlined, size: 18)
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: onClear,
                  tooltip: context.l10n.clearDate,
                ),
        ),
        child: Text(
          value == null
              ? context.l10n.notSet
              : DateFormat.yMMMd().format(value!),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}
