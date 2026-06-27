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
  String get dashboardShiftStatus => 'משמרת';

  @override
  String get dashboardSalesByBranch => 'מכירות לפי סניף';

  @override
  String get dashboardTopItems => 'פריטים מובילים';

  @override
  String get dashboardDemoNotice => 'נתוני הדגמה — לא משרת חי.';

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
  String get menuImageDeferredTitle => 'העלאת תמונות בקרוב';

  @override
  String get menuImageDeferredBody =>
      'הצגה והעלאה של תמונות פריטים דורשות רשומת תמונה בצד השרת (המשך מתוכנן). נתיב ההעלאה והאימות כבר מוכנים.';

  @override
  String get menuErrorRequired => 'חובה';

  @override
  String get menuErrorAmount => 'הזן סכום תקין';

  @override
  String get menuErrorNegativePrice => 'לא יכול להיות שלילי';

  @override
  String get menuErrorCurrency => 'השתמש בקוד בן 3 אותיות (למשל USD)';

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
  String get adminErrCurrency => 'השתמש בקוד בן 3 אותיות (למשל USD)';

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
}
