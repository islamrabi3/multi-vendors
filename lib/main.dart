import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:firebase_core/firebase_core.dart';

import 'app/app.dart';
import 'app/theme.dart' show appOverlayStyle;
import 'firebase_options.dart';
import 'core/config/app_config.dart';
import 'app/locale_cubit.dart' show AppLanguage;
import 'features/auth/screens/app_onboarding_screen.dart';
import 'core/services/notification_service.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Applies before the first frame, so the splash screen — which has no
  // AppBar to derive a style from — already draws the status bar icons dark
  // rather than the platform's white.
  SystemChrome.setSystemUIOverlayStyle(appOverlayStyle);

  // Supabase refreshes the session token on a background timer; when the
  // network blips mid-request it surfaces an AuthRetryableFetchException
  // outside any widget's error scope. The SDK retries by itself, so this
  // must never crash the app — swallow it, let everything else propagate.
  PlatformDispatcher.instance.onError = (error, stack) {
    if (error is AuthRetryableFetchException) {
      debugPrint('Transient auth refresh failure (will retry): $error');
      return true;
    }
    return false;
  };

  if (!AppConfig.isConfigured) {
    runApp(const _MissingConfigApp());
    return;
  }

  // Initialize Firebase & Supabase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  // Accepts either a legacy anon key or a new sb_publishable_... key.
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  // Initialize Notification Service
  NotificationService.instance.initialize();

  await AppOnboarding.load();
  await AppLanguage.load();

  runApp(const MultiVendorApp());
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '${context.l10n.missingSupabaseConfigurationnn}Run with:\nflutter run --dart-define=SUPABASE_ANON_KEY=<key>',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
