import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'driver_offer_alerts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // A delivery offer arrives as data only on Android, so nothing is on screen
  // until the app draws it — with its Accept / Reject buttons.
  if (defaultTargetPlatform == TargetPlatform.android &&
      DriverOfferAlerts.isOffer(message.data)) {
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveBackgroundNotificationResponse: driverOfferBackgroundResponse,
    );
    await DriverOfferAlerts.show(plugin, message.data);
  }
}

/// Device-side push plumbing: permissions, token sync, foreground display.
///
/// Sending happens server-side through the `send-push` Edge Function — the
/// Firebase service account must never ship inside the app, and reading the
/// recipient's fcm_token requires the service role (RLS hides other
/// users' profiles from the client).
class NotificationService {
  NotificationService._internal();
  static final NotificationService instance = NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Where a tapped notification should take the user. Set by the app once the
  /// router exists; a tap that arrives before then is replayed through
  /// [consumePendingRoute].
  void Function(String route)? onOpenRoute;

  /// A push that arrived while a browser tab was in the foreground.
  ///
  /// Native draws these with flutter_local_notifications, which has no web
  /// implementation — so on web the app has to render its own in-page banner,
  /// and this is how the service hands one over. Null until the UI layer sets
  /// it, in which case a foreground push on web is simply not shown; the
  /// service worker still handles everything that arrives while the tab is
  /// closed or in the background.
  void Function(String title, String body, Map<String, dynamic> data)?
  onForegroundMessage;
  String? _pendingRoute;

  /// The route a notification asked for while the router was not ready yet.
  /// The app drains this once after its first frame.
  String? consumePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  /// Translates a message's data payload into an in-app destination.
  ///
  /// Returns null for payloads with nothing to open, so a tap on those simply
  /// brings the app to the foreground instead of jumping somewhere arbitrary.
  static String? routeFor(Map<String, dynamic> data) {
    // Pushes that name their own destination (complaints, campaigns).
    final route = data['route'];
    if (route is String && route.startsWith('/') && data['order_id'] == null) {
      return route;
    }
    final orderId = data['order_id'] as String?;
    if (orderId == null || orderId.isEmpty) return null;
    // Driver pushes open the driver's own screens; `/order/:id` is the
    // customer's page and a driver has nothing to do there.
    switch (data['kind'] ?? data['event']) {
      case DriverOfferAlerts.kind || 'ready_for_pickup' || 'driver_offer_lost':
        return '/driver-app/pool';
      case 'driver_offer_won' || 'driver_assigned':
        return '/driver-app/active';
    }
    if (data['type'] != 'chat') return '/order/$orderId';
    // An order carries two conversations; the push says which one it came
    // from so the tap lands in it and not in the other.
    final thread = data['thread'] == 'driver' ? 'driver' : 'vendor';
    return '/order/$orderId/chat?thread=$thread';
  }

  void _openRoute(String route) =>
      onOpenRoute == null ? _pendingRoute = route : onOpenRoute!(route);

  /// A local notification was tapped, or one of its buttons pressed, while
  /// the app is running.
  Future<void> _onLocalResponse(NotificationResponse response) async {
    final data = DriverOfferAlerts.decode(response.payload);
    switch (response.actionId) {
      case DriverOfferAlerts.rejectAction:
        return;
      case DriverOfferAlerts.acceptAction:
        final orderId = '${data['order_id'] ?? ''}';
        if (orderId.isEmpty) return;
        try {
          final won = await DriverOfferAlerts.claim(
            Supabase.instance.client,
            orderId,
          );
          if (won) {
            _openRoute('/driver-app/active');
          } else {
            await DriverOfferAlerts.showOutcome(
              _localNotifications,
              data,
              won: false,
            );
          }
        } catch (_) {
          await DriverOfferAlerts.showOutcome(
            _localNotifications,
            data,
            won: false,
          );
        }
        return;
    }
    final route = routeFor(data);
    if (route != null) _openRoute(route);
  }

