import { expect, type Browser, type Request } from '@playwright/test';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';
import { API_URL, STOREFRONT_URL } from './service.mjs';
import { LOGICAL_ORIGIN, localMediaTarget } from './live-transport.mjs';

export type PublishedProductImage = {
  variant: string; path: string; width: number; height: number;
  bytes: number; sha256: string; transparent: number; partial: number;
  opaque: number; alphaSha256: string;
};

/** Actual served menu and image bytes; no fixture DOM, CSS injection or image replacement. */
export async function captureHighResolutionMenu(browser: Browser, slug: string, itemId: string,
  treatment: 'original' | 'experimental-cutout', variants: PublishedProductImage[], out: string) {
  expect(slug).toMatch(/^cinematic-[a-z0-9-]+$/);
  expect(itemId).toMatch(/^[0-9a-f-]{36}$/);
  expect(variants).toHaveLength(2);
  const rows = [];
  for (const width of [390, 1440]) for (const dpr of [1, 2, 3]) {
    const context = await browser.newContext({ viewport: { width, height: width === 390 ? 844 : 1000 },
      deviceScaleFactor: dpr, reducedMotion: 'reduce', serviceWorkers: 'block', locale: 'ar' });
    let rejected = 0;
    const expectedBytes = new Map<Request, string>();
    const responseHashes = new Map<string, string>();
    const checks: Promise<boolean>[] = [];
    context.on('response', response => {
      const expected = expectedBytes.get(response.request());
      if (expected) checks.push(response.body().then(bytes => {
        const hash = createHash('sha256').update(bytes).digest('hex');
        responseHashes.set(new URL(response.url()).pathname, hash);
        return hash === expected;
      }).catch(() => false));
    });
    await context.route('**/*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (url.origin === LOGICAL_ORIGIN) {
        try {
          const target = localMediaTarget(request.url(), request.method());
          const headers = await request.allHeaders();
          if (request.resourceType() !== 'image' || headers.authorization || headers.apikey || headers.cookie) throw new Error('Media credentials rejected');
          const response = await fetch(target, { redirect: 'error', signal: AbortSignal.timeout(15_000) });
          expect(response.status).toBe(200);
          const body = Buffer.from(await response.arrayBuffer());
          expectedBytes.set(request, createHash('sha256').update(body).digest('hex'));
          // Same guarded logical-to-loopback transport as the existing menu journey.
          const responseHeaders: Record<string, string> = {};
          response.headers.forEach((value, name) => { responseHeaders[name] = value; });
          await route.fulfill({ status: response.status, headers: responseHeaders, body });
        } catch { rejected++; await route.abort('blockedbyclient'); }
        return;
      }
      if (url.protocol !== 'http:' || ![API_URL, STOREFRONT_URL].includes(url.origin) || url.username || url.password) {
        rejected++; await route.abort('blockedbyclient'); return;
      }
      await route.continue();
    });
    try {
      const page = await context.newPage();
      const errors: string[] = [];
      page.on('pageerror', error => errors.push(error.name));
      // Observe normal ISR (60s) and hydration, exactly as the Dashboard menu
      // journey does. Do not alter cache settings or invent a fresh response.
      let hydrated = false, reloadAt = 0, navigations = 0;
      const started = Date.now();
      await expect.poll(async () => {
        if (navigations === 0 || (hydrated && Date.now() >= reloadAt)) {
          const response = await page.goto(`${STOREFRONT_URL}/s/${slug}/menu`, { waitUntil: 'domcontentloaded',
            timeout: Math.min(30_000, Math.max(1, 100_000 - (Date.now() - started))) });
          expect(response?.status()).toBe(200);
          navigations++; hydrated = false; reloadAt = Date.now() + 5000;
        }
        const observed = await page.evaluate(({ id, paths }) => {
          const root = document.querySelector<HTMLElement>('[data-sf-root]');
          const img = document.querySelector<HTMLImageElement>(`[data-sf-carousel-product="${id}"] img`);
          return { hydrated: Boolean(root?.style.getPropertyValue('--bg')),
            currentTreatment: Boolean(img && paths.every(path => img.srcset.includes(path))) };
        }, { id: itemId, paths: variants.map(variant => variant.path) });
        hydrated = observed.hydrated;
        return hydrated && observed.currentTreatment;
      }, { timeout: 100_000, intervals: [100, 250, 500, 1000] }).toBe(true);
      const slide = page.locator(`[data-sf-carousel-product="${itemId}"]`);
      await expect(slide).toHaveCount(1);
      await slide.scrollIntoViewIfNeeded();
      if (await slide.getAttribute('data-position') !== 'active') await slide.click();
      await expect(slide).toHaveAttribute('data-position', 'active');
      const image = slide.locator('img');
      await expect.poll(() => image.evaluate(img => img instanceof HTMLImageElement && img.complete && img.naturalWidth > 0)).toBe(true);
      await page.evaluate(async () => { await document.fonts.ready; await new Promise(requestAnimationFrame); });
      const measured = await image.evaluate((element) => {
        const img = element as HTMLImageElement, box = img.getBoundingClientRect();
        const css = getComputedStyle(img), parent = getComputedStyle(img.parentElement!);
        return { currentPath: new URL(img.currentSrc).pathname, srcset: img.srcset, sizes: img.sizes,
          browserDensityCorrectedNatural: { width: img.naturalWidth, height: img.naturalHeight },
          box: { x: box.x, y: box.y, width: box.width, height: box.height },
          objectFit: css.objectFit, imageFilter: css.filter, parentFilter: parent.filter,
          parentOpacity: parent.opacity, parentTransform: parent.transform,
          viewport: { width: innerWidth, height: innerHeight, dpr: devicePixelRatio },
          overflow: document.documentElement.scrollWidth > innerWidth };
      });
      expect(measured.objectFit).toBe('contain');
      expect(measured.imageFilter).not.toMatch(/(?:^|\s)blur\(/);
      expect(measured.parentFilter).not.toMatch(/(?:^|\s)blur\(/);
      expect(measured.overflow).toBe(false);
      const chosen = variants.find(variant => variant.path === measured.currentPath);
      expect(chosen, 'Current image belongs to the newly published treatment').toBeDefined();
      // naturalWidth can be density-corrected for srcset. Geometry uses the
      // actual decoded response dimensions already verified by publication.
      const scale = Math.min(measured.box.width / chosen!.width, measured.box.height / chosen!.height);
      const painted = { width: chosen!.width * scale, height: chosen!.height * scale };
      const requiredWidth = painted.width * dpr;
      const ordered = [...variants].sort((a, b) => a.width - b.width);
      const expected = ordered.find(variant => variant.width >= requiredWidth - 1) ?? ordered.at(-1)!;
      expect(chosen!.width, 'Selects the smallest sufficient real variant, or the largest available at its native cap').toBe(expected.width);
      for (const variant of variants) expect(measured.srcset).toContain(`${variant.width}w`);
      expect((await Promise.all(checks)).every(Boolean), 'The browser receives the exact public Storage bytes').toBe(true);
      expect(responseHashes.get(measured.currentPath), 'Rendered chosen source equals recorded public image hash').toBe(chosen!.sha256);
      expect(rejected).toBe(0); expect(errors).toEqual([]);
      const screenshot = `quality-highres-${treatment}-${width}-dpr${dpr}.png`;
      await page.screenshot({ path: resolve(out, screenshot) });
      rows.push({ treatment, screenshot, ...measured, resource: chosen, painted,
        requiredDevicePixels: { width: requiredWidth, height: painted.height * dpr },
        sourcePixelsPerRequiredPixel: chosen!.width / requiredWidth,
        limitedByLargestPublishedVariant: requiredWidth > ordered.at(-1)!.width,
        sourceAspect: chosen!.width / chosen!.height, paintedAspect: painted.width / painted.height,
        browserResponseHashVerified: true, rejectedRequests: rejected, navigations });
    } finally { await context.close(); }
  }
  return rows;
}
