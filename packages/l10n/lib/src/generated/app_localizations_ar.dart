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
  String get kdsAcknowledgeAction => 'استلام';

  @override
  String get kdsStartAction => 'بدء التحضير';

  @override
  String get kdsReadyAction => 'تم التحضير';

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

  @override
  String get dashboardOverviewHeading => 'نظرة عامة لليوم';

  @override
  String get dashboardTodaySales => 'مبيعات اليوم';

  @override
  String get dashboardOrders => 'الطلبات';

  @override
  String get dashboardAvgOrderValue => 'متوسط قيمة الطلب';

  @override
  String get dashboardCompletedOrders => 'الطلبات المكتملة';

  @override
  String get dashboardOpenOrders => 'الطلبات المفتوحة';

  @override
  String get dashboardDailySummary => 'ملخص اليوم';

  @override
  String get dashboardNetSales => 'صافي المبيعات';

  @override
  String get dashboardDiscounts => 'الخصومات';

  @override
  String get dashboardVoids => 'الإلغاءات';

  @override
  String get dashboardCashCollected => 'النقد المُحصَّل';

  @override
  String get dashboardCashVariance => 'فرق النقدية';

  @override
  String get dashboardShiftStatus => 'الوردية';

  @override
  String get dashboardSalesByBranch => 'المبيعات حسب الفرع';

  @override
  String get dashboardTopItems => 'الأصناف الأكثر مبيعًا';

  @override
  String get dashboardDemoNotice => 'بيانات تجريبية — ليست من خادم مباشر.';

  @override
  String get authLoadingAccount => 'جارٍ تحميل الحساب…';

  @override
  String get authSignInRequired => 'تسجيل الدخول مطلوب';

  @override
  String get authContinue => 'متابعة';

  @override
  String get authChooseLocation => 'اختر الموقع';

  @override
  String get authNoAccess => 'لا يوجد وصول نشط';

  @override
  String get authWrongRole => 'لا يمكن لهذا الدور استخدام هذا التطبيق';

  @override
  String get authAccessDenied => 'تم رفض الوصول إلى الحساب';

  @override
  String get authError => 'حدث خطأ ما';

  @override
  String get authTryAgain => 'حاول مرة أخرى';

  @override
  String get authSignOut => 'تسجيل الخروج';

  @override
  String get authPlatformAdmin => 'مشرف المنصة';

  @override
  String get authOrganization => 'المؤسسة';

  @override
  String get authRestaurant => 'المطعم';

  @override
  String get authBranch => 'الفرع';

  @override
  String get authRole => 'الدور';

  @override
  String get authRoleOwner => 'المالك';

  @override
  String get authRoleRestaurantOwner => 'مالك المطعم';

  @override
  String get authRoleManager => 'المدير';

  @override
  String get authRoleCashier => 'أمين الصندوق';

  @override
  String get authRoleKitchenStaff => 'طاقم المطبخ';

  @override
  String get authRoleAccountant => 'المحاسب';

  @override
  String get authComingSoon => 'قريبًا';
}
