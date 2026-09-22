/**
 * Unknown / unpublished storefront — screen 11, approved handoff.
 *
 * ISOLATION IS THE POINT. This component takes ONLY a locale. It never receives
 * a Tenant, never calls the source, and never renders a tenant colour, logo,
 * name or slug — so an unknown or unpublished slug cannot leak that a tenant
 * exists, or anything about it. The BIZBOT mark is platform-owned.
 */
import { rubikUnknown } from '@/fonts/rubik-unknown';
import { dirOf, type Locale } from '@/i18n/locales';
import { storefrontMessages } from '@/i18n/storefront';
import styles from './Unknown.module.css';

export function Unknown({ locale }: { locale: Locale }) {
  const m = storefrontMessages(locale);

  return (
    // `lang`/`dir` sit on the screen element, not on <html>: this component is
    // also rendered by app/not-found.tsx, which Next emits WITHOUT a root
    // layout, so there is no <html> tag of ours to carry them. Declaring them
    // here is what makes the Arabic copy render right-to-left in 404.html.
    <main className={`${styles.screen} ${rubikUnknown.className}`} lang={locale} dir={dirOf(locale)}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        className={styles.mark}
        src="/bizbot-symbol-256.png"
        alt="BIZBOT"
        width={64}
        height={64}
        decoding="async"
      />
      <h1 className={styles.title}>{m.unknownTitle}</h1>
      <p className={styles.body}>{m.unknownBody}</p>
      <p className={styles.credit}>
        {m.poweredBy} <span className={styles.creditName}>BIZBOT</span>
      </p>
    </main>
  );
}
