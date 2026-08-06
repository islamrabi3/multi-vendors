import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException, StorageException;

import '../../l10n/app_localizations.dart';

/// What went wrong, in the only terms the UI cares about.
///
/// The kind decides the shape of the response — offer a retry, send them to
/// support, or just say it plainly — while [code] carries the server's own
/// word for it when there is one.
enum FailureKind {
  /// No usable connection, or the request never came back.
  network,

  /// The session is gone or was never valid.
  auth,

  /// Signed in, but not allowed to do this — including a suspended account,
  /// which is the most common way this is reached.
  permission,

  /// The row is not there, or is not visible to this caller.
  notFound,

  /// The request was understood and refused for a business reason: a closed
  /// store, an empty cart, a coupon that does not apply.
  rejected,

  /// The server broke.
  server,

  /// Nothing above fit.
  unknown,
}

/// A single, typed description of any failure the app can produce.
///
/// Before this, every screen called `readableError(e)` on a stringified
/// exception and got English back — which meant an Arabic user read English
/// errors, and anything the map did not know became "Something went wrong".
/// Failures now carry their kind and code, and the text is resolved against
/// the active locale at render time.
class AppFailure implements Exception {
  const AppFailure({required this.kind, this.code, this.cause});

  final FailureKind kind;

  /// The server's own identifier — `VENDOR_CLOSED`, `COUPON_INVALID`, a
  /// Postgres SQLSTATE — or null when the failure did not come from one.
  final String? code;

  /// Kept for logging. Never shown: it is the raw exception.
  final Object? cause;

  bool get isRetryable =>
      kind == FailureKind.network || kind == FailureKind.server;

  /// Normalises anything throwable — and a plain [String], since cubits still
  /// hold `error.toString()` in their state — into one of these.
  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;

    if (error is SocketException || error is TimeoutException) {
      return AppFailure(kind: FailureKind.network, cause: error);
    }
    if (error is AuthException) {
      return AppFailure(
        kind: FailureKind.auth,
        code: _codeIn(error.message) ?? error.message,
        cause: error,
      );
    }
    if (error is PostgrestException) {
      return AppFailure(
        kind: _kindForPostgrest(error),
        code: _codeIn(error.message) ?? error.code,
        cause: error,
      );
    }
    if (error is StorageException) {
      return AppFailure(
        kind: error.statusCode == '403'
            ? FailureKind.permission
            : FailureKind.server,
        cause: error,
      );
    }

