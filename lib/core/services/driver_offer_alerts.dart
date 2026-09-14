import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

/// A delivery offered to online drivers, as a notification they can answer
/// from the shade: Accept claims the order without opening the app, Reject
/// dismisses it, and tapping the body opens the job board.
///
/// Android only for the buttons. There, the push arrives as a data message and
/// the app draws the notification itself, so it can attach actions and handle
/// them in a background isolate. On iOS the system draws remote alerts, and
/// answering one without opening the app needs native notification-delegate
/// code this project does not have; there the alert simply opens the order.
class DriverOfferAlerts {
  DriverOfferAlerts._();

  static const kind = 'driver_offer';
  static const acceptAction = 'accept_order';
  static const rejectAction = 'reject_order';

  static const channel = AndroidNotificationChannel(
    'driver_offers',
    'Delivery requests',
    description: 'New deliveries you can accept or reject.',
    importance: Importance.max,
  );

  static bool isOffer(Map<String, dynamic> data) => data['kind'] == kind;

  static String encode(Map<String, dynamic> data) =>
      data.entries.map((e) => '${e.key}=${e.value}').join('|');

  static Map<String, dynamic> decode(String? payload) {
    final data = <String, dynamic>{};
    if (payload == null) return data;
    for (final pair in payload.split('|')) {
      final split = pair.indexOf('=');
      if (split > 0) data[pair.substring(0, split)] = pair.substring(split + 1);
    }
    return data;
  }

  static int _idFor(String orderId) => orderId.hashCode & 0x7fffffff;

  /// Draws the actionable notification. Safe to call from the FCM background
  /// isolate: it only needs the plugin, which it initialises itself.
  static Future<void> show(
    FlutterLocalNotificationsPlugin plugin,
    Map<String, dynamic> data,
  ) async {
    final orderId = '${data['order_id'] ?? ''}';
    if (orderId.isEmpty) return;
    await plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
    await plugin.show(
      _idFor(orderId),
      '${data['title'] ?? ''}',
      '${data['body'] ?? ''}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.message,
          // An offer is only worth answering while it is still open.
          timeoutAfter: 10 * 60 * 1000,
          actions: [
            AndroidNotificationAction(
              acceptAction,
              '${data['accept_label'] ?? 'Accept'}',
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              rejectAction,
              '${data['reject_label'] ?? 'Reject'}',
              cancelNotification: true,
            ),
          ],
        ),
      ),
      payload: encode(data),
    );
  }

  /// Claims the order. Returns true when this driver won it.
  static Future<bool> claim(SupabaseClient client, String orderId) async {
    final result = await client.rpc(
      'claim_delivery',
      params: {'p_order_id': orderId},
    );
    return result == true;
  }

  /// The outcome of an Accept pressed from the shade, as its own notification:
  /// the driver never opened the app, so this is the only place to say so.
  static Future<void> showOutcome(
    FlutterLocalNotificationsPlugin plugin,
    Map<String, dynamic> data, {
    required bool won,
  }) async {
    final orderId = '${data['order_id'] ?? ''}';
    await plugin.show(
      _idFor(orderId),
      won
          ? '${data['accepted_title'] ?? 'Delivery accepted'}'
          : '${data['taken_title'] ?? 'Order already taken'}',
      won ? '${data['accepted_body'] ?? ''}' : '${data['taken_body'] ?? ''}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: encode({
        ...data,
        'kind': won ? 'driver_offer_won' : 'driver_offer_lost',
      }),
    );
  }
}

/// Runs in a background isolate when the driver presses Accept or Reject
/// while the app is not running. Must be top-level.
@pragma('vm:entry-point')
Future<void> driverOfferBackgroundResponse(
  NotificationResponse response,
) async {
  if (response.actionId != DriverOfferAlerts.acceptAction) return;
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  final data = DriverOfferAlerts.decode(response.payload);
  final orderId = '${data['order_id'] ?? ''}';
  if (orderId.isEmpty) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  try {
    // Restores the signed-in session saved by the main app.
    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabaseAnonKey,
      );
    } catch (_) {
      // Already initialised in this isolate.
    }
    final client = Supabase.instance.client;
    if (client.auth.currentSession == null) return;
    final won = await DriverOfferAlerts.claim(client, orderId);
    await DriverOfferAlerts.showOutcome(plugin, data, won: won);
  } catch (error) {
    if (kDebugMode) debugPrint('Background claim failed: $error');
    await DriverOfferAlerts.showOutcome(plugin, data, won: false);
  }
}
