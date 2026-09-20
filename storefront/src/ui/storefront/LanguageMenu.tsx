/**
 * Language control — one circular button showing the CURRENT language glyph,
 * opening a three-item menu with each language named in its own script and an
 * accent check on the active one, exactly as CONTENT_AND_LOCALIZATION describes.
 *
 * Built on <details>/<summary>, so the disclosure works with NO JavaScript and
 * nothing to hydrate. Each item is a PLAIN ANCHOR: crossing locales must be a
 * real document navigation so the served `lang`/`dir` are already correct
 * (approved decision 2). A next/link client transition would leave <html lang>
 * describing the previous language.
 */
import { dirOf, LOCALES, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { CheckIcon } from './icons';
import styles from './LanguageMenu.module.css';

const GLYPH: Readonly<Record<Locale, string>> = { ar: 'عربي', he: 'עברית', en: 'EN' };

export function LanguageMenu({
  locale,
  hrefFor,
}: {
  locale: Locale;
  hrefFor: (target: Locale) => string;
}) {
  const m = storefrontMessages(locale);

  return (
    <details className={styles.wrap}>
      <summary className={styles.control} aria-label={m.langLabel}>
        <span className={styles.glyph}>{GLYPH[locale]}</span>
        <span className={styles.caret} aria-hidden="true" />
      </summary>
      <ul className={styles.menu}>
        {LOCALES.map((code) => {
          const active = code === locale;
          return (
            <li key={code}>
              <a
                className={active ? `${styles.item} ${styles.itemActive}` : styles.item}
                href={hrefFor(code)}
                hrefLang={code}
                lang={code}
                dir={dirOf(code)}
                aria-current={active ? 'true' : undefined}
              >
                <span>{m.languageNames[code]}</span>
                {active ? (
                  <span className={styles.check}>
                    <CheckIcon />
                  </span>
                ) : null}
              </a>
            </li>
          );
        })}
      </ul>
    </details>
  );
}
