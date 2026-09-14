import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../models/banner_item.dart';
import '../repositories/offers_repository.dart';
import 'common.dart';

/// Full-screen ads, and the rules about when one may interrupt somebody.
///
/// Kept out of the widget because "have they seen this" is per-install state
/// that no server call should be needed to answer, and because the decision
/// not to show one is the more important half of the feature.
class InterstitialAds {
  InterstitialAds._();

  static const _seenPrefix = 'interstitial_seen_';

  /// Ads already shown in this run of the app. An `every_session` ad is
  /// allowed back after a restart but not twice in one sitting.
  static final Set<String> _shownThisSession = {};

  /// The narrowest possible gate: one interstitial per app launch, full stop.
  ///
  /// Even with sane per-ad frequencies, three campaigns running at once would
  /// otherwise stack three full-screen takeovers on a customer opening the
  /// app. Whatever else is true, they see at most one.
  static bool _shownSinceLaunch = false;

  static Future<bool> _alreadySeen(BannerItem ad) async {
    if (_shownThisSession.contains(ad.id)) return true;
    if (ad.frequency == 'every_session') return false;

    final prefs = await SharedPreferences.getInstance();
    final stamp = prefs.getString('$_seenPrefix${ad.id}');
    if (stamp == null) return false;
    if (ad.frequency == 'once') return true;

    // 'daily': seen today already?
    final seen = DateTime.tryParse(stamp);
    if (seen == null) return false;
    final now = DateTime.now();
    return seen.year == now.year &&
        seen.month == now.month &&
        seen.day == now.day;
  }

  static Future<void> _markSeen(BannerItem ad) async {
    _shownThisSession.add(ad.id);
    if (ad.frequency == 'every_session') return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_seenPrefix${ad.id}',
      DateTime.now().toIso8601String(),
    );
  }

  /// Video files already on this device, by ad id, for the ad about to show.
  static final Map<String, String> _localVideos = {};

  /// A full-screen video plays only from a file already on the device, so it
  /// starts instantly with no spinner. A video that is not cached yet is
  /// downloaded quietly for next time and this launch goes without it.
  static Future<bool> _videoReady(BannerItem ad) async {
    if (!ad.isVideo) return true;
    final url = ad.videoUrl!;
    try {
      final cached = await DefaultCacheManager().getFileFromCache(url);
      if (cached != null && await cached.file.exists()) {
        _localVideos[ad.id] = cached.file.path;
        return true;
      }
    } catch (_) {}
    unawaited(
      DefaultCacheManager().downloadFile(url).then((_) {}, onError: (_) {}),
    );
    return false;
  }

  /// Downloads the videos for [placement] ahead of time, so the next launch
  /// can play them immediately. Called once the app is idle.
  static Future<void> prefetch(
    OffersRepository repository, {
    AdPlacement placement = AdPlacement.splash,
  }) async {
    if (kIsWeb) return;
    try {
      final ads = await repository.activeAds(placement);
      for (final ad in ads.where((a) => a.isVideo)) {
        final url = ad.videoUrl!;
        final cached = await DefaultCacheManager().getFileFromCache(url);
        if (cached == null) {
          await DefaultCacheManager().downloadFile(url);
        }
      }
    } catch (_) {}
  }

  static String? localVideoFor(BannerItem ad) => _localVideos[ad.id];

  /// Shows the first eligible interstitial, if there is one and if now is a
  /// reasonable moment. Silent about everything else — an ad that cannot be
  /// fetched must never be visible to the customer as an error.
  static Future<void> maybeShow(
    BuildContext context, {
    required OffersRepository repository,
    AdPlacement placement = AdPlacement.interstitial,

    /// Bounds only the lookup. The ad itself stays up until it is closed —
    /// a timeout around the whole call used to tear the dialog down under
    /// the viewer as soon as the splash moved on.
    Duration? fetchTimeout,
  }) async {
    // Full-screen ads are a mobile-app format only.
    if (kIsWeb || _shownSinceLaunch) return;
    try {
      final lookup = repository.activeAds(placement);
      final ads = await (fetchTimeout == null
          ? lookup
          : lookup.timeout(fetchTimeout));
      if (ads.isEmpty) return;

      for (final ad in ads) {
        if (await _alreadySeen(ad)) continue;
        if (!await _videoReady(ad)) continue;
        if (!context.mounted) return;

        _shownSinceLaunch = true;
        _shownThisSession.add(ad.id);
        unawaited(repository.recordEvent(ad.id, click: false));

        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          // The ad's own close control is the way out, so the barrier does not
          // double as one — otherwise a mistimed tap dismisses it before it
          // has rendered.
          barrierDismissible: false,
          barrierColor: Colors.black.withValues(alpha: 0.82),
          useSafeArea: false,
          builder: (_) => _InterstitialDialog(ad: ad, repository: repository),
        );
        // Only once it has actually been on screen and closed does it count
        // as seen for `once` / `daily`.
        await _markSeen(ad);
        return;
      }
    } catch (_) {
      // A promo is never worth an error in front of a customer.
    }
  }

  /// Lets a signed-out user who then signs in see one, and keeps tests honest.
  @visibleForTesting
  static void resetForTesting() {
    _shownSinceLaunch = false;
    _shownThisSession.clear();
  }
}

