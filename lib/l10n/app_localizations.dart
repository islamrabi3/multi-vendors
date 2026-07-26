import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @missingSupabaseConfigurationnn.
  ///
  /// In en, this message translates to:
  /// **'Missing Supabase configuration.\n\n'**
  String get missingSupabaseConfigurationnn;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @createYournaccount.
  ///
  /// In en, this message translates to:
  /// **'Create your\\naccount'**
  String get createYournaccount;

  /// No description provided for @howWillYouUseEaty.
  ///
  /// In en, this message translates to:
  /// **'How will you use Eaty?'**
  String get howWillYouUseEaty;

  /// No description provided for @continueText.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueText;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @nameemailcom.
  ///
  /// In en, this message translates to:
  /// **'name@email.com'**
  String get nameemailcom;

  /// No description provided for @passwordMin6Chars.
  ///
  /// In en, this message translates to:
  /// **'Password (min 6 chars)'**
  String get passwordMin6Chars;

  /// No description provided for @eaty.
  ///
  /// In en, this message translates to:
  /// **'eaty'**
  String get eaty;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @logInToPickUpWhereYouLeftOff.
  ///
  /// In en, this message translates to:
  /// **'Log in to pick up where you left off.'**
  String get logInToPickUpWhereYouLeftOff;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @logIn.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get logIn;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @apple.
  ///
  /// In en, this message translates to:
  /// **'Apple'**
  String get apple;

  /// No description provided for @google.
  ///
  /// In en, this message translates to:
  /// **'Google'**
  String get google;

  /// No description provided for @newHere.
  ///
  /// In en, this message translates to:
  /// **'New here? '**
  String get newHere;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get createAccount;

  /// No description provided for @saraemailcom.
  ///
  /// In en, this message translates to:
  /// **'sara@email.com'**
  String get saraemailcom;

  /// No description provided for @emptyString.
  ///
  /// In en, this message translates to:
  /// **'••••••••'**
  String get emptyString;

  /// No description provided for @setUpYourStore.
  ///
  /// In en, this message translates to:
  /// **'Set up your store'**
  String get setUpYourStore;

  /// No description provided for @openMyStore.
  ///
  /// In en, this message translates to:
  /// **'Open my store'**
  String get openMyStore;

  /// No description provided for @storeName.
  ///
  /// In en, this message translates to:
  /// **'Store name'**
  String get storeName;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @storePhone.
  ///
  /// In en, this message translates to:
  /// **'Store phone'**
  String get storePhone;

  /// No description provided for @storeAddress.
  ///
  /// In en, this message translates to:
  /// **'Store address'**
  String get storeAddress;

  /// No description provided for @deliveryFeeEgp.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee (EGP)'**
  String get deliveryFeeEgp;

  /// No description provided for @minOrderEgp.
  ///
  /// In en, this message translates to:
  /// **'Min order (EGP)'**
  String get minOrderEgp;

  /// No description provided for @averagePrepTimeMinutes.
  ///
  /// In en, this message translates to:
  /// **'Average prep time (minutes)'**
  String get averagePrepTimeMinutes;

  /// No description provided for @cravingsDelivered.
  ///
  /// In en, this message translates to:
  /// **'Cravings, delivered.'**
  String get cravingsDelivered;

  /// No description provided for @getStarted.
  ///
  /// In en, this message translates to:
  /// **'Get started'**
  String get getStarted;

  /// No description provided for @iAlreadyHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'I already have an account'**
  String get iAlreadyHaveAnAccount;

  /// No description provided for @availableNearby.
  ///
  /// In en, this message translates to:
  /// **'Available nearby'**
  String get availableNearby;

  /// No description provided for @payout.
  ///
  /// In en, this message translates to:
  /// **'payout'**
  String get payout;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @earnings.
  ///
  /// In en, this message translates to:
  /// **'Earnings'**
  String get earnings;

  /// No description provided for @recentTrips.
  ///
  /// In en, this message translates to:
  /// **'Recent trips'**
  String get recentTrips;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @headToDropoff.
  ///
  /// In en, this message translates to:
  /// **'Head to drop-off'**
  String get headToDropoff;

  /// No description provided for @markDelivered.
  ///
  /// In en, this message translates to:
  /// **'Mark delivered'**
  String get markDelivered;

  /// No description provided for @vendors.
  ///
  /// In en, this message translates to:
  /// **'Vendors'**
  String get vendors;

  /// No description provided for @reject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get reject;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @rejectVendor.
  ///
  /// In en, this message translates to:
  /// **'Reject vendor?'**
  String get rejectVendor;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @cancelRefundOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel & refund order'**
  String get cancelRefundOrder;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel order'**
  String get cancelOrder;

  /// No description provided for @driver.
  ///
  /// In en, this message translates to:
  /// **'DRIVER'**
  String get driver;

  /// No description provided for @assign.
  ///
  /// In en, this message translates to:
  /// **'Assign'**
  String get assign;

  /// No description provided for @assignADriver.
  ///
  /// In en, this message translates to:
  /// **'Assign a driver'**
  String get assignADriver;

  /// No description provided for @noDriversAreOnlineRightNow.
  ///
  /// In en, this message translates to:
  /// **'No drivers are online right now.'**
  String get noDriversAreOnlineRightNow;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @promos.
  ///
  /// In en, this message translates to:
  /// **'Promos'**
  String get promos;

  /// No description provided for @newBanner.
  ///
  /// In en, this message translates to:
  /// **'New banner'**
  String get newBanner;

  /// No description provided for @newCoupon.
  ///
  /// In en, this message translates to:
  /// **'New coupon'**
  String get newCoupon;

  /// No description provided for @newText.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get newText;

  /// No description provided for @deleteBanner.
  ///
  /// In en, this message translates to:
  /// **'Delete banner?'**
  String get deleteBanner;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteCoupon.
  ///
  /// In en, this message translates to:
  /// **'Delete coupon?'**
  String get deleteCoupon;

  /// No description provided for @publishBanner.
  ///
  /// In en, this message translates to:
  /// **'Publish banner'**
  String get publishBanner;

  /// No description provided for @percentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get percentage;

  /// No description provided for @fixedEgp.
  ///
  /// In en, this message translates to:
  /// **'Fixed EGP'**
  String get fixedEgp;

  /// No description provided for @createCoupon.
  ///
  /// In en, this message translates to:
  /// **'Create coupon'**
  String get createCoupon;

  /// No description provided for @titleEg40OffFirstOrder.
  ///
  /// In en, this message translates to:
  /// **'Title · e.g. 40% off first order'**
  String get titleEg40OffFirstOrder;

  /// No description provided for @subtitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Subtitle (optional)'**
  String get subtitleOptional;

  /// No description provided for @promoCodeOptional.
  ///
  /// In en, this message translates to:
  /// **'Promo code (optional)'**
  String get promoCodeOptional;

  /// No description provided for @imageUrl.
  ///
  /// In en, this message translates to:
  /// **'Image URL'**
  String get imageUrl;

  /// No description provided for @codeEgEaty40.
  ///
  /// In en, this message translates to:
  /// **'Code · e.g. EATY40'**
  String get codeEgEaty40;

  /// No description provided for @minOrderOptional.
  ///
  /// In en, this message translates to:
  /// **'Min order (optional)'**
  String get minOrderOptional;

  /// No description provided for @maxDiscountCapOptional.
  ///
  /// In en, this message translates to:
  /// **'Max discount cap (optional)'**
  String get maxDiscountCapOptional;

  /// No description provided for @usageLimitOptional.
  ///
  /// In en, this message translates to:
  /// **'Usage limit (optional)'**
  String get usageLimitOptional;

  /// No description provided for @liveOrders.
  ///
  /// In en, this message translates to:
  /// **'Live orders'**
  String get liveOrders;

  /// No description provided for @eatyPlatformToday.
  ///
  /// In en, this message translates to:
  /// **'EATY PLATFORM · TODAY'**
  String get eatyPlatformToday;

  /// No description provided for @liveOverview.
  ///
  /// In en, this message translates to:
  /// **'Live overview'**
  String get liveOverview;

  /// No description provided for @grossMerchandiseValue.
  ///
  /// In en, this message translates to:
  /// **'Gross merchandise value'**
  String get grossMerchandiseValue;

  /// No description provided for @a.
  ///
  /// In en, this message translates to:
  /// **'A'**
  String get a;

  /// No description provided for @on.
  ///
  /// In en, this message translates to:
  /// **'on'**
  String get on;

  /// No description provided for @updating.
  ///
  /// In en, this message translates to:
  /// **'Updating'**
  String get updating;

  /// No description provided for @deliverTo.
  ///
  /// In en, this message translates to:
  /// **'DELIVER TO'**
  String get deliverTo;

  /// No description provided for @home12TahrirSt.
  ///
  /// In en, this message translates to:
  /// **'Home · 12 Tahrir St'**
  String get home12TahrirSt;

  /// No description provided for @s40OffYournfirstOrder.
  ///
  /// In en, this message translates to:
  /// **'40% off your\\nfirst order'**
  String get s40OffYournfirstOrder;

  /// No description provided for @codeEaty40.
  ///
  /// In en, this message translates to:
  /// **'CODE · EATY40'**
  String get codeEaty40;

  /// No description provided for @storesNearYou.
  ///
  /// In en, this message translates to:
  /// **'Stores near you'**
  String get storesNearYou;

  /// No description provided for @sort.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sort;

  /// No description provided for @searchStoresDishes.
  ///
  /// In en, this message translates to:
  /// **'Search stores & dishes…'**
  String get searchStoresDishes;

  /// No description provided for @startANewCart.
  ///
  /// In en, this message translates to:
  /// **'Start a new cart?'**
  String get startANewCart;

  /// No description provided for @keepCart.
  ///
  /// In en, this message translates to:
  /// **'Keep cart'**
  String get keepCart;

  /// No description provided for @startNewCart.
  ///
  /// In en, this message translates to:
  /// **'Start new cart'**
  String get startNewCart;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to cart'**
  String get addToCart;

  /// No description provided for @notesEgNoOnions.
  ///
  /// In en, this message translates to:
  /// **'Notes (e.g. no onions)'**
  String get notesEgNoOnions;

  /// No description provided for @viewCart.
  ///
  /// In en, this message translates to:
  /// **'View cart'**
  String get viewCart;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @addADeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Add a delivery address'**
  String get addADeliveryAddress;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @standard2535Min.
  ///
  /// In en, this message translates to:
  /// **'Standard · 25–35 min'**
  String get standard2535Min;

  /// No description provided for @arrivesBy935Pm.
  ///
  /// In en, this message translates to:
  /// **'Arrives by 9:35 PM'**
  String get arrivesBy935Pm;

  /// No description provided for @coupon.
  ///
  /// In en, this message translates to:
  /// **'Coupon'**
  String get coupon;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @couponCode.
  ///
  /// In en, this message translates to:
  /// **'Coupon code'**
  String get couponCode;

  /// No description provided for @orderNotesOptional.
  ///
  /// In en, this message translates to:
  /// **'Order notes (optional)'**
  String get orderNotesOptional;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @logOut.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logOut;

  /// No description provided for @myAddresses.
  ///
  /// In en, this message translates to:
  /// **'My addresses'**
  String get myAddresses;

  /// No description provided for @tapTheMapToDropYourPin.
  ///
  /// In en, this message translates to:
  /// **'Tap the map to drop your pin'**
  String get tapTheMapToDropYourPin;

  /// No description provided for @defaultAddress.
  ///
  /// In en, this message translates to:
  /// **'Default address'**
  String get defaultAddress;

  /// No description provided for @saveAddress.
  ///
  /// In en, this message translates to:
  /// **'Save address'**
  String get saveAddress;

  /// No description provided for @labelHomeWork.
  ///
  /// In en, this message translates to:
  /// **'Label (Home, Work…)'**
  String get labelHomeWork;

  /// No description provided for @street.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get street;

  /// No description provided for @building.
  ///
  /// In en, this message translates to:
  /// **'Building'**
  String get building;

  /// No description provided for @floor.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get floor;

  /// No description provided for @apt.
  ///
  /// In en, this message translates to:
  /// **'Apt'**
  String get apt;

  /// No description provided for @deliveryNotes.
  ///
  /// In en, this message translates to:
  /// **'Delivery notes'**
  String get deliveryNotes;

  /// No description provided for @yourCart.
  ///
  /// In en, this message translates to:
  /// **'Your cart'**
  String get yourCart;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @goToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Go to checkout'**
  String get goToCheckout;

  /// No description provided for @orderDetails.
  ///
  /// In en, this message translates to:
  /// **'Order details'**
  String get orderDetails;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @rateThisOrder.
  ///
  /// In en, this message translates to:
  /// **'Rate this order'**
  String get rateThisOrder;

  /// No description provided for @yourRiderIsOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'Your rider is on the way!'**
  String get yourRiderIsOnTheWay;

  /// No description provided for @yourDeliveryDriver.
  ///
  /// In en, this message translates to:
  /// **'Your delivery driver'**
  String get yourDeliveryDriver;

  /// No description provided for @call.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get call;

  /// No description provided for @payNow.
  ///
  /// In en, this message translates to:
  /// **'Pay now'**
  String get payNow;

  /// No description provided for @howWasYourOrder.
  ///
  /// In en, this message translates to:
  /// **'How was your order?'**
  String get howWasYourOrder;

  /// No description provided for @submitReview.
  ///
  /// In en, this message translates to:
  /// **'Submit review'**
  String get submitReview;

  /// No description provided for @commentOptional.
  ///
  /// In en, this message translates to:
  /// **'Comment (optional)'**
  String get commentOptional;

  /// No description provided for @tapToTrack.
  ///
  /// In en, this message translates to:
  /// **'Tap to track'**
  String get tapToTrack;

  /// No description provided for @track.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get track;

  /// No description provided for @rejectOrder.
  ///
  /// In en, this message translates to:
  /// **'Reject order'**
  String get rejectOrder;

  /// No description provided for @acceptOrder.
  ///
  /// In en, this message translates to:
  /// **'Accept order'**
  String get acceptOrder;

  /// No description provided for @startPreparing.
  ///
  /// In en, this message translates to:
  /// **'Start preparing'**
  String get startPreparing;

  /// No description provided for @markReadyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Mark ready for pickup'**
  String get markReadyForPickup;

  /// No description provided for @waitingForADriver.
  ///
  /// In en, this message translates to:
  /// **'Waiting for a driver…'**
  String get waitingForADriver;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @menu.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menu;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @sectionName.
  ///
  /// In en, this message translates to:
  /// **'Section name'**
  String get sectionName;

  /// No description provided for @addSection.
  ///
  /// In en, this message translates to:
  /// **'Add section'**
  String get addSection;

  /// No description provided for @deleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Delete product?'**
  String get deleteProduct;

  /// No description provided for @newOptionGroup.
  ///
  /// In en, this message translates to:
  /// **'New option group'**
  String get newOptionGroup;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @selectSection.
  ///
  /// In en, this message translates to:
  /// **'Select section'**
  String get selectSection;

  /// No description provided for @availableForOrdering.
  ///
  /// In en, this message translates to:
  /// **'Available for ordering'**
  String get availableForOrdering;

  /// No description provided for @addGroup.
  ///
  /// In en, this message translates to:
  /// **'Add group'**
  String get addGroup;

  /// No description provided for @saveTheProductFirstToAddOptionGroups.
  ///
  /// In en, this message translates to:
  /// **'Save the product first to add option groups.'**
  String get saveTheProductFirstToAddOptionGroups;

  /// No description provided for @noOptionGroupsYet.
  ///
  /// In en, this message translates to:
  /// **'No option groups yet.'**
  String get noOptionGroupsYet;

  /// No description provided for @nameSizeAddons.
  ///
  /// In en, this message translates to:
  /// **'Name (Size, Add-ons…)'**
  String get nameSizeAddons;

  /// No description provided for @minSelect.
  ///
  /// In en, this message translates to:
  /// **'Min select'**
  String get minSelect;

  /// No description provided for @maxSelect.
  ///
  /// In en, this message translates to:
  /// **'Max select'**
  String get maxSelect;

  /// No description provided for @optionName.
  ///
  /// In en, this message translates to:
  /// **'Option name'**
  String get optionName;

  /// No description provided for @extraPriceEgp.
  ///
  /// In en, this message translates to:
  /// **'Extra price (EGP)'**
  String get extraPriceEgp;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Product name'**
  String get productName;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @section.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get section;

  /// No description provided for @addOption.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get addOption;

  /// No description provided for @deleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete group'**
  String get deleteGroup;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @appLanguage.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get appLanguage;

  /// No description provided for @changeLanguage.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get changeLanguage;

  /// No description provided for @missingSupabaseConfigurationnn1.
  ///
  /// In en, this message translates to:
  /// **'Missing Supabase configuration.\\\\n\\\\n'**
  String get missingSupabaseConfigurationnn1;

  /// No description provided for @multiVendor.
  ///
  /// In en, this message translates to:
  /// **'Multi Vendor'**
  String get multiVendor;

  /// No description provided for @orderFood.
  ///
  /// In en, this message translates to:
  /// **'Order food'**
  String get orderFood;

  /// No description provided for @sellAsAVendor.
  ///
  /// In en, this message translates to:
  /// **'Sell as a vendor'**
  String get sellAsAVendor;

  /// No description provided for @deliverOrders.
  ///
  /// In en, this message translates to:
  /// **'Deliver orders'**
  String get deliverOrders;

  /// No description provided for @available.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get available;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @goOnlineToSeeAvailableOrders.
  ///
  /// In en, this message translates to:
  /// **'Go online to see available orders'**
  String get goOnlineToSeeAvailableOrders;

  /// No description provided for @noOrdersWaitingForPickup.
  ///
  /// In en, this message translates to:
  /// **'No orders waiting for pickup'**
  String get noOrdersWaitingForPickup;

  /// No description provided for @orderClaimedHeadToTheStore.
  ///
  /// In en, this message translates to:
  /// **'Order claimed — head to the store!'**
  String get orderClaimedHeadToTheStore;

  /// No description provided for @noDeliveriesYet.
  ///
  /// In en, this message translates to:
  /// **'No deliveries yet'**
  String get noDeliveriesYet;

  /// No description provided for @pickedUp.
  ///
  /// In en, this message translates to:
  /// **'Picked up'**
  String get pickedUp;

  /// No description provided for @noActiveDeliverynpullToRefresh.
  ///
  /// In en, this message translates to:
  /// **'No active delivery.\\nPull to refresh · or claim one from Available.'**
  String get noActiveDeliverynpullToRefresh;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @suspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspended;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed;

  /// No description provided for @noVendorsHere.
  ///
  /// In en, this message translates to:
  /// **'No vendors here'**
  String get noVendorsHere;

  /// No description provided for @couldNotLoadThisOrder.
  ///
  /// In en, this message translates to:
  /// **'Could not load this order.'**
  String get couldNotLoadThisOrder;

  /// No description provided for @orderCancelled.
  ///
  /// In en, this message translates to:
  /// **'This order was cancelled.'**
  String get orderCancelled;

  /// No description provided for @noOrdersInThisView.
  ///
  /// In en, this message translates to:
  /// **'No orders in this view'**
  String get noOrdersInThisView;

  /// No description provided for @addATitleOrImageFirst.
  ///
  /// In en, this message translates to:
  /// **'Add a title or image first.'**
  String get addATitleOrImageFirst;

  /// No description provided for @bannerPublished.
  ///
  /// In en, this message translates to:
  /// **'Banner published'**
  String get bannerPublished;

  /// No description provided for @enterACodeAndAValidDiscount.
  ///
  /// In en, this message translates to:
  /// **'Enter a code and a valid discount.'**
  String get enterACodeAndAValidDiscount;

  /// No description provided for @couponCreated.
  ///
  /// In en, this message translates to:
  /// **'Coupon created'**
  String get couponCreated;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pending;

  /// No description provided for @suspended1.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get suspended1;

  /// No description provided for @active1.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active1;

  /// No description provided for @couldNotLoadThisVendor.
  ///
  /// In en, this message translates to:
  /// **'Could not load this vendor.'**
  String get couldNotLoadThisVendor;

  /// No description provided for @drivers.
  ///
  /// In en, this message translates to:
  /// **'Drivers'**
  String get drivers;

  /// No description provided for @ordersNeedAttention.
  ///
  /// In en, this message translates to:
  /// **'Orders need attention'**
  String get ordersNeedAttention;

  /// No description provided for @vendorsToApprove.
  ///
  /// In en, this message translates to:
  /// **'Vendors to approve'**
  String get vendorsToApprove;

  /// No description provided for @noLiveOrdersRightNow.
  ///
  /// In en, this message translates to:
  /// **'No live orders right now'**
  String get noLiveOrdersRightNow;

  /// No description provided for @useCodeEaty40ToGetThisOffer.
  ///
  /// In en, this message translates to:
  /// **'Use code EATY40 to get this offer.'**
  String get useCodeEaty40ToGetThisOffer;

  /// No description provided for @openNow.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get openNow;

  /// No description provided for @closed1.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closed1;

  /// No description provided for @couldNotLoadStores.
  ///
  /// In en, this message translates to:
  /// **'Could not load stores.'**
  String get couldNotLoadStores;

  /// No description provided for @noStoresFound.
  ///
  /// In en, this message translates to:
  /// **'No stores found'**
  String get noStoresFound;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @addedToCart.
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get addedToCart;

  /// No description provided for @couldNotLoadThisStore.
  ///
  /// In en, this message translates to:
  /// **'Could not load this store.'**
  String get couldNotLoadThisStore;

  /// No description provided for @menuComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Menu coming soon'**
  String get menuComingSoon;

  /// No description provided for @thisStoreIsCurrentlyClosed.
  ///
  /// In en, this message translates to:
  /// **'This store is currently closed.'**
  String get thisStoreIsCurrentlyClosed;

  /// No description provided for @deliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get deliveryFee;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @cashOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery'**
  String get cashOnDelivery;

  /// No description provided for @cardPaymob.
  ///
  /// In en, this message translates to:
  /// **'Card · Paymob'**
  String get cardPaymob;

  /// No description provided for @yourCartIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get yourCartIsEmpty;

  /// No description provided for @noFavoritesYet.
  ///
  /// In en, this message translates to:
  /// **'No favorites yet'**
  String get noFavoritesYet;

  /// No description provided for @points.
  ///
  /// In en, this message translates to:
  /// **'Points'**
  String get points;

  /// No description provided for @addresses.
  ///
  /// In en, this message translates to:
  /// **'Addresses'**
  String get addresses;

  /// No description provided for @paymentMethods.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get paymentMethods;

  /// No description provided for @noAddressesYet.
  ///
  /// In en, this message translates to:
  /// **'No addresses yet'**
  String get noAddressesYet;

  /// No description provided for @locationPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Location permission denied'**
  String get locationPermissionDenied;

  /// No description provided for @couldNotGetYourLocation.
  ///
  /// In en, this message translates to:
  /// **'Could not get your location'**
  String get couldNotGetYourLocation;

  /// No description provided for @yourCartIsEmpty1.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get yourCartIsEmpty1;

  /// No description provided for @deliveryFee1.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get deliveryFee1;

  /// No description provided for @discount1.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount1;

  /// No description provided for @orderNotFound.
  ///
  /// In en, this message translates to:
  /// **'Order not found.'**
  String get orderNotFound;

  /// No description provided for @couldNotStartTheCall.
  ///
  /// In en, this message translates to:
  /// **'Could not start the call.'**
  String get couldNotStartTheCall;

  /// No description provided for @thanksForYourReview.
  ///
  /// In en, this message translates to:
  /// **'Thanks for your review!'**
  String get thanksForYourReview;

  /// No description provided for @active2.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active2;

  /// No description provided for @past.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get past;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @reorder.
  ///
  /// In en, this message translates to:
  /// **'Reorder'**
  String get reorder;

  /// No description provided for @nothingHereRightNow.
  ///
  /// In en, this message translates to:
  /// **'Nothing here right now'**
  String get nothingHereRightNow;

  /// No description provided for @newOrderReceived.
  ///
  /// In en, this message translates to:
  /// **'🔔 New order received!'**
  String get newOrderReceived;

  /// No description provided for @couldNotLoadTheMenu.
  ///
  /// In en, this message translates to:
  /// **'Could not load the menu.'**
  String get couldNotLoadTheMenu;

  /// No description provided for @addASectionThenYourFirstProduct.
  ///
  /// In en, this message translates to:
  /// **'Add a section, then your first product'**
  String get addASectionThenYourFirstProduct;

  /// No description provided for @noItemsInThisSectionYet.
  ///
  /// In en, this message translates to:
  /// **'No items in this section yet'**
  String get noItemsInThisSectionYet;

  /// No description provided for @productSaved.
  ///
  /// In en, this message translates to:
  /// **'Product saved'**
  String get productSaved;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @deliveryFee2.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get deliveryFee2;

  /// No description provided for @minimumOrder.
  ///
  /// In en, this message translates to:
  /// **'Minimum order'**
  String get minimumOrder;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// No description provided for @deliveryFee3.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee'**
  String get deliveryFee3;

  /// No description provided for @minimumOrder1.
  ///
  /// In en, this message translates to:
  /// **'Minimum order'**
  String get minimumOrder1;

  /// No description provided for @avgPrepTime.
  ///
  /// In en, this message translates to:
  /// **'Avg prep time'**
  String get avgPrepTime;

  /// No description provided for @couldNotStartTheCall1.
  ///
  /// In en, this message translates to:
  /// **'Could not start the call.'**
  String get couldNotStartTheCall1;

  /// No description provided for @ready.
  ///
  /// In en, this message translates to:
  /// **'ready'**
  String get ready;

  /// No description provided for @goodMorning.
  ///
  /// In en, this message translates to:
  /// **'Good morning'**
  String get goodMorning;

  /// No description provided for @goodAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Good afternoon'**
  String get goodAfternoon;

  /// No description provided for @goodEvening.
  ///
  /// In en, this message translates to:
  /// **'Good evening'**
  String get goodEvening;

  /// No description provided for @there.
  ///
  /// In en, this message translates to:
  /// **'there'**
  String get there;

  /// No description provided for @youAreOnline.
  ///
  /// In en, this message translates to:
  /// **'You\'re online'**
  String get youAreOnline;

  /// No description provided for @youAreOffline.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get youAreOffline;

  /// No description provided for @earnedToday.
  ///
  /// In en, this message translates to:
  /// **'Earned today'**
  String get earnedToday;

  /// No description provided for @trips.
  ///
  /// In en, this message translates to:
  /// **'Trips'**
  String get trips;

  /// No description provided for @inThePool.
  ///
  /// In en, this message translates to:
  /// **'In the pool'**
  String get inThePool;

  /// No description provided for @claimCollect.
  ///
  /// In en, this message translates to:
  /// **'Claim · collect'**
  String get claimCollect;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'cash'**
  String get cash;

  /// No description provided for @claimDelivery.
  ///
  /// In en, this message translates to:
  /// **'Claim delivery'**
  String get claimDelivery;

  /// No description provided for @km.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get km;

  /// No description provided for @store.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get store;

  /// No description provided for @customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customer;

  /// No description provided for @collect.
  ///
  /// In en, this message translates to:
  /// **'Collect'**
  String get collect;

  /// No description provided for @inCash.
  ///
  /// In en, this message translates to:
  /// **'in cash'**
  String get inCash;

  /// No description provided for @paidOnlineNothingToCollect.
  ///
  /// In en, this message translates to:
  /// **'Paid online — nothing to collect'**
  String get paidOnlineNothingToCollect;

  /// No description provided for @egp.
  ///
  /// In en, this message translates to:
  /// **'EGP'**
  String get egp;

  /// No description provided for @mondayInitial.
  ///
  /// In en, this message translates to:
  /// **'M'**
  String get mondayInitial;

  /// No description provided for @tuesdayInitial.
  ///
  /// In en, this message translates to:
  /// **'T'**
  String get tuesdayInitial;

  /// No description provided for @wednesdayInitial.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get wednesdayInitial;

  /// No description provided for @thursdayInitial.
  ///
  /// In en, this message translates to:
  /// **'T'**
  String get thursdayInitial;

  /// No description provided for @fridayInitial.
  ///
  /// In en, this message translates to:
  /// **'F'**
  String get fridayInitial;

  /// No description provided for @saturdayInitial.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get saturdayInitial;

  /// No description provided for @sundayInitial.
  ///
  /// In en, this message translates to:
  /// **'S'**
  String get sundayInitial;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @avgPrep.
  ///
  /// In en, this message translates to:
  /// **'Avg prep'**
  String get avgPrep;

  /// No description provided for @cod.
  ///
  /// In en, this message translates to:
  /// **'COD'**
  String get cod;

  /// No description provided for @cardPaid.
  ///
  /// In en, this message translates to:
  /// **'Card · paid'**
  String get cardPaid;

  /// No description provided for @cardUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Card · unpaid'**
  String get cardUnpaid;

  /// No description provided for @unavailable.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailable;

  /// No description provided for @newSection.
  ///
  /// In en, this message translates to:
  /// **'New section'**
  String get newSection;

  /// No description provided for @renameSection.
  ///
  /// In en, this message translates to:
  /// **'Rename section'**
  String get renameSection;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @soldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold out'**
  String get soldOut;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @fromTheMenu.
  ///
  /// In en, this message translates to:
  /// **'from the menu?'**
  String get fromTheMenu;

  /// No description provided for @addOptionTo.
  ///
  /// In en, this message translates to:
  /// **'Add option to'**
  String get addOptionTo;

  /// No description provided for @newProduct.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get newProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get editProduct;

  /// No description provided for @tapToChangePhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to change photo'**
  String get tapToChangePhoto;

  /// No description provided for @tapToAddPhoto.
  ///
  /// In en, this message translates to:
  /// **'Tap to add photo'**
  String get tapToAddPhoto;

  /// No description provided for @basicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic info'**
  String get basicInfo;

  /// No description provided for @customersCanAddThisToTheirCart.
  ///
  /// In en, this message translates to:
  /// **'Customers can add this to their cart'**
  String get customersCanAddThisToTheirCart;

  /// No description provided for @hiddenFromCustomers.
  ///
  /// In en, this message translates to:
  /// **'Hidden from customers'**
  String get hiddenFromCustomers;

  /// No description provided for @pricingAndCategory.
  ///
  /// In en, this message translates to:
  /// **'Pricing & category'**
  String get pricingAndCategory;

  /// No description provided for @enterAValidPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid price'**
  String get enterAValidPrice;

  /// No description provided for @noSectionsAddOneFirst.
  ///
  /// In en, this message translates to:
  /// **'No sections — add one first'**
  String get noSectionsAddOneFirst;

  /// No description provided for @options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get options;

  /// No description provided for @createProduct.
  ///
  /// In en, this message translates to:
  /// **'Create product'**
  String get createProduct;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get saveChanges;

  /// No description provided for @pick.
  ///
  /// In en, this message translates to:
  /// **'Pick'**
  String get pick;

  /// No description provided for @storeIsOpen.
  ///
  /// In en, this message translates to:
  /// **'Store is open'**
  String get storeIsOpen;

  /// No description provided for @storeIsClosed.
  ///
  /// In en, this message translates to:
  /// **'Store is closed'**
  String get storeIsClosed;

  /// No description provided for @acceptingOrdersNow.
  ///
  /// In en, this message translates to:
  /// **'Accepting orders now'**
  String get acceptingOrdersNow;

  /// No description provided for @customersCantOrder.
  ///
  /// In en, this message translates to:
  /// **'Customers can’t order'**
  String get customersCantOrder;

  /// No description provided for @storeProfile.
  ///
  /// In en, this message translates to:
  /// **'Store profile'**
  String get storeProfile;

  /// No description provided for @addADescription.
  ///
  /// In en, this message translates to:
  /// **'Add a description'**
  String get addADescription;

  /// No description provided for @feesAndOrders.
  ///
  /// In en, this message translates to:
  /// **'Fees & orders'**
  String get feesAndOrders;

  /// No description provided for @minShort.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get minShort;

  /// No description provided for @preferences.
  ///
  /// In en, this message translates to:
  /// **'Preferences'**
  String get preferences;

  /// No description provided for @autoAcceptOrders.
  ///
  /// In en, this message translates to:
  /// **'Auto-accept orders'**
  String get autoAcceptOrders;

  /// No description provided for @newOrderSound.
  ///
  /// In en, this message translates to:
  /// **'New-order sound'**
  String get newOrderSound;

  /// No description provided for @noteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note: '**
  String get noteLabel;

  /// No description provided for @totalCashOnDelivery.
  ///
  /// In en, this message translates to:
  /// **'Total · Cash on delivery'**
  String get totalCashOnDelivery;

  /// No description provided for @totalCardPaid.
  ///
  /// In en, this message translates to:
  /// **'Total · Card (paid)'**
  String get totalCardPaid;

  /// No description provided for @totalCardUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Total · Card (unpaid)'**
  String get totalCardUnpaid;

  /// No description provided for @awaitingApproval.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get awaitingApproval;

  /// No description provided for @willBeSuspendedAndHiddenFromCustomers.
  ///
  /// In en, this message translates to:
  /// **'will be suspended and hidden from customers.'**
  String get willBeSuspendedAndHiddenFromCustomers;

  /// No description provided for @ratings.
  ///
  /// In en, this message translates to:
  /// **'ratings'**
  String get ratings;

  /// No description provided for @stuck.
  ///
  /// In en, this message translates to:
  /// **'Stuck'**
  String get stuck;

  /// No description provided for @mShort.
  ///
  /// In en, this message translates to:
  /// **'m'**
  String get mShort;

  /// No description provided for @assignedTo.
  ///
  /// In en, this message translates to:
  /// **'Assigned to'**
  String get assignedTo;

  /// No description provided for @cancelledByAdmin.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by admin'**
  String get cancelledByAdmin;

  /// No description provided for @placed.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get placed;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @stuckIn.
  ///
  /// In en, this message translates to:
  /// **'Stuck in'**
  String get stuckIn;

  /// No description provided for @pastSlaNoDriverAssigned.
  ///
  /// In en, this message translates to:
  /// **'Past SLA · no driver assigned'**
  String get pastSlaNoDriverAssigned;

  /// No description provided for @pastSla.
  ///
  /// In en, this message translates to:
  /// **'Past SLA'**
  String get pastSla;

  /// No description provided for @stalledSuffix.
  ///
  /// In en, this message translates to:
  /// **' — stalled'**
  String get stalledSuffix;

  /// No description provided for @assigned.
  ///
  /// In en, this message translates to:
  /// **'Assigned'**
  String get assigned;

  /// No description provided for @notAssigned.
  ///
  /// In en, this message translates to:
  /// **'Not assigned'**
  String get notAssigned;

  /// No description provided for @order.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get order;

  /// No description provided for @live.
  ///
  /// In en, this message translates to:
  /// **'live'**
  String get live;

  /// No description provided for @flagged.
  ///
  /// In en, this message translates to:
  /// **'Flagged'**
  String get flagged;

  /// No description provided for @noDriverAssignedPastSla.
  ///
  /// In en, this message translates to:
  /// **'No driver assigned · past SLA'**
  String get noDriverAssignedPastSla;

  /// No description provided for @runningLatePastSla.
  ///
  /// In en, this message translates to:
  /// **'Running late · past SLA'**
  String get runningLatePastSla;

  /// No description provided for @justNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In en, this message translates to:
  /// **'m ago'**
  String get minutesAgo;

  /// No description provided for @hoursAgo.
  ///
  /// In en, this message translates to:
  /// **'h ago'**
  String get hoursAgo;

  /// No description provided for @daysAgo.
  ///
  /// In en, this message translates to:
  /// **'d ago'**
  String get daysAgo;

  /// No description provided for @untitledBanner.
  ///
  /// In en, this message translates to:
  /// **'Untitled banner'**
  String get untitledBanner;

  /// No description provided for @hidden.
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get hidden;

  /// No description provided for @willBeRemoved.
  ///
  /// In en, this message translates to:
  /// **'will be removed.'**
  String get willBeRemoved;

  /// No description provided for @noBannersYetTapNew.
  ///
  /// In en, this message translates to:
  /// **'No banners yet. Tap \"New\" to add one.'**
  String get noBannersYetTapNew;

  /// No description provided for @noCouponsYetTapNew.
  ///
  /// In en, this message translates to:
  /// **'No coupons yet. Tap \"New\" to add one.'**
  String get noCouponsYetTapNew;

  /// No description provided for @max.
  ///
  /// In en, this message translates to:
  /// **'max'**
  String get max;

  /// No description provided for @min.
  ///
  /// In en, this message translates to:
  /// **'min'**
  String get min;

  /// No description provided for @expired.
  ///
  /// In en, this message translates to:
  /// **'expired'**
  String get expired;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'off'**
  String get off;

  /// No description provided for @used.
  ///
  /// In en, this message translates to:
  /// **'used'**
  String get used;

  /// No description provided for @vendorApproved.
  ///
  /// In en, this message translates to:
  /// **'Vendor approved'**
  String get vendorApproved;

  /// No description provided for @vendorSuspended.
  ///
  /// In en, this message translates to:
  /// **'Vendor suspended'**
  String get vendorSuspended;

  /// No description provided for @ownerAndContact.
  ///
  /// In en, this message translates to:
  /// **'Owner & contact'**
  String get ownerAndContact;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @suspend.
  ///
  /// In en, this message translates to:
  /// **'Suspend'**
  String get suspend;

  /// No description provided for @approveVendor.
  ///
  /// In en, this message translates to:
  /// **'Approve vendor'**
  String get approveVendor;

  /// No description provided for @reactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get reactivate;

  /// No description provided for @accepted.
  ///
  /// In en, this message translates to:
  /// **'Accepted'**
  String get accepted;

  /// No description provided for @preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get preparing;

  /// No description provided for @readyForPickup.
  ///
  /// In en, this message translates to:
  /// **'Ready for pickup'**
  String get readyForPickup;

  /// No description provided for @outForDelivery.
  ///
  /// In en, this message translates to:
  /// **'Out for delivery'**
  String get outForDelivery;

  /// No description provided for @delivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get delivered;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelled;

  /// No description provided for @rejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get rejected;

  /// No description provided for @homeBanners.
  ///
  /// In en, this message translates to:
  /// **'Home banners'**
  String get homeBanners;

  /// No description provided for @coupons.
  ///
  /// In en, this message translates to:
  /// **'Coupons'**
  String get coupons;

  /// No description provided for @discountPercent.
  ///
  /// In en, this message translates to:
  /// **'Discount %'**
  String get discountPercent;

  /// No description provided for @discountAmountEgp.
  ///
  /// In en, this message translates to:
  /// **'Discount amount (EGP)'**
  String get discountAmountEgp;

  /// No description provided for @prep.
  ///
  /// In en, this message translates to:
  /// **'Prep'**
  String get prep;

  /// No description provided for @onTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get onTheWay;

  /// No description provided for @deleteAddress.
  ///
  /// In en, this message translates to:
  /// **'Delete address?'**
  String get deleteAddress;

  /// No description provided for @areYouSureYouWantToDeleteThisAddress.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this address?'**
  String get areYouSureYouWantToDeleteThisAddress;

  /// No description provided for @whereShouldWeDeliver.
  ///
  /// In en, this message translates to:
  /// **'Where should we deliver?'**
  String get whereShouldWeDeliver;

  /// No description provided for @addYourDeliveryAddressesToOrderDeliciousFoodAndTrackItStraightToYourDoorstep.
  ///
  /// In en, this message translates to:
  /// **'Add your delivery addresses to order delicious food and track it straight to your doorstep.'**
  String
  get addYourDeliveryAddressesToOrderDeliciousFoodAndTrackItStraightToYourDoorstep;

  /// No description provided for @useThisAsPrimaryDeliveryOption.
  ///
  /// In en, this message translates to:
  /// **'Use this as primary delivery option'**
  String get useThisAsPrimaryDeliveryOption;

  /// No description provided for @addAddress.
  ///
  /// In en, this message translates to:
  /// **'Add address'**
  String get addAddress;

  /// No description provided for @editAddress.
  ///
  /// In en, this message translates to:
  /// **'Edit address'**
  String get editAddress;

  /// No description provided for @addressLocation.
  ///
  /// In en, this message translates to:
  /// **'Address Location'**
  String get addressLocation;

  /// No description provided for @apartmentDetails.
  ///
  /// In en, this message translates to:
  /// **'Apartment details'**
  String get apartmentDetails;

  /// No description provided for @deliveryInstructions.
  ///
  /// In en, this message translates to:
  /// **'Delivery instructions'**
  String get deliveryInstructions;

  /// No description provided for @placeOrder.
  ///
  /// In en, this message translates to:
  /// **'Place order'**
  String get placeOrder;

  /// No description provided for @placeOrderAndPay.
  ///
  /// In en, this message translates to:
  /// **'Place order & pay'**
  String get placeOrderAndPay;

  /// No description provided for @payTheDriverInEgp.
  ///
  /// In en, this message translates to:
  /// **'Pay the driver in EGP'**
  String get payTheDriverInEgp;

  /// No description provided for @visaMastercardMeeza.
  ///
  /// In en, this message translates to:
  /// **'Visa, Mastercard, Meeza'**
  String get visaMastercardMeeza;

  /// No description provided for @couponApplied.
  ///
  /// In en, this message translates to:
  /// **'{code} applied'**
  String couponApplied(Object code);

  /// No description provided for @youSavedAmount.
  ///
  /// In en, this message translates to:
  /// **'You saved {amount}'**
  String youSavedAmount(Object amount);

  /// No description provided for @noActiveDelivery.
  ///
  /// In en, this message translates to:
  /// **'No active delivery'**
  String get noActiveDelivery;

  /// No description provided for @noActiveDeliveryDesc.
  ///
  /// In en, this message translates to:
  /// **'You don\'t have any active deliveries at the moment. Head over to the orders pool to claim a delivery, or pull down to refresh.'**
  String get noActiveDeliveryDesc;

  /// No description provided for @refreshStatus.
  ///
  /// In en, this message translates to:
  /// **'Refresh status'**
  String get refreshStatus;

  /// No description provided for @saveProductFirstToOption.
  ///
  /// In en, this message translates to:
  /// **'Add an option group (this will save the product details first).'**
  String get saveProductFirstToOption;

  /// No description provided for @cardOrWallet.
  ///
  /// In en, this message translates to:
  /// **'Card / Wallet'**
  String get cardOrWallet;

  /// No description provided for @paymentStatusLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment: {status}'**
  String paymentStatusLabel(Object status);

  /// No description provided for @paymentStatusPaid.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get paymentStatusPaid;

  /// No description provided for @paymentStatusUnpaid.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get paymentStatusUnpaid;

  /// No description provided for @rejectedByStore.
  ///
  /// In en, this message translates to:
  /// **'Rejected by store{reason}'**
  String rejectedByStore(Object reason);

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusPrepared.
  ///
  /// In en, this message translates to:
  /// **'Prepared'**
  String get statusPrepared;

  /// No description provided for @statusOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get statusOnTheWay;

  /// No description provided for @statusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get statusDelivered;

  /// No description provided for @deliveringTo.
  ///
  /// In en, this message translates to:
  /// **'Delivering to {address}'**
  String deliveringTo(Object address);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
