import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:multi_vendor/l10n/app_localizations.dart';
import 'locale_cubit.dart';

import '../core/repositories/auth_repository.dart';
import '../core/repositories/cart_repository.dart';
import '../core/repositories/catalog_repository.dart';
import '../core/services/notification_service.dart';
import '../features/auth/auth_cubit.dart';
import '../features/customer/cart/cart_cubit.dart';
import 'router.dart';
import 'theme.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class MultiVendorApp extends StatefulWidget {
  const MultiVendorApp({super.key});

  @override
  State<MultiVendorApp> createState() => _MultiVendorAppState();
}

class _MultiVendorAppState extends State<MultiVendorApp> {
  late final AuthCubit _authCubit;
  late final CartCubit _cartCubit;
  late final LocaleCubit _localeCubit;
  late final GoRouter _router;
  final _catalog = CatalogRepository();

  @override
  void initState() {
    super.initState();
    _authCubit = AuthCubit(AuthRepository());
    _cartCubit = CartCubit(repository: CartRepository(catalog: _catalog));
    _localeCubit = LocaleCubit();
    _router = buildRouter(_authCubit);

    // A tapped notification names a destination; the router is the only thing
    // that can open it. A tap from a cold start arrives before this point, so
    // the parked route is drained once the first frame is up.
    NotificationService.instance.onOpenRoute = _router.push;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pending = NotificationService.instance.consumePendingRoute();
      if (pending != null) _router.push(pending);
    });
  }

  @override
  void dispose() {
    _authCubit.close();
    _cartCubit.close();
    _localeCubit.close();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authCubit),
        BlocProvider.value(value: _cartCubit),
        BlocProvider.value(value: _localeCubit),
      ],
      child: BlocListener<AuthCubit, AppAuthState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (_, state) {
          if (state.status == AuthStatus.authenticated) {
            _cartCubit.restoreFromServer(_catalog.fetchVendor);
          } else if (state.status == AuthStatus.unauthenticated) {
            // Sign-out: drop the cart so it never carries into the next session.
            _cartCubit.resetLocal();
          }
        },
        child: BlocBuilder<LocaleCubit, Locale>(
          builder: (context, locale) {
            return MaterialApp.router(
              onGenerateTitle: (context) => context.l10n.multiVendor,
              debugShowCheckedModeBanner: false,
              theme: buildTheme(),
              routerConfig: _router,
              // Accessibility text scaling is the single biggest source of
              // overflowing labels: at the 2.0x some users run, a two-word
              // button caption is twice as wide as the button. Capped rather
              // than ignored — 1.3x is a real accessibility gain and still fits
              // the layouts. Beyond that the app stops being usable at all,
              // which helps nobody.
              builder: (context, child) => MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: child ?? const SizedBox.shrink(),
              ),
              locale: locale,
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [
                Locale('en'), // English
                Locale('ar'), // Arabic
              ],
            );
          },
        ),
      ),
    );
  }
}
