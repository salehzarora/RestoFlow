import 'package:restoflow_l10n/restoflow_l10n.dart';

/// Local organization/help copy; no server or shared localization changes.
String storefrontSettingsCopy(AppLocalizations l10n, String key) {
  const labels = <String, List<String>>{
    'details': ['Store details', 'تفاصيل المتجر', 'פרטי החנות'],
    'legacyText': [
      'Legacy welcome text',
      'نص الترحيب للتوافق',
      'טקסט פתיחה לתאימות',
    ],
    'legacyTextHelp': [
      'For older clients. Prefer Storefront content when available. Each editor keeps its own Save action; folding a section does not save.',
      'للعملاء الأقدم. استخدم محتوى واجهة المتجر عند توفره. لكل محرر زر حفظ مستقل؛ طي القسم لا يحفظ.',
      'ללקוחות ישנים. מומלץ להשתמש בתוכן חלון הראווה כשהוא זמין. לכל עורך שמירה נפרדת; קיפול אינו שומר.',
    ],
    'appearanceHelp': [
      'Colors affect the current design. Theme affects search and order pages; card layout affects search results. Motion respects the visitor’s reduced-motion preference.',
      'الألوان تؤثر على التصميم الحالي. السمة تُستخدم في البحث وصفحات الطلب؛ تخطيط البطاقات يؤثر على نتائج البحث. الحركة تراعي تفضيل الزائر لتقليلها.',
      'הצבעים משפיעים על העיצוב הנוכחי. ערכת הנושא משמשת בחיפוש ובדפי הזמנה; פריסת הכרטיסים משפיעה על תוצאות החיפוש. התנועה מכבדת העדפה לתנועה מופחתת.',
    ],
    'availability': [
      'Availability and opening hours',
      'التوفر وساعات العمل',
      'זמינות ושעות פתיחה',
    ],
  };
  final values = labels[key]!;
  return values[switch (l10n.localeName.split('_').first) {
    'ar' => 1,
    'he' => 2,
    _ => 0,
  }];
}
