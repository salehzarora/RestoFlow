import 'package:flutter/widgets.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

String welcomeVideoCopy(BuildContext context, String key) {
  const copy = <String, List<String>>{
    'title': ['Background', 'الخلفية', 'רקע'],
    'backgroundHelp': [
      'Choose an image or video for the full-page background.',
      'اختر صورة أو فيديو لخلفية الصفحة كاملة.',
      'בחרו תמונה או סרטון לרקע העמוד כולו.',
    ],
    'playbackHelp': [
      'Loops without sound, with a pause button. Reduced motion pauses it. If playback fails, the selected image is shown.',
      'يتكرر بلا صوت مع زر إيقاف مؤقت. يتوقف عند تقليل الحركة، وتظهر الصورة المختارة عند تعذّر التشغيل.',
      'מתנגן בלולאה ללא קול, עם כפתור השהיה. הפחתת תנועה משהה אותו. בכשל בניגון מוצגת התמונה שנבחרה.',
    ],
    'help': [
      'MP4, up to 30 seconds and 20 MiB. Uploading does not change the page.',
      'MP4، حتى 30 ثانية و20 MiB. الرفع وحده لا يغيّر الصفحة.',
      'MP4, עד 30 שניות ו־20 MiB. העלאה לבדה אינה משנה את העמוד.',
    ],
    'fileDetails': [
      'H.264 video, up to 1920×1080. AAC audio is allowed; background playback stays muted.',
      'فيديو H.264 بدقة حتى 1920×1080. يُقبل صوت AAC، ويظهر فيديو الخلفية بلا صوت.',
      'וידאו H.264 עד 1920×1080. שמע AAC נתמך; סרטון הרקע מוצג ללא קול.',
    ],
    'cropHelp': [
      'Edges may be cropped to fill the screen without stretching the image.',
      'قد تُقصّ الأطراف لملء الشاشة دون تشويه الصورة.',
      'ייתכן חיתוך בשוליים למילוי המסך, ללא עיוות התמונה.',
    ],
    'mode': ['Background type', 'نوع الخلفية', 'סוג הרקע'],
    'publicCopyHelp': [
      'The published file is public and kept as-is, including information stored inside it. No conversion or compression. Publish only what visitors may see.',
      'الملف المنشور متاح للجميع كما هو، مع المعلومات المحفوظة داخله، دون تحويل أو ضغط. انشر فقط ما تسمح للزوار برؤيته.',
      'הקובץ שפורסם זמין לכולם ונשאר כפי שהוא, כולל המידע השמור בתוכו, ללא המרה או דחיסה. פרסמו רק תוכן שמיועד למבקרים.',
    ],
    'legacy': ['Default background', 'الخلفية الافتراضية', 'רקע ברירת מחדל'],
    'image': ['Image', 'صورة', 'תמונה'],
    'video': ['Video', 'فيديو', 'סרטון'],
    'choose': ['Choose a video', 'اختيار فيديو', 'בחירת סרטון'],
    'selectedVideo': ['Selected video', 'الفيديو المختار', 'הסרטון שנבחר'],
    'useVideo': ['Use this video', 'استخدام هذا الفيديو', 'שימוש בסרטון הזה'],
    'videoNumber': ['Video {number}', 'فيديو {number}', 'סרטון {number}'],
    'uploadInProgress': [
      'Uploading and preparing the video…',
      'جارٍ رفع الفيديو وتجهيزه…',
      'מעלה ומכין את הסרטון…',
    ],
    'savedDraftHelp': [
      'Using a video changes the draft. Save the welcome page to show it to visitors.',
      'استخدام الفيديو يغيّر المسودة. احفظ صفحة الترحيب لإظهاره للزوار.',
      'בחירת הסרטון משנה את הטיוטה. שמרו את עמוד הפתיחה כדי להציג אותו למבקרים.',
    ],
    'more': ['More options', 'خيارات إضافية', 'אפשרויות נוספות'],
    'none': [
      'No video — show the image',
      'دون فيديو — إظهار الصورة',
      'ללא סרטון — הצגת התמונה',
    ],
    'unavailableSelection': [
      'Selected video unavailable',
      'الفيديو المختار غير متاح',
      'הסרטון שנבחר אינו זמין',
    ],
    'upload': [
      'Choose video from device',
      'اختيار فيديو من الجهاز',
      'בחירת סרטון מהמכשיר',
    ],
    'reload': ['Refresh videos', 'تحديث الفيديوهات', 'רענון הסרטונים'],
    'retry': ['Retry publishing', 'إعادة محاولة النشر', 'ניסיון פרסום חוזר'],
    'published': [
      'Video published. Use it, then save the welcome page.',
      'نُشر الفيديو. اضغط «استخدام هذا الفيديو» ثم احفظ صفحة الترحيب.',
      'הסרטון פורסם. בחרו בשימוש בסרטון ואז שמרו את עמוד הפתיחה.',
    ],
    'publishedReadFailed': [
      'Video published, but the list could not refresh. Refresh it without uploading again.',
      'نُشر الفيديو وتعذّر تحديث القائمة. حدّثها دون رفعه مجددًا.',
      'הסרטון פורסם, אך הרשימה לא התרעננה. רעננו אותה ללא העלאה נוספת.',
    ],
    'uncertain': [
      'Publication is not confirmed. Refresh the list before retrying the same upload. There is no automatic retry.',
      'لم يتأكد نشر الفيديو. حدّث القائمة قبل إعادة محاولة النشر نفسه. لا نعيد المحاولة تلقائيًا.',
      'פרסום הסרטון לא אושר. רעננו את הרשימה לפני ניסיון חוזר לאותה העלאה. אין ניסיון חוזר אוטומטי.',
    ],
    'refused': [
      'This video is not supported. Choose a suitable MP4 file.',
      'هذا الفيديو غير مدعوم. اختر ملف MP4 مناسبًا.',
      'הסרטון אינו נתמך. בחרו קובץ MP4 מתאים.',
    ],
    'denied': [
      'You do not have permission to publish for this restaurant.',
      'لا تملك صلاحية النشر لهذا المطعم.',
      'אין הרשאה לפרסם עבור המסעדה הזו.',
    ],
    'unauthenticated': [
      'Sign in again, then try publishing.',
      'سجّل الدخول مجددًا ثم أعد محاولة النشر.',
      'התחברו מחדש ואז נסו לפרסם.',
    ],
    'sourceMissing': [
      'The uploaded file is unavailable. Your video selection was not changed.',
      'الملف المرفوع غير متاح. لم نغيّر اختيار الفيديو.',
      'הקובץ שהועלה אינו זמין. בחירת הסרטון לא השתנתה.',
    ],
    'restartRequired': [
      'This upload conflicts with another. No new attempt was started automatically.',
      'تعارضت عملية الرفع. لم تبدأ محاولة جديدة تلقائيًا.',
      'ההעלאה מתנגשת עם פעולה אחרת. לא התחיל ניסיון חדש אוטומטית.',
    ],
    'objectConflict': [
      'The published video does not match the uploaded file. Your selection was not changed.',
      'الفيديو المنشور لا يطابق الملف المرفوع. لم نغيّر اختيارك.',
      'הסרטון שפורסם אינו תואם לקובץ שהועלה. הבחירה לא השתנתה.',
    ],
    'invalidRequest': [
      'This video could not be published. Reload this page.',
      'تعذّر نشر هذا الفيديو. أعد تحميل الصفحة.',
      'לא ניתן לפרסם את הסרטון. טענו את העמוד מחדש.',
    ],
    'serviceUnavailable': [
      'Publication could not be confirmed. Refresh the video list.',
      'تعذّر تأكيد النشر. حدّث قائمة الفيديوهات.',
      'לא ניתן לאשר את הפרסום. רעננו את רשימת הסרטונים.',
    ],
    'uploadFailed': [
      'The upload was not confirmed. No publishing retry was sent.',
      'لم يتأكد رفع الملف. لم نكرر محاولة النشر.',
      'ההעלאה לא אושרה. לא נשלח ניסיון פרסום חוזר.',
    ],
    'invalidFile': [
      'Choose an MP4 file up to 20 MiB. See the supported format under More options.',
      'اختر ملف MP4 بحجم حتى 20 MiB. المواصفات في «خيارات إضافية».',
      'בחרו קובץ MP4 עד 20 MiB. פרטי הפורמט נמצאים באפשרויות נוספות.',
    ],
    'bindingChanged': [
      'The restaurant or account changed. This upload will not be retried here.',
      'تغيّر المطعم أو الحساب. لن نعيد هذه العملية هنا.',
      'המסעדה או החשבון השתנו. ההעלאה הזו לא תישלח כאן שוב.',
    ],
    'pickerUnavailable': [
      'File upload is not available here.',
      'رفع الملفات غير متاح هنا.',
      'העלאת קבצים אינה זמינה כאן.',
    ],
    'previewLink': ['Open video', 'فتح الفيديو', 'פתיחת הסרטון'],
    'previewHelp': [
      'Opens the published video in a new tab. Opening it does not save your welcome-page selection.',
      'يفتح الفيديو المنشور في تبويب جديد، ولا يحفظ اختياره لصفحة الترحيب.',
      'פותח את הסרטון שפורסם בלשונית חדשה. פתיחתו אינה שומרת את הבחירה בעמוד הפתיחה.',
    ],
    'readFailed': [
      'The video list could not be loaded.',
      'تعذّر تحميل قائمة الفيديوهات.',
      'לא ניתן לטעון את רשימת הסרטונים.',
    ],
  };
  final locale = AppLocalizations.of(context).localeName.split('_').first;
  return copy[key]![switch (locale) {
    'ar' => 1,
    'he' => 2,
    _ => 0,
  }];
}
