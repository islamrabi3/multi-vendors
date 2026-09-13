import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/web/web_shell_frame.dart';
import '../../../core/widgets/web/web_table.dart';
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
  List<BannerItem>? _ads;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // No `_loading = true` on a refresh — that was what blanked the whole
    // table to a spinner on every toggle and every delete, when only one
    // row had actually changed. The list stays on screen; only the first
    // load, with nothing to show yet, gets the skeleton.
    setState(() => _error = null);
    try {
      final ads = await _repo.fetchAll();
      if (!mounted) return;
      setState(() {
        _ads = ads;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _compose({BannerItem? ad}) async {
    final saved = await showAdaptiveSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AdComposer(repo: _repo, ad: ad),
    );
    if (saved != true || !mounted) return;
    _load();
    showSnack(
      context,
      ad == null ? context.l10n.adCreated : context.l10n.adUpdated,
    );
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
      if (mounted) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canManage = context.select(
      (AuthCubit c) => c.state.can('ads.manage'),
    );

    final webWide = AppBreakpoints.isWebWide(context);

    Widget body;
    if (_loading) {
      body = const _AdsSkeleton();
    } else if (_error != null) {
      body = FailureView(error: _error!, onRetry: _load);
    } else {
      final ads = _ads ?? const <BannerItem>[];
      if (ads.isEmpty) {
        body = EmptyView(message: l10n.noAdsYet, icon: Icons.campaign_outlined);
      } else {
        // Live ones first — that is the question an operator opens this
        // screen to answer — then grouped by surface, so placement still
        // reads as neighbourhoods even without a section header for each.
        final sorted = [...ads]
          ..sort((a, b) {
            final live = (b.isLive ? 1 : 0) - (a.isLive ? 1 : 0);
            if (live != 0) return live;
            final placement = a.placement.index.compareTo(b.placement.index);
            if (placement != 0) return placement;
            return b.sortOrder.compareTo(a.sortOrder);
          });

        Future<void> toggle(BannerItem ad) async {
          try {
            await _repo.setActive(ad.id, !ad.isActive);
          } catch (error) {
            if (context.mounted) showFailure(context, error);
          } finally {
            if (context.mounted) _load();
          }
        }

        body = RefreshIndicator(
          onRefresh: _load,
          child: webWide
              ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpace.xl),
                  child: _AdTable(
                    ads: sorted,
                    canManage: canManage,
                    onToggle: toggle,
                    onDelete: _delete,
                    onEdit: (ad) => _compose(ad: ad),
                  ),
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.lg,
                    AppSpace.lg,
                    // Room for the floating "New ad" button, plus the gesture
                    // bar on a phone with no physical home button.
                    96 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < sorted.length; i++)
                            _AdRow(
                              ad: sorted[i],
                              canManage: canManage,
                              last: i == sorted.length - 1,
                              onToggle: () => toggle(sorted[i]),
                              onDelete: () => _delete(sorted[i]),
                              onEdit: () => _compose(ad: sorted[i]),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      }
    }

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
        forStaff: true,
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

/// Shaped like a run of table/list rows, so the ads don't jump when they
/// land.
class _AdsSkeleton extends StatelessWidget {
  const _AdsSkeleton();

  @override
  Widget build(BuildContext context) => SkeletonTheme(
    child: SkeletonList(
      padding: const EdgeInsets.all(AppSpace.lg),
      itemCount: 5,
      separator: const SizedBox(height: AppSpace.sm),
      itemBuilder: (_) => const Skeleton.box(height: 60, radius: AppRadii.lg),
    ),
  );
}

String placementLabel(BuildContext context, AdPlacement placement) =>
    switch (placement) {
      AdPlacement.homeCarousel => context.l10n.placementHomeCarousel,
      AdPlacement.homeInline => context.l10n.placementHomeInline,
      AdPlacement.vendorTop => context.l10n.placementVendorTop,
      AdPlacement.cart => context.l10n.placementCart,
      AdPlacement.orderTracking => context.l10n.placementOrderTracking,
      AdPlacement.interstitial => context.l10n.placementInterstitial,
      AdPlacement.splash => context.l10n.placementSplash,
    };

/// Why an ad is or is not running, in one badge — the first thing an
/// operator looking at a row of ads needs.
({String label, Color fill, Color ink}) _adStatus(
  BuildContext context,
  BannerItem ad,
) {
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

class _AdStatus extends StatelessWidget {
  const _AdStatus({required this.ad});

  final BannerItem ad;

  @override
  Widget build(BuildContext context) {
    final status = _adStatus(context, ad);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SoftBadge(label: status.label, fill: status.fill, ink: status.ink),
    );
  }
}

/// The artwork thumbnail every row leads with — a table still has to let an
/// operator recognise the creative, just without the full-width hero an
/// image-first card gave it.
class _AdThumb extends StatelessWidget {
  const _AdThumb({required this.ad});

  final BannerItem ad;
  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: ad.poster == null
              ? Container(width: size, height: size, color: AppColors.ink)
              : AppNetworkImage(
                  url: ad.poster,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
        ),
        if (ad.isVideo)
          PositionedDirectional(
            bottom: 1,
            end: 1,
            child: Icon(
              Icons.play_circle_rounded,
              size: size * 0.4,
              color: Colors.white,
              shadows: const [Shadow(blurRadius: 3, color: Colors.black54)],
            ),
          ),
      ],
    );
  }
}

