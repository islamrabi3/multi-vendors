import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../app/tokens.dart';
import '../models/banner_item.dart';
import '../repositories/offers_repository.dart';
import 'common.dart';

/// An ad surface.
///
/// Drop one wherever a placement exists and it fills itself: it asks the
/// server what is live for that surface right now, renders the first ad,
/// counts the view, and counts the tap. Empty when there is nothing scheduled,
/// so a placement costs nothing until somebody buys it.
///
/// Deliberately silent on failure. An ad that cannot load must never show an
/// error where a customer expects content, and must never block the screen it
/// sits on.
class AdSlot extends StatefulWidget {
  const AdSlot({
    super.key,
    required this.placement,
    this.height = 150,
    this.margin = const EdgeInsets.fromLTRB(22, 8, 22, 8),
  });

  final AdPlacement placement;
  final double height;
  final EdgeInsets margin;

  @override
  State<AdSlot> createState() => _AdSlotState();
}

class _AdSlotState extends State<AdSlot> {
  final _repo = OffersRepository();
  late Future<List<BannerItem>> _future = _load();

  /// Counted once per ad per mount. Rebuilds are not views.
  final _counted = <String>{};

  @override
  void initState() {
    super.initState();
    // Without this the slot keeps rendering an ad that was deleted a moment
    // ago, until something happens to remount it — which for a slot on the
    // home screen means closing and reopening the app.
    adsRevision.addListener(_onAdsChanged);
  }

  @override
  void dispose() {
    adsRevision.removeListener(_onAdsChanged);
    super.dispose();
  }

  void _onAdsChanged() {
    if (!mounted) return;
    setState(() {
      _future = _load();
      // A refetched slot may show a different ad, and that is a new view.
      _counted.clear();
    });
  }

  Future<List<BannerItem>> _load() async {
    // The audience rule needs to know whether this is somebody's first order,
    // and the server decides that too — a client claiming to be new would
    // otherwise collect every welcome offer.
    final isNew = await _repo.isNewCustomer().catchError((_) => false);
    return _repo.activeAds(widget.placement, isNewCustomer: isNew);
  }

  void _countImpression(BannerItem ad) {
    if (!_counted.add(ad.id)) return;
    _repo.recordEvent(ad.id, click: false);
  }

  Future<void> _onTap(BannerItem ad) async {
    _repo.recordEvent(ad.id, click: true);

    // Order matters: a store ad goes to the store even if it also carries a
    // code, because that is the more specific destination.
    if (ad.vendorId != null && ad.vendorId!.isNotEmpty) {
      if (mounted) context.push('/vendors/${ad.vendorId}');
      return;
    }
    if (ad.linkUrl != null && ad.linkUrl!.isNotEmpty) {
      final uri = Uri.tryParse(ad.linkUrl!);
      if (uri == null) return;
      // An in-app path stays in the app; anything else is a real link.
      if (!uri.hasScheme) {
        if (mounted) context.push(ad.linkUrl!);
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (ad.code != null && ad.code!.isNotEmpty && mounted) {
      // Nothing to open — the code is the point, so put it where it is used.
      context.push('/cart');
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BannerItem>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done ||
            snap.hasError ||
            (snap.data?.isEmpty ?? true)) {
          return const SizedBox.shrink();
        }
        final ad = snap.data!.first;
        // Fired from the build rather than a scroll observer: this widget is
        // only built when its placement is on screen.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _countImpression(ad),
        );

        return Padding(
          padding: widget.margin,
          child: SizedBox(
            height: widget.height,
            child: Material(
              borderRadius: BorderRadius.circular(AppRadii.xl),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _onTap(ad),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (ad.isVideo)
                      _AdVideo(
                        url: ad.videoUrl!,
                        poster: ad.posterUrl ?? ad.imageUrl,
                      )
                    else
                      AppNetworkImage(url: ad.imageUrl, fit: BoxFit.cover),
                    if (ad.title != null || ad.subtitle != null)
                      _AdCaption(ad: ad),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Text over the artwork, on a scrim so it stays readable whatever the ad
/// looks like underneath.
class _AdCaption extends StatelessWidget {
  const _AdCaption({required this.ad});

  final BannerItem ad;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: AlignmentDirectional.bottomStart,
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (ad.title != null)
            Text(
              ad.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          if (ad.subtitle != null)
            Text(
              ad.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12.5,
              ),
            ),
        ],
      ),
    );
  }
}

/// A video ad: muted, looping, no controls.
///
/// Sound would be hostile in a food app somebody is scrolling in public, and
/// controls invite a customer to manage a video they did not ask for. The
/// poster covers the first frame so the slot never flashes black.
class _AdVideo extends StatefulWidget {
  const _AdVideo({required this.url, required this.poster});

  final String url;
  final String poster;

  @override
  State<_AdVideo> createState() => _AdVideoState();
}

class _AdVideoState extends State<_AdVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Falls back to the poster, which is what a still ad would have been.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      return AppNetworkImage(url: widget.poster, fit: BoxFit.cover);
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}
