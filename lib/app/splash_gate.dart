import 'package:flutter/foundation.dart';

/// Holds the app on the splash until its intro has finished playing.
///
/// The router redirects away from `/splash` the instant the session resolves,
/// and resolving a cached session takes a few hundred milliseconds — well
/// inside the 1700 ms intro. The arch would be caught mid-draw and the whole
/// animation replaced by the home screen, so on a warm start nobody ever saw
/// the brand at all.
///
/// This is the other half of the condition. The splash leaves only once *both*
/// are true: the intro has run to its final frame, and the auth check has come
/// back. Whichever finishes second decides when the app appears.
///
/// A [ValueNotifier] rather than a `Completer` because GoRouter needs something
/// to listen to — it is merged into the router's `refreshListenable`, so
/// flipping it re-runs the redirect.
class SplashGate {
  SplashGate._();

  /// False until the splash's intro reaches its last frame.
  static final ValueNotifier<bool> introDone = ValueNotifier(false);

  /// Called by the splash when the timeline completes — or immediately when
  /// the platform asks for reduced motion, since there is then no animation to
  /// wait for.
  static void markIntroDone() => introDone.value = true;

  /// Lets a cold start play the intro again. Only used by tests today: the
  /// splash is a once-per-launch screen, and signing out goes to `/login`
  /// rather than back through here.
  @visibleForTesting
  static void reset() => introDone.value = false;
}
