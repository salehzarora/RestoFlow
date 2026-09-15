import ar from '../../messages/ar.json';
import en from '../../messages/en.json';
import he from '../../messages/he.json';
import type { Locale } from './locales';

export type Messages = {
  readonly brand: string;
  readonly title: string;
  readonly tagline: string;
  readonly status: string;
  readonly languageLabel: string;
  readonly languageNames: Readonly<Record<Locale, string>>;
  readonly notFoundTitle: string;
  readonly notFoundBody: string;
  readonly homeLink: string;
};

const MESSAGES: Readonly<Record<Locale, Messages>> = { ar, en, he };

export function messagesFor(locale: Locale): Messages {
  return MESSAGES[locale];
}
