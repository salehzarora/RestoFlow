import { expect, type Browser, type Request } from '@playwright/test';
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { API_URL, STOREFRONT_URL } from './service.mjs';
import { LOGICAL_ORIGIN, localMediaTarget } from './live-transport.mjs';

export type PublishedProductImage = {
  variant: string; path: string; width: number; height: number;
  bytes: number; sha256: string; transparent: number; partial: number;
  opaque: number; alphaSha256: string;
};

async function composeSourceComparison(browser: Browser, source: Buffer, crop: Buffer) {
  // Only an isolated, empty canvas page composes the evidence. The menu page,
  // its DOM/CSS and its actual screenshot bytes are never changed.
  const context = await browser.newContext({ serviceWorkers: 'block' });
  await context.route('**/*', route => route.abort('blockedbyclient'));
  try {
    const page = await context.newPage();
    return await page.evaluate(async ({ source64, crop64 }) => {
      const decode = (value: string) => createImageBitmap(new Blob([Uint8Array.from(atob(value), char => char.charCodeAt(0))]));
      const [original, display] = await Promise.all([decode(source64), decode(crop64)]);
      const pad = 24, gap = 32, heading = 118;
      const board = new OffscreenCanvas(display.width * 2 + pad * 2 + gap, display.height + heading + pad);
      const ctx = board.getContext('2d', { willReadFrequently: true })!;
      ctx.fillStyle = '#eeeeee'; ctx.fillRect(0, 0, board.width, board.height);
      ctx.fillStyle = '#111111'; ctx.font = 'bold 20px sans-serif';
      ctx.fillText('Genuine source vs actual menu display', pad, 28);
      ctx.font = '16px sans-serif';
      ctx.fillText('Camera JPEG: downsampled reference', pad, 58);
      ctx.fillText('Actual browser screenshot crop', pad + display.width + gap, 58);
      ctx.font = '14px sans-serif';
      ctx.fillText('Canvas high-quality scaling; no recovered detail', pad, 82);
      ctx.fillText('Copied at 1:1 screenshot pixels; not re-encoded media', pad + display.width + gap, 82);
      ctx.fillText(`Both panels: ${display.width} × ${display.height} physical pixels`, pad, 106);
      ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(original, pad, heading, display.width, display.height);
      ctx.drawImage(display, pad + display.width + gap, heading);
      const check = new OffscreenCanvas(display.width, display.height);
      const checkCtx = check.getContext('2d', { willReadFrequently: true })!;
      checkCtx.drawImage(display, 0, 0);
      const expected = checkCtx.getImageData(0, 0, display.width, display.height).data;
      const actual = ctx.getImageData(pad + display.width + gap, heading, display.width, display.height).data;
      const unchanged = expected.every((value, index) => value === actual[index]);
      const physical = { width: display.width, height: display.height };
      original.close(); display.close();
      const bytes = new Uint8Array(await (await board.convertToBlob({ type: 'image/png' })).arrayBuffer());
      let value = ''; for (const byte of bytes) value += String.fromCharCode(byte);
      return { png64: btoa(value), physical, unchanged };
    }, { source64: source.toString('base64'), crop64: crop.toString('base64') });
  } finally { await context.close(); }
}

/** Actual served menu and image bytes; no fixture DOM, CSS injection or image replacement. */
export async function captureHighResolutionMenu(browser: Browser, slug: string, itemId: string,
  treatment: 'original' | 'experimental-cutout', variants: PublishedProductImage[], out: string, sourceOriginal?: Buffer) {
  expect(slug).toMatch(/^cinematic-[a-z0-9-]+$/);
  expect(itemId).toMatch(/^[0-9a-f-]{36}$/);
  expect(variants).toHaveLength(2);
  if (treatment === 'original') {
    expect(sourceOriginal).toBeDefined();
    expect(createHash('sha256').update(sourceOriginal!).digest('hex'))
      .toBe('81f08a1cb0256293b862db2a661b76f9f9a54067ae5651469a454f7899b50bb3');
  }
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
          objectFit: css.objectFit, objectPosition: css.objectPosition, imageFilter: css.filter, parentFilter: parent.filter,
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
      let sourceComparison = null;
      if (treatment === 'original' && dpr === 2) {
        expect(measured.objectPosition, 'The measured contain image is centered before cropping').toBe('50% 50%');
        const clip = { x: measured.box.x + (measured.box.width - painted.width) / 2,
          y: measured.box.y + (measured.box.height - painted.height) / 2, ...painted };
        expect(clip.x).toBeGreaterThanOrEqual(0); expect(clip.y).toBeGreaterThanOrEqual(0);
        expect(clip.x + clip.width).toBeLessThanOrEqual(measured.viewport.width);
        expect(clip.y + clip.height).toBeLessThanOrEqual(measured.viewport.height);
        const uncovered = await image.evaluate((img, rect) => {
          // Images have pointer-events:none. Their owning slide must be the
          // frontmost hit at the photo corners and center, not a sticky overlay.
          const owner = img.closest('[data-sf-carousel-product]');
          return [[rect.x + 1, rect.y + 1], [rect.x + rect.width - 1, rect.y + 1],
            [rect.x + 1, rect.y + rect.height - 1], [rect.x + rect.width - 1, rect.y + rect.height - 1],
            [rect.x + rect.width / 2, rect.y + rect.height / 2]].every(([x, y]) =>
              document.elementFromPoint(x, y)?.closest('[data-sf-carousel-product]') === owner);
        }, clip);
        expect(uncovered, 'The actual photo crop is visible and unobscured').toBe(true);
        const cropFile = `quality-highres-display-crop-${width}-dpr${dpr}.png`;
        const crop = await page.screenshot({ path: resolve(out, cropFile), clip, scale: 'device' });
        const board = await composeSourceComparison(browser, sourceOriginal!, crop);
        expect(board.unchanged, 'The board retains actual screenshot pixels without scaling').toBe(true);
        expect(Math.abs(board.physical.width - clip.width * dpr)).toBeLessThanOrEqual(2);
        expect(Math.abs(board.physical.height - clip.height * dpr)).toBeLessThanOrEqual(2);
        const file = `quality-highres-source-vs-display-${width}-dpr${dpr}.png`;
        const boardBytes = Buffer.from(board.png64, 'base64');
        writeFileSync(resolve(out, file), boardBytes);
        sourceComparison = { file, cropFile, viewportCssCrop: clip, dpr, actualCropPixels: board.physical,
          actualScreenshotCropSha256: createHash('sha256').update(crop).digest('hex'),
          boardSha256: createHash('sha256').update(boardBytes).digest('hex'),
          sourceSha256: createHash('sha256').update(sourceOriginal!).digest('hex'),
          reference: 'Genuine original JPEG downsampled with Canvas high-quality scaling to actual crop pixel size; no recovered detail',
          display: 'Unmodified actual menu screenshot crop copied 1:1 into board',
          centeredContain: true, fullyVisibleAndUncovered: true, screenshotPixelsUnchanged: true };
      }
      rows.push({ treatment, screenshot, sourceComparison, ...measured, resource: chosen, painted,
        requiredDevicePixels: { width: requiredWidth, height: painted.height * dpr },
        sourcePixelsPerRequiredPixel: chosen!.width / requiredWidth,
        limitedByLargestPublishedVariant: requiredWidth > ordered.at(-1)!.width,
        sourceAspect: chosen!.width / chosen!.height, paintedAspect: painted.width / painted.height,
        browserResponseHashVerified: true, rejectedRequests: rejected, navigations });
    } finally { await context.close(); }
  }
  return rows;
}
