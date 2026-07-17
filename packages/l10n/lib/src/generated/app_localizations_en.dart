// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get dashboardNavActivity => 'Activity log';

  @override
  String get activityLogTitle => 'Activity log';

  @override
  String get activityLogSubtitle =>
      'A read-only record of key actions — who did what, when, and where.';

  @override
  String get activityLogRefresh => 'Refresh';

  @override
  String get activityLogDemoNotice =>
      'Demo data — sample activity so you can explore the timeline before connecting a backend.';

  @override
  String get activityLogFilterCategory => 'Category';

  @override
  String get activityLogFilterBranch => 'Branch';

  @override
  String get activityLogBranchAll => 'All permitted branches';

  @override
  String get activityLogFilterActor => 'Staff member';

  @override
  String get activityLogActorAll => 'All staff';

  @override
  String get activityLogSensitiveOnly => 'Sensitive only';

  @override
  String get activityLogError => 'Couldn\'t load the activity log';

  @override
  String get activityLogErrorHint =>
      'Check your connection or permissions and try again.';

  @override
  String get activityLogEmpty => 'No activity yet';

  @override
  String get activityLogEmptyHint => 'Actions in this range will appear here.';

  @override
  String get activityLogLoadMore => 'Load more';

  @override
  String get activityLogDenied => 'Denied';

  @override
  String get activityLogClose => 'Close';

  @override
  String get activityLogActorUnknown => 'Unavailable';

  @override
  String get activityLogEnabled => 'Enabled';

  @override
  String get activityLogDisabled => 'Disabled';

  @override
  String get activityLogChangesHeading => 'What changed';

  @override
  String get activityLogGenericNote =>
      'This activity was recorded without additional shareable detail.';

  @override
  String get activityLogCategoryAll => 'All categories';

  @override
  String get activityLogCategoryOrders => 'Orders';

  @override
  String get activityLogCategoryVoids => 'Voids';

  @override
  String get activityLogCategoryDiscounts => 'Discounts';

  @override
  String get activityLogCategoryPayments => 'Payments';

  @override
  String get activityLogCategoryShifts => 'Shifts & cash';

  @override
  String get activityLogCategoryStaff => 'Staff';

  @override
  String get activityLogCategoryAccess => 'Access';

  @override
  String get activityLogCategoryDevices => 'Devices';

  @override
  String get activityLogCategoryMenu => 'Menu';

  @override
  String get activityLogCategoryTables => 'Tables';

  @override
  String get activityLogCategoryOrganization => 'Organization';

  @override
  String get activityLogCategorySync => 'Sync';

  @override
  String get activityLogCategoryOther => 'Other';

  @override
  String get activityLogCategorySettings => 'Settings & configuration';

  @override
  String get activityLogTitleBranchSettings => 'Branch settings updated';

  @override
  String get activityLogTitleRestaurantSettings =>
      'Restaurant settings updated';

  @override
  String get activityLogTitleOrganizationSettings =>
      'Organization settings updated';

  @override
  String get activityLogFieldTimezone => 'Timezone';

  @override
  String get activityLogFieldName => 'Name';

  @override
  String get activityLogFieldReceiptPrefix => 'Receipt prefix';

  @override
  String get activityLogTitleOrderVoided => 'Order voided';

  @override
  String get activityLogTitleVoidAcknowledged =>
      'Cancellation acknowledged by kitchen';

  @override
  String get activityLogTitleVoidAckDenied =>
      'Cancellation acknowledgement denied';

  @override
  String get activityLogTitleItemsAdded => 'Items added to order';

  @override
  String get activityLogTitleItemsAddDenied => 'Adding items denied';

  @override
  String get activityLogTitleRoundStatusUpdated =>
      'Service round status updated';

  @override
  String get activityLogTitleRoundStatusDenied => 'Round status change denied';

  @override
  String get activityLogFieldRoundNumber => 'Round number';

  @override
  String get activityLogFieldAddedItemCount => 'Added items';

  @override
  String get kdsAdditionLabel => 'Addition';

  @override
  String kdsRoundLabel(int number) {
    return 'Round $number';
  }

  @override
  String get posAddItemsAction => 'Add items';

  @override
  String posAddingToOrderBanner(String orderCode) {
    return 'Adding to $orderCode';
  }

  @override
  String get posSubmitAddition => 'Submit addition';

  @override
  String get posAdditionPending => 'Addition pending…';

  @override
  String get posAdditionApplied => 'Addition sent to the kitchen';

  @override
  String get posAdditionFailedRetry => 'Addition failed — tap to retry';

  @override
  String get posAddItemsIneligiblePaid => 'Paid orders can\'t take additions';

  @override
  String get posAddItemsIneligibleStatus =>
      'This order can no longer take additions';

  @override
  String get posAddItemsIneligibleTakeaway =>
      'Takeaway orders can\'t take additions';

  @override
  String get activityLogTitleDiscountApplied => 'Discount applied';

  @override
  String get activityLogTitleOrderSubmitted => 'Order submitted';

  @override
  String get activityLogTitleOrderStatusUpdated => 'Order status updated';

  @override
  String get activityLogTitleStaffCreated => 'Staff member added';

  @override
  String get activityLogTitleStaffCapabilities => 'Staff permissions updated';

  @override
  String get activityLogTitleStaffPinSet => 'Staff PIN set';

  @override
  String get activityLogTitleMembershipGranted => 'Access granted';

  @override
  String get activityLogTitleMembershipRevoked => 'Access revoked';

  @override
  String get activityLogTitleRoleUpdated => 'Role changed';

  @override
  String get activityLogTitleShiftOpened => 'Shift opened';

  @override
  String get activityLogTitleShiftClosed => 'Shift closed';

  @override
  String get activityLogTitleShiftReconciled => 'Shift reconciled';

  @override
  String get activityLogTitleDeviceAdded => 'Device added';

  @override
  String get activityLogTitleDeviceRevoked => 'Device removed';

  @override
  String get activityLogTitleDeviceSignedIn => 'Device signed in';

  @override
  String get activityLogTitleEmployeeRevoked => 'Employee access revoked';

  @override
  String get activityLogTitlePaymentRecorded => 'Payment recorded';

  @override
  String get activityLogTitleOrganizationCreated => 'Organization created';

  @override
  String get activityLogFieldWhen => 'When';

  @override
  String get activityLogFieldActor => 'By';

  @override
  String get activityLogFieldScopeLocation => 'Location';

  @override
  String get activityLogFieldDevice => 'Device';

  @override
  String get activityLogFieldReason => 'Reason';

  @override
  String get activityLogFieldStatus => 'Status';

  @override
  String get activityLogFieldScope => 'Scope';

  @override
  String get activityLogFieldDiscountType => 'Discount type';

  @override
  String get activityLogFieldValue => 'Value';

  @override
  String get activityLogFieldAttemptedAction => 'Attempted action';

  @override
  String get activityLogFieldOrderType => 'Order type';

  @override
  String get activityLogFieldRole => 'Role';

  @override
  String get activityLogFieldFromRole => 'From role';

  @override
  String get activityLogFieldToRole => 'To role';

  @override
  String get activityLogFieldDiscountTotal => 'Discount total';

  @override
  String get activityLogFieldOrderTotal => 'Order total';

  @override
  String get activityLogFieldSubtotal => 'Subtotal';

  @override
  String get activityLogFieldLineTotal => 'Line total';

  @override
  String get activityLogFieldLineDiscount => 'Line discount';

  @override
  String get activityLogFieldAmount => 'Amount';

  @override
  String get activityLogFieldTendered => 'Tendered';

  @override
  String get activityLogFieldChange => 'Change';

  @override
  String get activityLogFieldOpeningFloat => 'Opening float';

  @override
  String get activityLogFieldExpectedCash => 'Expected cash';

  @override
  String get activityLogFieldCountedCash => 'Counted cash';

  @override
  String get activityLogFieldVariance => 'Variance';

  @override
  String get activityLogFieldItemCount => 'Items';

  @override
  String get activityLogFieldFailedAttempts => 'Failed attempts';

  @override
  String get activityLogFieldPinSet => 'PIN set';

  @override
  String get activityLogFieldLocked => 'Locked';

  @override
  String get activityLogCapApplyDiscount => 'Apply discount';

  @override
  String get activityLogCapVoidOrder => 'Void order';

  @override
  String get activityLogCapCloseShift => 'Close shift';

  @override
  String get appName => 'RestoFlow';

  @override
  String get posAppTitle => 'RestoFlow POS';

  @override
  String get kdsAppTitle => 'RestoFlow KDS';

  @override
  String get dashboardAppTitle => 'RestoFlow Dashboard';

  @override
  String get dashboardBrandName => 'RestoFlow';

  @override
  String get dashboardBrandTagline => 'Dashboard';

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
  String get adminMfaRequiredTitle => 'Multi-factor authentication required';

  @override
  String get adminMfaRequiredBody =>
      'Your account has platform-admin access, but this sign-in is not multi-factor (MFA) verified. Platform-wide data requires an MFA-verified session.';

  @override
  String get adminMfaRequiredNextTitle =>
      'Complete multi-factor authentication';

  @override
  String get adminMfaRequiredHint =>
      'Verify multi-factor authentication for your platform-operator account, then reload. See docs/LOCAL_RUNBOOK.md for platform-admin MFA setup.';

  @override
  String get adminSignInTitle => 'Platform operator sign in';

  @override
  String get adminSignInInvalid => 'Wrong email or password.';

  @override
  String get adminMfaEnrollTitle => 'Set up an authenticator app';

  @override
  String get adminMfaEnrollBody =>
      'Add this account to an authenticator app (e.g. Google Authenticator, 1Password) — scan the setup URI as a QR code or paste the setup key — then enter the 6-digit code below to finish.';

  @override
  String get adminMfaSetupKey => 'Setup key';

  @override
  String get adminMfaChallengeTitle => 'Enter your authentication code';

  @override
  String get adminMfaChallengeBody =>
      'Open your authenticator app and enter the current 6-digit code.';

  @override
  String get adminMfaCodeLabel => '6-digit code';

  @override
  String get adminMfaVerifyAction => 'Verify';

  @override
  String get adminMfaVerifyFailed =>
      'That code wasn\'t accepted. Enter the current code from your app.';

  @override
  String get adminMfaEnrollError =>
      'Couldn\'t start authenticator setup. Please try again.';

  @override
  String adminSignedInAs(String email) {
    return 'Signed in as $email';
  }

  @override
  String get adminSignInEmailRequired => 'Enter your work email.';

  @override
  String get adminSignInPasswordRequired => 'Enter your password.';

  @override
  String get adminSecureConsoleTagline =>
      'Operator console · every action is audited';

  @override
  String get adminMfaScanInstruction =>
      'Scan this QR code with an authenticator app, or enter the setup key by hand.';

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
  String get kdsCancelledCardTitle => 'Order canceled';

  @override
  String get kdsCancelledCardBody =>
      'The cashier canceled this order — stop preparing it.';

  @override
  String get kdsCancelledAtLabel => 'Canceled at';

  @override
  String get kdsAcknowledgeCancellation => 'Acknowledge cancellation';

  @override
  String get kdsAckPending => 'Sending acknowledgement…';

  @override
  String get kdsAckFailed =>
      'Could not acknowledge — check the connection and try again.';

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
  String get kdsPrepSummaryLabel => 'Prep';

  @override
  String get kdsTicketPrepHeading => 'Order prep';

  @override
  String kdsMeatTotalLabel(String count, String unit) {
    return 'Kitchen total: $count $unit';
  }

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
  String posReceiptOrderHeading(String orderNumber) {
    return 'Order $orderNumber';
  }

  @override
  String get posReceiptThankYou => 'Thank you for your visit';

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
  String get customerNameLabel => 'Customer name';

  @override
  String get customerNamePlaceholder => 'Optional';

  @override
  String get customerNameReceiptLabel => 'Customer';

  @override
  String get customerNameKitchenLabel => 'Customer';

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
  String get printReprintAction => 'Reprint';

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
  String get posShiftEmployee => 'Employee';

  @override
  String get posMenuChangeAvailability => 'Change availability';

  @override
  String get posMenuAvailAvailable => 'Available';

  @override
  String get posMenuAvailabilityOffline =>
      'Availability could not be changed while offline';

  @override
  String get posMenuAvailabilityDenied =>
      'This action requires menu-availability permission';

  @override
  String get posMenuAvailabilityFailed => 'Availability could not be changed';

  @override
  String get posRecoveryOrderNotCreated => 'Order was not created';

  @override
  String get posRecoveryUnavailableItems =>
      'These items are no longer available:';

  @override
  String get posRecoveryMenuRefreshed => 'The menu has been refreshed.';

  @override
  String get posRecoveryBackToCart => 'Back to cart';

  @override
  String get posRecoveryEditOrder => 'Edit order';

  @override
  String get posRecoveryDiscardDraft => 'Discard draft';

  @override
  String get posRecoveryDiscardConfirmTitle => 'Discard this order attempt?';

  @override
  String get posRecoveryDiscardConfirmBody =>
      'The order was not created, so nothing is cancelled on the server. Your draft will be cleared.';

  @override
  String get posRecoveryRemoveUnavailableHint =>
      'Remove the unavailable items, then send again.';

  @override
  String get posRecoveryReplaceCartTitle => 'Replace the current cart?';

  @override
  String get posRecoveryReplaceCartBody =>
      'The cart already has items. Restoring this draft will replace them.';

  @override
  String get posRecoveryReplaceCartAction => 'Replace current cart';

  @override
  String get posRecoveryKeepCartAction => 'Keep current cart';

  @override
  String get posRecentOrderNotCreated => 'Not created';

  @override
  String get posRecoveryOtherSession =>
      'This rejected draft belongs to another session';

  @override
  String get posTableOperations => 'Table operations';

  @override
  String get posTableManualStatus => 'Manual status';

  @override
  String get posTableEffectiveStatus => 'Effective status';

  @override
  String get posTableMarkAvailable => 'Mark available';

  @override
  String get posTableMarkReserved => 'Mark reserved';

  @override
  String get posTableMarkOccupied => 'Mark occupied';

  @override
  String get posTableMarkOutOfService => 'Mark out of service';

  @override
  String get posTableStateAvailable => 'Available';

  @override
  String get posTableStateReserved => 'Reserved';

  @override
  String get posTableStateOccupied => 'Occupied';

  @override
  String get posTableStateOutOfService => 'Out of service';

  @override
  String get posTableLinkAnother => 'Link another table';

  @override
  String get posTableSelectToLink => 'Select a table to link';

  @override
  String get posTableLinked => 'Linked tables';

  @override
  String get posTableUnlink => 'Unlink tables';

  @override
  String get posTableUnlinkConfirmTitle => 'Unlink these tables?';

  @override
  String get posTableActiveOrders => 'Active orders';

  @override
  String get posTableOccupiedByOrder => 'Occupied by an active order';

  @override
  String get posTableRequiresPermission =>
      'This action requires table-management permission';

  @override
  String get posTableOutOfServiceCannotOrder =>
      'An out-of-service table cannot receive an order';

  @override
  String get posTableStatusOffline =>
      'Table status could not be changed while offline';

  @override
  String get posTableStatusFailed => 'Table status could not be changed';

  @override
  String get posTableLinkFailed => 'Tables could not be linked';

  @override
  String get posTableUnlinkFailed => 'Tables could not be unlinked';

  @override
  String get posTableAlreadyGrouped => 'This table is already in a group';

  @override
  String get posTableGroup => 'Table group';

  @override
  String get posTableGroupSectionTitle => 'Linked tables';

  @override
  String get posTableGroupDetailTitle => 'Linked group';

  @override
  String get posTableGroupMembers => 'Group members';

  @override
  String get posTableGroupChoosePrompt => 'Choose a table for the new order';

  @override
  String get posTableGroupNoAssignable =>
      'No table in this group can take a new order right now';

  @override
  String get posTableGroupSelectAction => 'Select';

  @override
  String get posTableGroupJoiner => ' + ';

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
  String get posShiftOwnerMismatch =>
      'A shift is already open on this device, opened by another employee. Only its owner or a manager can close it — sign out so they can sign in.';

  @override
  String get posShiftCloseNotAllowed =>
      'You do not have permission to close this shift. Ask a manager to close it, or to enable shift-close for your account.';

  @override
  String get posShiftAuthorizationPending =>
      'Checking shift permissions… Close is unavailable until this is confirmed.';

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
  String get posModifierChooseOne => 'Choose one option';

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
  String get dashboardShiftCashTitle => 'Shift & cash';

  @override
  String dashboardShiftClosedToday(int count) {
    return '$count closed today';
  }

  @override
  String dashboardShiftOpenNow(int count) {
    return '$count open now';
  }

  @override
  String get dashboardShiftExpectedCash => 'Expected cash';

  @override
  String get dashboardShiftLastClosed => 'Last closed shift';

  @override
  String dashboardShiftClosedBy(String name) {
    return 'Closed by $name';
  }

  @override
  String get dashboardShiftNoneToday => 'No closed shifts yet today.';

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
  String get dashboardLiveReportsTitle => 'Live reports';

  @override
  String get dashboardLiveReportsPending =>
      'Detailed analytics — sales by hour, top items, sales by branch, and recent orders — will appear here once full reporting is enabled.';

  @override
  String adminDevicesShownCount(int count) {
    return '$count devices';
  }

  @override
  String adminDevicesRevokedCount(int count) {
    return '$count revoked';
  }

  @override
  String get adminDevicesRevokedSection => 'Revoked devices';

  @override
  String get dashboardGrossSales => 'Gross sales';

  @override
  String get dashboardCashSales => 'Cash sales';

  @override
  String get dashboardUnpaidOrders => 'Unpaid orders';

  @override
  String get dashboardPaymentMix => 'Payment mix';

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
  String get authProductionDemoBlockedTitle =>
      'Demo mode is on with real credentials';

  @override
  String get authProductionDemoBlockedBody =>
      'This build has valid backend connection settings but is running in demo mode, so it would show demo data as if it were live. Turn off demo mode to serve real data, or remove the connection settings to run the demo. RestoFlow never presents demo data as production.';

  @override
  String get authDeviceSignInUnavailableTitle => 'Device sign-in unavailable';

  @override
  String get offlineBootTitle => 'No connection';

  @override
  String get offlineBootMessage => 'Check Wi-Fi and try again';

  @override
  String get offlineBootRetry => 'Retry';

  @override
  String get offlineBootAutoReconnect =>
      'Keep this screen open — it will reconnect automatically.';

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
  String get menuKitchenPrepSection => 'Kitchen counts';

  @override
  String get menuKitchenPrepHint =>
      'Kitchen resources one of this item uses (e.g. 1 bun) — added to the kitchen count summary. Optional.';

  @override
  String get menuPrepComponentNameLabel => 'Resource';

  @override
  String get menuPrepComponentQuantityLabel => 'Qty';

  @override
  String get menuPrepComponentUnitLabel => 'Unit';

  @override
  String get menuAddPrepComponent => 'Add resource';

  @override
  String get menuRemovePrepComponent => 'Remove component';

  @override
  String get menuKitchenMeatSection => 'Kitchen count summary';

  @override
  String get menuKitchenMeatEnabledLabel => 'Count in kitchen total';

  @override
  String get menuKitchenMeatQuantityLabel => 'Quantity';

  @override
  String get menuKitchenMeatUnitLabel => 'Resource';

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
  String get pairingPanelTitle => 'Pair this device';

  @override
  String get pairingPanelInstructions =>
      'Open this link on the tablet, or scan the QR code, then tap Pair.';

  @override
  String get pairingPanelScanLabel => 'Scan to open on the tablet';

  @override
  String get pairingPanelLinkLabel => 'Pairing link';

  @override
  String get pairingPanelCopyLink => 'Copy link';

  @override
  String get pairingPanelCodeLabel => 'Pairing code';

  @override
  String get pairingPanelManualOnly =>
      'This device type has no app link — enter the code on the tablet manually.';

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
  String get pairingLocked =>
      'Too many attempts. Please wait a few minutes and try again.';

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
  String get dashboardModeDemoData => 'Demo data';

  @override
  String get dashboardModeLiveData => 'Live data';

  @override
  String get dashboardSalesByHour => 'Sales by hour';

  @override
  String dashboardSalesByHourSemantics(String hour, String amount) {
    return 'Sales by hour. Peak at $hour: $amount';
  }

  @override
  String dashboardDeltaVsYesterday(int percent) {
    return '$percent% vs yesterday';
  }

  @override
  String get dashboardRangeToday => 'Today';

  @override
  String get dashboardRangeYesterday => 'Yesterday';

  @override
  String get dashboardRangeLast7 => 'Last 7 days';

  @override
  String get dashboardRangeLast30 => 'Last 30 days';

  @override
  String get dashboardRangeUnavailable =>
      'This range isn\'t available in live reports yet — try Today, or check back after the reporting update ships.';

  @override
  String dashboardDeltaVsDayBefore(int percent) {
    return '$percent% vs day before';
  }

  @override
  String dashboardDeltaVsPrev7(int percent) {
    return '$percent% vs previous 7 days';
  }

  @override
  String dashboardDeltaVsPrev30(int percent) {
    return '$percent% vs previous 30 days';
  }

  @override
  String dashboardShiftClosedInRange(int count) {
    return '$count closed';
  }

  @override
  String get dashboardShiftNoneRange => 'No closed shifts in this range.';

  @override
  String dashboardShiftOpenedBy(String name) {
    return 'Opened by $name';
  }

  @override
  String get dashboardShiftCollected => 'Collected';

  @override
  String get dashboardShiftDurationLabel => 'Duration';

  @override
  String dashboardShiftDurationValue(int hours, int minutes) {
    return '${hours}h ${minutes}m';
  }

  @override
  String dashboardShiftRecentTitle(int count) {
    return 'Recent shifts ($count)';
  }

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
  String get dashboardSettingsTimezoneLabel => 'Branch timezone';

  @override
  String get dashboardSettingsTimezoneHint =>
      'Used for reporting (sales-by-hour, daily totals). Israel is Asia/Jerusalem.';

  @override
  String get dashboardSettingsTimezoneKeep => 'Leave unchanged';

  @override
  String get timezonePickerNotSet => 'Not set';

  @override
  String get timezonePickerWillChange => 'will change on save';

  @override
  String get timezonePickerTitle => 'Select timezone';

  @override
  String get timezonePickerSearchHint => 'Search by country, city, or IANA id';

  @override
  String get timezonePickerNoResults => 'No matching timezones';

  @override
  String get timezoneLabelAsiaJerusalem => 'Israel — Jerusalem';

  @override
  String get timezoneLabelAsiaGaza => 'Palestine — Gaza';

  @override
  String get timezoneLabelAsiaHebron => 'Palestine — Hebron';

  @override
  String get timezoneLabelEuropeLondon => 'United Kingdom — London';

  @override
  String get timezoneLabelEuropeBerlin => 'Germany — Berlin';

  @override
  String get timezoneLabelAmericaNewYork => 'United States — New York';

  @override
  String get timezoneLabelAmericaLosAngeles => 'United States — Los Angeles';

  @override
  String get timezoneLabelAsiaTokyo => 'Japan — Tokyo';

  @override
  String get timezoneLabelAustraliaSydney => 'Australia — Sydney';

  @override
  String get timezoneLabelAfricaCairo => 'Egypt — Cairo';

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
  String get setupReadyHeadline => 'Branch ready for service';

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
  String setupMoreSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count more setup steps',
      one: '1 more setup step',
    );
    return '$_temp0';
  }

  @override
  String get dashboardDevicesActiveOfConfigured =>
      'Active of configured devices';

  @override
  String get dashboardDevicesUnavailable => 'Device status unavailable';

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
  String get staffCapabilitiesTitle => 'Cashier capabilities';

  @override
  String get staffCapabilitiesHint =>
      'On by default. Turn a switch off to remove that capability for this cashier.';

  @override
  String get staffCapApplyDiscount => 'Can apply discounts';

  @override
  String get staffCapVoidOrder => 'Can cancel unpaid orders';

  @override
  String get staffCapCloseShift => 'Can close own shift';

  @override
  String get staffCapManageMenuAvailability => 'Can manage menu availability';

  @override
  String get staffCapManageTableOperations => 'Can manage table operations';

  @override
  String get staffCapabilitiesAction => 'Capabilities';

  @override
  String get staffCapabilitiesSaved => 'Capabilities updated';

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
  String get tablesStatusUnknown => 'Refresh required';

  @override
  String get tablesLinked => 'Linked';

  @override
  String get tablesEffective => 'Effective';

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
  String get pinSessionExpired =>
      'Session expired. Please enter your PIN again.';

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
  String get posPaymentFailedTitle => 'Payment not recorded';

  @override
  String get posPaymentFailedBody =>
      'The payment could not be recorded. Check the connection and try again — the order stays unpaid until this succeeds.';

  @override
  String posCartQtyUnit(int quantity, String unitPrice) {
    return '× $quantity · $unitPrice';
  }

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
  String get posCancelOrderAction => 'Cancel order';

  @override
  String get posCancelOrderConfirm => 'Confirm cancellation';

  @override
  String get posCancellationReasonLabel => 'Cancellation reason';

  @override
  String get posCancellationReasonRequired =>
      'A cancellation reason is required';

  @override
  String get posCancelOrderWarning =>
      'This will cancel the order and no payment will be recorded.';

  @override
  String get posOrderCancelledSnack => 'Order cancelled';

  @override
  String get posOrderCancelledChip => 'Cancelled';

  @override
  String get posCancelPermissionDenied =>
      'Only a manager can cancel this order - ask a manager.';

  @override
  String get posCancelPaidOrderError => 'A paid order cannot be cancelled.';

  @override
  String get posCancelOrderFailed => 'Cancellation failed. Please try again.';

  @override
  String get posCancelDemoNote => 'Demo mode - no real order is cancelled.';

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

  @override
  String get posNetworkPrinterHeading => 'Network printer (this device)';

  @override
  String get posNetworkPrinterHelp =>
      'Print directly to a Wi-Fi or Ethernet thermal printer on this network. No print bridge needed.';

  @override
  String get posNetworkPrinterIpLabel => 'Printer IP address';

  @override
  String get posNetworkPrinterIpHint => '192.168.1.50';

  @override
  String get posNetworkPrinterPortLabel => 'Port';

  @override
  String get posNetworkPrinterNameLabel => 'Printer name (optional)';

  @override
  String get posNetworkPrinterSaveAction => 'Save printer';

  @override
  String get posNetworkPrinterTestAction => 'Test print';

  @override
  String get posNetworkPrinterSavedSnack => 'Network printer saved';

  @override
  String get posNetworkPrinterStatusNotConfigured => 'Not configured';

  @override
  String get posNetworkPrinterStatusSaved => 'Saved';

  @override
  String get posNetworkPrinterTesting => 'Sending test print…';

  @override
  String get posNetworkPrinterTestSuccess => 'Test print sent';

  @override
  String get posNetworkPrinterTestFailure =>
      'Couldn\'t reach the printer. Check the IP address, the port, and that the printer is on this Wi-Fi network.';

  @override
  String get posNetworkPrinterInvalidIp =>
      'Enter a valid IP address (for example 192.168.1.50).';

  @override
  String get posNetworkPrinterInvalidPort => 'Enter a valid port (1–65535).';

  @override
  String get deviceSettingsNativeNetworkNote =>
      'This device can print directly to a network printer (set up above) — no print bridge needed.';

  @override
  String get deviceSettingsPrinterConfigured => 'Configured';

  @override
  String posMenuItemCount(int count) {
    return '$count items';
  }

  @override
  String get posMenuSearchHint => 'Search items…';

  @override
  String get posSearchNoResults => 'No items match your search';

  @override
  String get posOptionsChipLabel => 'Options';

  @override
  String get posCartBarSent => 'Order sent — details';

  @override
  String get posCartBarView => 'View cart';

  @override
  String get posPrinterTransportHeading => 'Printer connection';

  @override
  String get posPrinterTransportNetwork => 'Wi-Fi';

  @override
  String get posPrinterTransportBluetooth => 'Bluetooth';

  @override
  String get posBluetoothPrinterHeading => 'Bluetooth printer (this device)';

  @override
  String get posBluetoothPrinterHelp =>
      'Print to a paired Bluetooth thermal printer. Pair it in Android Bluetooth settings first, then refresh.';

  @override
  String get posBluetoothPairedLabel => 'Paired printers';

  @override
  String get posBluetoothRefreshAction => 'Refresh devices';

  @override
  String get posBluetoothNoDevices =>
      'No paired Bluetooth devices. Pair your printer in Android settings, then refresh.';

  @override
  String get posBluetoothPermissionRequired =>
      'Bluetooth permission is required. Allow it for RestoFlow in Android settings, then refresh.';

  @override
  String get posBluetoothOff => 'Bluetooth is off — turn it on, then refresh.';

  @override
  String get posBluetoothSavedSnack => 'Bluetooth printer saved';

  @override
  String get posBluetoothSelectHint => 'Select a paired printer above.';

  @override
  String get posPrinterRemoveAction => 'Remove printer';

  @override
  String get posReprintLastReceiptAction => 'Reprint last receipt';

  @override
  String get posReprintStartedSnack => 'Reprinting the last receipt…';

  @override
  String get posPrinterRemovedSnack => 'Printer removed';

  @override
  String get posPrinterNotConfigured => 'No printer configured on this device.';

  @override
  String get posPrinterErrorTimeout => 'The printer didn\'t respond in time.';

  @override
  String get posPrinterErrorUnreachable =>
      'Couldn\'t reach the printer — check it\'s on and connected.';

  @override
  String get kdsPrinterSettingsTitle => 'Local kitchen printer';

  @override
  String get kdsPrinterTransportNetwork => 'Wi-Fi';

  @override
  String get kdsPrinterTransportBluetooth => 'Bluetooth';

  @override
  String get kdsPrinterNetworkIp => 'Printer IP address';

  @override
  String get kdsPrinterNetworkPort => 'Port';

  @override
  String get kdsPrinterTestPrint => 'Test print';

  @override
  String get kdsPrinterTicketSent => 'Sent to printer';

  @override
  String get kdsPrinterPrintFailed =>
      'Print failed — check the printer and try again.';

  @override
  String get kdsPrinterNoPrinterConfigured =>
      'No printer configured on this device.';

  @override
  String get kdsPrinterBluetoothPairHint => 'Select a paired printer above.';

  @override
  String get kdsPrinterBluetoothPermissionRequired =>
      'Bluetooth permission is required. Allow it for RestoFlow in Android settings, then refresh.';

  @override
  String get dashboardNavOrders => 'Orders';

  @override
  String get ordersHistoryTitle => 'Order history';

  @override
  String get ordersHistorySubtitle => 'Review completed and in-progress orders';

  @override
  String get ordersSearchHint => 'Search order #, customer, or table';

  @override
  String get ordersRangeToday => 'Today';

  @override
  String get ordersRangeYesterday => 'Yesterday';

  @override
  String get ordersRangeLast7 => 'Last 7 days';

  @override
  String get ordersRangeLast30 => 'Last 30 days';

  @override
  String get ordersFilterStatus => 'Status';

  @override
  String get ordersFilterType => 'Type';

  @override
  String get ordersFilterPayment => 'Payment';

  @override
  String get ordersStatusAll => 'All statuses';

  @override
  String get ordersStatusDraft => 'Draft';

  @override
  String get ordersStatusSubmitted => 'Submitted';

  @override
  String get ordersStatusAccepted => 'Accepted';

  @override
  String get ordersStatusPreparing => 'Preparing';

  @override
  String get ordersStatusReady => 'Ready';

  @override
  String get ordersStatusServed => 'Served';

  @override
  String get ordersStatusCompleted => 'Completed';

  @override
  String get ordersStatusCancelled => 'Cancelled';

  @override
  String get ordersStatusVoided => 'Voided';

  @override
  String get ordersReprintCancelledBanner => 'CANCELLED - not a valid receipt';

  @override
  String get ordersTypeAll => 'All types';

  @override
  String get ordersPaymentAll => 'All payments';

  @override
  String get ordersEmpty => 'No orders found';

  @override
  String get ordersEmptyHint =>
      'Try a different date range or clear the filters.';

  @override
  String get ordersError => 'Couldn\'t load orders';

  @override
  String get ordersErrorHint => 'Check your connection and try again.';

  @override
  String get ordersLoadMore => 'Load more';

  @override
  String get ordersRefresh => 'Refresh';

  @override
  String ordersItemsCount(int count) {
    return '$count items';
  }

  @override
  String get ordersCustomerLabel => 'Customer';

  @override
  String get ordersTimeLabel => 'Time';

  @override
  String get ordersStaffLabel => 'Served by';

  @override
  String get ordersBranchLabel => 'Branch';

  @override
  String get ordersSubtotalLabel => 'Subtotal';

  @override
  String get ordersDiscountLabel => 'Discount';

  @override
  String get ordersTaxLabel => 'Tax';

  @override
  String get ordersChangeLabel => 'Change';

  @override
  String get ordersDetailItems => 'Items';

  @override
  String get ordersDetailPayment => 'Payment';

  @override
  String get ordersDetailKitchen => 'Kitchen';

  @override
  String get ordersDetailInfo => 'Order';

  @override
  String get ordersCopyCode => 'Copy order number';

  @override
  String get ordersCopied => 'Copied';

  @override
  String get ordersPrintFromBrowser => 'Print from browser';

  @override
  String get ordersReprintFromPosHint =>
      'To use the cashier printer, reprint from the POS device';

  @override
  String get ordersReprintFromKdsHint =>
      'For a hardware kitchen ticket, use KDS reprint on the kitchen device';

  @override
  String get ordersDemoNotice => 'Demo orders — not loaded from a backend.';

  @override
  String get ordersUnavailable => 'Unavailable';

  @override
  String get posReceiptOrderTotal => 'Order total';

  @override
  String get posReceiptPaid => 'Paid';

  @override
  String get posReceiptChange => 'Change';

  @override
  String get posPayLaterAction => 'Pay later';

  @override
  String get posPayLaterSavedSnack =>
      'Saved as unpaid — find it in Recent orders';

  @override
  String get posRecentOrdersTitle => 'Recent orders';

  @override
  String get posRecentOrdersWindow => 'Today and yesterday';

  @override
  String get posRecentFilterAll => 'All';

  @override
  String get posRecentFilterUnpaid => 'Unpaid';

  @override
  String get posRecentFilterPaid => 'Paid';

  @override
  String get posRecentEmpty => 'No recent orders';

  @override
  String get posRecentEmptyHint => 'Orders you take will appear here.';

  @override
  String get posRecentReprintAction => 'Reprint receipt';

  @override
  String get posRecentReprintStarted => 'Reprinting receipt…';

  @override
  String get posUnpaidChip => 'Unpaid';

  @override
  String get posNoChargeChip => 'No charge';

  @override
  String get posNoChargeNoPayment =>
      'This order is free — there is nothing to pay.';

  @override
  String get posCancelOrderClosed =>
      'This order is already closed and can no longer be cancelled.';

  @override
  String get posCancelOrderConflict =>
      'This order changed on another device. Refresh and try again.';

  @override
  String get posRecentSyncPending => 'Syncing…';

  @override
  String get posRecentSyncFailed => 'Not synced';

  @override
  String get posCartEditItem => 'Edit';

  @override
  String get posEditSaveChanges => 'Save changes';

  @override
  String get kdsNewOrderBadge => 'New order';

  @override
  String get posReceiptPrintedNote => 'Printed';

  @override
  String get posBluetoothConnectFailed =>
      'Could not connect to the Bluetooth printer. Check it is on and in range, then try again.';

  @override
  String get posBluetoothWriteFailed =>
      'Failed to send the print data — the printer dropped the connection mid-print. Try again.';

  @override
  String get posBluetoothNotPaired =>
      'This printer is not paired. Pair it in Android Bluetooth settings, then try again.';

  @override
  String get ordersTabActive => 'Active orders';

  @override
  String get ordersTabHistory => 'History';

  @override
  String get ordersActiveTitle => 'Active orders';

  @override
  String get ordersActiveSubtitle => 'Orders that are still open right now';

  @override
  String get ordersActiveEmpty => 'No active orders';

  @override
  String get ordersActiveEmptyHint =>
      'Orders appear here as soon as they are submitted, and stay until they are closed.';

  @override
  String get ordersActiveDemoNotice =>
      'Demo active orders — not loaded from a backend.';

  @override
  String get ordersActiveSummaryTotal => 'Active now';

  @override
  String get ordersActiveSummaryAwaitingClose => 'Awaiting close';

  @override
  String get ordersActiveStageAll => 'All stages';

  @override
  String get ordersActiveAgeLabel => 'Open for';

  @override
  String ordersActiveAgeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String ordersActiveAgeHours(int hours, int minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get ordersActiveNoDueTimeNotice =>
      'No promised time is set up, so orders are never marked late — only how long they have been open.';

  @override
  String get ordersActiveAutoRefresh => 'Auto-refresh';

  @override
  String ordersActiveLastUpdated(String time) {
    return 'Updated $time';
  }

  @override
  String ordersActiveTruncated(int shown, int total) {
    return 'Showing the oldest $shown of $total active orders.';
  }

  @override
  String get ordersBranchAll => 'All permitted branches';

  @override
  String get ordersCompleteAction => 'Complete order';

  @override
  String get ordersCompleteRecoveryNote =>
      'This order is served and paid, so it should have closed itself. Completing it by hand is a recovery step.';

  @override
  String get ordersCompleteConfirmTitle => 'Complete this order?';

  @override
  String ordersCompleteConfirmBody(String orderCode) {
    return 'This closes $orderCode and moves it to order history. It does not record a payment.';
  }

  @override
  String get ordersCompletePaymentLabel => 'Payment';

  @override
  String get ordersCompleteBlockedUnpaid =>
      'This order is unpaid. Record the payment before completing it.';

  @override
  String get ordersCompleteSuccess => 'Order completed';

  @override
  String get ordersCompleteErrorNotPaid =>
      'This order cannot be completed until its payment is recorded.';

  @override
  String get ordersCompleteErrorInvalidState =>
      'This order is no longer ready to be completed. Refresh and try again.';

  @override
  String get ordersCompleteErrorDenied =>
      'You do not have permission to complete this order.';

  @override
  String get ordersCompleteErrorConflict =>
      'Someone else updated this order. Refresh to see the latest state.';

  @override
  String get ordersCompleteErrorNotFound =>
      'This order is no longer available.';

  @override
  String get ordersCompleteErrorTransient =>
      'Couldn\'t reach the server. The order was not changed.';

  @override
  String get ordersCompleteRetry => 'Try again';

  @override
  String get activityLogFieldOrderCode => 'Order';

  @override
  String get activityLogFieldPaymentStatus => 'Payment';

  @override
  String get dashboardNoCharge => 'No charge';

  @override
  String get ordersPaymentFrozen =>
      'This order has been paid, so its total is locked. Discounts can no longer be changed.';

  @override
  String get activityLogFieldDeniedReason => 'Reason';

  @override
  String get activityLogDeniedOrderHasPayment => 'The order was already paid';

  @override
  String get activityLogDeniedFullCompRequiresManager =>
      'A full comp needs a manager';

  @override
  String get activityLogDeniedOrderNotVoidable =>
      'The order was already closed';

  @override
  String get activityLogPaymentNotChargeable => 'Nothing to pay';

  @override
  String get activityLogFieldCompletionMode => 'Closed';

  @override
  String get activityLogFieldCompletionTrigger => 'Closed by';

  @override
  String get activityLogCompletionModeAutomatic => 'Automatically';

  @override
  String get activityLogCompletionModeManual => 'By a person';

  @override
  String get activityLogCompletionTriggerOrderServed =>
      'The order being served';

  @override
  String get activityLogCompletionTriggerPaymentRecorded =>
      'The payment being recorded';

  @override
  String get ordersActiveSubtitleV2 =>
      'Orders currently open in operations. Finished orders move to History.';

  @override
  String get ordersQueueInProgress => 'In progress';

  @override
  String get ordersQueueAwaitingClose => 'Awaiting close';

  @override
  String get ordersQueueAllActive => 'All active';

  @override
  String get ordersSortLabel => 'Sort';

  @override
  String get ordersSortNewest => 'Newest first';

  @override
  String get ordersSortOldest => 'Oldest first';

  @override
  String get ordersActiveEmptyInProgress =>
      'No orders are currently being prepared or waiting to be served.';

  @override
  String get ordersActiveEmptyAwaitingClose =>
      'No served orders are waiting to be completed.';

  @override
  String get ordersAwaitingCloseExplainer =>
      'A served order closes itself as soon as it is fully paid, so anything still here needs attention — usually a payment that was never recorded. Record the payment and the order closes on its own.';

  @override
  String ordersAwaitingCloseBacklog(int count) {
    return '$count served orders have not closed. A served order closes itself once it is fully paid, so these are waiting on something.';
  }

  @override
  String ordersActiveTruncatedNewest(int shown, int total) {
    return 'Showing the newest $shown of $total matching active orders.';
  }

  @override
  String ordersActiveTruncatedOldest(int shown, int total) {
    return 'Showing the oldest $shown of $total matching active orders.';
  }

  @override
  String get ordersActiveRefreshFailed =>
      'Couldn\'t refresh just now. These orders may be out of date.';

  @override
  String get staffCapApplyFullComp => 'Can make an order free';

  @override
  String get staffCapApplyFullCompHint =>
      'Allows a discount that brings the order total to zero. Off by default.';

  @override
  String get staffCapApplyFullCompNeedsDiscount =>
      'Needs the discount permission above.';

  @override
  String get staffCapabilitiesRoleNote =>
      'Managers and owners can already do all of this.';

  @override
  String get posDiscountFullCompDenied =>
      'You don\'t have permission to make an order free - ask a manager.';

  @override
  String get posDiscountExceedsOrderTotal =>
      'That discount is more than the order total.';

  @override
  String get activityLogCapApplyFullComp => 'Make an order free';

  @override
  String get activityLogDeniedFullCompPermissionRequired =>
      'Making an order free needs permission';

  @override
  String get activityLogDeniedDiscountExceedsOrderTotal =>
      'The discount was more than the order total';

  @override
  String get activityLogFieldResultingChargeState => 'Would leave';

  @override
  String get activityLogTitleDiscountDenied => 'Discount refused';

  @override
  String get posOrdersCenterTitle => 'Orders';

  @override
  String get posOrdersSectionOpen => 'Open';

  @override
  String get posOrdersSectionNeedsPayment => 'Needs payment';

  @override
  String get posOrdersSectionCompleted => 'Completed recently';

  @override
  String get posOrdersSectionAll => 'All recent';

  @override
  String get posOrdersSearchHint => 'Search order code';

  @override
  String get posOrdersSearchClear => 'Clear search';

  @override
  String get posOrdersSearchEmpty => 'No order matches this search';

  @override
  String get posOrdersEmptyOpen => 'No open orders right now';

  @override
  String get posOrdersEmptyNeedsPayment => 'No orders currently need payment';

  @override
  String get posOrdersEmptyCompleted =>
      'No recently completed or closed orders';

  @override
  String get posOrdersEmptyOffline => 'No saved orders are available offline';

  @override
  String get posOrdersLoadMore => 'Load more';

  @override
  String get posOrdersRefresh => 'Refresh orders';

  @override
  String get posOrdersSyncing => 'Syncing...';

  @override
  String posOrdersLastUpdated(String time) {
    return 'Last updated $time';
  }

  @override
  String get posOrdersOffline => 'Offline - showing saved data';

  @override
  String get posOrdersSortNewest => 'Newest first';

  @override
  String get posOrdersSortOldest => 'Oldest first';

  @override
  String get posOrdersFilterStatus => 'Status';

  @override
  String get posOrdersFilterSettlement => 'Payment';

  @override
  String get posOrdersSettlementAll => 'All';

  @override
  String get posOrdersSettlementUnpaid => 'Needs payment';

  @override
  String get posOrdersSettlementPaid => 'Paid';

  @override
  String get posOrdersSettlementNoCharge => 'No charge';

  @override
  String get posOrdersPendingPayment => 'Payment syncing...';

  @override
  String get posOrdersPendingDiscount => 'Discount syncing...';

  @override
  String get posOrdersPendingCancellation => 'Cancellation syncing...';

  @override
  String get posOrdersOtherTill => 'Another till';

  @override
  String get posOrdersStatusSubmitted => 'Submitted';

  @override
  String get posOrdersStatusAccepted => 'Accepted';

  @override
  String get posOrdersStatusPreparing => 'Preparing';

  @override
  String get posOrdersStatusReady => 'Ready';

  @override
  String get posOrdersStatusServed => 'Served';

  @override
  String get posOrdersStatusCompleted => 'Completed';

  @override
  String get posOrdersStatusCancelled => 'Cancelled';

  @override
  String get posOrdersStatusVoided => 'Voided';

  @override
  String get posOrdersConflictRefreshed =>
      'This order changed on another device. It has been refreshed - check it and try again.';

  @override
  String get posOrdersConflictClose => 'Close and reopen';

  @override
  String get posOrdersStatusPickedUp => 'Picked up';

  @override
  String get posMenuItemSoldOut => 'Sold out';

  @override
  String get posMenuItemPaused => 'Temporarily unavailable';

  @override
  String posSyncItemUnavailable(String items) {
    return 'Not available right now: $items. Re-enter the order without these items.';
  }

  @override
  String get posSyncTableUnavailable =>
      'The selected table is no longer available. Pick another table and re-enter the order.';

  @override
  String get posOrdersFilterTypeAll => 'All types';

  @override
  String get posMoveTableAction => 'Move table';

  @override
  String get posMoveTableTitle => 'Move to another table';

  @override
  String posMoveTableCurrent(String table) {
    return 'Current table: $table';
  }

  @override
  String get posMoveTableNoTable => 'No table assigned yet';

  @override
  String get posMoveTableConfirm => 'Move';

  @override
  String posMoveTableMoved(String table) {
    return 'Moved to $table';
  }

  @override
  String get posMoveTableConflict =>
      'This order changed on another device. Close and act again from the updated order.';

  @override
  String get posMoveTableNotMovable => 'This order can no longer be moved.';

  @override
  String get posMoveTableTableUnavailable =>
      'That table is no longer available. Pick another.';

  @override
  String get posMoveTablePermissionDenied =>
      'You don’t have permission to move this order.';

  @override
  String get posMoveTableFailed =>
      'Couldn’t move the table. Check the connection and try again.';

  @override
  String posTableOpenOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open orders',
      one: '1 open order',
    );
    return '$_temp0';
  }

  @override
  String get kdsServedAction => 'Served';

  @override
  String get kdsPickedUpAction => 'Picked up';

  @override
  String get ordersStatusPickedUp => 'Picked up';

  @override
  String get menuAvailabilityLabel => 'Availability';

  @override
  String get menuAvailabilityAvailable => 'Available';

  @override
  String get menuAvailabilityUnavailable => 'Unavailable';

  @override
  String get menuAvailabilitySoldOut => 'Sold out';

  @override
  String get menuAvailabilityPaused => 'Paused';

  @override
  String get menuAvailabilityUpdated => 'Availability updated';

  @override
  String get menuAvailabilityUpdateFailed => 'Couldn’t update availability';

  @override
  String get menuAvailabilityNeedsBranch =>
      'Select a branch to manage availability';

  @override
  String tablesOpenOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open orders',
      one: '1 open order',
      zero: 'No open orders',
    );
    return '$_temp0';
  }

  @override
  String get activityLogTitleMenuAvailabilityChanged =>
      'Menu item availability changed';

  @override
  String get activityLogTitleMenuAvailabilityDenied =>
      'Menu availability change denied';

  @override
  String get activityLogTitleOrderTableMoved => 'Order moved to another table';

  @override
  String get activityLogTitleOrderTableMoveDenied => 'Table move denied';

  @override
  String get activityLogTitleTableStatusChanged => 'Table status changed';

  @override
  String get activityLogTitleTableStatusDenied => 'Table status change denied';

  @override
  String get activityLogTitleTablesLinked => 'Tables linked';

  @override
  String get activityLogTitleTableLinkDenied => 'Table link denied';

  @override
  String get activityLogTitleTablesUnlinked => 'Tables unlinked';

  @override
  String get activityLogTitleTableUnlinkDenied => 'Table unlink denied';

  @override
  String get activityLogFieldFromStatus => 'From status';

  @override
  String get activityLogFieldToStatus => 'To status';

  @override
  String get activityLogFieldGroupLabel => 'Linked tables';

  @override
  String get activityLogFieldVoidedFromStatus => 'Status when canceled';

  @override
  String get activityLogFieldDeviceType => 'Device type';

  @override
  String get activityLogFieldKitchenAckRequired =>
      'Kitchen acknowledgement required';

  @override
  String get activityLogFieldAvailability => 'Availability';

  @override
  String get activityLogFieldAvailabilityReason => 'Reason';

  @override
  String get activityLogFieldItemName => 'Item';

  @override
  String get activityLogFieldTableLabel => 'Table';

  @override
  String get activityLogFieldFromTable => 'From table';

  @override
  String get activityLogFieldToTable => 'To table';

  @override
  String get activityLogDeniedTakeawayOrder =>
      'Takeaway orders don’t use tables';

  @override
  String get activityLogDeniedOrderNotMovable =>
      'The order can no longer be moved';

  @override
  String get activityLogDeniedTableNotAvailable => 'The table isn’t available';

  @override
  String get activityLogDeniedPermission => 'Not permitted for this role';
}
