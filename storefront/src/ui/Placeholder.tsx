import Link from 'next/link';
import { LOCALES, dirOf, pathOf, type Locale } from '@/i18n/locales';
import { messagesFor } from '@/i18n/messages';

export function Placeholder({ locale }: { locale: Locale }) {
  const m = messagesFor(locale);

  return (
    <main className="shell" dir={dirOf(locale)}>
      <div className="card">
        <p className="brand">{m.brand}</p>
        <h1 className="title">{m.title}</h1>
        <p className="tagline">{m.tagline}</p>
        <p className="status" role="status">
          {m.status}
        </p>

        <nav className="langs" aria-label={m.languageLabel}>
          <ul className="langList">
            {LOCALES.map((code) => (
              <li key={code}>
                <Link
                  className="langLink"
                  href={pathOf(code)}
                  // Sibling root layouts mean crossing locales is a full document
                  // load, so an RSC prefetch is fetched and never used. Turning it
                  // off removes speculative traffic the shell cannot benefit from.
                  prefetch={false}
                  hrefLang={code}
                  lang={code}
                  dir={dirOf(code)}
                  aria-current={code === locale ? 'page' : undefined}
                >
                  {m.languageNames[code]}
                </Link>
              </li>
            ))}
          </ul>
        </nav>
      </div>
    </main>
  );
}
