// Private in-memory diagnostic of the actual v11 read, using shipped modules.
// Run in its own Node process so the established test-only TS resolver cannot
// change module resolution inside the running Next server or Playwright worker.
import { readFileSync } from 'node:fs';
import { bannerPublicProjection } from './banner-clear-trace.mjs';
import { LOGICAL_ORIGIN } from './live-transport.mjs';
await import('../../storefront/tests/support/ts-resolver.mjs');
const { decodeStorefrontMenuV11 } = await import('../../storefront/src/source/live/decodeContentV1.ts');
const { adaptStorefront } = await import('../../storefront/src/source/live/adapter.ts');
const raw = JSON.parse(readFileSync(0, 'utf8'));
const result = { public: bannerPublicProjection(raw) };
let decoded;
try {
  decoded = decodeStorefrontMenuV11(raw);
  result.decoder = { accepted: true };
} catch (error) {
  result.decoder = { accepted: false, field: error instanceof Error ? error.message.match(/(?:menu_banner[.\w]*|content_v1[.\w]*)/)?.[0] ?? null : null };
}
if (decoded?.ok) {
  try {
    const banner = adaptStorefront(decoded, LOGICAL_ORIGIN).view.tenant.menuBanner;
    result.adapter = banner ? Object.fromEntries(['image', 'desktopImage', 'enabled', 'layout', 'width', 'height', 'desktopWidth', 'desktopHeight']
      .filter(key => Object.hasOwn(banner, key)).map(key => [key, banner[key]])) : null;
    result.adapterAccepted = true;
  } catch {
    result.adapterAccepted = false;
  }
}
process.stdout.write(JSON.stringify(result));
