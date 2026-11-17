/** Welcome-only public copy, selected on the server; no shared checkout vector change. */
import type { Locale } from './locales';
import ar from '../../messages/welcome-background.ar.json';
import he from '../../messages/welcome-background.he.json';
import en from '../../messages/welcome-background.en.json';

interface WelcomeBackgroundMessages { readonly play: string; readonly pause: string }
const dictionaries = { ar, he, en } satisfies Record<Locale, WelcomeBackgroundMessages>;
export function welcomeBackgroundMessages(locale: Locale): WelcomeBackgroundMessages {
  return dictionaries[locale];
}
