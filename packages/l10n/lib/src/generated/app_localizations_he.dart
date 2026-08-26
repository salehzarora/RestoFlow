// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hebrew (`he`).
class AppLocalizationsHe extends AppLocalizations {
  AppLocalizationsHe([String locale = 'he']) : super(locale);

  @override
  String get dashboardNavActivity => 'יומן פעילות';

  @override
  String get activityLogTitle => 'יומן פעילות';

  @override
  String get activityLogSubtitle =>
      'רישום לקריאה בלבד של פעולות מרכזיות — מי עשה מה, מתי והיכן.';

  @override
  String get activityLogRefresh => 'רענון';

  @override
  String get activityLogDemoNotice =>
      'נתוני הדגמה — פעילות לדוגמה לחקירת היומן לפני חיבור לשרת.';

  @override
  String get activityLogFilterCategory => 'קטגוריה';

  @override
  String get activityLogFilterBranch => 'סניף';

  @override
  String get activityLogBranchAll => 'כל הסניפים המורשים';

  @override
  String get activityLogFilterActor => 'איש צוות';

  @override
  String get activityLogActorAll => 'כל הצוות';

  @override
  String get activityLogSensitiveOnly => 'רגישות בלבד';

  @override
  String get activityLogError => 'טעינת יומן הפעילות נכשלה';

  @override
  String get activityLogErrorHint => 'בדוק את החיבור או ההרשאות ונסה שוב.';

  @override
  String get activityLogEmpty => 'אין פעילות עדיין';

  @override
  String get activityLogEmptyHint => 'פעולות בטווח זה יופיעו כאן.';

  @override
  String get activityLogLoadMore => 'טען עוד';

  @override
  String get activityLogDenied => 'נדחה';

  @override
  String get activityLogClose => 'סגור';

  @override
  String get activityLogActorUnknown => 'לא זמין';

  @override
  String get activityLogEnabled => 'מופעל';

  @override
  String get activityLogDisabled => 'מושבת';

  @override
  String get activityLogChangesHeading => 'מה השתנה';

  @override
  String get activityLogGenericNote =>
      'פעילות זו נרשמה ללא פרטים נוספים הניתנים להצגה.';

  @override
  String get activityLogCategoryAll => 'כל הקטגוריות';

  @override
  String get activityLogCategoryOrders => 'הזמנות';

  @override
  String get activityLogCategoryVoids => 'ביטולים';

  @override
  String get activityLogCategoryDiscounts => 'הנחות';

  @override
  String get activityLogCategoryPayments => 'תשלומים';

  @override
  String get activityLogCategoryShifts => 'משמרות ומזומן';

  @override
  String get activityLogCategoryStaff => 'צוות';

  @override
  String get activityLogCategoryAccess => 'גישה';

  @override
  String get activityLogCategoryDevices => 'מכשירים';

  @override
  String get activityLogCategoryMenu => 'תפריט';

  @override
  String get activityLogCategoryTables => 'שולחנות';

  @override
  String get activityLogCategoryOrganization => 'ארגון';

  @override
  String get activityLogCategorySync => 'סנכרון';

  @override
  String get activityLogCategoryOther => 'אחר';

  @override
  String get activityLogCategorySettings => 'הגדרות ותצורה';

  @override
  String get activityLogTitleBranchSettings => 'הגדרות הסניף עודכנו';

  @override
  String get activityLogTitleRestaurantSettings => 'הגדרות המסעדה עודכנו';

  @override
  String get activityLogTitleOrganizationSettings => 'הגדרות הארגון עודכנו';

  @override
  String get activityLogFieldTimezone => 'אזור זמן';

  @override
  String get activityLogFieldName => 'שם';

  @override
  String get activityLogFieldReceiptPrefix => 'קידומת קבלה';

  @override
  String get activityLogTitleOrderVoided => 'הזמנה בוטלה';

  @override
  String get activityLogTitleVoidAcknowledged => 'המטבח אישר את צפייתו בביטול';

  @override
  String get activityLogTitleVoidAckDenied => 'אישור הצפייה בביטול נדחה';

  @override
  String get activityLogTitleItemsAdded => 'פריטים נוספו להזמנה';

  @override
  String get activityLogTitleItemsAddDenied => 'הוספת פריטים נדחתה';

  @override
  String get activityLogTitleRoundStatusUpdated => 'סטטוס סבב ההגשה עודכן';

  @override
  String get activityLogTitleRoundStatusDenied => 'שינוי סטטוס הסבב נדחה';

  @override
  String get activityLogFieldRoundNumber => 'מספר סבב';

  @override
  String get activityLogFieldAddedItemCount => 'פריטים שנוספו';

  @override
  String get kdsAdditionLabel => 'תוספת';

  @override
  String kdsRoundLabel(int number) {
    return 'סבב $number';
  }

  @override
  String get posAddItemsAction => 'הוספת פריטים';

  @override
  String posAddingToOrderBanner(String orderCode) {
    return 'מוסיפים אל $orderCode';
  }

  @override
  String get posSubmitAddition => 'שליחת התוספת';

  @override
  String get posAdditionPending => 'התוספת בשליחה…';

  @override
  String get posAdditionApplied => 'התוספת נשלחה למטבח';

  @override
  String get posAdditionClearCartFirst =>
      'סיימו או בטלו את הסל הנוכחי לפני הוספה להזמנה אחרת';

  @override
  String get posAdditionFailedRetry => 'התוספת נכשלה — הקישו לניסיון חוזר';

  @override
  String get posAdditionLoadingPending =>
      'בודקים שינויים שלא הושלמו — נסו שוב בעוד רגע';

  @override
  String get posAdditionConflictBlocked =>
      'בהזמנה הזו יש שינויים סותרים שלא הושלמו ויש לפתור אותם לפני עריכה';

  @override
  String get posReadyBellTooltip => 'התראות מוכנות';

  @override
  String get posReadyHistoryTitle => 'היסטוריית התראות';

  @override
  String get posReadyOrderReady => 'ההזמנה מוכנה';

  @override
  String posReadyAdditionReady(int number) {
    return 'התוספת מוכנה — סבב $number';
  }

  @override
  String posReadyGroupedAlert(int count) {
    return '$count הזמנות מוכנות';
  }

  @override
  String get posReadyEmpty => 'אין התראות מוכנות';

  @override
  String get posReadyUnreadLabel => 'לא נקרא';

  @override
  String get posReadyMarkAllRead => 'סמן הכל כנקרא';

  @override
  String get posReadyOpenOrder => 'פתח הזמנה';

  @override
  String posReadyAtTime(String time) {
    return 'מוכן ב-$time';
  }

  @override
  String get posReadyPollingDegraded =>
      'עדכוני המוכנות אינם זמינים זמנית — מנסה שוב';

  @override
  String get posReadyShowMore => 'הצג עוד';

  @override
  String get posAdditionSavedRefreshNeeded =>
      'הפריטים נוספו ונשמרו — תצוגת ההזמנה לא התרעננה. הקישו על רענון לסיום.';

  @override
  String get posReceiptUnavailableRetry =>
      'לא ניתן לטעון את קבלת ההזמנה — בדקו את החיבור ונסו שוב.';

  @override
  String get posAddItemsIneligiblePaid => 'אי אפשר להוסיף להזמנה ששולמה';

  @override
  String get posAddItemsIneligibleStatus => 'אי אפשר עוד להוסיף להזמנה הזו';

  @override
  String get posAddItemsIneligibleTakeaway => 'אי אפשר להוסיף להזמנות איסוף';

  @override
  String get activityLogTitleDiscountApplied => 'הנחה הוחלה';

  @override
  String get activityLogTitleOrderSubmitted => 'הזמנה נשלחה';

  @override
  String get activityLogTitleOrderStatusUpdated => 'סטטוס ההזמנה עודכן';

  @override
  String get activityLogTitleStaffCreated => 'נוסף איש צוות';

  @override
  String get activityLogTitleStaffCapabilities => 'הרשאות הצוות עודכנו';

  @override
  String get activityLogTitleStaffPinSet => 'נקבע קוד PIN לצוות';

  @override
  String get activityLogTitleMembershipGranted => 'הוענקה גישה';

  @override
  String get activityLogTitleMembershipRevoked => 'הגישה בוטלה';

  @override
  String get activityLogTitleRoleUpdated => 'התפקיד שונה';

  @override
  String get activityLogTitleShiftOpened => 'משמרת נפתחה';

  @override
  String get activityLogTitleShiftClosed => 'משמרת נסגרה';

  @override
  String get activityLogTitleShiftReconciled => 'המשמרת יושבה';

  @override
  String get activityLogTitleDeviceAdded => 'נוסף מכשיר';

  @override
  String get activityLogTitleDeviceRevoked => 'מכשיר הוסר';

  @override
  String get activityLogTitleDeviceSignedIn => 'המכשיר התחבר';

  @override
  String get activityLogTitleEmployeeRevoked => 'גישת העובד בוטלה';

  @override
  String get activityLogTitlePaymentRecorded => 'תשלום נרשם';

  @override
  String get activityLogTitleOrganizationCreated => 'הארגון נוצר';

  @override
  String get activityLogFieldWhen => 'מתי';

  @override
  String get activityLogFieldActor => 'על ידי';

  @override
  String get activityLogFieldScopeLocation => 'מיקום';

  @override
  String get activityLogFieldDevice => 'מכשיר';

  @override
  String get activityLogFieldReason => 'סיבה';

  @override
  String get activityLogFieldStatus => 'סטטוס';

  @override
  String get activityLogFieldScope => 'היקף';

  @override
  String get activityLogFieldDiscountType => 'סוג הנחה';

  @override
  String get activityLogFieldValue => 'ערך';

  @override
  String get activityLogFieldAttemptedAction => 'פעולה שנוסתה';

  @override
  String get activityLogFieldOrderType => 'סוג הזמנה';

  @override
  String get activityLogFieldRole => 'תפקיד';

  @override
  String get activityLogFieldFromRole => 'מתפקיד';

  @override
  String get activityLogFieldToRole => 'לתפקיד';

  @override
  String get activityLogFieldDiscountTotal => 'סך הנחה';

  @override
  String get activityLogFieldOrderTotal => 'סך ההזמנה';

  @override
  String get activityLogFieldSubtotal => 'סכום ביניים';

  @override
  String get activityLogFieldLineTotal => 'סך שורה';

  @override
  String get activityLogFieldLineDiscount => 'הנחת שורה';

  @override
  String get activityLogFieldAmount => 'סכום';

  @override
  String get activityLogFieldTendered => 'שולם';

  @override
  String get activityLogFieldChange => 'עודף';

  @override
  String get activityLogFieldOpeningFloat => 'קופה פותחת';

  @override
  String get activityLogFieldExpectedCash => 'מזומן צפוי';

  @override
  String get activityLogFieldCountedCash => 'מזומן שנספר';

  @override
  String get activityLogFieldVariance => 'פער';

  @override
  String get activityLogFieldItemCount => 'פריטים';

  @override
  String get activityLogFieldFailedAttempts => 'ניסיונות כושלים';

  @override
  String get activityLogFieldPinSet => 'PIN נקבע';

  @override
  String get activityLogFieldLocked => 'נעול';

  @override
  String get activityLogCapApplyDiscount => 'החלת הנחה';

  @override
  String get activityLogCapVoidOrder => 'ביטול הזמנה';

  @override
  String get activityLogCapCloseShift => 'סגירת משמרת';

  @override
  String get appName => 'רסטופלו';

  @override
  String get posAppTitle => 'רסטופלו - קופה';

  @override
  String get kdsAppTitle => 'רסטופלו - מסך מטבח';

  @override
  String get dashboardAppTitle => 'רסטופלו - לוח בקרה';

  @override
  String get dashboardBrandName => 'רסטופלו';

  @override
  String get dashboardBrandTagline => 'לוח בקרה';

  @override
  String get adminAppTitle => 'רסטופלו - ניהול';

  @override
  String get welcomeMessage => 'ברוכים הבאים לרסטופלו';

  @override
  String get adminOverviewTitle => 'סקירת הפלטפורמה';

  @override
  String get adminOverviewAsOf => 'נכון ל־';

  @override
  String get adminDemoDataTag => 'נתוני הדגמה';

  @override
  String get adminDemoDataNotice =>
      'נתוני פלטפורמה להדגמה — מחושבים מקומית במכשיר זה, ללא סנכרון לשרת.';

  @override
  String get adminRefresh => 'רענון';

  @override
  String get adminLoading => 'טוען נתוני פלטפורמה…';

  @override
  String get adminError => 'לא ניתן לטעון נתוני פלטפורמה.';

  @override
  String get adminEmpty => 'אין עדיין נתוני פלטפורמה.';

  @override
  String get adminActiveLabel => 'פעיל';

  @override
  String get adminKpiOrganizations => 'ארגונים';

  @override
  String get adminKpiRestaurants => 'מסעדות';

  @override
  String get adminKpiBranches => 'סניפים';

  @override
  String get adminKpiActiveBranches => 'סניפים פעילים';

  @override
  String get adminKpiDevices => 'מכשירים';

  @override
  String get adminKpiAlerts => 'התראות פתוחות';

  @override
  String get adminKpiOrdersToday => 'הזמנות היום';

  @override
  String get adminOrganizationsHeading => 'ארגונים';

  @override
  String get adminBranchHealthHeading => 'תקינות סניפים';

  @override
  String get adminRecentActivityHeading => 'פעילות אחרונה';

  @override
  String get adminCreatedLabel => 'נוצר';

  @override
  String get adminLastActivityLabel => 'פעילות אחרונה';

  @override
  String get adminOrdersTodayShort => 'הזמנות היום';

  @override
  String get adminWarningChip => 'דורש תשומת לב';

  @override
  String get adminRealModeNotice =>
      'נתוני פלטפורמה חיים — לקריאה בלבד ומוגבלים. חלק ממדדי התפעול עדיין אינם זמינים כאן, ואימות רב-שלבי (MFA) לניהול הפלטפורמה וניהול ההרשאות אינם חלק מגרסה זו.';

  @override
  String get adminLiveLimitedTag => 'חי · מוגבל';

  @override
  String get adminNotConfiguredTitle => 'ניהול הפלטפורמה אינו מוגדר';

  @override
  String get adminNotConfiguredBody =>
      'מצב אמיתי נבחר אך חיבור ה-Supabase אינו מוגדר, ולכן לא ניתן לטעון נתוני פלטפורמה. הגדירו את כתובת ה-Supabase ומפתח ה-anon, או הפעילו במצב הדגמה.';

  @override
  String get adminGateTitle => 'לוח ניהול הפלטפורמה';

  @override
  String get adminGateNotOwner =>
      'זהו לוח ניהול הפלטפורמה — לא הלוח של בעל המסעדה.';

  @override
  String get adminGateUseDashboard => 'השתמשו ב-Dashboard לניהול המסעדה.';

  @override
  String get adminGateNotAdminAccount => 'החשבון המחובר אינו מנהל פלטפורמה.';

  @override
  String get adminGateProvisionHint =>
      'גישת מנהל פלטפורמה ניתנת ידנית על ידי מפעיל הפלטפורמה — ראו docs/LOCAL_RUNBOOK.md.';

  @override
  String get adminGateOpenDashboard => 'פתיחת לוח המסעדה';

  @override
  String get adminMfaRequiredTitle => 'נדרש אימות רב-שלבי';

  @override
  String get adminMfaRequiredBody =>
      'לחשבון שלך יש הרשאת מנהל פלטפורמה, אך כניסה זו אינה מאומתת באימות רב-שלבי (MFA). נתוני הפלטפורמה מחייבים סשן מאומת ב-MFA.';

  @override
  String get adminMfaRequiredNextTitle => 'השלימו את האימות הרב-שלבי';

  @override
  String get adminMfaRequiredHint =>
      'אמתו אימות רב-שלבי עבור חשבון מפעיל הפלטפורמה, ואז טענו מחדש. ראו docs/LOCAL_RUNBOOK.md להגדרת אימות מנהל הפלטפורמה.';

  @override
  String get adminSignInTitle => 'כניסת מפעיל פלטפורמה';

  @override
  String get adminSignInInvalid => 'אימייל או סיסמה שגויים.';

  @override
  String get adminMfaEnrollTitle => 'הגדרת אפליקציית אימות';

  @override
  String get adminMfaEnrollBody =>
      'הוסיפו חשבון זה לאפליקציית אימות (למשל Google Authenticator או 1Password) — סרקו את כתובת ההגדרה כקוד QR או הדביקו את מפתח ההגדרה — ואז הזינו את הקוד בן 6 הספרות למטה כדי לסיים.';

  @override
  String get adminMfaSetupKey => 'מפתח הגדרה';

  @override
  String get adminMfaChallengeTitle => 'הזינו את קוד האימות';

  @override
  String get adminMfaChallengeBody =>
      'פתחו את אפליקציית האימות והזינו את הקוד הנוכחי בן 6 הספרות.';

  @override
  String get adminMfaCodeLabel => 'קוד בן 6 ספרות';

  @override
  String get adminMfaVerifyAction => 'אימות';

  @override
  String get adminMfaVerifyFailed =>
      'הקוד לא התקבל. הזינו את הקוד הנוכחי מהאפליקציה.';

  @override
  String get adminMfaEnrollError => 'לא ניתן להתחיל את הגדרת האימות. נסו שוב.';

  @override
  String adminSignedInAs(String email) {
    return 'מחובר כ-$email';
  }

  @override
  String get adminSignInEmailRequired => 'הזינו את אימייל העבודה שלכם.';

  @override
  String get adminSignInPasswordRequired => 'הזינו את הסיסמה.';

  @override
  String get adminSecureConsoleTagline =>
      'קונסולת מפעיל · כל פעולה נרשמת לביקורת';

  @override
  String get adminMfaScanInstruction =>
      'סרקו את קוד ה-QR באפליקציית אימות, או הזינו את מפתח ההגדרה ידנית.';

  @override
  String get adminAccessDeniedTitle => 'הגישה לניהול הפלטפורמה נדחתה';

  @override
  String get adminAccessDeniedBody =>
      'כדי לצפות בנתוני פלטפורמה חיים נדרשים הרשאת ניהול פלטפורמה פעילה והתחברות באימות רב-שלבי (MFA). התחברות מועצמת וניהול הרשאות אינם זמינים בגרסה זו עדיין.';

  @override
  String get localeEnglish => 'אנגלית';

  @override
  String get localeArabic => 'ערבית';

  @override
  String get localeHebrew => 'עברית';

  @override
  String get kdsEmptyState => 'אין כרטיסים פעילים';

  @override
  String get kdsColumnEmpty => 'אין כרטיסים';

  @override
  String get kdsStaleBanner => 'לא מחובר — מוצגים הכרטיסים האחרונים שסונכרנו';

  @override
  String get kdsCancelledCardTitle => 'ההזמנה בוטלה';

  @override
  String get kdsCancelledCardBody =>
      'הקופאי ביטל את ההזמנה — הפסיקו להכין אותה.';

  @override
  String get kdsCancelledAtLabel => 'בוטלה בשעה';

  @override
  String get kdsAcknowledgeCancellation => 'אישור צפייה בביטול';

  @override
  String get kdsAckPending => 'שולח אישור…';

  @override
  String get kdsAckFailed => 'לא ניתן היה לאשר — בדקו את החיבור ונסו שוב.';

  @override
  String get kdsBumpAction => 'סיום';

  @override
  String get kdsRecallAction => 'שחזור';

  @override
  String get kdsAcknowledgeAction => 'אישור קבלה';

  @override
  String get kdsStartAction => 'התחלת הכנה';

  @override
  String get kdsReadyAction => 'סימון כמוכן';

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
  String get kdsDemoFeedBanner => 'הזנת מטבח להדגמה — לא מסונכרנת לשרת';

  @override
  String get kdsColNew => 'חדש';

  @override
  String get kdsColPreparing => 'בהכנה';

  @override
  String get kdsColReady => 'מוכן';

  @override
  String get kdsColCleared => 'נוקה';

  @override
  String get kdsCompleteAction => 'סיום';

  @override
  String get kdsNoteLabel => 'הערה';

  @override
  String get kdsPrepSummaryLabel => 'הכנה';

  @override
  String get kdsTicketPrepHeading => 'הכנת ההזמנה';

  @override
  String kdsMeatTotalLabel(String count, String unit) {
    return 'סיכום הכנה: $count $unit';
  }

  @override
  String kitchenPrepResourceWithOption(String resource, String option) {
    return '$resource עם $option';
  }

  @override
  String kitchenPrepResourceWithoutOption(String resource, String option) {
    return '$resource בלי $option';
  }

  @override
  String kdsElapsedMinutes(int minutes) {
    return '$minutes ד׳';
  }

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
  String posAddToCartWithTotal(String total) {
    return 'הוספה · $total';
  }

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
  String get posSendNeedsTableHint => 'שייכו שולחן כדי לשלוח הזמנת ישיבה במקום';

  @override
  String get posDemoOrderNotice =>
      'הזמנת הדגמה — לא נשלחה לשרת, למטבח או למדפסת.';

  @override
  String posOutboxPending(int count) {
    return '$count ממתינות לסנכרון';
  }

  @override
  String get posOutboxSyncing => 'מסנכרן…';

  @override
  String posOutboxFailed(int count) {
    return '$count נכשלו — נסה שוב';
  }

  @override
  String get posOutboxSynced => 'כל ההזמנות סונכרנו';

  @override
  String get posOutboxAttention => 'הסנכרון דורש טיפול';

  @override
  String get posOutboxRetryAll => 'נסה שוב';

  @override
  String posOutboxResolvedFailures(int count) {
    return '$count שהסתיימו — ניקוי';
  }

  @override
  String get posOutboxClearResolved => 'ניקוי שגיאות שהסתיימו';

  @override
  String posOutboxClearResolvedDone(int count) {
    return 'נוקו $count שגיאות שהסתיימו';
  }

  @override
  String get posStorageWriteRefused => 'המכשיר לא הצליח לשמור הזמנה';

  @override
  String posStorageUnreadable(int count) {
    return '$count רשומות מקומיות לא ניתנות לקריאה';
  }

  @override
  String get posStorageNeedsAttention =>
      'האחסון המקומי דורש טיפול — הרשומות נשמרות אך אינן מסתנכרנות';

  @override
  String get posOrderSubmittedTitle => 'ההזמנה נשלחה';

  @override
  String get posOrderNumberLabel => 'מספר הזמנה';

  @override
  String posReceiptOrderHeading(String orderNumber) {
    return 'הזמנה $orderNumber';
  }

  @override
  String get posReceiptThankYou => 'תודה על ביקורכם';

  @override
  String get posOrderRejectedTitle => 'ההזמנה לא נשלחה';

  @override
  String get posOrderDeliveryUnconfirmedTitle => 'שליחת ההזמנה לא אושרה';

  @override
  String get posSyncDeliveryUnconfirmed =>
      'לא הצלחנו לאמת אם ההזמנה הגיעה לשרת. בדוק את החיבור ושלח שוב את אותה ההזמנה — הפעולה בטוחה וההזמנה לא תישלח פעמיים.';

  @override
  String get posSyncStateUnconfirmed => 'לא אושר';

  @override
  String get posOrderPendingTitle => 'ההזמנה ממתינה לשליחה';

  @override
  String get posOrderStatusSubmitted => 'נשלחה';

  @override
  String get posNewOrder => 'הזמנה חדשה';

  @override
  String get posOrderTypeLabel => 'סוג הזמנה';

  @override
  String get posOrderTypeDineIn => 'ישיבה במקום';

  @override
  String get posOrderTypeTakeaway => 'טייק אווי';

  @override
  String get posTableLabel => 'שולחן';

  @override
  String get customerNameLabel => 'שם לקוח';

  @override
  String get customerNamePlaceholder => 'אופציונלי';

  @override
  String get customerNameReceiptLabel => 'לקוח';

  @override
  String get customerNameKitchenLabel => 'לקוח';

  @override
  String get customerPhoneLabel => 'טלפון הלקוח';

  @override
  String get customerPhonePlaceholder => 'אופציונלי';

  @override
  String get customerPhoneReceiptLabel => 'טלפון';

  @override
  String get customerPhoneKitchenLabel => 'טלפון';

  @override
  String get customerPhoneErrorChars =>
      'יש להשתמש רק בספרות, רווחים ו- + - ( )';

  @override
  String get customerPhoneErrorDigits => 'יש להזין לפחות 5 ספרות';

  @override
  String get customerPhoneErrorInvalid => 'יש להזין מספר טלפון תקין';

  @override
  String get posCompleteOrder => 'סיום הזמנה';

  @override
  String get posCompleteOrderSuccess => 'ההזמנה הושלמה';

  @override
  String get posCompleteOrderFailure => 'לא ניתן היה לסיים את ההזמנה';

  @override
  String get posClosePaymentRequired => 'יש לגבות תשלום כדי לסיים';

  @override
  String get posCloseKdsRequired => 'מסך המטבח מסיים הזמנה זו';

  @override
  String get posCloseWorkflowUnavailable => 'מצב המטבח אינו זמין';

  @override
  String get posKitchenModeLoading => 'בודק את הגדרת המטבח…';

  @override
  String get posKitchenModeRetry => 'נסה שוב';

  @override
  String get posAssignTable => 'שיוך שולחן';

  @override
  String get posChangeTable => 'החלפת שולחן';

  @override
  String get posClearTableAssignment => 'הסרת שולחן';

