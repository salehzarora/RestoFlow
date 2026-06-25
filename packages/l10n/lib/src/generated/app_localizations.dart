import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_he.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
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

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
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
    Locale('he'),
  ];

  /// The product name, shown across all surfaces.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow'**
  String get appName;

  /// Window/app title for the POS cashier app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow POS'**
  String get posAppTitle;

  /// Window/app title for the Kitchen Display System app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow KDS'**
  String get kdsAppTitle;

  /// Window/app title for the owner/manager dashboard app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow Dashboard'**
  String get dashboardAppTitle;

  /// Window/app title for the platform admin app.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow Admin'**
  String get adminAppTitle;

  /// Generic welcome message shown on the scaffold body.
  ///
  /// In en, this message translates to:
  /// **'Welcome to RestoFlow'**
  String get welcomeMessage;

  /// Display name of the English locale.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get localeEnglish;

  /// Display name of the Arabic locale.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get localeArabic;

  /// Display name of the Hebrew locale.
  ///
  /// In en, this message translates to:
  /// **'Hebrew'**
  String get localeHebrew;

  /// KDS message shown when there are no tickets to display.
  ///
  /// In en, this message translates to:
  /// **'No active tickets'**
  String get kdsEmptyState;

  /// KDS action that marks a ready ticket as bumped (done).
  ///
  /// In en, this message translates to:
  /// **'Bump'**
  String get kdsBumpAction;

  /// KDS action that recalls a bumped ticket back into preparation.
  ///
  /// In en, this message translates to:
  /// **'Recall'**
  String get kdsRecallAction;

  /// KDS action that acknowledges a new ticket (new -> acknowledged).
  ///
  /// In en, this message translates to:
  /// **'Acknowledge'**
  String get kdsAcknowledgeAction;

  /// KDS action that starts preparing an acknowledged ticket (acknowledged -> in_preparation).
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get kdsStartAction;

  /// KDS action that marks a ticket ready (in_preparation -> ready).
  ///
  /// In en, this message translates to:
  /// **'Mark ready'**
  String get kdsReadyAction;

  /// KDS label prefixing a kitchen station name.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get kdsStationLabel;

  /// KDS label prefixing a kitchen ticket identifier.
  ///
  /// In en, this message translates to:
  /// **'Ticket'**
  String get kdsTicketLabel;

  /// KDS message shown while the first ticket pull is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading tickets…'**
  String get kdsLoadingState;

  /// KDS message shown when tickets cannot be loaded.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load tickets'**
  String get kdsErrorState;

  /// KDS message shown when the session is revoked/expired and re-authentication is required.
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get kdsReauthRequired;

  /// POS heading above the menu item grid.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get posMenuHeading;

  /// POS heading for the cart/order panel.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get posCartTitle;

  /// POS message shown when the cart has no items yet.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get posCartEmpty;

  /// POS label for the cart subtotal amount (non-authoritative preview, excludes tax).
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get posCartSubtotal;

  /// POS action that adds a menu item to the cart.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get posAddToCart;

  /// POS action that removes all items from the cart.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get posClearCart;

  /// POS action/tooltip that removes a single line from the cart.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get posRemoveItem;

  /// POS action/tooltip that increases a cart line quantity by one.
  ///
  /// In en, this message translates to:
  /// **'Increase quantity'**
  String get posIncreaseQuantity;

  /// POS action/tooltip that decreases a cart line quantity by one.
  ///
  /// In en, this message translates to:
  /// **'Decrease quantity'**
  String get posDecreaseQuantity;

  /// POS filter chip that shows menu items from every category.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get posCategoryAll;

  /// POS primary action button to send the current order (demo placeholder).
  ///
  /// In en, this message translates to:
  /// **'Send Order'**
  String get posSendOrder;

  /// POS notice on the local order confirmation clarifying nothing was sent to a backend/kitchen/printer.
  ///
  /// In en, this message translates to:
  /// **'Demo order — not sent to a backend, kitchen, or printer.'**
  String get posDemoOrderNotice;

  /// POS heading on the local order-confirmation panel after Send Order.
  ///
  /// In en, this message translates to:
  /// **'Order sent'**
  String get posOrderSubmittedTitle;

  /// POS label preceding the local/provisional demo order number.
  ///
  /// In en, this message translates to:
  /// **'Order number'**
  String get posOrderNumberLabel;

  /// POS status chip label for a locally-submitted demo order.
  ///
  /// In en, this message translates to:
  /// **'Submitted'**
  String get posOrderStatusSubmitted;

  /// POS action that dismisses the confirmation and starts a new empty order.
  ///
  /// In en, this message translates to:
  /// **'New order'**
  String get posNewOrder;

  /// Owner dashboard section heading above the daily KPI cards.
  ///
  /// In en, this message translates to:
  /// **'Today\'s overview'**
  String get dashboardOverviewHeading;

  /// Owner dashboard KPI card label for the day's net sales total.
  ///
  /// In en, this message translates to:
  /// **'Today\'s sales'**
  String get dashboardTodaySales;

  /// Owner dashboard KPI card label for the day's order count.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get dashboardOrders;

  /// Owner dashboard KPI card label for the average order value.
  ///
  /// In en, this message translates to:
  /// **'Avg. order value'**
  String get dashboardAvgOrderValue;

  /// Owner dashboard KPI card label for the count of completed orders.
  ///
  /// In en, this message translates to:
  /// **'Completed orders'**
  String get dashboardCompletedOrders;

  /// Owner dashboard label for the count of open/active orders.
  ///
  /// In en, this message translates to:
  /// **'Open orders'**
  String get dashboardOpenOrders;

  /// Owner dashboard heading for the daily summary card.
  ///
  /// In en, this message translates to:
  /// **'Daily summary'**
  String get dashboardDailySummary;

  /// Owner dashboard daily-summary row label for net sales.
  ///
  /// In en, this message translates to:
  /// **'Net sales'**
  String get dashboardNetSales;

  /// Owner dashboard daily-summary row label for total discounts.
  ///
  /// In en, this message translates to:
  /// **'Discounts'**
  String get dashboardDiscounts;

  /// Owner dashboard daily-summary row label for voids (count and total).
  ///
  /// In en, this message translates to:
  /// **'Voids'**
  String get dashboardVoids;

  /// Owner dashboard daily-summary row label for cash collected.
  ///
  /// In en, this message translates to:
  /// **'Cash collected'**
  String get dashboardCashCollected;

  /// Owner dashboard daily-summary row label for cash reconciliation variance (counted minus expected).
  ///
  /// In en, this message translates to:
  /// **'Cash variance'**
  String get dashboardCashVariance;

  /// Owner dashboard daily-summary row label preceding the current shift status.
  ///
  /// In en, this message translates to:
  /// **'Shift'**
  String get dashboardShiftStatus;

  /// Owner dashboard heading for the per-branch sales list.
  ///
  /// In en, this message translates to:
  /// **'Sales by branch'**
  String get dashboardSalesByBranch;

  /// Owner dashboard heading for the top-selling items list.
  ///
  /// In en, this message translates to:
  /// **'Top items'**
  String get dashboardTopItems;

  /// Owner dashboard banner clarifying the figures are in-memory demo data, not live.
  ///
  /// In en, this message translates to:
  /// **'Demo data — not from a live backend.'**
  String get dashboardDemoNotice;

  /// Auth gate message shown while the user's context is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading account…'**
  String get authLoadingAccount;

  /// Auth gate message shown when there is no authenticated session.
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get authSignInRequired;

  /// Auth gate primary action that proceeds (e.g. to sign-in).
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get authContinue;

  /// Auth gate heading above the membership picker (pick organization/restaurant/branch).
  ///
  /// In en, this message translates to:
  /// **'Choose location'**
  String get authChooseLocation;

  /// Auth gate message shown when the user has no active memberships for this app.
  ///
  /// In en, this message translates to:
  /// **'No active access'**
  String get authNoAccess;

  /// Auth gate message shown when the selected role may not enter this app surface.
  ///
  /// In en, this message translates to:
  /// **'This role can\'t use this app'**
  String get authWrongRole;

  /// Auth gate message shown when access is denied (unauthenticated/unlinked/inactive).
  ///
  /// In en, this message translates to:
  /// **'Account access denied'**
  String get authAccessDenied;

  /// Auth gate message shown for a generic backend/auth error.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get authError;

  /// Auth gate action that retries loading the account context.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get authTryAgain;

  /// Auth gate action that signs the user out.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get authSignOut;

  /// Auth gate label for the platform-admin entry/state (separate from tenant roles).
  ///
  /// In en, this message translates to:
  /// **'Platform admin'**
  String get authPlatformAdmin;

  /// Membership picker field label for the organization name.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get authOrganization;

  /// Membership picker field label for the restaurant name.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get authRestaurant;

  /// Membership picker field label for the branch name.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get authBranch;

  /// Membership picker field label for the membership role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get authRole;

  /// Display label for the org_owner membership role.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get authRoleOwner;

  /// Display label for the restaurant_owner membership role.
  ///
  /// In en, this message translates to:
  /// **'Restaurant owner'**
  String get authRoleRestaurantOwner;

  /// Display label for the manager membership role.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get authRoleManager;

  /// Display label for the cashier membership role.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get authRoleCashier;

  /// Display label for the kitchen_staff membership role.
  ///
  /// In en, this message translates to:
  /// **'Kitchen staff'**
  String get authRoleKitchenStaff;

  /// Display label for the accountant membership role.
  ///
  /// In en, this message translates to:
  /// **'Accountant'**
  String get authRoleAccountant;

  /// Auth gate message for a deferred role (e.g. accountant) not yet enabled.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get authComingSoon;
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
      <String>['ar', 'en', 'he'].contains(locale.languageCode);

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
    case 'he':
      return AppLocalizationsHe();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
