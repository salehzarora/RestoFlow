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
    'لهذا الفرع فقط. نشر الموقع والاستلام من المطعم وساعات العمل والإيقاف المؤقت لها إعداداتها الخاصة.',
    'לסניף הנבחר בלבד. פרסום האתר, איסוף עצמי, שעות הפתיחה והשהיה זמנית מנוהלים בנפרד.',
    'For this branch only. Website publication, pickup, opening hours and temporary pauses have separate settings.',
  );
  String get ordering => _text(
    'السماح للزبائن بالطلب من الموقع',
    'לאפשר ללקוחות להזמין מהאתר',
    'Allow customers to order from the website',
  );
  String get orderingHelp => _text(
    'يسمح للزبائن بإرسال طلبات جديدة عندما يكون الموقع منشورًا والمطعم مفتوحًا. إيقافه لا يؤثر على الطلبات السابقة.',
    'מאפשר ללקוחות לשלוח הזמנות חדשות כשהאתר מפורסם והמסעדה פתוחה. כיבוי אינו משפיע על הזמנות קודמות.',
    'Allows customers to send new orders when the website is published and the restaurant is open. Turning this off does not affect previous orders.',
  );
  String get alerts => _text(
    'إشعارات الطلبات على أجهزة الكاشير',
    'התראות הזמנות במכשירי הקופה',
    'Order alerts on cash register devices',
  );
  String get alertsHelp => _text(
    'يسمح لأجهزة الكاشير المفعّلة باستقبال تنبيهات الطلبات الجديدة. إيقافه لا يمنع وصول الطلبات. تشغيله مجددًا لا يعيد تفعيل الأجهزة تلقائيًا؛ قد تحتاج إلى تفعيل الإشعارات من داخل تطبيق الكاشير على كل جهاز.',
    'מאפשר למכשירי קופה שבהם ההתראות מופעלות לקבל התראות על הזמנות חדשות. כיבוי אינו מונע קבלת הזמנות. הפעלה מחדש אינה מפעילה מכשירים אוטומטית; ייתכן שצריך להפעיל שוב התראות מתוך אפליקציית הקופה בכל מכשיר.',
    'Allows cash register devices with alerts enabled to receive new-order alerts. Turning this off does not block incoming orders. Turning it back on does not re-enable devices automatically; you may need to enable alerts again in the cash register app on each device.',
  );
  String get printing => _text(
    'السماح بطباعة طلبات الموقع الجديدة',
    'לאפשר הדפסת הזמנות חדשות מהאתר',
    'Allow printing of new website orders',
  );
  String get printingHelp => _text(
    'يسمح بطباعة طلبات الموقع الجديدة عند قبولها إذا كانت الطابعة جاهزة والطباعة مسموحة. لا يطبع الطلبات القديمة أو يعيد طباعتها.',
    'מאפשר הדפסת הזמנות חדשות מהאתר בעת אישורן, אם המדפסת מוכנה וההדפסה מותרת. אינו מדפיס הזמנות ישנות או מדפיס אותן מחדש.',
    'Allows new website orders to print when accepted, if the printer is ready and printing is permitted. Does not print or reprint old orders.',
  );
  String get loading => _text(
    'جارٍ قراءة إعدادات الفرع…',
    'קורא את הגדרות הסניף…',
    'Reading branch settings…',
  );
  String get saving => _text('جارٍ الحفظ…', 'שומר…', 'Saving…');
  String get save => _text('حفظ الإعدادات', 'שמירת ההגדרות', 'Save settings');
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
    'تجاهل التغييرات غير المحفوظة وتحديث الإعدادات',
    'ביטול השינויים שלא נשמרו ורענון ההגדרות',
    'Discard unsaved changes and refresh settings',
  );
  String get read =>
      _text('تحديث الإعدادات', 'רענון ההגדרות', 'Refresh settings');
}
