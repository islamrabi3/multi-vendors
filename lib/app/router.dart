import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../core/models/profile.dart';
import '../core/utils/l10n_extension.dart';
import 'locale_cubit.dart' show AppLanguage;
import 'splash_gate.dart';
import '../features/auth/auth_cubit.dart';
import '../features/auth/screens/app_onboarding_screen.dart';
import '../features/auth/screens/language_screen.dart';
import '../features/auth/screens/phone_capture_screen.dart';
import '../features/auth/screens/policy_acceptance_screen.dart';
import '../features/auth/screens/blocked_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/auth/screens/role_choice_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/admin/admin_shell.dart';
import '../features/admin/screens/admin_complaints_screen.dart';
import '../features/admin/screens/admin_content_screen.dart';
import '../features/admin/screens/admin_dashboard_screen.dart';
import '../features/admin/screens/admin_drivers_screen.dart';
import '../features/admin/screens/admin_manage_screen.dart';
import '../features/admin/screens/admin_menu_import_screen.dart';
import '../features/admin/screens/admin_order_detail_screen.dart';
import '../features/admin/screens/admin_orders_screen.dart';
import '../features/admin/screens/admin_promos_screen.dart';
import '../features/admin/screens/admin_reports_screen.dart';
import '../features/admin/screens/admin_roles_screen.dart';
import '../features/admin/screens/admin_service_areas_screen.dart';
import '../features/admin/screens/admin_vendor_detail_screen.dart';
import '../features/admin/screens/admin_users_screen.dart';
import '../features/admin/screens/admin_vendors_screen.dart';
import '../features/support/my_support_screen.dart';
import '../features/admin/screens/admin_ads_screen.dart';
import '../features/admin/screens/admin_announcements_screen.dart';
import '../features/admin/screens/admin_categories_screen.dart';
import '../features/admin/screens/admin_price_adjustment_screen.dart';
import '../features/admin/screens/admin_deposits_screen.dart';
import '../features/admin/screens/admin_finance_screen.dart';
import '../features/admin/screens/admin_settlements_screen.dart';
import '../features/auth/screens/vendor_onboarding_screen.dart';
import '../features/customer/addresses/addresses_screen.dart';
import '../features/customer/categories/category_screen.dart';
import '../features/customer/cart/cart_screen.dart';
import '../features/customer/checkout/checkout_screen.dart';
import '../features/customer/checkout/paymob_checkout_screen.dart';
import '../features/customer/search/search_screen.dart';
import '../features/customer/home/customer_shell.dart';
import '../features/customer/home/home_screen.dart';
import '../features/customer/orders/order_chat_sheet.dart';
import '../features/customer/orders/order_details_screen.dart';
import '../features/customer/orders/orders_screen.dart';
import '../features/customer/profile/content_page_screen.dart';
import '../features/customer/profile/favorites_screen.dart';
import '../features/customer/profile/profile_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/customer/vendor_details/vendor_details_screen.dart';
import '../features/driver/driver_shell.dart';
import '../features/driver/screens/active_delivery_screen.dart';
import '../features/driver/screens/driver_documents_screen.dart';
import '../features/driver/screens/driver_history_screen.dart';
import '../features/driver/screens/driver_pool_screen.dart';
import '../features/driver/screens/driver_wallet_screen.dart';
import '../features/vendor/screens/menu_screen.dart';
import '../features/vendor/screens/product_editor_screen.dart';
import '../features/vendor/screens/vendor_dashboard_screen.dart';
import '../features/vendor/screens/vendor_order_details_screen.dart';
import '../features/vendor/screens/vendor_reviews_screen.dart';
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

/// Readable without an account.
///
/// The signup form links to the terms and the privacy policy directly above
/// its submit button, so these have to open for someone who has not signed in
/// yet — that is the entire moment they matter. Without them here the
/// redirect below sent every tap straight back to `/login`, which reads as
/// the link being broken. The database agrees: `app_content`'s read policy
/// grants `anon` for exactly this reason.
const _publicPaths = {'/terms', '/privacy', '/about'};

