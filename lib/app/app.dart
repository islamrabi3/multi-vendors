import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/repositories/auth_repository.dart';
import '../core/repositories/cart_repository.dart';
import '../core/repositories/catalog_repository.dart';
import '../features/auth/auth_cubit.dart';
import '../features/customer/cart/cart_cubit.dart';
import 'router.dart';
import 'theme.dart';

class MultiVendorApp extends StatefulWidget {
  const MultiVendorApp({super.key});

  @override
  State<MultiVendorApp> createState() => _MultiVendorAppState();
}

class _MultiVendorAppState extends State<MultiVendorApp> {
  late final AuthCubit _authCubit;
  late final CartCubit _cartCubit;
  late final GoRouter _router;
  final _catalog = CatalogRepository();

  @override
  void initState() {
    super.initState();
    _authCubit = AuthCubit(AuthRepository());
    _cartCubit = CartCubit(repository: CartRepository(catalog: _catalog));
    _router = buildRouter(_authCubit);
  }

  @override
  void dispose() {
    _authCubit.close();
    _cartCubit.close();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _authCubit),
        BlocProvider.value(value: _cartCubit),
      ],
      child: BlocListener<AuthCubit, AppAuthState>(
        listenWhen: (previous, current) =>
            previous.status != current.status &&
            current.status == AuthStatus.authenticated,
        listener: (_, _) => _cartCubit.restoreFromServer(_catalog.fetchVendor),
        child: MaterialApp.router(
          title: 'Multi Vendor',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          routerConfig: _router,
        ),
      ),
    );
  }
}
