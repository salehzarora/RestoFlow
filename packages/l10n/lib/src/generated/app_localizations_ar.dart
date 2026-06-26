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

  @override
  String get dashboardNavOverview => 'نظرة عامة';

  @override
  String get dashboardNavMenu => 'القائمة';

  @override
  String get menuManagementTitle => 'إدارة القائمة';

  @override
  String get menuDemoBanner =>
      'بيانات تجريبية — التغييرات تبقى على هذا الجهاز ولا تُحفظ على الخادم بعد.';

  @override
  String get menuCategoriesHeading => 'الفئات';

  @override
  String get menuItemsHeading => 'العناصر';

  @override
  String get menuSelectCategoryHint => 'اختر فئة لعرض عناصرها.';

  @override
  String get menuEmptyCategories => 'لا توجد فئات بعد.';

  @override
  String get menuEmptyItems => 'لا توجد عناصر في هذه الفئة بعد.';

  @override
  String get menuLoadError => 'تعذّر تحميل القائمة.';

  @override
  String get menuRetry => 'إعادة المحاولة';

  @override
  String menuItemCount(int count) {
    return '$count عناصر';
  }

  @override
  String get menuAddCategory => 'إضافة فئة';

  @override
  String get menuAddItem => 'إضافة عنصر';

  @override
  String get menuAddSize => 'إضافة حجم';

  @override
  String get menuAddVariant => 'إضافة نوع';

  @override
  String get menuAddModifier => 'إضافة مُعدِّل';

  @override
  String get menuAddOption => 'إضافة خيار';

  @override
  String get menuEditTitle => 'تعديل';

  @override
  String get menuSaveAction => 'حفظ';

  @override
  String get menuCancelAction => 'إلغاء';

  @override
  String get menuEditAction => 'تعديل';

  @override
  String get menuDeleteAction => 'حذف';

  @override
  String get menuNameLabel => 'الاسم';

  @override
  String get menuDescriptionLabel => 'الوصف (اختياري)';

  @override
  String get menuPriceLabel => 'السعر الأساسي';

  @override
  String get menuPriceDeltaLabel => 'تغيير السعر';

  @override
  String get menuCurrencyLabel => 'العملة';

  @override
  String get menuCategoryFieldLabel => 'الفئة';

  @override
  String get menuDisplayOrderLabel => 'ترتيب العرض';

  @override
  String get menuActiveLabel => 'نشط';

  @override
  String get menuSelectionTypeLabel => 'الاختيار';

  @override
  String get menuSelectionSingle => 'مفرد';

  @override
  String get menuSelectionMultiple => 'متعدد';

  @override
  String get menuMinSelectLabel => 'الحد الأدنى';

  @override
  String get menuMaxSelectLabel => 'الحد الأقصى (اختياري)';

  @override
  String get menuRequiredLabel => 'مطلوب';

  @override
  String get menuSizesHeading => 'الأحجام';

  @override
  String get menuVariantsHeading => 'الأنواع';

  @override
  String get menuModifiersHeading => 'المُعدِّلات';

  @override
  String get menuOptionsHeading => 'الخيارات';

  @override
  String get menuDeleteConfirmTitle => 'حذف هذا العنصر؟';

  @override
  String get menuDeleteConfirmBody =>
      'سيُخفى من القائمة. يمكنك استعادته لاحقًا.';

  @override
  String get menuConfirmDelete => 'حذف';

  @override
  String get menuInactiveBadge => 'غير نشط';

  @override
  String get menuGlobalBadge => 'كل الفروع';

  @override
  String get menuBranchBadge => 'هذا الفرع';

  @override
  String get menuImageHeading => 'صورة العنصر';

  @override
  String get menuImageDeferredTitle => 'رفع الصور قريبًا';

  @override
  String get menuImageDeferredBody =>
      'عرض ورفع صور العناصر يتطلب سجلًا خلفيًا للصور (متابعة مخطط لها). مسار الرفع والتحقق جاهزان بالفعل.';

  @override
  String get menuErrorRequired => 'مطلوب';

  @override
  String get menuErrorAmount => 'أدخل مبلغًا صالحًا';

  @override
  String get menuErrorNegativePrice => 'لا يمكن أن يكون سالبًا';

  @override
  String get menuErrorCurrency => 'استخدم رمزًا من 3 أحرف (مثل USD)';

  @override
  String get menuErrorSelectionType => 'اختر مفرد أو متعدد';

  @override
  String get menuErrorMaxLessThanMin => 'يجب ألا يقل عن الحد الأدنى';

  @override
  String get menuWritePermissionDenied =>
      'لا يمكنك تغيير القائمة في هذا النطاق.';

  @override
  String get menuWriteProblem => 'تعذّر الحفظ — يرجى المحاولة مرة أخرى.';

  @override
  String get menuSavedSnack => 'تم الحفظ';

  @override
  String get menuDeletedSnack => 'تم الحذف';

  @override
  String get menuManagementSubtitle =>
      'نظّم الفئات والعناصر والأحجام والمُعدِّلات والأسعار.';

  @override
  String get menuSearchHint => 'ابحث في القائمة';

  @override
  String get menuFilterAll => 'الكل';

  @override
  String get menuFilterActive => 'نشط';

  @override
  String get menuFilterInactive => 'غير نشط';

  @override
  String get menuEmptyCategoriesBody => 'أنشئ أول فئة لبدء بناء القائمة.';

  @override
  String get menuEmptyItemsBody => 'أضف عنصرًا إلى هذه الفئة للبدء.';

  @override
  String get menuLoadErrorBody => 'حدث خطأ أثناء تحميل القائمة.';

  @override
  String get menuImageEmptyHint => 'لا توجد صورة بعد';

  @override
  String get menuComingSoonBadge => 'قريبًا';

  @override
  String get menuItemDetailsSection => 'التفاصيل';

  @override
  String get menuNoResults => 'لا توجد نتائج';

  @override
  String get menuNoResultsBody => 'جرّب بحثًا أو تصفية مختلفة.';

  @override
  String get menuScopeUnavailableTitle => 'القائمة غير متاحة لهذا الوصول';

  @override
  String get menuScopeUnavailableBody =>
      'هذا وصول على مستوى المؤسسة دون اختيار مطعم. افتح إدارة القائمة من مطعم أو فرع محدد.';
}
