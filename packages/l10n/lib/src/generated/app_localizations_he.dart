// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get appName => 'רסטופלו';

  @override
  String get posAppTitle => 'רסטופלו - קופה';

  @override
  String get kdsAppTitle => 'רסטופלו - מסך מטבח';

  @override
  String get dashboardAppTitle => 'רסטופלו - לוח בקרה';

  @override
  String get adminAppTitle => 'רסטופלו - ניהול';

  @override
  String get welcomeMessage => 'ברוכים הבאים לרסטופלו';

  @override
  String get localeEnglish => 'אנגלית';

  @override
  String get localeArabic => 'ערבית';

  @override
  String get localeHebrew => 'עברית';

  @override
  String get kdsEmptyState => 'אין כרטיסים פעילים';

  @override
  String get kdsBumpAction => 'סיום';

  @override
  String get kdsRecallAction => 'שחזור';

  @override
  String get kdsStationLabel => 'עמדה';

  @override
  String get kdsTicketLabel => 'כרטיס';

  @override
  String get kdsLoadingState => 'טוען כרטיסים…';

  @override
  String get kdsErrorState => 'לא ניתן לטעון כרטיסים';

  @override
  String get kdsReauthRequired => 'נדרשת התחברות מחדש';

  @override
  String get posMenuHeading => 'תפריט';

  @override
  String get posCartTitle => 'עגלה';

  @override
  String get posCartEmpty => 'העגלה ריקה';

  @override
  String get posCartSubtotal => 'סכום ביניים';

  @override
  String get posAddToCart => 'הוספה';

  @override
  String get posClearCart => 'ניקוי';

  @override
  String get posRemoveItem => 'הסרה';

  @override
  String get posIncreaseQuantity => 'הגדלת כמות';

  @override
  String get posDecreaseQuantity => 'הקטנת כמות';

  @override
  String get posCategoryAll => 'הכול';

  @override
  String get posSendOrder => 'שליחת הזמנה';

  @override
  String get posDemoOrderNotice =>
      'הזמנת הדגמה — לא נשלחה לשרת, למטבח או למדפסת.';

  @override
  String get posOrderSubmittedTitle => 'ההזמנה נשלחה';

  @override
  String get posOrderNumberLabel => 'מספר הזמנה';

  @override
  String get posOrderStatusSubmitted => 'נשלחה';

  @override
  String get posNewOrder => 'הזמנה חדשה';
}
