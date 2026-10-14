import type { Locale } from './locales';
import type { OrderSnapshot, WebOrderErrorCode, WebOrderStatus } from '@/orders/contract';

const en = {
  payAtPickup: 'Pay at pickup',
  sendInfo: 'Send a pickup request to the restaurant. Your order is confirmed only when the restaurant accepts it.',
  estimate: 'Estimated total. The restaurant server calculates the final total when you submit.',
  taxTotal: 'Tax',
  atLeast: 'Choose at least {n}',
  orderNotes: 'Order notes',
  notesLimit: 'Use up to 500 characters for order notes.',
  itemNotesLimit: 'Use up to 140 characters for this item note.',
  phoneHint: '+972501234567',
  phoneHelp: 'Use + followed by 8–15 digits, including your country code.',
  limits: 'Pickup requests allow up to 20 lines and 50 items. Adjust your cart to continue.',
  pending: 'Waiting for the restaurant',
  pendingBody: 'Your request was saved. It is awaiting acceptance by the restaurant.',
  accepted: 'Accepted by the restaurant',
  acceptedBody: 'The restaurant accepted your pickup order. Pay at pickup.',
  rejected: 'Request declined',
  rejectedBody: 'The restaurant declined this request. It has not been accepted.',
  expired: 'Request expired',
  expiredBody: 'This request expired before the restaurant accepted it.',
  status: 'Request status',
  checking: 'Checking request status…',
  unknown: 'We could not confirm the request outcome. Check its status before trying again.',
  notFound: 'No request was found. You can retry the exact original request while this page remains open.',
  noRecovery: 'No recoverable request is available in this tab. A page reload cannot resend your previous request.',
  unavailable: 'Request status is temporarily unavailable. The last confirmed status remains below.',
  refresh: 'Check status',
  retry: 'Retry original request',
  invalid: 'Check your name, international phone number, items, modifiers and note lengths.',
  orderingUnavailable: 'The restaurant is not accepting pickup requests right now.',
  menuChanged: 'An item or modifier is unavailable or changed. Return to the menu to review your selections.',
  serviceUnavailable: 'The request could not be processed. Check its status before trying again.',
  rateLimited: 'Too many requests. Please wait before checking again.',
  recoveryUnavailable: 'Secure request recovery is unavailable. Keep this tab open and check the status before trying again.',
  unsupported: 'Pickup checkout is unavailable in this browser. Keep this tab open and check any existing request status before trying again.',
};
export type OrderMessages = { readonly [K in keyof typeof en]: string };
const ar: OrderMessages = {
  payAtPickup: 'الدفع عند الاستلام',
  sendInfo: 'أرسل طلب استلام إلى المطعم. يتم تأكيد الطلب فقط بعد قبول المطعم له.',
  estimate: 'المجموع تقديري. يحسب خادم المطعم المجموع النهائي عند إرسال الطلب.',
  taxTotal: 'الضريبة', atLeast: 'اختر {n} على الأقل',
  orderNotes: 'ملاحظات الطلب', notesLimit: 'استخدم حتى 500 حرف لملاحظات الطلب.', itemNotesLimit: 'استخدم حتى 140 حرفًا لملاحظة هذا الصنف.',
  phoneHint: '+972501234567', phoneHelp: 'أدخل + ثم 8 إلى 15 رقمًا، بما فيها رمز الدولة.',
  limits: 'يُسمح حتى 20 سطرًا و50 قطعة في طلب الاستلام. عدّل السلة للمتابعة.',
  pending: 'بانتظار المطعم', pendingBody: 'تم حفظ طلبك وهو بانتظار قبول المطعم.',
  accepted: 'قَبِل المطعم الطلب', acceptedBody: 'قَبِل المطعم طلب الاستلام. الدفع عند الاستلام.',
  rejected: 'تم رفض الطلب', rejectedBody: 'رفض المطعم هذا الطلب ولم يتم قبوله.',
  expired: 'انتهت صلاحية الطلب', expiredBody: 'انتهت صلاحية هذا الطلب قبل أن يقبله المطعم.',
  status: 'حالة الطلب', checking: 'جارٍ التحقق من حالة الطلب…',
  unknown: 'تعذّر تأكيد نتيجة الطلب. تحقّق من حالته قبل المحاولة مجددًا.',
  notFound: 'لم يتم العثور على الطلب. يمكنك إعادة إرسال الطلب الأصلي نفسه ما دامت هذه الصفحة مفتوحة.',
  noRecovery: 'لا يوجد طلب قابل للاستعادة في علامة التبويب هذه. لا يمكن إعادة إرسال الطلب السابق بعد إعادة تحميل الصفحة.',
  unavailable: 'حالة الطلب غير متاحة مؤقتًا. تظهر أدناه آخر حالة مؤكدة.',
  refresh: 'تحقّق من الحالة', retry: 'إعادة إرسال الطلب الأصلي',
  invalid: 'تحقّق من الاسم ورقم الهاتف الدولي والأصناف والإضافات وأطوال الملاحظات.',
  orderingUnavailable: 'المطعم لا يقبل طلبات الاستلام حاليًا.',
  menuChanged: 'أحد الأصناف أو الإضافات غير متاح أو تغيّر. عد إلى القائمة لمراجعة اختياراتك.',
  serviceUnavailable: 'تعذّرت معالجة الطلب. تحقّق من حالته قبل المحاولة مجددًا.',
  rateLimited: 'طلبات كثيرة. يُرجى الانتظار قبل التحقق مجددًا.',
  recoveryUnavailable: 'استعادة الطلب الآمنة غير متاحة. أبقِ علامة التبويب هذه مفتوحة وتحقّق من حالة الطلب قبل المحاولة مجددًا.',
  unsupported: 'طلب الاستلام غير متاح في هذا المتصفح. أبقِ علامة التبويب هذه مفتوحة وتحقّق من حالة أي طلب موجود قبل المحاولة مجددًا.',
};
const he: OrderMessages = {
  payAtPickup: 'תשלום באיסוף',
  sendInfo: 'שלחו בקשת איסוף למסעדה. ההזמנה מאושרת רק לאחר שהמסעדה מקבלת אותה.',
  estimate: 'הסכום משוער. שרת המסעדה מחשב את הסכום הסופי בעת שליחת הבקשה.',
  taxTotal: 'מס', atLeast: 'בחרו לפחות {n}',
  orderNotes: 'הערות להזמנה', notesLimit: 'ניתן להזין עד 500 תווים בהערות להזמנה.', itemNotesLimit: 'ניתן להזין עד 140 תווים בהערה לפריט זה.',
  phoneHint: '+972501234567', phoneHelp: 'הזינו + ואחריו 8–15 ספרות, כולל קידומת המדינה.',
  limits: 'בקשת איסוף יכולה לכלול עד 20 שורות ו־50 פריטים. עדכנו את הסל כדי להמשיך.',
  pending: 'ממתינים למסעדה', pendingBody: 'הבקשה נשמרה וממתינה לאישור המסעדה.',
  accepted: 'המסעדה קיבלה את ההזמנה', acceptedBody: 'המסעדה קיבלה את הזמנת האיסוף. התשלום באיסוף.',
  rejected: 'הבקשה נדחתה', rejectedBody: 'המסעדה דחתה את הבקשה. היא לא אושרה.',
  expired: 'תוקף הבקשה פג', expiredBody: 'תוקף הבקשה פג לפני שהמסעדה קיבלה אותה.',
  status: 'מצב הבקשה', checking: 'בודקים את מצב הבקשה…',
  unknown: 'לא ניתן לאמת את תוצאת הבקשה. בדקו את מצבה לפני ניסיון נוסף.',
  notFound: 'לא נמצאה בקשה. ניתן לשלוח שוב את הבקשה המקורית כל עוד הדף הזה נשאר פתוח.',
  noRecovery: 'אין בקשה הניתנת לשחזור בלשונית זו. טעינה מחדש אינה מאפשרת לשלוח שוב את הבקשה הקודמת.',
  unavailable: 'מצב הבקשה אינו זמין כעת. המצב האחרון שאומת מופיע בהמשך.',
  refresh: 'בדיקת מצב', retry: 'שליחה חוזרת של הבקשה המקורית',
  invalid: 'בדקו את השם, מספר הטלפון הבינלאומי, הפריטים, התוספות ואורך ההערות.',
  orderingUnavailable: 'המסעדה אינה מקבלת בקשות איסוף כרגע.',
  menuChanged: 'פריט או תוספת אינם זמינים או השתנו. חזרו לתפריט ובדקו את הבחירות.',
  serviceUnavailable: 'לא ניתן לעבד את הבקשה. בדקו את מצבה לפני ניסיון נוסף.',
  rateLimited: 'יותר מדי בקשות. המתינו לפני בדיקה נוספת.',
  recoveryUnavailable: 'שחזור הבקשה המאובטח אינו זמין. השאירו את הלשונית הזו פתוחה ובדקו את מצב הבקשה לפני ניסיון נוסף.',
  unsupported: 'הזמנת איסוף אינה זמינה בדפדפן זה. השאירו את הלשונית הזו פתוחה ובדקו את מצב הבקשה הקיימת לפני ניסיון נוסף.',
};
export function orderMessages(locale: Locale): OrderMessages { return locale === 'ar' ? ar : locale === 'he' ? he : en; }
export function orderStatusCopy(status: WebOrderStatus, m: OrderMessages) {
  return { title: m[status], body: m[`${status}Body`] };
}
export function orderErrorCopy(error: WebOrderErrorCode | null, m: OrderMessages): string {
  switch (error) {
    case 'ordering_unavailable': return m.orderingUnavailable;
    case 'item_unavailable': case 'modifier_selection_invalid': case 'menu_unavailable': return m.menuChanged;
    case 'invalid_request': case 'payload_too_large': return m.invalid;
    case 'rate_limited': case 'capacity_reached': return m.rateLimited;
    case 'storage_unavailable': return m.recoveryUnavailable;
    case 'configuration_invalid': case 'crypto_unavailable': return m.unsupported;
    case 'recovery_expired': case 'recovery_invalid': return m.noRecovery;
    default: return m.serviceUnavailable;
  }
}
export function orderSnapshotCopy(snapshot: OrderSnapshot, m: OrderMessages): string | null {
  switch (snapshot.phase) {
    case 'submitting': case 'reconciling': return m.checking;
    case 'unknown': return m.unknown;
    case 'not_found': return snapshot.canRetry ? m.notFound : m.noRecovery;
    case 'unavailable': return m.unavailable;
    case 'failure': return orderErrorCopy(snapshot.error, m);
    default: return null;
  }
}
