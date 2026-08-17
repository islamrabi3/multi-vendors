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
  /// **'Create your account'**
  String get createYournaccount;

  /// No description provided for @howWillYouUseKitchenIn.
  ///
  /// In en, this message translates to:
  /// **'How will you use Kitchen IN?'**
  String get howWillYouUseKitchenIn;

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

  /// No description provided for @goodFoodFromTheInside.
  ///
  /// In en, this message translates to:
  /// **'Good food, from the inside.'**
  String get goodFoodFromTheInside;

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

  /// No description provided for @platformToday.
  ///
  /// In en, this message translates to:
  /// **'PLATFORM · TODAY'**
  String get platformToday;

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
  /// **'40% off your first order'**
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
  /// **'Add Item'**
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

  /// No description provided for @collectedFromCustomers.
  ///
  /// In en, this message translates to:
  /// **'Collected from customers'**
  String get collectedFromCustomers;

  /// No description provided for @appWalletLabel.
  ///
  /// In en, this message translates to:
  /// **'App wallet balance'**
  String get appWalletLabel;

  /// No description provided for @whereItGoes.
  ///
  /// In en, this message translates to:
  /// **'Where it goes'**
  String get whereItGoes;

  /// No description provided for @ordersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} orders'**
  String ordersCount(int count);

  /// No description provided for @platformEarnings.
  ///
  /// In en, this message translates to:
  /// **'Platform earnings'**
  String get platformEarnings;

  /// No description provided for @earlySettlementFees.
  ///
  /// In en, this message translates to:
  /// **'Early settlement fees'**
  String get earlySettlementFees;

  /// No description provided for @signupWebSubhead.
  ///
  /// In en, this message translates to:
  /// **'Create an account to order from the kitchens near you, track every delivery, and keep your favourites in one place.'**
  String get signupWebSubhead;

  /// No description provided for @allRoles.
  ///
  /// In en, this message translates to:
  /// **'All roles'**
  String get allRoles;

  /// No description provided for @roleCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get roleCustomer;

  /// No description provided for @roleVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendors'**
  String get roleVendor;

  /// No description provided for @roleDriver.
  ///
  /// In en, this message translates to:
  /// **'Drivers'**
  String get roleDriver;

  /// No description provided for @roleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get roleAdmin;

  /// No description provided for @statusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get statusActive;

  /// No description provided for @statusBlocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get statusBlocked;

  /// No description provided for @statusClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosed;

  /// No description provided for @allStatuses.
  ///
  /// In en, this message translates to:
  /// **'Any status'**
  String get allStatuses;

  /// No description provided for @joinedLabel.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get joinedLabel;

  /// No description provided for @userLabel.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get userLabel;

  /// No description provided for @roleLabel.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleLabel;

  /// No description provided for @noUsersMatch.
  ///
  /// In en, this message translates to:
  /// **'No users match these filters.'**
  String get noUsersMatch;

  /// No description provided for @clearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get clearFilters;

  /// No description provided for @addYourPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Add your phone number'**
  String get addYourPhoneTitle;

  /// No description provided for @addYourPhoneBody.
  ///
  /// In en, this message translates to:
  /// **'We need a number to reach you about your orders — a driver at the door, or a store confirming an address.'**
  String get addYourPhoneBody;

  /// No description provided for @pageLabel.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get pageLabel;

  /// No description provided for @visibilityLabel.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get visibilityLabel;

  /// No description provided for @linkLabel.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linkLabel;

  /// No description provided for @scrollToReadAll.
  ///
  /// In en, this message translates to:
  /// **'Scroll to the end to continue'**
  String get scrollToReadAll;

  /// No description provided for @iAgreeToTerms.
  ///
  /// In en, this message translates to:
  /// **'I have read and agree to these terms'**
  String get iAgreeToTerms;

  /// No description provided for @acceptAndContinue.
  ///
  /// In en, this message translates to:
  /// **'Accept and continue'**
  String get acceptAndContinue;

  /// No description provided for @policyVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String policyVersionLabel(int version);

  /// No description provided for @requireReacceptance.
  ///
  /// In en, this message translates to:
  /// **'Require partners to accept again'**
  String get requireReacceptance;

  /// No description provided for @requireReacceptanceOn.
  ///
  /// In en, this message translates to:
  /// **'Publishes as version {version}. Every vendor or driver will be stopped until they accept it.'**
  String requireReacceptanceOn(int version);

  /// No description provided for @requireReacceptanceOff.
  ///
  /// In en, this message translates to:
  /// **'Stays at version {version}. Existing signatures remain valid.'**
  String requireReacceptanceOff(int version);

  /// No description provided for @expiresLabel.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get expiresLabel;

  /// No description provided for @pausedLabel.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get pausedLabel;

  /// No description provided for @titleLabel.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get titleLabel;

  /// No description provided for @adViews.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get adViews;

  /// No description provided for @adTaps.
  ///
  /// In en, this message translates to:
  /// **'Taps'**
  String get adTaps;

  /// No description provided for @adTapRate.
  ///
  /// In en, this message translates to:
  /// **'Tap rate'**
  String get adTapRate;

  /// No description provided for @statusSettled.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get statusSettled;

  /// No description provided for @noArabicName.
  ///
  /// In en, this message translates to:
  /// **'No Arabic name'**
  String get noArabicName;

  /// No description provided for @errMobileWalletUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Mobile wallet payments are not available right now. Please choose another method.'**
  String get errMobileWalletUnavailable;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMore;

  /// No description provided for @proofPhotoCancelled.
  ///
  /// In en, this message translates to:
  /// **'No photo taken — the delivery was not confirmed.'**
  String get proofPhotoCancelled;

  /// No description provided for @uploadingProofPhoto.
  ///
  /// In en, this message translates to:
  /// **'Uploading photo…'**
  String get uploadingProofPhoto;

  /// No description provided for @deliverWithoutPhoto.
  ///
  /// In en, this message translates to:
  /// **'Deliver without photo'**
  String get deliverWithoutPhoto;

  /// No description provided for @sendTipAmount.
  ///
  /// In en, this message translates to:
  /// **'Send {amount} tip'**
  String sendTipAmount(String amount);

  /// No description provided for @aiMenuImport.
  ///
  /// In en, this message translates to:
  /// **'AI menu import'**
  String get aiMenuImport;

  /// No description provided for @aiMenuImportOn.
  ///
  /// In en, this message translates to:
  /// **'This store can scan its own menu photos.'**
  String get aiMenuImportOn;

  /// No description provided for @aiMenuImportOff.
  ///
  /// In en, this message translates to:
  /// **'Only admins can import this store’s menu.'**
  String get aiMenuImportOff;

  /// No description provided for @aiMenuImportHint.
  ///
  /// In en, this message translates to:
  /// **'Scan photos of your menu'**
  String get aiMenuImportHint;

  /// No description provided for @newOrderTitle.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get newOrderTitle;

  /// No description provided for @viewOrder.
  ///
  /// In en, this message translates to:
  /// **'View order'**
  String get viewOrder;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count,plural, =1{1 item} other{{count} items}}'**
  String itemsCount(int count);

  /// No description provided for @mobileWallet.
  ///
  /// In en, this message translates to:
  /// **'Mobile wallet'**
  String get mobileWallet;

  /// No description provided for @mobileWalletProviders.
  ///
  /// In en, this message translates to:
  /// **'Vodafone Cash, Etisalat, Orange'**
  String get mobileWalletProviders;

  /// No description provided for @languageChangeLaterHint.
  ///
  /// In en, this message translates to:
  /// **'You can change this any time in Settings.'**
  String get languageChangeLaterHint;

  /// No description provided for @missingSupabaseConfigurationnn1.
  ///
  /// In en, this message translates to:
  /// **'Missing Supabase configuration.'**
  String get missingSupabaseConfigurationnn1;

  /// No description provided for @multiVendor.
  ///
  /// In en, this message translates to:
  /// **'KitchenIN'**
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
  /// **'No active delivery.\nPull to refresh · or claim one from Available.'**
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

  /// No description provided for @driverDocumentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification documents'**
  String get driverDocumentsTitle;

  /// No description provided for @driverDocumentsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your national ID and vehicle licence, front and back. An admin reviews these before you can accept deliveries.'**
  String get driverDocumentsSubtitle;

  /// No description provided for @driverDocumentsIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Add all four photos so your application can be reviewed.'**
  String get driverDocumentsIncomplete;

  /// No description provided for @driverDocumentsPending.
  ///
  /// In en, this message translates to:
  /// **'Documents received. An admin will review them shortly.'**
  String get driverDocumentsPending;

  /// No description provided for @enterAValidPhone.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid phone number'**
  String get enterAValidPhone;

  /// No description provided for @enterAValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address'**
  String get enterAValidEmail;

  /// No description provided for @passwordMinSixChars.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters'**
  String get passwordMinSixChars;

  /// No description provided for @tapToUpload.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload'**
  String get tapToUpload;

  /// No description provided for @photoAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get photoAdded;

  /// No description provided for @submittedDocuments.
  ///
  /// In en, this message translates to:
  /// **'Submitted documents'**
  String get submittedDocuments;

  /// No description provided for @vehicleLabel.
  ///
  /// In en, this message translates to:
  /// **'Vehicle'**
  String get vehicleLabel;

  /// No description provided for @noDocumentsUploaded.
  ///
  /// In en, this message translates to:
  /// **'This applicant uploaded no documents.'**
  String get noDocumentsUploaded;

  /// No description provided for @driverVerificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Verification'**
  String get driverVerificationTitle;

  /// No description provided for @driverVerificationPending.
  ///
  /// In en, this message translates to:
  /// **'Under review. You can accept deliveries once an admin approves your documents.'**
  String get driverVerificationPending;

  /// No description provided for @driverVerificationApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved. You can go online and accept deliveries.'**
  String get driverVerificationApproved;

  /// No description provided for @driverVerificationRejected.
  ///
  /// In en, this message translates to:
  /// **'Your documents were rejected. Replace them and they will be reviewed again.'**
  String get driverVerificationRejected;

  /// No description provided for @driverVerificationSuspended.
  ///
  /// In en, this message translates to:
  /// **'Your account is suspended. Contact support.'**
  String get driverVerificationSuspended;

  /// No description provided for @driverDocumentsMissingBanner.
  ///
  /// In en, this message translates to:
  /// **'Finish your verification to start delivering'**
  String get driverDocumentsMissingBanner;

  /// No description provided for @submitForReview.
  ///
  /// In en, this message translates to:
  /// **'Submit for review'**
  String get submitForReview;

  /// No description provided for @documentsSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Documents submitted for review.'**
  String get documentsSubmitted;

  /// No description provided for @onFileLabel.
  ///
  /// In en, this message translates to:
  /// **'On file'**
  String get onFileLabel;

  /// No description provided for @userDeletedAnonymised.
  ///
  /// In en, this message translates to:
  /// **'Account closed and anonymised. It could not be removed because it has order history.'**
  String get userDeletedAnonymised;

  /// No description provided for @unverifiedDriverNotice.
  ///
  /// In en, this message translates to:
  /// **'You cannot accept deliveries until an admin verifies your account.'**
  String get unverifiedDriverNotice;

  /// No description provided for @unverifiedVendorNotice.
  ///
  /// In en, this message translates to:
  /// **'You cannot accept orders until an admin verifies your store.'**
  String get unverifiedVendorNotice;

  /// No description provided for @suspendedVendorNotice.
  ///
  /// In en, this message translates to:
  /// **'Your store is suspended, so it cannot accept orders. Contact support.'**
  String get suspendedVendorNotice;

  /// No description provided for @documentPreview.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get documentPreview;

  /// No description provided for @notUploaded.
  ///
  /// In en, this message translates to:
  /// **'Not uploaded'**
  String get notUploaded;

  /// No description provided for @deliveryProofOptionalHint.
  ///
  /// In en, this message translates to:
  /// **'Attach a photo as proof of delivery, or skip.'**
  String get deliveryProofOptionalHint;

  /// No description provided for @proofPhotoFailed.
  ///
  /// In en, this message translates to:
  /// **'The photo could not be attached. The delivery was still completed.'**
  String get proofPhotoFailed;

  /// No description provided for @adjustWallet.
  ///
  /// In en, this message translates to:
  /// **'Adjust wallet'**
  String get adjustWallet;

  /// No description provided for @walletAdjustCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get walletAdjustCredit;

  /// No description provided for @walletAdjustDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get walletAdjustDebit;

  /// No description provided for @walletAdjustAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get walletAdjustAmount;

  /// No description provided for @walletAdjustReason.
  ///
  /// In en, this message translates to:
  /// **'Reason (shown to the customer)'**
  String get walletAdjustReason;

  /// No description provided for @walletAdjustReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Give a reason — the customer sees it in their wallet history.'**
  String get walletAdjustReasonRequired;

  /// No description provided for @walletAdjusted.
  ///
  /// In en, this message translates to:
  /// **'Wallet updated. New balance: {balance}'**
  String walletAdjusted(String balance);

  /// No description provided for @documentUploaded.
  ///
  /// In en, this message translates to:
  /// **'Document uploaded.'**
  String get documentUploaded;

  /// No description provided for @driverRejected.
  ///
  /// In en, this message translates to:
  /// **'Driver rejected. They can replace their documents and reapply.'**
  String get driverRejected;

  /// No description provided for @driverSuspendedToast.
  ///
  /// In en, this message translates to:
  /// **'Driver suspended and taken offline.'**
  String get driverSuspendedToast;

  /// No description provided for @couldNotLoadDocument.
  ///
  /// In en, this message translates to:
  /// **'Could not load this document'**
  String get couldNotLoadDocument;

  /// No description provided for @noDriverApplications.
  ///
  /// In en, this message translates to:
  /// **'No driver applications in this filter.'**
  String get noDriverApplications;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @statusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get statusApproved;

  /// No description provided for @statusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get statusSuspended;

  /// No description provided for @documentsOnFile.
  ///
  /// In en, this message translates to:
  /// **'{count} of 4 documents'**
  String documentsOnFile(int count);

  /// No description provided for @searchVendorsHint.
  ///
  /// In en, this message translates to:
  /// **'Search stores by name or phone'**
  String get searchVendorsHint;

  /// No description provided for @openSupportThreads.
  ///
  /// In en, this message translates to:
  /// **'Open support'**
  String get openSupportThreads;

  /// No description provided for @driversToApprove.
  ///
  /// In en, this message translates to:
  /// **'Drivers to approve'**
  String get driversToApprove;

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
  /// **'Re-order'**
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

  /// No description provided for @wallet.
  ///
  /// In en, this message translates to:
  /// **'Wallet'**
  String get wallet;

  /// No description provided for @walletBalance.
  ///
  /// In en, this message translates to:
  /// **'Wallet Balance'**
  String get walletBalance;

  /// No description provided for @useWalletBalance.
  ///
  /// In en, this message translates to:
  /// **'Use wallet balance'**
  String get useWalletBalance;

  /// No description provided for @loyaltyRewards.
  ///
  /// In en, this message translates to:
  /// **'Loyalty Rewards'**
  String get loyaltyRewards;

  /// No description provided for @driverTip.
  ///
  /// In en, this message translates to:
  /// **'Driver Tip'**
  String get driverTip;

  /// No description provided for @pickup.
  ///
  /// In en, this message translates to:
  /// **'Pick-up'**
  String get pickup;

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get delivery;

  /// No description provided for @scheduledDelivery.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Delivery'**
  String get scheduledDelivery;

  /// No description provided for @liveChat.
  ///
  /// In en, this message translates to:
  /// **'Live Chat'**
  String get liveChat;

  /// No description provided for @proofOfDelivery.
  ///
  /// In en, this message translates to:
  /// **'Proof of Delivery'**
  String get proofOfDelivery;

  /// No description provided for @busyMode.
  ///
  /// In en, this message translates to:
  /// **'Busy Mode (+15m)'**
  String get busyMode;

  /// No description provided for @addMoreToReachMinimum.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addMoreToReachMinimum;

  /// No description provided for @tips.
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get tips;

  /// No description provided for @financialReports.
  ///
  /// In en, this message translates to:
  /// **'Financial & sales'**
  String get financialReports;

  /// No description provided for @platformTab.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platformTab;

  /// No description provided for @vendorSalesTab.
  ///
  /// In en, this message translates to:
  /// **'Vendor sales'**
  String get vendorSalesTab;

  /// No description provided for @driverPayoutsTab.
  ///
  /// In en, this message translates to:
  /// **'Driver payouts'**
  String get driverPayoutsTab;

  /// No description provided for @period.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get period;

  /// No description provided for @periodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get periodToday;

  /// No description provided for @periodWeek.
  ///
  /// In en, this message translates to:
  /// **'7 days'**
  String get periodWeek;

  /// No description provided for @periodMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get periodMonth;

  /// No description provided for @periodAll.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get periodAll;

  /// No description provided for @grossRevenue.
  ///
  /// In en, this message translates to:
  /// **'Gross revenue'**
  String get grossRevenue;

  /// No description provided for @itemSales.
  ///
  /// In en, this message translates to:
  /// **'Item sales'**
  String get itemSales;

  /// No description provided for @platformCommission.
  ///
  /// In en, this message translates to:
  /// **'Platform commission'**
  String get platformCommission;

  /// No description provided for @driverCost.
  ///
  /// In en, this message translates to:
  /// **'Driver payouts'**
  String get driverCost;

  /// No description provided for @netMargin.
  ///
  /// In en, this message translates to:
  /// **'Net to platform'**
  String get netMargin;

  /// No description provided for @cashCollected.
  ///
  /// In en, this message translates to:
  /// **'Cash with drivers'**
  String get cashCollected;

  /// No description provided for @cardCollected.
  ///
  /// In en, this message translates to:
  /// **'Paid by card'**
  String get cardCollected;

  /// No description provided for @averageOrder.
  ///
  /// In en, this message translates to:
  /// **'Average order'**
  String get averageOrder;

  /// No description provided for @deliveredOrders.
  ///
  /// In en, this message translates to:
  /// **'Delivered Orders'**
  String get deliveredOrders;

  /// No description provided for @cancelledOrders.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get cancelledOrders;

  /// No description provided for @deliveryFeesTotal.
  ///
  /// In en, this message translates to:
  /// **'Delivery fees'**
  String get deliveryFeesTotal;

  /// No description provided for @discountsGiven.
  ///
  /// In en, this message translates to:
  /// **'Discounts given'**
  String get discountsGiven;

  /// No description provided for @vendorPayouts.
  ///
  /// In en, this message translates to:
  /// **'Vendor payouts'**
  String get vendorPayouts;

  /// No description provided for @noReportData.
  ///
  /// In en, this message translates to:
  /// **'No delivered orders in this period.'**
  String get noReportData;

  /// No description provided for @settlement.
  ///
  /// In en, this message translates to:
  /// **'Settlement'**
  String get settlement;

  /// No description provided for @volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get volume;

  /// No description provided for @accountBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account suspended'**
  String get accountBlockedTitle;

  /// No description provided for @accountBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'An administrator has suspended this account, so it cannot place orders, deliver, or trade. Contact support if you believe this is a mistake.'**
  String get accountBlockedBody;

  /// No description provided for @accountClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Account closed'**
  String get accountClosedTitle;

  /// No description provided for @accountClosedBody.
  ///
  /// In en, this message translates to:
  /// **'This account has been closed and can no longer be used. Past orders remain on record.'**
  String get accountClosedBody;

  /// No description provided for @supportChat.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportChat;

  /// No description provided for @supportResolvedNotice.
  ///
  /// In en, this message translates to:
  /// **'This conversation is resolved. Messages are removed 24 hours after it closes — send a reply to reopen it.'**
  String get supportResolvedNotice;

  /// No description provided for @supportChatEmpty.
  ///
  /// In en, this message translates to:
  /// **'Send us a message and we\'ll get back to you.'**
  String get supportChatEmpty;

  /// No description provided for @typeAMessage.
  ///
  /// In en, this message translates to:
  /// **'Type a message'**
  String get typeAMessage;

  /// No description provided for @markResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get markResolved;

  /// No description provided for @reopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get reopen;

  /// No description provided for @resolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get resolved;

  /// No description provided for @noSupportThreads.
  ///
  /// In en, this message translates to:
  /// **'No support conversations yet.'**
  String get noSupportThreads;

  /// No description provided for @openOnly.
  ///
  /// In en, this message translates to:
  /// **'Open only'**
  String get openOnly;

  /// No description provided for @users.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get users;

  /// No description provided for @blockUser.
  ///
  /// In en, this message translates to:
  /// **'Block user'**
  String get blockUser;

  /// No description provided for @unblockUser.
  ///
  /// In en, this message translates to:
  /// **'Unblock user'**
  String get unblockUser;

  /// No description provided for @blocked.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get blocked;

  /// No description provided for @blockReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (shown to nobody, kept for your records)'**
  String get blockReasonHint;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountWarning.
  ///
  /// In en, this message translates to:
  /// **'This closes your account for good. Past orders stay on record, but you will not be able to sign in again.'**
  String get deleteAccountWarning;

  /// No description provided for @deleteAccountActiveOrders.
  ///
  /// In en, this message translates to:
  /// **'You still have an order in progress. You can delete your account once it is finished.'**
  String get deleteAccountActiveOrders;

  /// No description provided for @deleteAccountWalletWarning.
  ///
  /// In en, this message translates to:
  /// **'You still have {amount} in your wallet. Deleting your account forfeits it.'**
  String deleteAccountWalletWarning(String amount);

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Yes, delete my account'**
  String get deleteAccountConfirm;

  /// No description provided for @accountDeleted.
  ///
  /// In en, this message translates to:
  /// **'Your account has been closed.'**
  String get accountDeleted;

  /// No description provided for @userBlocked.
  ///
  /// In en, this message translates to:
  /// **'User blocked.'**
  String get userBlocked;

  /// No description provided for @userUnblocked.
  ///
  /// In en, this message translates to:
  /// **'User unblocked.'**
  String get userUnblocked;

  /// No description provided for @userDeleted.
  ///
  /// In en, this message translates to:
  /// **'User account closed.'**
  String get userDeleted;

  /// No description provided for @searchUsers.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone'**
  String get searchUsers;

  /// No description provided for @bySigningUpYouAgree.
  ///
  /// In en, this message translates to:
  /// **'By continuing you agree to our'**
  String get bySigningUpYouAgree;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get and;

  /// No description provided for @nearbyRestaurants.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get nearbyRestaurants;

  /// No description provided for @aboutUs.
  ///
  /// In en, this message translates to:
  /// **'About us'**
  String get aboutUs;

  /// No description provided for @termsAndConditions.
  ///
  /// In en, this message translates to:
  /// **'Terms & Conditions'**
  String get termsAndConditions;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @followUs.
  ///
  /// In en, this message translates to:
  /// **'Follow us'**
  String get followUs;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated'**
  String get lastUpdated;

  /// No description provided for @contentNotAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'This page has not been published yet.'**
  String get contentNotAvailableYet;

  /// No description provided for @couldNotOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Could not open that link.'**
  String get couldNotOpenLink;

  /// No description provided for @recommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get recommended;

  /// No description provided for @content.
  ///
  /// In en, this message translates to:
  /// **'Content & pages'**
  String get content;

  /// No description provided for @socialLinks.
  ///
  /// In en, this message translates to:
  /// **'Social links'**
  String get socialLinks;

  /// No description provided for @addLink.
  ///
  /// In en, this message translates to:
  /// **'Add link'**
  String get addLink;

  /// No description provided for @platform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get platform;

  /// No description provided for @linkUrl.
  ///
  /// In en, this message translates to:
  /// **'Link URL'**
  String get linkUrl;

  /// No description provided for @published.
  ///
  /// In en, this message translates to:
  /// **'Published'**
  String get published;

  /// No description provided for @draft.
  ///
  /// In en, this message translates to:
  /// **'Draft — hidden from customers'**
  String get draft;

  /// No description provided for @sortOrder.
  ///
  /// In en, this message translates to:
  /// **'Sort order'**
  String get sortOrder;

  /// No description provided for @englishBody.
  ///
  /// In en, this message translates to:
  /// **'Body · English'**
  String get englishBody;

  /// No description provided for @arabicBody.
  ///
  /// In en, this message translates to:
  /// **'Body · Arabic'**
  String get arabicBody;

  /// No description provided for @englishTitle.
  ///
  /// In en, this message translates to:
  /// **'Title · English'**
  String get englishTitle;

  /// No description provided for @arabicTitle.
  ///
  /// In en, this message translates to:
  /// **'Title · Arabic'**
  String get arabicTitle;

  /// No description provided for @manageRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended stores'**
  String get manageRecommended;

  /// No description provided for @storeLocationOnMap.
  ///
  /// In en, this message translates to:
  /// **'Store location on map'**
  String get storeLocationOnMap;

  /// No description provided for @pickOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pick on map'**
  String get pickOnMap;

  /// No description provided for @pickStoreLocationFirst.
  ///
  /// In en, this message translates to:
  /// **'Pick your store location on the map first.'**
  String get pickStoreLocationFirst;

  /// No description provided for @sortNearest.
  ///
  /// In en, this message translates to:
  /// **'Nearest'**
  String get sortNearest;

  /// No description provided for @awayFromYou.
  ///
  /// In en, this message translates to:
  /// **'away'**
  String get awayFromYou;

  /// No description provided for @storeControls.
  ///
  /// In en, this message translates to:
  /// **'Store controls'**
  String get storeControls;

  /// No description provided for @storeClosedNotice.
  ///
  /// In en, this message translates to:
  /// **'Your store is closed — customers cannot place orders.'**
  String get storeClosedNotice;

  /// No description provided for @needsYourAttention.
  ///
  /// In en, this message translates to:
  /// **'need your attention'**
  String get needsYourAttention;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get allCaughtUp;

  /// No description provided for @totalAmount.
  ///
  /// In en, this message translates to:
  /// **'Total amount'**
  String get totalAmount;

  /// No description provided for @openInMaps.
  ///
  /// In en, this message translates to:
  /// **'Open in Maps'**
  String get openInMaps;

  /// No description provided for @enterOtp.
  ///
  /// In en, this message translates to:
  /// **'Enter Customer Code'**
  String get enterOtp;

  /// No description provided for @vendorAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Store Analytics'**
  String get vendorAnalytics;

  /// No description provided for @operatingSchedule.
  ///
  /// In en, this message translates to:
  /// **'Operating Hours'**
  String get operatingSchedule;

  /// No description provided for @addCategorySectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Add a category section to organize your menu items.'**
  String get addCategorySectionDesc;

  /// No description provided for @modifyCategoryNameDesc.
  ///
  /// In en, this message translates to:
  /// **'Modify category name or delete section.'**
  String get modifyCategoryNameDesc;

  /// No description provided for @sectionHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Burgers, Beverages, Desserts'**
  String get sectionHint;

  /// No description provided for @rejectReasonDesc.
  ///
  /// In en, this message translates to:
  /// **'Please state a reason for rejecting this incoming order.'**
  String get rejectReasonDesc;

  /// No description provided for @rejectReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Item out of stock, kitchen busy'**
  String get rejectReasonHint;

  /// No description provided for @cancelReasonDesc.
  ///
  /// In en, this message translates to:
  /// **'Specify a reason for admin cancellation and refund.'**
  String get cancelReasonDesc;

  /// No description provided for @cancelReasonHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Customer requested cancellation'**
  String get cancelReasonHint;

  /// No description provided for @deleteCategoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteCategoryTitle(Object name);

  /// No description provided for @deleteCategoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this category? This might affect vendors registered under it.'**
  String get deleteCategoryMessage;

  /// No description provided for @noMessagesYet.
  ///
  /// In en, this message translates to:
  /// **'No messages yet. Send a message to contact driver/support.'**
  String get noMessagesYet;

  /// No description provided for @typeYourMessage.
  ///
  /// In en, this message translates to:
  /// **'Type your message...'**
  String get typeYourMessage;

  /// No description provided for @topUp.
  ///
  /// In en, this message translates to:
  /// **'Top Up'**
  String get topUp;

  /// No description provided for @transactionHistory.
  ///
  /// In en, this message translates to:
  /// **'Transaction History'**
  String get transactionHistory;

  /// No description provided for @noTransactions.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet.'**
  String get noTransactions;

  /// No description provided for @pointsHistory.
  ///
  /// In en, this message translates to:
  /// **'Points History'**
  String get pointsHistory;

  /// No description provided for @totalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get totalRevenue;

  /// No description provided for @performanceOverview.
  ///
  /// In en, this message translates to:
  /// **'Performance Overview'**
  String get performanceOverview;

  /// No description provided for @driverEarnings.
  ///
  /// In en, this message translates to:
  /// **'Driver Earnings & Wallet'**
  String get driverEarnings;

  /// No description provided for @deliveryProofPhotoOptional.
  ///
  /// In en, this message translates to:
  /// **'Delivery Proof Photo (Optional)'**
  String get deliveryProofPhotoOptional;

  /// No description provided for @addPhotoProof.
  ///
  /// In en, this message translates to:
  /// **'Add Photo Proof'**
  String get addPhotoProof;

  /// No description provided for @skipAndDeliver.
  ///
  /// In en, this message translates to:
  /// **'Skip & Mark Delivered'**
  String get skipAndDeliver;

  /// No description provided for @proofPhotoAdded.
  ///
  /// In en, this message translates to:
  /// **'Photo Attached!'**
  String get proofPhotoAdded;

  /// No description provided for @liveChatWithDriverSupport.
  ///
  /// In en, this message translates to:
  /// **'Live Chat with Driver / Support'**
  String get liveChatWithDriverSupport;

  /// No description provided for @reorderItems.
  ///
  /// In en, this message translates to:
  /// **'Re-order items'**
  String get reorderItems;

  /// No description provided for @callCustomer.
  ///
  /// In en, this message translates to:
  /// **'Call Customer'**
  String get callCustomer;

  /// No description provided for @storeAnalyticsAndReports.
  ///
  /// In en, this message translates to:
  /// **'Store Analytics & Reports'**
  String get storeAnalyticsAndReports;

  /// No description provided for @operatingHoursSchedule.
  ///
  /// In en, this message translates to:
  /// **'Operating Hours Schedule'**
  String get operatingHoursSchedule;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @noNotificationsYet.
  ///
  /// In en, this message translates to:
  /// **'No notifications yet'**
  String get noNotificationsYet;

  /// No description provided for @averageStoreRating.
  ///
  /// In en, this message translates to:
  /// **'Average Store Rating'**
  String get averageStoreRating;

  /// No description provided for @avgPreparationTime.
  ///
  /// In en, this message translates to:
  /// **'Avg Preparation Time'**
  String get avgPreparationTime;

  /// No description provided for @twentyMins.
  ///
  /// In en, this message translates to:
  /// **'20 mins'**
  String get twentyMins;

  /// No description provided for @daySunday.
  ///
  /// In en, this message translates to:
  /// **'Sunday'**
  String get daySunday;

  /// No description provided for @dayMonday.
  ///
  /// In en, this message translates to:
  /// **'Monday'**
  String get dayMonday;

  /// No description provided for @dayTuesday.
  ///
  /// In en, this message translates to:
  /// **'Tuesday'**
  String get dayTuesday;

  /// No description provided for @dayWednesday.
  ///
  /// In en, this message translates to:
  /// **'Wednesday'**
  String get dayWednesday;

  /// No description provided for @dayThursday.
  ///
  /// In en, this message translates to:
  /// **'Thursday'**
  String get dayThursday;

  /// No description provided for @dayFriday.
  ///
  /// In en, this message translates to:
  /// **'Friday'**
  String get dayFriday;

  /// No description provided for @daySaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday'**
  String get daySaturday;

  /// No description provided for @closedStatus.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get closedStatus;

  /// No description provided for @openStatus.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get openStatus;

  /// No description provided for @busyStore.
  ///
  /// In en, this message translates to:
  /// **'Busy (+15m)'**
  String get busyStore;

  /// No description provided for @busyStoreNotice.
  ///
  /// In en, this message translates to:
  /// **'🔥 High Demand: Store is currently busy (+15 mins extra prep time)'**
  String get busyStoreNotice;

  /// No description provided for @myWallet.
  ///
  /// In en, this message translates to:
  /// **'My Wallet'**
  String get myWallet;

  /// No description provided for @currentBalance.
  ///
  /// In en, this message translates to:
  /// **'Current Balance'**
  String get currentBalance;

  /// No description provided for @topUpWallet.
  ///
  /// In en, this message translates to:
  /// **'Top Up Wallet'**
  String get topUpWallet;

  /// No description provided for @payWithPaymob.
  ///
  /// In en, this message translates to:
  /// **'Pay via Paymob'**
  String get payWithPaymob;

  /// No description provided for @selectTopUpAmount.
  ///
  /// In en, this message translates to:
  /// **'Select or enter top-up amount:'**
  String get selectTopUpAmount;

  /// No description provided for @payWithWallet.
  ///
  /// In en, this message translates to:
  /// **'Pay with Wallet'**
  String get payWithWallet;

  /// No description provided for @insufficientWalletBalance.
  ///
  /// In en, this message translates to:
  /// **'Insufficient Balance'**
  String get insufficientWalletBalance;

  /// No description provided for @walletPayment.
  ///
  /// In en, this message translates to:
  /// **'Wallet Payment'**
  String get walletPayment;

  /// No description provided for @earnPointsOnOrders.
  ///
  /// In en, this message translates to:
  /// **'Earn points on every completed order!'**
  String get earnPointsOnOrders;

  /// No description provided for @noLoyaltyPointsYet.
  ///
  /// In en, this message translates to:
  /// **'No loyalty points earned yet.'**
  String get noLoyaltyPointsYet;

  /// No description provided for @reportAnIssue.
  ///
  /// In en, this message translates to:
  /// **'Report an Issue'**
  String get reportAnIssue;

  /// No description provided for @reportStoreOrOrder.
  ///
  /// In en, this message translates to:
  /// **'Report Store / Order Issue'**
  String get reportStoreOrOrder;

  /// No description provided for @issueSubject.
  ///
  /// In en, this message translates to:
  /// **'Issue Subject'**
  String get issueSubject;

  /// No description provided for @issueDescription.
  ///
  /// In en, this message translates to:
  /// **'Describe the problem...'**
  String get issueDescription;

  /// No description provided for @submitReport.
  ///
  /// In en, this message translates to:
  /// **'Submit Report'**
  String get submitReport;

  /// No description provided for @reportSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Report submitted successfully. Admin will review soon!'**
  String get reportSubmitted;

  /// No description provided for @customerReports.
  ///
  /// In en, this message translates to:
  /// **'Customer Reports & Complaints'**
  String get customerReports;

  /// No description provided for @resolveAndNotify.
  ///
  /// In en, this message translates to:
  /// **'Resolve & Reply'**
  String get resolveAndNotify;

  /// No description provided for @replyMessage.
  ///
  /// In en, this message translates to:
  /// **'Reply to Customer'**
  String get replyMessage;

  /// No description provided for @statusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get statusPending;

  /// No description provided for @statusInProgress.
  ///
  /// In en, this message translates to:
  /// **'In Progress'**
  String get statusInProgress;

  /// No description provided for @statusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get statusResolved;

  /// No description provided for @refundRequired.
  ///
  /// In en, this message translates to:
  /// **'Refund required'**
  String get refundRequired;

  /// No description provided for @refundDueDesc.
  ///
  /// In en, this message translates to:
  /// **'The customer paid by card. Refund the amount to their wallet.'**
  String get refundDueDesc;

  /// No description provided for @refundToWallet.
  ///
  /// In en, this message translates to:
  /// **'Refund to wallet'**
  String get refundToWallet;

  /// No description provided for @refundedToWallet.
  ///
  /// In en, this message translates to:
  /// **'Refunded to the customer\'s wallet'**
  String get refundedToWallet;

  /// No description provided for @refundConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Refund to wallet?'**
  String get refundConfirmTitle;

  /// No description provided for @refundConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'This credits the paid amount back to the customer\'s wallet. It cannot be undone.'**
  String get refundConfirmMessage;

  /// No description provided for @noActiveOrders.
  ///
  /// In en, this message translates to:
  /// **'No active orders'**
  String get noActiveOrders;

  /// No description provided for @noPastOrders.
  ///
  /// In en, this message translates to:
  /// **'No past orders'**
  String get noPastOrders;

  /// No description provided for @noCategoriesYet.
  ///
  /// In en, this message translates to:
  /// **'No categories created yet.'**
  String get noCategoriesYet;

  /// No description provided for @noReportsFound.
  ///
  /// In en, this message translates to:
  /// **'No complaints or reports found.'**
  String get noReportsFound;

  /// No description provided for @bannerType.
  ///
  /// In en, this message translates to:
  /// **'Banner type'**
  String get bannerType;

  /// No description provided for @bannerTypeCoupon.
  ///
  /// In en, this message translates to:
  /// **'Coupon'**
  String get bannerTypeCoupon;

  /// No description provided for @bannerTypeVendor.
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get bannerTypeVendor;

  /// No description provided for @bannerTypeEvent.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get bannerTypeEvent;

  /// No description provided for @selectVendor.
  ///
  /// In en, this message translates to:
  /// **'Select vendor'**
  String get selectVendor;

  /// No description provided for @selectCoupon.
  ///
  /// In en, this message translates to:
  /// **'Select coupon'**
  String get selectCoupon;

  /// No description provided for @chooseVendorForBanner.
  ///
  /// In en, this message translates to:
  /// **'Choose a vendor for this banner.'**
  String get chooseVendorForBanner;

  /// No description provided for @chooseCouponForBanner.
  ///
  /// In en, this message translates to:
  /// **'Choose a coupon code for this banner.'**
  String get chooseCouponForBanner;

  /// No description provided for @copyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get copyCode;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Code copied!'**
  String get codeCopied;

  /// No description provided for @offerDetails.
  ///
  /// In en, this message translates to:
  /// **'Offer details'**
  String get offerDetails;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @onboardingTitle1.
  ///
  /// In en, this message translates to:
  /// **'All your favorite stores'**
  String get onboardingTitle1;

  /// No description provided for @onboardingBody1.
  ///
  /// In en, this message translates to:
  /// **'Restaurants, groceries and more — browse local vendors and order in a few taps.'**
  String get onboardingBody1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In en, this message translates to:
  /// **'Fast delivery, live tracking'**
  String get onboardingTitle2;

  /// No description provided for @onboardingBody2.
  ///
  /// In en, this message translates to:
  /// **'Follow your order from the kitchen to your door, with live driver updates.'**
  String get onboardingBody2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In en, this message translates to:
  /// **'Pay your way'**
  String get onboardingTitle3;

  /// No description provided for @onboardingBody3.
  ///
  /// In en, this message translates to:
  /// **'Cash on delivery, card, or your in-app wallet — with coupons and offers every day.'**
  String get onboardingBody3;

  /// No description provided for @categoriesTab.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categoriesTab;

  /// No description provided for @importMenuFromPhotos.
  ///
  /// In en, this message translates to:
  /// **'Import menu from photos'**
  String get importMenuFromPhotos;

  /// No description provided for @importMenuHint.
  ///
  /// In en, this message translates to:
  /// **'Upload photos of your menu. We read every section and item automatically — you review, edit, then import all at once.'**
  String get importMenuHint;

  /// No description provided for @addPhotos.
  ///
  /// In en, this message translates to:
  /// **'Add photos'**
  String get addPhotos;

  /// No description provided for @extractMenuAction.
  ///
  /// In en, this message translates to:
  /// **'Extract menu'**
  String get extractMenuAction;

  /// No description provided for @extractingMenu.
  ///
  /// In en, this message translates to:
  /// **'Reading your menu…'**
  String get extractingMenu;

  /// No description provided for @reviewExtractedMenu.
  ///
  /// In en, this message translates to:
  /// **'Review & edit before importing'**
  String get reviewExtractedMenu;

  /// No description provided for @importAll.
  ///
  /// In en, this message translates to:
  /// **'Import all'**
  String get importAll;

  /// No description provided for @menuImported.
  ///
  /// In en, this message translates to:
  /// **'Menu imported successfully!'**
  String get menuImported;

  /// No description provided for @extractionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the menu. Try clearer photos.'**
  String get extractionFailed;

  /// No description provided for @noItemsExtracted.
  ///
  /// In en, this message translates to:
  /// **'No items were found in these photos.'**
  String get noItemsExtracted;

  /// No description provided for @itemName.
  ///
  /// In en, this message translates to:
  /// **'Item name'**
  String get itemName;

  /// No description provided for @priceLabel.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get priceLabel;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @filters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get filters;

  /// No description provided for @sortBy.
  ///
  /// In en, this message translates to:
  /// **'Sort by'**
  String get sortBy;

  /// No description provided for @sortRecommended.
  ///
  /// In en, this message translates to:
  /// **'Recommended'**
  String get sortRecommended;

  /// No description provided for @sortRating.
  ///
  /// In en, this message translates to:
  /// **'Top rated'**
  String get sortRating;

  /// No description provided for @sortDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Lowest delivery fee'**
  String get sortDeliveryFee;

  /// No description provided for @sortPrepTime.
  ///
  /// In en, this message translates to:
  /// **'Fastest'**
  String get sortPrepTime;

  /// No description provided for @showOnly.
  ///
  /// In en, this message translates to:
  /// **'Show only'**
  String get showOnly;

  /// No description provided for @openStoresOnly.
  ///
  /// In en, this message translates to:
  /// **'Open now'**
  String get openStoresOnly;

  /// No description provided for @freeDeliveryOnly.
  ///
  /// In en, this message translates to:
  /// **'Free delivery'**
  String get freeDeliveryOnly;

  /// No description provided for @favoritesOnly.
  ///
  /// In en, this message translates to:
  /// **'My favorites'**
  String get favoritesOnly;

  /// No description provided for @maxDeliveryFee.
  ///
  /// In en, this message translates to:
  /// **'Max delivery fee'**
  String get maxDeliveryFee;

  /// No description provided for @minimumRating.
  ///
  /// In en, this message translates to:
  /// **'Minimum rating'**
  String get minimumRating;

  /// No description provided for @any.
  ///
  /// In en, this message translates to:
  /// **'Any'**
  String get any;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @showResults.
  ///
  /// In en, this message translates to:
  /// **'Show results'**
  String get showResults;

  /// No description provided for @noStoresMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No stores match these filters'**
  String get noStoresMatchFilters;

  /// No description provided for @storesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} stores'**
  String storesCount(int count);

  /// No description provided for @selectIconBanner.
  ///
  /// In en, this message translates to:
  /// **'Select icon / banner'**
  String get selectIconBanner;

  /// No description provided for @categoryNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Category name is required'**
  String get categoryNameRequired;

  /// No description provided for @issueLabel.
  ///
  /// In en, this message translates to:
  /// **'Issue'**
  String get issueLabel;

  /// No description provided for @report.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get report;

  /// No description provided for @chat.
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get chat;

  /// No description provided for @pendingApproval.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get pendingApproval;

  /// No description provided for @driverPendingApprovalDesc.
  ///
  /// In en, this message translates to:
  /// **'An admin is reviewing your account. You can go online once it is approved.'**
  String get driverPendingApprovalDesc;

  /// No description provided for @driverSuspendedDesc.
  ///
  /// In en, this message translates to:
  /// **'Your account is suspended. Contact support for details.'**
  String get driverSuspendedDesc;

  /// No description provided for @approveDriver.
  ///
  /// In en, this message translates to:
  /// **'Approve driver'**
  String get approveDriver;

  /// No description provided for @suspendDriver.
  ///
  /// In en, this message translates to:
  /// **'Suspend driver'**
  String get suspendDriver;

  /// No description provided for @driverApproved.
  ///
  /// In en, this message translates to:
  /// **'Driver approved'**
  String get driverApproved;

  /// No description provided for @driverSuspended.
  ///
  /// In en, this message translates to:
  /// **'Driver suspended'**
  String get driverSuspended;

  /// No description provided for @noDriversHere.
  ///
  /// In en, this message translates to:
  /// **'No drivers here'**
  String get noDriversHere;

  /// No description provided for @chooseYourRole.
  ///
  /// In en, this message translates to:
  /// **'How will you use the app?'**
  String get chooseYourRole;

  /// No description provided for @chooseYourRoleSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick the account type that fits you. This is the only time we ask.'**
  String get chooseYourRoleSubtitle;

  /// No description provided for @roleCustomerDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse stores & get it delivered'**
  String get roleCustomerDesc;

  /// No description provided for @roleVendorDesc.
  ///
  /// In en, this message translates to:
  /// **'Manage a store & menu'**
  String get roleVendorDesc;

  /// No description provided for @roleDriverDesc.
  ///
  /// In en, this message translates to:
  /// **'Earn on your schedule'**
  String get roleDriverDesc;

  /// No description provided for @roleChoiceIsPermanent.
  ///
  /// In en, this message translates to:
  /// **'Your account type cannot be changed once you start using the app.'**
  String get roleChoiceIsPermanent;

  /// No description provided for @editProfile.
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get editProfile;

  /// No description provided for @profileUpdated.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get profileUpdated;

  /// No description provided for @nameRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get nameRequired;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @pickLocationOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pick location on map'**
  String get pickLocationOnMap;

  /// No description provided for @searchForAPlace.
  ///
  /// In en, this message translates to:
  /// **'Search for a place'**
  String get searchForAPlace;

  /// No description provided for @outsideServiceArea.
  ///
  /// In en, this message translates to:
  /// **'We don\'t deliver to this spot yet'**
  String get outsideServiceArea;

  /// No description provided for @locatingAddress.
  ///
  /// In en, this message translates to:
  /// **'Finding address…'**
  String get locatingAddress;

  /// No description provided for @dragTheMapToPlaceThePin.
  ///
  /// In en, this message translates to:
  /// **'Drag the map to place the pin'**
  String get dragTheMapToPlaceThePin;

  /// No description provided for @confirmLocation.
  ///
  /// In en, this message translates to:
  /// **'Confirm location'**
  String get confirmLocation;

  /// No description provided for @changeLocation.
  ///
  /// In en, this message translates to:
  /// **'Change location'**
  String get changeLocation;

  /// No description provided for @deliveryLocation.
  ///
  /// In en, this message translates to:
  /// **'Delivery location'**
  String get deliveryLocation;

  /// No description provided for @serviceAreas.
  ///
  /// In en, this message translates to:
  /// **'Service areas'**
  String get serviceAreas;

  /// No description provided for @addServiceArea.
  ///
  /// In en, this message translates to:
  /// **'Add service area'**
  String get addServiceArea;

  /// No description provided for @editServiceArea.
  ///
  /// In en, this message translates to:
  /// **'Edit service area'**
  String get editServiceArea;

  /// No description provided for @deliveryRadius.
  ///
  /// In en, this message translates to:
  /// **'Delivery radius'**
  String get deliveryRadius;

  /// No description provided for @areaName.
  ///
  /// In en, this message translates to:
  /// **'Area name'**
  String get areaName;

  /// No description provided for @areaNameArabic.
  ///
  /// In en, this message translates to:
  /// **'Area name (Arabic)'**
  String get areaNameArabic;

  /// No description provided for @noServiceAreasYet.
  ///
  /// In en, this message translates to:
  /// **'No service areas yet'**
  String get noServiceAreasYet;

  /// No description provided for @coverageEverywhereNote.
  ///
  /// In en, this message translates to:
  /// **'With no areas set, orders are accepted everywhere. Add one to limit delivery.'**
  String get coverageEverywhereNote;

  /// No description provided for @serviceAreaSaved.
  ///
  /// In en, this message translates to:
  /// **'Service area saved'**
  String get serviceAreaSaved;

  /// No description provided for @serviceAreaDeleted.
  ///
  /// In en, this message translates to:
  /// **'Service area deleted'**
  String get serviceAreaDeleted;

  /// No description provided for @deleteServiceAreaConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this service area? Customers outside the remaining areas will no longer be able to order.'**
  String get deleteServiceAreaConfirm;

  /// No description provided for @kmUnit.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get kmUnit;

  /// No description provided for @areaActive.
  ///
  /// In en, this message translates to:
  /// **'Area is active'**
  String get areaActive;

  /// No description provided for @areaActiveDesc.
  ///
  /// In en, this message translates to:
  /// **'Inactive areas do not count towards coverage.'**
  String get areaActiveDesc;

  /// No description provided for @operations.
  ///
  /// In en, this message translates to:
  /// **'Operations'**
  String get operations;

  /// No description provided for @catalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get catalog;

  /// No description provided for @growth.
  ///
  /// In en, this message translates to:
  /// **'Growth'**
  String get growth;

  /// No description provided for @people.
  ///
  /// In en, this message translates to:
  /// **'People'**
  String get people;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @attachment.
  ///
  /// In en, this message translates to:
  /// **'Attachment'**
  String get attachment;

  /// No description provided for @attachmentUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Attachment unavailable'**
  String get attachmentUnavailable;

  /// No description provided for @attachmentOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open this file.'**
  String get attachmentOpenFailed;

  /// No description provided for @attachPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get attachPhoto;

  /// No description provided for @attachCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get attachCamera;

  /// No description provided for @attachFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get attachFile;

  /// No description provided for @attachSomething.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get attachSomething;

  /// No description provided for @attachmentUploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not upload that attachment.'**
  String get attachmentUploadFailed;

  /// No description provided for @howCanWeHelp.
  ///
  /// In en, this message translates to:
  /// **'How can we help?'**
  String get howCanWeHelp;

  /// No description provided for @pickTopicOrWrite.
  ///
  /// In en, this message translates to:
  /// **'Pick a topic for an instant answer, or write to us directly.'**
  String get pickTopicOrWrite;

  /// No description provided for @supportOtherTopic.
  ///
  /// In en, this message translates to:
  /// **'Something else'**
  String get supportOtherTopic;

  /// No description provided for @automaticReply.
  ///
  /// In en, this message translates to:
  /// **'Automatic reply'**
  String get automaticReply;

  /// No description provided for @errNetwork.
  ///
  /// In en, this message translates to:
  /// **'No connection. Check your internet and try again.'**
  String get errNetwork;

  /// No description provided for @errSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session has ended. Sign in again.'**
  String get errSessionExpired;

  /// No description provided for @errNoPermission.
  ///
  /// In en, this message translates to:
  /// **'You do not have permission to do that. If your account or store was suspended, contact support.'**
  String get errNoPermission;

  /// No description provided for @errNotFound.
  ///
  /// In en, this message translates to:
  /// **'That is no longer available.'**
  String get errNotFound;

  /// No description provided for @errServer.
  ///
  /// In en, this message translates to:
  /// **'The server had a problem. Try again in a moment.'**
  String get errServer;

  /// No description provided for @errUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Please try again.'**
  String get errUnknown;

  /// No description provided for @errCartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty.'**
  String get errCartEmpty;

  /// No description provided for @errVendorClosed.
  ///
  /// In en, this message translates to:
  /// **'This store is currently closed.'**
  String get errVendorClosed;

  /// No description provided for @errVendorNotApproved.
  ///
  /// In en, this message translates to:
  /// **'This store is not approved yet.'**
  String get errVendorNotApproved;

  /// No description provided for @errAddressNotFound.
  ///
  /// In en, this message translates to:
  /// **'Please choose a delivery address.'**
  String get errAddressNotFound;

  /// No description provided for @errOutsideServiceArea.
  ///
  /// In en, this message translates to:
  /// **'We don\'t deliver to this address yet. Pick another address inside our delivery area.'**
  String get errOutsideServiceArea;

  /// No description provided for @errRoleAlreadySet.
  ///
  /// In en, this message translates to:
  /// **'Your account type has already been set.'**
  String get errRoleAlreadySet;

  /// No description provided for @errRoleChangeNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Account type cannot be changed here.'**
  String get errRoleChangeNotAllowed;

  /// No description provided for @errCouponInvalid.
  ///
  /// In en, this message translates to:
  /// **'This coupon code is not valid.'**
  String get errCouponInvalid;

  /// No description provided for @errCouponMinOrder.
  ///
  /// In en, this message translates to:
  /// **'Order total is below the coupon minimum.'**
  String get errCouponMinOrder;

  /// No description provided for @errMinOrderNotMet.
  ///
  /// In en, this message translates to:
  /// **'Order total is below the store minimum.'**
  String get errMinOrderNotMet;

  /// No description provided for @errNotAnOnlineDriver.
  ///
  /// In en, this message translates to:
  /// **'Go online to claim orders. A new driver account needs admin approval first.'**
  String get errNotAnOnlineDriver;

  /// No description provided for @errDriverNotApproved.
  ///
  /// In en, this message translates to:
  /// **'Your driver account is awaiting admin approval. You can go online once it is approved.'**
  String get errDriverNotApproved;

  /// No description provided for @errInsufficientWallet.
  ///
  /// In en, this message translates to:
  /// **'Your wallet balance is not enough for this order.'**
  String get errInsufficientWallet;

  /// No description provided for @errCardPaymentsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Card payments are unavailable right now. Please try another method.'**
  String get errCardPaymentsUnavailable;

  /// No description provided for @errPaymentPageFailed.
  ///
  /// In en, this message translates to:
  /// **'The payment page could not be opened. Please try again.'**
  String get errPaymentPageFailed;

  /// No description provided for @errAlreadyPaid.
  ///
  /// In en, this message translates to:
  /// **'This order has already been paid.'**
  String get errAlreadyPaid;

  /// No description provided for @errAlreadyRefunded.
  ///
  /// In en, this message translates to:
  /// **'This order has already been refunded.'**
  String get errAlreadyRefunded;

  /// No description provided for @errOrderNotPaid.
  ///
  /// In en, this message translates to:
  /// **'This order was never paid, nothing to refund.'**
  String get errOrderNotPaid;

  /// No description provided for @errOrderNotCancelled.
  ///
  /// In en, this message translates to:
  /// **'Only cancelled or rejected orders can be refunded.'**
  String get errOrderNotCancelled;

  /// No description provided for @errNotACardOrder.
  ///
  /// In en, this message translates to:
  /// **'Only card-paid orders can be refunded to the wallet.'**
  String get errNotACardOrder;

  /// No description provided for @errProductUnavailable.
  ///
  /// In en, this message translates to:
  /// **'An item in your cart is no longer available.'**
  String get errProductUnavailable;

  /// No description provided for @errTransitionNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'This order was already updated. Refreshing…'**
  String get errTransitionNotAllowed;

  /// No description provided for @errAccountBlocked.
  ///
  /// In en, this message translates to:
  /// **'This account has been suspended. Contact support if you think that is a mistake.'**
  String get errAccountBlocked;

  /// No description provided for @errHasActiveOrders.
  ///
  /// In en, this message translates to:
  /// **'You still have an order in progress. You can delete your account once it is finished.'**
  String get errHasActiveOrders;

  /// No description provided for @errWalletHasBalance.
  ///
  /// In en, this message translates to:
  /// **'Your wallet still has a balance. Confirm you accept losing it to continue.'**
  String get errWalletHasBalance;

  /// No description provided for @errCannotBlockSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot block your own account.'**
  String get errCannotBlockSelf;

  /// No description provided for @errCannotDeleteSelf.
  ///
  /// In en, this message translates to:
  /// **'You cannot delete your own account from here.'**
  String get errCannotDeleteSelf;

  /// No description provided for @errCannotBlockAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin accounts cannot be blocked.'**
  String get errCannotBlockAdmin;

  /// No description provided for @errCannotDeleteAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin accounts cannot be deleted.'**
  String get errCannotDeleteAdmin;

  /// No description provided for @errInvalidLogin.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get errInvalidLogin;

  /// No description provided for @errEmailNotConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirm your email address first, then sign in.'**
  String get errEmailNotConfirmed;

  /// No description provided for @errUserAlreadyExists.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists.'**
  String get errUserAlreadyExists;

  /// No description provided for @errWeakPassword.
  ///
  /// In en, this message translates to:
  /// **'Password is too short.'**
  String get errWeakPassword;

  /// No description provided for @errDuplicate.
  ///
  /// In en, this message translates to:
  /// **'That already exists.'**
  String get errDuplicate;

  /// No description provided for @errStillReferenced.
  ///
  /// In en, this message translates to:
  /// **'This is still in use elsewhere and cannot be removed.'**
  String get errStillReferenced;

  /// No description provided for @paymentCancelledNotice.
  ///
  /// In en, this message translates to:
  /// **'Payment cancelled. The order was not sent to the restaurant.'**
  String get paymentCancelledNotice;

  /// No description provided for @paymentFailedNotice.
  ///
  /// In en, this message translates to:
  /// **'Payment failed. The order was not sent to the restaurant.'**
  String get paymentFailedNotice;

  /// No description provided for @paymentPendingNotice.
  ///
  /// In en, this message translates to:
  /// **'Still confirming your payment with the bank. The restaurant is notified only once it is confirmed.'**
  String get paymentPendingNotice;

  /// No description provided for @errLocationPermission.
  ///
  /// In en, this message translates to:
  /// **'Location permission is needed to share your position.'**
  String get errLocationPermission;

  /// No description provided for @errOrderTaken.
  ///
  /// In en, this message translates to:
  /// **'Another driver took this order.'**
  String get errOrderTaken;

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @manageSections.
  ///
  /// In en, this message translates to:
  /// **'Manage sections'**
  String get manageSections;

  /// No description provided for @reorderSections.
  ///
  /// In en, this message translates to:
  /// **'Drag to reorder sections'**
  String get reorderSections;

  /// No description provided for @searchMenuHint.
  ///
  /// In en, this message translates to:
  /// **'Search items'**
  String get searchMenuHint;

  /// No description provided for @sections.
  ///
  /// In en, this message translates to:
  /// **'Sections'**
  String get sections;

  /// No description provided for @duplicateItem.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get duplicateItem;

  /// No description provided for @moveToSection.
  ///
  /// In en, this message translates to:
  /// **'Move to section'**
  String get moveToSection;

  /// No description provided for @deleteItem.
  ///
  /// In en, this message translates to:
  /// **'Delete item'**
  String get deleteItem;

  /// No description provided for @deleteItemConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this item? It disappears from the menu straight away. Past orders keep it.'**
  String get deleteItemConfirm;

  /// No description provided for @deleteSectionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this section? Its items stay on the menu and move to Uncategorized.'**
  String get deleteSectionConfirm;

  /// No description provided for @itemDuplicated.
  ///
  /// In en, this message translates to:
  /// **'Copy created and left sold out until you edit it.'**
  String get itemDuplicated;

  /// No description provided for @itemDeleted.
  ///
  /// In en, this message translates to:
  /// **'Item deleted'**
  String get itemDeleted;

  /// No description provided for @sectionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Section deleted'**
  String get sectionDeleted;

  /// No description provided for @markSectionSoldOut.
  ///
  /// In en, this message translates to:
  /// **'Mark section sold out'**
  String get markSectionSoldOut;

  /// No description provided for @markSectionAvailable.
  ///
  /// In en, this message translates to:
  /// **'Mark section available'**
  String get markSectionAvailable;

  /// No description provided for @markAllSoldOut.
  ///
  /// In en, this message translates to:
  /// **'Mark everything sold out'**
  String get markAllSoldOut;

  /// No description provided for @markAllAvailable.
  ///
  /// In en, this message translates to:
  /// **'Mark everything available'**
  String get markAllAvailable;

  /// No description provided for @itemsUpdatedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items updated'**
  String itemsUpdatedCount(int count);

  /// No description provided for @sortManual.
  ///
  /// In en, this message translates to:
  /// **'My order'**
  String get sortManual;

  /// No description provided for @sortNameAsc.
  ///
  /// In en, this message translates to:
  /// **'Name A–Z'**
  String get sortNameAsc;

  /// No description provided for @sortPriceAsc.
  ///
  /// In en, this message translates to:
  /// **'Price, low to high'**
  String get sortPriceAsc;

  /// No description provided for @sortPriceDesc.
  ///
  /// In en, this message translates to:
  /// **'Price, high to low'**
  String get sortPriceDesc;

  /// No description provided for @noMatchingItems.
  ///
  /// In en, this message translates to:
  /// **'No items match your search.'**
  String get noMatchingItems;

  /// No description provided for @optionGroupsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} option groups'**
  String optionGroupsCount(int count);

  /// No description provided for @dragToReorderItems.
  ///
  /// In en, this message translates to:
  /// **'Hold and drag an item to reorder the menu.'**
  String get dragToReorderItems;

  /// No description provided for @reorderUnavailableWhileFiltered.
  ///
  /// In en, this message translates to:
  /// **'Reordering works in “My order” with no search or filter.'**
  String get reorderUnavailableWhileFiltered;

  /// No description provided for @menuStats.
  ///
  /// In en, this message translates to:
  /// **'{items} items · {sections} sections · {soldOut} sold out'**
  String menuStats(int items, int sections, int soldOut);

  /// No description provided for @sectionHasNoItems.
  ///
  /// In en, this message translates to:
  /// **'This section has no items yet.'**
  String get sectionHasNoItems;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @reviews.
  ///
  /// In en, this message translates to:
  /// **'Reviews'**
  String get reviews;

  /// No description provided for @ratingsAndReviews.
  ///
  /// In en, this message translates to:
  /// **'Ratings & reviews'**
  String get ratingsAndReviews;

  /// No description provided for @noReviewsYet.
  ///
  /// In en, this message translates to:
  /// **'No reviews yet. Be the first to leave one.'**
  String get noReviewsYet;

  /// No description provided for @seeAllReviews.
  ///
  /// In en, this message translates to:
  /// **'See all reviews'**
  String get seeAllReviews;

  /// No description provided for @basedOnReviews.
  ///
  /// In en, this message translates to:
  /// **'{count} reviews'**
  String basedOnReviews(int count);

  /// No description provided for @rateTheStore.
  ///
  /// In en, this message translates to:
  /// **'How was the food?'**
  String get rateTheStore;

  /// No description provided for @howWasTheDriver.
  ///
  /// In en, this message translates to:
  /// **'How was the delivery?'**
  String get howWasTheDriver;

  /// No description provided for @anonymous.
  ///
  /// In en, this message translates to:
  /// **'A customer'**
  String get anonymous;

  /// No description provided for @reviewsInbox.
  ///
  /// In en, this message translates to:
  /// **'Customer feedback'**
  String get reviewsInbox;

  /// No description provided for @averageRating.
  ///
  /// In en, this message translates to:
  /// **'Average rating'**
  String get averageRating;

  /// No description provided for @skipDriverRating.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skipDriverRating;

  /// No description provided for @estimatedArrival.
  ///
  /// In en, this message translates to:
  /// **'Arriving in about {minutes} min'**
  String estimatedArrival(int minutes);

  /// No description provided for @arrivingSoon.
  ///
  /// In en, this message translates to:
  /// **'Arriving any minute'**
  String get arrivingSoon;

  /// No description provided for @deliveredAtTime.
  ///
  /// In en, this message translates to:
  /// **'Delivered at {time}'**
  String deliveredAtTime(String time);

  /// No description provided for @etaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'On the way'**
  String get etaUnavailable;

  /// No description provided for @dishes.
  ///
  /// In en, this message translates to:
  /// **'Dishes'**
  String get dishes;

  /// No description provided for @matchesOnMenu.
  ///
  /// In en, this message translates to:
  /// **'On the menu: {items}'**
  String matchesOnMenu(String items);

  /// No description provided for @storesLabel.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get storesLabel;

  /// No description provided for @cartItemsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some items are no longer available'**
  String get cartItemsUnavailable;

  /// No description provided for @removeUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Remove them'**
  String get removeUnavailable;

  /// No description provided for @cartPricesChanged.
  ///
  /// In en, this message translates to:
  /// **'Prices changed since you added these. The new prices are shown.'**
  String get cartPricesChanged;

  /// No description provided for @unavailableNow.
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get unavailableNow;

  /// No description provided for @newPrice.
  ///
  /// In en, this message translates to:
  /// **'New price'**
  String get newPrice;

  /// No description provided for @reorderTitle.
  ///
  /// In en, this message translates to:
  /// **'Order again'**
  String get reorderTitle;

  /// No description provided for @reorderNothingAvailable.
  ///
  /// In en, this message translates to:
  /// **'None of these items are on the menu any more.'**
  String get reorderNothingAvailable;

  /// No description provided for @reorderStoreClosed.
  ///
  /// In en, this message translates to:
  /// **'{store} is closed right now. Add the items to your cart anyway?'**
  String reorderStoreClosed(String store);

  /// No description provided for @reorderStoreInactive.
  ///
  /// In en, this message translates to:
  /// **'{store} is not taking orders at the moment.'**
  String reorderStoreInactive(String store);

  /// No description provided for @reorderReplaceCart.
  ///
  /// In en, this message translates to:
  /// **'Your cart has items from {store}. Replacing it with this order?'**
  String reorderReplaceCart(String store);

  /// No description provided for @reorderSomeMissing.
  ///
  /// In en, this message translates to:
  /// **'{count} items are no longer available and were left out.'**
  String reorderSomeMissing(int count);

  /// No description provided for @reorderOptionsChanged.
  ///
  /// In en, this message translates to:
  /// **'Some choices are no longer offered and were left out.'**
  String get reorderOptionsChanged;

  /// No description provided for @reorderAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to your cart'**
  String get reorderAdded;

  /// No description provided for @addAnyway.
  ///
  /// In en, this message translates to:
  /// **'Add anyway'**
  String get addAnyway;

  /// No description provided for @replaceCart.
  ///
  /// In en, this message translates to:
  /// **'Replace cart'**
  String get replaceCart;

  /// No description provided for @okLabel.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get okLabel;

  /// No description provided for @errCouponNotStarted.
  ///
  /// In en, this message translates to:
  /// **'This offer hasn\'t started yet.'**
  String get errCouponNotStarted;

  /// No description provided for @errCouponExpired.
  ///
  /// In en, this message translates to:
  /// **'This offer has expired.'**
  String get errCouponExpired;

  /// No description provided for @errCouponExhausted.
  ///
  /// In en, this message translates to:
  /// **'This offer has been fully claimed.'**
  String get errCouponExhausted;

  /// No description provided for @errCouponAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'You have already used this code.'**
  String get errCouponAlreadyUsed;

  /// No description provided for @errCouponFirstOrderOnly.
  ///
  /// In en, this message translates to:
  /// **'This code is for your first order only.'**
  String get errCouponFirstOrderOnly;

  /// No description provided for @errCouponWrongVendor.
  ///
  /// In en, this message translates to:
  /// **'This code does not work at this store.'**
  String get errCouponWrongVendor;

  /// No description provided for @errPlatformTermsAdminOnly.
  ///
  /// In en, this message translates to:
  /// **'Delivery fee and commission are set by the platform.'**
  String get errPlatformTermsAdminOnly;

  /// No description provided for @errBillingModelLocked.
  ///
  /// In en, this message translates to:
  /// **'Your billing plan is set. Contact support to change it.'**
  String get errBillingModelLocked;

  /// No description provided for @setByPlatform.
  ///
  /// In en, this message translates to:
  /// **'Set by the platform'**
  String get setByPlatform;

  /// No description provided for @billingPlan.
  ///
  /// In en, this message translates to:
  /// **'Billing plan'**
  String get billingPlan;

  /// No description provided for @billingCommission.
  ///
  /// In en, this message translates to:
  /// **'Commission'**
  String get billingCommission;

  /// No description provided for @billingSubscription.
  ///
  /// In en, this message translates to:
  /// **'Fixed subscription'**
  String get billingSubscription;

  /// No description provided for @billingCommissionDesc.
  ///
  /// In en, this message translates to:
  /// **'No monthly fee. The platform takes {rate}% of each order.'**
  String billingCommissionDesc(String rate);

  /// No description provided for @billingSubscriptionDesc.
  ///
  /// In en, this message translates to:
  /// **'A fixed fee per month. The platform takes nothing per order.'**
  String get billingSubscriptionDesc;

  /// No description provided for @choosePlan.
  ///
  /// In en, this message translates to:
  /// **'Choose how you pay'**
  String get choosePlan;

  /// No description provided for @choosePlanDesc.
  ///
  /// In en, this message translates to:
  /// **'Pick the plan that suits your volume. You can ask support to change it later.'**
  String get choosePlanDesc;

  /// No description provided for @callStore.
  ///
  /// In en, this message translates to:
  /// **'Call the store'**
  String get callStore;

  /// No description provided for @noStorePhone.
  ///
  /// In en, this message translates to:
  /// **'This store has no phone number on file.'**
  String get noStorePhone;

  /// No description provided for @couponTypeFreeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Free delivery'**
  String get couponTypeFreeDelivery;

  /// No description provided for @perCustomerLimit.
  ///
  /// In en, this message translates to:
  /// **'Uses per customer'**
  String get perCustomerLimit;

  /// No description provided for @perCustomerUnlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited per customer'**
  String get perCustomerUnlimited;

  /// No description provided for @totalUsageLimit.
  ///
  /// In en, this message translates to:
  /// **'Total uses (optional)'**
  String get totalUsageLimit;

  /// No description provided for @couponStartsAt.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get couponStartsAt;

  /// No description provided for @couponExpiresAt.
  ///
  /// In en, this message translates to:
  /// **'Expires'**
  String get couponExpiresAt;

  /// No description provided for @couponFirstOrderOnly.
  ///
  /// In en, this message translates to:
  /// **'First order only'**
  String get couponFirstOrderOnly;

  /// No description provided for @couponFirstOrderOnlyDesc.
  ///
  /// In en, this message translates to:
  /// **'Only for customers who have never had an order delivered.'**
  String get couponFirstOrderOnlyDesc;

  /// No description provided for @couponPublic.
  ///
  /// In en, this message translates to:
  /// **'Show on the offers page'**
  String get couponPublic;

  /// No description provided for @couponPublicDesc.
  ///
  /// In en, this message translates to:
  /// **'Customers see it without having to know the code.'**
  String get couponPublicDesc;

  /// No description provided for @couponTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Campaign name (optional)'**
  String get couponTitleLabel;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearDate;

  /// No description provided for @couponScheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get couponScheduled;

  /// No description provided for @couponExhausted.
  ///
  /// In en, this message translates to:
  /// **'Fully claimed'**
  String get couponExhausted;

  /// No description provided for @couponRedemptions.
  ///
  /// In en, this message translates to:
  /// **'Redemptions'**
  String get couponRedemptions;

  /// No description provided for @oncePerCustomer.
  ///
  /// In en, this message translates to:
  /// **'Once per customer'**
  String get oncePerCustomer;

  /// No description provided for @usesPerCustomer.
  ///
  /// In en, this message translates to:
  /// **'{count}x per customer'**
  String usesPerCustomer(int count);

  /// No description provided for @platformTerms.
  ///
  /// In en, this message translates to:
  /// **'Platform terms'**
  String get platformTerms;

  /// No description provided for @commissionRate.
  ///
  /// In en, this message translates to:
  /// **'Commission rate'**
  String get commissionRate;

  /// No description provided for @subscriptionFee.
  ///
  /// In en, this message translates to:
  /// **'Subscription fee'**
  String get subscriptionFee;

  /// No description provided for @editTerms.
  ///
  /// In en, this message translates to:
  /// **'Edit terms'**
  String get editTerms;

  /// No description provided for @termsSaved.
  ///
  /// In en, this message translates to:
  /// **'Terms updated'**
  String get termsSaved;

  /// No description provided for @youMightAlsoLike.
  ///
  /// In en, this message translates to:
  /// **'You might also like'**
  String get youMightAlsoLike;

  /// No description provided for @goesWellWith.
  ///
  /// In en, this message translates to:
  /// **'Goes well with'**
  String get goesWellWith;

  /// No description provided for @managementRoles.
  ///
  /// In en, this message translates to:
  /// **'Management roles'**
  String get managementRoles;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staff;

  /// No description provided for @auditTrail.
  ///
  /// In en, this message translates to:
  /// **'Audit trail'**
  String get auditTrail;

  /// No description provided for @newRole.
  ///
  /// In en, this message translates to:
  /// **'New role'**
  String get newRole;

  /// No description provided for @editRole.
  ///
  /// In en, this message translates to:
  /// **'Edit role'**
  String get editRole;

  /// No description provided for @roleName.
  ///
  /// In en, this message translates to:
  /// **'Role name'**
  String get roleName;

  /// No description provided for @roleNameArabic.
  ///
  /// In en, this message translates to:
  /// **'Role name (Arabic)'**
  String get roleNameArabic;

  /// No description provided for @permissions.
  ///
  /// In en, this message translates to:
  /// **'Permissions'**
  String get permissions;

  /// No description provided for @permissionsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} permissions'**
  String permissionsCount(int count);

  /// No description provided for @unrestricted.
  ///
  /// In en, this message translates to:
  /// **'Full access'**
  String get unrestricted;

  /// No description provided for @unrestrictedDesc.
  ///
  /// In en, this message translates to:
  /// **'No role assigned — can do everything.'**
  String get unrestrictedDesc;

  /// No description provided for @assignRole.
  ///
  /// In en, this message translates to:
  /// **'Assign role'**
  String get assignRole;

  /// No description provided for @roleInUse.
  ///
  /// In en, this message translates to:
  /// **'Reassign the people holding this role before deleting it.'**
  String get roleInUse;

  /// No description provided for @roleSaved.
  ///
  /// In en, this message translates to:
  /// **'Role saved'**
  String get roleSaved;

  /// No description provided for @roleDeleted.
  ///
  /// In en, this message translates to:
  /// **'Role deleted'**
  String get roleDeleted;

  /// No description provided for @roleAssigned.
  ///
  /// In en, this message translates to:
  /// **'Role assigned'**
  String get roleAssigned;

  /// No description provided for @noStaffYet.
  ///
  /// In en, this message translates to:
  /// **'No admin accounts yet.'**
  String get noStaffYet;

  /// No description provided for @noAuditYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing has been done yet.'**
  String get noAuditYet;

  /// No description provided for @permGroupOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get permGroupOrders;

  /// No description provided for @permGroupVendors.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get permGroupVendors;

  /// No description provided for @permGroupCatalogue.
  ///
  /// In en, this message translates to:
  /// **'Catalogue & marketing'**
  String get permGroupCatalogue;

  /// No description provided for @permGroupDrivers.
  ///
  /// In en, this message translates to:
  /// **'Drivers'**
  String get permGroupDrivers;

  /// No description provided for @permGroupUsers.
  ///
  /// In en, this message translates to:
  /// **'Users & staff'**
  String get permGroupUsers;

  /// No description provided for @permGroupSupport.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get permGroupSupport;

  /// No description provided for @permGroupFinance.
  ///
  /// In en, this message translates to:
  /// **'Finance'**
  String get permGroupFinance;

  /// No description provided for @cannotChangeOwnRole.
  ///
  /// In en, this message translates to:
  /// **'You cannot change your own role.'**
  String get cannotChangeOwnRole;

  /// No description provided for @deleteRoleConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this role? Nobody may be holding it.'**
  String get deleteRoleConfirm;

  /// No description provided for @errCannotChangeOwnRole.
  ///
  /// In en, this message translates to:
  /// **'You cannot change your own role.'**
  String get errCannotChangeOwnRole;

  /// No description provided for @errRoleInUse.
  ///
  /// In en, this message translates to:
  /// **'Reassign the people holding this role before deleting it.'**
  String get errRoleInUse;

  /// No description provided for @errNotAnAdmin.
  ///
  /// In en, this message translates to:
  /// **'That account is not an admin.'**
  String get errNotAnAdmin;

  /// No description provided for @announcements.
  ///
  /// In en, this message translates to:
  /// **'Announcements'**
  String get announcements;

  /// No description provided for @newAnnouncement.
  ///
  /// In en, this message translates to:
  /// **'New announcement'**
  String get newAnnouncement;

  /// No description provided for @sendNow.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get sendNow;

  /// No description provided for @audience.
  ///
  /// In en, this message translates to:
  /// **'Audience'**
  String get audience;

  /// No description provided for @audienceAll.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get audienceAll;

  /// No description provided for @audienceCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get audienceCustomers;

  /// No description provided for @audienceVendors.
  ///
  /// In en, this message translates to:
  /// **'Stores'**
  String get audienceVendors;

  /// No description provided for @audienceDrivers.
  ///
  /// In en, this message translates to:
  /// **'Drivers'**
  String get audienceDrivers;

  /// No description provided for @reachableDevices.
  ///
  /// In en, this message translates to:
  /// **'{count} devices can be reached'**
  String reachableDevices(int count);

  /// No description provided for @announcementTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get announcementTitle;

  /// No description provided for @announcementBody.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get announcementBody;

  /// No description provided for @deepLinkOptional.
  ///
  /// In en, this message translates to:
  /// **'Open this screen on tap (optional)'**
  String get deepLinkOptional;

  /// No description provided for @campaignSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to {delivered} of {recipients} devices'**
  String campaignSent(int delivered, int recipients);

  /// No description provided for @campaignSendConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send this to {count} devices? It cannot be unsent.'**
  String campaignSendConfirm(int count);

  /// No description provided for @noCampaignsYet.
  ///
  /// In en, this message translates to:
  /// **'No announcements yet.'**
  String get noCampaignsYet;

  /// No description provided for @statusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get statusDraft;

  /// No description provided for @statusSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get statusSending;

  /// No description provided for @statusSent.
  ///
  /// In en, this message translates to:
  /// **'Sent'**
  String get statusSent;

  /// No description provided for @statusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get statusFailed;

  /// No description provided for @deliveredOf.
  ///
  /// In en, this message translates to:
  /// **'{delivered} delivered · {failed} failed'**
  String deliveredOf(int delivered, int failed);

  /// No description provided for @saveAsDraft.
  ///
  /// In en, this message translates to:
  /// **'Save as draft'**
  String get saveAsDraft;

  /// No description provided for @draftSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved as draft'**
  String get draftSaved;

  /// No description provided for @campaignNothingToReach.
  ///
  /// In en, this message translates to:
  /// **'Nobody in this audience can receive notifications yet.'**
  String get campaignNothingToReach;

  /// No description provided for @drafts.
  ///
  /// In en, this message translates to:
  /// **'Drafts'**
  String get drafts;

  /// No description provided for @resend.
  ///
  /// In en, this message translates to:
  /// **'Send again'**
  String get resend;

  /// No description provided for @resendConfirm.
  ///
  /// In en, this message translates to:
  /// **'Send this again to {count} devices? It goes out as a new announcement.'**
  String resendConfirm(int count);

  /// No description provided for @addStaff.
  ///
  /// In en, this message translates to:
  /// **'Add staff'**
  String get addStaff;

  /// No description provided for @createNewLogin.
  ///
  /// In en, this message translates to:
  /// **'Create a new login'**
  String get createNewLogin;

  /// No description provided for @createNewLoginDesc.
  ///
  /// In en, this message translates to:
  /// **'Email and password for someone who has no account yet.'**
  String get createNewLoginDesc;

  /// No description provided for @promoteExisting.
  ///
  /// In en, this message translates to:
  /// **'Promote an existing user'**
  String get promoteExisting;

  /// No description provided for @promoteExistingDesc.
  ///
  /// In en, this message translates to:
  /// **'Give an account that already exists a management role.'**
  String get promoteExistingDesc;

  /// No description provided for @searchUsersHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name, email or phone'**
  String get searchUsersHint;

  /// No description provided for @searchMinChars.
  ///
  /// In en, this message translates to:
  /// **'Type at least 3 characters.'**
  String get searchMinChars;

  /// No description provided for @noUsersFound.
  ///
  /// In en, this message translates to:
  /// **'Nobody matched that.'**
  String get noUsersFound;

  /// No description provided for @alreadyStaff.
  ///
  /// In en, this message translates to:
  /// **'Already staff'**
  String get alreadyStaff;

  /// No description provided for @staffCreated.
  ///
  /// In en, this message translates to:
  /// **'Staff account created'**
  String get staffCreated;

  /// No description provided for @staffPromoted.
  ///
  /// In en, this message translates to:
  /// **'Added to staff'**
  String get staffPromoted;

  /// No description provided for @staffRevoked.
  ///
  /// In en, this message translates to:
  /// **'Removed from staff'**
  String get staffRevoked;

  /// No description provided for @removeFromStaff.
  ///
  /// In en, this message translates to:
  /// **'Remove from staff'**
  String get removeFromStaff;

  /// No description provided for @removeFromStaffConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove this person from staff? They keep their account and history, but lose admin access.'**
  String get removeFromStaffConfirm;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @passwordMin.
  ///
  /// In en, this message translates to:
  /// **'At least 8 characters'**
  String get passwordMin;

  /// No description provided for @roleForNewStaff.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get roleForNewStaff;

  /// No description provided for @ownerFullAccess.
  ///
  /// In en, this message translates to:
  /// **'Owner — full access'**
  String get ownerFullAccess;

  /// No description provided for @errUserAlreadyExists2.
  ///
  /// In en, this message translates to:
  /// **'An account with this email already exists. Promote it instead.'**
  String get errUserAlreadyExists2;

  /// No description provided for @errCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'The account could not be created.'**
  String get errCreateFailed;

  /// No description provided for @ownsStore.
  ///
  /// In en, this message translates to:
  /// **'Owns a store'**
  String get ownsStore;

  /// No description provided for @isDriverAccount.
  ///
  /// In en, this message translates to:
  /// **'Driver account'**
  String get isDriverAccount;

  /// No description provided for @conflictWarning.
  ///
  /// In en, this message translates to:
  /// **'This account also operates on the platform. Admin rights let it approve or promote itself.'**
  String get conflictWarning;

  /// No description provided for @staffRestoredTo.
  ///
  /// In en, this message translates to:
  /// **'Removed from staff — restored to {role}'**
  String staffRestoredTo(String role);

  /// No description provided for @errCannotPromoteVendor.
  ///
  /// In en, this message translates to:
  /// **'A store owner cannot be made an admin — they would be able to approve and price their own store.'**
  String get errCannotPromoteVendor;

  /// No description provided for @errCannotPromoteDriver.
  ///
  /// In en, this message translates to:
  /// **'A driver cannot be made an admin — they would be able to approve their own account.'**
  String get errCannotPromoteDriver;

  /// No description provided for @nationalIdSection.
  ///
  /// In en, this message translates to:
  /// **'National ID'**
  String get nationalIdSection;

  /// No description provided for @idFront.
  ///
  /// In en, this message translates to:
  /// **'ID front'**
  String get idFront;

  /// No description provided for @idBack.
  ///
  /// In en, this message translates to:
  /// **'ID back'**
  String get idBack;

  /// No description provided for @vehicleLicenseSection.
  ///
  /// In en, this message translates to:
  /// **'Vehicle licence'**
  String get vehicleLicenseSection;

  /// No description provided for @licenseFront.
  ///
  /// In en, this message translates to:
  /// **'Licence front'**
  String get licenseFront;

  /// No description provided for @licenseBack.
  ///
  /// In en, this message translates to:
  /// **'Licence back'**
  String get licenseBack;

  /// No description provided for @categoryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Category name'**
  String get categoryNameLabel;

  /// No description provided for @resolveComplaint.
  ///
  /// In en, this message translates to:
  /// **'Resolve customer complaint'**
  String get resolveComplaint;

  /// No description provided for @complaintReplyHint.
  ///
  /// In en, this message translates to:
  /// **'Reply to the customer…'**
  String get complaintReplyHint;

  /// No description provided for @sendAndResolve.
  ///
  /// In en, this message translates to:
  /// **'Send & resolve'**
  String get sendAndResolve;

  /// No description provided for @pendingLabel.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get pendingLabel;

  /// No description provided for @resolvedLabel.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get resolvedLabel;

  /// No description provided for @noComplaints.
  ///
  /// In en, this message translates to:
  /// **'No complaints or reports found.'**
  String get noComplaints;

  /// No description provided for @viewDocument.
  ///
  /// In en, this message translates to:
  /// **'View {document}'**
  String viewDocument(String document);

  /// No description provided for @uploadReplaceDocument.
  ///
  /// In en, this message translates to:
  /// **'Upload / replace {document}'**
  String uploadReplaceDocument(String document);

  /// No description provided for @rejectSuspendDriver.
  ///
  /// In en, this message translates to:
  /// **'Reject / suspend driver'**
  String get rejectSuspendDriver;

  /// No description provided for @rejectionReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason for rejection (e.g. invalid licence)'**
  String get rejectionReasonHint;

  /// No description provided for @driverApprovals.
  ///
  /// In en, this message translates to:
  /// **'Driver approvals & accounts'**
  String get driverApprovals;

  /// No description provided for @salesAndFinancialReports.
  ///
  /// In en, this message translates to:
  /// **'Sales & financial reports'**
  String get salesAndFinancialReports;

  /// No description provided for @allWithCount.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String allWithCount(int count);

  /// No description provided for @pendingWithCount.
  ///
  /// In en, this message translates to:
  /// **'Pending ({count})'**
  String pendingWithCount(int count);

  /// No description provided for @approvedWithCount.
  ///
  /// In en, this message translates to:
  /// **'Approved ({count})'**
  String approvedWithCount(int count);

  /// No description provided for @suspendedWithCount.
  ///
  /// In en, this message translates to:
  /// **'Suspended ({count})'**
  String suspendedWithCount(int count);

  /// No description provided for @nationalIdCard.
  ///
  /// In en, this message translates to:
  /// **'National ID card'**
  String get nationalIdCard;

  /// No description provided for @driverLicence.
  ///
  /// In en, this message translates to:
  /// **'Driver licence'**
  String get driverLicence;

  /// No description provided for @optionalUpTo.
  ///
  /// In en, this message translates to:
  /// **'Optional · up to {count}'**
  String optionalUpTo(int count);

  /// No description provided for @cartFromOtherStore.
  ///
  /// In en, this message translates to:
  /// **'Your cart has items from {store}. Adding this item will clear it.'**
  String cartFromOtherStore(String store);

  /// No description provided for @promoCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'CODE'**
  String get promoCodeLabel;

  /// No description provided for @subjectLine.
  ///
  /// In en, this message translates to:
  /// **'Subject: {subject}'**
  String subjectLine(String subject);

  /// No description provided for @complaintFallback.
  ///
  /// In en, this message translates to:
  /// **'Complaint'**
  String get complaintFallback;

  /// No description provided for @adManager.
  ///
  /// In en, this message translates to:
  /// **'Ads'**
  String get adManager;

  /// No description provided for @newAd.
  ///
  /// In en, this message translates to:
  /// **'New ad'**
  String get newAd;

  /// No description provided for @adPlacement.
  ///
  /// In en, this message translates to:
  /// **'Placement'**
  String get adPlacement;

  /// No description provided for @placementHomeCarousel.
  ///
  /// In en, this message translates to:
  /// **'Home carousel'**
  String get placementHomeCarousel;

  /// No description provided for @placementHomeInline.
  ///
  /// In en, this message translates to:
  /// **'Home — between sections'**
  String get placementHomeInline;

  /// No description provided for @placementVendorTop.
  ///
  /// In en, this message translates to:
  /// **'Store page — top'**
  String get placementVendorTop;

  /// No description provided for @placementCart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get placementCart;

  /// No description provided for @placementOrderTracking.
  ///
  /// In en, this message translates to:
  /// **'Order tracking'**
  String get placementOrderTracking;

  /// No description provided for @adMedia.
  ///
  /// In en, this message translates to:
  /// **'Media'**
  String get adMedia;

  /// No description provided for @adImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get adImage;

  /// No description provided for @adVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get adVideo;

  /// No description provided for @adVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Video URL'**
  String get adVideoUrl;

  /// No description provided for @adLinkUrl.
  ///
  /// In en, this message translates to:
  /// **'Link on tap (optional)'**
  String get adLinkUrl;

  /// No description provided for @advertiser.
  ///
  /// In en, this message translates to:
  /// **'Advertiser (optional)'**
  String get advertiser;

  /// No description provided for @adAudience.
  ///
  /// In en, this message translates to:
  /// **'Audience'**
  String get adAudience;

  /// No description provided for @audienceNewCustomers.
  ///
  /// In en, this message translates to:
  /// **'New customers'**
  String get audienceNewCustomers;

  /// No description provided for @audienceReturning.
  ///
  /// In en, this message translates to:
  /// **'Returning customers'**
  String get audienceReturning;

  /// No description provided for @adStarts.
  ///
  /// In en, this message translates to:
  /// **'Starts'**
  String get adStarts;

  /// No description provided for @adEnds.
  ///
  /// In en, this message translates to:
  /// **'Ends'**
  String get adEnds;

  /// No description provided for @adPerformance.
  ///
  /// In en, this message translates to:
  /// **'{impressions} views · {clicks} taps · {rate}% tap rate'**
  String adPerformance(int impressions, int clicks, String rate);

  /// No description provided for @noAdsYet.
  ///
  /// In en, this message translates to:
  /// **'No ads yet.'**
  String get noAdsYet;

  /// No description provided for @adCreated.
  ///
  /// In en, this message translates to:
  /// **'Ad created'**
  String get adCreated;

  /// No description provided for @adDeleted.
  ///
  /// In en, this message translates to:
  /// **'Ad deleted'**
  String get adDeleted;

  /// No description provided for @deleteAdConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this ad? Its view and tap counts go with it.'**
  String get deleteAdConfirm;

  /// No description provided for @adLive.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get adLive;

  /// No description provided for @adEnded.
  ///
  /// In en, this message translates to:
  /// **'Ended'**
  String get adEnded;

  /// No description provided for @uploadArtwork.
  ///
  /// In en, this message translates to:
  /// **'Upload artwork'**
  String get uploadArtwork;

  /// No description provided for @artworkRequired.
  ///
  /// In en, this message translates to:
  /// **'Add artwork first — it is the poster for a video ad too.'**
  String get artworkRequired;

  /// No description provided for @tipDriver.
  ///
  /// In en, this message translates to:
  /// **'Tip your driver'**
  String get tipDriver;

  /// No description provided for @tipDriverDesc.
  ///
  /// In en, this message translates to:
  /// **'Paid from your wallet, straight to {driver}.'**
  String tipDriverDesc(String driver);

  /// No description provided for @tipDriverGeneric.
  ///
  /// In en, this message translates to:
  /// **'Paid from your wallet, straight to your driver.'**
  String get tipDriverGeneric;

  /// No description provided for @tipAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get tipAmount;

  /// No description provided for @sendTip.
  ///
  /// In en, this message translates to:
  /// **'Send tip'**
  String get sendTip;

  /// No description provided for @tipSent.
  ///
  /// In en, this message translates to:
  /// **'Thanks — {amount} sent to your driver.'**
  String tipSent(String amount);

  /// No description provided for @tippedAlready.
  ///
  /// In en, this message translates to:
  /// **'You tipped {amount} for this order.'**
  String tippedAlready(String amount);

  /// No description provided for @errTipTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That tip is larger than we allow. Try a smaller amount.'**
  String get errTipTooLarge;

  /// No description provided for @errAlreadyTipped.
  ///
  /// In en, this message translates to:
  /// **'You have already tipped for this order.'**
  String get errAlreadyTipped;

  /// No description provided for @errNoDriver.
  ///
  /// In en, this message translates to:
  /// **'This order had no driver to tip.'**
  String get errNoDriver;

  /// No description provided for @errOrderNotDelivered.
  ///
  /// In en, this message translates to:
  /// **'You can tip once the order has been delivered.'**
  String get errOrderNotDelivered;

  /// No description provided for @errInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get errInvalidAmount;

  /// No description provided for @orderTypeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get orderTypeDelivery;

  /// No description provided for @orderTypePickup.
  ///
  /// In en, this message translates to:
  /// **'Pick up'**
  String get orderTypePickup;

  /// No description provided for @orderTypeScheduled.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get orderTypeScheduled;

  /// No description provided for @pickupNoFee.
  ///
  /// In en, this message translates to:
  /// **'Collect from the store — no delivery fee.'**
  String get pickupNoFee;

  /// No description provided for @pickupCollectAt.
  ///
  /// In en, this message translates to:
  /// **'Collect from {store}'**
  String pickupCollectAt(String store);

  /// No description provided for @scheduleForLater.
  ///
  /// In en, this message translates to:
  /// **'Choose a time'**
  String get scheduleForLater;

  /// No description provided for @scheduledFor.
  ///
  /// In en, this message translates to:
  /// **'Scheduled for {time}'**
  String scheduledFor(String time);

  /// No description provided for @scheduleHint.
  ///
  /// In en, this message translates to:
  /// **'At least 45 minutes ahead, up to a week.'**
  String get scheduleHint;

  /// No description provided for @errScheduleRequired.
  ///
  /// In en, this message translates to:
  /// **'Choose a time for your order.'**
  String get errScheduleRequired;

  /// No description provided for @errScheduleTooSoon.
  ///
  /// In en, this message translates to:
  /// **'Pick a time at least 45 minutes from now.'**
  String get errScheduleTooSoon;

  /// No description provided for @errScheduleTooFar.
  ///
  /// In en, this message translates to:
  /// **'You can schedule up to a week ahead.'**
  String get errScheduleTooFar;

  /// No description provided for @readyForCollection.
  ///
  /// In en, this message translates to:
  /// **'Ready for collection'**
  String get readyForCollection;

  /// No description provided for @markCollected.
  ///
  /// In en, this message translates to:
  /// **'Mark as collected'**
  String get markCollected;

  /// No description provided for @shopByCategory.
  ///
  /// In en, this message translates to:
  /// **'Shop by category'**
  String get shopByCategory;

  /// No description provided for @closedNow.
  ///
  /// In en, this message translates to:
  /// **'Closed now'**
  String get closedNow;

  /// No description provided for @openUntil.
  ///
  /// In en, this message translates to:
  /// **'Open until {time}'**
  String openUntil(String time);

  /// No description provided for @closedOutsideHours.
  ///
  /// In en, this message translates to:
  /// **'Closed — outside opening hours'**
  String get closedOutsideHours;

  /// No description provided for @outsideOpeningHoursNotice.
  ///
  /// In en, this message translates to:
  /// **'Your store is switched on but today\'s opening hours have it closed, so customers cannot order.'**
  String get outsideOpeningHoursNotice;

  /// No description provided for @editHours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get editHours;

  /// No description provided for @proPartner.
  ///
  /// In en, this message translates to:
  /// **'pro'**
  String get proPartner;

  /// No description provided for @freeDelivery.
  ///
  /// In en, this message translates to:
  /// **'Free delivery'**
  String get freeDelivery;

  /// No description provided for @deliveryFeeLabel.
  ///
  /// In en, this message translates to:
  /// **'{fee} delivery'**
  String deliveryFeeLabel(String fee);

  /// No description provided for @minutesRange.
  ///
  /// In en, this message translates to:
  /// **'{from}–{to} min'**
  String minutesRange(int from, int to);

  /// No description provided for @recommendedIn.
  ///
  /// In en, this message translates to:
  /// **'Recommended in {category}'**
  String recommendedIn(String category);

  /// No description provided for @allStoresIn.
  ///
  /// In en, this message translates to:
  /// **'All in {category}'**
  String allStoresIn(String category);

  /// No description provided for @noStoresInCategory.
  ///
  /// In en, this message translates to:
  /// **'No stores here yet.'**
  String get noStoresInCategory;

  /// No description provided for @noRecommendationsYet.
  ///
  /// In en, this message translates to:
  /// **'No promoted stores in this category yet.'**
  String get noRecommendationsYet;

  /// No description provided for @addStore.
  ///
  /// In en, this message translates to:
  /// **'Add store'**
  String get addStore;

  /// No description provided for @parentCategory.
  ///
  /// In en, this message translates to:
  /// **'Parent category'**
  String get parentCategory;

  /// No description provided for @noParentTopLevel.
  ///
  /// In en, this message translates to:
  /// **'Top level'**
  String get noParentTopLevel;

  /// No description provided for @subCategory.
  ///
  /// In en, this message translates to:
  /// **'Sub-category'**
  String get subCategory;

  /// No description provided for @topLevelCategoryWithChildren.
  ///
  /// In en, this message translates to:
  /// **'This category has sub-categories, so it stays at the top level.'**
  String get topLevelCategoryWithChildren;

  /// No description provided for @categoryNameArabicLabel.
  ///
  /// In en, this message translates to:
  /// **'Name (Arabic)'**
  String get categoryNameArabicLabel;

  /// No description provided for @pickupFromBranch.
  ///
  /// In en, this message translates to:
  /// **'Pickup from branch'**
  String get pickupFromBranch;

  /// No description provided for @priceAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Price adjustment'**
  String get priceAdjustment;

  /// No description provided for @adjustmentType.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get adjustmentType;

  /// No description provided for @fixedAmount.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get fixedAmount;

  /// No description provided for @increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get increase;

  /// No description provided for @decrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get decrease;

  /// No description provided for @percentValue.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get percentValue;

  /// No description provided for @amountValue.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountValue;

  /// No description provided for @appliesTo.
  ///
  /// In en, this message translates to:
  /// **'Applies to'**
  String get appliesTo;

  /// No description provided for @scopeAllProducts.
  ///
  /// In en, this message translates to:
  /// **'Every product on the platform'**
  String get scopeAllProducts;

  /// No description provided for @scopeOneStore.
  ///
  /// In en, this message translates to:
  /// **'One store'**
  String get scopeOneStore;

  /// No description provided for @scopeOneCategory.
  ///
  /// In en, this message translates to:
  /// **'One category'**
  String get scopeOneCategory;

  /// No description provided for @counting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get counting;

  /// No description provided for @productsInScope.
  ///
  /// In en, this message translates to:
  /// **'{count} products in scope'**
  String productsInScope(int count);

  /// No description provided for @priceIncreaseSummary.
  ///
  /// In en, this message translates to:
  /// **'Raise prices by {amount} across {target}.'**
  String priceIncreaseSummary(String amount, String target);

  /// No description provided for @priceDecreaseSummary.
  ///
  /// In en, this message translates to:
  /// **'Lower prices by {amount} across {target}.'**
  String priceDecreaseSummary(String amount, String target);

  /// No description provided for @priceAdjustConfirm.
  ///
  /// In en, this message translates to:
  /// **'{summary}\n\nThis rewrites {count} prices and cannot be undone automatically.'**
  String priceAdjustConfirm(String summary, int count);

  /// No description provided for @applyToAllProducts.
  ///
  /// In en, this message translates to:
  /// **'Apply price change'**
  String get applyToAllProducts;

  /// No description provided for @pricesUpdated.
  ///
  /// In en, this message translates to:
  /// **'{count} prices updated.'**
  String pricesUpdated(int count);

  /// No description provided for @recentAdjustments.
  ///
  /// In en, this message translates to:
  /// **'Recent adjustments'**
  String get recentAdjustments;

  /// No description provided for @productsUpdatedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} products'**
  String productsUpdatedCount(int count);

  /// No description provided for @recentSearches.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get recentSearches;

  /// No description provided for @searchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Search for a store or a dish.'**
  String get searchPrompt;

  /// No description provided for @noResultsFor.
  ///
  /// In en, this message translates to:
  /// **'Nothing found for “{query}”.'**
  String noResultsFor(String query);

  /// No description provided for @searchFailed.
  ///
  /// In en, this message translates to:
  /// **'Search could not be completed. Try again.'**
  String get searchFailed;

  /// No description provided for @deliveryMargin.
  ///
  /// In en, this message translates to:
  /// **'Delivery margin ({share})'**
  String deliveryMargin(String share);

  /// No description provided for @platformFundedDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Discounts funded by platform'**
  String get platformFundedDiscounts;

  /// No description provided for @storeFundedDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Store-funded discounts'**
  String get storeFundedDiscounts;

  /// No description provided for @owedOut.
  ///
  /// In en, this message translates to:
  /// **'Owed out'**
  String get owedOut;

  /// No description provided for @tipsPassedThrough.
  ///
  /// In en, this message translates to:
  /// **'Tips (passed through)'**
  String get tipsPassedThrough;

  /// No description provided for @subscriptions.
  ///
  /// In en, this message translates to:
  /// **'Subscriptions'**
  String get subscriptions;

  /// No description provided for @subscriptionFeesMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly fees ({count} stores)'**
  String subscriptionFeesMonthly(int count);

  /// No description provided for @subscriptionNotInNet.
  ///
  /// In en, this message translates to:
  /// **'Billed monthly, so it is not included in the net above — that figure covers this period\'s orders only.'**
  String get subscriptionNotInNet;

  /// No description provided for @subscriptionPlan.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get subscriptionPlan;

  /// No description provided for @perMonthSuffix.
  ///
  /// In en, this message translates to:
  /// **'/mo'**
  String get perMonthSuffix;

  /// No description provided for @driverShareLabel.
  ///
  /// In en, this message translates to:
  /// **'Driver share (%)'**
  String get driverShareLabel;

  /// No description provided for @platformShareLabel.
  ///
  /// In en, this message translates to:
  /// **'Platform share'**
  String get platformShareLabel;

  /// No description provided for @netPayout.
  ///
  /// In en, this message translates to:
  /// **'Net payout'**
  String get netPayout;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @last7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// No description provided for @last30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// No description provided for @minutesShort.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String minutesShort(int count);

  /// No description provided for @noRatingsYet.
  ///
  /// In en, this message translates to:
  /// **'No ratings yet'**
  String get noRatingsYet;

  /// No description provided for @collectedForOthers.
  ///
  /// In en, this message translates to:
  /// **'Collected, not yours'**
  String get collectedForOthers;

  /// No description provided for @deliveryFeesNotYours.
  ///
  /// In en, this message translates to:
  /// **'Charged to the customer for delivery and paid to the driver and the platform. It is never part of your payout.'**
  String get deliveryFeesNotYours;

  /// No description provided for @subscriptionNotDeductedNote.
  ///
  /// In en, this message translates to:
  /// **'Your monthly subscription is billed separately and is not deducted from the payout above.'**
  String get subscriptionNotDeductedNote;

  /// No description provided for @onboardingTitle4.
  ///
  /// In en, this message translates to:
  /// **'Now, later, or collect it yourself'**
  String get onboardingTitle4;

  /// No description provided for @onboardingBody4.
  ///
  /// In en, this message translates to:
  /// **'Order for right now, schedule it for the time you want, or pick it up from the branch.'**
  String get onboardingBody4;

  /// No description provided for @cashDue.
  ///
  /// In en, this message translates to:
  /// **'Cash due'**
  String get cashDue;

  /// No description provided for @owedToYou.
  ///
  /// In en, this message translates to:
  /// **'Owed to you'**
  String get owedToYou;

  /// No description provided for @availableBalance.
  ///
  /// In en, this message translates to:
  /// **'Available balance'**
  String get availableBalance;

  /// No description provided for @cashCollectedLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash collected'**
  String get cashCollectedLabel;

  /// No description provided for @totalEarningsLabel.
  ///
  /// In en, this message translates to:
  /// **'Total earnings'**
  String get totalEarningsLabel;

  /// No description provided for @totalSettlementsLabel.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get totalSettlementsLabel;

  /// No description provided for @lastSettlement.
  ///
  /// In en, this message translates to:
  /// **'Last settlement'**
  String get lastSettlement;

  /// No description provided for @statement.
  ///
  /// In en, this message translates to:
  /// **'Statement'**
  String get statement;

  /// No description provided for @noTransactionsYet.
  ///
  /// In en, this message translates to:
  /// **'No transactions yet.'**
  String get noTransactionsYet;

  /// No description provided for @youOweExplainer.
  ///
  /// In en, this message translates to:
  /// **'Cash you collected from customers and still owe the platform.'**
  String get youOweExplainer;

  /// No description provided for @owedToYouExplainer.
  ///
  /// In en, this message translates to:
  /// **'Money the platform owes you.'**
  String get owedToYouExplainer;

  /// No description provided for @requestDeposit.
  ///
  /// In en, this message translates to:
  /// **'Deposit money'**
  String get requestDeposit;

  /// No description provided for @depositAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get depositAmount;

  /// No description provided for @depositMethod.
  ///
  /// In en, this message translates to:
  /// **'How you paid'**
  String get depositMethod;

  /// No description provided for @referenceOptional.
  ///
  /// In en, this message translates to:
  /// **'Reference (optional)'**
  String get referenceOptional;

  /// No description provided for @submitRequest.
  ///
  /// In en, this message translates to:
  /// **'Send request'**
  String get submitRequest;

  /// No description provided for @depositRequested.
  ///
  /// In en, this message translates to:
  /// **'Request sent. It is credited once an admin confirms the payment.'**
  String get depositRequested;

  /// No description provided for @depositsAwaitingReview.
  ///
  /// In en, this message translates to:
  /// **'Deposits'**
  String get depositsAwaitingReview;

  /// No description provided for @noDepositsPending.
  ///
  /// In en, this message translates to:
  /// **'No deposits waiting.'**
  String get noDepositsPending;

  /// No description provided for @depositApproved.
  ///
  /// In en, this message translates to:
  /// **'Deposit approved.'**
  String get depositApproved;

  /// No description provided for @depositRejected.
  ///
  /// In en, this message translates to:
  /// **'Deposit rejected.'**
  String get depositRejected;

  /// No description provided for @financeTitle.
  ///
  /// In en, this message translates to:
  /// **'Money'**
  String get financeTitle;

  /// No description provided for @cashReconciliation.
  ///
  /// In en, this message translates to:
  /// **'Cash reconciliation'**
  String get cashReconciliation;

  /// No description provided for @settlementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settlements'**
  String get settlementsTitle;

  /// No description provided for @expectedCash.
  ///
  /// In en, this message translates to:
  /// **'Expected'**
  String get expectedCash;

  /// No description provided for @collectedCash.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get collectedCash;

  /// No description provided for @settledCash.
  ///
  /// In en, this message translates to:
  /// **'Settled'**
  String get settledCash;

  /// No description provided for @outstandingCash.
  ///
  /// In en, this message translates to:
  /// **'Outstanding'**
  String get outstandingCash;

  /// No description provided for @cashDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get cashDifference;

  /// No description provided for @reconciliationClean.
  ///
  /// In en, this message translates to:
  /// **'Every cash order has a matching collection.'**
  String get reconciliationClean;

  /// No description provided for @reconciliationException.
  ///
  /// In en, this message translates to:
  /// **'A cash order was delivered with no collection recorded. Its settlement did not run.'**
  String get reconciliationException;

  /// No description provided for @recordSettlement.
  ///
  /// In en, this message translates to:
  /// **'Record settlement'**
  String get recordSettlement;

  /// No description provided for @settlementRecorded.
  ///
  /// In en, this message translates to:
  /// **'Settlement recorded.'**
  String get settlementRecorded;

  /// No description provided for @settlementMethodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get settlementMethodCash;

  /// No description provided for @settlementMethodBank.
  ///
  /// In en, this message translates to:
  /// **'Bank transfer'**
  String get settlementMethodBank;

  /// No description provided for @settlementDetails.
  ///
  /// In en, this message translates to:
  /// **'Settlement details'**
  String get settlementDetails;

  /// No description provided for @settlementHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get settlementHistory;

  /// No description provided for @settlementMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get settlementMethod;

  /// No description provided for @settlementReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get settlementReference;

  /// No description provided for @settlementNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get settlementNotes;

  /// No description provided for @settlementStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get settlementStatus;

  /// No description provided for @settlementRecordedOn.
  ///
  /// In en, this message translates to:
  /// **'Recorded on'**
  String get settlementRecordedOn;

  /// No description provided for @settlementCompletedOn.
  ///
  /// In en, this message translates to:
  /// **'Completed on'**
  String get settlementCompletedOn;

  /// No description provided for @settlementId.
  ///
  /// In en, this message translates to:
  /// **'Settlement ID'**
  String get settlementId;

  /// No description provided for @settlementCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get settlementCompleted;

  /// No description provided for @driversTab.
  ///
  /// In en, this message translates to:
  /// **'Drivers'**
  String get driversTab;

  /// No description provided for @booksBalanced.
  ///
  /// In en, this message translates to:
  /// **'Books balance'**
  String get booksBalanced;

  /// No description provided for @booksNotBalanced.
  ///
  /// In en, this message translates to:
  /// **'Books do not balance — {net} unaccounted for.'**
  String booksNotBalanced(String net);

  /// No description provided for @unsettledOrdersWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} delivered orders were never split.'**
  String unsettledOrdersWarning(int count);

  /// No description provided for @runBackfill.
  ///
  /// In en, this message translates to:
  /// **'Split them now'**
  String get runBackfill;

  /// No description provided for @driverCashDueTotal.
  ///
  /// In en, this message translates to:
  /// **'Driver cash due'**
  String get driverCashDueTotal;

  /// No description provided for @vendorPayableTotal.
  ///
  /// In en, this message translates to:
  /// **'Store payables'**
  String get vendorPayableTotal;

  /// No description provided for @platformNet.
  ///
  /// In en, this message translates to:
  /// **'Platform net'**
  String get platformNet;

  /// No description provided for @amountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount.'**
  String get amountRequired;

  /// No description provided for @refunds.
  ///
  /// In en, this message translates to:
  /// **'Refunds'**
  String get refunds;

  /// No description provided for @bonus.
  ///
  /// In en, this message translates to:
  /// **'Bonus'**
  String get bonus;

  /// No description provided for @penalty.
  ///
  /// In en, this message translates to:
  /// **'Penalty'**
  String get penalty;

  /// No description provided for @adjustments.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get adjustments;

  /// No description provided for @reversal.
  ///
  /// In en, this message translates to:
  /// **'Reversal'**
  String get reversal;

  /// No description provided for @opensAt.
  ///
  /// In en, this message translates to:
  /// **'Opens'**
  String get opensAt;

  /// No description provided for @closesAt.
  ///
  /// In en, this message translates to:
  /// **'Closes'**
  String get closesAt;

  /// No description provided for @openAllDay.
  ///
  /// In en, this message translates to:
  /// **'Open 24 hours'**
  String get openAllDay;

  /// No description provided for @closesNextDay.
  ///
  /// In en, this message translates to:
  /// **'Closes after midnight'**
  String get closesNextDay;

  /// No description provided for @hoursCloseTheStoreNotice.
  ///
  /// In en, this message translates to:
  /// **'Customers cannot order outside these hours, even while the store switch is on.'**
  String get hoursCloseTheStoreNotice;

  /// No description provided for @ordersHistory.
  ///
  /// In en, this message translates to:
  /// **'Order history'**
  String get ordersHistory;

  /// No description provided for @noOrdersOnDay.
  ///
  /// In en, this message translates to:
  /// **'No orders on this day.'**
  String get noOrdersOnDay;

  /// No description provided for @dayTotal.
  ///
  /// In en, this message translates to:
  /// **'Day total'**
  String get dayTotal;

  /// No description provided for @payouts.
  ///
  /// In en, this message translates to:
  /// **'Payouts'**
  String get payouts;

  /// No description provided for @nextPayout.
  ///
  /// In en, this message translates to:
  /// **'Next payout'**
  String get nextPayout;

  /// No description provided for @earlyPayout.
  ///
  /// In en, this message translates to:
  /// **'Request early payout'**
  String get earlyPayout;

  /// No description provided for @earlyPayoutFee.
  ///
  /// In en, this message translates to:
  /// **'Fee ({percent}%)'**
  String earlyPayoutFee(String percent);

  /// No description provided for @youReceive.
  ///
  /// In en, this message translates to:
  /// **'You receive'**
  String get youReceive;

  /// No description provided for @earlyPayoutExplainer.
  ///
  /// In en, this message translates to:
  /// **'Your money normally arrives on the weekly payout run. Ask for it now, for a fee, and an admin reviews it sooner.'**
  String get earlyPayoutExplainer;

  /// No description provided for @earlyPayoutUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Nothing to pay out yet.'**
  String get earlyPayoutUnavailable;

  /// No description provided for @earlyPayoutDone.
  ///
  /// In en, this message translates to:
  /// **'Paid out. {amount} is on its way.'**
  String earlyPayoutDone(String amount);

  /// No description provided for @confirmEarlyPayout.
  ///
  /// In en, this message translates to:
  /// **'Request {net} now instead of {gross} on {date}, for a fee?'**
  String confirmEarlyPayout(String net, String gross, String date);

  /// No description provided for @chatWithDriver.
  ///
  /// In en, this message translates to:
  /// **'Chat with your driver'**
  String get chatWithDriver;

  /// No description provided for @trackStock.
  ///
  /// In en, this message translates to:
  /// **'Track stock'**
  String get trackStock;

  /// No description provided for @trackStockOn.
  ///
  /// In en, this message translates to:
  /// **'Sold from a counted shelf. It goes out of stock at zero.'**
  String get trackStockOn;

  /// No description provided for @trackStockOff.
  ///
  /// In en, this message translates to:
  /// **'Always orderable while it is available. Right for a kitchen.'**
  String get trackStockOff;

  /// No description provided for @stockQuantity.
  ///
  /// In en, this message translates to:
  /// **'Units in stock'**
  String get stockQuantity;

  /// No description provided for @lowStockThreshold.
  ///
  /// In en, this message translates to:
  /// **'Warn me at or below'**
  String get lowStockThreshold;

  /// No description provided for @lowStockThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'0 turns the warning off.'**
  String get lowStockThresholdHint;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStock;

  /// No description provided for @stockAlerts.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stockAlerts;

  /// No description provided for @outOfStockCount.
  ///
  /// In en, this message translates to:
  /// **'{count} out of stock'**
  String outOfStockCount(int count);

  /// No description provided for @lowStockCount.
  ///
  /// In en, this message translates to:
  /// **'{count} running low'**
  String lowStockCount(int count);

  /// No description provided for @reviewStock.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewStock;

  /// No description provided for @unitsLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String unitsLeft(int count);

  /// No description provided for @setStock.
  ///
  /// In en, this message translates to:
  /// **'Set stock'**
  String get setStock;

  /// No description provided for @stockUpdated.
  ///
  /// In en, this message translates to:
  /// **'Stock updated.'**
  String get stockUpdated;

  /// No description provided for @contactSupport.
  ///
  /// In en, this message translates to:
  /// **'Contact support'**
  String get contactSupport;

  /// No description provided for @helpAndSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & support'**
  String get helpAndSupport;

  /// No description provided for @importFromFile.
  ///
  /// In en, this message translates to:
  /// **'Import a file'**
  String get importFromFile;

  /// No description provided for @importFileHint.
  ///
  /// In en, this message translates to:
  /// **'CSV or Excel is read directly and exactly. PDFs and photos go through AI.'**
  String get importFileHint;

  /// No description provided for @spreadsheetNoNameColumn.
  ///
  /// In en, this message translates to:
  /// **'No item-name column found. The sheet needs a column called Name, Item or Product.'**
  String get spreadsheetNoNameColumn;

  /// No description provided for @spreadsheetEmpty.
  ///
  /// In en, this message translates to:
  /// **'That file has no rows to read.'**
  String get spreadsheetEmpty;

  /// No description provided for @readingFile.
  ///
  /// In en, this message translates to:
  /// **'Reading file…'**
  String get readingFile;

  /// No description provided for @itemsFound.
  ///
  /// In en, this message translates to:
  /// **'{count} items found'**
  String itemsFound(int count);

  /// No description provided for @placementInterstitial.
  ///
  /// In en, this message translates to:
  /// **'Full screen'**
  String get placementInterstitial;

  /// No description provided for @busyModeHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on when orders pile up, to add extra prep time'**
  String get busyModeHint;

  /// No description provided for @photoUpdated.
  ///
  /// In en, this message translates to:
  /// **'Photo updated'**
  String get photoUpdated;

  /// No description provided for @autoAcceptOrdersHint.
  ///
  /// In en, this message translates to:
  /// **'New orders confirm instantly, no manual accept'**
  String get autoAcceptOrdersHint;

  /// No description provided for @newOrderSoundHint.
  ///
  /// In en, this message translates to:
  /// **'Play a sound when a new order comes in'**
  String get newOrderSoundHint;

  /// No description provided for @storeStatus.
  ///
  /// In en, this message translates to:
  /// **'Store status'**
  String get storeStatus;

  /// No description provided for @locationMissingHint.
  ///
  /// In en, this message translates to:
  /// **'Add a pin so customers can find you nearby'**
  String get locationMissingHint;

  /// No description provided for @requestSettlement.
  ///
  /// In en, this message translates to:
  /// **'Request settlement'**
  String get requestSettlement;

  /// No description provided for @requestSettlementHint.
  ///
  /// In en, this message translates to:
  /// **'Free — an admin reviews and pays this out. For instant cash-out, use Early Payout instead.'**
  String get requestSettlementHint;

  /// No description provided for @requestPayout.
  ///
  /// In en, this message translates to:
  /// **'Request payout'**
  String get requestPayout;

  /// No description provided for @requestPayoutHint.
  ///
  /// In en, this message translates to:
  /// **'Free — an admin reviews and pays out what you\'re owed.'**
  String get requestPayoutHint;

  /// No description provided for @settlementRequested.
  ///
  /// In en, this message translates to:
  /// **'Request sent. You\'ll be notified once an admin reviews it.'**
  String get settlementRequested;

  /// No description provided for @settlementRequestPending.
  ///
  /// In en, this message translates to:
  /// **'Awaiting admin approval'**
  String get settlementRequestPending;

  /// No description provided for @settlementApproved.
  ///
  /// In en, this message translates to:
  /// **'Settlement approved.'**
  String get settlementApproved;

  /// No description provided for @settlementRejected.
  ///
  /// In en, this message translates to:
  /// **'Settlement declined.'**
  String get settlementRejected;

  /// No description provided for @settlementRequestsTab.
  ///
  /// In en, this message translates to:
  /// **'Requests'**
  String get settlementRequestsTab;

  /// No description provided for @noSettlementRequests.
  ///
  /// In en, this message translates to:
  /// **'No requests waiting.'**
  String get noSettlementRequests;

  /// No description provided for @totalEarned.
  ///
  /// In en, this message translates to:
  /// **'Total earned'**
  String get totalEarned;

  /// No description provided for @alreadySettled.
  ///
  /// In en, this message translates to:
  /// **'Already settled'**
  String get alreadySettled;

  /// No description provided for @outstandingNow.
  ///
  /// In en, this message translates to:
  /// **'Outstanding now'**
  String get outstandingNow;

  /// No description provided for @shareReceipt.
  ///
  /// In en, this message translates to:
  /// **'Share receipt'**
  String get shareReceipt;

  /// No description provided for @pendingApprovalsBanner.
  ///
  /// In en, this message translates to:
  /// **'{count} settlement requests awaiting your approval'**
  String pendingApprovalsBanner(int count);

  /// No description provided for @searchByName.
  ///
  /// In en, this message translates to:
  /// **'Search by name'**
  String get searchByName;

  /// No description provided for @settlementApprovalExternalNotice.
  ///
  /// In en, this message translates to:
  /// **'This only records that you already sent the money outside the app — nothing is transferred automatically.'**
  String get settlementApprovalExternalNotice;

  /// No description provided for @feeLabel.
  ///
  /// In en, this message translates to:
  /// **'Fee'**
  String get feeLabel;

  /// No description provided for @grossAmount.
  ///
  /// In en, this message translates to:
  /// **'Before fee'**
  String get grossAmount;

  /// No description provided for @earlySettlementTag.
  ///
  /// In en, this message translates to:
  /// **'Early'**
  String get earlySettlementTag;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// No description provided for @lastMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Last message'**
  String get lastMessageLabel;

  /// No description provided for @storeLabel.
  ///
  /// In en, this message translates to:
  /// **'Store'**
  String get storeLabel;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @complaintResolvedAndNotified.
  ///
  /// In en, this message translates to:
  /// **'Complaint resolved and customer notified.'**
  String get complaintResolvedAndNotified;

  /// No description provided for @replyAndResolve.
  ///
  /// In en, this message translates to:
  /// **'Reply & resolve'**
  String get replyAndResolve;

  /// No description provided for @resolutionReply.
  ///
  /// In en, this message translates to:
  /// **'Resolution reply'**
  String get resolutionReply;

  /// No description provided for @earlyPayoutFeeTitle.
  ///
  /// In en, this message translates to:
  /// **'Early payout fee'**
  String get earlyPayoutFeeTitle;

  /// No description provided for @earlyPayoutFeeSummary.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of the payable, minimum {min}'**
  String earlyPayoutFeeSummary(String percent, String min);

  /// No description provided for @earlyPayoutFeeScope.
  ///
  /// In en, this message translates to:
  /// **'Applies to stores and drivers. New requests only — anything already pending keeps the fee it was quoted.'**
  String get earlyPayoutFeeScope;

  /// No description provided for @feePercentLabel.
  ///
  /// In en, this message translates to:
  /// **'Percent of payable (%)'**
  String get feePercentLabel;

  /// No description provided for @feeMinLabel.
  ///
  /// In en, this message translates to:
  /// **'Minimum fee'**
  String get feeMinLabel;

  /// No description provided for @feePreview.
  ///
  /// In en, this message translates to:
  /// **'On {amount}: fee {fee}, they receive {net}'**
  String feePreview(String amount, String fee, String net);

  /// No description provided for @feeUpdated.
  ///
  /// In en, this message translates to:
  /// **'Early payout fee updated'**
  String get feeUpdated;

  /// No description provided for @invalidFeePercent.
  ///
  /// In en, this message translates to:
  /// **'Enter a percent between 0 and 100.'**
  String get invalidFeePercent;

  /// No description provided for @invalidFeeMin.
  ///
  /// In en, this message translates to:
  /// **'The minimum fee cannot be negative.'**
  String get invalidFeeMin;

  /// No description provided for @deleteUncategorizedAction.
  ///
  /// In en, this message translates to:
  /// **'Delete all {count} uncategorized items'**
  String deleteUncategorizedAction(int count);

  /// No description provided for @moveUncategorizedAction.
  ///
  /// In en, this message translates to:
  /// **'Move all {count} into a section'**
  String moveUncategorizedAction(int count);

  /// No description provided for @deleteUncategorizedConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Permanently delete this item?} other{Permanently delete these {count} items?}} They are removed from the menu — unlike deleting a section, which keeps its items.'**
  String deleteUncategorizedConfirm(int count);

  /// No description provided for @moveItemsToSection.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Move 1 item to} other{Move {count} items to}}'**
  String moveItemsToSection(int count);

  /// No description provided for @itemsDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 item deleted} other{{count} items deleted}}'**
  String itemsDeleted(int count);

  /// No description provided for @selectItems.
  ///
  /// In en, this message translates to:
  /// **'Select items'**
  String get selectItems;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 selected} other{{count} selected}}'**
  String selectedCount(int count);

  /// No description provided for @deleteItemsConfirm.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{Permanently delete this item?} other{Permanently delete these {count} items?}} This cannot be undone.'**
  String deleteItemsConfirm(int count);

  /// No description provided for @showingOfTotal.
  ///
  /// In en, this message translates to:
  /// **'Showing {shown} of {total} items'**
  String showingOfTotal(int shown, int total);

  /// No description provided for @driverShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Driver delivery-fee share'**
  String get driverShareTitle;

  /// No description provided for @driverShareSummary.
  ///
  /// In en, this message translates to:
  /// **'Driver keeps {driverPercent}% · platform keeps {platformPercent}%'**
  String driverShareSummary(String driverPercent, String platformPercent);

  /// No description provided for @driverShareScope.
  ///
  /// In en, this message translates to:
  /// **'Applies to future deliveries only — orders already settled keep the split they were settled at.'**
  String get driverShareScope;

  /// No description provided for @platformShareResult.
  ///
  /// In en, this message translates to:
  /// **'Platform keeps {percent}%'**
  String platformShareResult(String percent);

  /// No description provided for @driverShareUpdated.
  ///
  /// In en, this message translates to:
  /// **'Driver share updated'**
  String get driverShareUpdated;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @passwordTooShort.
  ///
  /// In en, this message translates to:
  /// **'Must be at least 6 characters'**
  String get passwordTooShort;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @resetPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset your password'**
  String get resetPasswordTitle;

  /// No description provided for @resetPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'We will email a link to set a new one.'**
  String get resetPasswordSubtitle;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'Send link'**
  String get sendResetLink;

  /// No description provided for @resetLinkSent.
  ///
  /// In en, this message translates to:
  /// **'If that email has an account, a reset link is on its way'**
  String get resetLinkSent;

  /// No description provided for @setNewPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a new password'**
  String get setNewPasswordTitle;

  /// No description provided for @setNewPasswordSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a password for your account.'**
  String get setNewPasswordSubtitle;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @confirmNewPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get confirmNewPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @setNewPasswordAction.
  ///
  /// In en, this message translates to:
  /// **'Set password'**
  String get setNewPasswordAction;

  /// No description provided for @financialSummary.
  ///
  /// In en, this message translates to:
  /// **'Financial summary'**
  String get financialSummary;

  /// No description provided for @adPerformanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get adPerformanceLabel;

  /// No description provided for @adPerformanceCompact.
  ///
  /// In en, this message translates to:
  /// **'{views} · {taps} taps · {rate}%'**
  String adPerformanceCompact(String views, String taps, String rate);

  /// No description provided for @scheduleLabel.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get scheduleLabel;

  /// No description provided for @adAlwaysOn.
  ///
  /// In en, this message translates to:
  /// **'Always on'**
  String get adAlwaysOn;
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
