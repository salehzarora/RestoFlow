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
  String get localeEnglish => 'English';

  @override
  String get localeArabic => 'Arabic';

  @override
  String get localeHebrew => 'Hebrew';

  @override
  String get kdsEmptyState => 'No active tickets';

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
  String get posDemoOrderNotice =>
      'Demo order — not sent to a backend, kitchen, or printer.';

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
  String get posShiftDemoNote => 'Demo shift — not synced';

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
  String get menuImageDeferredTitle => 'Image upload coming soon';

  @override
  String get menuImageDeferredBody =>
      'Showing and uploading item photos needs a backend image record (a planned follow-up). The upload path and validation are already built.';

  @override
  String get menuErrorRequired => 'Required';

  @override
  String get menuErrorAmount => 'Enter a valid amount';

  @override
  String get menuErrorNegativePrice => 'Cannot be negative';

  @override
  String get menuErrorCurrency => 'Use a 3-letter code (e.g. USD)';

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
  String get adminErrCurrency => 'Use a 3-letter code (e.g. USD)';

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
}
