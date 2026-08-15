import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Shows the first eligible interstitial, if there is one and if now is a
  /// reasonable moment. Silent about everything else — an ad that cannot be
  /// fetched must never be visible to the customer as an error.
  static Future<void> maybeShow(
    BuildContext context, {
    required OffersRepository repository,
  }) async {
    if (_shownSinceLaunch) return;
    try {
      final ads = await repository.activeAds(AdPlacement.interstitial);
      if (ads.isEmpty) return;

      for (final ad in ads) {
        if (await _alreadySeen(ad)) continue;
        if (!context.mounted) return;

        _shownSinceLaunch = true;
        await _markSeen(ad);
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
        backgroundColor: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  // The whole artwork is tappable when there is no button, so
                  // artwork carrying its own call to action still works.
                  onTap: ad.ctaLabel == null ? _act : null,
                  child: _Artwork(ad: ad),
                ),
              ),
              PositionedDirectional(
                top: 12,
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
                  bottom: 28,
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
  const _Artwork({required this.ad});

  final BannerItem ad;

  @override
  Widget build(BuildContext context) {
    if (ad.isSvg) {
      return SvgPicture.network(
        ad.imageUrl,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }
    return AppNetworkImage(
      url: ad.imageUrl,
      fit: BoxFit.contain,
      width: double.infinity,
      height: double.infinity,
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
                  ? const Icon(Icons.close_rounded, size: 20, color: Colors.white)
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
