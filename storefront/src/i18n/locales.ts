export const LOCALES = ['ar', 'en', 'he'] as const;

export type Locale = (typeof LOCALES)[number];

export const DEFAULT_LOCALE: Locale = 'ar';

/** Writing direction. Arabic and Hebrew are right-to-left. */
export function dirOf(locale: Locale): 'rtl' | 'ltr' {
  return locale === 'en' ? 'ltr' : 'rtl';
}

export function isLocale(value: string): value is Locale {
  return (LOCALES as readonly string[]).includes(value);
}

/** The path each locale is served from. The default locale also owns `/`. */
export function pathOf(locale: Locale): string {
  return `/${locale}`;
}