    final text = error.toString();
    final code = _codeIn(text);
    if (code != null) {
      return AppFailure(
        kind: _knownCodes[code] ?? FailureKind.rejected,
        code: code,
        cause: error,
      );
    }
    if (_looksOffline(text)) {
      return AppFailure(kind: FailureKind.network, cause: error);
    }
    return AppFailure(kind: FailureKind.unknown, cause: error);
  }

  /// The sentence to show the user, in their language.
  String message(AppLocalizations l10n) {
    final byCode = code == null ? null : _messageForCode(code!, l10n);
    if (byCode != null) return byCode;
    return switch (kind) {
      FailureKind.network => l10n.errNetwork,
      FailureKind.auth => l10n.errSessionExpired,
      FailureKind.permission => l10n.errNoPermission,
      FailureKind.notFound => l10n.errNotFound,
      FailureKind.server => l10n.errServer,
      FailureKind.rejected || FailureKind.unknown => l10n.errUnknown,
    };
  }

  @override
  String toString() => 'AppFailure(${kind.name}, $code, $cause)';

  // ---------------------------------------------------------------------
  // Mapping
  // ---------------------------------------------------------------------

  /// Postgres refusals that reach a user, and how each one should read.
  ///
  /// A code that is not here still resolves — it falls back to its kind — so
  /// a new server error is a generic sentence rather than a crash.
  static const Map<String, FailureKind> _knownCodes = {
    'UNAUTHORIZED': FailureKind.auth,
    'FORBIDDEN': FailureKind.permission,
    'ACCOUNT_BLOCKED': FailureKind.permission,
    'CANNOT_BLOCK_SELF': FailureKind.permission,
    'CANNOT_DELETE_SELF': FailureKind.permission,
    'CANNOT_BLOCK_ADMIN': FailureKind.permission,
    'CANNOT_DELETE_ADMIN': FailureKind.permission,
    'NOT_FOUND': FailureKind.notFound,
    'TEMPLATE_NOT_FOUND': FailureKind.notFound,
    'PAYMOB_NOT_CONFIGURED': FailureKind.server,
    'PAYMOB_INTENTION_FAILED': FailureKind.server,
    'PAYMENT_GATEWAY_UNAVAILABLE': FailureKind.server,
  };

  /// Every code the app can put in front of a user, and the string for it.
  static String? _messageForCode(String code, AppLocalizations l10n) =>
      switch (code) {
        'CART_EMPTY' => l10n.errCartEmpty,
        'VENDOR_CLOSED' => l10n.errVendorClosed,
        'VENDOR_NOT_APPROVED' => l10n.errVendorNotApproved,
        'ADDRESS_NOT_FOUND' => l10n.errAddressNotFound,
        'OUTSIDE_SERVICE_AREA' => l10n.errOutsideServiceArea,
        'ROLE_ALREADY_SET' => l10n.errRoleAlreadySet,
        'ROLE_CHANGE_NOT_ALLOWED' => l10n.errRoleChangeNotAllowed,
        'COUPON_INVALID' => l10n.errCouponInvalid,
        // One code per rule, so the customer is told which rule they hit —
        // "not valid" for a code that simply has not started yet is what
        // generates support tickets.
        'COUPON_NOT_STARTED' => l10n.errCouponNotStarted,
        'COUPON_EXPIRED' => l10n.errCouponExpired,
        'COUPON_EXHAUSTED' => l10n.errCouponExhausted,
        'COUPON_ALREADY_USED' => l10n.errCouponAlreadyUsed,
        'COUPON_FIRST_ORDER_ONLY' => l10n.errCouponFirstOrderOnly,
        'COUPON_WRONG_VENDOR' => l10n.errCouponWrongVendor,
        'PLATFORM_TERMS_ADMIN_ONLY' => l10n.errPlatformTermsAdminOnly,
        'BILLING_MODEL_LOCKED' => l10n.errBillingModelLocked,
        'CANNOT_CHANGE_OWN_ROLE' => l10n.errCannotChangeOwnRole,
        'ROLE_IN_USE' => l10n.errRoleInUse,
        'NOT_AN_ADMIN' => l10n.errNotAnAdmin,
        'CREATE_FAILED' => l10n.errCreateFailed,
        'CANNOT_PROMOTE_VENDOR' => l10n.errCannotPromoteVendor,
        'CANNOT_PROMOTE_DRIVER' => l10n.errCannotPromoteDriver,
        'TIP_TOO_LARGE' => l10n.errTipTooLarge,
        'ALREADY_TIPPED' => l10n.errAlreadyTipped,
        'NO_DRIVER' => l10n.errNoDriver,
        'ORDER_NOT_DELIVERED' => l10n.errOrderNotDelivered,
        'INVALID_AMOUNT' => l10n.errInvalidAmount,
        'SCHEDULE_REQUIRED' => l10n.errScheduleRequired,
        'SCHEDULE_TOO_SOON' => l10n.errScheduleTooSoon,
        'SCHEDULE_TOO_FAR' => l10n.errScheduleTooFar,
        'COUPON_MIN_ORDER' => l10n.errCouponMinOrder,
        'MIN_ORDER_NOT_MET' => l10n.errMinOrderNotMet,
        'NOT_AN_ONLINE_DRIVER' => l10n.errNotAnOnlineDriver,
        'DRIVER_NOT_APPROVED' => l10n.errDriverNotApproved,
        'INSUFFICIENT_WALLET_BALANCE' => l10n.errInsufficientWallet,
        'PAYMOB_NOT_CONFIGURED' => l10n.errCardPaymentsUnavailable,
        'PAYMOB_INTENTION_FAILED' => l10n.errPaymentPageFailed,
        'PAYMENT_GATEWAY_UNAVAILABLE' => l10n.errPaymentPageFailed,
        'ALREADY_PAID' => l10n.errAlreadyPaid,
        'ALREADY_REFUNDED' => l10n.errAlreadyRefunded,
        'ORDER_NOT_PAID' => l10n.errOrderNotPaid,
        'ORDER_NOT_CANCELLED' => l10n.errOrderNotCancelled,
        'NOT_A_CARD_ORDER' => l10n.errNotACardOrder,
        'PRODUCT_UNAVAILABLE' => l10n.errProductUnavailable,
        'TRANSITION_NOT_ALLOWED' => l10n.errTransitionNotAllowed,
        'ACCOUNT_BLOCKED' => l10n.errAccountBlocked,
        'HAS_ACTIVE_ORDERS' => l10n.errHasActiveOrders,
        'WALLET_HAS_BALANCE' => l10n.errWalletHasBalance,
        'CANNOT_BLOCK_SELF' => l10n.errCannotBlockSelf,
        'CANNOT_DELETE_SELF' => l10n.errCannotDeleteSelf,
        'CANNOT_BLOCK_ADMIN' => l10n.errCannotBlockAdmin,
        'CANNOT_DELETE_ADMIN' => l10n.errCannotDeleteAdmin,
        'UNAUTHORIZED' => l10n.errSessionExpired,
        'FORBIDDEN' => l10n.errNoPermission,
        'TEMPLATE_NOT_FOUND' => l10n.errNotFound,
        'INVALID_LOGIN' => l10n.errInvalidLogin,
        'EMAIL_NOT_CONFIRMED' => l10n.errEmailNotConfirmed,
        'USER_ALREADY_EXISTS' => l10n.errUserAlreadyExists,
        'WEAK_PASSWORD' => l10n.errWeakPassword,
        'DUPLICATE' => l10n.errDuplicate,
        'STILL_REFERENCED' => l10n.errStillReferenced,
        // Raised by the app itself rather than the server: a cubit puts the
        // code in its state so the screen can translate it, instead of storing
        // an English sentence that no Arabic reader could use.
        'LOCATION_PERMISSION_DENIED' => l10n.errLocationPermission,
        'ORDER_TAKEN' => l10n.errOrderTaken,
        _ => null,
      };

  static FailureKind _kindForPostgrest(PostgrestException error) {
    // 42501 is Postgres' own "insufficient privilege"; PostgREST reports an
    // RLS refusal with it, and both mean the same thing to a user.
    if (error.code == '42501' ||
        error.message.contains('row-level security policy')) {
      return FailureKind.permission;
    }
    if (error.code == 'PGRST116') return FailureKind.notFound;
    if (error.code == '23505' || error.code == '23503') {
      return FailureKind.rejected;
    }
    if (error.code == '401' || error.code == 'PGRST301') {
      return FailureKind.auth;
    }
    return FailureKind.server;
  }

  /// Text the app itself never produced, so it has to be recognised by shape.
  static const _authPhrases = {
    'Invalid login credentials': 'INVALID_LOGIN',
    'Email not confirmed': 'EMAIL_NOT_CONFIRMED',
    'User already registered': 'USER_ALREADY_EXISTS',
    'Password should be at least': 'WEAK_PASSWORD',
  };

  static const _pgPhrases = {
    'row-level security policy': 'FORBIDDEN',
    'duplicate key value': 'DUPLICATE',
    'violates foreign key constraint': 'STILL_REFERENCED',
  };

  /// Pulls a `SCREAMING_SNAKE` code out of a message, which is how every RPC
  /// in this project raises one.
  static String? _codeIn(String text) {
    for (final entry in _authPhrases.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    for (final entry in _pgPhrases.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    final match = RegExp(
      r'\b([A-Z][A-Z0-9]+(?:_[A-Z0-9]+)+)\b',
    ).firstMatch(text);
    return match?.group(1);
  }

  static bool _looksOffline(String text) =>
      text.contains('SocketException') ||
      text.contains('Failed host lookup') ||
      text.contains('Connection closed') ||
      text.contains('Connection refused') ||
      text.contains('ClientException') ||
      text.contains('TimeoutException');
}
