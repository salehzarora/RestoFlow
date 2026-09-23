'use client';

/**
 * Skips the intro for a visitor who has already been past it in this tab.
 *
 * WHY A COMPONENT AND NOT A REDIRECT IN THE PAGE: every route here is a STATIC
 * document, so the served bytes are identical for every visitor and the
 * per-slug session flag can only be applied after hydration. The prerendered
 * HTML therefore shows the FIRST-VISIT state - the intro - which is what a
 * no-script visitor, a crawler and the canonical screenshot all see. This
 * component only ever removes it afterwards.
 *
 * NO HYDRATION MISMATCH: `skip` starts false, so the first client render is
 * identical to the server HTML. The flag is read in a LAYOUT effect, so when it
 * is set the intro is unmounted in the same commit, before the browser paints
 * the hydrated frame. The ThemeScope root keeps painting `--bg` at 100dvh, so
 * the intervening frame is the tenant canvas, never a white flash.
 *
 * Route role per DESIGN_HANDOFF.md:27 ("returning visitors skip straight to
 * home") and INTERACTIONS.md:10. The SAME line puts deep links in that class -
 * "Deep links (`?item=`, `/r/:code`) and returning visitors skip straight to
 * home" - so an `?item=` visitor skips the intro even on a first visit, and the
 * query is carried across so the sheet still opens on the menu.
 */
import { useLayoutEffect, useState, type ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import { hasSeenIntro } from '@/session/uiSession';

export function IntroGate({
  slug,
  homeHref,
  children,
}: {
  slug: string;
  homeHref: string;
  children: ReactNode;
}) {
  const router = useRouter();
  const [skip, setSkip] = useState(false);

  useLayoutEffect(() => {
    // A deep link to an item is not a visit to the intro, whether or not this
    // tab has been here before.
    const search = window.location.search;
    const deepLink = new URLSearchParams(search).has('item');
    if (!deepLink && !hasSeenIntro(slug)) return;
    setSkip(true);
    // `replace`, not `push`: the intro must not become a history entry the back
    // button lands on only to be skipped again.
    router.replace(deepLink ? `${homeHref}${search}` : homeHref);
  }, [slug, homeHref, router]);

  return skip ? null : <>{children}</>;
}