  @override
  String get posTableRequiredWarning => 'הזמנות לישיבה במקום דורשות שולחן';

  @override
  String get posTableNotNeeded => 'אין צורך בשולחן לטייק אווי';

  @override
  String get posTablePickerTitle => 'בחירת שולחן';

  @override
  String get posTableStatusAvailable => 'פנוי';

  @override
  String get posTableStatusOccupied => 'תפוס';

  @override
  String get posTableStatusBlocked => 'לא בשירות';

  @override
  String posTableSeats(int count) {
    return '$count מקומות';
  }

  @override
  String get posTablesDemoNotice => 'שולחנות הדגמה — לא נטענו משרת.';

  @override
  String get posTablesEmpty => 'אין שולחנות להצגה';

  @override
  String get posTablesError => 'טעינת השולחנות נכשלה';

  @override
  String get posTableStatusSelected => 'נבחר';

  @override
  String get posTableAreaMain => 'אזור הסעדה ראשי';

  @override
  String get posTableAreaPatio => 'מרפסת';

  @override
  String get posTablesAisleLabel => 'מעבר';

  @override
  String get posTablesEdgeEntrance => 'כניסה';

  @override
  String get posTablesEdgeCounter => 'דלפק';

  @override
  String get posTablesLayoutEditorHint =>
      'מיקומי השולחנות הם להדגמה בלבד — עורך הפריסה יגיע בהמשך.';

  @override
  String posTableSelectedSemantic(String label) {
    return '$label, נבחר';
  }

  @override
  String get posSyncSectionTitle => 'סטטוס סנכרון';

  @override
  String get posSyncStatePending => 'ממתין לסנכרון';

  @override
  String get posSyncStateSending => 'שולח…';

  @override
  String get posSyncStateSynced => 'סונכרן';

  @override
  String get posSyncStateFailed => 'הסנכרון נכשל';

  @override
  String get posSyncStoredLocally => 'נשמר מקומית — ממתין לסנכרון עם השרת';

  @override
  String get posSyncDemoNotice => 'סנכרון הדגמה — לא נשלח לשרת אמיתי';

  @override
  String get posSyncNow => 'סנכרן עכשיו (הדגמה)';

  @override
  String get posSyncRetry => 'נסה שוב';

  @override
  String get posOutboxRefLabel => 'מזהה תור יוצא';

  @override
  String get posSubmitFailed => 'לא ניתן היה להוסיף את ההזמנה לתור — נסה שוב';

  @override
  String posSyncPendingCount(int count) {
    return '$count ממתינים לסנכרון';
  }

  @override
  String get posPayCash => 'תשלום במזומן';

  @override
  String get posPaymentTitle => 'תשלום מזומן';

  @override
  String get posAmountDue => 'סכום לתשלום';

  @override
  String get posCashReceived => 'מזומן שהתקבל';

  @override
  String get posCashExact => 'מדויק';

  @override
  String get posChangeDue => 'עודף';

  @override
  String get posConfirmPayment => 'אישור תשלום';

  @override
  String get posCashInvalid => 'הזן סכום תקין';

  @override
  String get posCashInsufficient => 'המזומן שהתקבל חייב לכסות את הסכום לתשלום';

  @override
  String get posPaidChip => 'שולם';

  @override
  String get posPaymentMethodLabel => 'אמצעי תשלום';

  @override
  String get posPaymentMethodCash => 'מזומן';

  @override
  String get posPaidAtLabel => 'שולם בשעה';

  @override
  String get posReceiptTitle => 'קבלה';

  @override
  String get printRestaurantNameFallback => 'מסעדה';

  @override
  String get posReceiptNumberLabel => 'מס׳ קבלה';

  @override
  String get posReceiptTotal => 'סך הכול';

  @override
  String get posReceiptProvisionalNote => 'זמני — יותאם לקבלת שרת בעת סנכרון';

  @override
  String get posReceiptDemoNote => 'קבלת הדגמה — אין מדפסת מחוברת';

  @override
  String get posPrintReceiptDemo => 'הדפסת קבלה (הדגמה)';

  @override
  String get printPreviewAction => 'תצוגת הדפסה';

  @override
  String get printPreviewPrint => 'הדפס';

  @override
  String get printPreviewClose => 'סגור';

  @override
  String get printPreviewHint =>
      'השתמש בהדפסת הדפדפן (Ctrl+P) כדי להדפיס תצוגה זו';

  @override
  String get deviceSettingsMenuTooltip => 'תפריט המכשיר';

  @override
  String get deviceSettingsTitle => 'הגדרות מכשיר';

  @override
  String get deviceRefreshAction => 'רענון החיבור';

  @override
  String get deviceUnpairAction => 'ביטול צימוד המכשיר';

  @override
  String get deviceUnpairWarning =>
      'השתמשו בזה רק אם צריך לצמד את המכשיר הזה מחדש.';

  @override
  String get deviceUnpairConfirm => 'בטל צימוד';

  @override
  String get deviceUnpairCancel => 'ביטול';

  @override
  String get deviceSettingsAppTypeLabel => 'סוג היישום';

  @override
  String get deviceSettingsAppTypePos => 'קופה (POS)';

  @override
  String get deviceSettingsAppTypeKds => 'מסך מטבח (KDS)';

  @override
  String get deviceSettingsRestaurantLabel => 'מסעדה';

  @override
  String get deviceSettingsBranchLabel => 'סניף';

  @override
  String get deviceSettingsDeviceLabel => 'מכשיר';

  @override
  String get deviceSettingsPairingLabel => 'צימוד';

  @override
  String get deviceSettingsPairingActive => 'מצומד';

  @override
  String get deviceSettingsPinSessionLabel => 'משמרת עובד';

  @override
  String get deviceSettingsPinSessionActive => 'מחובר';

  @override
  String get deviceSettingsPinSessionNone => 'לא מחובר';

  @override
  String get deviceSettingsDemoNote => 'מצב הדגמה — אין מכשיר מצומד.';

  @override
  String get deviceSettingsUnavailable => 'פרטי המכשיר אינם זמינים.';

  @override
  String get deviceSettingsPrintersHeading => 'מדפסות';

  @override
  String get deviceSettingsNoPrinter =>
      'לא הוקצתה מדפסת. בקשו ממנהל להגדיר אותה ב-Dashboard ← מדפסות.';

  @override
  String get deviceSettingsBridgeRequired => 'מוגדרת בלבד — נדרש גשר הדפסה.';

  @override
  String get deviceSettingsCapabilityNote =>
      'הדפסה דורשת גשר הדפסה/אפליקציה מקורית. גרסה זו שומרת הגדרות ויוצרת/מציגה עבודות הדפסה.';

  @override
  String deviceSettingsLastRefresh(String time) {
    return 'רענון אחרון: $time';
  }

  @override
  String get deviceSettingsLoadError => 'לא ניתן לטעון את הקצאות המדפסות.';

  @override
  String get deviceSettingsPrinterDisabled => 'מושבתת ב-Dashboard';

  @override
  String deviceSettingsRouteStations(String names) {
    return 'תחנות: $names';
  }

  @override
  String get deviceRefreshedSnack => 'החיבור רוענן.';

  @override
  String get deviceUnpairedSnack => 'צימוד המכשיר בוטל.';

  @override
  String get deviceSettingsAutoPrintHeading => 'הדפסה אוטומטית';

  @override
  String get posAutoPrintReceiptToggle => 'הדפסת קבלה אוטומטית לאחר תשלום';

  @override
  String get kdsAutoPrintAcknowledgeToggle =>
      'הדפסת כרטיס מטבח אוטומטית באישור קבלה';

  @override
  String get autoPrintNoPrinterNote => 'מושבת — לא הוקצתה מדפסת.';

  @override
  String get autoPrintReceiptNoPrinterNote => 'מושבת — לא הוקצתה מדפסת קבלה.';

  @override
  String get autoPrintKitchenNoPrinterNote =>
      'הדפסה אוטומטית של כרטיס מטבח דורשת מדפסת מטבח מוגדרת.';

  @override
  String get posAutoPrintKitchenTicketToggle => 'הדפסה אוטומטית של כרטיס מטבח';

  @override
  String get posAutoPrintKitchenTicketToggleExplanation =>
      'כשמופעל, כרטיס מטבח מודפס אוטומטית ממכשיר הקופה הזה לאחר הזמנה מוצלחת. ההזמנה עדיין נשלחת למסך המטבח כרגיל.';

  @override
  String get posFinishAllKitchenOrders => 'סיום כל הזמנות המטבח';

  @override
  String get posFinishAllConfirmAction => 'סיים הכול';

  @override
  String get posFinishAllConfirmBody =>
      'כל הזמנות המטבח הפעילות יסתיימו ויוסרו ממסך המטבח. הזמנות שלא שולמו יישארו זמינות לתשלום בהיסטוריית ההזמנות.';

  @override
  String get posFinishAllNoActiveOrders => 'אין הזמנות מטבח פעילות';

  @override
  String posFinishAllResult(int count) {
    return 'הסתיימו $count הזמנות מטבח';
  }

  @override
  String posFinishAllResultWithFailures(int finished, int failed) {
    return 'הסתיימו $finished הזמנות מטבח, $failed לא הסתיימו (עדיין מוצגות לניסיון חוזר)';
  }

  @override
  String get posPrintKitchenTicketAction => 'הדפסה למטבח';

  @override
  String get posKitchenTicketPrintedSnack => 'כרטיס המטבח נשלח למדפסת';

  @override
  String get posKitchenTicketPrintFailedSnack =>
      'לא ניתן היה להדפיס את כרטיס המטבח';

  @override
  String get posKitchenPrinterNotConfiguredSnack =>
      'לא הוגדרה מדפסת מטבח. הגדר אחת בהגדרות המכשיר.';

  @override
  String get printStatusNotConfigured => 'לא הוגדרה מדפסת';

  @override
  String get printStatusWaitingForPrinter => 'ממתין למוכנות המדפסת…';

  @override
  String get printStatusPrepared =>
      'עבודת ההדפסה הוכנה — הדפסה פיזית דורשת גשר הדפסה.';

  @override
  String get printStatusPrinted => 'הודפס';

  @override
  String get printStatusFailed => 'ההדפסה נכשלה';

  @override
  String get printStatusSentToPrinter => 'נשלח למדפסת (ללא אישור הדפסה בפועל)';

  @override
  String get printStatusBridgeUnavailable =>
      'גשר ההדפסה אינו זמין — העבודה לא נשלחה';

  @override
  String get printRetryAction => 'נסה שוב';

  @override
  String get printReprintAction => 'הדפסה חוזרת';

  @override
  String get deviceSettingsBridgeConnected => 'גשר הדפסה: מחובר';

  @override
  String get deviceSettingsBridgeUnavailable => 'גשר הדפסה: לא זמין';

  @override
  String deviceSettingsBridgeLastJob(String time) {
    return 'עבודת ההדפסה האחרונה: $time';
  }

  @override
  String get posReceiptPrintLabel => 'הדפסת קבלה';

  @override
  String get kdsTicketPrintLabel => 'הדפסת מטבח';

  @override
  String get receiptPreviewTitle => 'תצוגת הדפסת קבלה';

  @override
  String get receiptDemoRestaurantName => 'מסעדת RestoFlow להדגמה';

  @override
  String get kdsPreviewTicketAction => 'תצוגת כרטיס';

  @override
  String get kdsTicketPreviewTitle => 'תצוגת הדפסת כרטיס מטבח';

  @override
  String get kdsElapsedLabel => 'שחלף';

  @override
  String get languageSelectorTooltip => 'שפה';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageHebrew => 'עברית';

  @override
  String get posShiftDemoName => 'משמרת בוקר להדגמה';

  @override
  String get posDrawerLabel => 'מגירת מזומן';

  @override
  String get posDrawerOpen => 'פתוחה';

  @override
  String get posDrawerClosed => 'סגורה';

  @override
  String get posCashInDrawer => 'מזומן במגירה';

  @override
  String get posLastCashPayment => 'תשלום מזומן אחרון';

  @override
  String get posShiftDemoNote =>
      'הדגמה — ההתאמה מחושבת מקומית ואינה נשמרת בשרת.';

  @override
  String get posShiftRealName => 'המשמרת הנוכחית';

  @override
  String get posShiftRealNote => 'נפתחה בכניסה — סכומי המזומן מנוהלים בשרת';

  @override
  String get posShiftCloseTitle => 'סגירת משמרת וספירת מזומן';

  @override
  String get posShiftCloseMenuItem => 'סגירת משמרת';

  @override
  String get posShiftCloseConfirmTitle => 'לסגור משמרת זו?';

  @override
  String get posShiftCloseConfirmBody =>
      'המשמרת תיסגר עם הסכום שנספר ולא ניתן לפתוח מחדש.';

  @override
  String get posShiftCancelAction => 'ביטול';

  @override
  String get posShiftCloseAction => 'סגור משמרת';

  @override
  String get posShiftDoneAction => 'סיום';

  @override
  String get posShiftNoOpenShift => 'אין משמרת פתוחה במכשיר זה.';

  @override
  String get posShiftNoOpenShiftHint => 'משמרת נפתחת אוטומטית בכניסת קופאי.';

  @override
  String get posShiftOpenedAt => 'נפתחה בשעה';

  @override
  String get posShiftEmployee => 'עובד';

  @override
  String get posMenuChangeAvailability => 'שינוי זמינות';

  @override
  String get posMenuAvailAvailable => 'זמין';

  @override
  String get posMenuAvailabilityOffline =>
      'לא ניתן היה לשנות זמינות במצב לא מקוון';

  @override
  String get posMenuAvailabilityDenied =>
      'פעולה זו דורשת הרשאת ניהול זמינות תפריט';

  @override
  String get posMenuAvailabilityFailed => 'לא ניתן היה לשנות את הזמינות';

  @override
  String get posRecoveryOrderNotCreated => 'ההזמנה לא נוצרה';

  @override
  String get posRecoveryUnavailableItems => 'הפריטים הבאים אינם זמינים עוד:';

  @override
  String get posRecoveryMenuRefreshed => 'התפריט עודכן.';

  @override
  String get posRecoveryBackToCart => 'חזרה לעגלה';

  @override
  String get posRecoveryEditOrder => 'עריכת הזמנה';

  @override
  String get posRecoveryDiscardDraft => 'מחיקת טיוטה';

  @override
  String get posRecoveryDiscardConfirmTitle => 'למחוק את ניסיון ההזמנה?';

  @override
  String get posRecoveryDiscardConfirmBody =>
      'ההזמנה לא נוצרה, ולכן שום דבר לא מבוטל בשרת. הטיוטה שלך תימחק.';

  @override
  String get posRecoveryRemoveUnavailableHint =>
      'הסר את הפריטים שאינם זמינים ושלח שוב.';

  @override
  String get posRecoveryReplaceCartTitle => 'להחליף את העגלה הנוכחית?';

  @override
  String get posRecoveryReplaceCartBody =>
      'בעגלה כבר יש פריטים. שחזור טיוטה זו יחליף אותם.';

  @override
  String get posRecoveryReplaceCartAction => 'החלף עגלה נוכחית';

  @override
  String get posRecoveryKeepCartAction => 'השאר עגלה נוכחית';

  @override
  String get posRecentOrderNotCreated => 'לא נוצרה';

  @override
  String get posRecoveryOtherSession => 'טיוטה דחויה זו שייכת להפעלה אחרת';

  @override
  String get posTableOperations => 'פעולות שולחנות';

  @override
  String get posTableManualStatus => 'סטטוס ידני';

  @override
  String get posTableEffectiveStatus => 'סטטוס בפועל';

  @override
  String get posTableMarkAvailable => 'סמן כפנוי';

  @override
  String get posTableMarkReserved => 'סמן כשמור';

  @override
  String get posTableMarkOccupied => 'סמן כתפוס';

  @override
  String get posTableMarkOutOfService => 'סמן כלא זמין';

  @override
  String get posTableStateAvailable => 'פנוי';

  @override
  String get posTableStateReserved => 'שמור';

  @override
  String get posTableStateOccupied => 'תפוס';

  @override
  String get posTableStateOutOfService => 'לא זמין';

  @override
  String get posTableLinkAnother => 'קישור שולחן נוסף';

  @override
  String get posTableSelectToLink => 'בחר שולחן לקישור';

  @override
  String get posTableLinked => 'שולחנות מקושרים';

  @override
  String get posTableUnlink => 'ביטול קישור שולחנות';

  @override
  String get posTableUnlinkConfirmTitle => 'לבטל את קישור השולחנות?';

  @override
  String get posTableActiveOrders => 'הזמנות פעילות';

  @override
  String get posTableOccupiedByOrder => 'תפוס בהזמנה פעילה';

  @override
  String get posTableRequiresPermission => 'פעולה זו דורשת הרשאת ניהול שולחנות';

  @override
  String get posTableOutOfServiceCannotOrder =>
      'שולחן שאינו זמין אינו יכול לקבל הזמנה';

  @override
  String get posTableStatusOffline =>
      'לא ניתן היה לשנות את סטטוס השולחן במצב לא מקוון';

  @override
  String get posTableStatusFailed => 'לא ניתן היה לשנות את סטטוס השולחן';

  @override
  String get posTableLinkFailed => 'לא ניתן היה לקשר את השולחנות';

  @override
  String get posTableUnlinkFailed => 'לא ניתן היה לבטל את קישור השולחנות';

  @override
  String get posTableAlreadyGrouped => 'שולחן זה כבר בקבוצה';

  @override
  String get posTableGroup => 'קבוצת שולחנות';

  @override
  String get posTableGroupSectionTitle => 'שולחנות מקושרים';

  @override
  String get posTableGroupDetailTitle => 'קבוצה מקושרת';

  @override
  String get posTableGroupMembers => 'שולחנות בקבוצה';

  @override
  String get posTableGroupChoosePrompt => 'בחרו שולחן להזמנה החדשה';

  @override
  String get posTableGroupNoAssignable =>
      'אף שולחן בקבוצה זו אינו יכול לקבל הזמנה חדשה כעת';

  @override
  String get posTableGroupSelectAction => 'בחירה';

  @override
  String get posTableGroupJoiner => ' + ';

  @override
  String get posShiftOpeningFloat => 'קופה פותחת';

  @override
  String get posShiftExpectedCash => 'מזומן צפוי';

  @override
  String get posShiftExpectedAtClose => 'המזומן הצפוי מחושב בשרת בעת הסגירה.';

  @override
  String get posShiftCountedLabel => 'מזומן שנספר';

  @override
  String get posShiftInvalidAmount => 'הזן סכום תקין.';

  @override
  String get posShiftReasonLabel => 'סיבה (חובה אם יש הפרש)';

  @override
  String get posShiftReasonRequired =>
      'הזן סיבה כאשר המזומן שנספר שונה מהצפוי.';

  @override
  String get posShiftClosedTitle => 'המשמרת נסגרה';

  @override
  String get posShiftBalanced => 'מאוזן';

  @override
  String get posShiftOver => 'עודף';

  @override
  String get posShiftShort => 'חוסר';

  @override
  String get posShiftDifference => 'הפרש';

  @override
  String get posShiftCloseUnavailable =>
      'הסגירה אינה זמינה — נדרשת התחברות עובד במכשיר מקושר.';

  @override
  String get posShiftClosePermissionDenied => 'אינך מורשה לסגור משמרת זו.';

  @override
  String get posShiftCloseServerRejected =>
      'השרת דחה את הסגירה — ייתכן שנדרשת סיבה או שמצב המשמרת אינו תקין.';

  @override
  String get posShiftCloseFailed => 'לא ניתן לסגור את המשמרת.';

  @override
  String get posShiftCouldNotRestore =>
      'לא ניתן לשחזר את מצב המשמרת. היכנס שוב כדי לפתוח משמרת.';

  @override
  String get posShiftOwnerMismatch =>
      'כבר פתוחה משמרת במכשיר זה, שנפתחה על ידי עובד אחר. רק בעליה או מנהל יכולים לסגור אותה — התנתק כדי שיוכלו להיכנס.';

  @override
  String get posShiftCloseNotAllowed =>
      'אין לך הרשאה לסגור משמרת זו. בקש ממנהל לסגור אותה או להפעיל עבורך הרשאת סגירת משמרת.';

  @override
  String get posShiftAuthorizationPending =>
      'בודק הרשאות משמרת… סגירה אינה זמינה עד לאישור.';

  @override
  String get posShiftReturnToPin => 'התנתקות';

  @override
  String get posSyncSendingReal => 'שולח לשרת…';

  @override
  String get posSyncSentReal => 'נשלח — מסך המטבח מקבל אותה אוטומטית.';

  @override
  String get posSyncFailedReal => 'השרת דחה את ההזמנה — היא לא נשלחה למטבח.';

  @override
  String get posSyncSendNow => 'שלח עכשיו';

  @override
  String get posReceiptNoPrinterNote => 'הדפסה עדיין אינה מחוברת במכשיר זה';

  @override
  String get posModifierRequired => 'חובה';

  @override
  String get posModifierOptional => 'אופציונלי';

  @override
  String get posModifierChooseOne => 'בחרו אפשרות אחת';

  @override
  String posModifierSelectedCount(int selected, int max) {
    return '$selected/$max';
  }

  @override
  String posModifierSelectedCountOpen(int selected) {
    return '$selected';
  }

  @override
  String get posModifierFree => 'חינם';

  @override
  String posModifierBasePrice(String price) {
    return 'מחיר בסיס · $price';
  }

  @override
  String get posModifierQuantityLabel => 'כמות';

  @override
  String get posModifierItemNoteLabel => 'הערה לפריט';

  @override
  String get posModifierItemNoteHint => 'לדוגמה: בלי בצל, תוספת רוטב';

  @override
  String get posItemNoteLabel => 'הערה';

  @override
  String get dashboardOverviewHeading => 'סקירת היום';

  @override
  String get dashboardTodaySales => 'מכירות היום';

  @override
  String get dashboardOrders => 'הזמנות';

  @override
  String get dashboardAvgOrderValue => 'ערך הזמנה ממוצע';

  @override
  String get dashboardCompletedOrders => 'הזמנות שהושלמו';

  @override
  String get dashboardOpenOrders => 'הזמנות פתוחות';

  @override
  String get dashboardDailySummary => 'סיכום יומי';

  @override
  String get dashboardNetSales => 'מכירות נטו';

  @override
  String get dashboardDiscounts => 'הנחות';

  @override
  String get dashboardVoids => 'ביטולים';

  @override
  String get dashboardCashCollected => 'מזומן שנאסף';

  @override
  String get dashboardCashVariance => 'פער מזומן';

  @override
  String get dashboardShiftCashTitle => 'משמרת ומזומן';

  @override
  String dashboardShiftClosedToday(int count) {
    return '$count נסגרו היום';
  }

  @override
  String dashboardShiftOpenNow(int count) {
    return '$count פתוחות כעת';
  }

  @override
  String get dashboardShiftExpectedCash => 'מזומן צפוי';

  @override
  String get dashboardShiftLastClosed => 'המשמרת האחרונה שנסגרה';

  @override
  String dashboardShiftClosedBy(String name) {
    return 'נסגרה על ידי $name';
  }

  @override
  String get dashboardShiftNoneToday => 'עדיין לא נסגרו משמרות היום.';

  @override
  String get dashboardShiftStatus => 'משמרת';

  @override
  String get dashboardSalesByBranch => 'מכירות לפי סניף';

  @override
  String get dashboardTopItems => 'פריטים מובילים';

  @override
  String get dashboardDemoNotice => 'נתוני הדגמה — לא משרת חי.';

  @override
  String get dashboardReportsHeading => 'דוחות הבעלים';

  @override
  String get dashboardReportDayLabel => 'יום הדוח';

  @override
  String get dashboardDemoDay => 'יום הדגמה';

  @override
  String get dashboardRefresh => 'רענון';

  @override
  String get dashboardLoadingReports => 'טוען דוחות…';

  @override
  String get dashboardReportsError => 'לא ניתן לטעון דוחות.';

  @override
  String get dashboardRetry => 'נסה שוב';

  @override
  String get dashboardNoReportData => 'אין נתוני דוח ליום זה.';

  @override
  String get dashboardNoDataForRange => 'אין נתונים לתקופה שנבחרה.';

  @override
  String get dashboardDemoReportsNotice =>
      'דוחות הדגמה — מחושבים מקומית מהזמנות לדוגמה, ללא סנכרון לשרת.';

  @override
  String get dashboardRealModeNotice =>
      'דוחות חיים — לקריאה בלבד ומוגבלים. חלק מהנתונים עדיין לא זמינים כאן.';

  @override
  String get dashboardLiveDataTag => 'חי · מוגבל';

  @override
  String get dashboardLiveReportsTitle => 'דוחות חיים';

  @override
  String get dashboardLiveReportsPending =>
      'ניתוח מפורט — מכירות לפי שעה, פריטים מובילים, מכירות לפי סניף והזמנות אחרונות — יופיע כאן לאחר הפעלת הדוחות המלאים.';

  @override
  String adminDevicesShownCount(int count) {
    return '$count מכשירים';
  }

  @override
  String adminDevicesRevokedCount(int count) {
    return '$count מבוטלים';
  }

  @override
  String get adminDevicesRevokedSection => 'מכשירים שבוטלו';

  @override
  String get dashboardGrossSales => 'מכירות ברוטו';

  @override
  String get dashboardCashSales => 'מכירות במזומן';

