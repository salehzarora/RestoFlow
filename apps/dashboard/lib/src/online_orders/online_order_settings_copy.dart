import 'package:flutter/widgets.dart';

/// Workstream-owned AR/HE/EN copy. Kept outside the shared payment-owned ARBs;
/// this module can move to the shared catalog in its coordinated integration.
class OnlineOrderSettingsCopy {
  OnlineOrderSettingsCopy(String languageCode)
    : _language = switch (languageCode) {
        'ar' => 0,
        'he' => 1,
        _ => 2,
      };

  factory OnlineOrderSettingsCopy.of(BuildContext context) =>
      OnlineOrderSettingsCopy(Localizations.localeOf(context).languageCode);

  final int _language;
  String _text(String ar, String he, String en) => [ar, he, en][_language];

  String get title => _text('طلبات الموقع', 'הזמנות מהאתר', 'Online orders');
  String get scope => _text(
    'للفرع المحدد فقط. نشر الموقع وPickup وساعات العمل والإيقاف المؤقت لها إعداداتها المستقلة.',
    'לסניף הנבחר בלבד. פרסום האתר, איסוף עצמי, שעות פתיחה והשהיה זמנית מנוהלים בנפרד.',
    'For the selected branch only. Website publication, Pickup, opening hours and temporary pause are managed separately.',
  );
  String get ordering => _text(
    'استقبال الطلبات من الموقع',
    'קבלת הזמנות מהאתר',
    'Website order intake',
  );
  String get orderingHelp => _text(
    'يهيّئ الفرع لاستقبال طلبات موقع جديدة، مع استمرار شروط نشر الموقع وقناة الاستقبال وحالة الفرع وساعات العمل. لا يغيّر الطلبات القائمة.',
    'מגדיר קבלת הזמנות אתר חדשות בסניף, בכפוף לפרסום האתר, לערוץ קבלת ההזמנות, לזמינות הסניף ולשעות הפתיחה. אינו משנה הזמנות קיימות.',
    'Configures new website intake for this branch, subject to website publication, the intake channel, branch availability and opening hours. Existing requests are unchanged.',
  );
  String get alerts => _text(
    'تنبيهات طلبات الموقع للفرع',
    'התראות הזמנות מהאתר לסניף',
    'Branch online-order alerts',
  );
  String get alertsHelp => _text(
    'إعداد للفرع مستقل عن مفتاح المشغّل العام وموافقة كل جهاز وصلاحية التنبيهات. إيقافه قد يلغي تفويض التنبيهات وتفعيلها المحفوظ محليًا على الجهاز. تشغيله لاحقًا لا يعيد تفعيل الأجهزة تلقائيًا؛ قد يحتاج الموظف المخوّل إلى تفعيل التنبيهات بالطريقة المعتادة داخل POS المفتوح مجددًا.',
    'הגדרת סניף נפרדת מהמתג הכללי, מהסכמת כל מכשיר ומתוקף הרשאת ההתראות. כיבוי עשוי להסיר את ההרשאה ואת ההסכמה המקומית במכשיר. הפעלה מחדש אינה מפעילה מכשירים אוטומטית; ייתכן שעובד מורשה יצטרך להפעיל שוב התראות בדרך הרגילה כאשר POS פתוח.',
    'A branch setting, independent of the global operator switch, device consent and notification-authority expiry. Turning it OFF can clear a device’s local alert authorization and opt-in. Turning it ON does not re-enable devices automatically; authorized staff may need to enable alerts normally in foreground POS again.',
  );
  String get printing => _text(
    'أهلية طباعة طلبات الموقع الجديدة',
    'זכאות להדפסת הזמנות אתר חדשות',
    'New web-order printing eligibility',
  );
  String get printingHelp => _text(
    'إعداد أهلية فقط، وليس تأكيدًا لجاهزية الطابعة أو السماح التشغيلي. لا يطبع طلبًا قديمًا أو يعيد طباعته، ولا يغيّر الحجوزات التاريخية.',
    'הגדרת זכאות בלבד, לא אישור למוכנות מדפסת או להיתר תפעולי. אינו מדפיס מחדש הזמנות קודמות ואינו משנה חסימות היסטוריות.',
    'Configured eligibility only, not confirmation of printer or containment readiness. Does not print or replay old requests or change historical holds.',
  );
  String get loading => _text(
    'جارٍ قراءة إعدادات الفرع…',
    'קורא את הגדרות הסניף…',
    'Reading branch settings…',
  );
  String get saving => _text('جارٍ الحفظ…', 'שומר…', 'Saving…');
  String get save =>
      _text('حفظ تغييرات الفرع', 'שמירת שינויי הסניף', 'Save branch changes');
  String get dirty =>
      _text('تغييرات غير محفوظة', 'שינויים שלא נשמרו', 'Unsaved changes');
  String get saved => _text(
    'تم تأكيد الحفظ. تُعرض الحالة الحالية من الخادم.',
    'השינוי אושר. מוצג המצב הנוכחי מהשרת.',
    'The save was confirmed. Current server settings are shown.',
  );
  String get unavailable => _text(
    'تعذّرت قراءة إعدادات الفرع. لا يمكن الحفظ قبل قراءة ناجحة.',
    'לא ניתן לקרוא את הגדרות הסניף. נדרשת קריאה מוצלחת לפני שמירה.',
    'Branch settings could not be read. A successful read is required before saving.',
  );
  String get savedReadUnavailable => _text(
    'تم تأكيد الحفظ، لكن تعذّرت قراءة الحالة الحالية. أعد القراءة؛ لا ترسل حفظًا جديدًا.',
    'השמירה אושרה, אך לא ניתן לקרוא את המצב הנוכחי. יש לקרוא שוב, ללא שמירה חדשה.',
    'The save was confirmed, but current settings could not be read. Read again; do not submit another save.',
  );
  String get denied => _text(
    'هذه الإعدادات متاحة لمدير أو مالك مخوّل بهذا الفرع فقط.',
    'הגדרות אלו זמינות רק למנהל או לבעלים המורשה בסניף זה.',
    'These settings require manager or owner authority for this branch.',
  );
  String get notFound => _text(
    'الفرع غير متاح ضمن صلاحياتك الحالية.',
    'הסניף אינו זמין בהרשאות הנוכחיות שלך.',
    'This branch is unavailable within your current permissions.',
  );
  String get conflict => _text(
    'تغيّرت الإعدادات لدى مستخدم آخر. لم نكتب فوقها. تجاهل المسودة واقرأ الحالة الأحدث قبل تعديل جديد.',
    'ההגדרות השתנו אצל משתמש אחר ולא נדרסו. יש לבטל את הטיוטה ולקרוא את המצב העדכני לפני עריכה נוספת.',
    'Another user changed these settings. Their changes were not overwritten. Discard this draft and read the latest state before editing again.',
  );
  String get requestConflict => _text(
    'تعارض معرّف الحفظ مع نية مختلفة. توقّف الحفظ؛ اقرأ الحالة الحالية قبل متابعة جديدة.',
    'מזהה השמירה מתנגש עם שינוי אחר. השמירה נעצרה; יש לקרוא את המצב הנוכחי לפני המשך.',
    'The save identity conflicts with a different intent. Saving stopped; read current settings before starting again.',
  );
  String get invalid => _text(
    'رُفض طلب الحفظ. اقرأ الحالة الحالية قبل متابعة جديدة.',
    'בקשת השמירה נדחתה. יש לקרוא את המצב הנוכחי לפני המשך.',
    'The save request was refused. Read current settings before starting again.',
  );
  String get uncertain => _text(
    'نتيجة الحفظ غير مؤكدة. لم نكرر الكتابة. تحقّق من الحفظ قبل أي محاولة أخرى.',
    'תוצאת השמירה אינה ודאית. הכתיבה לא נשלחה שוב. יש לבדוק את השמירה לפני ניסיון נוסף.',
    'The save outcome is uncertain. No write was repeated. Check the save before any further attempt.',
  );
  String get checkSave =>
      _text('التحقق من الحفظ', 'בדיקת השמירה', 'Check save outcome');
  String get notRecorded => _text(
    'لم يُسجّل هذا الحفظ عند التحقق، لكن ذلك لا يُلغيه وقد يصل الطلب المتأخر. تحقّق مرة أخرى أو أعد إرسال الحفظ نفسه فقط.',
    'השמירה לא נרשמה בעת הבדיקה, אך זו אינה פעולת ביטול והבקשה עשויה להגיע באיחור. יש לבדוק שוב או לשלוח מחדש רק את אותה שמירה.',
    'This save was not recorded when checked. This does not cancel it; the original request may arrive late. Check again or explicitly resend only the same save.',
  );
  String get retrySame => _text(
    'إعادة إرسال الحفظ نفسه',
    'שליחת אותה שמירה שוב',
    'Resend the same save',
  );
  String get reload => _text(
    'تجاهل المسودة وقراءة الحالة الحالية',
    'ביטול הטיוטה וקריאת המצב הנוכחי',
    'Discard draft and read current settings',
  );
  String get read => _text(
    'إعادة قراءة الإعدادات',
    'קריאת ההגדרות שוב',
    'Read settings again',
  );
}
