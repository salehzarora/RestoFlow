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
  String get posOrderSubmittedTitle => 'ההזמנה נשלחה';

  @override
  String get posOrderNumberLabel => 'מספר הזמנה';

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
  String get printStatusNotConfigured => 'לא הוגדרה מדפסת';

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
  String get dashboardNavPrinters => 'מדפסות';

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
  String dashboardDeltaVsYesterday(int percent) {
    return '$percent% לעומת אתמול';
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
  String get printersTitle => 'מדפסות';

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
  String get printersTestPrint => 'הדפסת ניסיון';

  @override
  String get printersTestPrintUnavailable =>
      'הדפסת ניסיון דורשת את מתאם ההדפסה או הגשר — לא זמינה בגרסת אינטרנט זו.';

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
  String get tablesSetStatus => 'הגדרת סטטוס';

  @override
  String get tablesSaved => 'השולחן נשמר';

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
}