  @override
  String get dashboardUnpaidOrders => 'הזמנות שלא שולמו';

  @override
  String get dashboardPaymentMix => 'תמהיל תשלומים';

  @override
  String get dashboardPaymentSummary => 'סיכום תשלום ומזומן';

  @override
  String get dashboardOpeningFloat => 'קופה פתיחה';

  @override
  String get dashboardExpectedDrawer => 'צפוי במגירה';

  @override
  String get dashboardCountedCash => 'מזומן שנספר';

  @override
  String get dashboardLastCashPayment => 'תשלום מזומן אחרון';

  @override
  String get dashboardPaymentMethods => 'אמצעי תשלום';

  @override
  String get dashboardPaymentMethodCash => 'מזומן';

  @override
  String get dashboardRecentOrders => 'הזמנות אחרונות';

  @override
  String get dashboardRecentOrdersViewAll => 'הצג הכול';

  @override
  String get dashboardPaid => 'שולם';

  @override
  String get dashboardUnpaid => 'לא שולם';

  @override
  String get authLoadingAccount => 'טוען חשבון…';

  @override
  String get authSignInRequired => 'נדרשת התחברות';

  @override
  String get authContinue => 'המשך';

  @override
  String get authChooseLocation => 'בחר מיקום';

  @override
  String get authNoAccess => 'אין גישה פעילה';

  @override
  String get authWrongRole => 'תפקיד זה אינו יכול להשתמש באפליקציה זו';

  @override
  String get authAccessDenied => 'הגישה לחשבון נדחתה';

  @override
  String get authError => 'משהו השתבש';

  @override
  String get authRealModeUnconfiguredTitle => 'מצב אמת אינו מוגדר';

  @override
  String get authRealModeUnconfiguredBody =>
      'האפליקציה הופעלה במצב אמת, אך הגדרות החיבור לשרת חסרות או שגויות. RestoFlow לעולם אינו מזייף שרת, ולכן מצב האמת נשאר נעול עד שיסופקו הגדרות תקינות.';

  @override
  String get authRealModeUnconfiguredHowTo =>
      'הפעל את האפליקציה עם הערכים הבאים';

  @override
  String get authRealModeUnconfiguredDemoHint =>
      'כדי לנסות את הדמו במקום זאת, הפעל את האפליקציה ללא כל הגדרה — מצב הדמו הוא ברירת המחדל.';

  @override
  String get authProductionDemoBlockedTitle =>
      'מצב הדגמה פעיל עם פרטי התחברות אמיתיים';

  @override
  String get authProductionDemoBlockedBody =>
      'לגרסה זו יש הגדרות חיבור שרת תקפות אך היא פועלת במצב הדגמה, ולכן היא תציג נתוני הדגמה כאילו היו אמיתיים. כבה את מצב ההדגמה כדי להציג נתונים אמיתיים, או הסר את הגדרות החיבור כדי להריץ את ההדגמה. RestoFlow לעולם אינו מציג נתוני הדגמה כנתוני ייצור.';

  @override
  String get authDeviceSignInUnavailableTitle => 'כניסת המכשיר אינה זמינה';

  @override
  String get offlineBootTitle => 'אין חיבור';

  @override
  String get offlineBootMessage => 'בדוק את חיבור ה-Wi-Fi ונסה שוב';

  @override
  String get offlineBootRetry => 'נסה שוב';

  @override
  String get offlineBootAutoReconnect =>
      'השאירו מסך זה פתוח — הוא יתחבר מחדש אוטומטית.';

  @override
  String get authDeviceSignInUnavailableBody =>
      'כניסת מכשירים אנונימית מושבתת או שאימות Supabase אינו מוגדר.';

  @override
  String get authDeviceSignInUnavailableHowTo => 'איך לתקן';

  @override
  String get authDeviceSignInUnavailableFix =>
      'אפשרו כניסה אנונימית בהגדרות האימות של Supabase, הפעילו מחדש את השרת ואז את האפליקציה. אין צורך בחשבון אישי במכשיר זה — הצימוד מחבר את המכשיר בעצמו.';

  @override
  String get authTryAgain => 'נסה שוב';

  @override
  String get authSignOut => 'התנתק';

  @override
  String get authPlatformAdmin => 'מנהל פלטפורמה';

  @override
  String get authOrganization => 'ארגון';

  @override
  String get authRestaurant => 'מסעדה';

  @override
  String get authBranch => 'סניף';

  @override
  String get authRole => 'תפקיד';

  @override
  String get authRoleOwner => 'בעלים';

  @override
  String get authRoleRestaurantOwner => 'בעל מסעדה';

  @override
  String get authRoleManager => 'מנהל';

  @override
  String get authRoleCashier => 'קופאי';

  @override
  String get authRoleKitchenStaff => 'צוות מטבח';

  @override
  String get authRoleAccountant => 'רואה חשבון';

  @override
  String get authComingSoon => 'בקרוב';

  @override
  String get dashboardNavOverview => 'סקירה';

  @override
  String get dashboardNavMenu => 'תפריט';

  @override
  String get menuManagementTitle => 'ניהול תפריט';

  @override
  String get menuDemoBanner =>
      'נתוני דמו — השינויים נשמרים במכשיר זה בלבד ועדיין לא נשמרים בשרת.';

  @override
  String get menuCategoriesHeading => 'קטגוריות';

  @override
  String get menuItemsHeading => 'פריטים';

  @override
  String get menuSelectCategoryHint => 'בחר קטגוריה כדי לראות את הפריטים שלה.';

  @override
  String get menuEmptyCategories => 'אין עדיין קטגוריות.';

  @override
  String get menuEmptyItems => 'אין עדיין פריטים בקטגוריה זו.';

  @override
  String get menuLoadError => 'לא ניתן לטעון את התפריט.';

  @override
  String get menuRetry => 'נסה שוב';

  @override
  String menuItemCount(int count) {
    return '$count פריטים';
  }

  @override
  String get menuCategoryIconLabel => 'סמל הקטגוריה';

  @override
  String get menuCategoryIconChange => 'שינוי';

  @override
  String get menuCategoryIconReset => 'איפוס לאוטומטי';

  @override
  String get menuCategoryIconAutomatic => 'אוטומטי';

  @override
  String get menuCategoryIconAutomaticHint => 'נבחר אוטומטית';

  @override
  String get menuCategoryIconCustom => 'סמל מותאם';

  @override
  String get menuCategoryIconPickerTitle => 'בחירת סמל קטגוריה';

  @override
  String get menuCategoryIconSearchHint => 'חיפוש סמלים';

  @override
  String get menuCategoryIconNoResults => 'לא נמצאו סמלים תואמים';

  @override
  String get menuCategoryIconSelected => 'נבחר';

  @override
  String menuCategoryIconName(String iconKey) {
    String _temp0 = intl.Intl.selectLogic(iconKey, {
      'meals': 'מנות',
      'dinner': 'ארוחת ערב',
      'grill': 'גריל',
      'rice': 'קערת אורז',
      'noodles': 'נודלס',
      'soup': 'מרק',
      'set_meal': 'ארוחה מוגשת',
      'bento': 'קופסת בנטו',
      'skewers': 'שיפודים',
      'tapas': 'מתאבנים',
      'burger': 'המבורגר',
      'fast_food': 'מזון מהיר',
      'pizza': 'פיצה',
      'takeaway': 'טייק אווי',
      'delivery': 'משלוח',
      'room_service': 'שירות חדרים',
      'kids_meal': 'ארוחת ילדים',
      'bakery': 'מאפים',
      'breakfast': 'ארוחת בוקר',
      'brunch': 'בראנץ',
      'eggs': 'ביצים',
      'cake': 'עוגה',
      'cookie': 'עוגיות',
      'donut': 'דונאט',
      'ice_cream': 'גלידה',
      'celebration': 'חגיגה',
      'drinks': 'משקאות',
      'bar': 'קוקטיילים',
      'wine': 'יין',
      'spirits': 'אלכוהול',
      'beer': 'בירה',
      'nightlife': 'חיי לילה',
      'water': 'מים',
      'cold': 'משקאות קרים',
      'coffee': 'קפה',
      'espresso': 'אספרסו',
      'tea': 'תה',
      'hot_drinks': 'משקאות חמים',
      'coffee_maker': 'מכונת קפה',
      'salad': 'סלט',
      'produce': 'תוצרת טרייה',
      'herbs': 'עשבי תיבול',
      'sauces': 'רטבים',
      'spicy': 'חריף',
      'kitchen': 'מטבח',
      'sides': 'תוספות',
      'offers': 'מבצעים',
      'general': 'כללי',
      'menu': 'תפריט',
      'other': 'סמל',
    });
    return '$_temp0';
  }

  @override
  String menuCategoryIconGroupLabel(String group) {
    String _temp0 = intl.Intl.selectLogic(group, {
      'mains': 'מנות עיקריות',
      'fastFood': 'מזון מהיר',
      'bakerySweets': 'מאפים וקינוחים',
      'coldDrinks': 'משקאות קרים',
      'hotDrinks': 'משקאות חמים',
      'other': 'אחר',
      'other': 'אחר',
    });
    return '$_temp0';
  }

  @override
  String get menuAddCategory => 'הוסף קטגוריה';

  @override
  String get menuAddItem => 'הוסף פריט';

  @override
  String get menuAddSize => 'הוסף גודל';

  @override
  String get menuAddVariant => 'הוסף וריאציה';

  @override
  String get menuAddModifier => 'הוסף תוספת';

  @override
  String get menuAddOption => 'הוסף אפשרות';

  @override
  String get menuEditTitle => 'עריכה';

  @override
  String get menuSaveAction => 'שמור';

  @override
  String get menuCancelAction => 'ביטול';

  @override
  String get menuEditAction => 'ערוך';

  @override
  String get menuDeleteAction => 'מחק';

  @override
  String get menuNameLabel => 'שם';

  @override
  String get menuDescriptionLabel => 'תיאור (אופציונלי)';

  @override
  String get menuPriceLabel => 'מחיר בסיס';

  @override
  String get menuPriceDeltaLabel => 'שינוי מחיר';

  @override
  String get menuCurrencyLabel => 'מטבע';

  @override
  String get menuCategoryFieldLabel => 'קטגוריה';

  @override
  String get menuDisplayOrderLabel => 'סדר תצוגה';

  @override
  String get menuActiveLabel => 'פעיל';

  @override
  String get menuSelectionTypeLabel => 'בחירה';

  @override
  String get menuSelectionSingle => 'יחיד';

  @override
  String get menuSelectionMultiple => 'מרובה';

  @override
  String get menuMinSelectLabel => 'מינימום';

  @override
  String get menuMaxSelectLabel => 'מקסימום (אופציונלי)';

  @override
  String get menuRequiredLabel => 'חובה';

  @override
  String get menuAllowQuantityLabel => 'אפשר כמות';

  @override
  String get menuAllowQuantityHelp =>
      'הקופאי יכול להוסיף את אותה האפשרות יותר מפעם אחת (לדוגמה: תוספת גבינה ×2).';

  @override
  String get menuMaxQuantityLabel => 'מקסימום לכל אפשרות';

  @override
  String get menuSizesHeading => 'גדלים';

  @override
  String get menuVariantsHeading => 'וריאציות';

  @override
  String get menuModifiersHeading => 'תוספות';

  @override
  String get menuOptionsHeading => 'אפשרויות';

  @override
  String get menuDeleteConfirmTitle => 'למחוק פריט זה?';

  @override
  String get menuDeleteConfirmBody =>
      'הוא יוסתר מהתפריט. ניתן לשחזר אותו מאוחר יותר.';

  @override
  String get menuConfirmDelete => 'מחק';

  @override
  String get menuInactiveBadge => 'לא פעיל';

  @override
  String get menuGlobalBadge => 'כל הסניפים';

  @override
  String get menuBranchBadge => 'סניף זה';

  @override
  String get menuImageHeading => 'תמונת פריט';

  @override
  String get menuImageDeferredTitle => 'העלאת תמונות אינה מחוברת';

  @override
  String get menuImageDeferredBody =>
      'לממשק הזה לא מחובר אחסון תמונות, ולכן אי אפשר להעלות או להציג כאן תמונות פריטים.';

  @override
  String get menuImagePickAction => 'בחירת תמונה';

  @override
  String get menuImageReplaceAction => 'החלפת תמונה';

  @override
  String get menuImageRemoveAction => 'הסרת תמונה';

  @override
  String get menuImageSaveAction => 'שמירת תמונה';

  @override
  String get menuImageInvalidType =>
      'אפשר להעלות רק תמונות PNG,‏ JPEG או WebP.';

  @override
  String get menuImageTooLarge => 'התמונה גדולה מדי — המגבלה היא 5MB.';

  @override
  String get menuImageUploadFailed => 'ההעלאה נכשלה — התמונה לא נשמרה.';

  @override
  String get menuImageUnsupportedPlatform =>
      'בחירת תמונה עדיין אינה זמינה בפלטפורמה הזו — יש להשתמש בלוח הבקרה באינטרנט.';

  @override
  String get menuImageDemoNote => 'דמו — התמונה לא מועלית לשרת.';

  @override
  String get menuImageLoadError => 'לא ניתן לטעון את תצוגת התמונה.';

  @override
  String get menuErrorRequired => 'חובה';

  @override
  String get menuErrorAmount => 'הזן סכום תקין';

  @override
  String get menuErrorNegativePrice => 'לא יכול להיות שלילי';

  @override
  String get menuErrorCurrency => 'השתמש בקוד בן 3 אותיות (למשל ILS)';

  @override
  String get menuErrorSelectionType => 'בחר יחיד או מרובה';

  @override
  String get menuErrorMaxLessThanMin => 'חייב להיות לפחות המינימום';

  @override
  String get menuWritePermissionDenied =>
      'אין לך הרשאה לשנות את התפריט בהיקף זה.';

  @override
  String get menuWriteProblem => 'השמירה נכשלה — נסה שוב.';

  @override
  String get menuSavedSnack => 'נשמר';

  @override
  String get menuDeletedSnack => 'נמחק';

  @override
  String get menuManagementSubtitle =>
      'ארגן קטגוריות, פריטים, גדלים, תוספות ומחירים.';

  @override
  String get menuSearchHint => 'חיפוש בתפריט';

  @override
  String get menuFilterAll => 'הכול';

  @override
  String get menuFilterActive => 'פעיל';

  @override
  String get menuFilterInactive => 'לא פעיל';

  @override
  String get menuEmptyCategoriesBody =>
      'צור את הקטגוריה הראשונה כדי להתחיל לבנות את התפריט.';

  @override
  String get menuEmptyItemsBody => 'הוסף פריט לקטגוריה זו כדי להתחיל.';

  @override
  String get menuLoadErrorBody => 'אירעה שגיאה בעת טעינת התפריט.';

  @override
  String get menuImageEmptyHint => 'אין עדיין תמונה';

  @override
  String get menuComingSoonBadge => 'בקרוב';

  @override
  String get menuItemDetailsSection => 'פרטים';

  @override
  String get menuNoResults => 'אין תוצאות';

  @override
  String get menuNoResultsBody => 'נסה חיפוש או סינון אחר.';

  @override
  String get menuScopeUnavailableTitle => 'התפריט אינו זמין לגישה זו';

  @override
  String get menuScopeUnavailableBody =>
      'זו גישה ברמת הארגון ללא מסעדה נבחרת. פתח את ניהול התפריט ממסעדה או סניף ספציפיים.';

  @override
  String get menuBasicInfoSection => 'מידע בסיסי';

  @override
  String get menuPricingSection => 'תמחור';

  @override
  String get menuPreparationSection => 'הכנה';

  @override
  String get menuAdvancedSection => 'מתקדם';

  @override
  String get menuAdvancedSectionHint =>
      'פרטים אופציונליים — השתמשו במה שמתאים לפריט.';

  @override
  String get menuItemTypeLabel => 'סוג פריט';

  @override
  String get menuItemTypeUnspecified => 'לא צוין';

  @override
  String get menuItemTypeFood => 'אוכל';

  @override
  String get menuItemTypeDrink => 'משקה';

  @override
  String get menuItemTypeSide => 'תוספת';

  @override
  String get menuItemTypeCombo => 'קומבו';

  @override
  String get menuItemTypeOther => 'אחר';

  @override
  String get menuTagsLabel => 'תגיות';

  @override
  String get menuTagSpicy => 'חריף';

  @override
  String get menuTagVegetarian => 'צמחוני';

  @override
  String get menuTagPopular => 'פופולרי';

  @override
  String get menuTagNew => 'חדש';

  @override
  String menuModifierGroupCount(int count) {
    return '$count קבוצות אפשרויות';
  }

  @override
  String get menuPrepMinutesLabel => 'זמן הכנה (דקות)';

  @override
  String get menuKitchenNoteLabel => 'הערה למטבח';

  @override
  String get menuKitchenPrepSection => 'ספירות מטבח';

  @override
  String get menuKitchenPrepHint =>
      'המשאבים שפריט אחד משתמש בהם (למשל לחמנייה אחת) — נוספים לסיכום ספירות המטבח. אופציונלי.';

  @override
  String get menuPrepComponentNameLabel => 'משאב';

  @override
  String get menuPrepComponentQuantityLabel => 'כמות';

  @override
  String get menuPrepComponentUnitLabel => 'יחידה';

  @override
  String get menuPrepClassifierLabel => 'פיצול לפי אפשרות';

  @override
  String get menuPrepClassifierNone => 'ללא פיצול';

  @override
  String get menuPrepClassifierHint =>
      'האפשרות רק קובעת לאיזה סיכום נספרת הכמות שלמעלה, והיא לא מוסיפה כמות משלה.';

  @override
  String get menuPrepClassifierMissing =>
      'האפשרות הזו כבר לא קיימת, ולכן המשאב לא יפוצל.';

  @override
  String get menuAddPrepComponent => 'הוספת משאב';

  @override
  String get menuRemovePrepComponent => 'הסרת רכיב';

  @override
  String get menuKitchenMeatSection => 'סיכום הכנה למטבח';

  @override
  String get menuKitchenMeatEnabledLabel => 'נכלל בסיכום ההכנה';

  @override
  String get menuKitchenMeatQuantityLabel => 'כמות';

  @override
  String get menuKitchenMeatUnitLabel => 'משאב';

  @override
  String get menuSkuLabel => 'מק\"ט (קוד פנימי)';

  @override
  String get menuPortionFieldLabel => 'תווית מנה';

  @override
  String get menuPattyCountLabel => 'כמות (קציצות או יחידות)';

  @override
  String get menuPattyWeightLabel => 'משקל ליחידה (גרם)';

  @override
  String get menuTemplateAddAction => 'הוספת תבנית';

  @override
  String get menuTemplatePickerTitle => 'הוספה מתבנית';

  @override
  String get menuTemplateRequiredSingle => 'חובה · בחירה אחת';

  @override
  String get menuTemplateOptionalMulti => 'רשות · בחירה מרובה';

  @override
  String get menuTemplateOptionalSingle => 'רשות · עד בחירה אחת';

  @override
  String menuTemplateOptionCount(int count) {
    return '$count אפשרויות';
  }

  @override
  String get menuTemplateApplyPartial =>
      'ההוספה נעצרה — השורות שכבר נוצרו נשארות ברשימה; אפשר לערוך או למחוק אותן למטה.';

  @override
  String get menuTemplateBurgerToppings => 'תוספות להמבורגר';

  @override
  String get menuTemplateOptLettuce => 'חסה';

  @override
  String get menuTemplateOptTomato => 'עגבנייה';

  @override
  String get menuTemplateOptOnion => 'בצל';

  @override
  String get menuTemplateOptPickles => 'מלפפון חמוץ';

  @override
  String get menuTemplateOptCheese => 'גבינה';

  @override
  String get menuTemplateDoneness => 'דרגת עשייה';

  @override
  String get menuTemplateOptRare => 'נא';

  @override
  String get menuTemplateOptMediumDoneness => 'מדיום';

  @override
  String get menuTemplateOptWellDone => 'עשוי היטב';

  @override
  String get menuTemplatePattyCount => 'מספר קציצות';

  @override
  String get menuTemplateOptSinglePatty => 'קציצה אחת';

  @override
  String get menuTemplateOptDoublePatty => 'שתי קציצות';

  @override
  String get menuTemplateOptTriplePatty => 'שלוש קציצות';

  @override
  String get menuTemplateExtras => 'תוספות';

  @override
  String get menuTemplateOptExtraCheese => 'תוספת גבינה';

  @override
  String get menuTemplateOptExtraPatty => 'קציצה נוספת';

  @override
  String get menuTemplateOptFries => 'צ\'יפס';

  @override
  String get menuTemplateOptDrink => 'משקה';

  @override
  String get menuTemplateDrinkSize => 'גודל משקה';

  @override
  String get menuTemplateOptSmall => 'קטן';

  @override
  String get menuTemplateOptMediumSize => 'בינוני';

  @override
  String get menuTemplateOptLarge => 'גדול';

  @override
  String get menuTemplateSpiciness => 'רמת חריפות';

  @override
  String get menuTemplateOptMild => 'עדין';

  @override
  String get menuTemplateOptMediumSpicy => 'בינוני';

  @override
  String get menuTemplateOptHot => 'חריף';

  @override
  String get dashboardNavSettings => 'הגדרות';

  @override
  String get dashboardNavUsers => 'משתמשים';

  @override
  String get dashboardNavDevices => 'מכשירים';

  @override
  String get adminDemoBanner =>
      'נתוני דמו — הפעולות תואמות לחוזי הצד-האחורי של RF-112 אך פועלות מול מאגר בזיכרון במכשיר זה; שום דבר עדיין לא נשמר בשרת.';

  @override
  String get adminPermissionDeniedTitle => 'אין לך הרשאה';

  @override
  String get adminPermissionDeniedBody =>
      'התפקיד שלך אינו יכול לבצע פעולה זו בהיקף זה. שומר דירוג-התפקידים מגביל את הניהול לתפקידים גבוהים יותר.';

  @override
  String get adminStateErrorTitle => 'משהו השתבש';

  @override
  String get adminStateErrorBody => 'לא הצלחנו לטעון זאת. נסה שוב.';

  @override
  String get adminRetry => 'נסה שוב';

  @override
  String get adminConflictMessage => 'פעולה זו אינה מותרת במצב הנוכחי.';

  @override
  String get adminActionProblem => 'לא ניתן היה להשלים את הפעולה — נסה שוב.';

  @override
  String get adminErrCurrency => 'השתמש בקוד בן 3 אותיות (למשל ILS)';

  @override
  String get adminErrCountry => 'השתמש בקוד בן 2 אותיות (למשל US)';

  @override
  String get adminErrName => 'שדה חובה';

  @override
  String get adminErrEmail => 'הזן אימייל תקין';

  @override
  String get adminErrStatus => 'בחר סטטוס תקין';

  @override
  String get adminErrRequired => 'שדה חובה';

  @override
  String get adminCopy => 'העתק';

  @override
  String get adminShownOnce =>
      'מוצג פעם אחת — העתק עכשיו. לא תוכל לראות אותו שוב.';

  @override
  String get adminDone => 'סיום';

  @override
  String get adminSavedSnack => 'נשמר';

  @override
  String get adminDevStatusNone => 'לא מצומד';

  @override
  String get adminDevStatusCodeIssued => 'הונפק קוד';

  @override
  String get adminDevStatusPending => 'ממתין לאישור';

  @override
  String get adminDevStatusPaired => 'מצומד';

  @override
  String get adminDevStatusActive => 'פעיל';

  @override
  String get adminDevStatusSuspended => 'מושהה';

  @override
  String get adminDevStatusRevoked => 'בוטל';

  @override
  String get adminDevStatusCodeExpired => 'פג תוקף הקוד';

  @override
  String get adminDevStatusRejected => 'נדחה';

  @override
  String get adminSettingsTitle => 'הגדרות';

  @override
  String get adminSettingsSubtitle => 'הגדרות ארגון, מסעדה וסניף עבור היקף זה.';

  @override
  String get adminSettingsReadOnly =>
      'התפקיד שלך יכול לצפות בהגדרות אלו אך לא לערוך אותן.';

  @override
  String get adminSectionOrg => 'ארגון';

  @override
  String get adminSectionRestaurant => 'מסעדה';

  @override
  String get adminSectionBranch => 'סניף';

  @override
  String get adminFieldDefaultCurrency => 'מטבע ברירת מחדל';

  @override
  String get adminFieldCountryCode => 'קוד מדינה';

  @override
  String get adminFieldStatus => 'סטטוס';

  @override
  String get adminFieldName => 'שם';

  @override
  String get adminFieldCurrencyOverride => 'עקיפת מטבע';

  @override
  String get adminFieldTimezone => 'אזור זמן';

  @override
  String get adminFieldAddress => 'כתובת';

  @override
  String get adminFieldReceiptPrefix => 'קידומת קבלה';

  @override
  String get adminStatusActive => 'פעיל';

  @override
  String get adminStatusSuspended => 'מושהה';

  @override
  String get adminOptional => 'אופציונלי';

  @override
  String get adminSave => 'שמור';

  @override
  String get adminCancel => 'ביטול';

  @override
  String get adminUsersTitle => 'משתמשים ותפקידים';

  @override
  String get adminUsersSubtitle =>
      'נהל מי יכול לגשת לארגון זה ומה מותר לו לעשות.';

  @override
  String get adminGrantUser => 'הענק גישה';

