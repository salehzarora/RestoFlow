import 'package:flutter/widgets.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

String welcomeVideoCopy(BuildContext context, String key) {
  const copy = <String, List<String>>{
    'title': ['Welcome-page video', 'فيديو صفحة الترحيب', 'סרטון עמוד הפתיחה'],
    'help': [
      'MP4/H.264, up to 20 MiB and 30 seconds, at most 1920×1080; optional AAC audio. Upload publishes a public asset only. Choose it and Save content to change the welcome page.',
      'MP4/H.264 حتى 20 ميبيبايت و30 ثانية، وبحد 1920×1080؛ صوت AAC اختياري. الرفع ينشر ملفًا عامًا فقط؛ اختره ثم اضغط حفظ المحتوى لتغيير صفحة الترحيب.',
      'MP4/H.264 עד20 MiB ו30 שניות, עד1920×1080; שמעAAC אופציונלי. העלאה מפרסמת קובץ ציבורי בלבד. יש לבחור ולשמור תוכן כדי לשנות את עמוד הפתיחה.',
    ],
    'mode': ['Welcome media', 'وسائط الترحيب', 'מדיה בעמוד הפתיחה'],
    'publicCopyHelp': [
      'The validated MP4 is published as-is, without transcoding, compression or embedded-metadata removal. Publish only a file intended for public viewing.',
      'يُنشر ملف MP4 المتحقق منه كما هو، دون تحويل أو ضغط أو حذف بياناته الوصفية المضمّنة. انشر ملفًا مناسبًا للعرض العام.',
      'קובץMP4 המאומת מפורסם כפי שהוא, ללא המרה, דחיסה או הסרת מטא־נתונים מוטמעים. יש לפרסם קובץ המיועד לצפייה ציבורית.',
    ],
    'legacy': [
      'Keep previous behavior',
      'السلوك السابق',
      'השארת ההתנהגות הקודמת',
    ],
    'image': ['Image', 'صورة', 'תמונה'],
    'video': ['Video', 'فيديو', 'סרטון'],
    'choose': ['Published video', 'الفيديو المنشور', 'סרטון שפורסם'],
    'none': [
      'No video — use the image fallback',
      'بدون فيديو — استخدام الصورة البديلة',
      'ללא סרטון — שימוש בתמונה החלופית',
    ],
    'unavailableSelection': [
      'Saved video unavailable',
      'الفيديو المحفوظ غير متاح',
      'הסרטון השמור אינו זמין',
    ],
    'upload': ['Upload and publish MP4', 'رفع ونشرMP4', 'העלאה ופרסוםMP4'],
    'reload': [
      'Reload published videos',
      'إعادة قراءة الفيديوهات المنشورة',
      'טעינה מחדש של סרטונים שפורסמו',
    ],
    'retry': [
      'Retry this exact publication',
      'إعادة محاولة عملية النشر نفسها',
      'ניסיון חוזר לאותו פרסום',
    ],
    'published': [
      'Published. Select the video and Save content to use it.',
      'نُشر الفيديو. اختره واحفظ المحتوى لاستخدامه.',
      'פורסם. יש לבחור בסרטון ולשמור תוכן כדי להשתמש בו.',
    ],
    'publishedReadFailed': [
      'Publication confirmed; the library could not be reloaded. Reload it without publishing again.',
      'تأكد النشر وتعذرت إعادة قراءة المكتبة. أعد قراءتها دون نشر جديد.',
      'הפרסום אושר אך טעינת הספרייה נכשלה. יש לטעון מחדש ללא פרסום נוסף.',
    ],
    'uncertain': [
      'Publication outcome unknown. Reload the library; there is no automatic retry. An explicit retry keeps the same operation identity.',
      'نتيجة النشر غير مؤكدة. أعد قراءة المكتبة؛ لا توجد إعادة تلقائية. المحاولة الصريحة تحتفظ بهوية العملية نفسها.',
      'תוצאת הפרסום אינה ודאית. יש לטעון את הספרייה; אין ניסיון חוזר אוטומטי. ניסיון מפורש שומר על אותה זהות פעולה.',
    ],
    'refused': [
      'The video was refused. Choose a supported MP4; the original image remains available.',
      'رُفض الفيديو. اختر MP4 بالمواصفات المدعومة؛ تبقى الصورة البديلة متاحة.',
      'הסרטון נדחה. יש לבחורMP4 נתמך; התמונה החלופית נשארת זמינה.',
    ],
    'denied': [
      'You do not have permission to publish here.',
      'لا تملك صلاحية النشر هنا.',
      'אין הרשאה לפרסם כאן.',
    ],
    'unauthenticated': [
      'Sign in again to publish.',
      'سجّل الدخول مجددًا للنشر.',
      'יש להתחבר מחדש כדי לפרסם.',
    ],
    'sourceMissing': [
      'The private upload is unavailable; no video was selected.',
      'الملف المرفوع الخاص غير متاح؛ لم يُحدد فيديو.',
      'הקובץ הפרטי אינו זמין; לא נבחר סרטון.',
    ],
    'restartRequired': [
      'This operation identity conflicts with another request. No automatic new request was sent.',
      'تعارضت هوية العملية مع طلب آخر. لم يُرسل طلب جديد تلقائيًا.',
      'זהות הפעולה מתנגשת עם בקשה אחרת. לא נשלחה בקשה חדשה אוטומטית.',
    ],
    'objectConflict': [
      'The published object conflicts with the expected video. Nothing was selected.',
      'تعارض الملف المنشور مع الفيديو المتوقع. لم يُحدد أي اختيار.',
      'הקובץ שפורסם מתנגש עם הסרטון הצפוי. לא נבחר דבר.',
    ],
    'invalidRequest': [
      'Publication could not be accepted. Reload the editor.',
      'تعذر قبول عملية النشر. أعد تحميل المحرر.',
      'לא ניתן לקבל את הפרסום. יש לטעון את העורך מחדש.',
    ],
    'serviceUnavailable': [
      'The publishing service could not be confirmed. Reload the library.',
      'تعذر التحقق من خدمة النشر. أعد قراءة المكتبة.',
      'לא ניתן לאמת את שירות הפרסום. יש לטעון את הספרייה מחדש.',
    ],
    'uploadFailed': [
      'The upload could not be confirmed. No publication retry was sent.',
      'تعذر تأكيد الرفع. لم تُرسل إعادة محاولة للنشر.',
      'לא ניתן לאמת את ההעלאה. לא נשלח ניסיון פרסום חוזר.',
    ],
    'invalidFile': [
      'Choose an MP4 file no larger than 20 MiB. The server also validates codec, dimensions and duration.',
      'اختر ملف MP4 لا يتجاوز 20 ميبيبايت. يتحقق الخادم أيضًا من الترميز والأبعاد والمدة.',
      'יש לבחורMP4 עד20 MiB. השרת בודק גם קידוד, ממדים ומשך.',
    ],
    'bindingChanged': [
      'The active restaurant or account changed. The previous operation will not be replayed here.',
      'تغير المطعم أو الحساب النشط. لن تُعاد العملية السابقة هنا.',
      'המסעדה או החשבון הפעילים השתנו. הפעולה הקודמת לא תישלח כאן שוב.',
    ],
    'pickerUnavailable': [
      'File upload is not available on this platform.',
      'رفع الملفات غير متاح على هذه المنصة.',
      'העלאת קבצים אינה זמינה בפלטפורמה זו.',
    ],
    'previewLink': [
      'Open the published video',
      'فتح الفيديو المنشور',
      'פתיחת הסרטון שפורסם',
    ],
    'previewHelp': [
      'Opens the published public file in a new tab. This is a file preview, not an embedded welcome-page playback test.',
      'يفتح الملف العام المنشور في علامة تبويب جديدة. هذه معاينة للملف وليست اختبار تشغيل مضمّن لصفحة الترحيب.',
      'פותח את הקובץ הציבורי שפורסם בלשונית חדשה. זו תצוגת הקובץ ולא בדיקת ניגון מוטמע בעמוד הפתיחה.',
    ],
    'readFailed': [
      'The video library could not be read.',
      'تعذرت قراءة مكتبة الفيديو.',
      'לא ניתן לקרוא את ספריית הסרטונים.',
    ],
  };
  final locale = AppLocalizations.of(context).localeName.split('_').first;
  return copy[key]![switch (locale) {
    'ar' => 1,
    'he' => 2,
    _ => 0,
  }];
}