  void _handleTap(RemoteMessage message) {
    final route = routeFor(message.data);
    if (route == null) return;
    final handler = onOpenRoute;
    if (handler == null) {
      _pendingRoute = route;
      return;
    }
    handler(route);
  }

  /// Initializes FCM and local notification listeners.
  ///
  /// On web this needs two things that native does not: the service worker at
  /// `web/firebase-messaging-sw.js`, and a VAPID key. Without the key it stays
  /// a no-op and the browser is never prompted — a permission request fired on
  /// page load and denied is denied *permanently*, so asking before push can
  /// actually be delivered would burn the only chance to ask.
  ///
  /// The native-only pieces below (background isolate, local-notification
  /// plugin, Android channel) are skipped on web: the browser draws
  /// background notifications from the service worker itself.
  Future<void> initialize() async {
    if (kIsWeb && !AppConfig.hasWebPush) return;
    try {
      if (!kIsWeb) {
        FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler,
        );
      }

      // Notification Permissions
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        if (kDebugMode) print('User granted notification permissions');
      }

      if (!kIsWeb) {
        // iOS shows nothing while the app is in the foreground unless this is
        // set; Android has no equivalent switch.
        await _fcm.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      // Declared here rather than inside the native block below: the
      // foreground listener further down reads it too.
      const androidChannel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'Used for order updates and chat alerts.',
        importance: Importance.high,
      );

      // Initialize Local Notifications for Foreground display
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings(
        // Asked through FCM above; asking twice shows nothing new.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      const initSettings = InitializationSettings(
        android: androidInit,
        iOS: iosInit,
      );

      // A foreground banner is drawn by flutter_local_notifications, so its own
      // tap callback is what fires for those — the FCM stream never sees them.
      // The plugin has no web backend, so this whole block is native-only.
      if (!kIsWeb) {
        await _localNotifications.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onLocalResponse,
          onDidReceiveBackgroundNotificationResponse:
              driverOfferBackgroundResponse,
        );

        // Cold start from tapping a notification the app itself drew (an
        // offer, or the result of accepting one from the shade).
        final launch = await _localNotifications
            .getNotificationAppLaunchDetails();
        final launchResponse = launch?.notificationResponse;
        if ((launch?.didNotificationLaunchApp ?? false) &&
            launchResponse != null) {
          await _onLocalResponse(launchResponse);
        }