class _InterstitialDialog extends StatefulWidget {
  const _InterstitialDialog({required this.ad, required this.repository});

  final BannerItem ad;
  final OffersRepository repository;

  @override
  State<_InterstitialDialog> createState() => _InterstitialDialogState();
}

class _InterstitialDialogState extends State<_InterstitialDialog> {
  late bool _canClose =
      widget.ad.dismissible && widget.ad.dismissAfterSeconds <= 0;
  Timer? _unlock;
  int _remaining = 0;

  @override
  void initState() {
    super.initState();
    _remaining = widget.ad.dismissAfterSeconds;
    if (!_canClose && widget.ad.dismissible) {
      // Counts down visibly. A close button that simply is not there yet reads
      // as a broken ad; one that says "3" reads as a rule.
      _unlock = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) {
          timer.cancel();
          setState(() => _canClose = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _unlock?.cancel();
    super.dispose();
  }

  void _close() {
    unawaited(widget.repository.recordEvent(widget.ad.id, dismissal: true));
    Navigator.of(context).maybePop();
  }

  Future<void> _act() async {
    final ad = widget.ad;
    unawaited(widget.repository.recordEvent(ad.id, click: true));
    Navigator.of(context).maybePop();
    if (!mounted) return;

    // Where it goes, in the order the record answers it.
    if (ad.vendorId != null) {
      context.push('/vendors/${ad.vendorId}');
      return;
    }
    final link = ad.linkUrl?.trim();
    if (link == null || link.isEmpty) return;
    if (link.startsWith('/')) {
      context.push(link);
      return;
    }
    final uri = Uri.tryParse(link);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    return PopScope(
      // The system back gesture must obey the same rule as the close button,
      // or `dismissible: false` means nothing.
      canPop: _canClose,
      child: Dialog.fullscreen(
        backgroundColor: ad.isVideo ? Colors.black : Colors.transparent,
        // Edge to edge: the artwork runs under the status bar and home
        // indicator; only the controls keep clear of them.
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                // The whole artwork is tappable when there is no button, so
                // artwork carrying its own call to action still works.
                onTap: ad.ctaLabel == null ? _act : null,
                child: _Artwork(
                  ad: ad,
                  // A video that cannot play and has no cover leaves nothing
                  // to look at; close quietly instead of showing a spinner.
                  onUnplayable: () {
                    if (mounted) Navigator.of(context).maybePop();
                  },
                  // Played through to the end: the ad is over, so the app
                  // carries on by itself.
                  onFinished: () {
                    if (mounted) Navigator.of(context).maybePop();
                  },
                ),
              ),
            ),
            PositionedDirectional(
              top: MediaQuery.paddingOf(context).top + 12,
              end: 12,
              child: _CloseButton(
                canClose: _canClose,
                remaining: _remaining,
                dismissible: ad.dismissible,
                onClose: _close,
              ),
            ),
            if (ad.ctaLabel != null)
              PositionedDirectional(
                bottom: MediaQuery.paddingOf(context).bottom + 28,
                start: 24,
                end: 24,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: _act,
                  child: Text(
                    ad.ctaLabel!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The creative: SVG or raster, contained rather than cropped.
///
/// `BoxFit.contain` because an interstitial is usually a designed composition
/// with text in it — cropping one to fill a phone cuts the message off, which
/// is worse than letterboxing it.
class _Artwork extends StatelessWidget {
  const _Artwork({
    required this.ad,
    required this.onUnplayable,
    required this.onFinished,
  });

  final BannerItem ad;
  final VoidCallback onUnplayable;
  final VoidCallback onFinished;

  @override
  Widget build(BuildContext context) {
    // Video first: `videoUrl` set is what makes a splash or interstitial ad a
    // video ad at all. This used to fall through to the static image even
    // when a video was attached, so a video URL an admin uploaded here never
    // actually played.
    if (ad.isVideo) {
      final local = InterstitialAds.localVideoFor(ad);
      return _FullScreenAdVideo(
        url: ad.videoUrl!,
        localPath: local,
        poster: ad.poster,
        onUnplayable: onUnplayable,
        onFinished: onFinished,
      );
    }
    // A still ad is a card floating over the dimmed app, not a raw image
    // pinned to the screen edges: inset, with rounded corners.
    final artwork = ad.isSvg
        ? SvgPicture.network(
            ad.imageUrl,
            fit: BoxFit.contain,
            placeholderBuilder: (_) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          )
        : AppNetworkImage(url: ad.imageUrl, fit: BoxFit.contain);
    final insets = MediaQuery.paddingOf(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        insets.top + 64,
        20,
        insets.bottom + (ad.ctaLabel == null ? 40 : 100),
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: artwork,
        ),
      ),
    );
  }
}

/// A full-screen video ad: fills the screen, plays once with sound, and
/// closes itself when it ends.
class _FullScreenAdVideo extends StatefulWidget {
  const _FullScreenAdVideo({
    required this.url,
    this.localPath,
    required this.poster,
    required this.onUnplayable,
    required this.onFinished,
  });

  final String url;

  /// The cached copy; played in preference to [url] so it starts instantly.
  final String? localPath;
  final String? poster;
  final VoidCallback onUnplayable;
  final VoidCallback onFinished;

  @override
  State<_FullScreenAdVideo> createState() => _FullScreenAdVideoState();
}

class _FullScreenAdVideoState extends State<_FullScreenAdVideo> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final local = widget.localPath;
    final controller = local != null
        ? VideoPlayerController.file(File(local))
        : VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _controller = controller;
    try {
      // A codec the platform cannot decode (HEVC in Chrome, say) may never
      // report an error at all, so it gets a deadline.
      await controller.initialize().timeout(const Duration(seconds: 8));
      // Closed while still loading: the controller is on its way out.
      if (!mounted) return;
      // Full screen and chosen to open the app with, so it plays with sound;
      // the viewer can mute it. Inline ads elsewhere stay silent.
      await controller.setVolume(1);
      if (!mounted) return;
      controller.addListener(_watchForEnd);
      await controller.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      // Falls back to the poster, which is what a still ad would have been.
      if (mounted && widget.poster == null) widget.onUnplayable();
    }
  }

  bool _finished = false;

  void _watchForEnd() {
    final value = _controller?.value;
    if (_finished || value == null || !value.isCompleted) return;
    _finished = true;
    widget.onFinished();
  }

  @override
  void dispose() {
    final controller = _controller;
    controller?.removeListener(_watchForEnd);
    // On completion video_player runs `pause().then(seekTo(end))` itself, and
    // that seek writes to the controller when it returns. Closing the ad on
    // completion disposes this widget in between, so the controller is
    // disposed a moment later instead of immediately.
    if (controller != null) {
      unawaited(controller.pause().catchError((_) {}));
      Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (!_ready || controller == null) {
      final poster = widget.poster;
      // No spinner: the video plays from the device and is ready in a
      // moment, and a loader flashing over an ad reads as a broken app.
      if (poster == null) return const ColoredBox(color: Colors.black);
      return AppNetworkImage(
        url: poster,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
      );
    }
    final size = controller.value.size;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover, not contain: fills the whole screen, trimming the edges
        // rather than letterboxing.
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
        PositionedDirectional(
          bottom: MediaQuery.paddingOf(context).bottom + 20,
          start: 16,
          child: Material(
            color: Colors.black.withValues(alpha: 0.55),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              color: Colors.white,
              icon: Icon(
                _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              ),
              onPressed: () {
                setState(() => _muted = !_muted);
                controller.setVolume(_muted ? 0 : 1);
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({
    required this.canClose,
    required this.remaining,
    required this.dismissible,
    required this.onClose,
  });

  final bool canClose;
  final int remaining;
  final bool dismissible;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    // A permanently un-closable full-screen ad is a trap, so even a
    // non-dismissible one keeps a way out once its delay has passed.
    if (!dismissible && !canClose) return const SizedBox.shrink();

    return Semantics(
      button: canClose,
      label: MaterialLocalizations.of(context).closeButtonLabel,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canClose ? onClose : null,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Center(
              child: canClose
                  ? const Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: Colors.white,
                    )
                  : Text(
                      '$remaining',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
