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
}
