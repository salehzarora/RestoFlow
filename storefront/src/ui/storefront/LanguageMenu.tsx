/** Native language disclosure. Both actual callers use the compact header. */
import { dirOf, LOCALES, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import { CheckIcon } from './icons';
import styles from './home/home.module.css';

const GLYPH: Readonly<Record<Locale, string>> = { ar: 'ع', he: 'עב', en: 'EN' };

export function LanguageMenu({ locale, hrefFor }: {
  locale: Locale; hrefFor: (target: Locale) => string;
}) {
  const m = storefrontMessages(locale);
  return <details className={styles.langWrap}>
    <summary className={styles.langControl} aria-label={m.langLabel}>
      <span>{GLYPH[locale]}</span>
    </summary>
    <ul className={styles.langMenu}>
      {LOCALES.map(code => {
        const active = code === locale;
        return <li key={code}>
          <a className={active ? `${styles.langItem} ${styles.langActive}` : styles.langItem}
            href={hrefFor(code)} hrefLang={code} lang={code} dir={dirOf(code)}
            aria-current={active ? 'true' : undefined}>
            <span>{m.languageNames[code]}</span>
            {active ? <CheckIcon /> : null}
          </a>
        </li>;
      })}
    </ul>
  </details>;
}