/// `Aug 12 - Sep 1`, or "always on" once neither end is set. Read straight
/// off the row rather than reformatted per caller, so the table cell and the
/// mobile subtitle can never disagree about what a blank date means.
///
/// A plain dash, not an arrow: the two dates are already in order (start,
/// then end), and an arrow glyph implies a direction that flips with the
/// reading direction while the dates it points between do not.
String _adSchedule(BuildContext context, BannerItem ad) {
  final language = Localizations.localeOf(context).languageCode;
  final parts = [
    if (ad.startsAt != null) DateFormat.MMMd(language).format(ad.startsAt!),
    if (ad.endsAt != null) DateFormat.MMMd(language).format(ad.endsAt!),
  ];
  if (parts.isEmpty) return context.l10n.adAlwaysOn;
  return parts.join(' - ');
}

/// Web/wide: ads as a real table.
///
/// A stack of 16:9 artwork cards was the layout when the whole point of a row
/// was to look at the creative. It stops being that the moment the question
/// is "what's running and how is it doing" — a placement, a status, three
/// numbers and a date range are six facts an operator re-finds in a
/// different spot per card; columns put every one of them where the eye
/// already is.
class _AdTable extends StatelessWidget {
  const _AdTable({
    required this.ads,
    required this.canManage,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  final List<BannerItem> ads;
  final bool canManage;
  final ValueChanged<BannerItem> onToggle;
  final ValueChanged<BannerItem> onDelete;
  final ValueChanged<BannerItem> onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final columns = [
      WebTableColumn(label: l10n.adManager, flex: 3),
      WebTableColumn(label: l10n.adPlacement, flex: 2),
      WebTableColumn(label: l10n.adPerformanceLabel, width: 170),
      WebTableColumn(label: l10n.scheduleLabel, width: 130),
      WebTableColumn(label: l10n.statusLabel, width: 104),
    ];

    return WebTable(
      columns: columns,
      trailingWidth: 132,
      rows: [
        for (final ad in ads)
          WebTableRow.aligned(
            columns: columns,
            trailingWidth: 132,
            onTap: canManage ? () => onEdit(ad) : null,
            cells: [
              Row(
                children: [
                  _AdThumb(ad: ad),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ad.title ?? ad.advertiser ?? '—',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (ad.advertiser != null && ad.title != null)
                          Text(
                            ad.advertiser!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              Text(
                placementLabel(context, ad.placement),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                l10n.adPerformanceCompact(
                  _compact(ad.impressions),
                  _compact(ad.clicks),
                  (ad.clickRate * 100).toStringAsFixed(1),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.mono(12, color: AppColors.textSecondary),
              ),
              Text(
                _adSchedule(context, ad),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                ),
              ),
              _AdStatus(ad: ad),
            ],
            trailing: canManage
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: 44,
                        child: Transform.scale(
                          scale: 0.78,
                          child: Switch(
                            value: ad.isActive,
                            // An ended campaign cannot be switched back on —
                            // its end date has passed, and toggling would
                            // look like it worked while the server kept it
                            // hidden.
                            onChanged: ad.hasEnded ? null : (_) => onToggle(ad),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.edit,
                        onPressed: () => onEdit(ad),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: AppColors.textMuted,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        tooltip: l10n.delete,
                        onPressed: () => onDelete(ad),
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        color: AppColors.dangerInk,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
      ],
    );
  }
}

/// Mobile: one row per ad, thumbnail leading, the same facts as the table
/// condensed into a title and a subtitle line.
class _AdRow extends StatelessWidget {
  const _AdRow({
    required this.ad,
    required this.canManage,
    required this.last,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  final BannerItem ad;
  final bool canManage;
  final bool last;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final dim = !ad.isLive;
    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      child: Opacity(
        opacity: dim ? 0.72 : 1,
        child: ListTile(
          onTap: canManage ? onEdit : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          leading: _AdThumb(ad: ad),
          title: Text(
            ad.title ?? ad.advertiser ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Text(
            [
              placementLabel(context, ad.placement),
              l10n.adPerformanceCompact(
                _compact(ad.impressions),
                _compact(ad.clicks),
                (ad.clickRate * 100).toStringAsFixed(1),
              ),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          trailing: canManage
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: ad.isActive,
                      onChanged: ad.hasEnded ? null : (_) => onToggle(),
                    ),
                    IconButton(
                      tooltip: l10n.edit,
                      onPressed: onEdit,
                      icon: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.delete,
                      onPressed: onDelete,
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: AppColors.dangerInk,
                        size: 20,
                      ),
                    ),
                  ],
                )
              : _AdStatus(ad: ad),
        ),
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
  const _AdComposer({required this.repo, this.ad});

  final OffersRepository repo;

  /// Set to edit an existing ad; null composes a new one.
  final BannerItem? ad;

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

  /// Full-screen placements only; `null` means "not chosen yet", resolved to
  /// the placement's default at save.
  String? _frequency;

  bool get _isFullScreen =>
      _placement == AdPlacement.splash ||
      _placement == AdPlacement.interstitial;

  /// A splash ad is expected at every launch; an interstitial mid-session is
  /// easier to overdo, so it defaults to once a day.
  String get _effectiveFrequency =>
      _frequency ??
      (_placement == AdPlacement.splash ? 'every_session' : 'daily');
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _imageUrl;
  bool _uploading = false;
  bool _saving = false;

  /// Image ad or video ad. A video ad's image is only its cover.
  bool _isVideo = false;
  String? _videoName;
  bool _uploadingVideo = false;

  /// Storage's default per-file cap on the free tier.
  static const _maxVideoBytes = 50 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final ad = widget.ad;
    if (ad == null) return;
    _title.text = ad.title ?? '';
    _subtitle.text = ad.subtitle ?? '';
    _code.text = ad.code ?? '';
    _linkUrl.text = ad.linkUrl ?? '';
    _advertiser.text = ad.advertiser ?? '';
    _placement = ad.placement;
    _audience = ad.audience;
    _frequency = ad.frequency;
    _startsAt = ad.startsAt;
    _endsAt = ad.endsAt;
    _isVideo = ad.isVideo;
    _videoUrl.text = ad.videoUrl ?? '';
    // A cover-less video ad stores the video URL as its image; that is not a
    // picture the artwork box can show.
    _imageUrl = ad.poster;
  }

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

  /// iPhones record HEVC by default. iOS plays it; most Android phones and
  /// Chrome do not, so the ad would silently never appear for them. The codec
  /// tag sits in the file's `stsd` box as plain ASCII.
  static bool _isHevc(List<int> bytes) {
    const tags = [
      [0x68, 0x76, 0x63, 0x31], // hvc1
      [0x68, 0x65, 0x76, 0x31], // hev1
    ];
    for (var i = 0; i + 4 <= bytes.length; i++) {
      for (final tag in tags) {
        if (bytes[i] == tag[0] &&
            bytes[i + 1] == tag[1] &&
            bytes[i + 2] == tag[2] &&
            bytes[i + 3] == tag[3]) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _pickVideo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null || !mounted) return;
    if (bytes.length > _maxVideoBytes) {
      showSnack(
        context,
        context.l10n.videoTooLarge(_maxVideoBytes ~/ (1024 * 1024)),
        error: true,
      );
      return;
    }
    if (_isHevc(bytes)) {
      showSnack(context, context.l10n.videoHevcUnsupported, error: true);
      return;
    }
    setState(() => _uploadingVideo = true);
    try {
      final url = await AdminRepository().uploadAdVideo(bytes, file.name);
      if (!mounted) return;
      setState(() {
        _videoUrl.text = url;
        _videoName = file.name;
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
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
    final videoUrl = _videoUrl.text.trim();
    if (_isVideo && videoUrl.isEmpty) {
      showSnack(context, context.l10n.videoRequired, error: true);
      return;
    }
    if (!_isVideo && _imageUrl == null) {
      showSnack(context, context.l10n.artworkRequired, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final existing = widget.ad;
      if (existing == null) {
        await widget.repo.create(
          // The column is required; a video ad with no cover stores the video
          // URL there, and `BannerItem.poster` knows not to draw it.
          imageUrl: _isVideo ? (_imageUrl ?? videoUrl) : _imageUrl!,
          type: _code.text.trim().isNotEmpty
              ? BannerType.coupon
              // A store ad has no field here; editing must not demote it.
              : (widget.ad?.type == BannerType.vendor
                    ? BannerType.vendor
                    : BannerType.event),
          placement: _placement,
          title: _title.text,
          subtitle: _subtitle.text,
          code: _code.text,
          videoUrl: _isVideo ? videoUrl : null,
          linkUrl: _linkUrl.text,
          advertiser: _advertiser.text,
          audience: _audience,
          startsAt: _startsAt,
          endsAt: _endsAt,
          frequency: _isFullScreen ? _effectiveFrequency : 'once',
        );
      } else {
        await widget.repo.edit(
          existing.id,
          // The column is required; a video ad with no cover stores the video
          // URL there, and `BannerItem.poster` knows not to draw it.
          imageUrl: _isVideo ? (_imageUrl ?? videoUrl) : _imageUrl!,
          type: _code.text.trim().isNotEmpty
              ? BannerType.coupon
              // A store ad has no field here; editing must not demote it.
              : (widget.ad?.type == BannerType.vendor
                    ? BannerType.vendor
                    : BannerType.event),
          placement: _placement,
          title: _title.text,
          subtitle: _subtitle.text,
          code: _code.text,
          videoUrl: _isVideo ? videoUrl : null,
          linkUrl: _linkUrl.text,
          advertiser: _advertiser.text,
          audience: _audience,
          startsAt: _startsAt,
          endsAt: _endsAt,
          frequency: _isFullScreen ? _effectiveFrequency : 'once',
        );
      }
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
            Text(
              widget.ad == null ? l10n.newAd : l10n.editAd,
              style: AppType.heading(18),
            ),
            const SizedBox(height: AppSpace.md),

            SegmentedButton<bool>(
              expandedInsets: EdgeInsets.zero,
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(l10n.adMediaImage),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.videocam_outlined),
                  label: Text(l10n.adVideo),
                ),
              ],
              selected: {_isVideo},
              onSelectionChanged: (value) =>
                  setState(() => _isVideo = value.first),
            ),
            const SizedBox(height: AppSpace.md),

            if (_isVideo) ...[
              _VideoPickerTile(
                uploading: _uploadingVideo,
                fileName: _videoName,
                hasVideo: _videoUrl.text.trim().isNotEmpty,
                onPick: _uploadingVideo ? null : _pickVideo,
                onClear: () => setState(() {
                  _videoUrl.clear();
                  _videoName = null;
                }),
              ),
              const SizedBox(height: AppSpace.sm),
              TextField(
                controller: _videoUrl,
                onChanged: (_) => setState(() => _videoName = null),
                decoration: InputDecoration(
                  labelText: l10n.adVideoUrl,
                  helperText: l10n.adVideoUrlHelper,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                l10n.videoCoverOptional,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
            ],

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
            if (_isFullScreen) ...[
              const SizedBox(height: AppSpace.sm),
              DropdownButtonFormField<String>(
                key: ValueKey(_placement),
                initialValue: _effectiveFrequency,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.adFrequency),
                items: [
                  DropdownMenuItem(
                    value: 'every_session',
                    child: Text(l10n.frequencyEverySession),
                  ),
                  DropdownMenuItem(
                    value: 'daily',
                    child: Text(l10n.frequencyDaily),
                  ),
                  DropdownMenuItem(
                    value: 'once',
                    child: Text(l10n.frequencyOnce),
                  ),
                ],
                onChanged: (value) => setState(() => _frequency = value),
              ),
            ],
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
                  ? const ButtonSpinner()
                  : Text(widget.ad == null ? l10n.save : l10n.saveChanges),
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
              : DateFormat.yMMMd(
                  Localizations.localeOf(context).languageCode,
                ).format(value!),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
}

class _VideoPickerTile extends StatelessWidget {
  const _VideoPickerTile({
    required this.uploading,
    required this.fileName,
    required this.hasVideo,
    required this.onPick,
    required this.onClear,
  });

  final bool uploading;
  final String? fileName;
  final bool hasVideo;
  final VoidCallback? onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: hasVideo ? AppColors.successFill : AppColors.neutralFill,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
              child: uploading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      hasVideo
                          ? Icons.play_arrow_rounded
                          : Icons.video_call_outlined,
                      color: Colors.white,
                    ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    uploading
                        ? l10n.uploadingVideo
                        : hasVideo
                        ? (fileName ?? l10n.videoAdded)
                        : l10n.uploadVideo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasVideo ? l10n.replaceVideo : l10n.videoFormatsHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            if (hasVideo && !uploading)
              IconButton(
                onPressed: onClear,
                icon: const Icon(Icons.close_rounded),
                color: AppColors.textMuted,
              ),
          ],
        ),
      ),
    );
  }
}
