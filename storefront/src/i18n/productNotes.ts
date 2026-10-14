import type { Locale } from './locales';

/** Product-sheet copy stays independent of checkout transport/status messages. */
export function productNoteMessages(locale: Locale) {
  if (locale === 'ar') return { itemNotesLimit: 'استخدم حتى 140 حرفًا لملاحظة هذا الصنف.', atLeast: 'اختر {n} على الأقل' };
  if (locale === 'he') return { itemNotesLimit: 'ניתן להזין עד 140 תווים בהערה לפריט זה.', atLeast: 'בחרו לפחות {n}' };
  return { itemNotesLimit: 'Use up to 140 characters for this item note.', atLeast: 'Choose at least {n}' };
}
