import { isProviderContext } from '@/source/mode';

export const CINEMATIC_PREVIEW_SLUG = 'sf-design-preview';
export type CinematicPreviewScreen = 'intro' | 'menu' | 'search' | 'cart';

/** BIZBOT-STOREFRONT-CINEMATIC-001: never expose the captured sample in Production. */
export function cinematicPreviewAllowed(env: NodeJS.ProcessEnv = process.env): boolean {
  return env.VERCEL_ENV === 'preview' || (
    !isProviderContext(env) &&
    env.STOREFRONT_SOURCE === 'fixture' &&
    env.SF_DESIGN_PREVIEW === '1'
  );
}

/** Keep checkout, payment, review and arbitrary nested destinations unavailable. */
export function cinematicPreviewScreen(segments: readonly string[] | undefined): CinematicPreviewScreen | null {
  if (segments === undefined || segments.length === 0) return 'intro';
  if (segments.length !== 1) return null;
  const screen = segments[0];
  return screen === 'menu' || screen === 'search' || screen === 'cart' ? screen : null;
}
