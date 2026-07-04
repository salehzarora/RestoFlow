// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'RestoFlow';

  @override
  String get posAppTitle => 'RestoFlow POS';

  @override
  String get kdsAppTitle => 'RestoFlow KDS';

  @override
  String get dashboardAppTitle => 'RestoFlow Dashboard';

  @override
  String get adminAppTitle => 'RestoFlow Admin';

  @override
  String get welcomeMessage => 'Welcome to RestoFlow';

  @override
  String get adminOverviewTitle => 'Platform overview';

  @override
  String get adminOverviewAsOf => 'As of';

  @override
  String get adminDemoDataTag => 'Demo data';

  @override
  String get adminDemoDataNotice =>
      'Demo platform data — computed locally on this device, not synced to a backend.';

  @override
  String get adminRefresh => 'Refresh';

  @override
  String get adminLoading => 'Loading platform data…';

  @override
  String get adminError => 'Couldn\'t load platform data.';

  @override
  String get adminEmpty => 'No platform data yet.';

  @override
  String get adminActiveLabel => 'Active';

  @override
  String get adminKpiOrganizations => 'Organizations';

  @override
  String get adminKpiRestaurants => 'Restaurants';

  @override
  String get adminKpiBranches => 'Branches';

  @override
  String get adminKpiActiveBranches => 'Active branches';

  @override
  String get adminKpiDevices => 'Devices';

  @override
  String get adminKpiAlerts => 'Open alerts';

  @override
  String get adminKpiOrdersToday => 'Orders today';

  @override
  String get adminOrganizationsHeading => 'Organizations';

  @override
  String get adminBranchHealthHeading => 'Branch health';

  @override
  String get adminRecentActivityHeading => 'Recent activity';

  @override
  String get adminCreatedLabel => 'Created';

  @override
  String get adminLastActivityLabel => 'Last activity';

  @override
  String get adminOrdersTodayShort => 'orders today';

  @override
  String get adminWarningChip => 'Needs attention';

  @override
  String get adminRealModeNotice =>
      'Live platform data — read-only and limited. Some operational metrics aren\'t available here yet, and platform-admin MFA step-up and grant management aren\'t part of this build.';

  @override
  String get adminLiveLimitedTag => 'Live · limited';

  @override
  String get adminNotConfiguredTitle => 'Platform admin isn\'t configured';

  @override
  String get adminNotConfiguredBody =>
      'Real mode is selected but the Supabase connection isn\'t configured, so no platform data can be loaded. Set the Supabase URL and anon key, or run in demo mode.';

  @override
  String get adminGateTitle => 'Platform admin panel';

  @override
  String get adminGateNotOwner =>
      'This is the platform administration panel — not the restaurant owner\'s panel.';

  @override
  String get adminGateUseDashboard =>
      'Use the Dashboard to manage your restaurant.';

  @override
  String get adminGateNotAdminAccount =>
      'This signed-in account is not a platform admin.';

  @override
  String get adminGateProvisionHint =>
      'Platform-admin access is granted manually by the platform operator — see docs/LOCAL_RUNBOOK.md.';

  @override
  String get adminGateOpenDashboard => 'Open Dashboard';

  @override
  String get adminAccessDeniedTitle => 'Platform admin access denied';

  @override
  String get adminAccessDeniedBody =>
      'An active platform-admin grant and multi-factor (MFA) sign-in are required to view live platform data. Step-up sign-in and grant management aren\'t available in this build yet.';

  @override
  String get localeEnglish => 'English';

  @override
  String get localeArabic => 'Arabic';

  @override
  String get localeHebrew => 'Hebrew';

  @override
  String get kdsEmptyState => 'No active tickets';

  @override
  String get kdsColumnEmpty => 'No tickets';

  @override
  String get kdsStaleBanner => 'Offline — showing last synced tickets';

  @override
  String get kdsBumpAction => 'Bump';

  @override
  String get kdsRecallAction => 'Recall';

  @override
  String get kdsAcknowledgeAction => 'Acknowledge';

  @override
  String get kdsStartAction => 'Start';

  @override
  String get kdsReadyAction => 'Mark ready';

  @override
  String get kdsStationLabel => 'Station';

  @override
  String get kdsTicketLabel => 'Ticket';

  @override
  String get kdsLoadingState => 'Loading tickets…';

  @override
  String get kdsErrorState => 'Couldn\'t load tickets';

  @override
  String get kdsReauthRequired => 'Sign-in required';

  @override
  String get kdsDemoFeedBanner => 'Demo kitchen feed — not synced to a backend';

  @override
  String get kdsColNew => 'New';

  @override
  String get kdsColPreparing => 'Preparing';

  @override
  String get kdsColReady => 'Ready';

  @override
  String get kdsColCleared => 'Cleared';

  @override
  String get kdsCompleteAction => 'Complete';

  @override
  String get kdsNoteLabel => 'Note';

  @override
  String kdsElapsedMinutes(int minutes) {
    return '${minutes}m';
  }

  @override
  String get posMenuHeading => 'Menu';

  @override
  String get posCartTitle => 'Cart';

  @override
  String get posCartEmpty => 'Your cart is empty';

  @override
  String get posCartSubtotal => 'Subtotal';

  @override
  String get posAddToCart => 'Add';

  @override
  String posAddToCartWithTotal(String total) {
    return 'Add · $total';
  }

  @override
  String get posClearCart => 'Clear';

  @override
  String get posRemoveItem => 'Remove';

  @override
  String get posIncreaseQuantity => 'Increase quantity';

  @override
  String get posDecreaseQuantity => 'Decrease quantity';

  @override
  String get posCategoryAll => 'All';

  @override
  String get posSendOrder => 'Send Order';

  @override
  String get posSendNeedsTableHint =>
      'Assign a table to send this dine-in order';

  @override
  String get posDemoOrderNotice =>
      'Demo order — not sent to a backend, kitchen, or printer.';

  @override
  String posOutboxPending(int count) {
    return '$count pending sync';
  }

  @override
  String get posOutboxSyncing => 'Syncing…';

  @override
  String posOutboxFailed(int count) {
    return '$count failed — retry';
  }

  @override
  String get posOutboxSynced => 'All orders synced';

  @override
  String get posOutboxAttention => 'Sync attention needed';

  @override
  String get posOutboxRetryAll => 'Retry all';

  @override
  String get posOrderSubmittedTitle => 'Order sent';

  @override
  String get posOrderNumberLabel => 'Order number';

  @override
  String get posOrderStatusSubmitted => 'Submitted';

  @override
  String get posNewOrder => 'New order';

  @override
  String get posOrderTypeLabel => 'Order type';

  @override
  String get posOrderTypeDineIn => 'Dine-in';

  @override
  String get posOrderTypeTakeaway => 'Takeaway';

  @override
  String get posTableLabel => 'Table';

  @override
  String get posAssignTable => 'Assign table';

  @override
  String get posChangeTable => 'Change table';

  @override
  String get posClearTableAssignment => 'Clear table';

  @override
  String get posTableRequiredWarning => 'Dine-in orders need a table';

  @override
  String get posTableNotNeeded => 'No table needed for takeaway';

  @override
  String get posTablePickerTitle => 'Choose a table';

  @override
  String get posTableStatusAvailable => 'Available';

  @override
  String get posTableStatusOccupied => 'Occupied';

  @override
  String get posTableStatusBlocked => 'Out of service';

  @override
  String posTableSeats(int count) {
    return '$count seats';
  }

  @override
  String get posTablesDemoNotice => 'Demo tables — not loaded from a backend.';

  @override
  String get posTablesEmpty => 'No tables to show';

  @override
  String get posTablesError => 'Couldn\'t load tables';

  @override
  String get posTableStatusSelected => 'Selected';

  @override
  String get posTableAreaMain => 'Main dining area';

  @override
  String get posTableAreaPatio => 'Patio';

  @override
  String get posTablesAisleLabel => 'Walkway';

  @override
  String get posTablesEdgeEntrance => 'Entrance';

  @override
  String get posTablesEdgeCounter => 'Counter';

  @override
  String get posTablesLayoutEditorHint =>
      'Table positions are demo-only — layout editor coming later.';

  @override
  String posTableSelectedSemantic(String label) {
    return '$label, selected';
  }

  @override
  String get posSyncSectionTitle => 'Sync status';

  @override
  String get posSyncStatePending => 'Pending sync';

  @override
  String get posSyncStateSending => 'Sending…';

  @override
  String get posSyncStateSynced => 'Synced';

  @override
  String get posSyncStateFailed => 'Sync failed';

  @override
  String get posSyncStoredLocally => 'Stored locally — backend sync pending';

  @override
  String get posSyncDemoNotice => 'Demo sync — not sent to a real backend';

  @override
  String get posSyncNow => 'Sync now (demo)';

  @override
  String get posSyncRetry => 'Retry';

  @override
  String get posOutboxRefLabel => 'Outbox ref';

  @override
  String get posSubmitFailed => 'Couldn\'t queue the order — please try again';

  @override
  String posSyncPendingCount(int count) {
    return '$count pending sync';
  }

  @override
  String get posPayCash => 'Pay Cash';

  @override
  String get posPaymentTitle => 'Cash payment';

  @override
  String get posAmountDue => 'Amount due';

  @override
  String get posCashReceived => 'Cash received';

  @override
  String get posCashExact => 'Exact';

  @override
  String get posChangeDue => 'Change due';

  @override
  String get posConfirmPayment => 'Confirm payment';

  @override
  String get posCashInvalid => 'Enter a valid amount';

  @override
  String get posCashInsufficient => 'Cash received must cover the amount due';

  @override
  String get posPaidChip => 'Paid';

  @override
  String get posPaymentMethodLabel => 'Payment method';

  @override
  String get posPaymentMethodCash => 'Cash';

  @override
  String get posPaidAtLabel => 'Paid at';

  @override
  String get posReceiptTitle => 'Receipt';

  @override
  String get posReceiptNumberLabel => 'Receipt no.';

  @override
  String get posReceiptTotal => 'Total';

  @override
  String get posReceiptProvisionalNote =>
      'Provisional — reconciled to a server receipt on sync';

  @override
  String get posReceiptDemoNote => 'Demo receipt — no printer connected';

  @override
  String get posPrintReceiptDemo => 'Print receipt (demo)';

  @override
  String get printPreviewAction => 'Print preview';

  @override
  String get printPreviewPrint => 'Print';

  @override
  String get printPreviewClose => 'Close';

  @override
  String get printPreviewHint =>
      'Use your browser\'s print (Ctrl+P) to print this preview';

  @override
  String get deviceSettingsMenuTooltip => 'Device menu';

  @override
  String get deviceSettingsTitle => 'Device settings';

  @override
  String get deviceRefreshAction => 'Refresh connection';

  @override
  String get deviceUnpairAction => 'Unpair device';

  @override
  String get deviceUnpairWarning =>
      'Only use this if this device should be paired again.';

  @override
  String get deviceUnpairConfirm => 'Unpair';

  @override
  String get deviceUnpairCancel => 'Cancel';

  @override
  String get deviceSettingsAppTypeLabel => 'App type';

  @override
  String get deviceSettingsAppTypePos => 'Cashier (POS)';

  @override
  String get deviceSettingsAppTypeKds => 'Kitchen display (KDS)';

  @override
  String get deviceSettingsRestaurantLabel => 'Restaurant';

  @override
  String get deviceSettingsBranchLabel => 'Branch';

  @override
  String get deviceSettingsDeviceLabel => 'Device';

  @override
  String get deviceSettingsPairingLabel => 'Pairing';

  @override
  String get deviceSettingsPairingActive => 'Paired';

  @override
  String get deviceSettingsPinSessionLabel => 'Staff session';

  @override
  String get deviceSettingsPinSessionActive => 'Signed in';

  @override
  String get deviceSettingsPinSessionNone => 'Not signed in';

  @override
  String get deviceSettingsDemoNote => 'Demo mode — no paired device.';

  @override
  String get deviceSettingsUnavailable => 'Device info unavailable.';

  @override
  String get deviceSettingsPrintersHeading => 'Printers';

  @override
  String get deviceSettingsNoPrinter =>
      'No printer assigned. Ask a manager to configure it in Dashboard → Printers.';

  @override
  String get deviceSettingsBridgeRequired =>
      'Configured only — print bridge required.';

  @override
  String get deviceSettingsCapabilityNote =>
      'Printing requires a print bridge/native app. This build can save config and create/preview print jobs.';

  @override
  String deviceSettingsLastRefresh(String time) {
    return 'Last refresh: $time';
  }

  @override
  String get deviceSettingsLoadError => 'Could not load printer assignments.';

  @override
  String get deviceSettingsPrinterDisabled => 'Disabled in Dashboard';

  @override
  String deviceSettingsRouteStations(String names) {
    return 'Stations: $names';
  }

  @override
  String get deviceRefreshedSnack => 'Connection refreshed.';

  @override
  String get deviceUnpairedSnack => 'Device unpaired.';

  @override
  String get deviceSettingsAutoPrintHeading => 'Auto-print';

  @override
  String get posAutoPrintReceiptToggle => 'Auto-print receipt after payment';

  @override
  String get kdsAutoPrintAcknowledgeToggle =>
      'Auto-print kitchen ticket on acknowledge';

  @override
  String get autoPrintNoPrinterNote => 'Disabled — no printer assigned.';

  @override
  String get printStatusNotConfigured => 'No printer configured';

  @override
  String get printStatusPrepared =>
      'Print job prepared — physical printing requires print bridge.';

  @override
  String get printStatusPrinted => 'Printed';

  @override
  String get printStatusFailed => 'Print failed';

  @override
  String get printStatusSentToPrinter =>
      'Sent to the printer (not confirmed printed)';

  @override
  String get printStatusBridgeUnavailable =>
      'Print bridge unavailable — job not sent';

  @override
  String get printRetryAction => 'Retry';

  @override
  String get deviceSettingsBridgeConnected => 'Print bridge: connected';

  @override
  String get deviceSettingsBridgeUnavailable => 'Print bridge: unavailable';

  @override
  String deviceSettingsBridgeLastJob(String time) {
    return 'Last print job: $time';
  }

  @override
  String get posReceiptPrintLabel => 'Receipt print';

  @override
  String get kdsTicketPrintLabel => 'Kitchen print';

  @override
  String get receiptPreviewTitle => 'Receipt preview';

  @override
  String get receiptDemoRestaurantName => 'RestoFlow Demo Restaurant';

  @override
  String get kdsPreviewTicketAction => 'Preview ticket';

  @override
  String get kdsTicketPreviewTitle => 'Kitchen ticket preview';

  @override
  String get kdsElapsedLabel => 'Elapsed';

  @override
  String get languageSelectorTooltip => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHebrew => 'עברית';

  @override
  String get posShiftDemoName => 'Demo morning shift';

  @override
  String get posDrawerLabel => 'Cash drawer';

  @override
  String get posDrawerOpen => 'Open';

  @override
  String get posDrawerClosed => 'Closed';

  @override
  String get posCashInDrawer => 'Cash in drawer';

  @override
  String get posLastCashPayment => 'Last cash payment';

  @override
  String get posShiftDemoNote =>
      'Demo — reconciliation is computed locally and not saved to a server.';

  @override
  String get posShiftRealName => 'Current shift';

  @override
  String get posShiftRealNote =>
      'Opened at sign-in — cash totals are tracked on the server';

  @override
  String get posShiftCloseTitle => 'Close shift & count cash';

  @override
  String get posShiftCloseMenuItem => 'Close shift';

  @override
  String get posShiftCloseConfirmTitle => 'Close this shift?';

  @override
  String get posShiftCloseConfirmBody =>
      'The shift will be closed with the counted amount and can\'t be reopened.';

  @override
  String get posShiftCancelAction => 'Cancel';

  @override
  String get posShiftCloseAction => 'Close shift';

  @override
  String get posShiftDoneAction => 'Done';

  @override
  String get posShiftNoOpenShift => 'No open shift on this device.';

  @override
  String get posShiftNoOpenShiftHint =>
      'A shift opens automatically when a cashier signs in.';

  @override
  String get posShiftOpenedAt => 'Opened at';

  @override
  String get posShiftOpeningFloat => 'Opening float';

  @override
  String get posShiftExpectedCash => 'Expected cash';

  @override
  String get posShiftExpectedAtClose =>
      'Expected cash is calculated on the server at close.';

  @override
  String get posShiftCountedLabel => 'Counted cash';

  @override
  String get posShiftInvalidAmount => 'Enter a valid amount.';

  @override
  String get posShiftReasonLabel =>
      'Reason (required if there\'s a difference)';

  @override
  String get posShiftReasonRequired =>
      'Enter a reason when the counted cash differs from expected.';

  @override
  String get posShiftClosedTitle => 'Shift closed';

  @override
  String get posShiftBalanced => 'Balanced';

  @override
  String get posShiftOver => 'Over';

  @override
  String get posShiftShort => 'Short';

  @override
  String get posShiftDifference => 'Difference';

  @override
  String get posShiftCloseUnavailable =>
      'Closing is unavailable — a staff session on a paired device is required.';

  @override
  String get posShiftClosePermissionDenied =>
      'You aren\'t allowed to close this shift.';

  @override
  String get posShiftCloseServerRejected =>
      'The server rejected the close — a reason may be required or the shift state is invalid.';

  @override
  String get posShiftCloseFailed => 'Couldn\'t close the shift.';

  @override
  String get posShiftCouldNotRestore =>
      'Couldn\'t restore the shift state. Sign in again to open a shift.';

  @override
  String get posShiftReturnToPin => 'Sign out';

  @override
  String get posSyncSendingReal => 'Sending to the backend…';

  @override
  String get posSyncSentReal =>
      'Sent — the kitchen display receives it automatically.';

  @override
  String get posSyncFailedReal =>
      'The backend rejected this order — it was NOT sent to the kitchen.';

  @override
  String get posSyncSendNow => 'Send now';

  @override
  String get posReceiptNoPrinterNote =>
      'Printing is not connected on this device yet';

  @override
  String get posModifierRequired => 'Required';

  @override
  String get posModifierOptional => 'Optional';

  @override
  String posModifierSelectedCount(int selected, int max) {
    return '$selected/$max';
  }

  @override
  String posModifierSelectedCountOpen(int selected) {
    return '$selected';
  }

  @override
  String get posModifierFree => 'Free';

  @override
  String posModifierBasePrice(String price) {
    return 'Base price · $price';
  }

  @override
  String get posModifierItemNoteLabel => 'Item note';

  @override
  String get posModifierItemNoteHint => 'Example: no onions, extra sauce';

  @override
  String get posItemNoteLabel => 'Note';

  @override
  String get dashboardOverviewHeading => 'Today\'s overview';

  @override
  String get dashboardTodaySales => 'Today\'s sales';

  @override
  String get dashboardOrders => 'Orders';

  @override
  String get dashboardAvgOrderValue => 'Avg. order value';

  @override
  String get dashboardCompletedOrders => 'Completed orders';

  @override
  String get dashboardOpenOrders => 'Open orders';

  @override
  String get dashboardDailySummary => 'Daily summary';

  @override
  String get dashboardNetSales => 'Net sales';

  @override
  String get dashboardDiscounts => 'Discounts';

  @override
  String get dashboardVoids => 'Voids';

  @override
  String get dashboardCashCollected => 'Cash collected';

  @override
  String get dashboardCashVariance => 'Cash variance';

  @override
  String get dashboardShiftStatus => 'Shift';

  @override
  String get dashboardSalesByBranch => 'Sales by branch';

  @override
  String get dashboardTopItems => 'Top items';

  @override
  String get dashboardDemoNotice => 'Demo data — not from a live backend.';

  @override
  String get dashboardReportsHeading => 'Owner reports';

  @override
  String get dashboardReportDayLabel => 'Report day';

  @override
  String get dashboardDemoDay => 'Demo day';

  @override
  String get dashboardRefresh => 'Refresh';

  @override
  String get dashboardLoadingReports => 'Loading reports…';

  @override
  String get dashboardReportsError => 'Couldn\'t load reports.';

  @override
  String get dashboardRetry => 'Retry';

  @override
  String get dashboardNoReportData => 'No report data for this day.';

  @override
  String get dashboardDemoReportsNotice =>
      'Demo reports — calculated locally from sample orders, not synced to a backend.';

  @override
  String get dashboardRealModeNotice =>
      'Live reports — read-only and limited. Some figures aren\'t available here yet.';

  @override
  String get dashboardLiveDataTag => 'Live · limited';

  @override
  String get dashboardGrossSales => 'Gross sales';

  @override
  String get dashboardCashSales => 'Cash sales';

  @override
  String get dashboardUnpaidOrders => 'Unpaid orders';

  @override
  String get dashboardPaymentSummary => 'Payment & cash summary';

  @override
  String get dashboardOpeningFloat => 'Opening float';

  @override
  String get dashboardExpectedDrawer => 'Expected in drawer';

  @override
  String get dashboardCountedCash => 'Counted cash';

  @override
  String get dashboardLastCashPayment => 'Last cash payment';

  @override
  String get dashboardPaymentMethods => 'Payment methods';

  @override
  String get dashboardPaymentMethodCash => 'Cash';

  @override
  String get dashboardRecentOrders => 'Recent orders';

  @override
  String get dashboardPaid => 'Paid';

  @override
  String get dashboardUnpaid => 'Unpaid';

  @override
  String get authLoadingAccount => 'Loading account…';

  @override
  String get authSignInRequired => 'Sign-in required';

  @override
  String get authContinue => 'Continue';

  @override
  String get authChooseLocation => 'Choose location';

  @override
  String get authNoAccess => 'No active access';

  @override
  String get authWrongRole => 'This role can\'t use this app';

  @override
  String get authAccessDenied => 'Account access denied';

  @override
  String get authError => 'Something went wrong';

  @override
  String get authRealModeUnconfiguredTitle => 'Real mode is not configured';

  @override
  String get authRealModeUnconfiguredBody =>
      'The app was started in real mode, but the backend connection settings are missing or invalid. RestoFlow never fakes a backend, so real mode stays locked until valid settings are provided.';

  @override
  String get authRealModeUnconfiguredHowTo => 'Start the app with these values';

  @override
  String get authRealModeUnconfiguredDemoHint =>
      'To explore the demo instead, run the app without any configuration — demo mode is the default.';

  @override
  String get authDeviceSignInUnavailableTitle => 'Device sign-in unavailable';

  @override
  String get authDeviceSignInUnavailableBody =>
      'Anonymous device sign-in is disabled or Supabase auth is not configured.';

  @override
  String get authDeviceSignInUnavailableHowTo => 'How to fix it';

  @override
  String get authDeviceSignInUnavailableFix =>
      'Allow anonymous sign-ins in the Supabase Auth settings, restart the backend, then restart this app. No personal account is needed on this device — pairing signs the device in by itself.';

  @override
  String get authTryAgain => 'Try again';

  @override
  String get authSignOut => 'Sign out';

  @override
  String get authPlatformAdmin => 'Platform admin';

  @override
  String get authOrganization => 'Organization';

  @override
  String get authRestaurant => 'Restaurant';

  @override
  String get authBranch => 'Branch';

  @override
  String get authRole => 'Role';

  @override
  String get authRoleOwner => 'Owner';

  @override
  String get authRoleRestaurantOwner => 'Restaurant owner';

  @override
  String get authRoleManager => 'Manager';

  @override
  String get authRoleCashier => 'Cashier';

  @override
  String get authRoleKitchenStaff => 'Kitchen staff';

  @override
  String get authRoleAccountant => 'Accountant';

  @override
  String get authComingSoon => 'Coming soon';

  @override
  String get dashboardNavOverview => 'Overview';

  @override
  String get dashboardNavMenu => 'Menu';

  @override
  String get menuManagementTitle => 'Menu management';

  @override
  String get menuDemoBanner =>
      'Demo data — changes stay on this device and are not saved to a server yet.';

  @override
  String get menuCategoriesHeading => 'Categories';

  @override
  String get menuItemsHeading => 'Items';

  @override
  String get menuSelectCategoryHint => 'Select a category to see its items.';

  @override
  String get menuEmptyCategories => 'No categories yet.';

  @override
  String get menuEmptyItems => 'No items in this category yet.';

  @override
  String get menuLoadError => 'Could not load the menu.';

  @override
  String get menuRetry => 'Retry';

  @override
  String menuItemCount(int count) {
    return '$count items';
  }

  @override
  String get menuAddCategory => 'Add category';

  @override
  String get menuAddItem => 'Add item';

  @override
  String get menuAddSize => 'Add size';

  @override
  String get menuAddVariant => 'Add variant';

  @override
  String get menuAddModifier => 'Add modifier';

  @override
  String get menuAddOption => 'Add option';

  @override
  String get menuEditTitle => 'Edit';

  @override
  String get menuSaveAction => 'Save';

  @override
  String get menuCancelAction => 'Cancel';

  @override
  String get menuEditAction => 'Edit';

  @override
  String get menuDeleteAction => 'Delete';

  @override
  String get menuNameLabel => 'Name';

  @override
  String get menuDescriptionLabel => 'Description (optional)';

  @override
  String get menuPriceLabel => 'Base price';

  @override
  String get menuPriceDeltaLabel => 'Price change';

  @override
  String get menuCurrencyLabel => 'Currency';

  @override
  String get menuCategoryFieldLabel => 'Category';

  @override
  String get menuDisplayOrderLabel => 'Display order';

  @override
  String get menuActiveLabel => 'Active';

  @override
  String get menuSelectionTypeLabel => 'Selection';

  @override
  String get menuSelectionSingle => 'Single';

  @override
  String get menuSelectionMultiple => 'Multiple';

  @override
  String get menuMinSelectLabel => 'Minimum';

  @override
  String get menuMaxSelectLabel => 'Maximum (optional)';

  @override
  String get menuRequiredLabel => 'Required';

  @override
  String get menuAllowQuantityLabel => 'Allow quantity';

  @override
  String get menuAllowQuantityHelp =>
      'The cashier can add the same option more than once (e.g. extra cheese ×2).';

  @override
  String get menuMaxQuantityLabel => 'Max per option';

  @override
  String get menuSizesHeading => 'Sizes';

  @override
  String get menuVariantsHeading => 'Variants';

  @override
  String get menuModifiersHeading => 'Modifiers';

  @override
  String get menuOptionsHeading => 'Options';

  @override
  String get menuDeleteConfirmTitle => 'Delete this entry?';

  @override
  String get menuDeleteConfirmBody =>
      'It will be hidden from the menu. You can restore it later.';

  @override
  String get menuConfirmDelete => 'Delete';

  @override
  String get menuInactiveBadge => 'Inactive';

  @override
  String get menuGlobalBadge => 'All branches';

  @override
  String get menuBranchBadge => 'This branch';

  @override
  String get menuImageHeading => 'Item image';

  @override
  String get menuImageDeferredTitle => 'Image upload isn\'t connected';

  @override
  String get menuImageDeferredBody =>
      'This surface has no image storage connected, so item photos can\'t be uploaded or shown here.';

  @override
  String get menuImagePickAction => 'Choose image';

  @override
  String get menuImageReplaceAction => 'Replace image';

  @override
  String get menuImageRemoveAction => 'Remove image';

  @override
  String get menuImageSaveAction => 'Save image';

  @override
  String get menuImageInvalidType =>
      'Only PNG, JPEG, or WebP images can be uploaded.';

  @override
  String get menuImageTooLarge => 'The image is too large — the limit is 5 MB.';

  @override
  String get menuImageUploadFailed =>
      'Upload failed — the image was not saved.';

  @override
  String get menuImageUnsupportedPlatform =>
      'Choosing an image isn\'t available on this platform yet — use the web dashboard.';

  @override
  String get menuImageDemoNote =>
      'Demo — the image is not uploaded to a server.';

  @override
  String get menuImageLoadError => 'Couldn\'t load the image preview.';

  @override
  String get menuErrorRequired => 'Required';

  @override
  String get menuErrorAmount => 'Enter a valid amount';

  @override
  String get menuErrorNegativePrice => 'Cannot be negative';

  @override
  String get menuErrorCurrency => 'Use a 3-letter code (e.g. ILS)';

  @override
  String get menuErrorSelectionType => 'Choose single or multiple';

  @override
  String get menuErrorMaxLessThanMin => 'Must be at least the minimum';

  @override
  String get menuWritePermissionDenied =>
      'You can\'t change the menu in this scope.';

  @override
  String get menuWriteProblem => 'Couldn\'t save — please try again.';

  @override
  String get menuSavedSnack => 'Saved';

  @override
  String get menuDeletedSnack => 'Deleted';

  @override
  String get menuManagementSubtitle =>
      'Organize categories, items, sizes, modifiers, and prices.';

  @override
  String get menuSearchHint => 'Search the menu';

  @override
  String get menuFilterAll => 'All';

  @override
  String get menuFilterActive => 'Active';

  @override
  String get menuFilterInactive => 'Inactive';

  @override
  String get menuEmptyCategoriesBody =>
      'Create your first category to start building the menu.';

  @override
  String get menuEmptyItemsBody =>
      'Add an item to this category to get started.';

  @override
  String get menuLoadErrorBody =>
      'Something went wrong while loading the menu.';

  @override
  String get menuImageEmptyHint => 'No image yet';

  @override
  String get menuComingSoonBadge => 'Soon';

  @override
  String get menuItemDetailsSection => 'Details';

  @override
  String get menuNoResults => 'No matches';

  @override
  String get menuNoResultsBody => 'Try a different search or filter.';

  @override
  String get menuScopeUnavailableTitle => 'Menu not available for this access';

  @override
  String get menuScopeUnavailableBody =>
      'This is organization-wide access with no restaurant selected. Open menu management from a specific restaurant or branch.';

  @override
  String get menuBasicInfoSection => 'Basic info';

  @override
  String get menuPricingSection => 'Pricing';

  @override
  String get menuPreparationSection => 'Preparation';

  @override
  String get menuAdvancedSection => 'Advanced';

  @override
  String get menuAdvancedSectionHint =>
      'Optional details — use what fits this item.';

  @override
  String get menuItemTypeLabel => 'Item type';

  @override
  String get menuItemTypeUnspecified => 'Not specified';

  @override
  String get menuItemTypeFood => 'Food';

  @override
  String get menuItemTypeDrink => 'Drink';

  @override
  String get menuItemTypeSide => 'Side';

  @override
  String get menuItemTypeCombo => 'Combo';

  @override
  String get menuItemTypeOther => 'Other';

  @override
  String get menuTagsLabel => 'Tags';

  @override
  String get menuTagSpicy => 'Spicy';

  @override
  String get menuTagVegetarian => 'Vegetarian';

  @override
  String get menuTagPopular => 'Popular';

  @override
  String get menuTagNew => 'New';

  @override
  String menuModifierGroupCount(int count) {
    return '$count option groups';
  }

  @override
  String get menuPrepMinutesLabel => 'Prep time (minutes)';

  @override
  String get menuKitchenNoteLabel => 'Kitchen note';

  @override
  String get menuSkuLabel => 'SKU (internal code)';

  @override
  String get menuPortionFieldLabel => 'Portion label';

  @override
  String get menuPattyCountLabel => 'Count (patties or pieces)';

  @override
  String get menuPattyWeightLabel => 'Weight per piece (g)';

  @override
  String get menuTemplateAddAction => 'Add template';

  @override
  String get menuTemplatePickerTitle => 'Add from template';

  @override
  String get menuTemplateRequiredSingle => 'Required · choose 1';

  @override
  String get menuTemplateOptionalMulti => 'Optional · multi-select';

  @override
  String get menuTemplateOptionalSingle => 'Optional · choose up to 1';

  @override
  String menuTemplateOptionCount(int count) {
    return '$count options';
  }

  @override
  String get menuTemplateApplyPartial =>
      'Stopped — the rows already added stay in the list; edit or delete them below.';

  @override
  String get menuTemplateBurgerToppings => 'Burger toppings';

  @override
  String get menuTemplateOptLettuce => 'Lettuce';

  @override
  String get menuTemplateOptTomato => 'Tomato';

  @override
  String get menuTemplateOptOnion => 'Onion';

  @override
  String get menuTemplateOptPickles => 'Pickles';

  @override
  String get menuTemplateOptCheese => 'Cheese';

  @override
  String get menuTemplateDoneness => 'Doneness';

  @override
  String get menuTemplateOptRare => 'Rare';

  @override
  String get menuTemplateOptMediumDoneness => 'Medium';

  @override
  String get menuTemplateOptWellDone => 'Well done';

  @override
  String get menuTemplatePattyCount => 'Patty count';

  @override
  String get menuTemplateOptSinglePatty => 'Single patty';

  @override
  String get menuTemplateOptDoublePatty => 'Double patty';

  @override
  String get menuTemplateOptTriplePatty => 'Triple patty';

  @override
  String get menuTemplateExtras => 'Extras';

  @override
  String get menuTemplateOptExtraCheese => 'Extra cheese';

  @override
  String get menuTemplateOptExtraPatty => 'Extra patty';

  @override
  String get menuTemplateOptFries => 'Fries';

  @override
  String get menuTemplateOptDrink => 'Drink';

  @override
  String get menuTemplateDrinkSize => 'Drink size';

  @override
  String get menuTemplateOptSmall => 'Small';

  @override
  String get menuTemplateOptMediumSize => 'Medium';

  @override
  String get menuTemplateOptLarge => 'Large';

  @override
  String get menuTemplateSpiciness => 'Spiciness';

  @override
  String get menuTemplateOptMild => 'Mild';

  @override
  String get menuTemplateOptMediumSpicy => 'Medium';

  @override
  String get menuTemplateOptHot => 'Hot';

  @override
  String get dashboardNavSettings => 'Settings';

  @override
  String get dashboardNavUsers => 'Users';

  @override
  String get dashboardNavDevices => 'Devices';

  @override
  String get adminDemoBanner =>
      'Demo data — actions follow the RF-112 backend contracts but run against an in-memory store on this device; nothing is saved to a server yet.';

  @override
  String get adminPermissionDeniedTitle => 'You don’t have permission';

  @override
  String get adminPermissionDeniedBody =>
      'Your role can’t perform this action at this scope. The role-rank guard limits management to higher roles.';

  @override
  String get adminStateErrorTitle => 'Something went wrong';

  @override
  String get adminStateErrorBody => 'We couldn’t load this. Please try again.';

  @override
  String get adminRetry => 'Retry';

  @override
  String get adminConflictMessage =>
      'That action isn’t allowed in the current state.';

  @override
  String get adminActionProblem =>
      'Couldn’t complete the action — please try again.';

  @override
  String get adminErrCurrency => 'Use a 3-letter code (e.g. ILS)';

  @override
  String get adminErrCountry => 'Use a 2-letter code (e.g. US)';

  @override
  String get adminErrName => 'Required';

  @override
  String get adminErrEmail => 'Enter a valid email';

  @override
  String get adminErrStatus => 'Choose a valid status';

  @override
  String get adminErrRequired => 'Required';

  @override
  String get adminCopy => 'Copy';

  @override
  String get adminShownOnce =>
      'Shown once — copy it now. You won’t be able to see it again.';

  @override
  String get adminDone => 'Done';

  @override
  String get adminSavedSnack => 'Saved';

  @override
  String get adminDevStatusNone => 'Not paired';

  @override
  String get adminDevStatusCodeIssued => 'Code issued';

  @override
  String get adminDevStatusPending => 'Pending approval';

  @override
  String get adminDevStatusPaired => 'Paired';

  @override
  String get adminDevStatusActive => 'Active';

  @override
  String get adminDevStatusSuspended => 'Suspended';

  @override
  String get adminDevStatusRevoked => 'Revoked';

  @override
  String get adminDevStatusCodeExpired => 'Code expired';

  @override
  String get adminDevStatusRejected => 'Rejected';

  @override
  String get adminSettingsTitle => 'Settings';

  @override
  String get adminSettingsSubtitle =>
      'Organization, restaurant, and branch settings for this scope.';

  @override
  String get adminSettingsReadOnly =>
      'Your role can view these settings but can’t edit them.';

  @override
  String get adminSectionOrg => 'Organization';

  @override
  String get adminSectionRestaurant => 'Restaurant';

  @override
  String get adminSectionBranch => 'Branch';

  @override
  String get adminFieldDefaultCurrency => 'Default currency';

  @override
  String get adminFieldCountryCode => 'Country code';

  @override
  String get adminFieldStatus => 'Status';

  @override
  String get adminFieldName => 'Name';

  @override
  String get adminFieldCurrencyOverride => 'Currency override';

  @override
  String get adminFieldTimezone => 'Timezone';

  @override
  String get adminFieldAddress => 'Address';

  @override
  String get adminFieldReceiptPrefix => 'Receipt prefix';

  @override
  String get adminStatusActive => 'Active';

  @override
  String get adminStatusSuspended => 'Suspended';

  @override
  String get adminOptional => 'optional';

  @override
  String get adminSave => 'Save';

  @override
  String get adminCancel => 'Cancel';

  @override
  String get adminUsersTitle => 'Users & Roles';

  @override
  String get adminUsersSubtitle =>
      'Manage who can access this organization and what they can do.';

  @override
  String get adminGrantUser => 'Grant access';

  @override
  String get adminGrantDialogTitle => 'Grant access';

  @override
  String get adminGrant => 'Grant';

  @override
  String get adminChangeRole => 'Change role';

  @override
  String get adminChangeRoleTitle => 'Change role';

  @override
  String get adminUpdate => 'Update';

  @override
  String get adminRevoke => 'Revoke';

  @override
  String get adminComingSoon => 'coming soon';

  @override
  String get adminRoleGuardNote =>
      'You can assign roles below your own — the role-rank guard prevents granting your own role or higher.';

  @override
  String get adminSelf => 'You';

  @override
  String get adminStatusRevoked => 'Revoked';

  @override
  String get adminFieldDisplayName => 'Display name';

  @override
  String get adminFieldEmail => 'Email';

  @override
  String get adminFieldRole => 'Role';

  @override
  String get adminUsersEmptyTitle => 'No members yet';

  @override
  String get adminUsersEmptyBody =>
      'Grant access to add the first member to this organization.';

  @override
  String get adminUserGranted => 'Access granted';

  @override
  String get adminRoleUpdated => 'Role updated';

  @override
  String get adminRevokeMemberTitle => 'Revoke access?';

  @override
  String get adminRevokeMemberBody =>
      'This removes the member’s access to this organization and ends any PIN sign-in. You can’t undo this here.';

  @override
  String get adminMemberRevoked => 'Access revoked';

  @override
  String get adminDevicesTitle => 'Devices';

  @override
  String get adminDevicesSubtitle =>
      'Provision and pair POS and kitchen-display devices for this branch.';

  @override
  String get adminCreateDevice => 'Add device';

  @override
  String get adminCreateDeviceTitle => 'Add device';

  @override
  String get adminCreate => 'Create';

  @override
  String get adminFieldDeviceLabel => 'Device label';

  @override
  String get adminFieldDeviceType => 'Device type';

  @override
  String get adminDeviceTypePos => 'POS';

  @override
  String get adminDeviceTypeKds => 'Kitchen display';

  @override
  String get adminLifecycleNote =>
      'Lifecycle: issue a code → the device redeems it (pending) → approve (paired) → activate (active) → start a session. Approval and activation are separate steps; a device can’t jump from pending to active.';

  @override
  String get adminIssueCode => 'Issue code';

  @override
  String get adminRedeem => 'Redeem code';

  @override
  String get adminApprove => 'Approve';

  @override
  String get adminActivate => 'Activate';

  @override
  String get adminStartSession => 'Start session';

  @override
  String get adminDevicesEmptyTitle => 'No devices yet';

  @override
  String get adminDevicesEmptyBody =>
      'Add a device to begin the enrollment and pairing flow.';

  @override
  String get adminCodeIssuedTitle => 'Enrollment code';

  @override
  String get adminCodeIssuedSubtitle =>
      'Enter this code on the device to begin pairing.';

  @override
  String get adminCodeExpiresNote =>
      'This code expires shortly and can be redeemed once.';

  @override
  String get adminTokenStartedTitle => 'Device session started';

  @override
  String get adminTokenStartedSubtitle =>
      'Load this session token onto the device to authenticate it.';

  @override
  String get adminSessionOpen => 'Session active';

  @override
  String get adminDeviceCreated => 'Device added';

  @override
  String get adminDeviceUpdated => 'Device updated';

  @override
  String get authWelcomeTitle => 'Welcome to RestoFlow';

  @override
  String get authBrandTagline => 'Restaurant operating system';

  @override
  String get authSignInTab => 'Sign in';

  @override
  String get authCreateAccountTab => 'Create account';

  @override
  String get authEmailLabel => 'Email';

  @override
  String get authPasswordLabel => 'Password';

  @override
  String get authSignInAction => 'Sign in';

  @override
  String get authEmailRequired => 'Enter your email';

  @override
  String get authPasswordRequired => 'Enter your password';

  @override
  String get authPasswordTooShort => 'Use at least 6 characters';

  @override
  String get authInvalidCredentials => 'Incorrect email or password';

  @override
  String get authSignUpFailed =>
      'Couldn\'t create your account. Please try again.';

  @override
  String get authNetworkError =>
      'Can\'t reach the server. Check your connection.';

  @override
  String get authEmailConfirmationSent =>
      'Check your email to confirm your account, then sign in.';

  @override
  String get onboardingTitle => 'Set up your restaurant';

  @override
  String get onboardingIntro =>
      'Create your restaurant to start using RestoFlow.';

  @override
  String get onboardingRestaurantNameLabel => 'Restaurant name';

  @override
  String get onboardingBranchNameLabel => 'Branch name (optional)';

  @override
  String get onboardingRestaurantNameRequired => 'Enter a restaurant name';

  @override
  String get onboardingCreateAction => 'Create restaurant';

  @override
  String get onboardingFailed =>
      'Couldn\'t create your restaurant. Please try again.';

  @override
  String get pairingTitle => 'Pair this device';

  @override
  String get pairingIntro =>
      'Enter the pairing code created in the restaurant dashboard to connect this device.';

  @override
  String get pairingWhereCode =>
      'Get a pairing code from the Dashboard → Devices tab.';

  @override
  String get pairingCodeLabel => 'Pairing code';

  @override
  String get pairingCodeRequired => 'Enter the pairing code';

  @override
  String get pairingPairAction => 'Pair device';

  @override
  String get pairingInvalidCode =>
      'That pairing code wasn\'t accepted. Check it and try again.';

  @override
  String get pairingExpired =>
      'This pairing code has expired. Ask for a new one.';

  @override
  String get pairingWrongScope =>
      'This code is for a different restaurant or branch.';

  @override
  String get pairingFailed => 'Couldn\'t pair this device. Please try again.';

  @override
  String get dashboardNavPrinters => 'Printers';

  @override
  String get dashboardNavStaff => 'Staff';

  @override
  String get dashboardNavTables => 'Tables';

  @override
  String get dashboardModeDemo => 'Demo';

  @override
  String get dashboardModeReal => 'Real';

  @override
  String get dashboardUsersNotConnectedTitle =>
      'User management not connected yet';

  @override
  String get dashboardUsersNotConnectedBody =>
      'This build cannot list or invite real members yet — there is no member directory API. Instead of showing sample people, this page stays empty. Demo mode previews how the flow will work.';

  @override
  String get dashboardSettingsWorkspace => 'Workspace';

  @override
  String get dashboardSettingsRealNotice =>
      'These are your real workspace values. Editing settings is not connected in this build yet, so there is nothing to save here.';

  @override
  String get dashboardSettingsEditableTitle => 'Edit branch details';

  @override
  String get dashboardSettingsBranchNameLabel => 'Branch name';

  @override
  String get dashboardSettingsRestaurantNameLabel => 'Restaurant name';

  @override
  String get dashboardSettingsReceiptPrefixHint =>
      'Leave blank to keep the current prefix';

  @override
  String get dashboardSettingsCurrencyLocked =>
      'Currency is fixed to ₪ (ILS) for the pilot and can’t be changed here.';

  @override
  String get dashboardShiftCloseSectionTitle => 'Shift reconciliation (POS)';

  @override
  String get dashboardShiftCloseToggleLabel =>
      'Show “Close shift & count cash” on the POS';

  @override
  String get dashboardShiftCloseToggleHelp =>
      'When on, cashiers can close their shift and count the cash drawer on the POS for this branch. Turning it off hides that workflow; payments are unaffected.';

  @override
  String get dashboardShiftCloseOwnerOnly =>
      'Only an owner can change this setting.';

  @override
  String get dashboardShiftCloseUnavailable =>
      'Couldn’t load this setting right now. Try again later.';

  @override
  String get dashboardShiftCloseSaved => 'Setting saved.';

  @override
  String get dashboardShiftCloseDenied =>
      'You don’t have permission to change this setting.';

  @override
  String get dashboardShiftCloseSaveFailed =>
      'Couldn’t save the setting. Please try again.';

  @override
  String get setupTitle => 'Setup';

  @override
  String get setupSubtitle => 'Get this branch ready for service';

  @override
  String get setupDevices => 'Devices';

  @override
  String get setupDevicesCaption => 'active / total';

  @override
  String get setupPrinters => 'Printers';

  @override
  String get setupPrintersCaption => 'enabled / total';

  @override
  String get setupStaffPin => 'Staff PINs';

  @override
  String get setupStaffCaption => 'with PIN / total';

  @override
  String get setupMetricUnavailable => 'n/a';

  @override
  String get setupNoDevices =>
      'No devices yet — create a POS or KDS device and issue a pairing code.';

  @override
  String get setupNoActiveDevice =>
      'No device is paired yet — issue a code in Devices and redeem it on the device\'s pairing screen.';

  @override
  String get setupNoPrinters =>
      'No printers configured yet — add a receipt or kitchen printer.';

  @override
  String get setupNoStaffPin =>
      'No staff member has a PIN yet — POS/KDS sign-in (and the live order flow) needs at least one.';

  @override
  String get setupReady =>
      'This branch is ready: paired device and staff PIN in place.';

  @override
  String get setupMenu => 'Menu items';

  @override
  String get setupMenuCaption => 'active / total';

  @override
  String get setupNoMenu => 'No menu items yet — the POS has nothing to sell.';

  @override
  String get setupAddMenuItem => 'Add your first menu item';

  @override
  String get setupNoPosDevice =>
      'No POS device yet — the counter needs one to take orders.';

  @override
  String get setupCreatePos => 'Create POS device';

  @override
  String get setupNoKdsDevice =>
      'No kitchen display yet — the kitchen won\'t see incoming orders.';

  @override
  String get setupCreateKds => 'Create kitchen display';

  @override
  String get setupPairingHint =>
      'Open the POS or KDS app on that device and enter the pairing code from the Devices tab.';

  @override
  String get setupAddPrinter => 'Add printer';

  @override
  String get setupCreatePin => 'Create staff PIN';

  @override
  String get printersTitle => 'Printers';

  @override
  String get printersSubtitle => 'Receipt and kitchen printers for this branch';

  @override
  String get printersAdd => 'Add printer';

  @override
  String get printersEmptyTitle => 'No printers yet';

  @override
  String get printersEmptyBody =>
      'Add a receipt or kitchen printer to prepare this branch for printing.';

  @override
  String get printersTransportNoticeTitle =>
      'Configuration only — no print transport yet';

  @override
  String get printersTransportNotice =>
      'Printer settings are saved and validated on the backend, but this build does not send anything to physical printers. The print engine ships network-first; Bluetooth and USB transports are not installed yet. No fake print success is ever shown.';

  @override
  String get printersRoleReceipt => 'Receipt';

  @override
  String get printersRoleKitchen => 'Kitchen';

  @override
  String get printersConnNetwork => 'Network (Wi-Fi/LAN)';

  @override
  String get printersConnBluetooth => 'Bluetooth';

  @override
  String get printersConnUsb => 'USB';

  @override
  String get printersConnConfigOnly =>
      'Configuration only — this transport is not installed yet.';

  @override
  String get printersAdvanced => 'Advanced';

  @override
  String get printersDialogSavesConfigOnly =>
      'This build saves the printer configuration only — nothing is printed yet.';

  @override
  String get printersConnBluetoothWeb =>
      'Bluetooth discovery is not available in the web app yet. Save configuration only.';

  @override
  String get printersConnUsbAdapter =>
      'USB printing requires the desktop/native printer adapter. Save configuration only.';

  @override
  String get printersFieldName => 'Display name';

  @override
  String get printersFieldRole => 'Printer role';

  @override
  String get printersFieldConnection => 'Connection type';

  @override
  String get printersFieldPaper => 'Paper width';

  @override
  String get printersFieldHost => 'Host / IP address';

  @override
  String get printersFieldPort => 'Port';

  @override
  String get printersFieldBluetoothId => 'Bluetooth device id / name';

  @override
  String get printersFieldUsbPath => 'USB path / identifier';

  @override
  String get printersEnabled => 'Enabled';

  @override
  String get printersDisabled => 'Disabled';

  @override
  String get printersEdit => 'Edit';

  @override
  String get printersRoute => 'Route to station';

  @override
  String get printersRouteTitle => 'Route printer to a station';

  @override
  String get printersRouteStation => 'Station';

  @override
  String get printersRouteActive => 'Route enabled';

  @override
  String get printersRoutedTo => 'Routes to';

  @override
  String get printersDelete => 'Remove printer';

  @override
  String get printersDeleteConfirm =>
      'Remove this printer? Its station routes are removed too.';

  @override
  String get printersSaved => 'Saved';

  @override
  String get printersNoStations => 'No stations found for this branch yet.';

  @override
  String get printersErrHost => 'Enter the printer host / IP';

  @override
  String get printersErrPort => 'Enter a valid port (1–65535)';

  @override
  String get printersSave => 'Save';

  @override
  String get printersWizardStepPurpose => 'What do you want to print?';

  @override
  String get printersPurposeReceiptsHint =>
      'Bills for customers at the counter.';

  @override
  String get printersPurposeKitchenHint => 'Tickets for the kitchen staff.';

  @override
  String get printersWizardStepConnection => 'How is the printer connected?';

  @override
  String get printersConnNetworkHint =>
      'The printer must be on the same Wi-Fi/network as this device.';

  @override
  String get printersWizardStepDetails => 'Printer details';

  @override
  String get printersNext => 'Next';

  @override
  String get printersBack => 'Back';

  @override
  String get printersStatusDisabled => 'Disabled';

  @override
  String get printersStatusNeedsBridge => 'Requires print bridge';

  @override
  String get printersStatusConfigOnly => 'Configured only';

  @override
  String get printersStatusReadyNetwork => 'Ready via network adapter';

  @override
  String get printersTestPrint => 'Test print';

  @override
  String get printersTestPrintUnavailable =>
      'Test print needs the print adapter or bridge — not available in this web build.';

  @override
  String get staffTitle => 'Staff';

  @override
  String get staffSubtitle => 'Employees and PIN sign-in for this branch';

  @override
  String get staffAdd => 'Add staff member';

  @override
  String get staffEmptyTitle => 'No staff yet';

  @override
  String get staffEmptyBody =>
      'Create your cashiers, kitchen staff, and managers, then set each one a PIN for POS/KDS sign-in.';

  @override
  String get staffFieldName => 'Display name';

  @override
  String get staffFieldRole => 'Role';

  @override
  String get staffPinSet => 'PIN set';

  @override
  String get staffNoPin => 'No PIN';

  @override
  String get staffSetPin => 'Set PIN';

  @override
  String get staffResetPin => 'Reset PIN';

  @override
  String get staffPinDialogTitle => 'Set sign-in PIN';

  @override
  String get staffPinDialogBody =>
      '4–8 digits. Stored as a secure hash — it can never be read back; setting a new PIN replaces the old one.';

  @override
  String get staffFieldPin => 'PIN (4–8 digits)';

  @override
  String get staffFieldPinConfirm => 'Confirm PIN';

  @override
  String get staffPinMismatch => 'PINs don\'t match';

  @override
  String get staffPinInvalid => 'Enter 4–8 digits';

  @override
  String get staffPinSaved => 'PIN saved';

  @override
  String get staffCreated => 'Staff member created';

  @override
  String get staffNoPinWarning =>
      'Staff without a PIN can\'t sign in on POS/KDS.';

  @override
  String get staffInactive => 'Inactive';

  @override
  String get tablesTitle => 'Tables';

  @override
  String get tablesSubtitle =>
      'Dining tables for this branch — the POS table picker sells from this list.';

  @override
  String get tablesAdd => 'Add table';

  @override
  String get tablesEdit => 'Edit';

  @override
  String get tablesDelete => 'Remove table';

  @override
  String get tablesDeleteConfirm =>
      'Remove this table? Existing orders keep their table reference.';

  @override
  String get tablesEmptyTitle => 'No tables yet';

  @override
  String get tablesEmptyBody =>
      'Add your first table — the POS dine-in flow needs at least one.';

  @override
  String get tablesFieldLabel => 'Table name / number';

  @override
  String get tablesFieldSeats => 'Seats';

  @override
  String get tablesFieldArea => 'Area / section';

  @override
  String get tablesActive => 'Active';

  @override
  String get tablesInactive => 'Inactive';

  @override
  String get tablesErrLabel => 'Enter a table name';

  @override
  String get tablesErrSeats => 'Seats must be a positive number';

  @override
  String get tablesStatusAvailable => 'Available';

  @override
  String get tablesStatusOccupied => 'Occupied';

  @override
  String get tablesStatusReserved => 'Reserved';

  @override
  String get tablesStatusOutOfService => 'Out of service';

  @override
  String get tablesSetStatus => 'Set status';

  @override
  String get tablesSaved => 'Table saved';

  @override
  String get adminRevokeConfirm =>
      'Revoke this device? Its pairing and sessions end immediately and the device returns to its pairing screen.';

  @override
  String get adminPairOnDevice =>
      'Enter the one-time code on this device\'s pairing screen to pair it.';

  @override
  String get pinLoginTitle => 'Staff sign-in';

  @override
  String get pinLoginPickName => 'Tap your name';

  @override
  String get pinLoginEmptyTitle => 'No staff PINs yet';

  @override
  String get pinLoginEmptyBody =>
      'Ask a manager to add staff members and set their PINs in the dashboard.';

  @override
  String get pinLoginEmptyBodyPos =>
      'Open Dashboard → Staff, add a cashier or manager, set their PIN, then come back and tap Try again.';

  @override
  String get pinLoginEmptyBodyKds =>
      'Open Dashboard → Staff, add a kitchen staff member or manager, set their PIN, then come back and tap Try again.';

  @override
  String get pinLoginStepsTitle => 'Setup steps';

  @override
  String get pinLoginStep1 => '1. Open the Dashboard';

  @override
  String get pinLoginStep2 => '2. Go to Staff';

  @override
  String get pinLoginStep3 => '3. Add a staff member';

  @override
  String get pinLoginStep4 => '4. Set a PIN';

  @override
  String get pinLoginStep5 => '5. Return here and tap Try again';

  @override
  String get pinLoginLoadError =>
      'Couldn\'t load the staff list. Check the connection and try again.';

  @override
  String get pinLoginSessionInvalid =>
      'This device\'s session is no longer valid. Pair the device again.';

  @override
  String get pinLoginWrongPin => 'Wrong PIN — try again.';

  @override
  String get pinLoginLocked =>
      'Too many attempts. This sign-in is temporarily locked.';

  @override
  String get pinLoginNetworkError => 'Connection problem — try again.';

  @override
  String get pinLoginUnavailable => 'Sign-in isn\'t available right now.';

  @override
  String get pinLoginSubmit => 'Sign in';

  @override
  String get pinLoginBack => 'Back';

  @override
  String get pinFieldLabel => 'PIN';

  @override
  String get posSignOutStaff => 'End staff session';

  @override
  String get posMenuLoadError =>
      'Couldn\'t load the menu. Check the connection and try again.';

  @override
  String get posMenuEmptyTitle => 'No menu items yet';

  @override
  String get posMenuEmptyBody =>
      'Add menu items in the dashboard to start selling.';

  @override
  String get posTablesEmptyReal =>
      'No tables configured — add tables in Dashboard → Tables.';

  @override
  String get kdsSignInAgain => 'Sign in again';

  @override
  String get posTakePayment => 'Take payment';

  @override
  String get posTenderTypeLabel => 'Tender type';

  @override
  String get posExternalPaymentTitle => 'Record external payment';

  @override
  String get posPaymentMethodCard => 'Card';

  @override
  String get posPaymentMethodBit => 'Bit';

  @override
  String get posPaymentMethodExternal => 'External';

  @override
  String get posNonCashNote =>
      'External payment recorded — RestoFlow does not process the card or transfer; no real charge is made.';

  @override
  String get posTaxLabel => 'Tax';

  @override
  String get posGrandTotal => 'Total';

  @override
  String get posApplyDiscount => 'Apply discount';

  @override
  String get posDiscountLabel => 'Discount';

  @override
  String get posDiscountFixedLabel => 'Fixed amount';

  @override
  String get posDiscountPercentLabel => 'Percentage';

  @override
  String get posDiscountValueLabel => 'Discount value';

  @override
  String get posDiscountReasonLabel => 'Reason';

  @override
  String get posDiscountValueInvalid => 'Enter a valid discount';

  @override
  String get posDiscountReasonRequired => 'A reason is required';

  @override
  String get posDiscountExceedsSubtotal =>
      'Discount can\'t exceed the subtotal';

  @override
  String get posDiscountApplyAction => 'Apply';

  @override
  String get posDiscountPermissionDenied =>
      'You don\'t have permission to apply a discount — ask a manager.';

  @override
  String get posDiscountFailed => 'Couldn\'t apply the discount';

  @override
  String get posDiscountDemoNote => 'Demo discount — applied locally';
}
