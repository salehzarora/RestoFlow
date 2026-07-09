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

  /// Platform-admin overview page heading.
  ///
  /// In en, this message translates to:
  /// **'Platform overview'**
  String get adminOverviewTitle;

  /// Platform-admin label preceding the overview's business day.
  ///
  /// In en, this message translates to:
  /// **'As of'**
  String get adminOverviewAsOf;

  /// Platform-admin pill clarifying the overview is demo data, not live.
  ///
  /// In en, this message translates to:
  /// **'Demo data'**
  String get adminDemoDataTag;

  /// Platform-admin banner honestly stating the overview is computed demo data, not a live backend.
  ///
  /// In en, this message translates to:
  /// **'Demo platform data — computed locally on this device, not synced to a backend.'**
  String get adminDemoDataNotice;

  /// Platform-admin action that reloads the overview.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get adminRefresh;

  /// Platform-admin message shown while the overview is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading platform data…'**
  String get adminLoading;

  /// Platform-admin message shown when the overview fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load platform data.'**
  String get adminError;

  /// Platform-admin message shown when there is no platform data.
  ///
  /// In en, this message translates to:
  /// **'No platform data yet.'**
  String get adminEmpty;

  /// Platform-admin caption word for an active count (e.g. active organizations).
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminActiveLabel;

  /// Platform-admin KPI card label for the organizations count.
  ///
  /// In en, this message translates to:
  /// **'Organizations'**
  String get adminKpiOrganizations;

  /// Platform-admin KPI card label for the restaurants count.
  ///
  /// In en, this message translates to:
  /// **'Restaurants'**
  String get adminKpiRestaurants;

  /// Platform-admin KPI card label for the branches count.
  ///
  /// In en, this message translates to:
  /// **'Branches'**
  String get adminKpiBranches;

  /// Platform-admin KPI card label for the active branches count.
  ///
  /// In en, this message translates to:
  /// **'Active branches'**
  String get adminKpiActiveBranches;

  /// Platform-admin KPI card label for the devices count.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get adminKpiDevices;

  /// Platform-admin KPI card label for the count of branches needing attention.
  ///
  /// In en, this message translates to:
  /// **'Open alerts'**
  String get adminKpiAlerts;

  /// Platform-admin KPI card label for the platform-wide order count today.
  ///
  /// In en, this message translates to:
  /// **'Orders today'**
  String get adminKpiOrdersToday;

  /// Platform-admin heading for the organizations summary list.
  ///
  /// In en, this message translates to:
  /// **'Organizations'**
  String get adminOrganizationsHeading;

  /// Platform-admin heading for the branch-health list.
  ///
  /// In en, this message translates to:
  /// **'Branch health'**
  String get adminBranchHealthHeading;

  /// Platform-admin heading for the recent-activity feed.
  ///
  /// In en, this message translates to:
  /// **'Recent activity'**
  String get adminRecentActivityHeading;

  /// Platform-admin label preceding an organization's created date.
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get adminCreatedLabel;

  /// Platform-admin label preceding a branch's last activity time.
  ///
  /// In en, this message translates to:
  /// **'Last activity'**
  String get adminLastActivityLabel;

  /// Platform-admin short suffix after a branch's order count (e.g. "87 orders today").
  ///
  /// In en, this message translates to:
  /// **'orders today'**
  String get adminOrdersTodayShort;

  /// Platform-admin chip on a branch row that needs attention (inactive branch or suspended org).
  ///
  /// In en, this message translates to:
  /// **'Needs attention'**
  String get adminWarningChip;

  /// Platform-admin banner shown in real mode: the live panel is read-only and limited (some metrics and the MFA/grant management UX are not available yet).
  ///
  /// In en, this message translates to:
  /// **'Live platform data — read-only and limited. Some operational metrics aren\'t available here yet, and platform-admin MFA step-up and grant management aren\'t part of this build.'**
  String get adminRealModeNotice;

  /// Platform-admin pill (real mode) marking the overview as live but limited, read-only data.
  ///
  /// In en, this message translates to:
  /// **'Live · limited'**
  String get adminLiveLimitedTag;

  /// Platform-admin safe-state title shown when real mode is selected but the Supabase connection is not configured.
  ///
  /// In en, this message translates to:
  /// **'Platform admin isn\'t configured'**
  String get adminNotConfiguredTitle;

  /// Platform-admin safe-state body explaining that real mode needs Supabase configuration, or to run in demo mode.
  ///
  /// In en, this message translates to:
  /// **'Real mode is selected but the Supabase connection isn\'t configured, so no platform data can be loaded. Set the Supabase URL and anon key, or run in demo mode.'**
  String get adminNotConfiguredBody;

  /// Heading of the admin app's access explainer (shown to non-platform-admin visitors).
  ///
  /// In en, this message translates to:
  /// **'Platform admin panel'**
  String get adminGateTitle;

  /// Admin gate explainer line 1: what this app is.
  ///
  /// In en, this message translates to:
  /// **'This is the platform administration panel — not the restaurant owner\'s panel.'**
  String get adminGateNotOwner;

  /// Admin gate explainer line 2: where restaurant owners should go.
  ///
  /// In en, this message translates to:
  /// **'Use the Dashboard to manage your restaurant.'**
  String get adminGateUseDashboard;

  /// Admin gate note when a signed-in tenant account (e.g. an owner) opens the admin app.
  ///
  /// In en, this message translates to:
  /// **'This signed-in account is not a platform admin.'**
  String get adminGateNotAdminAccount;

  /// Admin gate note about how platform access is provisioned (no self-service).
  ///
  /// In en, this message translates to:
  /// **'Platform-admin access is granted manually by the platform operator — see docs/LOCAL_RUNBOOK.md.'**
  String get adminGateProvisionHint;

  /// Admin gate action that opens the restaurant Dashboard app.
  ///
  /// In en, this message translates to:
  /// **'Open Dashboard'**
  String get adminGateOpenDashboard;

  /// RF-119 admin gate title: an active platform-admin grant but no MFA (aal2) session.
  ///
  /// In en, this message translates to:
  /// **'Multi-factor authentication required'**
  String get adminMfaRequiredTitle;

  /// RF-119 admin gate body explaining the platform admin needs an aal2/MFA session.
  ///
  /// In en, this message translates to:
  /// **'Your account has platform-admin access, but this sign-in is not multi-factor (MFA) verified. Platform-wide data requires an MFA-verified session.'**
  String get adminMfaRequiredBody;

  /// RF-119 admin gate section title for the MFA next-steps guidance.
  ///
  /// In en, this message translates to:
  /// **'Complete multi-factor authentication'**
  String get adminMfaRequiredNextTitle;

  /// RF-119 admin gate guidance to complete MFA (setup is operator/manual; see the runbook).
  ///
  /// In en, this message translates to:
  /// **'Verify multi-factor authentication for your platform-operator account, then reload. See docs/LOCAL_RUNBOOK.md for platform-admin MFA setup.'**
  String get adminMfaRequiredHint;

  /// RF-119-b admin sign-in screen title (distinct from the restaurant Dashboard login).
  ///
  /// In en, this message translates to:
  /// **'Platform operator sign in'**
  String get adminSignInTitle;

  /// RF-119-b safe admin sign-in credential error (no account-existence leak).
  ///
  /// In en, this message translates to:
  /// **'Wrong email or password.'**
  String get adminSignInInvalid;

  /// RF-119-b TOTP enrolment section title.
  ///
  /// In en, this message translates to:
  /// **'Set up an authenticator app'**
  String get adminMfaEnrollTitle;

  /// RF-119-b TOTP enrolment instructions.
  ///
  /// In en, this message translates to:
  /// **'Add this account to an authenticator app (e.g. Google Authenticator, 1Password) — scan the setup URI as a QR code or paste the setup key — then enter the 6-digit code below to finish.'**
  String get adminMfaEnrollBody;

  /// RF-119-b label for the one-time TOTP setup key / URI shown during enrolment.
  ///
  /// In en, this message translates to:
  /// **'Setup key'**
  String get adminMfaSetupKey;

  /// RF-119-b TOTP challenge section title (an authenticator is already enrolled).
  ///
  /// In en, this message translates to:
  /// **'Enter your authentication code'**
  String get adminMfaChallengeTitle;

  /// RF-119-b TOTP challenge instructions.
  ///
  /// In en, this message translates to:
  /// **'Open your authenticator app and enter the current 6-digit code.'**
  String get adminMfaChallengeBody;

  /// RF-119-b label for the TOTP code entry field.
  ///
  /// In en, this message translates to:
  /// **'6-digit code'**
  String get adminMfaCodeLabel;

  /// RF-119-b TOTP verify button.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get adminMfaVerifyAction;

  /// RF-119-b safe generic TOTP verification failure.
  ///
  /// In en, this message translates to:
  /// **'That code wasn\'t accepted. Enter the current code from your app.'**
  String get adminMfaVerifyFailed;

  /// RF-119-b safe error when starting TOTP enrolment fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t start authenticator setup. Please try again.'**
  String get adminMfaEnrollError;

  /// DESIGN-002: shows the platform operator which account is signed in (email is non-secret; confirms identity on the MFA screen and overview).
  ///
  /// In en, this message translates to:
  /// **'Signed in as {email}'**
  String adminSignedInAs(String email);

  /// DESIGN-002: instructional empty-field validator for the admin sign-in email (replaces the bare field label).
  ///
  /// In en, this message translates to:
  /// **'Enter your work email.'**
  String get adminSignInEmailRequired;

  /// DESIGN-002: instructional empty-field validator for the admin sign-in password (replaces the bare field label).
  ///
  /// In en, this message translates to:
  /// **'Enter your password.'**
  String get adminSignInPasswordRequired;

  /// DESIGN-002: the trust/console-identity tagline on the platform-operator sign-in and MFA screens.
  ///
  /// In en, this message translates to:
  /// **'Operator console · every action is audited'**
  String get adminSecureConsoleTagline;

  /// DESIGN-002: instruction above the enrolment QR code + manual setup key.
  ///
  /// In en, this message translates to:
  /// **'Scan this QR code with an authenticator app, or enter the setup key by hand.'**
  String get adminMfaScanInstruction;

  /// Platform-admin safe-state title shown when the backend denies the read (missing platform-admin grant or MFA step-up).
  ///
  /// In en, this message translates to:
  /// **'Platform admin access denied'**
  String get adminAccessDeniedTitle;

  /// Platform-admin safe-state body explaining that an active platform-admin grant and MFA sign-in are required, and that the step-up/grant UX is not in this build.
  ///
  /// In en, this message translates to:
  /// **'An active platform-admin grant and multi-factor (MFA) sign-in are required to view live platform data. Step-up sign-in and grant management aren\'t available in this build yet.'**
  String get adminAccessDeniedBody;

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

  /// Placeholder inside an empty KDS board column.
  ///
  /// In en, this message translates to:
  /// **'No tickets'**
  String get kdsColumnEmpty;

  /// KDS warning pill when polling fails and the board shows cached (possibly stale) tickets.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing last synced tickets'**
  String get kdsStaleBanner;

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

  /// KDS banner stating the board is a local demo feed, not backend-synced.
  ///
  /// In en, this message translates to:
  /// **'Demo kitchen feed — not synced to a backend'**
  String get kdsDemoFeedBanner;

  /// KDS board column header for new (and acknowledged) kitchen orders.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get kdsColNew;

  /// KDS board column header for orders being prepared.
  ///
  /// In en, this message translates to:
  /// **'Preparing'**
  String get kdsColPreparing;

  /// KDS board column header for orders that are ready.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get kdsColReady;

  /// KDS board column header for completed/bumped (cleared) orders.
  ///
  /// In en, this message translates to:
  /// **'Cleared'**
  String get kdsColCleared;

  /// KDS action that completes (bumps) a ready order off the active board.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get kdsCompleteAction;

  /// KDS label preceding a kitchen note on an order item.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get kdsNoteLabel;

  /// KITCHEN-PREP-001: heading for the compact kitchen prep summary section on a KDS order card (aggregated components the chef assembles). Non-money.
  ///
  /// In en, this message translates to:
  /// **'Prep'**
  String get kdsPrepSummaryLabel;

  /// KITCHEN-PREP-001: heading printed above the aggregated prep component list on a kitchen ticket, before the item details. Non-money.
  ///
  /// In en, this message translates to:
  /// **'Order prep'**
  String get kdsTicketPrepHeading;

  /// KITCHEN-MEAT-001: the whole-order meat total shown at the top of the KDS card + kitchen ticket (one per unit group). count is a formatted count string, unit is free text (e.g. patties, g). Non-money.
  ///
  /// In en, this message translates to:
  /// **'Meat total: {count} {unit}'**
  String kdsMeatTotalLabel(String count, String unit);

  /// KDS elapsed time since an order was submitted, in whole minutes (compact, e.g. 7m).
  ///
  /// In en, this message translates to:
  /// **'{minutes}m'**
  String kdsElapsedMinutes(int minutes);

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

  /// POS modifier-sheet confirm button: add the configured item, showing the running line total (already currency-formatted).
  ///
  /// In en, this message translates to:
  /// **'Add · {total}'**
  String posAddToCartWithTotal(String total);

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

  /// Hint above the DISABLED Send button explaining WHY it is disabled: the cart has items but the dine-in order has no table yet.
  ///
  /// In en, this message translates to:
  /// **'Assign a table to send this dine-in order'**
  String get posSendNeedsTableHint;

  /// POS notice on the local order confirmation clarifying nothing was sent to a backend/kitchen/printer.
  ///
  /// In en, this message translates to:
  /// **'Demo order — not sent to a backend, kitchen, or printer.'**
  String get posDemoOrderNotice;

  /// RF-114: POS outbox chip — N orders queued locally, not yet delivered.
  ///
  /// In en, this message translates to:
  /// **'{count} pending sync'**
  String posOutboxPending(int count);

  /// RF-114: POS outbox chip — a queued order is being delivered.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get posOutboxSyncing;

  /// RF-114: POS outbox chip — N orders failed to sync; tap to retry all.
  ///
  /// In en, this message translates to:
  /// **'{count} failed — retry'**
  String posOutboxFailed(int count);

  /// RF-114: POS outbox chip — every submitted order is confirmed by the backend.
  ///
  /// In en, this message translates to:
  /// **'All orders synced'**
  String get posOutboxSynced;

  /// RF-114: POS outbox chip — a queued order is in a conflict/resolved state that needs review; NOT confirmed synced.
  ///
  /// In en, this message translates to:
  /// **'Sync attention needed'**
  String get posOutboxAttention;

  /// RF-114: POS outbox — retry-all-failed action label.
  ///
  /// In en, this message translates to:
  /// **'Retry all'**
  String get posOutboxRetryAll;

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

  /// PRINT-LAYOUT-001: the big, customer-facing order-number heading printed at the top of the receipt (the internal receipt number is no longer printed).
  ///
  /// In en, this message translates to:
  /// **'Order {orderNumber}'**
  String posReceiptOrderHeading(String orderNumber);

  /// PRINT-LAYOUT-001: a short thank-you footer line on the cashier receipt.
  ///
  /// In en, this message translates to:
  /// **'Thank you for your visit'**
  String get posReceiptThankYou;

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

  /// POS label above the order-type (dine-in / takeaway) selector.
  ///
  /// In en, this message translates to:
  /// **'Order type'**
  String get posOrderTypeLabel;

  /// POS order-type option: the order is served at a table in the restaurant.
  ///
  /// In en, this message translates to:
  /// **'Dine-in'**
  String get posOrderTypeDineIn;

  /// POS order-type option: the order is taken away (no table).
  ///
  /// In en, this message translates to:
  /// **'Takeaway'**
  String get posOrderTypeTakeaway;

  /// POS label preceding a dining-table name/number.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get posTableLabel;

  /// ORDER-CUSTOMER-001: label for the OPTIONAL customer-name field in the POS order/cart setup.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerNameLabel;

  /// ORDER-CUSTOMER-001: placeholder/hint for the optional POS customer-name field (it never blocks sending an order).
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get customerNamePlaceholder;

  /// ORDER-CUSTOMER-001: label preceding the optional customer name on the cashier receipt header.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerNameReceiptLabel;

  /// ORDER-CUSTOMER-001: label preceding the optional customer name on the KDS kitchen ticket / order card.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customerNameKitchenLabel;

  /// POS action that opens the table picker to assign a table to a dine-in order.
  ///
  /// In en, this message translates to:
  /// **'Assign table'**
  String get posAssignTable;

  /// POS action that reopens the table picker to change the assigned table.
  ///
  /// In en, this message translates to:
  /// **'Change table'**
  String get posChangeTable;

  /// POS action/tooltip that removes the assigned table from a dine-in order.
  ///
  /// In en, this message translates to:
  /// **'Clear table'**
  String get posClearTableAssignment;

  /// POS validation message shown when a dine-in order has no table assigned.
  ///
  /// In en, this message translates to:
  /// **'Dine-in orders need a table'**
  String get posTableRequiredWarning;

  /// POS hint shown for takeaway orders, which do not require a table.
  ///
  /// In en, this message translates to:
  /// **'No table needed for takeaway'**
  String get posTableNotNeeded;

  /// POS heading on the table-picker sheet.
  ///
  /// In en, this message translates to:
  /// **'Choose a table'**
  String get posTablePickerTitle;

  /// POS table status: free and assignable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get posTableStatusAvailable;

  /// POS table status: an open dine-in order is already on the table.
  ///
  /// In en, this message translates to:
  /// **'Occupied'**
  String get posTableStatusOccupied;

  /// POS table status: the table is inactive and cannot be assigned.
  ///
  /// In en, this message translates to:
  /// **'Out of service'**
  String get posTableStatusBlocked;

  /// POS table seating capacity.
  ///
  /// In en, this message translates to:
  /// **'{count} seats'**
  String posTableSeats(int count);

  /// POS notice on the table picker clarifying the tables are in-memory demo data.
  ///
  /// In en, this message translates to:
  /// **'Demo tables — not loaded from a backend.'**
  String get posTablesDemoNotice;

  /// POS empty-state message on the table picker when there are no tables.
  ///
  /// In en, this message translates to:
  /// **'No tables to show'**
  String get posTablesEmpty;

  /// POS error-state message on the table picker when tables fail to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load tables'**
  String get posTablesError;

  /// POS table status / legend label for the currently assigned (selected) table.
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get posTableStatusSelected;

  /// POS floor-map zone header for the main indoor dining area.
  ///
  /// In en, this message translates to:
  /// **'Main dining area'**
  String get posTableAreaMain;

  /// POS floor-map zone header for the outdoor patio area.
  ///
  /// In en, this message translates to:
  /// **'Patio'**
  String get posTableAreaPatio;

  /// POS floor-map label on the aisle/walkway separator between two table zones.
  ///
  /// In en, this message translates to:
  /// **'Walkway'**
  String get posTablesAisleLabel;

  /// POS floor-map spatial edge label marking the entrance side of a zone.
  ///
  /// In en, this message translates to:
  /// **'Entrance'**
  String get posTablesEdgeEntrance;

  /// POS floor-map spatial edge label marking the service counter side of a zone.
  ///
  /// In en, this message translates to:
  /// **'Counter'**
  String get posTablesEdgeCounter;

  /// POS footnote on the table picker noting the floor positions are demo-only and a layout editor will arrive later.
  ///
  /// In en, this message translates to:
  /// **'Table positions are demo-only — layout editor coming later.'**
  String get posTablesLayoutEditorHint;

  /// Screen-reader label announcing that a table tile is the selected one.
  ///
  /// In en, this message translates to:
  /// **'{label}, selected'**
  String posTableSelectedSemantic(String label);

  /// POS heading for the order's client outbox / sync status card on the confirmation.
  ///
  /// In en, this message translates to:
  /// **'Sync status'**
  String get posSyncSectionTitle;

  /// POS sync status: the order is queued locally and not yet sent.
  ///
  /// In en, this message translates to:
  /// **'Pending sync'**
  String get posSyncStatePending;

  /// POS sync status: the order is being delivered (demo push in progress).
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get posSyncStateSending;

  /// POS sync status: the order's demo sync completed.
  ///
  /// In en, this message translates to:
  /// **'Synced'**
  String get posSyncStateSynced;

  /// POS sync status: the order's demo delivery failed and can be retried.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get posSyncStateFailed;

  /// POS honest note that the queued order is stored locally and not yet pushed to a backend.
  ///
  /// In en, this message translates to:
  /// **'Stored locally — backend sync pending'**
  String get posSyncStoredLocally;

  /// POS honest note that the sync lifecycle is a local demo and nothing is sent to a real backend.
  ///
  /// In en, this message translates to:
  /// **'Demo sync — not sent to a real backend'**
  String get posSyncDemoNotice;

  /// POS action that runs the demo push of a locally-queued order.
  ///
  /// In en, this message translates to:
  /// **'Sync now (demo)'**
  String get posSyncNow;

  /// POS action that re-queues and re-pushes a failed outbox entry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get posSyncRetry;

  /// POS label preceding the compact outbox operation reference (idempotency local_operation_id).
  ///
  /// In en, this message translates to:
  /// **'Outbox ref'**
  String get posOutboxRefLabel;

  /// POS message shown when enqueuing the order to the outbox failed; the cart is kept.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t queue the order — please try again'**
  String get posSubmitFailed;

  /// POS cart-header chip showing how many submitted orders are still queued for sync.
  ///
  /// In en, this message translates to:
  /// **'{count} pending sync'**
  String posSyncPendingCount(int count);

  /// POS action on the order confirmation that opens the cash-payment sheet.
  ///
  /// In en, this message translates to:
  /// **'Pay Cash'**
  String get posPayCash;

  /// POS heading of the cash-payment sheet.
  ///
  /// In en, this message translates to:
  /// **'Cash payment'**
  String get posPaymentTitle;

  /// POS label for the order total the customer must pay.
  ///
  /// In en, this message translates to:
  /// **'Amount due'**
  String get posAmountDue;

  /// POS label for the cash amount handed over by the customer.
  ///
  /// In en, this message translates to:
  /// **'Cash received'**
  String get posCashReceived;

  /// POS quick-cash button that fills the cash field with the exact amount due.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get posCashExact;

  /// POS label for the change to give back (cash received minus amount due).
  ///
  /// In en, this message translates to:
  /// **'Change due'**
  String get posChangeDue;

  /// POS action that records the cash payment and marks the order paid.
  ///
  /// In en, this message translates to:
  /// **'Confirm payment'**
  String get posConfirmPayment;

  /// POS validation message when the typed cash amount is empty or malformed.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get posCashInvalid;

  /// POS validation message when the cash received is less than the amount due.
  ///
  /// In en, this message translates to:
  /// **'Cash received must cover the amount due'**
  String get posCashInsufficient;

  /// POS status chip shown on a paid order.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get posPaidChip;

  /// POS receipt label preceding the payment method.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get posPaymentMethodLabel;

  /// POS payment method value: cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get posPaymentMethodCash;

  /// POS receipt label preceding the payment timestamp.
  ///
  /// In en, this message translates to:
  /// **'Paid at'**
  String get posPaidAtLabel;

  /// POS heading of the receipt preview card.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get posReceiptTitle;

  /// POS receipt label preceding the receipt number/reference.
  ///
  /// In en, this message translates to:
  /// **'Receipt no.'**
  String get posReceiptNumberLabel;

  /// POS receipt label for the order total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get posReceiptTotal;

  /// POS note that the receipt number is a local provisional id, reconciled to a server number on sync.
  ///
  /// In en, this message translates to:
  /// **'Provisional — reconciled to a server receipt on sync'**
  String get posReceiptProvisionalNote;

  /// POS note that the receipt is a demo preview and nothing is printed.
  ///
  /// In en, this message translates to:
  /// **'Demo receipt — no printer connected'**
  String get posReceiptDemoNote;

  /// POS disabled demo action that would print the receipt (no printer integration).
  ///
  /// In en, this message translates to:
  /// **'Print receipt (demo)'**
  String get posPrintReceiptDemo;

  /// Action that opens the browser-style print preview (POS receipt).
  ///
  /// In en, this message translates to:
  /// **'Print preview'**
  String get printPreviewAction;

  /// Print-preview action that triggers the browser print (web) of the preview.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printPreviewPrint;

  /// Print-preview action that closes the preview dialog.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get printPreviewClose;

  /// Honest hint in the print preview: it is a browser print preview, not a hardware printer.
  ///
  /// In en, this message translates to:
  /// **'Use your browser\'s print (Ctrl+P) to print this preview'**
  String get printPreviewHint;

  /// Tooltip of the POS/KDS app-bar overflow (three-dot) device menu.
  ///
  /// In en, this message translates to:
  /// **'Device menu'**
  String get deviceSettingsMenuTooltip;

  /// Title of the operational device-settings sheet on POS/KDS and its menu entry. NOT an owner/admin screen.
  ///
  /// In en, this message translates to:
  /// **'Device settings'**
  String get deviceSettingsTitle;

  /// Device-menu action: reload the device session/printer assignments.
  ///
  /// In en, this message translates to:
  /// **'Refresh connection'**
  String get deviceRefreshAction;

  /// Device-menu action: clear this device's local pairing and return to the pairing screen.
  ///
  /// In en, this message translates to:
  /// **'Unpair device'**
  String get deviceUnpairAction;

  /// Warning shown before unpairing a device.
  ///
  /// In en, this message translates to:
  /// **'Only use this if this device should be paired again.'**
  String get deviceUnpairWarning;

  /// Confirming button of the unpair dialog.
  ///
  /// In en, this message translates to:
  /// **'Unpair'**
  String get deviceUnpairConfirm;

  /// Cancel button of the unpair confirmation dialog.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get deviceUnpairCancel;

  /// Device-settings row label: which surface this device runs (POS or KDS).
  ///
  /// In en, this message translates to:
  /// **'App type'**
  String get deviceSettingsAppTypeLabel;

  /// Device-settings app-type value for the POS surface.
  ///
  /// In en, this message translates to:
  /// **'Cashier (POS)'**
  String get deviceSettingsAppTypePos;

  /// Device-settings app-type value for the KDS surface.
  ///
  /// In en, this message translates to:
  /// **'Kitchen display (KDS)'**
  String get deviceSettingsAppTypeKds;

  /// Device-settings row label: the restaurant this device belongs to.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get deviceSettingsRestaurantLabel;

  /// Device-settings row label: the branch this device belongs to.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get deviceSettingsBranchLabel;

  /// Device-settings row label: this device's own label/name.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get deviceSettingsDeviceLabel;

  /// Device-settings row label: the device pairing/session status.
  ///
  /// In en, this message translates to:
  /// **'Pairing'**
  String get deviceSettingsPairingLabel;

  /// Device-settings pairing status: the device holds an active pairing.
  ///
  /// In en, this message translates to:
  /// **'Paired'**
  String get deviceSettingsPairingActive;

  /// Device-settings row label: whether a staff PIN session is active on this device.
  ///
  /// In en, this message translates to:
  /// **'Staff session'**
  String get deviceSettingsPinSessionLabel;

  /// Device-settings staff-session status: a PIN session is active.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get deviceSettingsPinSessionActive;

  /// Device-settings staff-session status: no PIN session.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get deviceSettingsPinSessionNone;

  /// Honest device-settings note in demo mode (no backend, no pairing).
  ///
  /// In en, this message translates to:
  /// **'Demo mode — no paired device.'**
  String get deviceSettingsDemoNote;

  /// Device-settings fallback when no paired-device context is available.
  ///
  /// In en, this message translates to:
  /// **'Device info unavailable.'**
  String get deviceSettingsUnavailable;

  /// Device-settings section heading: the printers assigned to this device's branch.
  ///
  /// In en, this message translates to:
  /// **'Printers'**
  String get deviceSettingsPrintersHeading;

  /// Device-settings empty state: no printer of this device's role is configured for its branch.
  ///
  /// In en, this message translates to:
  /// **'No printer assigned. Ask a manager to configure it in Dashboard → Printers.'**
  String get deviceSettingsNoPrinter;

  /// Printer capability status: the printer is configured in the Dashboard but this build has no physical print transport.
  ///
  /// In en, this message translates to:
  /// **'Configured only — print bridge required.'**
  String get deviceSettingsBridgeRequired;

  /// Honest capability note: physical printing is not possible from this web build; jobs are prepared/previewed only.
  ///
  /// In en, this message translates to:
  /// **'Printing requires a print bridge/native app. This build can save config and create/preview print jobs.'**
  String get deviceSettingsCapabilityNote;

  /// Device-settings footer: when the printer assignments were last fetched.
  ///
  /// In en, this message translates to:
  /// **'Last refresh: {time}'**
  String deviceSettingsLastRefresh(String time);

  /// Device-settings safe error when the assignments RPC fails (network/session).
  ///
  /// In en, this message translates to:
  /// **'Could not load printer assignments.'**
  String get deviceSettingsLoadError;

  /// Printer row status: the printer exists but is disabled by the owner in the Dashboard.
  ///
  /// In en, this message translates to:
  /// **'Disabled in Dashboard'**
  String get deviceSettingsPrinterDisabled;

  /// Printer row subtitle: the kitchen stations routed to this printer.
  ///
  /// In en, this message translates to:
  /// **'Stations: {names}'**
  String deviceSettingsRouteStations(String names);

  /// Snackbar after the device menu's Refresh connection reloaded the assignments.
  ///
  /// In en, this message translates to:
  /// **'Connection refreshed.'**
  String get deviceRefreshedSnack;

  /// Snackbar after the device was unpaired locally.
  ///
  /// In en, this message translates to:
  /// **'Device unpaired.'**
  String get deviceUnpairedSnack;

  /// Device-settings section heading: per-device automatic print triggers.
  ///
  /// In en, this message translates to:
  /// **'Auto-print'**
  String get deviceSettingsAutoPrintHeading;

  /// POS device-settings toggle: prepare a customer receipt print job automatically after a successful payment.
  ///
  /// In en, this message translates to:
  /// **'Auto-print receipt after payment'**
  String get posAutoPrintReceiptToggle;

  /// KDS device-settings toggle: prepare a kitchen-ticket print job automatically when a ticket is acknowledged.
  ///
  /// In en, this message translates to:
  /// **'Auto-print kitchen ticket on acknowledge'**
  String get kdsAutoPrintAcknowledgeToggle;

  /// Why an auto-print toggle is disabled: the branch has no printer of the needed role.
  ///
  /// In en, this message translates to:
  /// **'Disabled — no printer assigned.'**
  String get autoPrintNoPrinterNote;

  /// Print-job status: nothing was prepared because no printer is assigned.
  ///
  /// In en, this message translates to:
  /// **'No printer configured'**
  String get printStatusNotConfigured;

  /// Print-job status: the job payload is ready; no physical transport exists in this build, so it is NOT claimed as printed.
  ///
  /// In en, this message translates to:
  /// **'Print job prepared — physical printing requires print bridge.'**
  String get printStatusPrepared;

  /// Print-job status: a transport CONFIRMED the physical print (unreachable until a print bridge exists).
  ///
  /// In en, this message translates to:
  /// **'Printed'**
  String get printStatusPrinted;

  /// Print-job status: preparing/sending the job failed; the order/ticket itself is unaffected.
  ///
  /// In en, this message translates to:
  /// **'Print failed'**
  String get printStatusFailed;

  /// Print-job status: the local print bridge CONFIRMED it wrote the bytes to the printer transport. This is delivery-to-printer, NOT a hardware paper-print acknowledgement (ESC/POS over a socket has none).
  ///
  /// In en, this message translates to:
  /// **'Sent to the printer (not confirmed printed)'**
  String get printStatusSentToPrinter;

  /// Print-job status: a local print bridge is configured/expected but could not be reached; the job was prepared but not delivered.
  ///
  /// In en, this message translates to:
  /// **'Print bridge unavailable — job not sent'**
  String get printStatusBridgeUnavailable;

  /// Button that re-runs a failed / bridge-unavailable / not-configured print job.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get printRetryAction;

  /// PRINT-STABILITY-001: button that re-sends an already-printed job (an extra money-free copy) — used on a sent KDS kitchen ticket.
  ///
  /// In en, this message translates to:
  /// **'Reprint'**
  String get printReprintAction;

  /// Device-settings bridge row: a local print bridge answered its health check.
  ///
  /// In en, this message translates to:
  /// **'Print bridge: connected'**
  String get deviceSettingsBridgeConnected;

  /// Device-settings bridge row: a local print bridge is configured but not currently reachable.
  ///
  /// In en, this message translates to:
  /// **'Print bridge: unavailable'**
  String get deviceSettingsBridgeUnavailable;

  /// Device-settings bridge row: when the last print job was submitted to the bridge.
  ///
  /// In en, this message translates to:
  /// **'Last print job: {time}'**
  String deviceSettingsBridgeLastJob(String time);

  /// Label of the receipt print-job status line on the POS order confirmation.
  ///
  /// In en, this message translates to:
  /// **'Receipt print'**
  String get posReceiptPrintLabel;

  /// Label of the kitchen print-job status line on a KDS ticket.
  ///
  /// In en, this message translates to:
  /// **'Kitchen print'**
  String get kdsTicketPrintLabel;

  /// Title of the POS receipt print-preview dialog.
  ///
  /// In en, this message translates to:
  /// **'Receipt preview'**
  String get receiptPreviewTitle;

  /// Demo restaurant name printed at the top of the receipt preview.
  ///
  /// In en, this message translates to:
  /// **'RestoFlow Demo Restaurant'**
  String get receiptDemoRestaurantName;

  /// KDS action on a kitchen order card that opens the kitchen-ticket print preview.
  ///
  /// In en, this message translates to:
  /// **'Preview ticket'**
  String get kdsPreviewTicketAction;

  /// Title of the KDS kitchen-ticket print-preview dialog.
  ///
  /// In en, this message translates to:
  /// **'Kitchen ticket preview'**
  String get kdsTicketPreviewTitle;

  /// KDS label preceding the elapsed time since an order was submitted.
  ///
  /// In en, this message translates to:
  /// **'Elapsed'**
  String get kdsElapsedLabel;

  /// Tooltip for the EN/AR/HE language selector in the app bar.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSelectorTooltip;

  /// Language selector option: English (endonym, same in every locale).
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Language selector option: Arabic (endonym, same in every locale).
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// Language selector option: Hebrew (endonym, same in every locale).
  ///
  /// In en, this message translates to:
  /// **'עברית'**
  String get languageHebrew;

  /// POS demo shift name shown in the shift/cash-drawer context bar.
  ///
  /// In en, this message translates to:
  /// **'Demo morning shift'**
  String get posShiftDemoName;

  /// POS label for the cash drawer in the shift context bar.
  ///
  /// In en, this message translates to:
  /// **'Cash drawer'**
  String get posDrawerLabel;

  /// POS cash-drawer state: open/active.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get posDrawerOpen;

  /// POS cash-drawer state: closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get posDrawerClosed;

  /// POS label for the running cash total in the drawer.
  ///
  /// In en, this message translates to:
  /// **'Cash in drawer'**
  String get posCashInDrawer;

  /// POS label for the amount of the most recent cash payment.
  ///
  /// In en, this message translates to:
  /// **'Last cash payment'**
  String get posLastCashPayment;

  /// POS honest note that the shift/cash-drawer context is a local demo and not synced.
  ///
  /// In en, this message translates to:
  /// **'Demo — reconciliation is computed locally and not saved to a server.'**
  String get posShiftDemoNote;

  /// REAL-mode shift bar label: a real shift was opened on the server at PIN sign-in.
  ///
  /// In en, this message translates to:
  /// **'Current shift'**
  String get posShiftRealName;

  /// REAL-mode shift bar note: the RF-055 auto-opened server shift holds the cash truth; local drawer figures are never invented.
  ///
  /// In en, this message translates to:
  /// **'Opened at sign-in — cash totals are tracked on the server'**
  String get posShiftRealNote;

  /// No description provided for @posShiftCloseTitle.
  ///
  /// In en, this message translates to:
  /// **'Close shift & count cash'**
  String get posShiftCloseTitle;

  /// No description provided for @posShiftCloseMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get posShiftCloseMenuItem;

  /// No description provided for @posShiftCloseConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Close this shift?'**
  String get posShiftCloseConfirmTitle;

  /// No description provided for @posShiftCloseConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The shift will be closed with the counted amount and can\'t be reopened.'**
  String get posShiftCloseConfirmBody;

  /// No description provided for @posShiftCancelAction.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get posShiftCancelAction;

  /// No description provided for @posShiftCloseAction.
  ///
  /// In en, this message translates to:
  /// **'Close shift'**
  String get posShiftCloseAction;

  /// No description provided for @posShiftDoneAction.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get posShiftDoneAction;

  /// No description provided for @posShiftNoOpenShift.
  ///
  /// In en, this message translates to:
  /// **'No open shift on this device.'**
  String get posShiftNoOpenShift;

  /// No description provided for @posShiftNoOpenShiftHint.
  ///
  /// In en, this message translates to:
  /// **'A shift opens automatically when a cashier signs in.'**
  String get posShiftNoOpenShiftHint;

  /// No description provided for @posShiftOpenedAt.
  ///
  /// In en, this message translates to:
  /// **'Opened at'**
  String get posShiftOpenedAt;

  /// No description provided for @posShiftOpeningFloat.
  ///
  /// In en, this message translates to:
  /// **'Opening float'**
  String get posShiftOpeningFloat;

  /// No description provided for @posShiftExpectedCash.
  ///
  /// In en, this message translates to:
  /// **'Expected cash'**
  String get posShiftExpectedCash;

  /// No description provided for @posShiftExpectedAtClose.
  ///
  /// In en, this message translates to:
  /// **'Expected cash is calculated on the server at close.'**
  String get posShiftExpectedAtClose;

  /// No description provided for @posShiftCountedLabel.
  ///
  /// In en, this message translates to:
  /// **'Counted cash'**
  String get posShiftCountedLabel;

  /// No description provided for @posShiftInvalidAmount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount.'**
  String get posShiftInvalidAmount;

  /// No description provided for @posShiftReasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason (required if there\'s a difference)'**
  String get posShiftReasonLabel;

  /// No description provided for @posShiftReasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a reason when the counted cash differs from expected.'**
  String get posShiftReasonRequired;

  /// No description provided for @posShiftClosedTitle.
  ///
  /// In en, this message translates to:
  /// **'Shift closed'**
  String get posShiftClosedTitle;

  /// No description provided for @posShiftBalanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get posShiftBalanced;

  /// No description provided for @posShiftOver.
  ///
  /// In en, this message translates to:
  /// **'Over'**
  String get posShiftOver;

  /// No description provided for @posShiftShort.
  ///
  /// In en, this message translates to:
  /// **'Short'**
  String get posShiftShort;

  /// No description provided for @posShiftDifference.
  ///
  /// In en, this message translates to:
  /// **'Difference'**
  String get posShiftDifference;

  /// No description provided for @posShiftCloseUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Closing is unavailable — a staff session on a paired device is required.'**
  String get posShiftCloseUnavailable;

  /// No description provided for @posShiftClosePermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'You aren\'t allowed to close this shift.'**
  String get posShiftClosePermissionDenied;

  /// No description provided for @posShiftCloseServerRejected.
  ///
  /// In en, this message translates to:
  /// **'The server rejected the close — a reason may be required or the shift state is invalid.'**
  String get posShiftCloseServerRejected;

  /// No description provided for @posShiftCloseFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t close the shift.'**
  String get posShiftCloseFailed;

  /// No description provided for @posShiftCouldNotRestore.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t restore the shift state. Sign in again to open a shift.'**
  String get posShiftCouldNotRestore;

  /// No description provided for @posShiftReturnToPin.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get posShiftReturnToPin;

  /// REAL-mode sync note while the order push is in flight.
  ///
  /// In en, this message translates to:
  /// **'Sending to the backend…'**
  String get posSyncSendingReal;

  /// REAL-mode sync note once the backend applied the order.
  ///
  /// In en, this message translates to:
  /// **'Sent — the kitchen display receives it automatically.'**
  String get posSyncSentReal;

  /// REAL-mode sync note when the backend rejected the order; honest, with Retry offered.
  ///
  /// In en, this message translates to:
  /// **'The backend rejected this order — it was NOT sent to the kitchen.'**
  String get posSyncFailedReal;

  /// REAL-mode label of the manual send button for a pending (not yet pushed) order.
  ///
  /// In en, this message translates to:
  /// **'Send now'**
  String get posSyncSendNow;

  /// REAL-mode receipt note: the receipt number is the true server number; only printing hardware is missing.
  ///
  /// In en, this message translates to:
  /// **'Printing is not connected on this device yet'**
  String get posReceiptNoPrinterNote;

  /// Pill on a modifier group the cashier MUST choose from (e.g. doneness) before adding the item.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get posModifierRequired;

  /// Quiet pill on a modifier group the cashier MAY skip (no minimum selection).
  ///
  /// In en, this message translates to:
  /// **'Optional'**
  String get posModifierOptional;

  /// Live selected-count indicator on a modifier group with a maximum, e.g. 1/2 (selected of max).
  ///
  /// In en, this message translates to:
  /// **'{selected}/{max}'**
  String posModifierSelectedCount(int selected, int max);

  /// Live selected-count indicator on a modifier group WITHOUT a maximum: just the number selected.
  ///
  /// In en, this message translates to:
  /// **'{selected}'**
  String posModifierSelectedCountOpen(int selected);

  /// Quiet label on a modifier option whose price delta is zero (included at no charge).
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get posModifierFree;

  /// Modifier-sheet header subtitle: the item's base price BEFORE option deltas (already currency-formatted), shown so the cashier can compare base vs the running total.
  ///
  /// In en, this message translates to:
  /// **'Base price · {price}'**
  String posModifierBasePrice(String price);

  /// Label of the optional per-item special-instructions field on the POS modifier sheet (e.g. no onions).
  ///
  /// In en, this message translates to:
  /// **'Item note'**
  String get posModifierItemNoteLabel;

  /// Placeholder/hint of the per-item note field on the POS modifier sheet, suggesting typical kitchen instructions.
  ///
  /// In en, this message translates to:
  /// **'Example: no onions, extra sauce'**
  String get posModifierItemNoteHint;

  /// Short prefix label before a cart line's / receipt line's per-item note, e.g. 'Note: no onions'.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get posItemNoteLabel;

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

  /// Owner dashboard Overview card title for today's shift / cash reconciliation (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'Shift & cash'**
  String get dashboardShiftCashTitle;

  /// Count of shifts closed today, shown as a pill on the Shift & cash card (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'{count} closed today'**
  String dashboardShiftClosedToday(int count);

  /// Count of shifts currently open, shown as a pill on the Shift & cash card (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'{count} open now'**
  String dashboardShiftOpenNow(int count);

  /// Shift & cash card row: expected cash (opening float + cash sales) for today's closed shifts (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'Expected cash'**
  String get dashboardShiftExpectedCash;

  /// Shift & cash card sub-heading for the most recent closed shift's summary (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'Last closed shift'**
  String get dashboardShiftLastClosed;

  /// Shift & cash card: who closed the shift (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'Closed by {name}'**
  String dashboardShiftClosedBy(String name);

  /// Shift & cash card calm empty state when no shift has been closed today (RF-REPORT-003).
  ///
  /// In en, this message translates to:
  /// **'No closed shifts yet today.'**
  String get dashboardShiftNoneToday;

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

  /// Owner dashboard reports section heading above the day context and KPI cards.
  ///
  /// In en, this message translates to:
  /// **'Owner reports'**
  String get dashboardReportsHeading;

  /// Owner dashboard label preceding the business day a report covers.
  ///
  /// In en, this message translates to:
  /// **'Report day'**
  String get dashboardReportDayLabel;

  /// Owner dashboard pill clarifying the report day is a demo day, not a live date.
  ///
  /// In en, this message translates to:
  /// **'Demo day'**
  String get dashboardDemoDay;

  /// Owner dashboard action that reloads the report.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get dashboardRefresh;

  /// Owner dashboard message shown while the report is loading.
  ///
  /// In en, this message translates to:
  /// **'Loading reports…'**
  String get dashboardLoadingReports;

  /// Owner dashboard message shown when the report fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load reports.'**
  String get dashboardReportsError;

  /// Owner dashboard action that retries loading the report after an error.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get dashboardRetry;

  /// Owner dashboard message shown when there is no report data for the day.
  ///
  /// In en, this message translates to:
  /// **'No report data for this day.'**
  String get dashboardNoReportData;

  /// Owner dashboard banner honestly stating the reports are computed from local demo data, not a live backend.
  ///
  /// In en, this message translates to:
  /// **'Demo reports — calculated locally from sample orders, not synced to a backend.'**
  String get dashboardDemoReportsNotice;

  /// Owner dashboard real-mode banner: the reports are live but read-only and limited (RF-140).
  ///
  /// In en, this message translates to:
  /// **'Live reports — read-only and limited. Some figures aren\'t available here yet.'**
  String get dashboardRealModeNotice;

  /// Owner dashboard pill shown in real mode in place of the 'Demo day' pill.
  ///
  /// In en, this message translates to:
  /// **'Live · limited'**
  String get dashboardLiveDataTag;

  /// Owner dashboard real-mode reports banner title, making the live-but-limited state feel intentional (LIVE-UX-001).
  ///
  /// In en, this message translates to:
  /// **'Live reports'**
  String get dashboardLiveReportsTitle;

  /// Owner dashboard note listing the analytics that are not yet available in the live-limited report; shown instead of empty cards (LIVE-UX-001).
  ///
  /// In en, this message translates to:
  /// **'Detailed analytics — sales by hour, top items, sales by branch, and recent orders — will appear here once full reporting is enabled.'**
  String get dashboardLiveReportsPending;

  /// Devices screen: count of live (non-revoked) devices shown above the list; status-neutral because they may be pending/paired/active, not only 'active' (LIVE-UX-001).
  ///
  /// In en, this message translates to:
  /// **'{count} devices'**
  String adminDevicesShownCount(int count);

  /// Devices screen: count of revoked devices (LIVE-UX-001).
  ///
  /// In en, this message translates to:
  /// **'{count} revoked'**
  String adminDevicesRevokedCount(int count);

  /// Devices screen: collapsed section title holding the read-only revoked-device history (LIVE-UX-001).
  ///
  /// In en, this message translates to:
  /// **'Revoked devices'**
  String get adminDevicesRevokedSection;

  /// Owner dashboard KPI card label for gross sales (before discounts).
  ///
  /// In en, this message translates to:
  /// **'Gross sales'**
  String get dashboardGrossSales;

  /// Owner dashboard label for total completed cash sales.
  ///
  /// In en, this message translates to:
  /// **'Cash sales'**
  String get dashboardCashSales;

  /// Owner dashboard KPI card label for the count of unpaid orders.
  ///
  /// In en, this message translates to:
  /// **'Unpaid orders'**
  String get dashboardUnpaidOrders;

  /// Dashboard '1c' Overview card title for the payment-mix donut (cash vs card share).
  ///
  /// In en, this message translates to:
  /// **'Payment mix'**
  String get dashboardPaymentMix;

  /// Owner dashboard heading for the payment and cash-drawer summary card.
  ///
  /// In en, this message translates to:
  /// **'Payment & cash summary'**
  String get dashboardPaymentSummary;

  /// Owner dashboard payment-summary row label for the shift opening cash float.
  ///
  /// In en, this message translates to:
  /// **'Opening float'**
  String get dashboardOpeningFloat;

  /// Owner dashboard payment-summary row label for expected cash in the drawer (opening float + cash sales).
  ///
  /// In en, this message translates to:
  /// **'Expected in drawer'**
  String get dashboardExpectedDrawer;

  /// Owner dashboard payment-summary row label for the physically counted cash.
  ///
  /// In en, this message translates to:
  /// **'Counted cash'**
  String get dashboardCountedCash;

  /// Owner dashboard payment-summary row label for the most recent cash payment amount.
  ///
  /// In en, this message translates to:
  /// **'Last cash payment'**
  String get dashboardLastCashPayment;

  /// Owner dashboard heading for the payment-method breakdown.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get dashboardPaymentMethods;

  /// Owner dashboard payment-method label for cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get dashboardPaymentMethodCash;

  /// Owner dashboard heading for the recent-orders list.
  ///
  /// In en, this message translates to:
  /// **'Recent orders'**
  String get dashboardRecentOrders;

  /// Owner dashboard recent-orders chip for a paid order.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get dashboardPaid;

  /// Owner dashboard recent-orders chip for an unpaid order.
  ///
  /// In en, this message translates to:
  /// **'Unpaid'**
  String get dashboardUnpaid;

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

  /// Title of the help page shown when the app starts in real mode without valid Supabase connection settings.
  ///
  /// In en, this message translates to:
  /// **'Real mode is not configured'**
  String get authRealModeUnconfiguredTitle;

  /// Body of the real-mode-unconfigured help page explaining why the app is locked.
  ///
  /// In en, this message translates to:
  /// **'The app was started in real mode, but the backend connection settings are missing or invalid. RestoFlow never fakes a backend, so real mode stays locked until valid settings are provided.'**
  String get authRealModeUnconfiguredBody;

  /// Heading above the code block listing the required --dart-define values for real mode.
  ///
  /// In en, this message translates to:
  /// **'Start the app with these values'**
  String get authRealModeUnconfiguredHowTo;

  /// Hint on the real-mode-unconfigured help page explaining how to run the demo.
  ///
  /// In en, this message translates to:
  /// **'To explore the demo instead, run the app without any configuration — demo mode is the default.'**
  String get authRealModeUnconfiguredDemoHint;

  /// Title of the help page shown when a release build is in demo mode while valid real backend credentials are present (an accidental production demo).
  ///
  /// In en, this message translates to:
  /// **'Demo mode is on with real credentials'**
  String get authProductionDemoBlockedTitle;

  /// Body of the production-demo-blocked help page explaining the misconfiguration and how to fix it.
  ///
  /// In en, this message translates to:
  /// **'This build has valid backend connection settings but is running in demo mode, so it would show demo data as if it were live. Turn off demo mode to serve real data, or remove the connection settings to run the demo. RestoFlow never presents demo data as production.'**
  String get authProductionDemoBlockedBody;

  /// Title of the help page shown when POS/KDS device bootstrap fails because anonymous sign-in is rejected by the backend.
  ///
  /// In en, this message translates to:
  /// **'Device sign-in unavailable'**
  String get authDeviceSignInUnavailableTitle;

  /// Body of the device-sign-in-unavailable help page: the exact reason pairing cannot start.
  ///
  /// In en, this message translates to:
  /// **'Anonymous device sign-in is disabled or Supabase auth is not configured.'**
  String get authDeviceSignInUnavailableBody;

  /// Heading above the code block showing the Supabase auth setting that enables anonymous device sign-in.
  ///
  /// In en, this message translates to:
  /// **'How to fix it'**
  String get authDeviceSignInUnavailableHowTo;

  /// Hint on the device-sign-in-unavailable help page explaining the fix and that no owner account is required on a POS/KDS device.
  ///
  /// In en, this message translates to:
  /// **'Allow anonymous sign-ins in the Supabase Auth settings, restart the backend, then restart this app. No personal account is needed on this device — pairing signs the device in by itself.'**
  String get authDeviceSignInUnavailableFix;

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

  /// Dashboard navigation label for the overview/report screen.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get dashboardNavOverview;

  /// Dashboard navigation label for the menu management surface.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get dashboardNavMenu;

  /// Title of the owner menu management surface.
  ///
  /// In en, this message translates to:
  /// **'Menu management'**
  String get menuManagementTitle;

  /// Banner explaining the menu surface uses local demo data, not a real backend.
  ///
  /// In en, this message translates to:
  /// **'Demo data — changes stay on this device and are not saved to a server yet.'**
  String get menuDemoBanner;

  /// Heading for the list of menu categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get menuCategoriesHeading;

  /// Heading for the list of menu items in a category.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get menuItemsHeading;

  /// Hint shown in the detail panel before a category is selected.
  ///
  /// In en, this message translates to:
  /// **'Select a category to see its items.'**
  String get menuSelectCategoryHint;

  /// Empty state for the category list.
  ///
  /// In en, this message translates to:
  /// **'No categories yet.'**
  String get menuEmptyCategories;

  /// Empty state for the item list of a category.
  ///
  /// In en, this message translates to:
  /// **'No items in this category yet.'**
  String get menuEmptyItems;

  /// Error state when the menu fails to load.
  ///
  /// In en, this message translates to:
  /// **'Could not load the menu.'**
  String get menuLoadError;

  /// Button to retry loading the menu.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get menuRetry;

  /// Number of items in a category.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String menuItemCount(int count);

  /// Action to create a new menu category.
  ///
  /// In en, this message translates to:
  /// **'Add category'**
  String get menuAddCategory;

  /// Action to create a new menu item.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get menuAddItem;

  /// Action to add a size option to an item.
  ///
  /// In en, this message translates to:
  /// **'Add size'**
  String get menuAddSize;

  /// Action to add a variant option to an item.
  ///
  /// In en, this message translates to:
  /// **'Add variant'**
  String get menuAddVariant;

  /// Action to add a modifier group to an item.
  ///
  /// In en, this message translates to:
  /// **'Add modifier'**
  String get menuAddModifier;

  /// Action to add an option to a modifier.
  ///
  /// In en, this message translates to:
  /// **'Add option'**
  String get menuAddOption;

  /// Generic edit dialog title.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEditTitle;

  /// Save button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get menuSaveAction;

  /// Cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get menuCancelAction;

  /// Edit a menu entry.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get menuEditAction;

  /// Delete (soft-delete) a menu entry.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get menuDeleteAction;

  /// Name field label for menu entries.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get menuNameLabel;

  /// Optional description field label for a menu item.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get menuDescriptionLabel;

  /// Base price field label for a menu item.
  ///
  /// In en, this message translates to:
  /// **'Base price'**
  String get menuPriceLabel;

  /// Signed price-delta field label for sizes/variants/options.
  ///
  /// In en, this message translates to:
  /// **'Price change'**
  String get menuPriceDeltaLabel;

  /// Currency code field label.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get menuCurrencyLabel;

  /// Category selector field label for an item.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get menuCategoryFieldLabel;

  /// Display-order field label.
  ///
  /// In en, this message translates to:
  /// **'Display order'**
  String get menuDisplayOrderLabel;

  /// Active/inactive toggle label.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get menuActiveLabel;

  /// Modifier selection-type field label.
  ///
  /// In en, this message translates to:
  /// **'Selection'**
  String get menuSelectionTypeLabel;

  /// Single-selection modifier type.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get menuSelectionSingle;

  /// Multiple-selection modifier type.
  ///
  /// In en, this message translates to:
  /// **'Multiple'**
  String get menuSelectionMultiple;

  /// Modifier minimum-selection field label.
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get menuMinSelectLabel;

  /// Modifier maximum-selection field label.
  ///
  /// In en, this message translates to:
  /// **'Maximum (optional)'**
  String get menuMaxSelectLabel;

  /// Modifier required toggle label.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get menuRequiredLabel;

  /// Modifier-group toggle: the cashier may add the same option more than once (quantity stepper on the POS).
  ///
  /// In en, this message translates to:
  /// **'Allow quantity'**
  String get menuAllowQuantityLabel;

  /// Helper text under the allow-quantity toggle explaining what it enables on the POS.
  ///
  /// In en, this message translates to:
  /// **'The cashier can add the same option more than once (e.g. extra cheese ×2).'**
  String get menuAllowQuantityHelp;

  /// Modifier-group field label: maximum quantity of a single option (only when quantity is allowed).
  ///
  /// In en, this message translates to:
  /// **'Max per option'**
  String get menuMaxQuantityLabel;

  /// Heading for an item's sizes.
  ///
  /// In en, this message translates to:
  /// **'Sizes'**
  String get menuSizesHeading;

  /// Heading for an item's variants.
  ///
  /// In en, this message translates to:
  /// **'Variants'**
  String get menuVariantsHeading;

  /// Heading for an item's modifiers.
  ///
  /// In en, this message translates to:
  /// **'Modifiers'**
  String get menuModifiersHeading;

  /// Heading for a modifier's options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get menuOptionsHeading;

  /// Soft-delete confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Delete this entry?'**
  String get menuDeleteConfirmTitle;

  /// Soft-delete confirmation dialog body.
  ///
  /// In en, this message translates to:
  /// **'It will be hidden from the menu. You can restore it later.'**
  String get menuDeleteConfirmBody;

  /// Confirm-delete button.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get menuConfirmDelete;

  /// Badge for an inactive menu entry.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get menuInactiveBadge;

  /// Badge for a restaurant-scoped (global) menu entry.
  ///
  /// In en, this message translates to:
  /// **'All branches'**
  String get menuGlobalBadge;

  /// Badge for a branch-scoped menu entry.
  ///
  /// In en, this message translates to:
  /// **'This branch'**
  String get menuBranchBadge;

  /// Heading for the item image section.
  ///
  /// In en, this message translates to:
  /// **'Item image'**
  String get menuImageHeading;

  /// Title of the image panel's honest state when no image storage is wired for this surface.
  ///
  /// In en, this message translates to:
  /// **'Image upload isn\'t connected'**
  String get menuImageDeferredTitle;

  /// Body explaining that no image storage backend is wired for this surface.
  ///
  /// In en, this message translates to:
  /// **'This surface has no image storage connected, so item photos can\'t be uploaded or shown here.'**
  String get menuImageDeferredBody;

  /// Button that opens the image file picker for an item without an image.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get menuImagePickAction;

  /// Button that opens the image file picker to replace an item's existing image.
  ///
  /// In en, this message translates to:
  /// **'Replace image'**
  String get menuImageReplaceAction;

  /// Button that removes the item's current image.
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get menuImageRemoveAction;

  /// Button that uploads the picked image and saves it on the item.
  ///
  /// In en, this message translates to:
  /// **'Save image'**
  String get menuImageSaveAction;

  /// Error when the picked file's type is not an allowed image MIME type.
  ///
  /// In en, this message translates to:
  /// **'Only PNG, JPEG, or WebP images can be uploaded.'**
  String get menuImageInvalidType;

  /// Error when the picked image exceeds the bucket size limit.
  ///
  /// In en, this message translates to:
  /// **'The image is too large — the limit is 5 MB.'**
  String get menuImageTooLarge;

  /// Error when the storage upload fails; nothing was persisted.
  ///
  /// In en, this message translates to:
  /// **'Upload failed — the image was not saved.'**
  String get menuImageUploadFailed;

  /// Note shown on platforms without an image file picker.
  ///
  /// In en, this message translates to:
  /// **'Choosing an image isn\'t available on this platform yet — use the web dashboard.'**
  String get menuImageUnsupportedPlatform;

  /// Honest note on the demo surface: picked images are kept in memory only.
  ///
  /// In en, this message translates to:
  /// **'Demo — the image is not uploaded to a server.'**
  String get menuImageDemoNote;

  /// Caption when the stored image preview fails to load.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the image preview.'**
  String get menuImageLoadError;

  /// Validation error: a required field is blank.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get menuErrorRequired;

  /// Validation error: a price did not parse to an amount.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid amount'**
  String get menuErrorAmount;

  /// Validation error: base price is negative.
  ///
  /// In en, this message translates to:
  /// **'Cannot be negative'**
  String get menuErrorNegativePrice;

  /// Validation error: invalid currency code.
  ///
  /// In en, this message translates to:
  /// **'Use a 3-letter code (e.g. ILS)'**
  String get menuErrorCurrency;

  /// Validation error: invalid selection type.
  ///
  /// In en, this message translates to:
  /// **'Choose single or multiple'**
  String get menuErrorSelectionType;

  /// Validation error: max-select is below min-select.
  ///
  /// In en, this message translates to:
  /// **'Must be at least the minimum'**
  String get menuErrorMaxLessThanMin;

  /// Failure message: the role lacks menu write permission.
  ///
  /// In en, this message translates to:
  /// **'You can\'t change the menu in this scope.'**
  String get menuWritePermissionDenied;

  /// Failure message: a transient/server/unexpected write error.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save — please try again.'**
  String get menuWriteProblem;

  /// Snackbar after a successful save.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get menuSavedSnack;

  /// Snackbar after a successful soft-delete.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get menuDeletedSnack;

  /// Subtitle under the menu management page title.
  ///
  /// In en, this message translates to:
  /// **'Organize categories, items, sizes, modifiers, and prices.'**
  String get menuManagementSubtitle;

  /// Placeholder for the menu search field.
  ///
  /// In en, this message translates to:
  /// **'Search the menu'**
  String get menuSearchHint;

  /// Filter chip: show all (active + inactive) entries.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get menuFilterAll;

  /// Filter chip: show only active entries.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get menuFilterActive;

  /// Filter chip: show only inactive entries.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get menuFilterInactive;

  /// Empty-state description for the category list.
  ///
  /// In en, this message translates to:
  /// **'Create your first category to start building the menu.'**
  String get menuEmptyCategoriesBody;

  /// Empty-state description for the item list.
  ///
  /// In en, this message translates to:
  /// **'Add an item to this category to get started.'**
  String get menuEmptyItemsBody;

  /// Error-state description when the menu fails to load.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading the menu.'**
  String get menuLoadErrorBody;

  /// Placeholder caption for the item image preview.
  ///
  /// In en, this message translates to:
  /// **'No image yet'**
  String get menuImageEmptyHint;

  /// Short badge marking a deferred/planned feature.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get menuComingSoonBadge;

  /// Section title for the item's main fields in the editor.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get menuItemDetailsSection;

  /// Empty-state title when a search/filter returns nothing.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get menuNoResults;

  /// Empty-state description when a search/filter returns nothing.
  ///
  /// In en, this message translates to:
  /// **'Try a different search or filter.'**
  String get menuNoResultsBody;

  /// Blocked-state title when the active membership is organization-wide with no restaurant.
  ///
  /// In en, this message translates to:
  /// **'Menu not available for this access'**
  String get menuScopeUnavailableTitle;

  /// Blocked-state body explaining menu management needs a restaurant scope.
  ///
  /// In en, this message translates to:
  /// **'This is organization-wide access with no restaurant selected. Open menu management from a specific restaurant or branch.'**
  String get menuScopeUnavailableBody;

  /// Item editor section title: name, description, category, type, and tags.
  ///
  /// In en, this message translates to:
  /// **'Basic info'**
  String get menuBasicInfoSection;

  /// Item editor section title: the base price (with sizes/variants below it).
  ///
  /// In en, this message translates to:
  /// **'Pricing'**
  String get menuPricingSection;

  /// Item editor section title: prep time and the standing kitchen note.
  ///
  /// In en, this message translates to:
  /// **'Preparation'**
  String get menuPreparationSection;

  /// Item editor collapsed section title: SKU, portion label, and per-piece count/weight.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get menuAdvancedSection;

  /// Subtitle under the Advanced section title explaining the fields are optional and generic across cuisines.
  ///
  /// In en, this message translates to:
  /// **'Optional details — use what fits this item.'**
  String get menuAdvancedSectionHint;

  /// Label for the item type dropdown (food/drink/side/combo/other).
  ///
  /// In en, this message translates to:
  /// **'Item type'**
  String get menuItemTypeLabel;

  /// Item type dropdown entry for no type (stored as null).
  ///
  /// In en, this message translates to:
  /// **'Not specified'**
  String get menuItemTypeUnspecified;

  /// Display label for the item type wire value 'food'.
  ///
  /// In en, this message translates to:
  /// **'Food'**
  String get menuItemTypeFood;

  /// Display label for the item type wire value 'drink'.
  ///
  /// In en, this message translates to:
  /// **'Drink'**
  String get menuItemTypeDrink;

  /// Display label for the item type wire value 'side'.
  ///
  /// In en, this message translates to:
  /// **'Side'**
  String get menuItemTypeSide;

  /// Display label for the item type wire value 'combo'.
  ///
  /// In en, this message translates to:
  /// **'Combo'**
  String get menuItemTypeCombo;

  /// Display label for the item type wire value 'other'.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get menuItemTypeOther;

  /// Label above the fixed tag filter chips (spicy/vegetarian/popular/new).
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get menuTagsLabel;

  /// Display label for the tag wire value 'spicy' (data stays the wire string).
  ///
  /// In en, this message translates to:
  /// **'Spicy'**
  String get menuTagSpicy;

  /// Display label for the tag wire value 'vegetarian'.
  ///
  /// In en, this message translates to:
  /// **'Vegetarian'**
  String get menuTagVegetarian;

  /// Display label for the tag wire value 'popular'.
  ///
  /// In en, this message translates to:
  /// **'Popular'**
  String get menuTagPopular;

  /// Display label for the tag wire value 'new'.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get menuTagNew;

  /// Compact indicator label/tooltip: how many modifier (option) groups an item carries — dashboard item rows and POS cards.
  ///
  /// In en, this message translates to:
  /// **'{count} option groups'**
  String menuModifierGroupCount(int count);

  /// Label for the expected preparation time field (whole minutes; time, never money).
  ///
  /// In en, this message translates to:
  /// **'Prep time (minutes)'**
  String get menuPrepMinutesLabel;

  /// Label for the standing kitchen preparation note field (shown to the KDS).
  ///
  /// In en, this message translates to:
  /// **'Kitchen note'**
  String get menuKitchenNoteLabel;

  /// KITCHEN-PREP-001: sub-heading for the optional kitchen prep components editor (what the chef assembles per one unit of the item). Non-money.
  ///
  /// In en, this message translates to:
  /// **'Kitchen prep'**
  String get menuKitchenPrepSection;

  /// KITCHEN-PREP-001: helper text under the kitchen prep components editor explaining it is optional per-unit assembly info.
  ///
  /// In en, this message translates to:
  /// **'What the chef assembles for one item. Optional.'**
  String get menuKitchenPrepHint;

  /// KITCHEN-PREP-001: label for a prep component's name field (e.g. beef patty, bun).
  ///
  /// In en, this message translates to:
  /// **'Component'**
  String get menuPrepComponentNameLabel;

  /// KITCHEN-PREP-001: label for a prep component's per-unit quantity field (a count, never money).
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get menuPrepComponentQuantityLabel;

  /// KITCHEN-PREP-001: label for a prep component's optional unit field (e.g. pcs, g).
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get menuPrepComponentUnitLabel;

  /// KITCHEN-PREP-001: action to add a new kitchen prep component row.
  ///
  /// In en, this message translates to:
  /// **'Add prep component'**
  String get menuAddPrepComponent;

  /// KITCHEN-PREP-001: tooltip/label for removing a kitchen prep component row.
  ///
  /// In en, this message translates to:
  /// **'Remove component'**
  String get menuRemovePrepComponent;

  /// KITCHEN-MEAT-001: sub-heading for the optional meat-contribution section on a modifier option editor (counts into the KDS whole-order meat total).
  ///
  /// In en, this message translates to:
  /// **'Kitchen meat summary'**
  String get menuKitchenMeatSection;

  /// KITCHEN-MEAT-001: toggle label — whether this option contributes to the KDS meat total.
  ///
  /// In en, this message translates to:
  /// **'Count in meat total'**
  String get menuKitchenMeatEnabledLabel;

  /// KITCHEN-MEAT-001: label for the per-selection meat quantity field (a count, never money).
  ///
  /// In en, this message translates to:
  /// **'Meat quantity'**
  String get menuKitchenMeatQuantityLabel;

  /// KITCHEN-MEAT-001: label for the meat unit field (e.g. patties, g).
  ///
  /// In en, this message translates to:
  /// **'Meat unit'**
  String get menuKitchenMeatUnitLabel;

  /// Label for the internal stock/product code field (back-office only; never sent to devices).
  ///
  /// In en, this message translates to:
  /// **'SKU (internal code)'**
  String get menuSkuLabel;

  /// Label for the free-text portion wording field (e.g. Single, Family) in Advanced.
  ///
  /// In en, this message translates to:
  /// **'Portion label'**
  String get menuPortionFieldLabel;

  /// Generic Advanced field: how many patties/pieces make the item — pizza/cafe owners simply leave it empty.
  ///
  /// In en, this message translates to:
  /// **'Count (patties or pieces)'**
  String get menuPattyCountLabel;

  /// Generic Advanced field: weight per patty/piece in grams (a weight, never money).
  ///
  /// In en, this message translates to:
  /// **'Weight per piece (g)'**
  String get menuPattyWeightLabel;

  /// Modifiers section action opening the modifier template picker (copy-on-attach; creates ordinary per-item rows).
  ///
  /// In en, this message translates to:
  /// **'Add template'**
  String get menuTemplateAddAction;

  /// Title of the modifier template picker dialog.
  ///
  /// In en, this message translates to:
  /// **'Add from template'**
  String get menuTemplatePickerTitle;

  /// Template summary fragment: a required single-choice group (min 1, max 1).
  ///
  /// In en, this message translates to:
  /// **'Required · choose 1'**
  String get menuTemplateRequiredSingle;

  /// Template summary fragment: an optional multi-select group.
  ///
  /// In en, this message translates to:
  /// **'Optional · multi-select'**
  String get menuTemplateOptionalMulti;

  /// Template summary fragment: an optional single-choice group (min 0, max 1).
  ///
  /// In en, this message translates to:
  /// **'Optional · choose up to 1'**
  String get menuTemplateOptionalSingle;

  /// Template summary fragment: how many options applying the template creates.
  ///
  /// In en, this message translates to:
  /// **'{count} options'**
  String menuTemplateOptionCount(int count);

  /// Honest note appended to the failure message when a template apply fails midway: earlier writes are NOT rolled back and remain visible for manual cleanup.
  ///
  /// In en, this message translates to:
  /// **'Stopped — the rows already added stay in the list; edit or delete them below.'**
  String get menuTemplateApplyPartial;

  /// Template group name: optional multi-select burger toppings. Inserted as tenant DATA in the active locale at apply time.
  ///
  /// In en, this message translates to:
  /// **'Burger toppings'**
  String get menuTemplateBurgerToppings;

  /// Burger toppings template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Lettuce'**
  String get menuTemplateOptLettuce;

  /// Burger toppings template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Tomato'**
  String get menuTemplateOptTomato;

  /// Burger toppings template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Onion'**
  String get menuTemplateOptOnion;

  /// Burger toppings template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Pickles'**
  String get menuTemplateOptPickles;

  /// Burger toppings template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Cheese'**
  String get menuTemplateOptCheese;

  /// Template group name: required single-choice meat doneness. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Doneness'**
  String get menuTemplateDoneness;

  /// Doneness template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Rare'**
  String get menuTemplateOptRare;

  /// Doneness template option (free): medium doneness. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get menuTemplateOptMediumDoneness;

  /// Doneness template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Well done'**
  String get menuTemplateOptWellDone;

  /// Template group name: required single-choice number of patties. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Patty count'**
  String get menuTemplatePattyCount;

  /// Patty count template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Single patty'**
  String get menuTemplateOptSinglePatty;

  /// Patty count template option (+900 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Double patty'**
  String get menuTemplateOptDoublePatty;

  /// Patty count template option (+1800 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Triple patty'**
  String get menuTemplateOptTriplePatty;

  /// Template group name: optional multi-select paid extras. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Extras'**
  String get menuTemplateExtras;

  /// Extras template option (+300 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Extra cheese'**
  String get menuTemplateOptExtraCheese;

  /// Extras template option (+900 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Extra patty'**
  String get menuTemplateOptExtraPatty;

  /// Extras template option (+700 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Fries'**
  String get menuTemplateOptFries;

  /// Extras template option (+500 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Drink'**
  String get menuTemplateOptDrink;

  /// Template group name: required single-choice drink size. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Drink size'**
  String get menuTemplateDrinkSize;

  /// Drink size template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get menuTemplateOptSmall;

  /// Drink size template option (+200 minor units): medium size. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get menuTemplateOptMediumSize;

  /// Drink size template option (+400 minor units). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get menuTemplateOptLarge;

  /// Template group name: optional single-choice spiciness level. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Spiciness'**
  String get menuTemplateSpiciness;

  /// Spiciness template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Mild'**
  String get menuTemplateOptMild;

  /// Spiciness template option (free): medium heat. Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get menuTemplateOptMediumSpicy;

  /// Spiciness template option (free). Inserted as tenant data in the active locale.
  ///
  /// In en, this message translates to:
  /// **'Hot'**
  String get menuTemplateOptHot;

  /// No description provided for @dashboardNavSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get dashboardNavSettings;

  /// No description provided for @dashboardNavUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get dashboardNavUsers;

  /// No description provided for @dashboardNavDevices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get dashboardNavDevices;

  /// No description provided for @adminDemoBanner.
  ///
  /// In en, this message translates to:
  /// **'Demo data — actions follow the RF-112 backend contracts but run against an in-memory store on this device; nothing is saved to a server yet.'**
  String get adminDemoBanner;

  /// No description provided for @adminPermissionDeniedTitle.
  ///
  /// In en, this message translates to:
  /// **'You don’t have permission'**
  String get adminPermissionDeniedTitle;

  /// No description provided for @adminPermissionDeniedBody.
  ///
  /// In en, this message translates to:
  /// **'Your role can’t perform this action at this scope. The role-rank guard limits management to higher roles.'**
  String get adminPermissionDeniedBody;

  /// No description provided for @adminStateErrorTitle.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get adminStateErrorTitle;

  /// No description provided for @adminStateErrorBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn’t load this. Please try again.'**
  String get adminStateErrorBody;

  /// No description provided for @adminRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get adminRetry;

  /// No description provided for @adminConflictMessage.
  ///
  /// In en, this message translates to:
  /// **'That action isn’t allowed in the current state.'**
  String get adminConflictMessage;

  /// No description provided for @adminActionProblem.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t complete the action — please try again.'**
  String get adminActionProblem;

  /// No description provided for @adminErrCurrency.
  ///
  /// In en, this message translates to:
  /// **'Use a 3-letter code (e.g. ILS)'**
  String get adminErrCurrency;

  /// No description provided for @adminErrCountry.
  ///
  /// In en, this message translates to:
  /// **'Use a 2-letter code (e.g. US)'**
  String get adminErrCountry;

  /// No description provided for @adminErrName.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get adminErrName;

  /// No description provided for @adminErrEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get adminErrEmail;

  /// No description provided for @adminErrStatus.
  ///
  /// In en, this message translates to:
  /// **'Choose a valid status'**
  String get adminErrStatus;

  /// No description provided for @adminErrRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get adminErrRequired;

  /// No description provided for @adminCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get adminCopy;

  /// No description provided for @adminShownOnce.
  ///
  /// In en, this message translates to:
  /// **'Shown once — copy it now. You won’t be able to see it again.'**
  String get adminShownOnce;

  /// No description provided for @adminDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get adminDone;

  /// No description provided for @adminSavedSnack.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get adminSavedSnack;

  /// No description provided for @adminDevStatusNone.
  ///
  /// In en, this message translates to:
  /// **'Not paired'**
  String get adminDevStatusNone;

  /// No description provided for @adminDevStatusCodeIssued.
  ///
  /// In en, this message translates to:
  /// **'Code issued'**
  String get adminDevStatusCodeIssued;

  /// No description provided for @adminDevStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending approval'**
  String get adminDevStatusPending;

  /// No description provided for @adminDevStatusPaired.
  ///
  /// In en, this message translates to:
  /// **'Paired'**
  String get adminDevStatusPaired;

  /// No description provided for @adminDevStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminDevStatusActive;

  /// No description provided for @adminDevStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get adminDevStatusSuspended;

  /// No description provided for @adminDevStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get adminDevStatusRevoked;

  /// No description provided for @adminDevStatusCodeExpired.
  ///
  /// In en, this message translates to:
  /// **'Code expired'**
  String get adminDevStatusCodeExpired;

  /// No description provided for @adminDevStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get adminDevStatusRejected;

  /// No description provided for @adminSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get adminSettingsTitle;

  /// No description provided for @adminSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Organization, restaurant, and branch settings for this scope.'**
  String get adminSettingsSubtitle;

  /// No description provided for @adminSettingsReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Your role can view these settings but can’t edit them.'**
  String get adminSettingsReadOnly;

  /// No description provided for @adminSectionOrg.
  ///
  /// In en, this message translates to:
  /// **'Organization'**
  String get adminSectionOrg;

  /// No description provided for @adminSectionRestaurant.
  ///
  /// In en, this message translates to:
  /// **'Restaurant'**
  String get adminSectionRestaurant;

  /// No description provided for @adminSectionBranch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get adminSectionBranch;

  /// No description provided for @adminFieldDefaultCurrency.
  ///
  /// In en, this message translates to:
  /// **'Default currency'**
  String get adminFieldDefaultCurrency;

  /// No description provided for @adminFieldCountryCode.
  ///
  /// In en, this message translates to:
  /// **'Country code'**
  String get adminFieldCountryCode;

  /// No description provided for @adminFieldStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get adminFieldStatus;

  /// No description provided for @adminFieldName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get adminFieldName;

  /// No description provided for @adminFieldCurrencyOverride.
  ///
  /// In en, this message translates to:
  /// **'Currency override'**
  String get adminFieldCurrencyOverride;

  /// No description provided for @adminFieldTimezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get adminFieldTimezone;

  /// No description provided for @adminFieldAddress.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get adminFieldAddress;

  /// No description provided for @adminFieldReceiptPrefix.
  ///
  /// In en, this message translates to:
  /// **'Receipt prefix'**
  String get adminFieldReceiptPrefix;

  /// No description provided for @adminStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get adminStatusActive;

  /// No description provided for @adminStatusSuspended.
  ///
  /// In en, this message translates to:
  /// **'Suspended'**
  String get adminStatusSuspended;

  /// No description provided for @adminOptional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get adminOptional;

  /// No description provided for @adminSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get adminSave;

  /// No description provided for @adminCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get adminCancel;

  /// No description provided for @adminUsersTitle.
  ///
  /// In en, this message translates to:
  /// **'Users & Roles'**
  String get adminUsersTitle;

  /// No description provided for @adminUsersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Manage who can access this organization and what they can do.'**
  String get adminUsersSubtitle;

  /// No description provided for @adminGrantUser.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get adminGrantUser;

  /// No description provided for @adminGrantDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Grant access'**
  String get adminGrantDialogTitle;

  /// No description provided for @adminGrant.
  ///
  /// In en, this message translates to:
  /// **'Grant'**
  String get adminGrant;

  /// No description provided for @adminChangeRole.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get adminChangeRole;

  /// No description provided for @adminChangeRoleTitle.
  ///
  /// In en, this message translates to:
  /// **'Change role'**
  String get adminChangeRoleTitle;

  /// No description provided for @adminUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get adminUpdate;

  /// No description provided for @adminRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get adminRevoke;

  /// No description provided for @adminComingSoon.
  ///
  /// In en, this message translates to:
  /// **'coming soon'**
  String get adminComingSoon;

  /// No description provided for @adminRoleGuardNote.
  ///
  /// In en, this message translates to:
  /// **'You can assign roles below your own — the role-rank guard prevents granting your own role or higher.'**
  String get adminRoleGuardNote;

  /// No description provided for @adminSelf.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get adminSelf;

  /// No description provided for @adminStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get adminStatusRevoked;

  /// No description provided for @adminFieldDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get adminFieldDisplayName;

  /// No description provided for @adminFieldEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get adminFieldEmail;

  /// No description provided for @adminFieldRole.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get adminFieldRole;

  /// No description provided for @adminUsersEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No members yet'**
  String get adminUsersEmptyTitle;

  /// No description provided for @adminUsersEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Grant access to add the first member to this organization.'**
  String get adminUsersEmptyBody;

  /// No description provided for @adminUserGranted.
  ///
  /// In en, this message translates to:
  /// **'Access granted'**
  String get adminUserGranted;

  /// No description provided for @adminRoleUpdated.
  ///
  /// In en, this message translates to:
  /// **'Role updated'**
  String get adminRoleUpdated;

  /// No description provided for @adminRevokeMemberTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke access?'**
  String get adminRevokeMemberTitle;

  /// No description provided for @adminRevokeMemberBody.
  ///
  /// In en, this message translates to:
  /// **'This removes the member’s access to this organization and ends any PIN sign-in. You can’t undo this here.'**
  String get adminRevokeMemberBody;

  /// No description provided for @adminMemberRevoked.
  ///
  /// In en, this message translates to:
  /// **'Access revoked'**
  String get adminMemberRevoked;

  /// No description provided for @adminDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get adminDevicesTitle;

  /// No description provided for @adminDevicesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Provision and pair POS and kitchen-display devices for this branch.'**
  String get adminDevicesSubtitle;

  /// No description provided for @adminCreateDevice.
  ///
  /// In en, this message translates to:
  /// **'Add device'**
  String get adminCreateDevice;

  /// No description provided for @adminCreateDeviceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add device'**
  String get adminCreateDeviceTitle;

  /// No description provided for @adminCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get adminCreate;

  /// No description provided for @adminFieldDeviceLabel.
  ///
  /// In en, this message translates to:
  /// **'Device label'**
  String get adminFieldDeviceLabel;

  /// No description provided for @adminFieldDeviceType.
  ///
  /// In en, this message translates to:
  /// **'Device type'**
  String get adminFieldDeviceType;

  /// No description provided for @adminDeviceTypePos.
  ///
  /// In en, this message translates to:
  /// **'POS'**
  String get adminDeviceTypePos;

  /// No description provided for @adminDeviceTypeKds.
  ///
  /// In en, this message translates to:
  /// **'Kitchen display'**
  String get adminDeviceTypeKds;

  /// No description provided for @adminLifecycleNote.
  ///
  /// In en, this message translates to:
  /// **'Lifecycle: issue a code → the device redeems it (pending) → approve (paired) → activate (active) → start a session. Approval and activation are separate steps; a device can’t jump from pending to active.'**
  String get adminLifecycleNote;

  /// No description provided for @adminIssueCode.
  ///
  /// In en, this message translates to:
  /// **'Issue code'**
  String get adminIssueCode;

  /// No description provided for @adminRedeem.
  ///
  /// In en, this message translates to:
  /// **'Redeem code'**
  String get adminRedeem;

  /// No description provided for @adminApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get adminApprove;

  /// No description provided for @adminActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get adminActivate;

  /// No description provided for @adminStartSession.
  ///
  /// In en, this message translates to:
  /// **'Start session'**
  String get adminStartSession;

  /// No description provided for @adminDevicesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No devices yet'**
  String get adminDevicesEmptyTitle;

  /// No description provided for @adminDevicesEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Add a device to begin the enrollment and pairing flow.'**
  String get adminDevicesEmptyBody;

  /// No description provided for @adminCodeIssuedTitle.
  ///
  /// In en, this message translates to:
  /// **'Enrollment code'**
  String get adminCodeIssuedTitle;

  /// No description provided for @adminCodeIssuedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enter this code on the device to begin pairing.'**
  String get adminCodeIssuedSubtitle;

  /// No description provided for @adminCodeExpiresNote.
  ///
  /// In en, this message translates to:
  /// **'This code expires shortly and can be redeemed once.'**
  String get adminCodeExpiresNote;

  /// Title of the Dashboard QR pairing panel shown after issuing a device enrollment code (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'Pair this device'**
  String get pairingPanelTitle;

  /// How to use the pairing QR/link on the device (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'Open this link on the tablet, or scan the QR code, then tap Pair.'**
  String get pairingPanelInstructions;

  /// Accessibility/label caption for the pairing QR code (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'Scan to open on the tablet'**
  String get pairingPanelScanLabel;

  /// Label for the copyable hosted pairing link (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'Pairing link'**
  String get pairingPanelLinkLabel;

  /// Tooltip/button to copy the pairing link (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get pairingPanelCopyLink;

  /// Label for the manual pairing code shown as a fallback (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingPanelCodeLabel;

  /// Shown when the device type has no pos/kds app route, so only the manual code is offered (LIVE-OPS-001).
  ///
  /// In en, this message translates to:
  /// **'This device type has no app link — enter the code on the tablet manually.'**
  String get pairingPanelManualOnly;

  /// No description provided for @adminTokenStartedTitle.
  ///
  /// In en, this message translates to:
  /// **'Device session started'**
  String get adminTokenStartedTitle;

  /// No description provided for @adminTokenStartedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Load this session token onto the device to authenticate it.'**
  String get adminTokenStartedSubtitle;

  /// No description provided for @adminSessionOpen.
  ///
  /// In en, this message translates to:
  /// **'Session active'**
  String get adminSessionOpen;

  /// No description provided for @adminDeviceCreated.
  ///
  /// In en, this message translates to:
  /// **'Device added'**
  String get adminDeviceCreated;

  /// No description provided for @adminDeviceUpdated.
  ///
  /// In en, this message translates to:
  /// **'Device updated'**
  String get adminDeviceUpdated;

  /// Heading on the dashboard sign-in / create-account screen (RF-151).
  ///
  /// In en, this message translates to:
  /// **'Welcome to RestoFlow'**
  String get authWelcomeTitle;

  /// Muted tagline under the brand mark on login/pairing screens.
  ///
  /// In en, this message translates to:
  /// **'Restaurant operating system'**
  String get authBrandTagline;

  /// Segmented control option / action for signing in (RF-151).
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInTab;

  /// Segmented control option / action for creating an account (RF-151).
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccountTab;

  /// Email text-field label on the sign-in / sign-up form.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmailLabel;

  /// Password text-field label on the sign-in / sign-up form.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPasswordLabel;

  /// Primary button label that submits the sign-in form.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignInAction;

  /// Validation message when the email field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get authEmailRequired;

  /// Validation message when the password field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get authPasswordRequired;

  /// Validation message when the sign-up password is too short.
  ///
  /// In en, this message translates to:
  /// **'Use at least 6 characters'**
  String get authPasswordTooShort;

  /// Safe sign-in error shown for rejected credentials.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password'**
  String get authInvalidCredentials;

  /// Safe generic error shown when account creation fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create your account. Please try again.'**
  String get authSignUpFailed;

  /// Safe error shown when the backend is unreachable.
  ///
  /// In en, this message translates to:
  /// **'Can\'t reach the server. Check your connection.'**
  String get authNetworkError;

  /// Honest state shown when sign-up requires email confirmation before a session.
  ///
  /// In en, this message translates to:
  /// **'Check your email to confirm your account, then sign in.'**
  String get authEmailConfirmationSent;

  /// Heading on the restaurant onboarding screen (RF-151).
  ///
  /// In en, this message translates to:
  /// **'Set up your restaurant'**
  String get onboardingTitle;

  /// Intro text on the restaurant onboarding screen.
  ///
  /// In en, this message translates to:
  /// **'Create your restaurant to start using RestoFlow.'**
  String get onboardingIntro;

  /// Restaurant-name field label on the onboarding form.
  ///
  /// In en, this message translates to:
  /// **'Restaurant name'**
  String get onboardingRestaurantNameLabel;

  /// Optional branch-name field label on the onboarding form.
  ///
  /// In en, this message translates to:
  /// **'Branch name (optional)'**
  String get onboardingBranchNameLabel;

  /// Validation message when the restaurant name is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter a restaurant name'**
  String get onboardingRestaurantNameRequired;

  /// Primary button that submits the onboarding form (calls create_organization).
  ///
  /// In en, this message translates to:
  /// **'Create restaurant'**
  String get onboardingCreateAction;

  /// Safe error shown when create_organization fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create your restaurant. Please try again.'**
  String get onboardingFailed;

  /// Heading on the POS/KDS device pairing screen (RF-153).
  ///
  /// In en, this message translates to:
  /// **'Pair this device'**
  String get pairingTitle;

  /// Intro text on the device pairing screen.
  ///
  /// In en, this message translates to:
  /// **'Enter the pairing code created in the restaurant dashboard to connect this device.'**
  String get pairingIntro;

  /// Helper line on the pairing screen pointing to where codes are issued.
  ///
  /// In en, this message translates to:
  /// **'Get a pairing code from the Dashboard → Devices tab.'**
  String get pairingWhereCode;

  /// Pairing-code text-field label.
  ///
  /// In en, this message translates to:
  /// **'Pairing code'**
  String get pairingCodeLabel;

  /// Validation message when the pairing code is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter the pairing code'**
  String get pairingCodeRequired;

  /// Primary button that submits the pairing code.
  ///
  /// In en, this message translates to:
  /// **'Pair device'**
  String get pairingPairAction;

  /// Safe error when the pairing code is rejected.
  ///
  /// In en, this message translates to:
  /// **'That pairing code wasn\'t accepted. Check it and try again.'**
  String get pairingInvalidCode;

  /// Safe error when the pairing code has expired.
  ///
  /// In en, this message translates to:
  /// **'This pairing code has expired. Ask for a new one.'**
  String get pairingExpired;

  /// Safe error when the code belongs to another org/branch.
  ///
  /// In en, this message translates to:
  /// **'This code is for a different restaurant or branch.'**
  String get pairingWrongScope;

  /// Safe generic error when pairing fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t pair this device. Please try again.'**
  String get pairingFailed;

  /// Safe rate-limit error after too many invalid pairing attempts (RF-118); reveals only that the caller is throttled.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. Please wait a few minutes and try again.'**
  String get pairingLocked;

  /// Dashboard navigation label for the printers surface.
  ///
  /// In en, this message translates to:
  /// **'Printers'**
  String get dashboardNavPrinters;

  /// Dashboard navigation label for the staff/PIN surface.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get dashboardNavStaff;

  /// Dashboard navigation label for the dining-tables surface.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get dashboardNavTables;

  /// Header mode pill when the app runs on in-memory demo data.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get dashboardModeDemo;

  /// Header mode pill when the app runs against the real backend.
  ///
  /// In en, this message translates to:
  /// **'Real'**
  String get dashboardModeReal;

  /// DESIGN-002: user-facing header data-source pill for demo mode (replaces the developer 'Demo' label).
  ///
  /// In en, this message translates to:
  /// **'Demo data'**
  String get dashboardModeDemoData;

  /// DESIGN-002: user-facing header data-source pill for real mode (replaces the developer 'Real' label).
  ///
  /// In en, this message translates to:
  /// **'Live data'**
  String get dashboardModeLiveData;

  /// DESIGN-002: title of the Overview sales-by-hour chart card.
  ///
  /// In en, this message translates to:
  /// **'Sales by hour'**
  String get dashboardSalesByHour;

  /// DESIGN-002: KPI trend delta suffix (the up/down arrow is added by the card). percent is the absolute integer percentage change vs the prior period.
  ///
  /// In en, this message translates to:
  /// **'{percent}% vs yesterday'**
  String dashboardDeltaVsYesterday(int percent);

  /// RF-REPORT-004 reporting-range chip: today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get dashboardRangeToday;

  /// RF-REPORT-004 reporting-range chip: yesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get dashboardRangeYesterday;

  /// RF-REPORT-004 reporting-range chip: the rolling last 7 days (incl. today).
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get dashboardRangeLast7;

  /// RF-REPORT-004 reporting-range chip: the rolling last 30 days (incl. today).
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get dashboardRangeLast30;

  /// RF-REPORT-004 honest state shown when the owner_report_range RPC isn't deployed yet and the chosen range isn't today.
  ///
  /// In en, this message translates to:
  /// **'This range isn\'t available in live reports yet — try Today, or check back after the reporting update ships.'**
  String get dashboardRangeUnavailable;

  /// RF-REPORT-004 KPI trend delta suffix for the Yesterday range (vs the day before). percent is the absolute integer percentage change.
  ///
  /// In en, this message translates to:
  /// **'{percent}% vs day before'**
  String dashboardDeltaVsDayBefore(int percent);

  /// RF-REPORT-004 KPI trend delta suffix for the Last 7 days range. percent is the absolute integer percentage change.
  ///
  /// In en, this message translates to:
  /// **'{percent}% vs previous 7 days'**
  String dashboardDeltaVsPrev7(int percent);

  /// RF-REPORT-004 KPI trend delta suffix for the Last 30 days range. percent is the absolute integer percentage change.
  ///
  /// In en, this message translates to:
  /// **'{percent}% vs previous 30 days'**
  String dashboardDeltaVsPrev30(int percent);

  /// RF-REPORT-004 Shift & cash pill: count of shifts closed in the selected (non-today) range.
  ///
  /// In en, this message translates to:
  /// **'{count} closed'**
  String dashboardShiftClosedInRange(int count);

  /// RF-REPORT-004 Shift & cash calm empty state for a non-today range with no closed shifts.
  ///
  /// In en, this message translates to:
  /// **'No closed shifts in this range.'**
  String get dashboardShiftNoneRange;

  /// RF-REPORT-004 Shift & cash: who opened the shift.
  ///
  /// In en, this message translates to:
  /// **'Opened by {name}'**
  String dashboardShiftOpenedBy(String name);

  /// RF-REPORT-004 Shift & cash per-shift detail: total collected (all tenders) in the shift.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get dashboardShiftCollected;

  /// RF-REPORT-004 Shift & cash per-shift detail label: shift duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get dashboardShiftDurationLabel;

  /// RF-REPORT-004 shift duration formatted as hours and minutes.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}m'**
  String dashboardShiftDurationValue(int hours, int minutes);

  /// RF-REPORT-004 collapsible header for the remaining closed shifts in the range (beyond the last one shown in detail).
  ///
  /// In en, this message translates to:
  /// **'Recent shifts ({count})'**
  String dashboardShiftRecentTitle(int count);

  /// Honest real-mode Users tab state: no member read API exists yet, so no list is shown.
  ///
  /// In en, this message translates to:
  /// **'User management not connected yet'**
  String get dashboardUsersNotConnectedTitle;

  /// Body of the honest real-mode Users tab state.
  ///
  /// In en, this message translates to:
  /// **'This build cannot list or invite real members yet — there is no member directory API. Instead of showing sample people, this page stays empty. Demo mode previews how the flow will work.'**
  String get dashboardUsersNotConnectedBody;

  /// Title of the real-mode settings card showing the signed-in workspace values.
  ///
  /// In en, this message translates to:
  /// **'Workspace'**
  String get dashboardSettingsWorkspace;

  /// Honest notice on the real-mode Settings tab: values are real, saving is not wired.
  ///
  /// In en, this message translates to:
  /// **'These are your real workspace values. Editing settings is not connected in this build yet, so there is nothing to save here.'**
  String get dashboardSettingsRealNotice;

  /// RF-116: title of the owner-only editable settings card on the real Settings tab.
  ///
  /// In en, this message translates to:
  /// **'Edit branch details'**
  String get dashboardSettingsEditableTitle;

  /// RF-116: label for the editable branch display-name field.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get dashboardSettingsBranchNameLabel;

  /// RF-116: label for the editable restaurant display-name field.
  ///
  /// In en, this message translates to:
  /// **'Restaurant name'**
  String get dashboardSettingsRestaurantNameLabel;

  /// RF-116: hint under the receipt-prefix field; blank means leave unchanged.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the current prefix'**
  String get dashboardSettingsReceiptPrefixHint;

  /// RF-REPORT-004: label for the branch timezone picker in Settings.
  ///
  /// In en, this message translates to:
  /// **'Branch timezone'**
  String get dashboardSettingsTimezoneLabel;

  /// RF-REPORT-004: hint under the branch timezone picker explaining its effect on reporting.
  ///
  /// In en, this message translates to:
  /// **'Used for reporting (sales-by-hour, daily totals). Israel is Asia/Jerusalem.'**
  String get dashboardSettingsTimezoneHint;

  /// RF-REPORT-004: the branch timezone picker option that leaves the current zone unchanged.
  ///
  /// In en, this message translates to:
  /// **'Leave unchanged'**
  String get dashboardSettingsTimezoneKeep;

  /// RF-116: note that currency stays locked to ILS and is not editable.
  ///
  /// In en, this message translates to:
  /// **'Currency is fixed to ₪ (ILS) for the pilot and can’t be changed here.'**
  String get dashboardSettingsCurrencyLocked;

  /// RF-113: Settings section for the per-branch POS shift-close policy.
  ///
  /// In en, this message translates to:
  /// **'Shift reconciliation (POS)'**
  String get dashboardShiftCloseSectionTitle;

  /// RF-113: label for the toggle that shows/hides the POS shift-close workflow.
  ///
  /// In en, this message translates to:
  /// **'Show “Close shift & count cash” on the POS'**
  String get dashboardShiftCloseToggleLabel;

  /// RF-113: help text under the shift-close toggle.
  ///
  /// In en, this message translates to:
  /// **'When on, cashiers can close their shift and count the cash drawer on the POS for this branch. Turning it off hides that workflow; payments are unaffected.'**
  String get dashboardShiftCloseToggleHelp;

  /// RF-113: note shown to non-owners; the toggle is read-only for them.
  ///
  /// In en, this message translates to:
  /// **'Only an owner can change this setting.'**
  String get dashboardShiftCloseOwnerOnly;

  /// RF-113: shown when the policy read fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load this setting right now. Try again later.'**
  String get dashboardShiftCloseUnavailable;

  /// RF-113: confirmation snackbar after a successful policy save.
  ///
  /// In en, this message translates to:
  /// **'Setting saved.'**
  String get dashboardShiftCloseSaved;

  /// RF-113: snackbar when the server denies the policy write.
  ///
  /// In en, this message translates to:
  /// **'You don’t have permission to change this setting.'**
  String get dashboardShiftCloseDenied;

  /// RF-113: snackbar when the policy write fails for a transient reason.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t save the setting. Please try again.'**
  String get dashboardShiftCloseSaveFailed;

  /// Title of the real-mode setup center on the dashboard overview.
  ///
  /// In en, this message translates to:
  /// **'Setup'**
  String get setupTitle;

  /// Dashboard '1c' readiness strip headline when the branch is fully set up.
  ///
  /// In en, this message translates to:
  /// **'Branch ready for service'**
  String get setupReadyHeadline;

  /// Subtitle of the setup center.
  ///
  /// In en, this message translates to:
  /// **'Get this branch ready for service'**
  String get setupSubtitle;

  /// Setup metric label: paired devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get setupDevices;

  /// Caption under the devices setup metric.
  ///
  /// In en, this message translates to:
  /// **'active / total'**
  String get setupDevicesCaption;

  /// Setup metric label: configured printers.
  ///
  /// In en, this message translates to:
  /// **'Printers'**
  String get setupPrinters;

  /// Caption under the printers setup metric.
  ///
  /// In en, this message translates to:
  /// **'enabled / total'**
  String get setupPrintersCaption;

  /// Setup metric label: staff with a sign-in PIN.
  ///
  /// In en, this message translates to:
  /// **'Staff PINs'**
  String get setupStaffPin;

  /// Caption under the staff setup metric.
  ///
  /// In en, this message translates to:
  /// **'with PIN / total'**
  String get setupStaffCaption;

  /// Shown when a setup metric could not be loaded (never a fake zero).
  ///
  /// In en, this message translates to:
  /// **'n/a'**
  String get setupMetricUnavailable;

  /// Setup next-step when the branch has no devices.
  ///
  /// In en, this message translates to:
  /// **'No devices yet — create a POS or KDS device and issue a pairing code.'**
  String get setupNoDevices;

  /// Setup next-step when devices exist but none is actively paired.
  ///
  /// In en, this message translates to:
  /// **'No device is paired yet — issue a code in Devices and redeem it on the device\'s pairing screen.'**
  String get setupNoActiveDevice;

  /// Setup next-step when no printers are configured.
  ///
  /// In en, this message translates to:
  /// **'No printers configured yet — add a receipt or kitchen printer.'**
  String get setupNoPrinters;

  /// Setup warning when no active staff member has a PIN.
  ///
  /// In en, this message translates to:
  /// **'No staff member has a PIN yet — POS/KDS sign-in (and the live order flow) needs at least one.'**
  String get setupNoStaffPin;

  /// Setup success banner when the readiness checks pass.
  ///
  /// In en, this message translates to:
  /// **'This branch is ready: paired device and staff PIN in place.'**
  String get setupReady;

  /// Setup-center metric label for the menu-items count.
  ///
  /// In en, this message translates to:
  /// **'Menu items'**
  String get setupMenu;

  /// Caption under the menu-items metric (active items vs all items).
  ///
  /// In en, this message translates to:
  /// **'active / total'**
  String get setupMenuCaption;

  /// Setup checklist warning when the branch has no active menu items.
  ///
  /// In en, this message translates to:
  /// **'No menu items yet — the POS has nothing to sell.'**
  String get setupNoMenu;

  /// Checklist action that jumps to the Menu tab.
  ///
  /// In en, this message translates to:
  /// **'Add your first menu item'**
  String get setupAddMenuItem;

  /// Setup checklist step when no POS-type device exists.
  ///
  /// In en, this message translates to:
  /// **'No POS device yet — the counter needs one to take orders.'**
  String get setupNoPosDevice;

  /// Checklist action that jumps to the Devices tab to create a POS device.
  ///
  /// In en, this message translates to:
  /// **'Create POS device'**
  String get setupCreatePos;

  /// Setup checklist step when no KDS-type device exists.
  ///
  /// In en, this message translates to:
  /// **'No kitchen display yet — the kitchen won\'t see incoming orders.'**
  String get setupNoKdsDevice;

  /// Checklist action that jumps to the Devices tab to create a KDS device.
  ///
  /// In en, this message translates to:
  /// **'Create kitchen display'**
  String get setupCreateKds;

  /// Explains HOW to pair: shown under the no-device-paired warning.
  ///
  /// In en, this message translates to:
  /// **'Open the POS or KDS app on that device and enter the pairing code from the Devices tab.'**
  String get setupPairingHint;

  /// Checklist action that jumps to the Printers tab.
  ///
  /// In en, this message translates to:
  /// **'Add printer'**
  String get setupAddPrinter;

  /// Checklist action that jumps to the Staff tab.
  ///
  /// In en, this message translates to:
  /// **'Create staff PIN'**
  String get setupCreatePin;

  /// Printers page title.
  ///
  /// In en, this message translates to:
  /// **'Printers'**
  String get printersTitle;

  /// Printers page subtitle.
  ///
  /// In en, this message translates to:
  /// **'Receipt and kitchen printers for this branch'**
  String get printersSubtitle;

  /// Button that opens the add-printer dialog.
  ///
  /// In en, this message translates to:
  /// **'Add printer'**
  String get printersAdd;

  /// Empty-state title on the printers page.
  ///
  /// In en, this message translates to:
  /// **'No printers yet'**
  String get printersEmptyTitle;

  /// Empty-state body on the printers page.
  ///
  /// In en, this message translates to:
  /// **'Add a receipt or kitchen printer to prepare this branch for printing.'**
  String get printersEmptyBody;

  /// Title of the honest transport-status notice.
  ///
  /// In en, this message translates to:
  /// **'Configuration only — no print transport yet'**
  String get printersTransportNoticeTitle;

  /// Body of the honest transport-status notice.
  ///
  /// In en, this message translates to:
  /// **'Printer settings are saved and validated on the backend, but this build does not send anything to physical printers. The print engine ships network-first; Bluetooth and USB transports are not installed yet. No fake print success is ever shown.'**
  String get printersTransportNotice;

  /// Printer role: customer receipts.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get printersRoleReceipt;

  /// Printer role: kitchen tickets.
  ///
  /// In en, this message translates to:
  /// **'Kitchen'**
  String get printersRoleKitchen;

  /// Connection type label: network.
  ///
  /// In en, this message translates to:
  /// **'Network (Wi-Fi/LAN)'**
  String get printersConnNetwork;

  /// Connection type label: Bluetooth.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get printersConnBluetooth;

  /// Connection type label: USB.
  ///
  /// In en, this message translates to:
  /// **'USB'**
  String get printersConnUsb;

  /// Honest note on Bluetooth/USB printers: config is saved, transport missing.
  ///
  /// In en, this message translates to:
  /// **'Configuration only — this transport is not installed yet.'**
  String get printersConnConfigOnly;

  /// Collapsed section in the printer dialog holding technical fields (port, device identifiers).
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get printersAdvanced;

  /// Honest note shown in the printer dialog for EVERY connection type: saving config never prints.
  ///
  /// In en, this message translates to:
  /// **'This build saves the printer configuration only — nothing is printed yet.'**
  String get printersDialogSavesConfigOnly;

  /// Honest note when Bluetooth is selected in the printer dialog on web: no scan, config only.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth discovery is not available in the web app yet. Save configuration only.'**
  String get printersConnBluetoothWeb;

  /// Honest note when USB is selected in the printer dialog: needs the native adapter, config only.
  ///
  /// In en, this message translates to:
  /// **'USB printing requires the desktop/native printer adapter. Save configuration only.'**
  String get printersConnUsbAdapter;

  /// Printer form field: display name.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get printersFieldName;

  /// Printer form field: role.
  ///
  /// In en, this message translates to:
  /// **'Printer role'**
  String get printersFieldRole;

  /// Printer form field: connection type.
  ///
  /// In en, this message translates to:
  /// **'Connection type'**
  String get printersFieldConnection;

  /// Printer form field: paper width.
  ///
  /// In en, this message translates to:
  /// **'Paper width'**
  String get printersFieldPaper;

  /// Printer form field: network host.
  ///
  /// In en, this message translates to:
  /// **'Host / IP address'**
  String get printersFieldHost;

  /// Printer form field: network port.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get printersFieldPort;

  /// Printer form field: Bluetooth identifier (configuration only).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth device id / name'**
  String get printersFieldBluetoothId;

  /// Printer form field: USB identifier (configuration only).
  ///
  /// In en, this message translates to:
  /// **'USB path / identifier'**
  String get printersFieldUsbPath;

  /// Printer state pill/switch: enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get printersEnabled;

  /// Printer state pill: disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get printersDisabled;

  /// Edit-printer action.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get printersEdit;

  /// Action that opens the route-to-station dialog.
  ///
  /// In en, this message translates to:
  /// **'Route to station'**
  String get printersRoute;

  /// Route dialog title.
  ///
  /// In en, this message translates to:
  /// **'Route printer to a station'**
  String get printersRouteTitle;

  /// Route dialog station dropdown label.
  ///
  /// In en, this message translates to:
  /// **'Station'**
  String get printersRouteStation;

  /// Route dialog enabled switch label.
  ///
  /// In en, this message translates to:
  /// **'Route enabled'**
  String get printersRouteActive;

  /// Prefix before the list of stations a printer routes to.
  ///
  /// In en, this message translates to:
  /// **'Routes to'**
  String get printersRoutedTo;

  /// Delete-printer action + confirm button.
  ///
  /// In en, this message translates to:
  /// **'Remove printer'**
  String get printersDelete;

  /// Delete-printer confirmation body.
  ///
  /// In en, this message translates to:
  /// **'Remove this printer? Its station routes are removed too.'**
  String get printersDeleteConfirm;

  /// Snackbar after a successful printer save/route/removal.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get printersSaved;

  /// Shown when routing is attempted with no stations.
  ///
  /// In en, this message translates to:
  /// **'No stations found for this branch yet.'**
  String get printersNoStations;

  /// Validation message for a missing network host.
  ///
  /// In en, this message translates to:
  /// **'Enter the printer host / IP'**
  String get printersErrHost;

  /// Validation message for an invalid network port.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid port (1–65535)'**
  String get printersErrPort;

  /// Printer dialog save button.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get printersSave;

  /// Printer wizard step 1 title: choose the printer's purpose (receipts vs kitchen tickets).
  ///
  /// In en, this message translates to:
  /// **'What do you want to print?'**
  String get printersWizardStepPurpose;

  /// Hint under the receipt-purpose choice tile in the printer wizard.
  ///
  /// In en, this message translates to:
  /// **'Bills for customers at the counter.'**
  String get printersPurposeReceiptsHint;

  /// Hint under the kitchen-purpose choice tile in the printer wizard.
  ///
  /// In en, this message translates to:
  /// **'Tickets for the kitchen staff.'**
  String get printersPurposeKitchenHint;

  /// Printer wizard step 2 title: choose the connection type.
  ///
  /// In en, this message translates to:
  /// **'How is the printer connected?'**
  String get printersWizardStepConnection;

  /// Honest hint under the selected network tile in the printer wizard.
  ///
  /// In en, this message translates to:
  /// **'The printer must be on the same Wi-Fi/network as this device.'**
  String get printersConnNetworkHint;

  /// Printer wizard step 3 title: name, address, and options.
  ///
  /// In en, this message translates to:
  /// **'Printer details'**
  String get printersWizardStepDetails;

  /// Printer wizard forward button (steps 1-2).
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get printersNext;

  /// Printer wizard back button (steps 2-3).
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get printersBack;

  /// Printer status pill: the printer is switched off in configuration.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get printersStatusDisabled;

  /// Printer status pill for Bluetooth/USB printers: printing needs the native print bridge, which this build does not include.
  ///
  /// In en, this message translates to:
  /// **'Requires print bridge'**
  String get printersStatusNeedsBridge;

  /// Printer status pill for network printers in this build: the configuration is saved but no print adapter is registered, so nothing can be dispatched.
  ///
  /// In en, this message translates to:
  /// **'Configured only'**
  String get printersStatusConfigOnly;

  /// Printer status pill RESERVED for builds that register a real network print adapter. In this web build no adapter exists (hasPrintAdapter is const false in code), so this status is intentionally unreachable — it must never be shown without a real adapter.
  ///
  /// In en, this message translates to:
  /// **'Ready via network adapter'**
  String get printersStatusReadyNetwork;

  /// Per-printer test-print button label. In this build the button is ALWAYS disabled (no print transport); it must never fake a success.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get printersTestPrint;

  /// Explanation next to the permanently disabled test-print button in this build.
  ///
  /// In en, this message translates to:
  /// **'Test print needs the print adapter or bridge — not available in this web build.'**
  String get printersTestPrintUnavailable;

  /// Staff page title.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffTitle;

  /// Staff page subtitle.
  ///
  /// In en, this message translates to:
  /// **'Employees and PIN sign-in for this branch'**
  String get staffSubtitle;

  /// Button that opens the add-staff dialog.
  ///
  /// In en, this message translates to:
  /// **'Add staff member'**
  String get staffAdd;

  /// Empty-state title on the staff page.
  ///
  /// In en, this message translates to:
  /// **'No staff yet'**
  String get staffEmptyTitle;

  /// Empty-state body on the staff page.
  ///
  /// In en, this message translates to:
  /// **'Create your cashiers, kitchen staff, and managers, then set each one a PIN for POS/KDS sign-in.'**
  String get staffEmptyBody;

  /// Staff form field: display name.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get staffFieldName;

  /// Staff form field: role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get staffFieldRole;

  /// Pill: this staff member has a PIN.
  ///
  /// In en, this message translates to:
  /// **'PIN set'**
  String get staffPinSet;

  /// Pill: this staff member has no PIN yet.
  ///
  /// In en, this message translates to:
  /// **'No PIN'**
  String get staffNoPin;

  /// Action that opens the set-PIN dialog.
  ///
  /// In en, this message translates to:
  /// **'Set PIN'**
  String get staffSetPin;

  /// Action label when a PIN already exists.
  ///
  /// In en, this message translates to:
  /// **'Reset PIN'**
  String get staffResetPin;

  /// Set-PIN dialog title.
  ///
  /// In en, this message translates to:
  /// **'Set sign-in PIN'**
  String get staffPinDialogTitle;

  /// Set-PIN dialog explanation.
  ///
  /// In en, this message translates to:
  /// **'4–8 digits. Stored as a secure hash — it can never be read back; setting a new PIN replaces the old one.'**
  String get staffPinDialogBody;

  /// Set-PIN dialog PIN field label.
  ///
  /// In en, this message translates to:
  /// **'PIN (4–8 digits)'**
  String get staffFieldPin;

  /// Set-PIN dialog confirm field label.
  ///
  /// In en, this message translates to:
  /// **'Confirm PIN'**
  String get staffFieldPinConfirm;

  /// Validation message when PIN and confirmation differ.
  ///
  /// In en, this message translates to:
  /// **'PINs don\'t match'**
  String get staffPinMismatch;

  /// Validation message for a malformed PIN.
  ///
  /// In en, this message translates to:
  /// **'Enter 4–8 digits'**
  String get staffPinInvalid;

  /// Snackbar after a successful PIN save.
  ///
  /// In en, this message translates to:
  /// **'PIN saved'**
  String get staffPinSaved;

  /// Snackbar after creating a staff member.
  ///
  /// In en, this message translates to:
  /// **'Staff member created'**
  String get staffCreated;

  /// Warning banner when active staff lack PINs.
  ///
  /// In en, this message translates to:
  /// **'Staff without a PIN can\'t sign in on POS/KDS.'**
  String get staffNoPinWarning;

  /// Pill for a suspended/terminated staff member.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get staffInactive;

  /// Tables page title.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get tablesTitle;

  /// Tables page subtitle.
  ///
  /// In en, this message translates to:
  /// **'Dining tables for this branch — the POS table picker sells from this list.'**
  String get tablesSubtitle;

  /// Button that opens the add-table dialog.
  ///
  /// In en, this message translates to:
  /// **'Add table'**
  String get tablesAdd;

  /// Edit-table action.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get tablesEdit;

  /// Delete-table action + confirm button.
  ///
  /// In en, this message translates to:
  /// **'Remove table'**
  String get tablesDelete;

  /// Delete-table confirmation body.
  ///
  /// In en, this message translates to:
  /// **'Remove this table? Existing orders keep their table reference.'**
  String get tablesDeleteConfirm;

  /// Empty-state title on the tables page.
  ///
  /// In en, this message translates to:
  /// **'No tables yet'**
  String get tablesEmptyTitle;

  /// Empty-state body on the tables page.
  ///
  /// In en, this message translates to:
  /// **'Add your first table — the POS dine-in flow needs at least one.'**
  String get tablesEmptyBody;

  /// Table form field: the table's label (name or number).
  ///
  /// In en, this message translates to:
  /// **'Table name / number'**
  String get tablesFieldLabel;

  /// Table form field: seat count (optional).
  ///
  /// In en, this message translates to:
  /// **'Seats'**
  String get tablesFieldSeats;

  /// Table form field: dining area or section (optional).
  ///
  /// In en, this message translates to:
  /// **'Area / section'**
  String get tablesFieldArea;

  /// Table form switch: the table is active (offered by the POS table picker).
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get tablesActive;

  /// Pill for a deactivated table (hidden from the POS table picker).
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get tablesInactive;

  /// Validation message for a missing table label.
  ///
  /// In en, this message translates to:
  /// **'Enter a table name'**
  String get tablesErrLabel;

  /// Validation message for a non-positive/invalid seat count.
  ///
  /// In en, this message translates to:
  /// **'Seats must be a positive number'**
  String get tablesErrSeats;

  /// Table status pill: available for new guests.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get tablesStatusAvailable;

  /// Table status pill: guests are seated.
  ///
  /// In en, this message translates to:
  /// **'Occupied'**
  String get tablesStatusOccupied;

  /// Table status pill: held for a reservation.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get tablesStatusReserved;

  /// Table status pill: not usable (broken/blocked).
  ///
  /// In en, this message translates to:
  /// **'Out of service'**
  String get tablesStatusOutOfService;

  /// Per-table action that opens the status menu.
  ///
  /// In en, this message translates to:
  /// **'Set status'**
  String get tablesSetStatus;

  /// Snackbar after a successful table save/status change/removal.
  ///
  /// In en, this message translates to:
  /// **'Table saved'**
  String get tablesSaved;

  /// Device revoke confirmation body.
  ///
  /// In en, this message translates to:
  /// **'Revoke this device? Its pairing and sessions end immediately and the device returns to its pairing screen.'**
  String get adminRevokeConfirm;

  /// Hint shown for a code_issued device in real mode (device-originated pairing).
  ///
  /// In en, this message translates to:
  /// **'Enter the one-time code on this device\'s pairing screen to pair it.'**
  String get adminPairOnDevice;

  /// PIN sign-in screen title (POS/KDS).
  ///
  /// In en, this message translates to:
  /// **'Staff sign-in'**
  String get pinLoginTitle;

  /// Heading above the staff list on the PIN sign-in screen.
  ///
  /// In en, this message translates to:
  /// **'Tap your name'**
  String get pinLoginPickName;

  /// PIN sign-in empty-state title when the branch has no active staff with PINs.
  ///
  /// In en, this message translates to:
  /// **'No staff PINs yet'**
  String get pinLoginEmptyTitle;

  /// PIN sign-in empty-state body (generic fallback when no surface is given).
  ///
  /// In en, this message translates to:
  /// **'Ask a manager to add staff members and set their PINs in the dashboard.'**
  String get pinLoginEmptyBody;

  /// PIN sign-in empty-state body on the POS: which roles can sign in and what to do.
  ///
  /// In en, this message translates to:
  /// **'Open Dashboard → Staff, add a cashier or manager, set their PIN, then come back and tap Try again.'**
  String get pinLoginEmptyBodyPos;

  /// PIN sign-in empty-state body on the KDS: which roles can sign in and what to do.
  ///
  /// In en, this message translates to:
  /// **'Open Dashboard → Staff, add a kitchen staff member or manager, set their PIN, then come back and tap Try again.'**
  String get pinLoginEmptyBodyKds;

  /// Heading of the numbered setup-steps list on the no-staff PIN screen.
  ///
  /// In en, this message translates to:
  /// **'Setup steps'**
  String get pinLoginStepsTitle;

  /// No-staff setup step 1.
  ///
  /// In en, this message translates to:
  /// **'1. Open the Dashboard'**
  String get pinLoginStep1;

  /// No-staff setup step 2.
  ///
  /// In en, this message translates to:
  /// **'2. Go to Staff'**
  String get pinLoginStep2;

  /// No-staff setup step 3.
  ///
  /// In en, this message translates to:
  /// **'3. Add a staff member'**
  String get pinLoginStep3;

  /// No-staff setup step 4.
  ///
  /// In en, this message translates to:
  /// **'4. Set a PIN'**
  String get pinLoginStep4;

  /// No-staff setup step 5.
  ///
  /// In en, this message translates to:
  /// **'5. Return here and tap Try again'**
  String get pinLoginStep5;

  /// PIN sign-in staff-list load failure message.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the staff list. Check the connection and try again.'**
  String get pinLoginLoadError;

  /// PIN sign-in message when the stored device session was rejected.
  ///
  /// In en, this message translates to:
  /// **'This device\'s session is no longer valid. Pair the device again.'**
  String get pinLoginSessionInvalid;

  /// PIN sign-in wrong-PIN message.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN — try again.'**
  String get pinLoginWrongPin;

  /// PIN sign-in lockout message.
  ///
  /// In en, this message translates to:
  /// **'Too many attempts. This sign-in is temporarily locked.'**
  String get pinLoginLocked;

  /// PIN sign-in transient network message.
  ///
  /// In en, this message translates to:
  /// **'Connection problem — try again.'**
  String get pinLoginNetworkError;

  /// PIN sign-in generic unavailable message.
  ///
  /// In en, this message translates to:
  /// **'Sign-in isn\'t available right now.'**
  String get pinLoginUnavailable;

  /// Shown on the PIN screen after an inactivity/max-age expiry signed the operator out (RF-118).
  ///
  /// In en, this message translates to:
  /// **'Session expired. Please enter your PIN again.'**
  String get pinSessionExpired;

  /// PIN sign-in submit button.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get pinLoginSubmit;

  /// PIN sign-in back-to-staff-list button.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get pinLoginBack;

  /// PIN input field label.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinFieldLabel;

  /// POS/KDS action that ends the current staff PIN session.
  ///
  /// In en, this message translates to:
  /// **'End staff session'**
  String get posSignOutStaff;

  /// POS real-menu load failure message.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the menu. Check the connection and try again.'**
  String get posMenuLoadError;

  /// POS real-menu empty-state title.
  ///
  /// In en, this message translates to:
  /// **'No menu items yet'**
  String get posMenuEmptyTitle;

  /// POS real-menu empty-state body.
  ///
  /// In en, this message translates to:
  /// **'Add menu items in the dashboard to start selling.'**
  String get posMenuEmptyBody;

  /// POS dine-in table-picker empty state in real mode: the branch has no configured tables yet.
  ///
  /// In en, this message translates to:
  /// **'No tables configured — add tables in Dashboard → Tables.'**
  String get posTablesEmptyReal;

  /// KDS action shown when the live session expired/was revoked; returns to the staff PIN screen.
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get kdsSignInAgain;

  /// POS action on the order confirmation that opens the payment sheet (cash or a non-cash tender).
  ///
  /// In en, this message translates to:
  /// **'Take payment'**
  String get posTakePayment;

  /// POS label above the tender-type selector (Cash / Card / Bit / External) on the payment sheet.
  ///
  /// In en, this message translates to:
  /// **'Tender type'**
  String get posTenderTypeLabel;

  /// POS heading of the payment sheet when a non-cash (externally-recorded) tender is selected.
  ///
  /// In en, this message translates to:
  /// **'Record external payment'**
  String get posExternalPaymentTitle;

  /// POS payment method value: card (externally recorded; no charge processed by RestoFlow).
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get posPaymentMethodCard;

  /// POS payment method value: Bit (the mobile transfer app; externally recorded).
  ///
  /// In en, this message translates to:
  /// **'Bit'**
  String get posPaymentMethodBit;

  /// POS payment method value: another external tender, recorded without a real charge.
  ///
  /// In en, this message translates to:
  /// **'External'**
  String get posPaymentMethodExternal;

  /// POS honest note on the payment sheet for a non-cash tender: RestoFlow records the tender but processes no charge.
  ///
  /// In en, this message translates to:
  /// **'External payment recorded — RestoFlow does not process the card or transfer; no real charge is made.'**
  String get posNonCashNote;

  /// DESIGN-001: title of the pinned danger banner in the payment sheet after a failed payment push (previously a silent failure).
  ///
  /// In en, this message translates to:
  /// **'Payment not recorded'**
  String get posPaymentFailedTitle;

  /// DESIGN-001: body of the payment-failure banner. Honest: nothing was recorded; the Confirm button doubles as the retry.
  ///
  /// In en, this message translates to:
  /// **'The payment could not be recorded. Check the connection and try again — the order stays unpaid until this succeeds.'**
  String get posPaymentFailedBody;

  /// DESIGN-001: the muted 'quantity times unit price' line under a cart item's name (e.g. '× 2 · ₪42.00'). unitPrice arrives as a pre-formatted money string (integer minor units upstream).
  ///
  /// In en, this message translates to:
  /// **'× {quantity} · {unitPrice}'**
  String posCartQtyUnit(int quantity, String unitPrice);

  /// POS label for the tax line on the cart/checkout summary and receipt.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get posTaxLabel;

  /// POS label for the order grand total (subtotal minus discount plus tax) on the cart/checkout summary.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get posGrandTotal;

  /// POS action on the order confirmation that opens the order-level discount sheet; also the sheet heading.
  ///
  /// In en, this message translates to:
  /// **'Apply discount'**
  String get posApplyDiscount;

  /// POS label for the applied order-level discount line on the summary and receipt.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get posDiscountLabel;

  /// POS discount-type option: a fixed money amount off the order.
  ///
  /// In en, this message translates to:
  /// **'Fixed amount'**
  String get posDiscountFixedLabel;

  /// POS discount-type option: a percentage off the order.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get posDiscountPercentLabel;

  /// POS label for the discount value input (money amount for fixed, or percent for percentage).
  ///
  /// In en, this message translates to:
  /// **'Discount value'**
  String get posDiscountValueLabel;

  /// POS label for the required discount reason input.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get posDiscountReasonLabel;

  /// POS validation message when the typed discount value is empty or malformed.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid discount'**
  String get posDiscountValueInvalid;

  /// POS validation message when the discount reason is empty.
  ///
  /// In en, this message translates to:
  /// **'A reason is required'**
  String get posDiscountReasonRequired;

  /// POS validation message when the fixed discount amount is larger than the order subtotal.
  ///
  /// In en, this message translates to:
  /// **'Discount can\'t exceed the subtotal'**
  String get posDiscountExceedsSubtotal;

  /// POS action that applies the entered order-level discount.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get posDiscountApplyAction;

  /// POS honest message when a cashier without the discount permission tries to apply one (server permission_denied).
  ///
  /// In en, this message translates to:
  /// **'You don\'t have permission to apply a discount — ask a manager.'**
  String get posDiscountPermissionDenied;

  /// POS message when applying the discount failed for a non-permission reason (rejected/unavailable).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t apply the discount'**
  String get posDiscountFailed;

  /// POS honest note that in demo mode the discount is computed and applied locally, not on a backend.
  ///
  /// In en, this message translates to:
  /// **'Demo discount — applied locally'**
  String get posDiscountDemoNote;

  /// POS device-settings heading for the on-device network (Wi-Fi/Ethernet) ESC/POS printer setup (ANDROID-002).
  ///
  /// In en, this message translates to:
  /// **'Network printer (this device)'**
  String get posNetworkPrinterHeading;

  /// POS help text explaining the native network printer prints directly with no print bridge (ANDROID-002).
  ///
  /// In en, this message translates to:
  /// **'Print directly to a Wi-Fi or Ethernet thermal printer on this network. No print bridge needed.'**
  String get posNetworkPrinterHelp;

  /// POS label for the network printer IP-address input.
  ///
  /// In en, this message translates to:
  /// **'Printer IP address'**
  String get posNetworkPrinterIpLabel;

  /// POS example IP address shown as the hint in the printer IP input (an example address, not translated).
  ///
  /// In en, this message translates to:
  /// **'192.168.1.50'**
  String get posNetworkPrinterIpHint;

  /// POS label for the network printer TCP port input (default 9100).
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get posNetworkPrinterPortLabel;

  /// POS label for the optional friendly printer name input.
  ///
  /// In en, this message translates to:
  /// **'Printer name (optional)'**
  String get posNetworkPrinterNameLabel;

  /// POS action that saves the network printer config locally on this device.
  ///
  /// In en, this message translates to:
  /// **'Save printer'**
  String get posNetworkPrinterSaveAction;

  /// POS action that sends a test print to the configured network printer.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get posNetworkPrinterTestAction;

  /// POS confirmation shown after the network printer config is saved locally.
  ///
  /// In en, this message translates to:
  /// **'Network printer saved'**
  String get posNetworkPrinterSavedSnack;

  /// POS network-printer status: no printer has been configured on this device yet.
  ///
  /// In en, this message translates to:
  /// **'Not configured'**
  String get posNetworkPrinterStatusNotConfigured;

  /// POS network-printer status: a printer config is saved on this device (no test run yet).
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get posNetworkPrinterStatusSaved;

  /// POS network-printer status while the test print bytes are being sent.
  ///
  /// In en, this message translates to:
  /// **'Sending test print…'**
  String get posNetworkPrinterTesting;

  /// POS network-printer status: the test print bytes were delivered to the printer (best-effort, not a hardware paper-print acknowledgement).
  ///
  /// In en, this message translates to:
  /// **'Test print sent'**
  String get posNetworkPrinterTestSuccess;

  /// POS network-printer status: the test print could not reach the printer (unreachable/timeout).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the printer. Check the IP address, the port, and that the printer is on this Wi-Fi network.'**
  String get posNetworkPrinterTestFailure;

  /// POS validation message when the typed printer IP address is empty or malformed.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid IP address (for example 192.168.1.50).'**
  String get posNetworkPrinterInvalidIp;

  /// POS validation message when the typed printer port is out of the 1–65535 range.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid port (1–65535).'**
  String get posNetworkPrinterInvalidPort;

  /// Device-settings capability note shown on the native Android app when direct network printing is available, replacing the print-bridge-required note (ANDROID-002).
  ///
  /// In en, this message translates to:
  /// **'This device can print directly to a network printer (set up above) — no print bridge needed.'**
  String get deviceSettingsNativeNetworkNote;

  /// Device-settings status pill for an enabled assigned printer on the native Android app, replacing 'Requires print bridge' when direct network printing is available (ANDROID-002).
  ///
  /// In en, this message translates to:
  /// **'Configured'**
  String get deviceSettingsPrinterConfigured;

  /// POS menu header: how many items the active menu has (DESIGN-004).
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String posMenuItemCount(int count);

  /// POS menu search field placeholder — filters the already-loaded items by name (DESIGN-004).
  ///
  /// In en, this message translates to:
  /// **'Search items…'**
  String get posMenuSearchHint;

  /// POS empty state shown when the client-side search filter matches no menu items (DESIGN-004).
  ///
  /// In en, this message translates to:
  /// **'No items match your search'**
  String get posSearchNoResults;

  /// POS menu-card chip marking an item whose add opens the options/modifier sheet (DESIGN-004).
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get posOptionsChipLabel;

  /// POS phone bottom cart-bar label after an order was submitted (opens the confirmation) (DESIGN-004).
  ///
  /// In en, this message translates to:
  /// **'Order sent — details'**
  String get posCartBarSent;

  /// POS phone bottom cart-bar accessibility label to open the slide-up cart sheet (DESIGN-004).
  ///
  /// In en, this message translates to:
  /// **'View cart'**
  String get posCartBarView;

  /// POS device-settings heading for the native printer transport chooser (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Printer connection'**
  String get posPrinterTransportHeading;

  /// POS printer transport option: a Wi-Fi/Ethernet network printer (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get posPrinterTransportNetwork;

  /// POS printer transport option: a Bluetooth Classic thermal printer (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get posPrinterTransportBluetooth;

  /// POS device-settings heading for the on-device Bluetooth printer setup (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth printer (this device)'**
  String get posBluetoothPrinterHeading;

  /// POS help text for Bluetooth printer setup — the MVP uses already-paired devices (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Print to a paired Bluetooth thermal printer. Pair it in Android Bluetooth settings first, then refresh.'**
  String get posBluetoothPrinterHelp;

  /// POS label above the list of paired Bluetooth devices (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Paired printers'**
  String get posBluetoothPairedLabel;

  /// POS action to reload the paired Bluetooth devices list (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Refresh devices'**
  String get posBluetoothRefreshAction;

  /// POS empty state when no paired Bluetooth devices are found (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'No paired Bluetooth devices. Pair your printer in Android settings, then refresh.'**
  String get posBluetoothNoDevices;

  /// POS message when the Android 12+ Bluetooth runtime permission is denied (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission is required. Allow it for RestoFlow in Android settings, then refresh.'**
  String get posBluetoothPermissionRequired;

  /// POS message when the Bluetooth adapter is off (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off — turn it on, then refresh.'**
  String get posBluetoothOff;

  /// POS confirmation shown after a Bluetooth printer is saved locally (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth printer saved'**
  String get posBluetoothSavedSnack;

  /// POS hint prompting the cashier to pick a paired printer before saving/testing (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Select a paired printer above.'**
  String get posBluetoothSelectHint;

  /// POS action to remove the saved native (network/Bluetooth) printer from this device (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Remove printer'**
  String get posPrinterRemoveAction;

  /// PRINT-STABILITY-001: POS device-settings action to reprint the last built receipt through the current printer; disabled until one exists.
  ///
  /// In en, this message translates to:
  /// **'Reprint last receipt'**
  String get posReprintLastReceiptAction;

  /// PRINT-STABILITY-001: POS confirmation shown when a last-receipt reprint is dispatched to the printer.
  ///
  /// In en, this message translates to:
  /// **'Reprinting the last receipt…'**
  String get posReprintStartedSnack;

  /// POS confirmation shown after the saved printer is removed (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Printer removed'**
  String get posPrinterRemovedSnack;

  /// POS message when a print action runs but no native printer is configured on the device (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'No printer configured on this device.'**
  String get posPrinterNotConfigured;

  /// POS print failure reason: connection/write timed out (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'The printer didn\'t respond in time.'**
  String get posPrinterErrorTimeout;

  /// POS print failure reason: connection refused / host unreachable / not connected (ANDROID-003).
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the printer — check it\'s on and connected.'**
  String get posPrinterErrorUnreachable;

  /// KDS device-settings heading for the on-device kitchen-ticket printer setup (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Local kitchen printer'**
  String get kdsPrinterSettingsTitle;

  /// KDS printer transport choice: a Wi-Fi/Ethernet network printer (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get kdsPrinterTransportNetwork;

  /// KDS printer transport choice: a Bluetooth Classic (SPP) printer (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth'**
  String get kdsPrinterTransportBluetooth;

  /// KDS label for the network printer IP/host field (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Printer IP address'**
  String get kdsPrinterNetworkIp;

  /// KDS label for the network printer TCP port field, 9100 by default (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get kdsPrinterNetworkPort;

  /// KDS action to send a money-free ESC/POS test print to the configured local printer (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get kdsPrinterTestPrint;

  /// KDS status when the kitchen ticket bytes were delivered to the local printer (delivery, not a hardware paper-print) (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Sent to printer'**
  String get kdsPrinterTicketSent;

  /// KDS status when a local kitchen-ticket print attempt failed (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Print failed — check the printer and try again.'**
  String get kdsPrinterPrintFailed;

  /// KDS status when no local kitchen printer is configured on this device (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'No printer configured on this device.'**
  String get kdsPrinterNoPrinterConfigured;

  /// KDS hint prompting the operator to pick a paired Bluetooth printer before saving/testing (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Select a paired printer above.'**
  String get kdsPrinterBluetoothPairHint;

  /// KDS message when the Android 12+ Bluetooth runtime permission is denied (ANDROID-004).
  ///
  /// In en, this message translates to:
  /// **'Bluetooth permission is required. Allow it for RestoFlow in Android settings, then refresh.'**
  String get kdsPrinterBluetoothPermissionRequired;
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
