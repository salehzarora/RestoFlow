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
  String get adminOverviewTitle => 'نظرة عامة على المنصة';

  @override
  String get adminOverviewAsOf => 'حتى';

  @override
  String get adminDemoDataTag => 'بيانات تجريبية';

  @override
  String get adminDemoDataNotice =>
      'بيانات منصة تجريبية — محسوبة محليًا على هذا الجهاز، وغير متزامنة مع خادم.';

  @override
  String get adminRefresh => 'تحديث';

  @override
  String get adminLoading => 'جارٍ تحميل بيانات المنصة…';

  @override
  String get adminError => 'تعذّر تحميل بيانات المنصة.';

  @override
  String get adminEmpty => 'لا توجد بيانات منصة بعد.';

  @override
  String get adminActiveLabel => 'نشط';

  @override
  String get adminKpiOrganizations => 'المؤسسات';

  @override
  String get adminKpiRestaurants => 'المطاعم';

  @override
  String get adminKpiBranches => 'الفروع';

  @override
  String get adminKpiActiveBranches => 'الفروع النشطة';

  @override
  String get adminKpiDevices => 'الأجهزة';

  @override
  String get adminKpiAlerts => 'التنبيهات المفتوحة';

  @override
  String get adminKpiOrdersToday => 'طلبات اليوم';

  @override
  String get adminOrganizationsHeading => 'المؤسسات';

  @override
  String get adminBranchHealthHeading => 'حالة الفروع';

  @override
  String get adminRecentActivityHeading => 'النشاط الأخير';

  @override
  String get adminCreatedLabel => 'أُنشئت';

  @override
  String get adminLastActivityLabel => 'آخر نشاط';

  @override
  String get adminOrdersTodayShort => 'طلبات اليوم';

  @override
  String get adminWarningChip => 'تحتاج إلى انتباه';

  @override
  String get adminRealModeNotice =>
      'بيانات منصة مباشرة — للقراءة فقط ومحدودة. بعض مؤشرات التشغيل غير متوفرة هنا بعد، كما أن التحقق الثنائي (MFA) لإدارة المنصة وإدارة الصلاحيات ليسا ضمن هذا الإصدار.';

  @override
  String get adminLiveLimitedTag => 'مباشر · محدود';

  @override
  String get adminNotConfiguredTitle => 'إدارة المنصة غير مُهيأة';

  @override
  String get adminNotConfiguredBody =>
      'الوضع الحقيقي مُحدَّد لكن اتصال Supabase غير مُهيأ، لذا تعذّر تحميل أي بيانات للمنصة. اضبط عنوان Supabase ومفتاح anon، أو شغّل الوضع التجريبي.';

  @override
  String get adminGateTitle => 'لوحة إدارة المنصة';

  @override
  String get adminGateNotOwner =>
      'هذه لوحة إدارة المنصة، وليست لوحة صاحب المطعم.';

  @override
  String get adminGateUseDashboard => 'استخدم Dashboard لإدارة المطعم.';

  @override
  String get adminGateNotAdminAccount => 'هذا الحساب ليس مشرف منصة.';

  @override
  String get adminGateProvisionHint =>
      'يُمنح وصول مشرف المنصة يدويًا من مشغّل المنصة — راجع docs/LOCAL_RUNBOOK.md.';

  @override
  String get adminGateOpenDashboard => 'فتح لوحة المطعم';

  @override
  String get adminAccessDeniedTitle => 'تم رفض الوصول إلى إدارة المنصة';

  @override
  String get adminAccessDeniedBody =>
      'يلزم وجود صلاحية فعّالة لإدارة المنصة وتسجيل دخول بالتحقق متعدد العوامل (MFA) لعرض بيانات المنصة المباشرة. تسجيل الدخول المعزز وإدارة الصلاحيات غير متوفرين في هذا الإصدار بعد.';

  @override
  String get localeEnglish => 'الإنجليزية';

  @override
  String get localeArabic => 'العربية';

  @override
  String get localeHebrew => 'العبرية';

  @override
  String get kdsEmptyState => 'لا توجد تذاكر نشطة';

  @override
  String get kdsColumnEmpty => 'لا توجد تذاكر';

  @override
  String get kdsStaleBanner => 'غير متصل — تُعرض آخر التذاكر المتزامنة';

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
  String get kdsDemoFeedBanner => 'تغذية مطبخ تجريبية — غير متزامنة مع خادم';

  @override
  String get kdsColNew => 'جديد';

  @override
  String get kdsColPreparing => 'قيد التحضير';

  @override
  String get kdsColReady => 'جاهز';

  @override
  String get kdsColCleared => 'تم الإنهاء';

  @override
  String get kdsCompleteAction => 'إنهاء';

  @override
  String get kdsNoteLabel => 'ملاحظة';

  @override
  String kdsElapsedMinutes(int minutes) {
    return '$minutes د';
  }

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
  String posAddToCartWithTotal(String total) {
    return 'إضافة · $total';
  }

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
  String get posSendNeedsTableHint => 'عيّن طاولة لإرسال طلب التناول في المطعم';

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
  String get posPayCash => 'الدفع نقدًا';

  @override
  String get posPaymentTitle => 'دفع نقدي';

  @override
  String get posAmountDue => 'المبلغ المستحق';

  @override
  String get posCashReceived => 'النقد المستلم';

  @override
  String get posCashExact => 'بالضبط';

  @override
  String get posChangeDue => 'الباقي';

  @override
  String get posConfirmPayment => 'تأكيد الدفع';

  @override
  String get posCashInvalid => 'أدخل مبلغًا صالحًا';

  @override
  String get posCashInsufficient => 'يجب أن يغطي النقد المستلم المبلغ المستحق';

  @override
  String get posPaidChip => 'مدفوع';

  @override
  String get posPaymentMethodLabel => 'طريقة الدفع';

  @override
  String get posPaymentMethodCash => 'نقدًا';

  @override
  String get posPaidAtLabel => 'وقت الدفع';

  @override
  String get posReceiptTitle => 'إيصال';

  @override
  String get posReceiptNumberLabel => 'رقم الإيصال';

  @override
  String get posReceiptTotal => 'الإجمالي';

  @override
  String get posReceiptProvisionalNote =>
      'مؤقّت — تتم مطابقته مع إيصال الخادم عند المزامنة';

  @override
  String get posReceiptDemoNote => 'إيصال تجريبي — لا توجد طابعة متصلة';

  @override
  String get posPrintReceiptDemo => 'طباعة الإيصال (تجريبي)';

  @override
  String get printPreviewAction => 'معاينة الطباعة';

  @override
  String get printPreviewPrint => 'طباعة';

  @override
  String get printPreviewClose => 'إغلاق';

  @override
  String get printPreviewHint =>
      'استخدم طباعة المتصفح (Ctrl+P) لطباعة هذه المعاينة';

  @override
  String get deviceSettingsMenuTooltip => 'قائمة الجهاز';

  @override
  String get deviceSettingsTitle => 'إعدادات الجهاز';

  @override
  String get deviceRefreshAction => 'تحديث الاتصال';

  @override
  String get deviceUnpairAction => 'إلغاء اقتران الجهاز';

  @override
  String get deviceUnpairWarning =>
      'استخدم هذا فقط إذا كان يجب إقران هذا الجهاز من جديد.';

  @override
  String get deviceUnpairConfirm => 'إلغاء الاقتران';

  @override
  String get deviceUnpairCancel => 'إلغاء';

  @override
  String get deviceSettingsAppTypeLabel => 'نوع التطبيق';

  @override
  String get deviceSettingsAppTypePos => 'الكاشير (POS)';

  @override
  String get deviceSettingsAppTypeKds => 'شاشة المطبخ (KDS)';

  @override
  String get deviceSettingsRestaurantLabel => 'المطعم';

  @override
  String get deviceSettingsBranchLabel => 'الفرع';

  @override
  String get deviceSettingsDeviceLabel => 'الجهاز';

  @override
  String get deviceSettingsPairingLabel => 'الاقتران';

  @override
  String get deviceSettingsPairingActive => 'مقترن';

  @override
  String get deviceSettingsPinSessionLabel => 'جلسة الموظف';

  @override
  String get deviceSettingsPinSessionActive => 'مسجّل الدخول';

  @override
  String get deviceSettingsPinSessionNone => 'غير مسجّل الدخول';

  @override
  String get deviceSettingsDemoNote => 'وضع تجريبي — لا يوجد جهاز مقترن.';

  @override
  String get deviceSettingsUnavailable => 'معلومات الجهاز غير متاحة.';

  @override
  String get deviceSettingsPrintersHeading => 'الطابعات';

  @override
  String get deviceSettingsNoPrinter =>
      'لا توجد طابعة معيّنة. اطلب من المدير إعدادها في لوحة التحكم ← الطابعات.';

  @override
  String get deviceSettingsBridgeRequired =>
      'مُعدّة فقط — تتطلب الطباعة جسر طباعة.';

  @override
  String get deviceSettingsCapabilityNote =>
      'تتطلب الطباعة جسر طباعة أو تطبيقًا أصليًا. هذا الإصدار يحفظ الإعدادات وينشئ/يعاين مهام الطباعة.';

  @override
  String deviceSettingsLastRefresh(String time) {
    return 'آخر تحديث: $time';
  }

  @override
  String get deviceSettingsLoadError => 'تعذّر تحميل تعيينات الطابعات.';

  @override
  String get deviceSettingsPrinterDisabled => 'معطّلة في لوحة التحكم';

  @override
  String deviceSettingsRouteStations(String names) {
    return 'المحطات: $names';
  }

  @override
  String get deviceRefreshedSnack => 'تم تحديث الاتصال.';

  @override
  String get deviceUnpairedSnack => 'تم إلغاء اقتران الجهاز.';

  @override
  String get deviceSettingsAutoPrintHeading => 'طباعة تلقائية';

  @override
  String get posAutoPrintReceiptToggle => 'طباعة الإيصال تلقائيًا بعد الدفع';

  @override
  String get kdsAutoPrintAcknowledgeToggle =>
      'طباعة تذكرة المطبخ تلقائيًا عند الاستلام';

  @override
  String get autoPrintNoPrinterNote => 'معطّل — لا توجد طابعة معيّنة.';

  @override
  String get printStatusNotConfigured => 'لا توجد طابعة مُعدّة';

  @override
  String get printStatusPrepared =>
      'تم تجهيز مهمة الطباعة — الطباعة الفعلية تتطلب جسر طباعة.';

  @override
  String get printStatusPrinted => 'تمت الطباعة';

  @override
  String get printStatusFailed => 'فشلت الطباعة';

  @override
  String get posReceiptPrintLabel => 'طباعة الإيصال';

  @override
  String get kdsTicketPrintLabel => 'طباعة المطبخ';

  @override
  String get receiptPreviewTitle => 'معاينة الإيصال';

  @override
  String get receiptDemoRestaurantName => 'مطعم RestoFlow التجريبي';

  @override
  String get kdsPreviewTicketAction => 'معاينة التذكرة';

  @override
  String get kdsTicketPreviewTitle => 'معاينة تذكرة المطبخ';

  @override
  String get kdsElapsedLabel => 'المنقضي';

  @override
  String get languageSelectorTooltip => 'اللغة';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHebrew => 'עברית';

  @override
  String get posShiftDemoName => 'وردية صباحية تجريبية';

  @override
  String get posDrawerLabel => 'درج النقد';

  @override
  String get posDrawerOpen => 'مفتوح';

  @override
  String get posDrawerClosed => 'مغلق';

  @override
  String get posCashInDrawer => 'النقد في الدرج';

  @override
  String get posLastCashPayment => 'آخر دفعة نقدية';

  @override
  String get posShiftDemoNote =>
      'وضع تجريبي — الجرد محسوب محليًا ولا يُحفظ على الخادم.';

  @override
  String get posShiftRealName => 'الوردية الحالية';

  @override
  String get posShiftRealNote =>
      'فُتحت عند تسجيل الدخول — إجماليات النقد تُتابَع على الخادم';

  @override
  String get posShiftCloseTitle => 'إغلاق الوردية وجرد النقد';

  @override
  String get posShiftCloseMenuItem => 'إغلاق الوردية';

  @override
  String get posShiftCloseConfirmTitle => 'تأكيد إغلاق الوردية';

  @override
  String get posShiftCloseConfirmBody =>
      'ستُغلق الوردية بالمبلغ المعدود ولا يمكن التراجع.';

  @override
  String get posShiftCancelAction => 'إلغاء';

  @override
  String get posShiftCloseAction => 'إغلاق الوردية';

  @override
  String get posShiftDoneAction => 'تم';

  @override
  String get posShiftNoOpenShift => 'لا توجد وردية مفتوحة على هذا الجهاز.';

  @override
  String get posShiftNoOpenShiftHint =>
      'تُفتح الوردية تلقائيًا عند تسجيل دخول الكاشير.';

  @override
  String get posShiftOpenedAt => 'فُتحت الساعة';

  @override
  String get posShiftOpeningFloat => 'الرصيد الافتتاحي';

  @override
  String get posShiftExpectedCash => 'النقد المتوقع';

  @override
  String get posShiftExpectedAtClose =>
      'يُحتسب النقد المتوقع على الخادم عند الإغلاق.';

  @override
  String get posShiftCountedLabel => 'النقد المعدود';

  @override
  String get posShiftInvalidAmount => 'أدخل مبلغًا صحيحًا.';

  @override
  String get posShiftReasonLabel => 'السبب (مطلوب عند وجود فرق)';

  @override
  String get posShiftReasonRequired =>
      'أدخل سببًا عند اختلاف النقد المعدود عن المتوقع.';

  @override
  String get posShiftClosedTitle => 'تم إغلاق الوردية';

  @override
  String get posShiftBalanced => 'مطابق';

  @override
  String get posShiftOver => 'زيادة';

  @override
  String get posShiftShort => 'عجز';

  @override
  String get posShiftDifference => 'الفرق';

  @override
  String get posShiftCloseUnavailable =>
      'الإغلاق غير متاح — يلزم جلسة موظف على جهاز مقترن.';

  @override
  String get posShiftClosePermissionDenied =>
      'غير مصرّح لك بإغلاق هذه الوردية.';

  @override
  String get posShiftCloseServerRejected =>
      'رفض الخادم الإغلاق — قد يلزم إدخال سبب أو أن حالة الوردية غير صالحة.';

  @override
  String get posShiftCloseFailed => 'تعذّر إغلاق الوردية.';

  @override
  String get posShiftCouldNotRestore =>
      'تعذّر استرجاع حالة الوردية. سجّل الدخول مجددًا لفتح وردية.';

  @override
  String get posShiftReturnToPin => 'تسجيل الخروج';

  @override
  String get posSyncSendingReal => 'جارٍ الإرسال إلى الخادم…';

  @override
  String get posSyncSentReal => 'أُرسل — شاشة المطبخ تستقبله تلقائيًا.';

  @override
  String get posSyncFailedReal =>
      'رفض الخادم هذا الطلب — لم يُرسَل إلى المطبخ.';

  @override
  String get posSyncSendNow => 'إرسال الآن';

  @override
  String get posReceiptNoPrinterNote => 'الطباعة غير متصلة على هذا الجهاز بعد';

  @override
  String get posModifierRequired => 'إلزامي';

  @override
  String get posModifierOptional => 'اختياري';

  @override
  String posModifierSelectedCount(int selected, int max) {
    return '$selected/$max';
  }

  @override
  String posModifierSelectedCountOpen(int selected) {
    return '$selected';
  }

  @override
  String get posModifierFree => 'مجاني';

  @override
  String posModifierBasePrice(String price) {
    return 'السعر الأساسي · $price';
  }

  @override
  String get posModifierItemNoteLabel => 'ملاحظة للمنتج';

  @override
  String get posModifierItemNoteHint => 'مثال: بدون بصل، زيادة صوص';

  @override
  String get posItemNoteLabel => 'ملاحظة';

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
  String get dashboardReportsHeading => 'تقارير المالك';

  @override
  String get dashboardReportDayLabel => 'يوم التقرير';

  @override
  String get dashboardDemoDay => 'يوم تجريبي';

  @override
  String get dashboardRefresh => 'تحديث';

  @override
  String get dashboardLoadingReports => 'جارٍ تحميل التقارير…';

  @override
  String get dashboardReportsError => 'تعذّر تحميل التقارير.';

  @override
  String get dashboardRetry => 'إعادة المحاولة';

  @override
  String get dashboardNoReportData => 'لا توجد بيانات تقرير لهذا اليوم.';

  @override
  String get dashboardDemoReportsNotice =>
      'تقارير تجريبية — محسوبة محليًا من طلبات نموذجية، وغير متزامنة مع خادم.';

  @override
  String get dashboardRealModeNotice =>
      'تقارير مباشرة — للقراءة فقط ومحدودة. بعض الأرقام غير متوفرة هنا بعد.';

  @override
  String get dashboardLiveDataTag => 'مباشر · محدود';

  @override
  String get dashboardGrossSales => 'إجمالي المبيعات';

  @override
  String get dashboardCashSales => 'المبيعات النقدية';

  @override
  String get dashboardUnpaidOrders => 'الطلبات غير المدفوعة';

  @override
  String get dashboardPaymentSummary => 'ملخص الدفع والنقدية';

  @override
  String get dashboardOpeningFloat => 'الرصيد الافتتاحي';

  @override
  String get dashboardExpectedDrawer => 'المتوقع في الدرج';

  @override
  String get dashboardCountedCash => 'النقد المعدود';

  @override
  String get dashboardLastCashPayment => 'آخر دفعة نقدية';

  @override
  String get dashboardPaymentMethods => 'طرق الدفع';

  @override
  String get dashboardPaymentMethodCash => 'نقدًا';

  @override
  String get dashboardRecentOrders => 'أحدث الطلبات';

  @override
  String get dashboardPaid => 'مدفوع';

  @override
  String get dashboardUnpaid => 'غير مدفوع';

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
  String get authRealModeUnconfiguredTitle => 'الوضع الحقيقي غير مُهيَّأ';

  @override
  String get authRealModeUnconfiguredBody =>
      'تم تشغيل التطبيق في الوضع الحقيقي، لكن إعدادات الاتصال بالخادم مفقودة أو غير صالحة. RestoFlow لا يزيّف الخادم أبدًا، لذا يبقى الوضع الحقيقي مقفلاً حتى يتم توفير إعدادات صالحة.';

  @override
  String get authRealModeUnconfiguredHowTo => 'شغّل التطبيق بهذه القيم';

  @override
  String get authRealModeUnconfiguredDemoHint =>
      'لاستكشاف النسخة التجريبية بدلاً من ذلك، شغّل التطبيق دون أي إعدادات — الوضع التجريبي هو الافتراضي.';

  @override
  String get authDeviceSignInUnavailableTitle => 'تسجيل دخول الجهاز غير متاح';

  @override
  String get authDeviceSignInUnavailableBody =>
      'تسجيل الدخول المجهول للأجهزة معطَّل أو أن مصادقة Supabase غير مهيأة.';

  @override
  String get authDeviceSignInUnavailableHowTo => 'كيفية الإصلاح';

  @override
  String get authDeviceSignInUnavailableFix =>
      'فعِّل تسجيل الدخول المجهول في إعدادات مصادقة Supabase، ثم أعد تشغيل الخادم وهذا التطبيق. لا يحتاج هذا الجهاز إلى حساب شخصي — الاقتران يسجّل دخول الجهاز بنفسه.';

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
  String get menuAllowQuantityLabel => 'السماح بالكمية';

  @override
  String get menuAllowQuantityHelp =>
      'يمكن للكاشير إضافة نفس الخيار أكثر من مرة (مثال: جبنة إضافية ×2).';

  @override
  String get menuMaxQuantityLabel => 'الحد الأقصى لكل خيار';

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
  String get menuImageDeferredTitle => 'رفع الصور غير متصل';

  @override
  String get menuImageDeferredBody =>
      'لا يوجد تخزين صور متصل بهذه الواجهة، لذا لا يمكن رفع صور العناصر أو عرضها هنا.';

  @override
  String get menuImagePickAction => 'اختيار صورة';

  @override
  String get menuImageReplaceAction => 'استبدال الصورة';

  @override
  String get menuImageRemoveAction => 'إزالة الصورة';

  @override
  String get menuImageSaveAction => 'حفظ الصورة';

  @override
  String get menuImageInvalidType => 'يمكن رفع صور PNG أو JPEG أو WebP فقط.';

  @override
  String get menuImageTooLarge => 'الصورة كبيرة جدًا — الحد الأقصى 5 ميغابايت.';

  @override
  String get menuImageUploadFailed => 'فشل الرفع — لم يتم حفظ الصورة.';

  @override
  String get menuImageUnsupportedPlatform =>
      'اختيار صورة غير متاح على هذه المنصة بعد — استخدم لوحة التحكم عبر الويب.';

  @override
  String get menuImageDemoNote => 'تجريبي — لا يتم رفع الصورة إلى خادم.';

  @override
  String get menuImageLoadError => 'تعذر تحميل معاينة الصورة.';

  @override
  String get menuErrorRequired => 'مطلوب';

  @override
  String get menuErrorAmount => 'أدخل مبلغًا صالحًا';

  @override
  String get menuErrorNegativePrice => 'لا يمكن أن يكون سالبًا';

  @override
  String get menuErrorCurrency => 'استخدم رمزًا من 3 أحرف (مثل ILS)';

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
  String get menuBasicInfoSection => 'معلومات أساسية';

  @override
  String get menuPricingSection => 'التسعير';

  @override
  String get menuPreparationSection => 'التحضير';

  @override
  String get menuAdvancedSection => 'متقدم';

  @override
  String get menuAdvancedSectionHint =>
      'تفاصيل اختيارية — استخدم ما يناسب هذا الصنف.';

  @override
  String get menuItemTypeLabel => 'نوع الصنف';

  @override
  String get menuItemTypeUnspecified => 'غير محدد';

  @override
  String get menuItemTypeFood => 'طعام';

  @override
  String get menuItemTypeDrink => 'مشروب';

  @override
  String get menuItemTypeSide => 'طبق جانبي';

  @override
  String get menuItemTypeCombo => 'وجبة كومبو';

  @override
  String get menuItemTypeOther => 'أخرى';

  @override
  String get menuTagsLabel => 'وسوم';

  @override
  String get menuTagSpicy => 'حار';

  @override
  String get menuTagVegetarian => 'نباتي';

  @override
  String get menuTagPopular => 'رائج';

  @override
  String get menuTagNew => 'جديد';

  @override
  String menuModifierGroupCount(int count) {
    return '$count مجموعات خيارات';
  }

  @override
  String get menuPrepMinutesLabel => 'وقت التحضير (بالدقائق)';

  @override
  String get menuKitchenNoteLabel => 'ملاحظة للمطبخ';

  @override
  String get menuSkuLabel => 'SKU (رمز داخلي)';

  @override
  String get menuPortionFieldLabel => 'تسمية الحصة';

  @override
  String get menuPattyCountLabel => 'العدد (قطع أو شرائح)';

  @override
  String get menuPattyWeightLabel => 'وزن القطعة (غرام)';

  @override
  String get menuTemplateAddAction => 'إضافة قالب';

  @override
  String get menuTemplatePickerTitle => 'إضافة من قالب';

  @override
  String get menuTemplateRequiredSingle => 'إلزامي · اختيار واحد';

  @override
  String get menuTemplateOptionalMulti => 'اختياري · اختيار متعدد';

  @override
  String get menuTemplateOptionalSingle => 'اختياري · خيار واحد كحد أقصى';

  @override
  String menuTemplateOptionCount(int count) {
    return '$count خيارات';
  }

  @override
  String get menuTemplateApplyPartial =>
      'توقفت الإضافة — الصفوف التي أُنشئت تبقى في القائمة؛ يمكن تعديلها أو حذفها أدناه.';

  @override
  String get menuTemplateBurgerToppings => 'إضافات البرغر';

  @override
  String get menuTemplateOptLettuce => 'خس';

  @override
  String get menuTemplateOptTomato => 'بندورة';

  @override
  String get menuTemplateOptOnion => 'بصل';

  @override
  String get menuTemplateOptPickles => 'مخلل';

  @override
  String get menuTemplateOptCheese => 'جبنة';

  @override
  String get menuTemplateDoneness => 'درجة الاستواء';

  @override
  String get menuTemplateOptRare => 'نادرة';

  @override
  String get menuTemplateOptMediumDoneness => 'وسط';

  @override
  String get menuTemplateOptWellDone => 'ناضجة جيدًا';

  @override
  String get menuTemplatePattyCount => 'عدد قطع اللحم';

  @override
  String get menuTemplateOptSinglePatty => 'قطعة واحدة';

  @override
  String get menuTemplateOptDoublePatty => 'قطعتان';

  @override
  String get menuTemplateOptTriplePatty => 'ثلاث قطع';

  @override
  String get menuTemplateExtras => 'إضافات';

  @override
  String get menuTemplateOptExtraCheese => 'جبنة إضافية';

  @override
  String get menuTemplateOptExtraPatty => 'قطعة لحم إضافية';

  @override
  String get menuTemplateOptFries => 'بطاطا مقلية';

  @override
  String get menuTemplateOptDrink => 'مشروب';

  @override
  String get menuTemplateDrinkSize => 'حجم المشروب';

  @override
  String get menuTemplateOptSmall => 'صغير';

  @override
  String get menuTemplateOptMediumSize => 'وسط';

  @override
  String get menuTemplateOptLarge => 'كبير';

  @override
  String get menuTemplateSpiciness => 'مستوى الحار';

  @override
  String get menuTemplateOptMild => 'خفيف';

  @override
  String get menuTemplateOptMediumSpicy => 'وسط';

  @override
  String get menuTemplateOptHot => 'حار';

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
  String get adminErrCurrency => 'استخدم رمزًا من 3 أحرف (مثل ILS)';

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

  @override
  String get authWelcomeTitle => 'مرحبًا بك في RestoFlow';

  @override
  String get authBrandTagline => 'نظام تشغيل المطاعم';

  @override
  String get authSignInTab => 'تسجيل الدخول';

  @override
  String get authCreateAccountTab => 'إنشاء حساب';

  @override
  String get authEmailLabel => 'البريد الإلكتروني';

  @override
  String get authPasswordLabel => 'كلمة المرور';

  @override
  String get authSignInAction => 'تسجيل الدخول';

  @override
  String get authEmailRequired => 'أدخل بريدك الإلكتروني';

  @override
  String get authPasswordRequired => 'أدخل كلمة المرور';

  @override
  String get authPasswordTooShort => 'استخدم 6 أحرف على الأقل';

  @override
  String get authInvalidCredentials =>
      'البريد الإلكتروني أو كلمة المرور غير صحيحة';

  @override
  String get authSignUpFailed => 'تعذّر إنشاء حسابك. حاول مرة أخرى.';

  @override
  String get authNetworkError => 'تعذّر الوصول إلى الخادم. تحقّق من اتصالك.';

  @override
  String get authEmailConfirmationSent =>
      'تحقّق من بريدك الإلكتروني لتأكيد حسابك ثم سجّل الدخول.';

  @override
  String get onboardingTitle => 'إعداد مطعمك';

  @override
  String get onboardingIntro => 'أنشئ مطعمك لبدء استخدام RestoFlow.';

  @override
  String get onboardingRestaurantNameLabel => 'اسم المطعم';

  @override
  String get onboardingBranchNameLabel => 'اسم الفرع (اختياري)';

  @override
  String get onboardingRestaurantNameRequired => 'أدخل اسم المطعم';

  @override
  String get onboardingCreateAction => 'إنشاء المطعم';

  @override
  String get onboardingFailed => 'تعذّر إنشاء مطعمك. حاول مرة أخرى.';

  @override
  String get pairingTitle => 'اقتران هذا الجهاز';

  @override
  String get pairingIntro =>
      'أدخل رمز الاقتران الذي أُنشئ في لوحة تحكم المطعم لربط هذا الجهاز.';

  @override
  String get pairingWhereCode =>
      'احصل على رمز الاقتران من لوحة التحكم ← تبويب الأجهزة.';

  @override
  String get pairingCodeLabel => 'رمز الاقتران';

  @override
  String get pairingCodeRequired => 'أدخل رمز الاقتران';

  @override
  String get pairingPairAction => 'اقتران الجهاز';

  @override
  String get pairingInvalidCode =>
      'لم يُقبل رمز الاقتران. تحقّق منه وحاول مرة أخرى.';

  @override
  String get pairingExpired => 'انتهت صلاحية رمز الاقتران. اطلب رمزًا جديدًا.';

  @override
  String get pairingWrongScope => 'هذا الرمز لمطعم أو فرع مختلف.';

  @override
  String get pairingFailed => 'تعذّر اقتران هذا الجهاز. حاول مرة أخرى.';

  @override
  String get dashboardNavPrinters => 'الطابعات';

  @override
  String get dashboardNavStaff => 'الموظفون';

  @override
  String get dashboardNavTables => 'الطاولات';

  @override
  String get dashboardModeDemo => 'تجريبي';

  @override
  String get dashboardModeReal => 'حقيقي';

  @override
  String get dashboardUsersNotConnectedTitle =>
      'إدارة المستخدمين غير متصلة بعد';

  @override
  String get dashboardUsersNotConnectedBody =>
      'لا يمكن لهذا الإصدار عرض الأعضاء الحقيقيين أو دعوتهم بعد — لا توجد واجهة لقراءة الأعضاء. بدلاً من عرض أشخاص تجريبيين تبقى هذه الصفحة فارغة. الوضع التجريبي يعرض كيف سيعمل هذا المسار.';

  @override
  String get dashboardSettingsWorkspace => 'مساحة العمل';

  @override
  String get dashboardSettingsRealNotice =>
      'هذه هي القيم الحقيقية لمساحة العمل. تعديل الإعدادات غير متصل في هذا الإصدار بعد، لذا لا يوجد شيء للحفظ هنا.';

  @override
  String get dashboardShiftCloseSectionTitle => 'تسوية الوردية (نقطة البيع)';

  @override
  String get dashboardShiftCloseToggleLabel =>
      'إظهار «إغلاق الوردية وعدّ النقد» على نقطة البيع';

  @override
  String get dashboardShiftCloseToggleHelp =>
      'عند التفعيل، يمكن للكاشير إغلاق ورديته وعدّ درج النقد على نقطة البيع لهذا الفرع. إيقافه يُخفي هذا الإجراء؛ ولا يؤثر على المدفوعات.';

  @override
  String get dashboardShiftCloseOwnerOnly =>
      'يمكن للمالك فقط تغيير هذا الإعداد.';

  @override
  String get dashboardShiftCloseUnavailable =>
      'تعذّر تحميل هذا الإعداد الآن. حاول مرة أخرى لاحقًا.';

  @override
  String get dashboardShiftCloseSaved => 'تم حفظ الإعداد.';

  @override
  String get dashboardShiftCloseDenied =>
      'ليست لديك صلاحية لتغيير هذا الإعداد.';

  @override
  String get dashboardShiftCloseSaveFailed =>
      'تعذّر حفظ الإعداد. حاول مرة أخرى.';

  @override
  String get setupTitle => 'الإعداد';

  @override
  String get setupSubtitle => 'جهّز هذا الفرع للعمل';

  @override
  String get setupDevices => 'الأجهزة';

  @override
  String get setupDevicesCaption => 'نشِط / الإجمالي';

  @override
  String get setupPrinters => 'الطابعات';

  @override
  String get setupPrintersCaption => 'مفعّل / الإجمالي';

  @override
  String get setupStaffPin => 'أرقام PIN للموظفين';

  @override
  String get setupStaffCaption => 'لديه PIN / الإجمالي';

  @override
  String get setupMetricUnavailable => 'غير متاح';

  @override
  String get setupNoDevices =>
      'لا توجد أجهزة بعد — أنشئ جهاز نقطة بيع أو شاشة مطبخ وأصدر رمز اقتران.';

  @override
  String get setupNoActiveDevice =>
      'لا يوجد جهاز مقترن بعد — أصدر رمزًا من صفحة الأجهزة واستخدمه على شاشة اقتران الجهاز.';

  @override
  String get setupNoPrinters =>
      'لا توجد طابعات مُهيأة بعد — أضف طابعة إيصالات أو طابعة مطبخ.';

  @override
  String get setupNoStaffPin =>
      'لا يملك أي موظف رقم PIN بعد — تسجيل الدخول إلى نقطة البيع/شاشة المطبخ (ودورة الطلبات الحية) يتطلب واحدًا على الأقل.';

  @override
  String get setupReady =>
      'هذا الفرع جاهز: جهاز مقترن ورقم PIN للموظفين متوفران.';

  @override
  String get setupMenu => 'أصناف القائمة';

  @override
  String get setupMenuCaption => 'نشِط / الإجمالي';

  @override
  String get setupNoMenu =>
      'لا توجد أصناف في القائمة بعد — لا يوجد ما تبيعه نقطة البيع.';

  @override
  String get setupAddMenuItem => 'أضف أول صنف في القائمة';

  @override
  String get setupNoPosDevice =>
      'لا يوجد جهاز نقطة بيع بعد — يحتاج الكاشير إلى جهاز لاستقبال الطلبات.';

  @override
  String get setupCreatePos => 'إنشاء جهاز نقطة بيع';

  @override
  String get setupNoKdsDevice =>
      'لا توجد شاشة مطبخ بعد — لن يرى المطبخ الطلبات الواردة.';

  @override
  String get setupCreateKds => 'إنشاء شاشة مطبخ';

  @override
  String get setupPairingHint =>
      'افتح تطبيق نقطة البيع أو شاشة المطبخ على ذلك الجهاز وأدخل رمز الاقتران من تبويب الأجهزة.';

  @override
  String get setupAddPrinter => 'إضافة طابعة';

  @override
  String get setupCreatePin => 'إنشاء رمز PIN للموظف';

  @override
  String get printersTitle => 'الطابعات';

  @override
  String get printersSubtitle => 'طابعات الإيصالات والمطبخ لهذا الفرع';

  @override
  String get printersAdd => 'إضافة طابعة';

  @override
  String get printersEmptyTitle => 'لا توجد طابعات بعد';

  @override
  String get printersEmptyBody =>
      'أضف طابعة إيصالات أو طابعة مطبخ لتجهيز هذا الفرع للطباعة.';

  @override
  String get printersTransportNoticeTitle =>
      'إعدادات فقط — لا يوجد نقل طباعة بعد';

  @override
  String get printersTransportNotice =>
      'تُحفظ إعدادات الطابعة وتُتحقق في الخادم، لكن هذا الإصدار لا يرسل شيئًا إلى الطابعات الفعلية. محرك الطباعة يعمل عبر الشبكة أولاً؛ ولم تُركَّب وسائط البلوتوث وUSB بعد. لا يُعرض أبدًا نجاح طباعة زائف.';

  @override
  String get printersRoleReceipt => 'إيصالات';

  @override
  String get printersRoleKitchen => 'مطبخ';

  @override
  String get printersConnNetwork => 'شبكة (Wi-Fi/LAN)';

  @override
  String get printersConnBluetooth => 'بلوتوث';

  @override
  String get printersConnUsb => 'USB';

  @override
  String get printersConnConfigOnly =>
      'إعدادات فقط — وسيلة النقل هذه غير مُركّبة بعد.';

  @override
  String get printersAdvanced => 'خيارات متقدمة';

  @override
  String get printersDialogSavesConfigOnly =>
      'هذا الإصدار يحفظ إعدادات الطابعة فقط — لا تتم أي طباعة بعد.';

  @override
  String get printersConnBluetoothWeb =>
      'اكتشاف البلوتوث غير متاح في تطبيق الويب بعد. سيتم حفظ الإعدادات فقط.';

  @override
  String get printersConnUsbAdapter =>
      'الطباعة عبر USB تتطلب محوّل الطابعة لسطح المكتب/الأصلي. سيتم حفظ الإعدادات فقط.';

  @override
  String get printersFieldName => 'الاسم المعروض';

  @override
  String get printersFieldRole => 'دور الطابعة';

  @override
  String get printersFieldConnection => 'نوع الاتصال';

  @override
  String get printersFieldPaper => 'عرض الورق';

  @override
  String get printersFieldHost => 'المضيف / عنوان IP';

  @override
  String get printersFieldPort => 'المنفذ';

  @override
  String get printersFieldBluetoothId => 'معرّف / اسم جهاز البلوتوث';

  @override
  String get printersFieldUsbPath => 'مسار / معرّف USB';

  @override
  String get printersEnabled => 'مفعّلة';

  @override
  String get printersDisabled => 'معطّلة';

  @override
  String get printersEdit => 'تعديل';

  @override
  String get printersRoute => 'توجيه إلى محطة';

  @override
  String get printersRouteTitle => 'توجيه الطابعة إلى محطة';

  @override
  String get printersRouteStation => 'المحطة';

  @override
  String get printersRouteActive => 'التوجيه مفعّل';

  @override
  String get printersRoutedTo => 'تُوجّه إلى';

  @override
  String get printersDelete => 'إزالة الطابعة';

  @override
  String get printersDeleteConfirm =>
      'هل تريد إزالة هذه الطابعة؟ ستُزال أيضًا توجيهات المحطات الخاصة بها.';

  @override
  String get printersSaved => 'تم الحفظ';

  @override
  String get printersNoStations => 'لا توجد محطات لهذا الفرع بعد.';

  @override
  String get printersErrHost => 'أدخل مضيف / عنوان IP للطابعة';

  @override
  String get printersErrPort => 'أدخل منفذًا صالحًا (1–65535)';

  @override
  String get printersSave => 'حفظ';

  @override
  String get printersWizardStepPurpose => 'ماذا تريد أن تطبع؟';

  @override
  String get printersPurposeReceiptsHint => 'فواتير للعملاء عند الكاشير.';

  @override
  String get printersPurposeKitchenHint => 'تذاكر لطاقم المطبخ.';

  @override
  String get printersWizardStepConnection => 'كيف تتصل الطابعة؟';

  @override
  String get printersConnNetworkHint =>
      'يجب أن تكون الطابعة على نفس شبكة Wi-Fi/الشبكة التي يستخدمها هذا الجهاز.';

  @override
  String get printersWizardStepDetails => 'تفاصيل الطابعة';

  @override
  String get printersNext => 'التالي';

  @override
  String get printersBack => 'رجوع';

  @override
  String get printersStatusDisabled => 'معطّلة';

  @override
  String get printersStatusNeedsBridge => 'تتطلب جسر الطباعة';

  @override
  String get printersStatusConfigOnly => 'مُهيأة فقط';

  @override
  String get printersStatusReadyNetwork => 'جاهزة عبر محوّل الشبكة';

  @override
  String get printersTestPrint => 'طباعة تجريبية';

  @override
  String get printersTestPrintUnavailable =>
      'الطباعة التجريبية تتطلب محوّل الطباعة أو الجسر — غير متاحة في إصدار الويب هذا.';

  @override
  String get staffTitle => 'الموظفون';

  @override
  String get staffSubtitle => 'الموظفون وتسجيل الدخول برقم PIN لهذا الفرع';

  @override
  String get staffAdd => 'إضافة موظف';

  @override
  String get staffEmptyTitle => 'لا يوجد موظفون بعد';

  @override
  String get staffEmptyBody =>
      'أنشئ الكاشيرين وطاقم المطبخ والمديرين، ثم عيّن لكل منهم رقم PIN لتسجيل الدخول إلى نقطة البيع/شاشة المطبخ.';

  @override
  String get staffFieldName => 'الاسم المعروض';

  @override
  String get staffFieldRole => 'الدور';

  @override
  String get staffPinSet => 'تم تعيين PIN';

  @override
  String get staffNoPin => 'بدون PIN';

  @override
  String get staffSetPin => 'تعيين PIN';

  @override
  String get staffResetPin => 'إعادة تعيين PIN';

  @override
  String get staffPinDialogTitle => 'تعيين رقم PIN لتسجيل الدخول';

  @override
  String get staffPinDialogBody =>
      'من 4 إلى 8 أرقام. يُخزَّن كتجزئة آمنة — لا يمكن قراءته أبدًا؛ تعيين رقم جديد يستبدل القديم.';

  @override
  String get staffFieldPin => 'رقم PIN (4–8 أرقام)';

  @override
  String get staffFieldPinConfirm => 'تأكيد رقم PIN';

  @override
  String get staffPinMismatch => 'رقما PIN غير متطابقين';

  @override
  String get staffPinInvalid => 'أدخل من 4 إلى 8 أرقام';

  @override
  String get staffPinSaved => 'تم حفظ رقم PIN';

  @override
  String get staffCreated => 'تم إنشاء الموظف';

  @override
  String get staffNoPinWarning =>
      'الموظف بدون رقم PIN لا يمكنه تسجيل الدخول إلى نقطة البيع/شاشة المطبخ.';

  @override
  String get staffInactive => 'غير نشط';

  @override
  String get tablesTitle => 'الطاولات';

  @override
  String get tablesSubtitle =>
      'طاولات الطعام لهذا الفرع — منتقي الطاولات في نقطة البيع يبيع من هذه القائمة.';

  @override
  String get tablesAdd => 'إضافة طاولة';

  @override
  String get tablesEdit => 'تعديل';

  @override
  String get tablesDelete => 'إزالة الطاولة';

  @override
  String get tablesDeleteConfirm =>
      'هل تريد إزالة هذه الطاولة؟ الطلبات الحالية تحتفظ بمرجع الطاولة الخاص بها.';

  @override
  String get tablesEmptyTitle => 'لا توجد طاولات بعد';

  @override
  String get tablesEmptyBody =>
      'أضف أول طاولة — مسار تناول الطعام داخل المطعم في نقطة البيع يحتاج إلى طاولة واحدة على الأقل.';

  @override
  String get tablesFieldLabel => 'اسم / رقم الطاولة';

  @override
  String get tablesFieldSeats => 'المقاعد';

  @override
  String get tablesFieldArea => 'المنطقة / القسم';

  @override
  String get tablesActive => 'نشطة';

  @override
  String get tablesInactive => 'غير نشطة';

  @override
  String get tablesErrLabel => 'أدخل اسم الطاولة';

  @override
  String get tablesErrSeats => 'يجب أن يكون عدد المقاعد رقمًا موجبًا';

  @override
  String get tablesStatusAvailable => 'متاحة';

  @override
  String get tablesStatusOccupied => 'مشغولة';

  @override
  String get tablesStatusReserved => 'محجوزة';

  @override
  String get tablesStatusOutOfService => 'خارج الخدمة';

  @override
  String get tablesSetStatus => 'تعيين الحالة';

  @override
  String get tablesSaved => 'تم حفظ الطاولة';

  @override
  String get adminRevokeConfirm =>
      'هل تريد إلغاء هذا الجهاز؟ سينتهي اقترانه وجلساته فورًا وسيعود الجهاز إلى شاشة الاقتران.';

  @override
  String get adminPairOnDevice =>
      'أدخل الرمز لمرة واحدة على شاشة اقتران هذا الجهاز لإتمام الاقتران.';

  @override
  String get pinLoginTitle => 'تسجيل دخول الموظفين';

  @override
  String get pinLoginPickName => 'اختر اسمك';

  @override
  String get pinLoginEmptyTitle => 'لا توجد رموز PIN للموظفين بعد';

  @override
  String get pinLoginEmptyBody =>
      'اطلب من المدير إضافة الموظفين وتعيين أرقام PIN في لوحة التحكم.';

  @override
  String get pinLoginEmptyBodyPos =>
      'افتح لوحة التحكم ← الموظفون، أضف كاشيرًا أو مديرًا وعيّن له رمز PIN، ثم ارجع واضغط \"حاول مرة أخرى\".';

  @override
  String get pinLoginEmptyBodyKds =>
      'افتح لوحة التحكم ← الموظفون، أضف موظف مطبخ أو مديرًا وعيّن له رمز PIN، ثم ارجع واضغط \"حاول مرة أخرى\".';

  @override
  String get pinLoginStepsTitle => 'خطوات الإعداد';

  @override
  String get pinLoginStep1 => '1. افتح لوحة التحكم';

  @override
  String get pinLoginStep2 => '2. انتقل إلى الموظفين';

  @override
  String get pinLoginStep3 => '3. أضف موظفًا';

  @override
  String get pinLoginStep4 => '4. عيّن رمز PIN';

  @override
  String get pinLoginStep5 => '5. ارجع إلى هنا واضغط \"حاول مرة أخرى\"';

  @override
  String get pinLoginLoadError =>
      'تعذّر تحميل قائمة الموظفين. تحقّق من الاتصال وحاول مرة أخرى.';

  @override
  String get pinLoginSessionInvalid =>
      'جلسة هذا الجهاز لم تعد صالحة. أعد اقتران الجهاز.';

  @override
  String get pinLoginWrongPin => 'رقم PIN خاطئ — حاول مرة أخرى.';

  @override
  String get pinLoginLocked => 'محاولات كثيرة جدًا. تسجيل الدخول مقفل مؤقتًا.';

  @override
  String get pinLoginNetworkError => 'مشكلة في الاتصال — حاول مرة أخرى.';

  @override
  String get pinLoginUnavailable => 'تسجيل الدخول غير متاح الآن.';

  @override
  String get pinLoginSubmit => 'تسجيل الدخول';

  @override
  String get pinLoginBack => 'رجوع';

  @override
  String get pinFieldLabel => 'PIN';

  @override
  String get posSignOutStaff => 'إنهاء جلسة الموظف';

  @override
  String get posMenuLoadError =>
      'تعذّر تحميل القائمة. تحقّق من الاتصال وحاول مرة أخرى.';

  @override
  String get posMenuEmptyTitle => 'لا توجد عناصر في القائمة بعد';

  @override
  String get posMenuEmptyBody => 'أضف عناصر القائمة في لوحة التحكم لبدء البيع.';

  @override
  String get posTablesEmptyReal =>
      'لا توجد طاولات مُعدة — أضف الطاولات من لوحة التحكم ← الطاولات.';

  @override
  String get kdsSignInAgain => 'تسجيل الدخول مرة أخرى';
}
