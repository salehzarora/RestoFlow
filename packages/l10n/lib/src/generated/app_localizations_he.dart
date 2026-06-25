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
}
