import 'package:flutter/widgets.dart';

/// Ticket-owned AR/HE/EN copy, independent of payment-owned shared catalogs.
class SeoConsentCopy {
  SeoConsentCopy(String languageCode)
    : _language = switch (languageCode) {
        'ar' => 0,
        'he' => 1,
        _ => 2,
      };

  factory SeoConsentCopy.of(BuildContext context) =>
      SeoConsentCopy(Localizations.localeOf(context).languageCode);

  final int _language;
  String _text(String ar, String he, String en) => [ar, he, en][_language];

  String get title => _text(
    'الظهور في محركات البحث',
    'הופעה במנועי חיפוש',
    'Search engine visibility',
  );
  String get label => _text(
    'السماح بظهور منيو المطعم في محركات البحث',
    'לאפשר לתפריט המסעדה להופיע במנועי חיפוש',
    'Allow the restaurant menu to appear in search engines',
  );
  String get scope => _text(
    'موافقة اختيارية لهذا المطعم بجميع فروعه. لا يؤدي الإغلاق المؤقت إلى سحب الموافقة.',
    'הסכמה לבחירתכם עבור המסעדה בכל סניפיה. סגירה זמנית אינה מבטלת את ההסכמה.',
    'Optional consent for this restaurant across all branches. Temporarily closing the restaurant does not withdraw consent.',
  );
  String get notOperational => _text(
    'لإصدار مستقبلي — الفهرسة غير مفعّلة حاليًا. تشغيل هذا الخيار يحفظ موافقتك فقط، ولا يفعّل الظهور في محركات البحث الآن.',
    'מיועד לגרסה עתידית — האינדוקס עדיין אינו פעיל. הפעלת האפשרות שומרת את הסכמתכם בלבד ואינה מפעילה כעת הופעה במנועי חיפוש.',
    'For a future release — indexing is not active yet. Turning this on only records your consent; it does not activate search engine indexing now.',
  );
  String get help => _text(
    'تقرر Google ومحركات البحث الأخرى ما إذا كانت ستعرض الصفحات ومتى. الموافقة لا تضمن الظهور.',
    'Google ומנועי חיפוש אחרים מחליטים אם ומתי להציג דפים. הסכמה אינה מבטיחה הופעה.',
    'Google and other search engines decide whether and when to display pages. Consent does not guarantee visibility.',
  );
  String get withdrawal => _text(
    'إيقاف الخيار وحفظه يسحب الموافقة لأي أهلية فهرسة مستقبلية. لا يكون المطعم غير المنشور أو الموقوف أو المحذوف مؤهلًا للفهرسة.',
    'כיבוי האפשרות ושמירה מבטלים את ההסכמה לזכאות עתידית לאינדוקס. מסעדה שלא פורסמה, הושעתה או נמחקה אינה זכאית לאינדוקס.',
    'Turning this off and saving withdraws consent for future indexing eligibility. Unpublished, suspended or deleted restaurants are never eligible.',
  );
  String get independent => _text(
    'لا يؤثر هذا الإعداد على طلبات الموقع أو التنبيهات أو الطباعة.',
    'ההגדרה אינה משפיעה על הזמנות מהאתר, התראות או הדפסה.',
    'This setting does not affect website orders, alerts or printing.',
  );
  String get loading => _text(
    'جارٍ قراءة موافقة المطعم…',
    'קורא את הסכמת המסעדה…',
    'Reading restaurant consent…',
  );
  String get save => _text('حفظ الموافقة', 'שמירת ההסכמה', 'Save consent');
  String get saving => _text('جارٍ الحفظ…', 'שומר…', 'Saving…');
  String get dirty =>
      _text('تغييرات غير محفوظة', 'שינויים שלא נשמרו', 'Unsaved changes');
  String get saved => _text(
    'تم تأكيد الحفظ. تُعرض الموافقة الحالية من الخادم. الفهرسة لا تزال غير مفعّلة.',
    'השמירה אושרה. מוצגת ההסכמה הנוכחית מהשרת. האינדוקס עדיין אינו פעיל.',
    'The save was confirmed. Current server consent is shown. Indexing is still inactive.',
  );
  String get denied => _text(
    'يمكن لمالك المؤسسة أو مالك المطعم المخوّل فقط تغيير هذه الموافقة.',
    'רק בעל הארגון או בעל המסעדה המורשה יכול לשנות את ההסכמה.',
    'Only an authorized organization owner or restaurant owner can change this consent.',
  );
  String get notFound => _text(
    'المطعم غير متاح ضمن صلاحياتك الحالية.',
    'המסעדה אינה זמינה בהרשאות הנוכחיות שלכם.',
    'This restaurant is unavailable within your current permissions.',
  );
  String get unavailable => _text(
    'تعذّرت قراءة الموافقة. لا يمكن الحفظ قبل قراءة ناجحة.',
    'לא ניתן לקרוא את ההסכמה. נדרשת קריאה מוצלחת לפני שמירה.',
    'Consent could not be read. A successful read is required before saving.',
  );
  String get savedReadUnavailable => _text(
    'تم تأكيد الحفظ، لكن تعذّرت قراءة الموافقة الحالية. أعد القراءة قبل أي حفظ جديد.',
    'השמירה אושרה, אך לא ניתן לקרוא את ההסכמה הנוכחית. יש לקרוא שוב לפני שמירה חדשה.',
    'The save was confirmed, but current consent could not be read. Refresh before any new save.',
  );
  String get conflict => _text(
    'غيّر مالك آخر الموافقة. لم نكتب فوقها. تجاهل المسودة واقرأ الحالة الأحدث قبل تعديل جديد.',
    'בעלים אחר שינה את ההסכמה והשינוי לא נדרס. יש לבטל את הטיוטה ולקרוא את המצב העדכני לפני עריכה נוספת.',
    'Another owner changed the consent. Their change was not overwritten. Discard this draft and read the latest state before editing again.',
  );
  String get requestConflict => _text(
    'تعارض معرّف الحفظ مع طلب مختلف. اقرأ الموافقة الحالية قبل المتابعة.',
    'מזהה השמירה מתנגש עם בקשה אחרת. יש לקרוא את ההסכמה הנוכחית לפני המשך.',
    'The save identity conflicts with a different request. Read current consent before continuing.',
  );
  String get invalid => _text(
    'رُفض طلب الحفظ. اقرأ الموافقة الحالية قبل المتابعة.',
    'בקשת השמירה נדחתה. יש לקרוא את ההסכמה הנוכחית לפני המשך.',
    'The save request was refused. Read current consent before continuing.',
  );
  String get uncertain => _text(
    'نتيجة الحفظ غير مؤكدة. تحقّق من النتيجة قبل أي محاولة أخرى. لم نكرر الحفظ تلقائيًا.',
    'תוצאת השמירה אינה ודאית. יש לבדוק אותה לפני ניסיון נוסף. השמירה לא נשלחה שוב אוטומטית.',
    'The save outcome is uncertain. Check the outcome before any further attempt. The save was not repeated automatically.',
  );
  String get notRecorded => _text(
    'لم يُسجّل الحفظ عند التحقق، لكن الطلب قد يصل متأخرًا. تحقّق مجددًا أو أعد إرسال الحفظ نفسه فقط.',
    'השמירה לא נרשמה בעת הבדיקה, אך הבקשה עשויה להגיע באיחור. יש לבדוק שוב או לשלוח מחדש רק את אותה שמירה.',
    'The save was not recorded when checked, but the request may still arrive late. Check again or resend only the same save.',
  );
  String get checkSave => _text(
    'التحقق من نتيجة الحفظ',
    'בדיקת תוצאת השמירה',
    'Check save outcome',
  );
  String get retrySame => _text(
    'إعادة إرسال الحفظ نفسه',
    'שליחת אותה שמירה שוב',
    'Resend the same save',
  );
  String get reload => _text(
    'تجاهل المسودة وتحديث الموافقة',
    'ביטול הטיוטה ורענון ההסכמה',
    'Discard draft and refresh consent',
  );
  String get refresh =>
      _text('تحديث الموافقة', 'רענון ההסכמה', 'Refresh consent');
}
