import type { Category, MenuItem, ModifierGroup, DeliveryZone, MotionMode, StorefrontResolution, Tenant } from '@/source/types';
import { CINEMATIC_PREVIEW_SLUG, cinematicPreviewAllowed } from './access';
import catalogSnapshot from './catalog.snapshot.json';
import runtimeSnapshot from './runtime.snapshot.json';

/** Public menu captured on 2026-11-03; no customer, order or private dashboard data. */
const catalog = catalogSnapshot as { tenant: Tenant; categories: Category[] };
const runtime = runtimeSnapshot as {
  menuVersion: string; items: MenuItem[]; groups: ModifierGroup[];
  zones: DeliveryZone[]; taxRateBp: number; motion: MotionMode;
};
const title = 'الجوع إله وجهة.';

/** A presentation profile over the captured catalog, isolated from every live slug. */
export function cinematicPreviewResolution(env: NodeJS.ProcessEnv = process.env): StorefrontResolution | null {
  if (!cinematicPreviewAllowed(env)) return null;
  return {
    source: 'fixture',
    preset: 'dark',
    menuVersion: `cinematic-preview-${runtime.menuVersion}`,
    groups: runtime.groups,
    zones: runtime.zones,
    taxRateBp: runtime.taxRateBp,
    view: {
      tenant: {
        ...catalog.tenant,
        slug: CINEMATIC_PREVIEW_SLUG,
        heroImage: '/cinematic-preview/cover.webp',
        brand: {
          ...catalog.tenant.brand,
          primary: '#151513', accent: '#f2ad79', text: '#f7f2ea',
          buttonText: '#161410', fontFamily: 'alexandria',
        },
        service: { ...catalog.tenant.service, orderingEnabled: false },
      },
      categories: catalog.categories,
      items: runtime.items.map((item) => ({
        ...item,
        image: item.image === null ? null : `/cinematic-preview/${item.id}.webp`,
        imageFit: 'whole-image', cardLayout: 'cutout',
      })),
      cardMode: 'list',
      motion: runtime.motion,
      modules: {
        campaign: {
          title, subline: 'طعم بتحب ترجع له.',
          hero: {
            mode: 'editorial', itemId: null,
            format: { text: title, highlight: { start: 10, end: 14 }, break_before: 6 },
            eyebrow: null, stamp: null, footnote: null,
          },
        },
        announcement: null, promo: null, story: null,
        popular: { enabled: false, ready: false },
      },
      cart: { lines: [], itemCount: 0, subtotalMinor: 0, taxMinor: 0, totalMinor: 0, taxRateBp: runtime.taxRateBp },
    },
  };
}
