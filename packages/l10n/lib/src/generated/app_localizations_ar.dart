// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'ريستوفلو';

  @override
  String get posAppTitle => 'ريستوفلو - نقطة البيع';

  @override
  String get kdsAppTitle => 'ريستوفلو - شاشة المطبخ';

  @override
  String get dashboardAppTitle => 'ريستوفلو - لوحة التحكم';

  @override
  String get adminAppTitle => 'ريستوفلو - الإدارة';

  @override
  String get welcomeMessage => 'مرحبًا بك في ريستوفلو';

  @override
  String get localeEnglish => 'الإنجليزية';

  @override
  String get localeArabic => 'العربية';

  @override
  String get localeHebrew => 'العبرية';

  @override
  String get kdsEmptyState => 'لا توجد تذاكر نشطة';

  @override
  String get kdsBumpAction => 'إنهاء';

  @override
  String get kdsRecallAction => 'استرجاع';

  @override
  String get kdsStationLabel => 'محطة';

  @override
  String get kdsTicketLabel => 'تذكرة';

  @override
  String get kdsLoadingState => 'جارٍ تحميل التذاكر…';

  @override
  String get kdsErrorState => 'تعذّر تحميل التذاكر';

  @override
  String get kdsReauthRequired => 'تسجيل الدخول مطلوب';

  @override
  String get posMenuHeading => 'القائمة';

  @override
  String get posCartTitle => 'السلة';

  @override
  String get posCartEmpty => 'سلتك فارغة';

  @override
  String get posCartSubtotal => 'المجموع الفرعي';

  @override
  String get posAddToCart => 'إضافة';

  @override
  String get posClearCart => 'مسح';

  @override
  String get posRemoveItem => 'إزالة';

  @override
  String get posIncreaseQuantity => 'زيادة الكمية';

  @override
  String get posDecreaseQuantity => 'إنقاص الكمية';

  @override
  String get posCategoryAll => 'الكل';

  @override
  String get posSendOrder => 'إرسال الطلب';

  @override
  String get posDemoOrderNotice =>
      'طلب تجريبي — لم يُرسَل إلى خادم أو مطبخ أو طابعة.';

  @override
  String get posOrderSubmittedTitle => 'تم إرسال الطلب';

  @override
  String get posOrderNumberLabel => 'رقم الطلب';

  @override
  String get posOrderStatusSubmitted => 'تم الإرسال';

  @override
  String get posNewOrder => 'طلب جديد';
}
