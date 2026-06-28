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
  String get posOrderTypeLabel => 'نوع الطلب';

  @override
  String get posOrderTypeDineIn => 'تناول في المطعم';

  @override
  String get posOrderTypeTakeaway => 'سفري';

  @override
  String get posTableLabel => 'طاولة';

  @override
  String get posAssignTable => 'تعيين طاولة';

  @override
  String get posChangeTable => 'تغيير الطاولة';

  @override
  String get posClearTableAssignment => 'إزالة الطاولة';

  @override
  String get posTableRequiredWarning =>
      'طلبات تناول الطعام في المطعم تتطلب طاولة';

  @override
  String get posTableNotNeeded => 'لا حاجة لطاولة للطلبات السفري';

  @override
  String get posTablePickerTitle => 'اختر طاولة';

  @override
  String get posTableStatusAvailable => 'متاحة';

  @override
  String get posTableStatusOccupied => 'مشغولة';

  @override
  String get posTableStatusBlocked => 'خارج الخدمة';

  @override
  String posTableSeats(int count) {
    return '$count مقاعد';
  }

  @override
  String get posTablesDemoNotice => 'طاولات تجريبية — غير محمّلة من خادم.';

  @override
  String get posTablesEmpty => 'لا توجد طاولات لعرضها';

  @override
  String get posTablesError => 'تعذّر تحميل الطاولات';

  @override
  String get posTableStatusSelected => 'محدد';

  @override
  String get posTableAreaMain => 'صالة الطعام الرئيسية';

  @override
  String get posTableAreaPatio => 'الفناء';

  @override
  String get posTablesAisleLabel => 'ممر';

  @override
  String get posTablesEdgeEntrance => 'المدخل';

  @override
  String get posTablesEdgeCounter => 'الكاونتر';

  @override
  String get posTablesLayoutEditorHint =>
      'مواضع الطاولات تجريبية فقط — محرّر التخطيط قادم لاحقًا.';

  @override
  String posTableSelectedSemantic(String label) {
    return '$label، محدد';
  }

  @override
  String get posSyncSectionTitle => 'حالة المزامنة';

  @override
  String get posSyncStatePending => 'بانتظار المزامنة';

  @override
  String get posSyncStateSending => 'جارٍ الإرسال…';

  @override
  String get posSyncStateSynced => 'تمت المزامنة';

  @override
  String get posSyncStateFailed => 'فشلت المزامنة';

  @override
  String get posSyncStoredLocally =>
      'مخزَّن محليًا — بانتظار المزامنة مع الخادم';

  @override
  String get posSyncDemoNotice => 'مزامنة تجريبية — لم تُرسل إلى خادم حقيقي';

  @override
  String get posSyncNow => 'المزامنة الآن (تجريبي)';

  @override
  String get posSyncRetry => 'إعادة المحاولة';

  @override
  String get posOutboxRefLabel => 'مرجع الصندوق الصادر';

  @override
  String get posSubmitFailed => 'تعذّر إدراج الطلب — يرجى المحاولة مرة أخرى';

  @override
  String posSyncPendingCount(int count) {
    return '$count بانتظار المزامنة';
  }

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

  @override
  String get dashboardNavSettings => 'الإعدادات';

  @override
  String get dashboardNavUsers => 'المستخدمون';

  @override
  String get dashboardNavDevices => 'الأجهزة';

  @override
  String get adminDemoBanner =>
      'بيانات تجريبية — الإجراءات تتبع عقود الواجهة الخلفية RF-112 لكنها تعمل على مخزن في الذاكرة على هذا الجهاز؛ لا شيء يُحفظ على الخادم بعد.';

  @override
  String get adminPermissionDeniedTitle => 'ليس لديك صلاحية';

  @override
  String get adminPermissionDeniedBody =>
      'لا يمكن لدورك تنفيذ هذا الإجراء في هذا النطاق. حارس رتبة الأدوار يقصر الإدارة على الأدوار الأعلى.';

  @override
  String get adminStateErrorTitle => 'حدث خطأ ما';

  @override
  String get adminStateErrorBody => 'تعذّر تحميل هذا. يرجى المحاولة مرة أخرى.';

  @override
  String get adminRetry => 'إعادة المحاولة';

  @override
  String get adminConflictMessage => 'هذا الإجراء غير مسموح في الحالة الحالية.';

  @override
  String get adminActionProblem =>
      'تعذّر إتمام الإجراء — يرجى المحاولة مرة أخرى.';

  @override
  String get adminErrCurrency => 'استخدم رمزًا من 3 أحرف (مثل USD)';

  @override
  String get adminErrCountry => 'استخدم رمزًا من حرفين (مثل US)';

  @override
  String get adminErrName => 'مطلوب';

  @override
  String get adminErrEmail => 'أدخل بريدًا إلكترونيًا صالحًا';

  @override
  String get adminErrStatus => 'اختر حالة صالحة';

  @override
  String get adminErrRequired => 'مطلوب';

  @override
  String get adminCopy => 'نسخ';

  @override
  String get adminShownOnce =>
      'يُعرض مرة واحدة — انسخه الآن. لن تتمكن من رؤيته مجددًا.';

  @override
  String get adminDone => 'تم';

  @override
  String get adminSavedSnack => 'تم الحفظ';

  @override
  String get adminDevStatusNone => 'غير مقترن';

  @override
  String get adminDevStatusCodeIssued => 'تم إصدار الرمز';

  @override
  String get adminDevStatusPending => 'بانتظار الموافقة';

  @override
  String get adminDevStatusPaired => 'مقترن';

  @override
  String get adminDevStatusActive => 'نشط';

  @override
  String get adminDevStatusSuspended => 'موقوف';

  @override
  String get adminDevStatusRevoked => 'مُلغى';

  @override
  String get adminDevStatusCodeExpired => 'انتهت صلاحية الرمز';

  @override
  String get adminDevStatusRejected => 'مرفوض';

  @override
  String get adminSettingsTitle => 'الإعدادات';

  @override
  String get adminSettingsSubtitle =>
      'إعدادات المؤسسة والمطعم والفرع لهذا النطاق.';

  @override
  String get adminSettingsReadOnly =>
      'يمكن لدورك عرض هذه الإعدادات لكن لا يمكن تعديلها.';

  @override
  String get adminSectionOrg => 'المؤسسة';

  @override
  String get adminSectionRestaurant => 'المطعم';

  @override
  String get adminSectionBranch => 'الفرع';

  @override
  String get adminFieldDefaultCurrency => 'العملة الافتراضية';

  @override
  String get adminFieldCountryCode => 'رمز الدولة';

  @override
  String get adminFieldStatus => 'الحالة';

  @override
  String get adminFieldName => 'الاسم';

  @override
  String get adminFieldCurrencyOverride => 'تجاوز العملة';

  @override
  String get adminFieldTimezone => 'المنطقة الزمنية';

  @override
  String get adminFieldAddress => 'العنوان';

  @override
  String get adminFieldReceiptPrefix => 'بادئة الإيصال';

  @override
  String get adminStatusActive => 'نشط';

  @override
  String get adminStatusSuspended => 'موقوف';

  @override
  String get adminOptional => 'اختياري';

  @override
  String get adminSave => 'حفظ';

  @override
  String get adminCancel => 'إلغاء';

  @override
  String get adminUsersTitle => 'المستخدمون والأدوار';

  @override
  String get adminUsersSubtitle =>
      'أدر من يمكنه الوصول إلى هذه المؤسسة وما يمكنه فعله.';

  @override
  String get adminGrantUser => 'منح وصول';

  @override
  String get adminGrantDialogTitle => 'منح وصول';

  @override
  String get adminGrant => 'منح';

  @override
  String get adminChangeRole => 'تغيير الدور';

  @override
  String get adminChangeRoleTitle => 'تغيير الدور';

  @override
  String get adminUpdate => 'تحديث';

  @override
  String get adminRevoke => 'إلغاء الوصول';

  @override
  String get adminComingSoon => 'قريبًا';

  @override
  String get adminRoleGuardNote =>
      'يمكنك إسناد أدوار أقل من دورك — حارس رتبة الأدوار يمنع منح دورك نفسه أو أعلى.';

  @override
  String get adminSelf => 'أنت';

  @override
  String get adminStatusRevoked => 'مُلغى';

  @override
  String get adminFieldDisplayName => 'الاسم المعروض';

  @override
  String get adminFieldEmail => 'البريد الإلكتروني';

  @override
  String get adminFieldRole => 'الدور';

  @override
  String get adminUsersEmptyTitle => 'لا يوجد أعضاء بعد';

  @override
  String get adminUsersEmptyBody =>
      'امنح وصولًا لإضافة أول عضو إلى هذه المؤسسة.';

  @override
  String get adminUserGranted => 'تم منح الوصول';

  @override
  String get adminRoleUpdated => 'تم تحديث الدور';

  @override
  String get adminDevicesTitle => 'الأجهزة';

  @override
  String get adminDevicesSubtitle =>
      'زوّد واقترن أجهزة نقاط البيع وشاشات المطبخ لهذا الفرع.';

  @override
  String get adminCreateDevice => 'إضافة جهاز';

  @override
  String get adminCreateDeviceTitle => 'إضافة جهاز';

  @override
  String get adminCreate => 'إنشاء';

  @override
  String get adminFieldDeviceLabel => 'اسم الجهاز';

  @override
  String get adminFieldDeviceType => 'نوع الجهاز';

  @override
  String get adminDeviceTypePos => 'نقطة بيع';

  @override
  String get adminDeviceTypeKds => 'شاشة مطبخ';

  @override
  String get adminLifecycleNote =>
      'دورة الحياة: أصدر رمزًا، يستردّه الجهاز (قيد الانتظار)، ثم الموافقة (مقترن)، ثم التفعيل (نشط)، ثم بدء جلسة. الموافقة والتفعيل خطوتان منفصلتان؛ لا يمكن للجهاز القفز من قيد الانتظار إلى نشط.';

  @override
  String get adminIssueCode => 'إصدار رمز';

  @override
  String get adminRedeem => 'استرداد الرمز';

  @override
  String get adminApprove => 'موافقة';

  @override
  String get adminActivate => 'تفعيل';

  @override
  String get adminStartSession => 'بدء جلسة';

  @override
  String get adminDevicesEmptyTitle => 'لا توجد أجهزة بعد';

  @override
  String get adminDevicesEmptyBody =>
      'أضف جهازًا لبدء عملية التسجيل والاقتران.';

  @override
  String get adminCodeIssuedTitle => 'رمز التسجيل';

  @override
  String get adminCodeIssuedSubtitle =>
      'أدخل هذا الرمز على الجهاز لبدء الاقتران.';

  @override
  String get adminCodeExpiresNote =>
      'تنتهي صلاحية هذا الرمز قريبًا ويمكن استرداده مرة واحدة.';

  @override
  String get adminTokenStartedTitle => 'بدأت جلسة الجهاز';

  @override
  String get adminTokenStartedSubtitle =>
      'حمّل رمز الجلسة هذا على الجهاز للمصادقة عليه.';

  @override
  String get adminSessionOpen => 'الجلسة نشطة';

  @override
  String get adminDeviceCreated => 'تمت إضافة الجهاز';

  @override
  String get adminDeviceUpdated => 'تم تحديث الجهاز';
}