  @override
  String get adminGrantDialogTitle => 'הענק גישה';

  @override
  String get adminGrant => 'הענק';

  @override
  String get adminChangeRole => 'שנה תפקיד';

  @override
  String get adminChangeRoleTitle => 'שנה תפקיד';

  @override
  String get adminUpdate => 'עדכן';

  @override
  String get adminRevoke => 'בטל גישה';

  @override
  String get adminComingSoon => 'בקרוב';

  @override
  String get adminRoleGuardNote =>
      'אפשר להקצות תפקידים נמוכים משלך — שומר דירוג-התפקידים מונע הענקת התפקיד שלך עצמו או גבוה ממנו.';

  @override
  String get adminSelf => 'אתה';

  @override
  String get adminStatusRevoked => 'בוטל';

  @override
  String get adminFieldDisplayName => 'שם תצוגה';

  @override
  String get adminFieldEmail => 'אימייל';

  @override
  String get adminFieldRole => 'תפקיד';

  @override
  String get adminUsersEmptyTitle => 'אין עדיין חברים';

  @override
  String get adminUsersEmptyBody =>
      'הענק גישה כדי להוסיף את החבר הראשון לארגון זה.';

  @override
  String get adminUserGranted => 'הגישה הוענקה';

  @override
  String get adminRoleUpdated => 'התפקיד עודכן';

  @override
  String get adminRevokeMemberTitle => 'לבטל את הגישה?';

  @override
  String get adminRevokeMemberBody =>
      'פעולה זו מסירה את גישת החבר לארגון ומסיימת כל כניסה עם קוד PIN. לא ניתן לבטל זאת מכאן.';

  @override
  String get adminMemberRevoked => 'הגישה בוטלה';

  @override
  String get adminDevicesTitle => 'מכשירים';

  @override
  String get adminDevicesSubtitle =>
      'ספק וצמד מכשירי קופה ומסכי מטבח עבור סניף זה.';

  @override
  String get adminCreateDevice => 'הוסף מכשיר';

  @override
  String get adminCreateDeviceTitle => 'הוסף מכשיר';

  @override
  String get adminCreate => 'צור';

  @override
  String get adminFieldDeviceLabel => 'שם המכשיר';

  @override
  String get adminFieldDeviceType => 'סוג המכשיר';

  @override
  String get adminDeviceTypePos => 'קופה';

  @override
  String get adminDeviceTypeKds => 'מסך מטבח';

  @override
  String get adminDeviceTypeKiosk => 'קיוסק להזמנה עצמית';

  @override
  String get adminLifecycleNote =>
      'מחזור חיים: הנפק קוד, המכשיר פודה אותו (ממתין), לאחר מכן אישור (מצומד), לאחר מכן הפעלה (פעיל), לאחר מכן התחלת מושב. אישור והפעלה הם שלבים נפרדים; מכשיר אינו יכול לקפוץ מממתין לפעיל.';

  @override
  String get adminIssueCode => 'הנפק קוד';

  @override
  String get adminRedeem => 'פדה קוד';

  @override
  String get adminApprove => 'אשר';

  @override
  String get adminActivate => 'הפעל';

  @override
  String get adminStartSession => 'התחל מושב';

  @override
  String get adminDevicesEmptyTitle => 'אין עדיין מכשירים';

  @override
  String get adminDevicesEmptyBody =>
      'הוסף מכשיר כדי להתחיל בתהליך הרישום והצימוד.';

  @override
  String get adminCodeIssuedTitle => 'קוד רישום';

  @override
  String get adminCodeIssuedSubtitle => 'הזן קוד זה במכשיר כדי להתחיל בצימוד.';

  @override
  String get adminCodeExpiresNote => 'תוקף הקוד פג בקרוב וניתן לפדותו פעם אחת.';

  @override
  String get pairingPanelTitle => 'התאמת המכשיר הזה';

  @override
  String get pairingPanelInstructions =>
      'פתחו את הקישור הזה בטאבלט, או סרקו את קוד ה-QR, ואז הקישו על התאמה.';

  @override
  String get pairingPanelScanLabel => 'סרקו כדי לפתוח בטאבלט';

  @override
  String get pairingPanelLinkLabel => 'קישור התאמה';

  @override
  String get pairingPanelCopyLink => 'העתקת קישור';

  @override
  String get pairingPanelCodeLabel => 'קוד התאמה';

  @override
  String get pairingPanelManualOnly =>
      'אין קישור אפליקציה לסוג מכשיר זה — הזינו את הקוד ידנית בטאבלט.';

  @override
  String get adminTokenStartedTitle => 'מושב המכשיר התחיל';

  @override
  String get adminTokenStartedSubtitle =>
      'טען אסימון מושב זה למכשיר כדי לאמת אותו.';

  @override
  String get adminSessionOpen => 'המושב פעיל';

  @override
  String get adminDeviceCreated => 'המכשיר נוסף';

  @override
  String get adminDeviceUpdated => 'המכשיר עודכן';

  @override
  String get authWelcomeTitle => 'ברוכים הבאים ל-RestoFlow';

  @override
  String get authBrandTagline => 'מערכת הפעלה למסעדות';

  @override
  String get authSignInTab => 'התחברות';

  @override
  String get authCreateAccountTab => 'יצירת חשבון';

  @override
  String get authEmailLabel => 'אימייל';

  @override
  String get authPasswordLabel => 'סיסמה';

  @override
  String get authSignInAction => 'התחברות';

  @override
  String get authEmailRequired => 'הזינו אימייל';

  @override
  String get authPasswordRequired => 'הזינו סיסמה';

  @override
  String get authPasswordTooShort => 'השתמשו ב-6 תווים לפחות';

  @override
  String get authInvalidCredentials => 'אימייל או סיסמה שגויים';

  @override
  String get authSignUpFailed => 'לא ניתן ליצור את החשבון. נסו שוב.';

  @override
  String get authNetworkError => 'לא ניתן להגיע לשרת. בדקו את החיבור.';

  @override
  String get authEmailConfirmationSent =>
      'בדקו את האימייל לאישור החשבון ואז התחברו.';

  @override
  String get onboardingTitle => 'הגדרת המסעדה שלך';

  @override
  String get onboardingIntro => 'צרו את המסעדה כדי להתחיל להשתמש ב-RestoFlow.';

  @override
  String get onboardingRestaurantNameLabel => 'שם המסעדה';

  @override
  String get onboardingBranchNameLabel => 'שם הסניף (אופציונלי)';

  @override
  String get onboardingRestaurantNameRequired => 'הזינו שם מסעדה';

  @override
  String get onboardingCreateAction => 'יצירת מסעדה';

  @override
  String get onboardingFailed => 'לא ניתן ליצור את המסעדה. נסו שוב.';

  @override
  String get pairingTitle => 'צימוד המכשיר';

  @override
  String get pairingIntro =>
      'הזינו את קוד הצימוד שנוצר בלוח הבקרה של המסעדה כדי לחבר את המכשיר.';

  @override
  String get pairingWhereCode => 'קבלו קוד צימוד מלוח הבקרה ← לשונית מכשירים.';

  @override
  String get pairingCodeLabel => 'קוד צימוד';

  @override
  String get pairingCodeRequired => 'הזינו קוד צימוד';

  @override
  String get pairingPairAction => 'צימוד מכשיר';

  @override
  String get pairingInvalidCode => 'קוד הצימוד לא התקבל. בדקו אותו ונסו שוב.';

  @override
  String get pairingExpired => 'תוקף קוד הצימוד פג. בקשו קוד חדש.';

  @override
  String get pairingWrongScope => 'הקוד שייך למסעדה או לסניף אחר.';

  @override
  String get pairingFailed => 'לא ניתן לצמד את המכשיר. נסו שוב.';

  @override
  String get pairingLocked =>
      'יותר מדי ניסיונות. אנא המתינו כמה דקות ונסו שוב.';

  @override
  String get dashboardNavPrinters => 'הדפסה';

  @override
  String get dashboardNavStaff => 'צוות';

  @override
  String get dashboardNavTables => 'שולחנות';

  @override
  String get dashboardModeDemo => 'דמו';

  @override
  String get dashboardModeReal => 'אמת';

  @override
  String get dashboardModeDemoData => 'נתוני דמו';

  @override
  String get dashboardModeLiveData => 'נתונים חיים';

  @override
  String get dashboardSalesByHour => 'מכירות לפי שעה';

  @override
  String dashboardSalesByHourSemantics(String hour, String amount) {
    return 'מכירות לפי שעה. שיא ב-$hour: $amount';
  }

  @override
  String get dashboardSalesByDay => 'מכירות לפי יום';

  @override
  String dashboardSalesByDaySemantics(String day, String amount) {
    return 'מכירות לפי יום. היום החזק ביותר $day: $amount';
  }

  @override
  String get dashboardSalesByOrderType => 'מכירות לפי סוג הזמנה';

  @override
  String dashboardShareOfOrders(String percent) {
    return '$percent% מההזמנות';
  }

  @override
  String get dashboardRecordedTendersNote =>
      'תשלומים שנרשמו במערכת בלבד — לא סליקה מול חברת האשראי.';