/// Whether [path] may be opened without an account. Exposed for tests: the
/// rule is one line and easy to trim by accident.
@visibleForTesting
bool isPubliclyReadablePath(String path) => _publicPaths.contains(path);

String _roleHome(UserRole role) => switch (role) {
  UserRole.vendor => '/vendor-app/dashboard',
  UserRole.driver => '/driver-app/pool',
  UserRole.admin => '/admin-app/overview',
  _ => '/home',
};

/// Pages every role can open. Legal text and the about page belong to the
/// platform, not to the customer app, so a vendor or driver reading them must
/// not be bounced back to their own home.
const _sharedPaths = {'/about', '/terms', '/privacy', '/support'};

bool _allowedForRole(UserRole role, String location) {
  if (_sharedPaths.contains(location)) return true;
  return switch (role) {
    UserRole.vendor => location.startsWith('/vendor-app'),
    UserRole.driver => location.startsWith('/driver-app'),
    UserRole.admin => location.startsWith('/admin-app'),
    _ =>
      !location.startsWith('/vendor-app') &&
          !location.startsWith('/driver-app') &&
          !location.startsWith('/admin-app'),
  };
}

GoRouter buildRouter(AuthCubit authCubit) {
  return GoRouter(
    initialLocation: '/splash',
    // Both halves of "is the app ready": the session check, and the splash's
    // own intro. Either finishing has to re-run the redirect below.
    refreshListenable: Listenable.merge([
      _AuthRefreshNotifier(authCubit),
      SplashGate.introDone,
      AppLanguage.chosen,
    ]),
    redirect: (context, state) {
      final auth = authCubit.state;
      final location = state.matchedLocation;

      if (auth.status == AuthStatus.unknown) {
        return location == '/splash' ? null : '/splash';
      }

      // The session is resolved but the brand animation is still running. Hold
      // here rather than cutting it off — whichever of the two finishes second
      // is what decides when the app appears.
      if (!SplashGate.introDone.value) {
        return location == '/splash' ? null : '/splash';
      }
      // Asked before anything else with words in it: the onboarding carousel
      // and the login form are both already written in a language, and on a
      // fresh install nobody has said which one that should be.
      if (!AppLanguage.chosen.value) {
        return location == '/language' ? null : '/language';
      }

      if (auth.status == AuthStatus.unauthenticated) {
        // First launch only: the intro carousel. Once it has been seen — or
        // once anyone has ever signed in on this device — signing out lands
        // straight on the login screen instead of replaying "get started".
        if (!AppOnboarding.seen) {
          return location == '/onboarding' ? null : '/onboarding';
        }
        return _authPaths.contains(location) || _publicPaths.contains(location)
            ? null
            : '/login';
      }

      // Authenticated.
      // A password-reset link just landed. Ahead of every other authenticated
      // gate, including the lockout below — a blocked account should still be
      // able to set a new password, and this is a short-lived detour that
      // clears itself the moment the new-password screen succeeds.
      if (auth.passwordRecovery) {
        return location == '/reset-password' ? null : '/reset-password';
      }
      // A suspended or closed account is stopped ahead of everything else:
      // the server already refuses its writes, and without this the user just
      // meets unexplained failures screen by screen. Support stays reachable
      // so a block can be appealed.
      if (auth.profile?.isLockedOut ?? false) {
        return location == '/blocked' || location == '/support'
            ? null
            : '/blocked';
      }
      // A social sign-up carries no role, so it is asked once before it can
      // reach any part of the app.
      if (auth.needsRoleChoice) {
        return location == '/choose-role' ? null : '/choose-role';
      }
      // After the role is settled — the role decides whether a phone is even
      // required — and before vendor onboarding, which is a longer form the
      // store owner should not be dropped into missing a contact number.
      if (auth.needsPhone) {
        return location == '/add-phone' ? null : '/add-phone';
      }
      // After the phone gate: a partner who agreed to terms we cannot reach
      // them about is worse than one who has not agreed yet. Before vendor
      // onboarding, because onboarding is where trading starts.
      if (auth.needsPolicyAcceptance) {
        return location == '/accept-terms' ? null : '/accept-terms';
      }
      if (auth.needsVendorOnboarding) {
        return location == '/vendor-onboarding' ? null : '/vendor-onboarding';
      }
      final role = auth.profile!.role;
      if (location == '/splash' ||
          location == '/choose-role' ||
          location == '/add-phone' ||
          location == '/accept-terms' ||
          location == '/onboarding' ||
          location == '/vendor-onboarding' ||
          _authPaths.contains(location) ||
          !_allowedForRole(role, location)) {
        return _roleHome(role);
      }
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(
        path: '/language',
        // No explicit destination: committing the choice flips
        // AppLanguage.chosen, and the refresh listener re-runs the redirect
        // above, which sends this on to onboarding or login as appropriate.
        builder: (_, _) => const LanguageScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (_, _) => const AppOnboardingScreen(),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignupScreen()),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/choose-role',
        builder: (_, _) => const RoleChoiceScreen(),
      ),
      GoRoute(path: '/blocked', builder: (_, _) => const BlockedScreen()),
      GoRoute(
        path: '/add-phone',
        builder: (_, _) => const PhoneCaptureScreen(),
      ),
      GoRoute(
        path: '/accept-terms',
        builder: (_, _) => const PolicyAcceptanceScreen(),
      ),
      GoRoute(
        path: '/vendor-onboarding',
        builder: (_, _) => const VendorOnboardingScreen(),
      ),

      // Customer area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/orders', builder: (_, _) => const OrdersScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, _) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/vendors/:id',
        builder: (_, state) =>
            VendorDetailsScreen(vendorId: state.pathParameters['id']!),
      ),
      // Outside the customer shell on purpose: search and categories are
      // drill-downs with a back arrow, not extra tabs.
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(
        path: '/categories/:id',
        builder: (_, state) =>
            CategoryScreen(categoryId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/cart', builder: (_, _) => const CartScreen()),
      GoRoute(path: '/checkout', builder: (_, _) => const CheckoutScreen()),
      GoRoute(
        path: '/paymob-checkout',
        builder: (_, state) =>
            PaymobCheckoutScreen(checkoutUrl: state.extra! as String),
      ),
      GoRoute(
        path: '/order/:id',
        builder: (_, state) =>
            OrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
      // A tapped chat notification lands here, so the thread has to be
      // reachable as a route rather than only as a sheet pushed from a screen
      // the user may never have opened.
      GoRoute(
        path: '/order/:id/chat',
        builder: (_, state) =>
            OrderChatScreen(orderId: state.pathParameters['id']!),
      ),
      // Support belongs to every role: a vendor or driver needs the platform
      // just as much as a customer does.
      GoRoute(path: '/support', builder: (_, _) => const MySupportScreen()),

      // Operator-managed pages. The body is fetched, so a wording change ships
      // from the admin app rather than through a store review.
      GoRoute(
        path: '/about',
        builder: (context, _) => ContentPageScreen(
          contentKey: 'about',
          fallbackTitle: context.l10n.aboutUs,
          showLinks: true,
        ),
      ),
      GoRoute(
        path: '/terms',
        builder: (context, _) => ContentPageScreen(
          contentKey: 'terms',
          fallbackTitle: context.l10n.termsAndConditions,
        ),
      ),
      GoRoute(
        path: '/privacy',
        builder: (context, _) => ContentPageScreen(
          contentKey: 'privacy',
          fallbackTitle: context.l10n.privacyPolicy,
        ),
      ),
      GoRoute(path: '/addresses', builder: (_, _) => const AddressesScreen()),
      GoRoute(path: '/favorites', builder: (_, _) => const FavoritesScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),

      // Vendor area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => VendorShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vendor-app/dashboard',
                builder: (_, _) => const VendorDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vendor-app/menu',
                builder: (_, _) => const MenuScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/vendor-app/settings',
                builder: (_, _) => const VendorSettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/vendor-app/orders/:id',
        builder: (_, state) =>
            VendorOrderDetailsScreen(orderId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/vendor-app/reviews',
        builder: (_, _) => const VendorReviewsScreen(),
      ),
      GoRoute(
        path: '/vendor-app/product-editor',
        builder: (_, state) =>
            ProductEditorScreen(args: state.extra! as ProductEditorArgs),
      ),

      // Admin area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => AdminShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin-app/overview',
                builder: (_, _) => const AdminDashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin-app/orders',
                builder: (_, _) => const AdminOrdersScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin-app/vendors',
                builder: (_, _) => const AdminVendorsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/admin-app/manage',
                builder: (_, _) => const AdminManageScreen(),
              ),
            ],
          ),
        ],
      ),

      // Reached from the Manage hub rather than the tab bar, so they push over
      // the shell instead of owning a branch.
      GoRoute(
        path: '/admin-app/promos',
        builder: (_, _) => const AdminPromosScreen(),
      ),
      GoRoute(
        path: '/admin-app/categories',
        builder: (_, _) => const AdminCategoriesScreen(),
      ),
      GoRoute(
        path: '/admin-app/content',
        builder: (_, _) => const AdminContentScreen(),
      ),
      GoRoute(
        path: '/admin-app/ads',
        builder: (_, _) => const AdminAdsScreen(),
      ),
      GoRoute(
        path: '/admin-app/announcements',
        builder: (_, _) => const AdminAnnouncementsScreen(),
      ),
      GoRoute(
        path: '/admin-app/roles',
        builder: (_, _) => const AdminRolesScreen(),
      ),
      GoRoute(
        path: '/admin-app/users',
        builder: (_, _) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: '/admin-app/support',
        builder: (_, _) => const AdminSupportScreen(),
      ),
      GoRoute(
        path: '/admin-app/complaints',
        builder: (_, _) => const AdminComplaintsScreen(),
      ),
      GoRoute(
        path: '/admin-app/sales-reports',
        builder: (_, _) => const AdminReportsScreen(),
      ),
      GoRoute(
        path: '/admin-app/reports',
        builder: (_, _) => const AdminReportsScreen(),
      ),
      GoRoute(
        path: '/admin-app/service-areas',
        builder: (_, _) => const AdminServiceAreasScreen(),
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
      // AI menu extraction is an operator tool, not a vendor one: each run
      // costs money and writes a whole catalogue.
      GoRoute(
        path: '/admin-app/drivers',
        builder: (_, _) => const AdminDriversScreen(),
      ),
      GoRoute(
        path: '/admin-app/menu-import',
        builder: (_, _) => const AdminMenuImportScreen(),
      ),
      GoRoute(
        path: '/admin-app/price-adjustment',
        builder: (_, _) => const AdminPriceAdjustmentScreen(),
      ),
      GoRoute(
        path: '/admin-app/finance',
        builder: (_, _) => const AdminFinanceScreen(),
      ),
      GoRoute(
        path: '/admin-app/settlements',
        builder: (_, _) => const AdminSettlementsScreen(),
      ),
      GoRoute(
        path: '/admin-app/deposits',
        builder: (_, _) => const AdminDepositsScreen(),
      ),

      // Driver area.
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => DriverShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver-app/pool',
                builder: (_, _) => const DriverPoolScreen(),
                routes: [
                  // Nested so the shell's tab bar stays put: verification is
                  // something a driver steps into and back out of, not a
                  // fourth place to be.
                  GoRoute(
                    path: 'documents',
                    builder: (_, _) => const DriverDocumentsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver-app/active',
                builder: (_, _) => const ActiveDeliveryScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver-app/history',
                builder: (_, _) => const DriverHistoryScreen(),
              ),
            ],
          ),
          // The driver's money is a destination, not a detail behind their
          // earnings history: the cash they owe is the thing they check
          // before ending a shift.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/driver-app/wallet',
                builder: (_, _) => const DriverWalletScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
