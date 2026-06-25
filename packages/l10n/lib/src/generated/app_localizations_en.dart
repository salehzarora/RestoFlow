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
}