  @override
  String dashboardRecordedPaymentsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count תשלומים שנרשמו',
      two: 'שני תשלומים שנרשמו',
      one: 'תשלום אחד שנרשם',
    );
    return '$_temp0';
  }

  @override
  String dashboardShareOfCollected(String percent) {
    return '$percent% מהנגבה';
  }

  @override
  String dashboardAvgRecordedPayment(String amount) {
    return 'תשלום ממוצע $amount';
  }

  @override
  String dashboardMethodTrendTitle(String method) {
    return 'תקבולים שנרשמו לפי יום: $method';
  }

  @override
  String get dashboardComparedVsYesterdayAll => 'לעומת כל יום אתמול';

  @override
  String get dashboardComparedVsDayBefore => 'לעומת שלשום';

  @override
  String get dashboardComparedVsPrev7 => 'לעומת 7 הימים הקודמים';

  @override
  String get dashboardComparedVsPrev30 => 'לעומת 30 הימים הקודמים';

  @override
  String get dashboardComparedVsPrev60 => 'לעומת 60 הימים הקודמים';

  @override
  String get dashboardComparedVsPrev90 => 'לעומת 90 הימים הקודמים';

  @override
  String dashboardComparedVsPrevDays(int days) {
    return 'לעומת $days הימים הקודמים';
  }

  @override
  String dashboardDeltaVsYesterday(int percent) {
    return '$percent% לעומת כל יום אתמול';
  }

  @override
  String get dashboardRangeToday => 'היום';

  @override
  String get dashboardRangeYesterday => 'אתמול';

  @override
  String get dashboardRangeLast7 => '7 הימים האחרונים';

  @override
  String get dashboardRangeLast30 => '30 הימים האחרונים';

  @override
  String get dashboardRangeLast60 => '60 הימים האחרונים';

  @override
  String get dashboardRangeLast90 => '90 הימים האחרונים';

  @override
  String get dashboardRangeCustom => 'מותאם אישית';

  @override
  String get dashboardRangeCustomTitle => 'טווח מותאם אישית';

  @override
  String get dashboardRangeCustomChoose => 'בחירת תאריכים';

  @override
  String get dashboardRangeCustomFrom => 'מתאריך';

  @override
  String get dashboardRangeCustomTo => 'עד תאריך';

  @override
  String get dashboardRangeCustomApply => 'החלה';

  @override
  String get dashboardRangeCustomCancel => 'ביטול';

  @override
  String get dashboardRangeCustomClear => 'ניקוי התאריכים';

  @override
  String get dashboardRangeCustomEmpty => 'יש לבחור תאריך התחלה וסיום';

  @override
  String get dashboardRangeCustomReversed =>
      'תאריך הסיום לא יכול להקדים את תאריך ההתחלה';

  @override
  String dashboardRangeCustomTooLong(int max) {
    return 'יש לבחור עד $max ימים';
  }

  @override
  String dashboardRangeCustomSelected(String start, String end) {
    return '$start – $end';
  }

  @override
  String dashboardRangeCustomDays(int days) {
    return 'טווח של $days ימים';
  }

  @override
  String get dashboardRangeUnavailable =>
      'טווח זה עדיין אינו זמין בדוחות החיים — נסה היום, או בדוק שוב לאחר שעדכון הדוחות יעלה.';

  @override
  String dashboardDeltaVsDayBefore(int percent) {
    return '$percent% לעומת שלשום';
  }

  @override
  String dashboardDeltaVsPrev7(int percent) {
    return '$percent% לעומת 7 הימים הקודמים';
  }

  @override
  String dashboardDeltaVsPrev30(int percent) {
    return '$percent% לעומת 30 הימים הקודמים';
  }

  @override
  String dashboardDeltaVsPrev60(int percent) {
    return '$percent% לעומת 60 הימים הקודמים';
  }

  @override
  String dashboardDeltaVsPrev90(int percent) {
    return '$percent% לעומת 90 הימים הקודמים';
  }

  @override
  String dashboardDeltaVsPrevDays(int percent, int days) {
    return '$percent% לעומת $days הימים הקודמים';
  }

  @override
  String dashboardShiftClosedInRange(int count) {
    return '$count נסגרו';
  }

  @override
  String get dashboardShiftNoneRange => 'אין משמרות שנסגרו בטווח זה.';

  @override
  String dashboardShiftOpenedBy(String name) {
    return 'נפתחה על ידי $name';
  }

  @override
  String get dashboardShiftCollected => 'נאסף';

  @override
  String get dashboardShiftDurationLabel => 'משך';

  @override
  String dashboardShiftDurationValue(int hours, int minutes) {
    return '$hoursש $minutesד';
  }

  @override
  String dashboardShiftRecentTitle(int count) {
    return 'משמרות אחרונות ($count)';
  }

  @override
  String get dashboardUsersNotConnectedTitle => 'ניהול המשתמשים עדיין לא מחובר';

  @override
  String get dashboardUsersNotConnectedBody =>
      'גרסה זו עדיין אינה יכולה להציג או להזמין חברים אמיתיים — אין ממשק לקריאת חברים. במקום להציג אנשים לדוגמה, העמוד נשאר ריק. מצב הדמו מדגים כיצד המסך יעבוד.';

  @override
  String get dashboardSettingsWorkspace => 'סביבת העבודה';

  @override
  String get dashboardSettingsRealNotice =>
      'אלה הערכים האמיתיים של סביבת העבודה. עריכת ההגדרות עדיין אינה מחוברת בגרסה זו, ולכן אין כאן מה לשמור.';

  @override
  String get dashboardSettingsEditableTitle => 'עריכת פרטי הסניף';

  @override
  String get dashboardSettingsBranchNameLabel => 'שם הסניף';

  @override
  String get dashboardSettingsRestaurantNameLabel => 'שם המסעדה';

  @override
  String get dashboardSettingsReceiptPrefixHint =>
      'השאירו ריק כדי לשמור על הקידומת הנוכחית';

  @override
  String get dashboardSettingsTimezoneLabel => 'אזור הזמן של הסניף';

  @override
  String get dashboardSettingsTimezoneHint =>
      'משמש לדוחות (מכירות לפי שעה, סיכומים יומיים). ישראל היא Asia/Jerusalem.';

  @override
  String get dashboardSettingsTimezoneKeep => 'ללא שינוי';

  @override
  String get timezonePickerNotSet => 'לא הוגדר';

  @override
  String get timezonePickerWillChange => 'ישתנה בשמירה';

  @override
  String get timezonePickerTitle => 'בחר אזור זמן';

  @override
  String get timezonePickerSearchHint => 'חפש לפי מדינה, עיר או מזהה IANA';

  @override
  String get timezonePickerNoResults => 'אין אזורי זמן תואמים';

  @override
  String get timezoneLabelAsiaJerusalem => 'ישראל — ירושלים';

  @override
  String get timezoneLabelAsiaGaza => 'פלסטין — עזה';

  @override
  String get timezoneLabelAsiaHebron => 'פלסטין — חברון';

  @override
  String get timezoneLabelEuropeLondon => 'בריטניה — לונדון';

  @override
  String get timezoneLabelEuropeBerlin => 'גרמניה — ברלין';

  @override
  String get timezoneLabelAmericaNewYork => 'ארצות הברית — ניו יורק';

  @override
  String get timezoneLabelAmericaLosAngeles => 'ארצות הברית — לוס אנג׳לס';

  @override
  String get timezoneLabelAsiaTokyo => 'יפן — טוקיו';

  @override
  String get timezoneLabelAustraliaSydney => 'אוסטרליה — סידני';

  @override
  String get timezoneLabelAfricaCairo => 'מצרים — קהיר';

  @override
  String get dashboardSettingsCurrencyLocked =>
      'המטבע קבוע ל-₪ (ILS) עבור הפיילוט ולא ניתן לשנותו כאן.';

  @override
  String get dashboardShiftCloseSectionTitle => 'התאמת משמרת (קופה)';

  @override
  String get dashboardShiftCloseToggleLabel =>
      'הצג «סגירת משמרת וספירת מזומן» בקופה';

  @override
  String get dashboardShiftCloseToggleHelp =>
      'כשמופעל, קופאים יכולים לסגור את המשמרת ולספור את מגירת המזומן בקופה עבור סניף זה. כיבוי מסתיר את התהליך; התשלומים אינם מושפעים.';

  @override
  String get dashboardShiftCloseOwnerOnly => 'רק בעלים יכול לשנות הגדרה זו.';

  @override
  String get dashboardShiftCloseUnavailable =>
      'לא ניתן לטעון הגדרה זו כעת. נסה שוב מאוחר יותר.';

  @override
  String get dashboardShiftCloseSaved => 'ההגדרה נשמרה.';

  @override
  String get dashboardShiftCloseDenied => 'אין לך הרשאה לשנות הגדרה זו.';

  @override
  String get dashboardShiftCloseSaveFailed =>
      'לא ניתן לשמור את ההגדרה. נסה שוב.';

  @override
  String get setupTitle => 'הגדרה';

  @override
  String get setupReadyHeadline => 'הסניף מוכן לשירות';

  @override
  String get setupSubtitle => 'הכינו את הסניף הזה לשירות';

  @override
  String get setupDevices => 'מכשירים';

  @override
  String get setupDevicesCaption => 'פעילים / סה״כ';

  @override
  String get setupPrinters => 'מדפסות';

  @override
  String get setupPrintersCaption => 'מופעלות / סה״כ';

  @override
  String get setupStaffPin => 'קודי PIN לצוות';

  @override
  String get setupStaffCaption => 'עם PIN / סה״כ';

  @override
  String get setupMetricUnavailable => 'לא זמין';

  @override
  String get setupNoDevices =>
      'אין מכשירים עדיין — צרו מכשיר קופה או מסך מטבח והנפיקו קוד צימוד.';

  @override
  String get setupNoActiveDevice =>
      'אף מכשיר אינו מצומד עדיין — הנפיקו קוד בעמוד המכשירים והזינו אותו במסך הצימוד של המכשיר.';

  @override
  String get setupNoPrinters =>
      'אין מדפסות מוגדרות עדיין — הוסיפו מדפסת קבלות או מדפסת מטבח.';

  @override
  String get setupNoStaffPin =>
      'לאף איש צוות אין PIN עדיין — כניסה לקופה/מסך המטבח (ומחזור ההזמנות החי) דורשת לפחות אחד.';

  @override
  String get setupReady => 'הסניף מוכן: מכשיר מצומד וקוד PIN לצוות קיימים.';

  @override
  String get setupMenu => 'פריטי תפריט';

  @override
  String get setupMenuCaption => 'פעילים / סה״כ';

  @override
  String get setupNoMenu => 'אין עדיין פריטי תפריט — לקופה אין מה למכור.';

  @override
  String get setupAddMenuItem => 'הוסיפו את פריט התפריט הראשון';

  @override
  String get setupNoPosDevice =>
      'אין עדיין מכשיר קופה — הדלפק זקוק לאחד כדי לקבל הזמנות.';

  @override
  String get setupCreatePos => 'יצירת מכשיר קופה';

  @override
  String get setupNoKdsDevice =>
      'אין עדיין צג מטבח — המטבח לא יראה הזמנות נכנסות.';

  @override
  String get setupCreateKds => 'יצירת צג מטבח';

  @override
  String get setupPairingHint =>
      'פתחו את אפליקציית הקופה או צג המטבח במכשיר והזינו את קוד הצימוד מלשונית המכשירים.';

  @override
  String get setupAddPrinter => 'הוספת מדפסת';

  @override
  String get setupCreatePin => 'יצירת קוד PIN לעובד';

  @override
  String setupMoreSteps(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count שלבי הגדרה נוספים',
      two: 'שני שלבי הגדרה נוספים',
      one: 'שלב הגדרה נוסף אחד',
    );
    return '$_temp0';
  }

  @override
  String get dashboardDevicesActiveOfConfigured =>
      'פעילים מתוך המכשירים המוגדרים';

  @override
  String get dashboardDevicesUnavailable => 'סטטוס המכשירים אינו זמין';

  @override
  String get printersTitle => 'הגדרת הדפסה';

  @override
  String get printersSubtitle => 'מדפסות קבלות ומטבח לסניף זה';

  @override
  String get printersAdd => 'הוספת מדפסת';

  @override
  String get printersEmptyTitle => 'אין מדפסות עדיין';

  @override
  String get printersEmptyBody =>
      'הוסיפו מדפסת קבלות או מדפסת מטבח כדי להכין את הסניף להדפסה.';

  @override
  String get printersTransportNoticeTitle =>
      'תצורה בלבד — אין עדיין ערוץ הדפסה';

  @override
  String get printersTransportNotice =>
      'הגדרות המדפסת נשמרות ומאומתות בשרת, אך גרסה זו אינה שולחת דבר למדפסות פיזיות. מנוע ההדפסה בנוי רשת-תחילה; ערוצי Bluetooth ו-USB עדיין לא מותקנים. לעולם לא מוצגת הצלחת הדפסה מזויפת.';

  @override
  String get printersRoleReceipt => 'קבלות';

  @override
  String get printersRoleKitchen => 'מטבח';

  @override
  String get printersConnNetwork => 'רשת (Wi-Fi/LAN)';

  @override
  String get printersConnBluetooth => 'Bluetooth';

  @override
  String get printersConnUsb => 'USB';

  @override
  String get printersConnConfigOnly => 'תצורה בלבד — ערוץ זה עדיין לא מותקן.';

  @override
  String get printersAdvanced => 'מתקדם';

  @override
  String get printersDialogSavesConfigOnly =>
      'גרסה זו שומרת את הגדרות המדפסת בלבד — עדיין לא מתבצעת הדפסה.';

  @override
  String get printersConnBluetoothWeb =>
      'גילוי Bluetooth עדיין אינו זמין באפליקציית האינטרנט. תישמר תצורה בלבד.';

  @override
  String get printersConnUsbAdapter =>
      'הדפסת USB דורשת את מתאם המדפסת של גרסת שולחן העבודה. תישמר תצורה בלבד.';

  @override
  String get printersFieldName => 'שם תצוגה';

  @override
  String get printersFieldRole => 'תפקיד המדפסת';

  @override
  String get printersFieldConnection => 'סוג חיבור';

  @override
  String get printersFieldPaper => 'רוחב נייר';

  @override
  String get printersFieldHost => 'מארח / כתובת IP';

  @override
  String get printersFieldPort => 'פורט';

  @override
  String get printersFieldBluetoothId => 'מזהה / שם התקן Bluetooth';

  @override
  String get printersFieldUsbPath => 'נתיב / מזהה USB';

  @override
  String get printersEnabled => 'מופעלת';

  @override
  String get printersDisabled => 'מושבתת';

  @override
  String get printersEdit => 'עריכה';

  @override
  String get printersRoute => 'ניתוב לתחנה';

  @override
  String get printersRouteTitle => 'ניתוב המדפסת לתחנה';

  @override
  String get printersRouteStation => 'תחנה';

  @override
  String get printersRouteActive => 'הניתוב מופעל';

  @override
  String get printersRoutedTo => 'מנתבת אל';

  @override
  String get printersDelete => 'הסרת מדפסת';

  @override
  String get printersDeleteConfirm =>
      'להסיר את המדפסת הזו? גם ניתובי התחנות שלה יוסרו.';

  @override
  String get printersSaved => 'נשמר';

  @override
  String get printersNoStations => 'אין תחנות לסניף זה עדיין.';

  @override
  String get printersErrHost => 'הזינו מארח / כתובת IP של המדפסת';

  @override
  String get printersErrPort => 'הזינו פורט תקין (1–65535)';

  @override
  String get printersSave => 'שמירה';

  @override
  String get printersWizardStepPurpose => 'מה תרצו להדפיס?';

  @override
  String get printersPurposeReceiptsHint => 'חשבונות ללקוחות בדלפק.';

  @override
  String get printersPurposeKitchenHint => 'כרטיסים לצוות המטבח.';

  @override
  String get printersWizardStepConnection => 'איך המדפסת מחוברת?';

  @override
  String get printersConnNetworkHint =>
      'המדפסת חייבת להיות באותה רשת Wi-Fi/רשת כמו מכשיר זה.';

  @override
  String get printersWizardStepDetails => 'פרטי המדפסת';

  @override
  String get printersNext => 'הבא';

  @override
  String get printersBack => 'חזרה';

  @override
  String get printersStatusDisabled => 'מושבתת';

  @override
  String get printersStatusNeedsBridge => 'דורשת גשר הדפסה';

  @override
  String get printersStatusConfigOnly => 'מוגדרת בלבד';

  @override
  String get printersStatusReadyNetwork => 'מוכנה דרך מתאם רשת';

  @override
  String get staffTitle => 'צוות';

  @override
  String get staffSubtitle => 'עובדים וכניסת PIN לסניף זה';

  @override
  String get staffAdd => 'הוספת איש צוות';

  @override
  String get staffEmptyTitle => 'אין צוות עדיין';

  @override
  String get staffEmptyBody =>
      'צרו קופאים, אנשי מטבח ומנהלים, ואז הגדירו לכל אחד PIN לכניסה לקופה/מסך המטבח.';

  @override
  String get staffFieldName => 'שם תצוגה';

  @override
  String get staffFieldRole => 'תפקיד';

  @override
  String get staffPinSet => 'PIN הוגדר';

  @override
  String get staffNoPin => 'אין PIN';

  @override
  String get staffSetPin => 'הגדרת PIN';

  @override
  String get staffResetPin => 'איפוס PIN';

  @override
  String get staffPinDialogTitle => 'הגדרת PIN לכניסה';

  @override
  String get staffPinDialogBody =>
      '4–8 ספרות. נשמר כגיבוב מאובטח — לא ניתן לקרוא אותו לעולם; הגדרת PIN חדש מחליפה את הישן.';

  @override
  String get staffFieldPin => 'PIN (4–8 ספרות)';

  @override
  String get staffFieldPinConfirm => 'אישור PIN';

  @override
  String get staffPinMismatch => 'קודי ה-PIN אינם תואמים';

  @override
  String get staffPinInvalid => 'הזינו 4–8 ספרות';

  @override
  String get staffPinSaved => 'ה-PIN נשמר';

  @override
  String get staffCreated => 'איש הצוות נוצר';

  @override
  String get staffNoPinWarning =>
      'איש צוות ללא PIN אינו יכול להיכנס לקופה/מסך המטבח.';

  @override
  String get staffInactive => 'לא פעיל';

  @override
  String get staffCapabilitiesTitle => 'הרשאות קופאי';

  @override
  String get staffCapabilitiesHint =>
      'מופעל כברירת מחדל. כבה מתג כדי להסיר את ההרשאה מקופאי זה.';

  @override
  String get staffCapApplyDiscount => 'יכול להחיל הנחות';

  @override
  String get staffCapVoidOrder => 'יכול לבטל הזמנות שלא שולמו';

  @override
  String get staffCapCloseShift => 'יכול לסגור את המשמרת שלו';

  @override
  String get staffCapManageMenuAvailability => 'יכול לנהל זמינות תפריט';

  @override
  String get staffCapManageTableOperations => 'יכול לנהל פעולות שולחנות';

  @override
  String get staffCapabilitiesAction => 'הרשאות';

  @override
  String get staffCapabilitiesSaved => 'ההרשאות עודכנו';

  @override
  String get tablesTitle => 'שולחנות';

  @override
  String get tablesSubtitle =>
      'שולחנות האוכל של סניף זה — בורר השולחנות בקופה מוכר מהרשימה הזו.';

  @override
  String get tablesAdd => 'הוספת שולחן';

  @override
  String get tablesEdit => 'עריכה';

  @override
  String get tablesDelete => 'הסרת שולחן';

  @override
  String get tablesDeleteConfirm =>
      'להסיר את השולחן הזה? הזמנות קיימות שומרות את הפניית השולחן שלהן.';

  @override
  String get tablesEmptyTitle => 'אין שולחנות עדיין';

  @override
  String get tablesEmptyBody =>
      'הוסיפו את השולחן הראשון — זרימת הישיבה במסעדה בקופה דורשת לפחות שולחן אחד.';

  @override
  String get tablesFieldLabel => 'שם / מספר שולחן';

  @override
  String get tablesFieldSeats => 'מקומות ישיבה';

  @override
  String get tablesFieldArea => 'אזור / מדור';

  @override
  String get tablesActive => 'פעיל';

  @override
  String get tablesInactive => 'לא פעיל';

  @override
  String get tablesErrLabel => 'הזינו שם שולחן';

  @override
  String get tablesErrSeats => 'מספר המקומות חייב להיות מספר חיובי';

  @override
  String get tablesStatusAvailable => 'פנוי';

  @override
  String get tablesStatusOccupied => 'תפוס';

  @override
  String get tablesStatusReserved => 'שמור';

  @override
  String get tablesStatusOutOfService => 'לא בשירות';

  @override
  String get tablesStatusUnknown => 'נדרש רענון';

  @override
  String get tablesLinked => 'מקושר';

  @override
  String get tablesEffective => 'בפועל';

  @override
  String get tablesSetStatus => 'הגדרת סטטוס';

  @override
  String get tablesSaved => 'השולחן נשמר';

  @override
  String get tablesSectionsTitle => 'אזורי הישיבה';

  @override
  String get tablesSectionAdd => 'הוספת אזור';

  @override
  String get tablesSectionName => 'שם האזור';

  @override
  String get tablesSectionEdit => 'שינוי שם האזור';

  @override
  String get tablesSectionDelete => 'מחיקת האזור';

  @override
  String get tablesSectionDeleteConfirm =>
      'למחוק את האזור הזה? השולחנות שבו יישמרו ויהפכו ללא-משויכים.';

  @override
  String get tablesArrange => 'סידור שולחנות';

  @override
  String get tablesArrangeDone => 'סיום הסידור';

  @override
  String get tablesSetSection => 'שיוך לאזור';

  @override
  String get tablesSectionNone => 'ללא אזור';

  @override
  String get tablesUnassignedZone => 'שולחנות לא משויכים';

  @override
  String get tablesNotPlaced => 'טרם הוצב';

  @override
  String get tablesPlaceOnMap => 'הצבה על המפה';

  @override
  String get tablesOverlapWarning => 'חלק מהשולחנות חופפים על המפה.';

  @override
  String get tablesFloorModeTables => 'שולחנות';

  @override
  String get tablesFloorModeElements => 'אלמנטים';

  @override
  String get tablesAddElement => 'הוספת אלמנט';

  @override
  String get floorElementWall => 'קיר';

  @override
  String get floorElementDoor => 'דלת';

  @override
  String get floorElementWindow => 'חלון';

  @override
  String get floorElementCashier => 'קופה';

  @override
  String get floorElementPlant => 'צמח';

  @override
  String get tablesVisualPreset => 'צורת השולחן';

  @override
  String get tablesVisualPresetPreview => 'תצוגה מקדימה';

  @override
  String get tablesVisualPresetClassicRect => 'מלבן קלאסי';

  @override
  String get tablesVisualPresetRound => 'שולחן עגול';

  @override
  String get tablesVisualPresetBarrels => 'שולחן עם חביות';

  @override
  String get tablesVisualPresetBooth => 'תא ישיבה';

  @override
  String get tablesFloorPreset => 'סגנון הרצפה';

  @override
  String get tablesFloorPresetPlainLight => 'בהיר פשוט';

  @override
  String get tablesFloorPresetWoodDark => 'עץ כהה';

  @override
  String get tablesFloorPresetTileModern => 'אריחים מודרניים';

  @override
  String get tablesFloorPresetStoneNeutral => 'אבן ניטרלית';

  @override
  String get floorElementRotate => 'סיבוב';

  @override
  String get floorElementResize => 'שינוי גודל';

  @override
  String get floorElementLabel => 'תווית';

  @override
  String get floorElementDelete => 'מחיקת אלמנט';

  @override
  String get floorElementDeleteConfirmTitle => 'למחוק את האלמנט?';

  @override
  String floorElementDeleteConfirmBody(String kind) {
    return '$kind יוסר ממפת הרצפה.';
  }

  @override
  String floorElementDeleteConfirmBodyLabeled(String kind, String label) {
    return '$kind \"$label\" יוסר ממפת הרצפה.';
  }

  @override
  String get floorElementWidth => 'רוחב';

  @override
  String get floorElementHeight => 'גובה';

  @override
  String get tablesElementOverlapWarning => 'אלמנט חופף לשולחן על המפה.';

  @override
  String get adminRevokeConfirm =>
      'לבטל את המכשיר הזה? הצימוד וההפעלות שלו יסתיימו מיד והמכשיר יחזור למסך הצימוד.';

  @override
  String get adminPairOnDevice =>
      'הזינו את הקוד החד-פעמי במסך הצימוד של המכשיר כדי לצמד אותו.';

  @override
  String get pinLoginTitle => 'כניסת צוות';

  @override
  String get pinLoginPickName => 'הקישו על השם שלכם';

  @override
  String get pinLoginEmptyTitle => 'אין עדיין קודי PIN לצוות';

  @override
  String get pinLoginEmptyBody =>
      'בקשו ממנהל להוסיף אנשי צוות ולהגדיר להם PIN בלוח הבקרה.';

  @override
  String get pinLoginEmptyBodyPos =>
      'פתחו את לוח הבקרה ← צוות, הוסיפו קופאי או מנהל והגדירו קוד PIN, ואז חזרו והקישו \"נסה שוב\".';

  @override
  String get pinLoginEmptyBodyKds =>
      'פתחו את לוח הבקרה ← צוות, הוסיפו איש צוות מטבח או מנהל והגדירו קוד PIN, ואז חזרו והקישו \"נסה שוב\".';

  @override
  String get pinLoginStepsTitle => 'שלבי הגדרה';

  @override
  String get pinLoginStep1 => '1. פתחו את לוח הבקרה';

  @override
  String get pinLoginStep2 => '2. עברו אל צוות';

  @override
  String get pinLoginStep3 => '3. הוסיפו איש צוות';

  @override
  String get pinLoginStep4 => '4. הגדירו קוד PIN';

  @override
  String get pinLoginStep5 => '5. חזרו לכאן והקישו \"נסה שוב\"';

  @override
  String get pinLoginLoadError =>
      'לא ניתן לטעון את רשימת הצוות. בדקו את החיבור ונסו שוב.';

  @override
  String get pinLoginSessionInvalid =>
      'הפעלת המכשיר אינה תקפה עוד. צמדו את המכשיר מחדש.';

  @override
  String get pinLoginWrongPin => 'PIN שגוי — נסו שוב.';

  @override
  String get pinLoginLocked => 'יותר מדי ניסיונות. הכניסה נעולה זמנית.';

  @override
  String get pinLoginNetworkError => 'בעיית חיבור — נסו שוב.';

  @override
  String get pinLoginUnavailable => 'הכניסה אינה זמינה כעת.';

  @override
  String get pinSessionExpired => 'פג תוקף החיבור. אנא הזינו את קוד ה-PIN שוב.';

  @override
  String get pinLoginSubmit => 'כניסה';

  @override
  String get pinLoginBack => 'חזרה';

  @override
  String get pinFieldLabel => 'PIN';

  @override
  String get posSignOutStaff => 'סיום הפעלת צוות';

  @override
  String get posMenuLoadError =>
      'לא ניתן לטעון את התפריט. בדקו את החיבור ונסו שוב.';

  @override
  String get posMenuEmptyTitle => 'אין פריטי תפריט עדיין';

  @override
  String get posMenuEmptyBody =>
      'הוסיפו פריטי תפריט בלוח הבקרה כדי להתחיל למכור.';

  @override
  String get posTablesEmptyReal =>
      'לא הוגדרו שולחנות — הוסיפו שולחנות בלוח הבקרה ← שולחנות.';

  @override
  String get kdsSignInAgain => 'כניסה מחדש';

  @override
  String get posTakePayment => 'קבלת תשלום';

  @override
  String get posTenderTypeLabel => 'אמצעי תשלום';

  @override
  String get posExternalPaymentTitle => 'רישום תשלום חיצוני';

  @override
  String get posPaymentMethodCard => 'כרטיס';

  @override
  String get posPaymentMethodBit => 'ביט';

  @override
  String get posPaymentMethodExternal => 'חיצוני';

  @override
  String get posNonCashNote =>
      'תשלום חיצוני נרשם — RestoFlow אינו מעבד את הכרטיס או ההעברה; לא מבוצע חיוב אמיתי.';

  @override
  String get posPaymentFailedTitle => 'התשלום לא נרשם';

  @override
  String get posPaymentFailedBody =>
      'לא ניתן היה לרשום את התשלום. בדקו את החיבור ונסו שוב — ההזמנה נשארת ללא תשלום עד שהרישום יצליח.';

  @override
  String posCartQtyUnit(int quantity, String unitPrice) {
    return '× $quantity · $unitPrice';
  }

  @override
  String get posTaxLabel => 'מס';

  @override
  String get posGrandTotal => 'סה״כ';

  @override
  String get posApplyDiscount => 'החלת הנחה';

  @override
  String get posDiscountLabel => 'הנחה';

  @override
  String get posDiscountFixedLabel => 'סכום קבוע';

  @override
  String get posDiscountPercentLabel => 'אחוז';

  @override
  String get posDiscountValueLabel => 'ערך ההנחה';

  @override
  String get posDiscountReasonLabel => 'סיבה';

  @override
  String get posCancelOrderAction => 'ביטול הזמנה';

  @override
  String get posCancelOrderConfirm => 'אישור ביטול';

  @override
  String get posCancellationReasonLabel => 'סיבת ביטול';

  @override
  String get posCancellationReasonRequired => 'נדרשת סיבת ביטול';

  @override
  String get posCancelOrderWarning => 'ההזמנה תבוטל ולא יירשם תשלום.';

  @override
  String get posOrderCancelledSnack => 'ההזמנה בוטלה';

  @override
  String get posOrderCancelledChip => 'בוטלה';

  @override
  String get posCancelPermissionDenied =>
      'רק מנהל יכול לבטל הזמנה זו - פנה למנהל.';

  @override
  String get posCancelPaidOrderError => 'לא ניתן לבטל הזמנה ששולמה.';

  @override
  String get posCancelOrderFailed => 'הביטול נכשל. נסה שוב.';

  @override
  String get posCancelDemoNote => 'מצב הדגמה - לא מבוטלת הזמנה אמיתית.';

  @override
  String get posDiscountValueInvalid => 'הזינו הנחה תקינה';

  @override
  String get posDiscountReasonRequired => 'נדרשת סיבה';

  @override
  String get posDiscountExceedsSubtotal =>
      'ההנחה לא יכולה לעלות על סכום הביניים';

  @override
  String get posDiscountApplyAction => 'החל';

  @override
  String get posDiscountPermissionDenied =>
      'אין לך הרשאה להחיל הנחה — פנה למנהל.';

  @override
  String get posDiscountFailed => 'לא ניתן להחיל את ההנחה';

  @override
  String get posDiscountDemoNote => 'הנחת דמו — הוחלה מקומית';

  @override
  String get printerProfilesHeading => 'מדפסות שמורות';

  @override
  String get printerProfilesAddAction => 'הוספת מדפסת';

  @override
  String get printerProfilesEditAction => 'עריכת מדפסת';

  @override
  String get printerProfilesDeleteAction => 'מחיקת מדפסת';

  @override
  String get printerProfilesSelectAction => 'שימוש במדפסת זו';

  @override
  String get printerProfilesActiveBadge => 'פעילה';

  @override
  String get printerProfilesDefaultName => 'מדפסת שמורה';

  @override
  String get printerProfilesNameLabel => 'שם המדפסת';

  @override
  String get printerProfilesEmpty =>
      'אין עדיין מדפסות שמורות. הוסיפו אחת כדי לעבור בין מדפסות במהירות.';

  @override
  String get printerProfilesLoading => 'טוען מדפסות שמורות…';

  @override
  String get printerProfilesLoadFailure => 'לא ניתן לטעון את המדפסות השמורות.';

  @override
  String get printerProfilesRetryAction => 'נסה שוב';

  @override
  String get printerProfilesDeleteConfirmTitle => 'למחוק את המדפסת?';

  @override
  String printerProfilesDeleteConfirmBody(Object name) {
    return '$name תוסר ממכשיר זה.';
  }

  @override
  String get printerProfilesDeleteActiveWarning =>
      'זו המדפסת הפעילה. לא תהיה מדפסת עד שתבחרו אחרת.';

  @override
  String get printerProfilesDuplicateError =>
      'קיימת מדפסת שמורה עם כתובת ופורט אלה.';

  @override
  String get printerProfilesNameRequired => 'הזינו שם מדפסת.';

  @override
  String get printerProfilesSaveFailure => 'לא ניתן לשמור את המדפסת.';

  @override
  String get printerProfilesCancelAction => 'ביטול';

  @override
  String get posPrintBillAction => 'הדפסת חשבון';

  @override
  String get receiptUnpaidBillLabel => 'חשבון ראשוני — לא שולם';

  @override
  String get receiptAmountDueLabel => 'סכום לתשלום';

  @override
  String get posPrintBillStarted => 'מדפיס חשבון';

  @override
  String get posPrintBillFailed => 'הדפסת החשבון נכשלה';

  @override
  String get receiptLocalReferenceNote => 'אסמכתא מקומית — לא מספר הזמנה מהשרת';

  @override
  String get receiptOrderNotSyncedNote => 'ההזמנה טרם סונכרנה';

  @override
  String get posNetworkPrinterHeading => 'מדפסת רשת (מכשיר זה)';

  @override
  String get posNetworkPrinterHelp =>
      'הדפסה ישירה למדפסת תרמית ברשת Wi‑Fi או Ethernet. אין צורך בגשר הדפסה.';

  @override
  String get posNetworkPrinterIpLabel => 'כתובת IP של המדפסת';

  @override
  String get posNetworkPrinterIpHint => '192.168.1.50';

  @override
  String get posNetworkPrinterPortLabel => 'פורט';

  @override
  String get posNetworkPrinterNameLabel => 'שם המדפסת (אופציונלי)';

  @override
  String get posNetworkPrinterSaveAction => 'שמירת מדפסת';

  @override
  String get posPrinterMediaSizeLabel => 'גודל מדיית הדפסה';

  @override
  String get posPrinterMediaSizeContinuous => 'גליל 80 מ״מ (ברירת מחדל)';

  @override
  String get posPrinterMediaSize50 => 'תווית 50 × 50 מ״מ';

  @override
  String get posPrinterMediaSize80 => 'תווית 80 × 80 מ״מ';

  @override
  String get posPrinterDiagHeading => 'אבחון מדפסת';

  @override
  String posPrinterDiagWidthDots(int width) {
    return 'רוחב: $width נקודות';
  }

  @override
  String posPrinterDiagHeightDots(int height) {
    return 'גובה מדיה: $height נקודות';
  }

  @override
  String get posPrinterDiagTopSafe => 'אזור בטוח עליון';

  @override
  String get posPrinterDiagBottomSafe => 'אזור בטוח תחתון — לא נחתך';

  @override
  String posPrinterDiagPage(int page, int total) {
    return 'עמוד $page מתוך $total';
  }

  @override
  String get posNetworkPrinterTestAction => 'הדפסת בדיקה';

  @override
  String get posNetworkPrinterSavedSnack => 'מדפסת הרשת נשמרה';

  @override
  String get posNetworkPrinterStatusNotConfigured => 'לא הוגדרה';

  @override
  String get posNetworkPrinterStatusSaved => 'נשמרה';

  @override
  String get posNetworkPrinterTesting => 'שולח הדפסת בדיקה…';

  @override
  String get posNetworkPrinterTestSuccess => 'הדפסת הבדיקה נשלחה';

  @override
  String get posNetworkPrinterTestFailure =>
      'לא ניתן היה להגיע למדפסת. בדוק את כתובת ה‑IP, הפורט, ושהמדפסת מחוברת לרשת ה‑Wi‑Fi הזו.';

  @override
  String get posNetworkPrinterInvalidIp =>
      'הזן כתובת IP תקינה (לדוגמה 192.168.1.50).';

  @override
  String get posNetworkPrinterInvalidPort => 'הזן פורט תקין (1–65535).';

  @override
  String get deviceSettingsNativeNetworkNote =>
      'מכשיר זה יכול להדפיס ישירות למדפסת רשת (מוגדרת למעלה) — אין צורך בגשר הדפסה.';

  @override
  String get deviceSettingsPerfDiagnosticsTitle => 'אבחון ביצועים (גרסת בדיקה)';

  @override
  String get deviceSettingsPerfDiagnosticsNote =>
      'מקומי בלבד — שום דבר לא נשמר ולא נשלח. השאירו את האפליקציה על מסך עמוס 30 שניות ואז קראו כאן את מספרי הפריימים.';

  @override
  String get deviceSettingsPerfDiagnosticsReset => 'איפוס דגימות';

  @override
  String get deviceSettingsPrinterConfigured => 'מוגדרת';

  @override
  String posMenuItemCount(int count) {
    return '$count פריטים';
  }

  @override
  String get posMenuSearchHint => 'חפש פריט…';

  @override
  String get posSearchNoResults => 'אין פריטים התואמים לחיפוש';

  @override
  String get posOptionsChipLabel => 'אפשרויות';

  @override
  String get posCartBarSent => 'הזמנה נשלחה — פרטים';

  @override
  String get posCartBarView => 'הצג סל';

  @override
  String get posPrinterTransportHeading => 'חיבור המדפסת';

  @override
  String get posPrinterTransportNetwork => 'Wi‑Fi';

  @override
  String get posPrinterTransportBluetooth => 'בלוטות\'';

  @override
  String get posBluetoothPrinterHeading => 'מדפסת בלוטות\' (מכשיר זה)';

  @override
  String get posBluetoothPrinterHelp =>
      'הדפסה למדפסת תרמית דרך בלוטות\'. התאם אותה קודם בהגדרות הבלוטות\' של אנדרואיד, ואז רענן.';

  @override
  String get posBluetoothPairedLabel => 'מדפסות מותאמות';

  @override
  String get posBluetoothRefreshAction => 'רענון מכשירים';

  @override
  String get posBluetoothNoDevices =>
      'לא נמצאו מכשירי בלוטות\' מותאמים. התאם את המדפסת בהגדרות אנדרואיד ואז רענן.';

  @override
  String get posBluetoothPermissionRequired =>
      'נדרשת הרשאת בלוטות\'. אשר אותה ל‑RestoFlow בהגדרות אנדרואיד ואז רענן.';

  @override
  String get posBluetoothOff => 'הבלוטות\' כבוי — הפעל אותו ואז רענן.';

  @override
  String get posBluetoothSavedSnack => 'מדפסת הבלוטות\' נשמרה';

  @override
  String get posBluetoothSelectHint => 'בחר מדפסת מותאמת למעלה.';

  @override
  String get posPrinterRemoveAction => 'הסרת מדפסת';

  @override
  String get posReprintLastReceiptAction => 'הדפסה חוזרת של הקבלה האחרונה';

  @override
  String get posReprintStartedSnack => 'מדפיס מחדש את הקבלה האחרונה…';

  @override
  String get posPrinterRemovedSnack => 'המדפסת הוסרה';

  @override
  String get posPrinterNotConfigured => 'לא הוגדרה מדפסת במכשיר זה.';

  @override
  String get posPrinterErrorTimeout => 'המדפסת לא הגיבה בזמן.';

  @override
  String get posPrinterErrorUnreachable =>
      'לא ניתן היה להגיע למדפסת — ודא שהיא פועלת ומחוברת.';

  @override
  String get kdsPrinterSettingsTitle => 'מדפסת מטבח מקומית';

  @override
  String get kdsPrinterTransportNetwork => 'Wi-Fi';

  @override
  String get kdsPrinterTransportBluetooth => 'בלוטות\'';

  @override
  String get kdsPrinterNetworkIp => 'כתובת IP של המדפסת';

  @override
  String get kdsPrinterNetworkPort => 'פורט';

  @override
  String get kdsPrinterTestPrint => 'הדפסת בדיקה';

  @override
  String get kdsPrinterTicketSent => 'נשלח למדפסת';

  @override
  String get kdsPrinterPrintFailed => 'ההדפסה נכשלה — בדוק את המדפסת ונסה שוב.';

  @override
  String get kdsPrinterNoPrinterConfigured => 'לא הוגדרה מדפסת במכשיר הזה.';

  @override
  String get kdsPrinterBluetoothPairHint => 'בחר מדפסת מותאמת למעלה.';

  @override
  String get kdsPrinterBluetoothPermissionRequired =>
      'נדרשת הרשאת Bluetooth. אפשר אותה עבור RestoFlow בהגדרות Android ואז רענן.';

  @override
  String get dashboardNavOrders => 'הזמנות';

  @override
  String get ordersHistoryTitle => 'היסטוריית הזמנות';

  @override
  String get ordersHistorySubtitle => 'עיון בהזמנות שהושלמו ובביצוע';

  @override
  String get ordersSearchHint => 'חיפוש לפי מספר הזמנה, לקוח או שולחן';

  @override
  String get ordersRangeToday => 'היום';

  @override
  String get ordersRangeYesterday => 'אתמול';

  @override
  String get ordersRangeLast7 => '7 הימים האחרונים';

  @override
  String get ordersRangeLast30 => '30 הימים האחרונים';

  @override
  String get ordersFilterStatus => 'סטטוס';

  @override
  String get ordersFilterType => 'סוג';

  @override
  String get ordersFilterPayment => 'תשלום';

  @override
  String get ordersStatusAll => 'כל הסטטוסים';

  @override
  String get ordersStatusDraft => 'טיוטה';

  @override
  String get ordersStatusSubmitted => 'נשלח';

  @override
  String get ordersStatusAccepted => 'התקבל';

  @override
  String get ordersStatusPreparing => 'בהכנה';

  @override
  String get ordersStatusReady => 'מוכן';

  @override
  String get ordersStatusServed => 'הוגש';

  @override
  String get ordersStatusCompleted => 'הושלם';

  @override
  String get ordersStatusCancelled => 'בוטל';

  @override
  String get ordersStatusVoided => 'בוטל (ביטול)';

  @override
  String get ordersReprintCancelledBanner => 'מבוטל - לא חשבונית תקפה';

  @override
  String get ordersTypeAll => 'כל הסוגים';

  @override
  String get ordersPaymentAll => 'כל התשלומים';

  @override
  String get ordersEmpty => 'לא נמצאו הזמנות';

  @override
  String get ordersEmptyHint => 'נסה טווח תאריכים אחר או נקה את המסננים.';

  @override
  String get ordersError => 'לא ניתן לטעון הזמנות';

  @override
  String get ordersErrorHint => 'בדוק את החיבור ונסה שוב.';

  @override
  String get ordersLoadMore => 'טען עוד';

  @override
  String get ordersRefresh => 'רענן';

  @override
  String ordersItemsCount(int count) {
    return '$count פריטים';
  }

  @override
  String get ordersCustomerLabel => 'לקוח';

  @override
  String get ordersTimeLabel => 'שעה';

  @override
  String get ordersStaffLabel => 'טופל על ידי';

  @override
  String get ordersBranchLabel => 'סניף';

  @override
  String get ordersSubtotalLabel => 'סכום ביניים';

  @override
  String get ordersDiscountLabel => 'הנחה';

  @override
  String get ordersTaxLabel => 'מס';

  @override
  String get ordersChangeLabel => 'עודף';

  @override
  String get ordersDetailItems => 'פריטים';

  @override
  String get ordersDetailPayment => 'תשלום';

  @override
  String get ordersDetailKitchen => 'מטבח';

  @override
  String get ordersDetailInfo => 'הזמנה';

  @override
  String get ordersCopyCode => 'העתק מספר הזמנה';

  @override
  String get ordersCopied => 'הועתק';

  @override
  String get ordersPrintFromBrowser => 'הדפסה מהדפדפן';

  @override
  String get ordersReprintFromPosHint =>
      'להדפסה במדפסת קופה, הדפס מחדש ממכשיר POS';

  @override
  String get ordersReprintFromKdsHint =>
      'להדפסת כרטיס מטבח פיזי, השתמש בהדפסה חוזרת במסך המטבח (KDS)';

  @override
  String get ordersDemoNotice => 'הזמנות הדגמה — לא נטענו משרת.';

  @override
  String get ordersUnavailable => 'לא זמין';

  @override
  String get posReceiptOrderTotal => 'סך ההזמנה';

  @override
  String get posReceiptPaid => 'שולם';

  @override
  String get posReceiptChange => 'עודף';

  @override
  String get posPayLaterAction => 'לתשלום מאוחר יותר';

  @override
  String get posPayLaterSavedSnack =>
      'נשמר כלא שולם — ניתן למצוא בהזמנות אחרונות';

  @override
  String get posRecentOrdersTitle => 'הזמנות אחרונות';

  @override
  String get posRecentOrdersWindow => 'היום ואתמול';

  @override
  String get posRecentFilterAll => 'הכול';

  @override
  String get posRecentFilterUnpaid => 'לא שולם';

  @override
  String get posRecentFilterPaid => 'שולם';

  @override
  String get posRecentEmpty => 'אין הזמנות אחרונות';

  @override
  String get posRecentEmptyHint => 'הזמנות שתיצור יופיעו כאן.';

  @override
  String get posRecentReprintAction => 'הדפס קבלה מחדש';

  @override
  String get posRecentReprintStarted => 'מדפיס קבלה מחדש…';

  @override
  String get posUnpaidChip => 'לא שולם';

  @override
  String get posNoChargeChip => 'ללא חיוב';

  @override
  String get posNoChargeNoPayment => 'ההזמנה ללא חיוב — אין מה לשלם.';

  @override
  String get posCancelOrderClosed => 'ההזמנה כבר נסגרה ולא ניתן עוד לבטל אותה.';

  @override
  String get posCancelOrderConflict =>
      'ההזמנה שונתה במכשיר אחר. רעננו ונסו שוב.';

  @override
  String get posRecentSyncPending => 'מסנכרן…';

  @override
  String get posRecentSyncFailed => 'לא סונכרן';

  @override
  String get posCartEditItem => 'עריכה';

  @override
  String get posEditSaveChanges => 'שמירת שינויים';

  @override
  String get posModifierOptionsUnavailable =>
      'לא ניתן היה לטעון את האפשרויות. אפשר לערוך רק את ההערה - האפשרויות השמורות של הפריט נשמרות כפי שהן.';

  @override
  String get posModifierSavedOptionsChanged =>
      'חלק מהאפשרויות השמורות על הפריט השתנו בתפריט. רענן את התפריט כדי לשנות אותו, או בטל כדי להשאיר אותו כפי שהן.';

  @override
  String get posModifierSavedOptionsUnavailable =>
      'חלק מהאפשרויות השמורות על הפריט כבר אינן בתפריט. רענן את התפריט כדי לשנות אותו, או בטל כדי להשאיר אותו כפי שהוא.';

  @override
  String get kdsNewOrderBadge => 'הזמנה חדשה';

  @override
  String get posReceiptPrintedNote => 'הודפס';

  @override
  String get posBluetoothConnectFailed =>
      'לא ניתן להתחבר למדפסת ה‑Bluetooth. ודא שהיא דולקת ובטווח ונסה שוב.';

  @override
  String get posBluetoothWriteFailed =>
      'שליחת נתוני ההדפסה נכשלה — החיבור נותק באמצע ההדפסה. נסה שוב.';

  @override
  String get posBluetoothNotPaired =>
      'המדפסת אינה מותאמת. התאם אותה בהגדרות ה‑Bluetooth של אנדרואיד ונסה שוב.';

  @override
  String get ordersTabActive => 'הזמנות פעילות';

  @override
  String get ordersTabHistory => 'היסטוריה';

  @override
  String get ordersActiveTitle => 'הזמנות פעילות';

  @override
  String get ordersActiveSubtitle => 'הזמנות שעדיין פתוחות כעת';

  @override
  String get ordersActiveEmpty => 'אין הזמנות פעילות';

  @override
  String get ordersActiveEmptyHint =>
      'הזמנות מופיעות כאן מיד עם שליחתן, ונשארות עד לסגירתן.';

  @override
  String get ordersActiveDemoNotice => 'הזמנות פעילות לדוגמה — לא נטענו משרת.';

  @override
  String get ordersActiveSummaryTotal => 'פעילות כעת';

  @override
  String get ordersActiveSummaryAwaitingClose => 'ממתינות לסגירה';

  @override
  String get ordersActiveStageAll => 'כל השלבים';

  @override
  String get ordersActiveAgeLabel => 'פתוחה כבר';

  @override
  String ordersActiveAgeMinutes(int minutes) {
    return '$minutes דק׳';
  }

  @override
  String ordersActiveAgeHours(int hours, int minutes) {
    return '$hours שע׳ $minutes דק׳';
  }

  @override
  String get ordersActiveNoDueTimeNotice =>
      'לא הוגדר זמן הבטחה, ולכן הזמנות לעולם אינן מסומנות כמאחרות — מוצג רק משך הזמן שהן פתוחות.';

  @override
  String get ordersActiveAutoRefresh => 'רענון אוטומטי';

  @override
  String ordersActiveLastUpdated(String time) {
    return 'עודכן $time';
  }

  @override
  String ordersActiveTruncated(int shown, int total) {
    return 'מוצגות $shown ההזמנות הוותיקות ביותר מתוך $total הזמנות פעילות.';
  }

  @override
  String get ordersBranchAll => 'כל הסניפים המורשים';

  @override
  String get ordersCompleteAction => 'סגירת הזמנה';

  @override
  String get ordersCompleteRecoveryNote =>
      'ההזמנה הוגשה ושולמה, ולכן הייתה אמורה להיסגר מעצמה. סגירה ידנית היא פעולת תיקון.';

  @override
  String get ordersCompleteConfirmTitle => 'לסגור את ההזמנה?';

  @override
  String ordersCompleteConfirmBody(String orderCode) {
    return 'פעולה זו סוגרת את הזמנה $orderCode ומעבירה אותה להיסטוריית ההזמנות. היא אינה רושמת תשלום.';
  }

  @override
  String get ordersCompletePaymentLabel => 'תשלום';

  @override
  String get ordersCompleteBlockedUnpaid =>
      'ההזמנה אינה משולמת. יש לרשום את התשלום לפני סגירתה.';

  @override
  String get ordersCompleteSuccess => 'ההזמנה נסגרה';

  @override
  String get ordersCompleteErrorNotPaid =>
      'לא ניתן לסגור את ההזמנה לפני שנרשם התשלום.';

  @override
  String get ordersCompleteErrorInvalidState =>
      'ההזמנה כבר אינה מוכנה לסגירה. רענן ונסה שוב.';

  @override
  String get ordersCompleteErrorDenied => 'אין לך הרשאה לסגור הזמנה זו.';

  @override
  String get ordersCompleteErrorConflict =>
      'מישהו אחר עדכן את ההזמנה. רענן כדי לראות את המצב העדכני.';

  @override
  String get ordersCompleteErrorNotFound => 'ההזמנה כבר אינה זמינה.';

  @override
  String get ordersCompleteErrorTransient =>
      'לא ניתן להגיע לשרת. ההזמנה לא שונתה.';

  @override
  String get ordersCompleteRetry => 'נסה שוב';

  @override
  String get activityLogFieldOrderCode => 'הזמנה';

  @override
  String get activityLogFieldPaymentStatus => 'תשלום';

  @override
  String get dashboardNoCharge => 'ללא חיוב';

  @override
  String get ordersPaymentFrozen =>
      'ההזמנה כבר שולמה, ולכן הסכום שלה נעול. לא ניתן עוד לשנות הנחות.';

  @override
  String get activityLogFieldDeniedReason => 'סיבה';

  @override
  String get activityLogDeniedOrderHasPayment => 'ההזמנה כבר שולמה';

  @override
  String get activityLogDeniedFullCompRequiresManager => 'פטור מלא מחייב מנהל';

  @override
  String get activityLogDeniedOrderNotVoidable => 'ההזמנה כבר נסגרה';

  @override
  String get activityLogPaymentNotChargeable => 'אין תשלום נדרש';

  @override
  String get activityLogFieldCompletionMode => 'אופן הסגירה';

  @override
  String get activityLogFieldCompletionTrigger => 'מה סגר';

  @override
  String get activityLogCompletionModeAutomatic => 'אוטומטית';

  @override
  String get activityLogCompletionModeManual => 'על ידי אדם';

  @override
  String get activityLogCompletionTriggerOrderServed => 'הגשת ההזמנה';

  @override
  String get activityLogCompletionTriggerPaymentRecorded => 'רישום התשלום';

  @override
  String get ordersActiveSubtitleV2 =>
      'הזמנות פתוחות כעת בתפעול. הזמנות שהסתיימו עוברות להיסטוריה.';

  @override
  String get ordersQueueInProgress => 'בתהליך';

  @override
  String get ordersQueueAwaitingClose => 'ממתינות לסגירה';

  @override
  String get ordersQueueAllActive => 'כל ההזמנות הפעילות';

  @override
  String get ordersSortLabel => 'מיון';

  @override
  String get ordersSortNewest => 'החדשות ביותר תחילה';

  @override
  String get ordersSortOldest => 'הוותיקות ביותר תחילה';

  @override
  String get ordersActiveEmptyInProgress =>
      'אין כרגע הזמנות בהכנה או בהמתנה להגשה.';

  @override
  String get ordersActiveEmptyAwaitingClose =>
      'אין הזמנות שהוגשו וממתינות לסגירה.';

  @override
  String get ordersAwaitingCloseExplainer =>
      'הזמנה שהוגשה נסגרת מעצמה ברגע שהיא משולמת במלואה, ולכן כל מה שנשאר כאן דורש טיפול — לרוב תשלום שלא נרשם. רשמו את התשלום וההזמנה תיסגר מעצמה.';

  @override
  String ordersAwaitingCloseBacklog(int count) {
    return '$count הזמנות שהוגשו לא נסגרו. הזמנה שהוגשה נסגרת מעצמה ברגע שהיא משולמת במלואה, ולכן אלו ממתינות למשהו.';
  }

  @override
  String ordersActiveTruncatedNewest(int shown, int total) {
    return 'מוצגות $shown ההזמנות החדשות ביותר מתוך $total הזמנות פעילות תואמות.';
  }

  @override
  String ordersActiveTruncatedOldest(int shown, int total) {
    return 'מוצגות $shown ההזמנות הוותיקות ביותר מתוך $total הזמנות פעילות תואמות.';
  }

  @override
  String get ordersActiveRefreshFailed =>
      'הרענון נכשל כעת. ייתכן שההזמנות אינן מעודכנות.';

  @override
  String get staffCapApplyFullComp => 'יכול לתת הזמנה חינם';

  @override
  String get staffCapApplyFullCompHint =>
      'מאפשר הנחה שמאפסת את סכום ההזמנה. כבוי כברירת מחדל.';

  @override
  String get staffCapApplyFullCompNeedsDiscount =>
      'דורש את הרשאת ההנחה שלמעלה.';

  @override
  String get staffCapabilitiesRoleNote =>
      'למנהלים ולבעלים כבר יש את כל ההרשאות האלה.';

  @override
  String get posDiscountFullCompDenied =>
      'אין לך הרשאה לתת הזמנה חינם — פנה למנהל.';

  @override
  String get posDiscountExceedsOrderTotal => 'ההנחה גדולה מסכום ההזמנה.';

  @override
  String get activityLogCapApplyFullComp => 'מתן הזמנה חינם';

  @override
  String get activityLogDeniedFullCompPermissionRequired =>
      'מתן הזמנה חינם דורש הרשאה';

  @override
  String get activityLogDeniedDiscountExceedsOrderTotal =>
      'ההנחה עלתה על סכום ההזמנה';

  @override
  String get activityLogFieldResultingChargeState => 'יישאר';

  @override
  String get activityLogTitleDiscountDenied => 'ההנחה נדחתה';

  @override
  String get posOrdersCenterTitle => 'הזמנות';

  @override
  String get posOrdersSectionOpen => 'פתוחות';

  @override
  String get posOrdersSectionNeedsPayment => 'ממתינות לתשלום';

  @override
  String get posOrdersSectionCompleted => 'נסגרו לאחרונה';

  @override
  String get posOrdersSectionAll => 'כל האחרונות';

  @override
  String get posOrdersSearchHint => 'חיפוש לפי מספר הזמנה';

  @override
  String get posOrdersSearchClear => 'ניקוי החיפוש';

  @override
  String get posOrdersSearchEmpty => 'אין הזמנה שתואמת לחיפוש';

  @override
  String get posOrdersEmptyOpen => 'אין כרגע הזמנות פתוחות';

  @override
  String get posOrdersEmptyNeedsPayment => 'אין הזמנות שממתינות לתשלום';

  @override
  String get posOrdersEmptyCompleted => 'אין הזמנות שנסגרו לאחרונה';

  @override
  String get posOrdersEmptyOffline => 'אין הזמנות שמורות זמינות במצב לא מקוון';

  @override
  String get posOrdersLoadMore => 'טעינת עוד';

  @override
  String get posOrdersRefresh => 'רענון הזמנות';

  @override
  String get posOrdersSyncing => 'מסנכרן...';

  @override
  String posOrdersLastUpdated(String time) {
    return 'עודכן לאחרונה $time';
  }

  @override
  String get posOrdersOffline => 'לא מקוון - מוצגים נתונים שמורים';

  @override
  String get posOrdersSortNewest => 'החדשות תחילה';

  @override
  String get posOrdersSortOldest => 'הישנות תחילה';

  @override
  String get posOrdersFilterStatus => 'סטטוס';

  @override
  String get posOrdersFilterSettlement => 'תשלום';

  @override
  String get posOrdersSettlementAll => 'הכול';

  @override
  String get posOrdersSettlementUnpaid => 'ממתינה לתשלום';

  @override
  String get posOrdersSettlementPaid => 'שולם';

  @override
  String get posOrdersSettlementNoCharge => 'ללא חיוב';

  @override
  String get posOrdersPendingPayment => 'מסנכרן תשלום...';

  @override
  String get posOrdersPendingDiscount => 'מסנכרן הנחה...';

  @override
  String get posOrdersPendingCancellation => 'מסנכרן ביטול...';

  @override
  String get posOrdersOtherTill => 'קופה אחרת';

  @override
  String get posOrdersStatusSubmitted => 'נשלחה';

  @override
  String get posOrdersStatusAccepted => 'התקבלה';

  @override
  String get posOrdersStatusPreparing => 'בהכנה';

  @override
  String get posOrdersStatusReady => 'מוכנה';

  @override
  String get posOrdersStatusServed => 'הוגשה';

  @override
  String get posOrdersStatusCompleted => 'הושלמה';

  @override
  String get posOrdersStatusCancelled => 'בוטלה';

  @override
  String get posOrdersStatusVoided => 'בוטלה סופית';

  @override
  String get posOrdersConflictRefreshed =>
      'ההזמנה השתנתה במכשיר אחר. היא רועננה - בדוק ונסה שוב.';

  @override
  String get posOrdersConflictClose => 'סגור ופתח מחדש';

  @override
  String get posOrdersStatusPickedUp => 'נאסף';

  @override
  String get posMenuItemSoldOut => 'אזל מהמלאי';

  @override
  String get posMenuItemConfigurationUnavailable => 'האפשרויות אינן זמינות';

  @override
  String get posMenuItemPaused => 'לא זמין זמנית';

  @override
  String posSyncItemUnavailable(String items) {
    return 'לא זמין כרגע: $items. הזן את ההזמנה מחדש ללא פריטים אלה.';
  }

  @override
  String get posPrepSnapshotStale =>
      'הגדרות ההכנה בתפריט השתנו. רענן את התפריט ובחר שוב את אפשרויות הפריט.';

  @override
  String get posSyncTableUnavailable =>
      'השולחן שנבחר אינו זמין עוד. בחר שולחן אחר והזן את ההזמנה מחדש.';

  @override
  String get posOrdersFilterTypeAll => 'כל הסוגים';

  @override
  String get posMoveTableAction => 'העברת שולחן';

  @override
  String get posMoveTableTitle => 'העברה לשולחן אחר';

  @override
  String posMoveTableCurrent(String table) {
    return 'שולחן נוכחי: $table';
  }

  @override
  String get posMoveTableNoTable => 'עדיין לא הוקצה שולחן';

  @override
  String get posMoveTableConfirm => 'העבר';

  @override
  String posMoveTableMoved(String table) {
    return 'הועבר אל $table';
  }

  @override
  String get posMoveTableConflict =>
      'הזמנה זו השתנתה במכשיר אחר. סגור ופעל שוב מתוך ההזמנה המעודכנת.';

  @override
  String get posMoveTableNotMovable => 'לא ניתן עוד להעביר הזמנה זו.';

  @override
  String get posMoveTableTableUnavailable =>
      'השולחן הזה אינו זמין עוד. בחר אחר.';

  @override
  String get posMoveTablePermissionDenied => 'אין לך הרשאה להעביר הזמנה זו.';

  @override
  String get posMoveTableFailed =>
      'לא ניתן היה להעביר את השולחן. בדוק את החיבור ונסה שוב.';

  @override
  String posTableOpenOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count הזמנות פתוחות',
      one: 'הזמנה פתוחה אחת',
    );
    return '$_temp0';
  }

  @override
  String get kdsServedAction => 'הוגש';

  @override
  String get kdsPickedUpAction => 'נאסף';

  @override
  String get ordersStatusPickedUp => 'נאסף';

  @override
  String get menuAvailabilityLabel => 'זמינות';

  @override
  String get menuAvailabilityAvailable => 'זמין';

  @override
  String get menuAvailabilityUnavailable => 'לא זמין';

  @override
  String get menuAvailabilitySoldOut => 'אזל מהמלאי';

  @override
  String get menuAvailabilityPaused => 'מושהה';

  @override
  String get menuAvailabilityUpdated => 'הזמינות עודכנה';

  @override
  String get menuAvailabilityUpdateFailed => 'לא ניתן היה לעדכן את הזמינות';

  @override
  String get menuAvailabilityNeedsBranch => 'בחר סניף כדי לנהל זמינות';

  @override
  String tablesOpenOrders(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count הזמנות פתוחות',
      one: 'הזמנה פתוחה אחת',
      zero: 'אין הזמנות פתוחות',
    );
    return '$_temp0';
  }

  @override
  String get activityLogTitleMenuAvailabilityChanged =>
      'זמינות פריט התפריט שונתה';

  @override
  String get activityLogTitleMenuAvailabilityDenied =>
      'שינוי זמינות התפריט נדחה';

  @override
  String get activityLogTitleOrderTableMoved => 'ההזמנה הועברה לשולחן אחר';

  @override
  String get activityLogTitleOrderTableMoveDenied => 'העברת השולחן נדחתה';

  @override
  String get activityLogTitleTableStatusChanged => 'סטטוס השולחן שונה';

  @override
  String get activityLogTitleTableStatusDenied => 'שינוי סטטוס השולחן נדחה';

  @override
  String get activityLogTitleTablesLinked => 'השולחנות קושרו';

  @override
  String get activityLogTitleTableLinkDenied => 'קישור השולחן נדחה';

  @override
  String get activityLogTitleTablesUnlinked => 'קישור השולחנות בוטל';

  @override
  String get activityLogTitleTableUnlinkDenied => 'ביטול קישור השולחן נדחה';

  @override
  String get activityLogFieldFromStatus => 'מסטטוס';

  @override
  String get activityLogFieldToStatus => 'לסטטוס';

  @override
  String get activityLogFieldGroupLabel => 'שולחנות מקושרים';

  @override
  String get activityLogFieldVoidedFromStatus => 'הסטטוס בעת הביטול';

  @override
  String get activityLogFieldDeviceType => 'סוג המכשיר';

  @override
  String get activityLogFieldKitchenAckRequired => 'נדרש אישור מטבח';

  @override
  String get activityLogFieldAvailability => 'זמינות';

  @override
  String get activityLogFieldAvailabilityReason => 'סיבה';

  @override
  String get activityLogFieldItemName => 'פריט';

  @override
  String get activityLogFieldTableLabel => 'שולחן';

  @override
  String get activityLogFieldFromTable => 'משולחן';

  @override
  String get activityLogFieldToTable => 'לשולחן';

  @override
  String get activityLogDeniedTakeawayOrder =>
      'הזמנות טייק-אווי אינן משתמשות בשולחנות';

  @override
  String get activityLogDeniedOrderNotMovable => 'לא ניתן עוד להעביר את ההזמנה';

  @override
  String get activityLogDeniedTableNotAvailable => 'השולחן אינו זמין';

  @override
  String get activityLogDeniedPermission => 'אין הרשאה לתפקיד זה';

  @override
  String get printersRoleBoth => 'שניהם';

  @override
  String get printersPurposeBothHint =>
      'מדפסת אחת מדפיסה קבלות ללקוחות וכרטיסי מטבח';

  @override
  String get printersReadinessTitle => 'מוכנות מדפסות';

  @override
  String get printersReadinessServerOnly =>
      'רשומות שרת בלבד — בחירת המכשיר והדפסה בפועל אינן מאומתות כאן';

  @override
  String get printersReadinessMissing => 'חסרה';

  @override
  String get printers80mmReady => 'מוכנה 80מ״מ';

  @override
  String get printers80mmRequired => 'נדרש 80מ״מ';

  @override
  String get printersCustomerReceiptPrinter => 'מדפסת קבלות ללקוחות';

  @override
  String get printersKitchenTicketPrinter => 'מדפסת כרטיסי מטבח';

  @override
  String get printersSameForBoth => 'אותה מדפסת יכולה לשרת את שני היעדים';

  @override
  String get printersKitchenPreparationTitle => 'הכנת מטבח במדפסת בלבד';

  @override
  String get printersPrinterOnlyNotYetAvailable =>
      'הכנת מטבח במדפסת בלבד עדיין אינה זמינה עד להשלמת מוכנות המכשירים.';

  @override
  String get activityLogTitlePrinterCreated => 'נוספה מדפסת';

  @override
  String get activityLogTitlePrinterUpdated => 'המדפסת עודכנה';

  @override
  String get activityLogTitlePrinterDeleted => 'המדפסת הוסרה';

  @override
  String get activityLogTitlePrinterRouteUpdated => 'ניתוב המדפסת שונה';

  @override
  String get activityLogFieldPaperWidth => 'רוחב נייר';

  @override
  String get activityLogFieldEnabled => 'מופעלת';

  @override
  String get activityLogFieldConnectionType => 'חיבור';

  @override
  String get posPrinterPurposeHeading => 'מה מדפיסה המדפסת הזו?';

  @override
  String get posPrinterPurposeCustomer => 'קבלות ללקוחות';

  @override
  String get posPrinterPurposeKitchen => 'כרטיסי מטבח';

  @override
  String get posKitchenPrinterPreparationTitle => 'הדפסה אוטומטית למטבח';

  @override
  String get posKitchenPrinterPreparationBody =>
      'הדפסה אוטומטית של כרטיס מטבח פועלת לפי תהליך המטבח שנקבע לסניף זה בלוח הבקרה, ודורשת מדפסת מטבח מוגדרת. אפשר גם להדפיס כרטיס מטבח ידנית מתוך הזמנה שנוצרה.';

  @override
  String get posKitchenPrinterUseCustomerAction =>
      'השתמש במדפסת הלקוחות לכרטיסי מטבח';

  @override
  String get posKitchenPrinterCopiedSnack =>
      'מדפסת הלקוחות הועתקה למשבצת המטבח';

  @override
  String get posKitchenPrinterNothingToCopySnack => 'טרם הוגדרה מדפסת לקוחות';

  @override
  String get posKitchenTestBanner => '*** בדיקה ***';

  @override
  String get posKitchenTestTitle => 'בדיקת כרטיס מטבח';

  @override
  String get posKitchenTestSampleItem => '1 x פריט לדוגמה';

  @override
  String get posKitchenTestSampleModifier => '+ תוספת לדוגמה';

  @override
  String get posKitchenTestSampleNote => 'הערה: הערת דוגמה';

  @override
  String get brandingSectionTitle => 'לוגו בקבלה';

  @override
  String get brandingSectionSubtitle =>
      'הדפיסו את הלוגו שלכם בראש קבלות הלקוח.';

  @override
  String get brandingUploadAction => 'בחירת לוגו';

  @override
  String get brandingReplaceAction => 'החלפה';

  @override
  String get brandingRemoveAction => 'הסרה';

  @override
  String get brandingSaveAction => 'שמירת לוגו';

  @override
  String get brandingEnableToggle => 'הדפסת לוגו בקבלות הלקוח';

  @override
  String get brandingCurrentLabel => 'הלוגו הנוכחי';

  @override
  String get brandingPreviewLabel => 'תצוגה מקדימה (טרם נשמר)';

  @override
  String get brandingNoLogo => 'לא הוגדר לוגו';

  @override
  String get brandingFormatsHint => 'PNG, JPEG או WebP, עד 2 MB.';

  @override
  String get brandingSaved => 'הלוגו נשמר.';

  @override
  String get brandingRemoved => 'הלוגו הוסר.';

  @override
  String get brandingCleanupWarning =>
      'הלוגו נשמר. לא ניתן היה להסיר את התמונה הקודמת.';

  @override
  String get brandingErrorInvalidType =>
      'סוג הקובץ אינו נתמך. השתמשו ב-PNG, JPEG או WebP.';

  @override
  String get brandingErrorTooLarge => 'התמונה גדולה מ-2 MB.';

  @override
  String get brandingErrorTooSmall => 'התמונה קטנה מדי.';

  @override
  String get brandingErrorDimensions =>
      'מידות התמונה גדולות מדי (עד 4096 על 4096).';

  @override
  String get brandingErrorBlank => 'התמונה נראית ריקה.';

  @override
  String get brandingErrorTransparent => 'התמונה שקופה לחלוטין.';

  @override
  String get brandingErrorAspect => 'התמונה רחבה או גבוהה מדי.';

  @override
  String get brandingErrorCorrupt => 'לא ניתן היה לקרוא את התמונה.';

  @override
  String get brandingErrorUploadFailed => 'ההעלאה נכשלה. דבר לא שונה.';

  @override
  String get brandingErrorSaveFailed => 'השמירה נכשלה. דבר לא שונה.';

  @override
  String get brandingErrorDenied => 'אין לך הרשאה לשנות את המיתוג.';

  @override
  String get brandingErrorConflict =>
      'המיתוג שונה על ידי מישהו אחר. מוצג המצב העדכני.';

  @override
  String get brandingRemoveConfirmTitle => 'להסיר את הלוגו?';

  @override
  String get brandingRemoveConfirmBody =>
      'קבלות הלקוח יפסיקו להציג את הלוגו שלכם.';

  @override
  String get brandingUnavailable => 'ניהול הלוגו אינו זמין כאן.';

  @override
  String get brandingDemoNote =>
      'התחברו לסביבת עבודה חיה כדי לנהל את לוגו הקבלה.';

  @override
  String get brandingPickerUnsupported => 'העלאה זמינה רק בלוח הבקרה בדפדפן.';

  @override
  String get brandingReadOnlyNote => 'לוגו הקבלה מנוהל ברמת המסעדה.';

  @override
  String get brandingErrorUncertain =>
      'לא הצלחנו לאמת את השינוי. רעננו ובדקו לפני ניסיון נוסף.';

  @override
  String get posParkOrder => 'השהיית הזמנה';

  @override
  String get posParkedOrders => 'הזמנות מושהות';

  @override
  String get posParkedOrdersEmpty => 'אין הזמנות מושהות';

  @override
  String get posParkedOrdersLoading => 'טוען הזמנות מושהות';

  @override
  String get posParkedOrdersLoadFailed => 'לא ניתן לטעון הזמנות מושהות';

  @override
  String get posParkedOrdersRetry => 'נסה שוב';

  @override
  String get posParkedRestore => 'שחזור';

  @override
  String get posParkedDelete => 'מחיקה';

  @override
  String get posParkedDeleteTitle => 'מחיקת הזמנה מושהית';

  @override
  String posParkedDeleteBody(String label) {
    return 'למחוק את $label? ההזמנה לא נשלחה, ולכן דבר אינו מבוטל בשרת.';
  }

  @override
  String get posParkedParkSucceeded => 'ההזמנה הושהתה';

  @override
  String get posParkedParkFailed =>
      'לא ניתן להשהות את ההזמנה. היא נשארה בעגלה.';

  @override
  String get posParkedRestoreFailed =>
      'לא ניתן לשחזר את ההזמנה. היא נשארה מושהית.';

  @override
  String get posParkedTableUnavailable =>
      'השולחן כבר אינו זמין, ולכן ההזמנה שוחזרה ללא שולחן.';

  @override
  String get posParkedActiveCartTitle => 'העגלה הנוכחית אינה ריקה';

  @override
  String get posParkedActiveCartBody =>
      'השהו תחילה את העגלה הנוכחית ולאחר מכן שחזרו את זו. דבר אינו ממוזג או נמחק.';

  @override
  String get posParkedParkCurrentAndRestore => 'השהיית העגלה הנוכחית ושחזור';

  @override
  String get posParkedBlockedByAddition =>
      'השהיה אינה זמינה בעת הוספת פריטים להזמנה';

  @override
  String get posParkedCopyRetained =>
      'שוחזר, אך לא ניתן היה להסיר את העותק המושהה.';

  @override
  String posParkedItemCount(int count) {
    return '$count פריטים';
  }

  @override
  String posParkedAt(String time) {
    return 'הושהה $time';
  }

  @override
  String posParkedOrdersTooltip(int count) {
    return 'הזמנות מושהות: $count';
  }

  @override
  String get posParkedUnnamedOrder => 'הזמנה מושהית';

  @override
  String get posOrderPreviewTitle => 'פרטי ההזמנה';

  @override
  String get posOrderPreviewLoadFailedTitle => 'לא ניתן לטעון את ההזמנה';

  @override
  String get posOrderPreviewLoadFailedBody =>
      'פרטי ההזמנה אינם זמינים כעת. דבר לא שונה.';

  @override
  String get posOrderPreviewLocalCopy => 'עותק מקומי - לא רוענן';

  @override
  String get posOrderPreviewRetry => 'נסה שוב';

  @override
  String get posOrderPreviewLoading => 'טוען את פרטי ההזמנה';

  @override
  String get posOrderPreviewItems => 'פריטים';

  @override
  String posOrderPreviewOpenedAt(String time) {
    return 'נפתח $time';
  }

  @override
  String get dashboardKitchenWorkflowSectionTitle => 'תהליך העבודה במטבח';

  @override
  String get dashboardKitchenWorkflowKdsLabel => 'מסך מטבח ייעודי';

  @override
  String get dashboardKitchenWorkflowKdsHelp =>
      'ההזמנות מנוהלות ממסך מטבח נפרד.';

  @override
  String get dashboardKitchenWorkflowPrinterLabel => 'מכשיר אחד עם מדפסת מטבח';

  @override
  String get dashboardKitchenWorkflowPrinterHelp =>
      'הקופה מדפיסה כרטיסי מטבח ויכולה לסגור סבבי מטבח מאושרים ללא מכשיר מטבח נפרד.';

  @override
  String get dashboardKitchenWorkflowOwnerOnly =>
      'רק בעלים יכול לשנות הגדרה זו.';

  @override
  String get dashboardKitchenWorkflowUnavailable =>
      'לא הצלחנו לטעון את ההגדרה כעת. נסה שוב מאוחר יותר.';

  @override
  String get dashboardKitchenWorkflowConfirmTitle =>
      'לשנות את תהליך העבודה במטבח?';

  @override
  String dashboardKitchenWorkflowConfirmBranch(String branch) {
    return 'סניף: $branch';
  }

  @override
  String dashboardKitchenWorkflowConfirmChange(String from, String to) {
    return 'מ-$from ל-$to';
  }

  @override
  String get dashboardKitchenWorkflowPrinterWarning =>
      'סניף זה אמור לעבוד עם הקופה ומדפסות המטבח, ללא תהליך עבודה של מסך מטבח ייעודי.';

  @override
  String get dashboardKitchenWorkflowConfirmAction => 'שמירת תהליך העבודה';

  @override
  String get dashboardKitchenWorkflowSaved => 'תהליך העבודה במטבח נשמר.';

  @override
  String get dashboardKitchenWorkflowDenied => 'אין לך הרשאה לשנות הגדרה זו.';

  @override
  String get dashboardKitchenWorkflowNotFound =>
      'הסניף אינו זמין עבור החשבון שלך.';

  @override
  String get dashboardKitchenWorkflowSaveFailed =>
      'לא הצלחנו לשמור את תהליך העבודה במטבח. נסה שוב.';

  @override
  String get posSyncDetailsTitle => 'סנכרון';

  @override
  String get posSyncDetailsClose => 'סגירה';

  @override
  String get posSyncDetailsRowPending => 'ממתין לשליחה';

  @override
  String get posSyncDetailsRowSyncing => 'נשלח כעת';

  @override
  String get posSyncDetailsRowFailed => 'נכשל';

  @override
  String get posSyncDetailsRowResolved => 'כשלים סופיים';

  @override
  String get posSyncDetailsRowAttention => 'דורש בדיקה';

  @override
  String get posSyncDetailsExplainSynced =>
      'אין דבר שממתין לשליחה, וכל הזמנה שהמכשיר הזה שלח אושרה בשרת. אפשר לסגור או להחליף את האפליקציה בבטחה.';

  @override
  String get posSyncDetailsExplainPending =>
      'חלק מההזמנות עדיין שמורות במכשיר ולא נשלחו. השאירו את המכשיר מחובר עד לסיום.';

  @override
  String get posSyncDetailsExplainSyncing =>
      'ההזמנות נשלחות כעת. השאירו את המכשיר מחובר.';

  @override
  String get posSyncDetailsExplainFailed =>
      'לא ניתן היה לשלוח חלק מההזמנות. הן עדיין שמורות במכשיר וניתן לנסות שוב.';

  @override
  String get posSyncDetailsExplainResolved =>
      'השרת דחה אותן לפני שנוצר משהו, ולכן לא אבדה אף הזמנה. אפשר לנקות אותן.';

  @override
  String get posSyncDetailsExplainAttention =>
      'חלק מהפעולות הסתיימו במצב שהאפליקציה אינה יכולה לפתור לבד. אין להסיר את האפליקציה לפני בדיקת מנהל.';

  @override
  String get posSyncRetryConfirmTitle => 'לנסות לשלוח שוב הזמנות שנכשלו?';

  @override
  String get posSyncRetryConfirmBody =>
      'ההזמנות השמורות יישלחו שוב. שליחה כפולה של אותה הזמנה בטוחה ולא תיצור כפילות.';

  @override
  String get posSyncRetryStarted => 'שולח שוב הזמנות שנכשלו';

  @override
  String get posSyncClearConfirmTitle => 'לנקות כשלים סופיים?';

  @override
  String get posSyncClearConfirmBody =>
      'הם נדחו לפני שנוצר משהו, ולכן לא אבדה אף הזמנה. הם יוסרו מהרשימה הזו בלבד.';

  @override
  String get posOfflineModeBanner => 'לא מקוון — מוצג התפריט השמור';

  @override
  String posOfflineDataAge(String age) {
    return 'נשמר $age';
  }

  @override
  String get posOfflineSetupRequiredTitle => 'נדרשת הגדרה מקוונת';

  @override
  String get posOfflineSetupRequiredBody =>
      'אין עדיין תפריט שמור במכשיר זה. יש לחבר אותו לאינטרנט פעם אחת כדי להוריד את התפריט וההגדרות — לאחר מכן הוא יכול להמשיך למכור ללא חיבור.';

  @override
  String get posOfflineReauthNeeded => 'ממתין להתחברות';

  @override
  String get posOfflineSessionExpired =>
      'חלון העבודה ללא חיבור הסתיים — יש להתחבר לאינטרנט ולהיכנס מחדש.';

  @override
  String get posOfflineSendBlockedSession =>
      'השליחה מושהית — חלון העבודה ללא חיבור הסתיים. התחברו והיכנסו מחדש כדי לשלוח הזמנות.';

  @override
  String get posOfflineKitchenModeStale =>
      'עבר זמן רב מדי ללא חיבור ולא ניתן לאמת את הגדרת המטבח השמורה — התחברו מחדש כדי לשלוח הזמנות.';

  @override
  String posOutboxAuthHold(int count) {
    return '$count ממתינות לכניסה מחדש';
  }

  @override
  String get posOutboxAuthHoldTooltip =>
      'ההזמנות האלה שמורות במכשיר הזה. היכנסו מחדש והן יסתנכרנו אוטומטית.';

  @override
  String get posOfflineReconnecting => 'בודק את החיבור…';

  @override
  String get posOfflineSyncRestored => 'נכנסת — ההזמנות השמורות מסתנכרנות כעת.';

  @override
  String get posOfflineOrderSavedLocally => 'נשמר במכשיר הזה';

  @override
  String get posOfflineAwaitingSync => 'ממתין לסנכרון';

  @override
  String get posOfflinePrinterUnreachable =>
      'אין גישה למדפסת — בדקו את חיבור המדפסת.';

  @override
  String get posOfflinePrintPending =>
      'כרטיס המטבח עדיין לא הודפס — השתמשו ב\"הדפסת כרטיס מטבח\" כשהמדפסת זמינה.';

  @override
  String get posOfflineActionUnavailable =>
      'לא זמין במצב לא מקוון — התחברו מחדש כדי להשתמש בפעולה זו.';

  @override
  String get posOfflineKdsPending =>
      'ההזמנה הזו תגיע למסך המטבח כשהחיבור יחזור.';

  @override
  String get posOfflineBannerReconnecting => 'מתחבר מחדש…';

  @override
  String get posPaymentAwaitingOrderSync =>
      'ההזמנה עדיין מסתנכרנת — התשלום ייפתח ברגע שהשרת יאשר אותה.';

  @override
  String get posCashDrawerAutoOpenTitle =>
      'פתיחת מגירת המזומנים אוטומטית לאחר תשלום במזומן';

  @override
  String get posCashDrawerAutoOpenHelp =>
      'משתמש ביציאת המגירה של מדפסת הקבלות.';

  @override
  String get posCashDrawerOpenFailed => 'התשלום נרשם — מגירת המזומנים לא נפתחה';

  @override
  String get posDeviceAccentTitle => 'צבע הדגשה למסוף זה';

  @override
  String get posDeviceAccentHelp =>
      'צובע הדגשות קטנות במסוף זה בלבד — לא סטטוסים ולא מחירים.';

  @override
  String get posDeviceAccentMint => 'מנטה';

  @override
  String get posDeviceAccentSaffron => 'זעפרן';

  @override
  String get posDeviceAccentPomegranate => 'רימון';

  @override
  String get posDeviceAccentAubergine => 'חציל';

  @override
  String posItemAddedToast(String name) {
    return '$name נוסף';
  }

  @override
  String get posAddMore => 'הוסף עוד';

  @override
  String get posMenuItemAvailable => 'זמין';

  @override
  String get posCartEmptyHint => 'בחרו פריטים מהתפריט כדי להתחיל הזמנה חדשה';

  @override
  String get posSending => 'שולח…';

  @override
  String get posBrandName => 'רסטופלו';

  @override
  String get posBrandTagline => 'נקודת מכירה';

  @override
  String get posDeviceThemeTitle => 'מראה המכשיר הזה';

  @override
  String get posDeviceThemeHelp =>
      'בחרו את זהות הצבעים של הקופה הזו. השינוי חל על הסרגל, הכפתורים וההדגשות במכשיר זה בלבד — ואינו משפיע על הזמנות, סטטוסים או קבלות.';

  @override
  String get posDeviceThemeNavyEmber => 'כחול כהה ונחושת';

  @override
  String get posDeviceThemeForestCharcoal => 'ירוק יער ונחושת';

  @override
  String get posDeviceThemeAubergineSlate => 'חציל ולבנה';

  @override
  String get posDeviceThemeSaffronGold => 'פחם וזהב';

  @override
  String get posDeviceThemeCustom => 'מותאם אישית';

  @override
  String get posDeviceThemeCustomHelp =>
      'בחרו שני צבעים בעין — הם משנים את מראה המכשיר הזה בלבד.';

  @override
  String get posDeviceThemeCustomPrimaryLabel => 'הצבע הראשי';

  @override
  String get posDeviceThemeCustomSecondaryLabel => 'הצבע המשני';

  @override
  String get posDeviceThemeCustomHexHint => '#RRGGBB';

  @override
  String get posDeviceThemeCustomInvalidHex => 'פורמט לא תקין — נדרש ‎#RRGGBB';

  @override
  String get posDeviceThemeCustomApply => 'החלת הצבעים';

  @override
  String get posDeviceThemeCustomCancel => 'ביטול';

  @override
  String get posDeviceThemeCustomReset => 'חזרה לברירת המחדל';

  @override
  String get posDeviceThemeCustomPreviewTitle => 'תצוגה מקדימה';

  @override
  String get posDeviceThemeCustomChange => 'שינוי';

  @override
  String get posColorPickerQuickColors => 'צבעים מהירים';

  @override
  String get posColorPickerField => 'לוח הצבעים';

  @override
  String get posColorPickerHue => 'גוון';

  @override
  String get posColorPickerShade => 'בהיר יותר או כהה יותר';

  @override
  String get posColorPickerAdvanced => 'מתקדם';

  @override
  String get posColorPickerConfirm => 'בחירת הצבע';

  @override
  String get posOpenOrdersElapsedNow => 'עכשיו';

  @override
  String posOpenOrdersElapsedMinutes(int minutes) {
    return 'לפני $minutes דק׳';
  }

  @override
  String posOpenOrdersElapsedHoursMinutes(int hours, int minutes) {
    return 'לפני $hours שע׳ $minutes דק׳';
  }

  @override
  String get setupPrintingConfig => 'הגדרת הדפסה';

  @override
  String get setupPrintingConfigHelp =>
      'תצורת ההדפסה של הסניף. היא אינה בודקת שהמדפסת פועלת, מחוברת או זמינה — החיבור הפיזי מוגדר בכל מכשיר קופה או מסך מטבח.';

  @override
  String get setupNoKitchenPrinter =>
      'אין מדפסת מטבח פעילה — מצב הדפסה בלבד מחייב אחת.';

  @override
  String get printersGovernanceIntro =>
      'קבעו אילו מדפסות יש לסניף, מה הן מדפיסות ואילו עמדות הן משרתות. כל מכשיר קופה או מסך מטבח מגדיר את החיבור הפיזי שלו; דף זה אינו יודע אם מדפסת מחוברת.';

  @override
  String get posReprintChooserTitle => 'הדפסה חוזרת';

  @override
  String get posReprintCustomerReceipt => 'קבלת לקוח';

  @override
  String get posReprintCustomerReceiptHint =>
      'מדפיסה את קבלת הקופה במדפסת הקבלות.';

  @override
  String get posReprintKitchenTicket => 'פתק מטבח';

  @override
  String get posReprintKitchenTicketHint =>
      'מדפיסה את פתק ההזמנה במדפסת המטבח.';

  @override
  String get posReprintKitchenUnavailable =>
      'להזמנה זו אין פתק מטבח להדפסה במכשיר זה.';

  @override
  String get posReprintKitchenFetchFailed =>
      'לא ניתן לטעון הזמנה זו מהשרת להדפסה חוזרת של כרטיס המטבח. בדקו את החיבור ונסו שוב.';

  @override
  String get posReprintKitchenCountsUnavailable =>
      'סיכומי ההכנה אינם זמינים להזמנה זו; הכרטיס הודפס ללא מקטע הסיכומים.';

  @override
  String get posPrintAction => 'הדפסה';

  @override
  String get posPrintChooserTitle => 'אפשרויות הדפסה';

  @override
  String get posPrintCustomerBill => 'חשבון לקוח';

  @override
  String get posPrintCustomerBillHint =>
      'מדפיסה את החשבון הנוכחי במדפסת הקבלות.';

  @override
  String get dashboardSettingsOperatingCurrency => 'מטבע המסעדה';

  @override
  String get dashboardSettingsOperatingCurrencyHint =>
      'משמש לתפריט ולהזמנות חדשות של מסעדה זו.';

  @override
  String get dashboardSettingsCurrencyInherited => 'בירושה מהגדרות הארגון';

  @override
  String get dashboardSettingsCurrencyOverridden => 'מוגדר עבור מסעדה זו';

  @override
  String get dashboardSettingsCurrencyOverrideNote =>
      'לאחר ההגדרה ניתן לשנות למטבע אחר בלבד — לא ניתן לחזור לירושה מכאן.';

  @override
  String get dashboardSettingsCurrencyChangeTitle => 'לשנות את מטבע המסעדה?';

  @override
  String get dashboardSettingsCurrencyChangeBody =>
      'הסכומים אינם מומרים. 40.00 יישאר 40.00 במטבע החדש. הזמנות, תשלומים וקבלות קודמים שומרים על המטבע המקורי שלהם.';

  @override
  String dashboardSettingsCurrencyChangeFromTo(String from, String to) {
    return '$from ← $to';
  }

  @override
  String get dashboardSettingsCurrencyChangeAck =>
      'אני מבין/ה שהסכומים אינם מומרים.';

  @override
  String get dashboardSettingsCurrencyChangeConfirm => 'שינוי מטבע';

  @override
  String get dashboardSettingsCurrencyBlockedTitle =>
      'יש לסיים תחילה עבודה פתוחה';

  @override
  String dashboardSettingsCurrencyBlockedOrders(int count) {
    return 'יש $count הזמנות פתוחות. סגרו אותן לפני שינוי המטבע.';
  }

  @override
  String dashboardSettingsCurrencyBlockedShifts(int count) {
    return 'יש $count משמרות מזומן פתוחות. סגרו אותן לפני שינוי המטבע.';
  }

  @override
  String get dashboardSettingsCurrencyBlockedUnknown =>
      'לא ניתן היה לבדוק הזמנות פתוחות ומשמרות. נסו שוב.';

  @override
  String get menuCurrencyInherited => 'בירושה מהגדרות המסעדה';

  @override
  String get dashboardSettingsCurrencySearchHint => 'חיפוש לפי קוד (למשל USD)';

  @override
  String get dashboardCurrencyMixedTitle => 'יותר ממטבע אחד בטווח הזה';

  @override
  String get dashboardCurrencyMixedBody =>
      'הסכומים מוצגים לפי מטבע. אין המרה ואין חיבור בין מטבעות.';

  @override
  String get dashboardCurrencyCheckUnavailable =>
      'הסכומים הכספיים מוסתרים: לא ניתן היה לבדוק את המטבעות של הטווח, ואסור לחבר סכומים במטבעות שונים.';

  @override
  String get menuCopyFromItemTitle => 'העתקת הגדרות מפריט קיים';

  @override
  String get menuCopyFromItemHint =>
      'שימוש חוזר בספירות המטבח, בקבוצות התוספות, באפשרויות ובמחיר הבסיס של פריט אחר. שום דבר לא נכתב עד שתלחצו על שמירה.';

  @override
  String get menuCopyFromItemAction => 'בחירת פריט מקור';

  @override
  String get menuCopyFromItemChange => 'החלפת מקור';

  @override
  String get menuCopyFromItemRemove => 'ביטול ההגדרות שהועתקו';

  @override
  String get menuCopyFromItemSearch => 'חיפוש פריטים';

  @override
  String get menuCopyFromItemEmpty =>
      'אין עדיין פריט אחר במסעדה הזו עם הגדרות להעתקה.';

  @override
  String get menuCopyFromItemNoMatch => 'אין פריט שתואם לחיפוש הזה.';

  @override
  String get menuCopyPreviewTitle => 'מה יועתק';

  @override
  String menuCopyPreviewGroups(int count) {
    return '$count קבוצות תוספות';
  }

  @override
  String menuCopyPreviewOptions(int count) {
    return '$count אפשרויות';
  }

  @override
  String menuCopyPreviewPrepRows(int count) {
    return '$count שורות בספירות המטבח';
  }

  @override
  String menuCopyPreviewKitchenCounts(int count) {
    return '$count אפשרויות נושאות ספירות מטבח';
  }

  @override
  String menuCopyPreviewClassifiers(int count) {
    return '$count קישורי פיצול, יקושרו מחדש לפריט הזה בשמירה';
  }

  @override
  String menuCopyPreviewBasePrice(String price) {
    return 'מחיר בסיס $price';
  }

  @override
  String get menuCopyPreviewNothing => 'לפריט הזה אין הגדרות להעתקה.';

  @override
  String get menuCopyPreviewExcluded =>
      'השם, התיאור, התמונה, הקטגוריה והקוד לעולם אינם מועתקים.';

  @override
  String get menuCopyApplyAction => 'העתקת הגדרות';

  @override
  String get menuCopyDraftNotice => 'עדיין לא נשמר — לחצו על שמירה כדי ליצור.';

  @override
  String menuCopyAppliedFrom(String name) {
    return 'הועתק מתוך $name';
  }

  @override
  String get menuCopyReplaceTitle => 'להחליף את ההגדרות בטופס הזה?';

  @override
  String get menuCopyReplaceBody =>
      'מחיר הבסיס, ספירות המטבח והתוספות בטופס הזה יוחלפו במועתקים. שום דבר בשרת לא משתנה עד שתלחצו על שמירה.';

  @override
  String get menuCopyReplaceConfirm => 'החלפה';

  @override
  String get menuCopyBlockedHasModifiers =>
      'לפריט הזה כבר יש קבוצות תוספות, ולכן העתקה תשכפל אותן. מחקו אותן קודם, או העתיקו לפריט חדש.';

  @override
  String menuCopySavingProgress(int done, int total) {
    return 'שומר את ההגדרות שהועתקו… $done/$total';
  }

  @override
  String menuCopyFlushPartial(int groups, int options) {
    return 'נעצר לאחר יצירת $groups קבוצות ו-$options אפשרויות. שום דבר לא בוטל — לחצו שוב על שמירה כדי להמשיך מכאן.';
  }

  @override
  String menuCopySavedSummary(int groups, int options) {
    return 'הועתקו $groups קבוצות ו-$options אפשרויות.';
  }

  @override
  String get menuCopyDraftEditHint =>
      'אלו שורות טיוטה — ערכו אותן כאן. הן נוצרות בלחיצה על שמירה.';

  @override
  String get menuCopyDraftRemoveTitle => 'להסיר מההעתקה?';

  @override
  String get menuCopyDraftRemoveBody =>
      'ההסרה היא מהטופס הזה בלבד. שום דבר לא נשמר עדיין, ולכן שום דבר לא נמחק.';

  @override
  String get menuCopyDraftRemoveLinked =>
      'אפשרות אחרת מפוצלת לפי זו. הקישור הזה ינוקה.';

  @override
  String get kioskTagline => 'על האש. טרי בשבילכם.';

  @override
  String get kioskStart => 'התחילו הזמנה';

  @override
  String get kioskTouchStart => 'געו במסך כדי להתחיל';

  @override
  String get kioskHow => 'איך תרצו את הארוחה?';

  @override
  String get kioskDineIn => 'לשבת במקום';

  @override
  String get kioskTakeaway => 'לקחת';

  @override
  String get kioskDineInSub => 'אוכלים כאן במסעדה';

  @override
  String get kioskTakeawaySub => 'ארוז לדרך';

  @override
  String get kioskPayNote => 'התשלום בקופה — לא בעמדה';

  @override
  String get kioskBack => 'חזרה';

  @override
  String get kioskChooseTable => 'בחרו שולחן';

  @override
  String get kioskTableAvailable => 'פנוי';

  @override
  String get kioskTableOccupied => 'תפוס';

  @override
  String get kioskTableReserved => 'שמור';

  @override
  String kioskSeatsCount(int count) {
    return '$count מקומות';
  }

  @override
  String kioskFreeCount(int count) {
    return '$count פנויים';
  }

  @override
  String get kioskContinue => 'המשך';

  @override
  String get kioskPickTableFirst => 'בחרו שולחן פנוי כדי להמשיך';

  @override
  String get kioskTableLabel => 'שולחן';

  @override
  String get kioskMenuTitle => 'על מה בא לכם היום?';

  @override
  String get kioskSwipeMore => 'החליקו לעוד קטגוריות';

  @override
  String get kioskCart => 'סל';

  @override
  String get kioskCheckout => 'לתשלום';

  @override
  String kioskItemsCount(int count) {
    return '$count פריטים';
  }

  @override
  String get kioskYourOrder => 'ההזמנה שלכם';

  @override
  String get kioskBasePrice => 'מחיר בסיס';

  @override
  String get kioskKitchenNote => 'הערה למטבח';

  @override
  String get kioskKitchenNoteHint => 'לדוגמה: בלי מלח בצ׳יפס…';

  @override
  String get kioskOptional => 'רשות';

  @override
  String get kioskRequired => 'חובה';

  @override
  String get kioskChooseOne => 'בחרו 1';

  @override
  String kioskUpTo(int count) {
    return 'עד $count';
  }

  @override
  String get kioskIncluded => 'כלול';

  @override
  String get kioskAddToOrder => 'הוסיפו להזמנה';

  @override
  String get kioskUpdateItem => 'עדכון פריט';

  @override
  String kioskPleaseChoose(String groups) {
    return 'נא לבחור: $groups';
  }

  @override
  String get kioskRemove => 'הסרה';

  @override
  String get kioskForCounterCall => 'לקריאה בקופה';

  @override
  String get kioskNameOptional => 'שם (לא חובה)';

  @override
  String get kioskPhoneOptional => 'טלפון (לא חובה)';

  @override
  String get kioskChange => 'שינוי';

  @override
  String get kioskTotal => 'סה\"כ';

  @override
  String get kioskPlaceOrder => 'שליחת הזמנה';

  @override
  String get kioskCartEmpty => 'הסל ריק';

  @override
  String get kioskCartEmptySub => 'הדברים הטובים במרחק נגיעה';

  @override
  String get kioskBrowseMenu => 'לתפריט';

  @override
  String get kioskOrderSent => 'ההזמנה נשלחה!';

  @override
  String get kioskShowNumber => 'הציגו את המספר בקופה — שם משלמים.';

  @override
  String get kioskOrderNumberLabel => 'מספר הזמנה';

  @override
  String get kioskServiceLabel => 'שירות';

  @override
  String get kioskNameLabel => 'שם';

  @override
  String get kioskPayAtCounter => 'לתשלום בקופה';

  @override
  String get kioskPrintingSlip => 'מדפיסים לכם פתק';

  @override
  String get kioskNewOrder => 'הזמנה חדשה';

  @override
  String kioskBackToStartIn(int seconds) {
    return 'חוזרים להתחלה בעוד $seconds שניות';
  }

  @override
  String get kioskStillThere => 'עדיין כאן?';

  @override
  String get kioskStillThereSub => 'ההזמנה תתאפס כדי שהאורח הבא יתחיל נקי.';

  @override
  String get kioskImStillHere => 'אני כאן';

  @override
  String get kioskStartOver => 'להתחיל מחדש';

  @override
  String get kioskAddedToOrder => 'נוסף להזמנה';

  @override
  String get kioskZoneHall => 'האולם';

  @override
  String get kioskZonePatio => 'המרפסת';

  @override
  String get kioskZoneBar => 'הבר';

  @override
  String get kioskMadeFresh => 'על האש · טרי בשבילכם';

  @override
  String kioskPoweredBy(String device) {
    return 'מופעל על ידי RestoFlow · עמדה $device';
  }

  @override
  String get kioskGroupWeight => 'בחרו משקל קציצה';

  @override
  String get kioskGroupSide => 'בחרו תוספת';

  @override
  String get kioskGroupDrink => 'בחרו שתייה';

  @override
  String get kioskGroupSauce => 'בחרו רוטב';

  @override
  String get kioskGroupAddons => 'תוספות';

  @override
  String get kioskGroupRemovals => 'להוריד משהו?';

  @override
  String get kioskStaffAccess => 'כניסת צוות';

  @override
  String get kioskStaffPinPrompt => 'הזינו קוד עובד — אותו קוד כמו בקופה.';

  @override
  String get kioskStaffChooseName => 'בחרו את שמכם';

  @override
  String get kioskStaffPinWrong => 'קוד PIN שגוי — נסו שוב.';

  @override
  String get kioskStaffPinNetwork => 'בעיית תקשורת — נסו שוב.';

  @override
  String get kioskAppearanceSection => 'מראה';

  @override
  String get kioskAppearanceIdentity => 'זהות המסעדה';

  @override
  String get kioskAppearanceDisplayName => 'שם המסעדה';

  @override
  String get kioskAppearanceLogo => 'לוגו';

  @override
  String get kioskAppearanceChooseLogo => 'בחירת לוגו';

  @override
  String get kioskAppearanceRemoveLogo => 'הסרת הלוגו';

  @override
  String get kioskAppearanceLogoInvalid =>
      'אי אפשר להשתמש בקובץ הזה — PNG, JPEG או WebP עד 256KB.';

  @override
  String get kioskAppearanceLogoUnsupported =>
      'העלאת לוגו אינה זמינה במכשיר הזה.';

  @override
  String get kioskAppearanceWordmark => 'לוגוטייפ';

  @override
  String get kioskAppearanceTitlePrimary => 'טקסט ראשי';

  @override
  String get kioskAppearanceTitleAccent => 'טקסט מודגש (רשות)';

  @override
  String get kioskAppearancePrimaryColor => 'צבע שם המסעדה (ראשי)';

  @override
  String get kioskAppearanceAccentColor => 'צבע שם המסעדה (הדגשה)';

  @override
  String get kioskAppearanceHexHint => 'HEX #RRGGBB';

  @override
  String get kioskAppearanceTagline => 'סלוגן';

  @override
  String get kioskAppearanceMenuCopy => 'טקסטים בתפריט';

  @override
  String get kioskAppearanceMenuHeadline => 'כותרת התפריט';

  @override
  String get kioskAppearanceMenuSubtitle => 'כותרת משנה';

  @override
  String get kioskAppearanceMedia => 'מדיית מסך המתנה';

  @override
  String get kioskAppearanceInterval => 'משך הצגת תמונה';

  @override
  String get kioskAppearanceLiveMenuPhotos => 'תמונות תפריט חיות';

  @override
  String get kioskAppearanceReset => 'איפוס המראה';

  @override
  String get kioskAppearanceResetConfirm =>
      'לאפס את כל הגדרות המראה במכשיר הזה?';

  @override
  String get kioskAppearanceSave => 'שמירת שינויים';

  @override
  String get kioskAppearanceSaved => 'המראה נשמר';

  @override
  String get kioskAppearancePreview => 'תצוגה מקדימה';

  @override
  String get kioskKitchenRole => 'כרטיס מטבח';

  @override
  String get kioskKitchenGovernedByKds =>
      'הדפסת המטבח בסניף זה מנוהלת דרך מסך המטבח. העמדה מדפיסה קבלות לקוח בלבד.';

  @override
  String get kioskKitchenAutoPrint => 'הדפסת כרטיס מטבח אוטומטית';

  @override
  String get kioskKitchenAutoPrintHint =>
      'לאחר הזמנה מוצלחת, העמדה מדפיסה את כרטיס המטבח במדפסת המטבח שלה.';

  @override
  String get kioskKitchenCopyCustomer => 'שימוש במדפסת הלקוחות';

  @override
  String get kioskKitchenTest => 'בדיקת כרטיס מטבח';

  @override
  String get kioskKitchenLastFailed => 'כרטיס המטבח האחרון לא הודפס.';

  @override
  String get kioskKitchenLastPossibly =>
      'ייתכן שכרטיס המטבח האחרון הודפס — לא יודפס שוב אוטומטית.';

  @override
  String get kioskKitchenRetry => 'ניסיון חוזר';

  @override
  String get kioskIdleDelaySection => 'זמן חוסר פעילות';

  @override
  String get kioskIdleDelayHelper =>
      'זמן השקט לפני שמופיעה ההתראה «עדיין כאן?». חלון ההתראה (10 שניות) אינו משתנה.';

  @override
  String get kioskIdleDelayLegacyNote =>
      'לא הוגדר — המכשיר שומר על התזמון המקורי (התראה אחרי 50 שניות).';

  @override
  String get kioskUiThemeSection => 'צבעי ממשק המכשיר';

  @override
  String get kioskUiThemeExplainer =>
      'בחרו את שני הצבעים המרכזיים לממשק המכשיר הזה בלבד.';

  @override
  String get kioskUiThemeVsWordmarkNote => 'נפרד מצבעי שם/זהות המסעדה שלמעלה.';

  @override
  String get kioskUiThemePresetNavy => 'כחול כהה + כתום';

  @override
  String get kioskUiThemePresetForest => 'ירוק יער + כתום';

  @override
  String get kioskUiThemePresetAubergine => 'חציל + לבנה';

  @override
  String get kioskUiThemePresetCharcoal => 'פחם + זהב';

  @override
  String get kioskUiThemeCustom => 'מותאם אישית';

  @override
  String get kioskUiThemeCustomTitle => 'צבעי מכשיר מותאמים';

  @override
  String get kioskUiThemePrimaryLabel => 'צבע מבני (ראשי)';

  @override
  String get kioskUiThemeActionLabel => 'צבע הכפתורים (פעולה)';

  @override
  String get kioskUiThemeApply => 'החלה';

  @override
  String get kioskUiThemeReset => 'שחזור צבעי ברירת המחדל';

  @override
  String get kioskUiThemePreviewAction => 'כפתור ראשי';

  @override
  String get kioskUiThemePreviewBody => 'טקסט קריא';

  @override
  String get kioskUiThemeAdvancedHex => 'HEX מתקדם';

  @override
  String get kioskPrintFailedNotice =>
      'לא ניתן היה להדפיס את הקבלה — בקשו עותק מהקופאי.';

  @override
  String get kioskPrinterSection => 'מדפסת קבלות';

  @override
  String get kioskPrinterWebUnavailable =>
      'הגדרת המדפסת זמינה רק במכשיר הקיוסק המותקן. ההזמנות אינן מושפעות.';

  @override
  String get kioskPrinterAutoPrint => 'הדפסת קבלה אוטומטית';

  @override
  String get kioskPrinterAutoPrintHint =>
      'קבלת הלקוח מודפסת אוטומטית כשההזמנה מתקבלת.';

  @override
  String get kioskPrinterTransportWifi => 'Wi-Fi';

  @override
  String get kioskPrinterTransportBluetooth => 'Bluetooth';

  @override
  String get kioskPrinterHost => 'כתובת המדפסת (IP)';

  @override
  String get kioskPrinterPort => 'פורט';

  @override
  String get kioskPrinterInvalidHost => 'הזינו כתובת מדפסת תקינה.';

  @override
  String get kioskPrinterInvalidPort => 'הזינו פורט תקין (1–65535).';

  @override
  String get kioskPrinterSave => 'שמירת מדפסת';

  @override
  String get kioskPrinterSaved => 'המדפסת נשמרה';

  @override
  String get kioskPrinterTest => 'הדפסת ניסיון';

  @override
  String get kioskPrinterTestOk => 'הניסיון נשלח למדפסת.';

  @override
  String get kioskPrinterTestFailed => 'הדפסת הניסיון נכשלה — בדקו את המדפסת.';

  @override
  String get kioskPrinterBtPick => 'בחירת מדפסת מצומדת';

  @override
  String get kioskPrinterBtNone =>
      'אין מכשירי Bluetooth מצומדים — צמדו את המדפסת בהגדרות אנדרואיד תחילה.';

  @override
  String get kioskPrinterBtUnavailable =>
      'Bluetooth אינו זמין או שההרשאה נדחתה.';

  @override
  String get kioskPrinterNotConfigured => 'עדיין לא הוגדרה מדפסת.';

  @override
  String get kioskPrinterCurrentSaved => 'המדפסת השמורה:';

  @override
  String get kioskAttractModeMenuPhotos => 'תמונות נבחרות מהתפריט';

  @override
  String get kioskAttractModeImage => 'תמונה חיצונית';

  @override
  String get kioskAttractModeVideo => 'סרטון חיצוני';

  @override
  String get kioskFeaturedPickAction => 'בחירת תמונות';

  @override
  String get kioskFeaturedAutoNote =>
      'אין בחירה עדיין — מוצגות תמונות תפריט אוטומטיות.';

  @override
  String get kioskFeaturedClear => 'ניקוי הבחירה';

  @override
  String get kioskFeaturedTitle => 'תמונות תפריט מובילות';

  @override
  String get kioskFeaturedHint => 'בחרו 4–8 מוצרים שיובילו את מסך הפתיחה.';

  @override
  String get kioskFeaturedFewWarning =>
      'בתפריט פחות מ-4 תמונות שמישות — אפשר לבחור את כל השמישות.';

  @override
  String get kioskFeaturedSearch => 'חיפוש מוצר';

  @override
  String get kioskFeaturedAllCategories => 'הכל';

  @override
  String get kioskFeaturedNoPhoto => 'ללא תמונה';

  @override
  String get kioskFeaturedStale => 'לא זמין';

  @override
  String get kioskAttractChooseImage => 'בחירת תמונה';

  @override
  String get kioskAttractChooseVideo => 'בחירת סרטון';

  @override
  String get kioskAttractMediaWebOnlyNote =>
      'מדיה מותאמת נקבעת רק במכשיר הקיוסק המותקן.';

  @override
  String get kioskAttractMediaSet => 'המדיה שמורה במכשיר הזה';

  @override
  String get kioskAttractMediaTooLarge => 'הקובץ גדול מדי לקיוסק.';

  @override
  String get kioskAttractMediaTooLong => 'הסרטון ארוך מדי — עד 3 דקות.';

  @override
  String get kioskAttractMediaInvalid => 'אי אפשר להשתמש בקובץ הזה בקיוסק.';

  @override
  String get kioskCancel => 'ביטול';

  @override
  String get kioskSettingsTitle => 'הגדרות עמדת הקיוסק';

  @override
  String get kioskSettingsSignedIn => 'מחוברים באמצעות קוד עובד';

  @override
  String get kioskSettingsExit => 'יציאה לקיוסק';

  @override
  String get kioskSettingsOrdering => 'הזמנות';

  @override
  String get kioskSettingsTableToggleTitle => 'בחירת שולחן לישיבה במקום';

  @override
  String get kioskSettingsTableToggleSub =>
      'פעיל: הלקוח חייב לבחור שולחן פנוי. כבוי: ממשיכים בלי שולחן.';

  @override
  String get kioskSettingsIdleSection => 'מסך המתנה ופרסום';

  @override
  String get kioskSettingsIdleAfter => 'חזרה למסך הפתיחה אחרי';

  @override
  String get kioskSettingsAttractContent => 'תוכן מסך הפתיחה';

  @override
  String get kioskSettingsAttractPhotos => 'מצגת תמונות';

  @override
  String get kioskSettingsAttractPromo => 'תמונת פרסום';

  @override
  String get kioskSettingsAttractVideo => 'קובץ וידאו';

  @override
  String get kioskSettingsPromoDropHint =>
      'גררו לכאן מודעה או פוסטר עונתי — הוא יהפוך למסך ההמתנה. מומלץ 1080×1920 לאורך.';

  @override
  String get kioskSettingsVideoHint =>
      'העלו קובץ .mp4 בלוח הבקרה של RestoFlow ← מכשירים. הוא יסתנכרן לעמדה ויתנגן בהמתנה, ללא קול.';

  @override
  String get kioskSettingsPrinterSection => 'מדפסת פתקים';

  @override
  String get kioskSettingsPrintTest => 'הדפסת פתק ניסיון';

  @override
  String get kioskSettingsPrinterNote =>
      'אותו מודל קישור מדפסות כמו בעמדות הקופה — הקיוסק מדפיס את פתק הלקוח; כרטיסי מטבח ממשיכים לפי תחנה.';

  @override
  String get kioskPrinterBound => 'מקושרת';

  @override
  String get kioskPrinterAvailable => 'זמינה';

  @override
  String get kioskPrinterOffline => 'מנותקת';

  @override
  String get kioskSettingsDefaultLang => 'שפת ברירת מחדל למסך הפתיחה';

  @override
  String get kioskSettingsDefaultLangNote =>
      'הלקוחות יכולים להחליף שפה בכל רגע; העמדה חוזרת לשפה זו באיפוס.';

  @override
  String get kioskSettingsDiagnostics => 'אבחון';

  @override
  String get kioskSettingsDevice => 'מכשיר';

  @override
  String get kioskSettingsPairing => 'צימוד';

  @override
  String get kioskSettingsPairingActive => 'פעיל ✓';

  @override
  String get kioskSettingsMenuSync => 'סנכרון תפריט';

  @override
  String get kioskSettingsOrdersToday => 'הזמנות היום';

  @override
  String get kioskSettingsResync => 'סנכרון תפריט מחדש';

  @override
  String get kioskSettingsAccessNote =>
      'הגישה מוגנת בקוד עובד — כל תפקיד מורשה (קופאי, מנהל, טבח). אין סיסמת קיוסק נפרדת.';

  @override
  String kioskSecondsShort(int seconds) {
    return '$seconds שנ׳';
  }

  @override
  String kioskTestSlipSent(String printer) {
    return 'פתק ניסיון נשלח אל $printer';
  }

  @override
  String get kioskResyncDone => 'התפריט סונכרן מחדש · נתוני דמו';

  @override
  String get kioskActivationTitle => 'הפעלת העמדה';

  @override
  String get kioskActivationSubtitle =>
      'הזינו את קוד הרישום מלוח הבקרה כדי לצמד את המכשיר.';

  @override
  String get kioskActivationCodeLabel => 'קוד רישום';

  @override
  String get kioskActivationSubmit => 'הפעלה';

  @override
  String get kioskActivationErrorInvalid => 'הקוד אינו תקין. בדקו ונסו שוב.';

  @override
  String get kioskActivationErrorExpired =>
      'תוקף הקוד פג. הנפיקו קוד חדש מלוח הבקרה.';

  @override
  String get kioskActivationErrorWrongType => 'הקוד שייך לסוג מכשיר אחר.';

  @override
  String get kioskActivationErrorLocked =>
      'יותר מדי ניסיונות. המתינו מעט ונסו שוב.';

  @override
  String get kioskActivationErrorNetwork => 'אין חיבור. בדקו את הרשת ונסו שוב.';

  @override
  String get kioskActivationErrorUnknown => 'ההפעלה נכשלה. נסו שוב.';

  @override
  String get kioskBootRestoring => 'בודק את העמדה…';

  @override
  String get kioskReconnectTitle => 'מתחבר מחדש…';

  @override
  String get kioskReconnectBody => 'העמדה איבדה את החיבור לרשת. נחזור בקרוב.';

  @override
  String get kioskRetry => 'נסו שוב';

  @override
  String get kioskMenuLoadingTitle => 'טוען את התפריט…';

  @override
  String get kioskMenuEmptyTitle => 'התפריט ריק';

  @override
  String get kioskMenuEmptyBody => 'נא להזמין בדלפק.';

  @override
  String get kioskMenuUnavailableTitle => 'התפריט אינו זמין';

  @override
  String get kioskMenuUnavailableBody => 'נא להזמין בדלפק.';

  @override
  String get kioskTablesLoadingTitle => 'בודק את השולחנות…';

  @override
  String get kioskTablesUnavailableTitle => 'השולחנות אינם זמינים';

  @override
  String get kioskTablesUnavailableBody => 'לא ניתן לבדוק את השולחנות כרגע.';

  @override
  String get kioskTablesRefresh => 'רענון';

  @override
  String get kioskItemUnavailableBadge => 'אזל מהמלאי';

  @override
  String get kioskCartStaleTitle => 'התפריט השתנה';

  @override
  String get kioskCartStaleBody =>
      'חלק מהפריטים או המחירים בהזמנה עודכנו. בדקו את ההזמנה כדי להמשיך.';

  @override
  String get kioskCartStaleRefresh => 'עדכון ההזמנה';

  @override
  String get kioskSubtotal => 'סכום ביניים';

  @override
  String get kioskTax => 'מס';

  @override
  String get kioskTaxIncludedNote => 'כולל מס';

  @override
  String get kioskSubmitUnconfirmedTitle => 'לא ניתן לאשר את ההזמנה';

  @override
  String get kioskSubmitUnconfirmedBody =>
      'החיבור נקטע לפני שקיבלנו תשובה. ייתכן שההזמנה התקבלה — הקישו על “נסו שוב” לבדיקה בטוחה (היא לעולם לא תישלח פעמיים).';

  @override
  String get kioskSubmitRetry => 'נסו שוב';

  @override
  String get kioskSubmitFailed =>
      'לא ניתן לשלוח את ההזמנה. נסו שוב או פנו לקופה.';

  @override
  String get kioskTaxUnavailableMsg =>
      'לא ניתן לאמת את המחירים כרגע — נסו שוב בעוד רגע.';

  @override
  String get kioskPhoneInvalidMsg =>
      'לא ניתן להשתמש במספר הטלפון — בדקו אותו ונסו שוב.';

  @override
  String get kioskTotalUpdating => 'מעדכן את הסכום…';

  @override
  String get kioskTotalUpdated => 'הסכום עודכן';

  @override
  String get kioskTotalUpdatedBody => 'אנא בדקו את הסכום החדש ואשרו שוב.';

  @override
  String get kioskOrderingUnavailable =>
      'לא ניתן להזמין מהעמדה כרגע — נא להזמין בדלפק.';

  @override
  String get kioskTableNoLongerAvailable =>
      'השולחן נתפס הרגע — נא לבחור שולחן אחר.';
}