        final androidPlugin = _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
        await androidPlugin?.createNotificationChannel(androidChannel);
      }

      // Listen for FCM messages while app is in foreground
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        // On Android an offer is data-only and must be drawn here too. On iOS
        // the system already shows its alert in the foreground.
        if (!kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android &&
            DriverOfferAlerts.isOffer(message.data)) {
          DriverOfferAlerts.show(_localNotifications, message.data);
          return;
        }
        final notification = message.notification;
        final android = message.notification?.android;
        // flutter_local_notifications has no web implementation; a foreground
        // push in a browser tab is surfaced by the app's own in-page banner
        // instead, which `onForegroundMessage` hands to the UI layer.
        if (kIsWeb) {
          if (notification != null) {
            onForegroundMessage?.call(
              notification.title ?? '',
              notification.body ?? '',
              message.data,
            );
          }
          return;
        }
        if (notification != null) {
          _localNotifications.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                androidChannel.id,
                androidChannel.name,
                channelDescription: androidChannel.description,
                icon: android?.smallIcon ?? '@mipmap/ic_launcher',
                importance: Importance.high,
                priority: Priority.high,
              ),
              iOS: const DarwinNotificationDetails(),
            ),
            payload: message.data.entries
                .map((e) => '${e.key}=${e.value}')
                .join('|'),
          );
        }
      });

      // Tapped while the app was backgrounded.
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

      // Opened from a cold start by tapping a notification. The router does
      // not exist yet here, so the route is parked and replayed.
      final initial = await _fcm.getInitialMessage();
      if (initial != null) _handleTap(initial);

      // Save initial FCM token to current logged-in user profile
      await syncFcmToken();

      // Listen to token refreshes
      _fcm.onTokenRefresh.listen((newToken) {
        _saveTokenToSupabase(newToken);
      });
    } catch (e) {
      if (kDebugMode) print('Error initializing NotificationService: $e');
    }
  }

  /// Fetches and updates current user's FCM token in Supabase `profiles` table.
  ///
  /// Do not gate this on getAPNSToken(): that only reads the currently cached
  /// APNs token and returns null while registration is still in flight, while
  /// getToken() waits for APNs itself. Gating on it skipped the sync entirely
  /// on iOS.
  Future<void> syncFcmToken() async {
    if (kIsWeb && !AppConfig.hasWebPush) return;
    try {
      // Web derives its token from the VAPID key and the registered service
      // worker; native ignores the argument entirely.
      final token = await _fcm.getToken(
        vapidKey: kIsWeb ? AppConfig.fcmVapidKey : null,
      );
      if (token == null) {
        if (kDebugMode) print('FCM token not available yet.');
        return;
      }
      if (kDebugMode) print('FCM token: $token');
      await _saveTokenToSupabase(token);
    } catch (e) {
      if (kDebugMode) print('Error syncing FCM token: $e');
    }
  }

  /// Detaches this device from the signed-in account. Call before signing out,
  /// while the session still exists (RLS needs it to clear the column).
  ///
  /// Without this the token stayed on the old profile after sign-out, so a
  /// shared or handed-over phone kept receiving the previous user's order,
  /// chat and support pushes — and after switching accounts it carried
  /// several users' notifications at once. Deleting the token too means the
  /// next account gets a fresh one, and any stale copy still stored elsewhere
  /// starts failing at FCM and is cleaned up by the senders.
  Future<void> releaseDeviceToken() async {
    final client = Supabase.instance.client;
    final userId = client.auth.currentUser?.id;
    try {
      if (userId != null) {
        await client
            .from('profiles')
            .update({'fcm_token': null})
            .eq('id', userId);
      }
    } catch (e) {
      if (kDebugMode) print('Error clearing FCM token from profile: $e');
    }
    if (kIsWeb && !AppConfig.hasWebPush) return;
    try {
      await _fcm.deleteToken();
    } catch (e) {
      if (kDebugMode) print('Error deleting FCM token: $e');
    }
  }

  Future<void> _saveTokenToSupabase(String fcmToken) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      // The locale rides along: the server composes push text and has no other
      // way to know which language this user reads the app in. Written here
      // because this is the first moment after sign-in where a session exists.
      final prefs = await SharedPreferences.getInstance();
      final locale = prefs.getString('app_locale');
      await Supabase.instance.client
          .from('profiles')
          .update({
            'fcm_token': fcmToken,
            if (locale == 'en' || locale == 'ar') 'locale': locale,
          })
          .eq('id', userId);
    } catch (e) {
      if (kDebugMode) print('Error saving FCM token to profile: $e');
    }
  }

  /// Sends a push to [userId] via the `send-push` Edge Function. Fire and
  /// forget: a failed push must never break the action that triggered it.
  ///
  /// Prefer [titleKey] to [title]. The sender has no idea what language the
  /// recipient reads — an admin working in English resolving a complaint for
  /// an Arabic customer would otherwise send them an English heading — so a
  /// keyed title is resolved server-side against the recipient's own
  /// `profiles.locale`.
  Future<void> sendNotificationToUser({
    required String userId,
    required String body,
    String? title,
    String? titleKey,
    Map<String, String>? data,
  }) async {
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'user_id': userId,
          'title': ?title,
          'title_key': ?titleKey,
          'body': body,
          'data': ?data,
        },
      );
      if (kDebugMode) print('send-push: ${response.data}');
    } catch (e) {
      if (kDebugMode) print('Error sending notification to user $userId: $e');
    }
  }
}
