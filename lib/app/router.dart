import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/models/profile.dart';
import '../features/auth/auth_cubit.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/admin/screens/admin_order_detail_screen.dart';
import '../features/admin/screens/admin_orders_screen.dart';
import '../features/admin/screens/admin_promos_screen.dart';
import '../features/admin/screens/admin_vendor_detail_screen.dart';
import '../features/admin/screens/admin_vendors_screen.dart';
import '../features/admin/screens/admin_categories_screen.dart';
import '../features/auth/screens/vendor_onboarding_screen.dart';
import '../features/customer/addresses/addresses_screen.dart';
import '../features/customer/cart/cart_screen.dart';
import '../features/customer/checkout/checkout_screen.dart';
import '../features/customer/checkout/paymob_checkout_screen.dart';
import '../features/customer/home/customer_shell.dart';
import '../features/customer/home/home_screen.dart';
import '../features/customer/orders/order_details_screen.dart';
import '../features/customer/orders/orders_screen.dart';
import '../features/customer/profile/favorites_screen.dart';
import '../features/customer/profile/profile_screen.dart';
import '../features/customer/vendor_details/vendor_details_screen.dart';
import '../features/driver/driver_shell.dart';
import '../features/driver/screens/active_delivery_screen.dart';
import '../features/driver/screens/driver_history_screen.dart';
import '../features/driver/screens/driver_pool_screen.dart';
import '../features/vendor/screens/menu_screen.dart';
import '../features/vendor/screens/product_editor_screen.dart';
import '../features/vendor/screens/vendor_dashboard_screen.dart';
import '../features/vendor/screens/vendor_order_details_screen.dart';
import '../features/vendor/screens/vendor_settings_screen.dart';
import '../features/vendor/vendor_shell.dart';

/// Bridges the AuthCubit stream into a Listenable for GoRouter refresh.
class _AuthRefreshNotifier extends ChangeNotifier {
  _AuthRefreshNotifier(AuthCubit cubit) {
    _subscription = cubit.stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<AppAuthState> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

const _authPaths = {'/login', '/signup'};

String _roleHome(UserRole role) => switch (role) {
      UserRole.vendor => '/vendor-app/dashboard',
      UserRole.driver => '/driver-app/pool',
      UserRole.admin => '/admin-app/overview',
      _ => '/home',
    };

bool _allowedForRole(UserRole role, String location) => switch (role) {
      UserRole.vendor => location.startsWith('/vendor-app'),
      UserRole.driver => location.startsWith('/driver-app'),
      UserRole.admin => location.startsWith('/admin-app'),
      _ => !location.startsWith('/vendor-app') &&
          !location.startsWith('/driver-app') &&
          !location.startsWith('/admin-app'),
    };

GoRouter buildRouter(AuthCubit authCubit) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: _AuthRefreshNotifier(authCubit),
    redirect: (context, state) {
      final auth = authCubit.state;
      final location = state.matchedLocation;

      if (auth.status == AuthStatus.unknown) {
        return location == '/splash' ? null : '/splash';
      }
      if (auth.status == AuthStatus.unauthenticated) {
        return (_authPaths.contains(location) || location == '/splash') ? null : '/splash';
      }

      // Authenticated.
      if (auth.needsVendorOnboarding) {
        return location == '/vendor-onboarding' ? null : '/vendor-onboarding';
      }
      final role = auth.profile!.role;
      if (location == '/splash' ||
          location == '/vendor-onboarding' ||
          _authPaths.contains(location) ||
          !_allowedForRole(role, location)) {
        return _roleHome(role);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/vendor-onboarding',
        builder: (_, _) => const VendorOnboardingScreen(),
      ),

      // Customer area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
      GoRoute(
        path: '/vendors/:id',
        builder: (_, state) =>
            VendorDetailsScreen(vendorId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: '/paymob-checkout',
        builder: (_, state) {
          final args = state.extra! as Map<String, String>;
          return PaymobCheckoutScreen(
            checkoutUrl: args['url']!,
            orderId: args['orderId']!,
          );
        },
      ),
      GoRoute(
        path: '/order/:id',
        builder: (_, state) =>
            OrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/addresses', builder: (_, _) => const AddressesScreen()),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),

      // Vendor area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => VendorShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/vendor-app/dashboard',
              builder: (_, _) => const VendorDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/vendor-app/menu',
              builder: (_, _) => const MenuScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/vendor-app/settings',
              builder: (_, _) => const VendorSettingsScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: '/vendor-app/orders/:id',
        builder: (_, state) =>
            VendorOrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/vendor-app/product-editor',
        builder: (_, state) => ProductEditorScreen(
          args: state.extra! as ProductEditorArgs,
        ),
      ),

      // Admin area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AdminShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin-app/overview',
              builder: (_, _) => const AdminDashboardScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin-app/vendors',
              builder: (_, _) => const AdminVendorsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin-app/orders',
              builder: (_, _) => const AdminOrdersScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin-app/promos',
              builder: (_, _) => const AdminPromosScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/admin-app/categories',
              builder: (_, _) => const AdminCategoriesScreen(),
            ),
          ]),
        ],
      ),
      GoRoute(
        path: '/admin-app/vendors/:id',
        builder: (_, state) =>
            AdminVendorDetailScreen(vendorId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/admin-app/orders/:id',
        builder: (_, state) =>
            AdminOrderDetailScreen(orderId: state.pathParameters['id']!),
      ),

      // Driver area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => DriverShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/driver-app/pool',
              builder: (_, _) => const DriverPoolScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/driver-app/active',
              builder: (_, _) => const ActiveDeliveryScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/driver-app/history',
              builder: (_, _) => const DriverHistoryScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
}
