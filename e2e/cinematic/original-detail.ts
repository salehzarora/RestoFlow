import { expect, type Browser, type Page } from '@playwright/test';
import { createHash } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { API_URL, STOREFRONT_URL, rpc, scope } from './service.mjs';
import { LOGICAL_ORIGIN, localMediaTarget, localProductMediaTarget } from './live-transport.mjs';
import { waitForText } from '../lib/dashboard';

const hash = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
type Image = { item_id: string; url: string; width: number; height: number };

/** Uses only an actually published manifest; no fixture field/SQL/Edge reply injection. */
export async function verifyOriginalDetail(args: {
  page: Page; browser: Browser; fixture: any; token: string; itemId: string;
  selected: Record<string, any>; selectedProof: Record<string, any>;
  click: (name: string) => Promise<void>;
  decode: (page: Page, bytes: Buffer) => Promise<{ width: number; height: number; transparent: number; opaque: number }>;
}) {
  const { page, browser, fixture, token, itemId, selected, selectedProof, click, decode } = args;
  const dir = process.env.CINEMATIC_ARTIFACT_DIR!;
  let stage = 'before-publication';
  const receipt: Record<string, unknown> = { status: 'FAIL', failedStage: stage, data: 'synthetic isolated CI; actual Auth/Storage/Edge and shipped UI' };
  const readSelection = async () => (await rpc(fixture, token, 'get_storefront_product_original_v1', { ...scope(fixture.ownerA), p_item_id: itemId })).data;
  try {
    const before = await rpc(fixture, null, 'storefront_menu_v10', { p_slug: fixture.ownerA.slug });
    expect(before.status).toBe(200); expect(before.data.ok).toBe(true);
    expect(before.data.product_original_images_v1.find((row: Image) => row.item_id === itemId), 'Fresh source has no independently published Original').toBeUndefined();
    stage = 'explicit-dashboard-original-publication';
    const reply = page.waitForResponse(response => {
      if (response.request().method() !== 'POST' || response.url() !== API_URL + '/functions/v1/storefront-media-publish') return false;
      const body = response.request().postDataJSON(); return body.slot === 'product' && body.variant === 'w960';
    });
    await click('نشر الأصل للتفاصيل');
    const response = await reply;
    expect(response.status()).toBe(200);
    const published = await response.json(); expect(published.ok).toBe(true); expect(published.status).toBe('published');
    expect(published.recipe).toBe('storefront-media-c4');
    stage = 'dashboard-original-published-status';
    // CanvasKit Text is exposed through aria-labels, not DOM textContent.
    // Use the same real semantics reader as the existing publication journey.
    await waitForText(page, 'تم نشر الأصل للتفاصيل.');
    stage = 'same-selection-and-public-readback';
    const current = await readSelection();
    for (const key of ['source_key', 'source_snapshot', 'selection_version', 'selected_derivative_id']) expect(current[key], key + ' unchanged').toEqual(selectedProof[key]);
    const after = await rpc(fixture, null, 'storefront_menu_v10', { p_slug: fixture.ownerA.slug });
    expect(after.status).toBe(200); expect(after.data.ok).toBe(true);
    const original: Image = after.data.product_original_images_v1.find((row: Image) => row.item_id === itemId);
    expect(original).toBeDefined(); expect(original.url).not.toBe(selected.w960_url);
    expect(after.data.product_images_v1.find((row: Image) => row.item_id === itemId)).toEqual(selected);
    stage = 'decode-real-public-original';
    const originalResponse = await fetch(localProductMediaTarget(original.url), { redirect: 'error', signal: AbortSignal.timeout(15000) });
    expect(originalResponse.status).toBe(200); expect(originalResponse.headers.get('content-type')).toContain('image/webp');
    const originalBytes = Buffer.from(await originalResponse.arrayBuffer()), alpha = await decode(page, originalBytes);
    expect([alpha.width, alpha.height]).toEqual([original.width, original.height]);
    expect(Math.max(alpha.width, alpha.height)).toBeLessThanOrEqual(960); expect(originalBytes.length).toBeLessThanOrEqual(524288);
    expect(alpha.transparent, 'Original source background remains opaque').toBe(0);
    expect(alpha.opaque).toBe(alpha.width * alpha.height);
    const selectedResponse = await fetch(localProductMediaTarget(selected.w960_url), { redirect: 'error' });
    expect(selectedResponse.status).toBe(200);
    const selectedBytes = Buffer.from(await selectedResponse.arrayBuffer()), cutout = await decode(page, selectedBytes);
    expect(cutout.transparent, 'The selected slider derivative is genuinely cut out').toBeGreaterThan(0);
    expect(hash(originalBytes)).not.toBe(hash(selectedBytes));
    receipt.publicOriginal = { path: original.url, bytes: originalBytes.length, sha256: hash(originalBytes), ...alpha };
    receipt.publicSelected = { path: selected.w960_url, bytes: selectedBytes.length, sha256: hash(selectedBytes), ...cutout };
    stage = 'real-storefront-reload-and-open';
    const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, serviceWorkers: 'block', reducedMotion: 'reduce' });
    const menu = await context.newPage(); let denied = 0;
    await context.route('**/*', async route => {
      const request = route.request(), url = new URL(request.url());
      if (url.origin === LOGICAL_ORIGIN) {
        try {
          const target = localMediaTarget(request.url(), request.method()), headers = await request.allHeaders();
          if (request.resourceType() !== 'image' || headers.authorization || headers.apikey || headers.cookie) throw new Error('credentialed image');
          const actual = await fetch(target, { redirect: 'error', signal: AbortSignal.timeout(15000) });
          const body = Buffer.from(await actual.arrayBuffer());
          const responseHeaders: Record<string, string> = {};
          actual.headers.forEach((value, name) => { responseHeaders[name] = value; });
          await route.fulfill({ status: actual.status, headers: responseHeaders, body });
        } catch { denied++; await route.abort('blockedbyclient'); }
      } else if (url.origin === STOREFRONT_URL && ['GET', 'HEAD'].includes(request.method())) await route.continue();
      else { denied++; await route.abort('blockedbyclient'); }
    });
    try {
      await expect.poll(async () => {
        await menu.goto(STOREFRONT_URL + '/ar/s/' + fixture.ownerA.slug + '/menu', { waitUntil: 'domcontentloaded' });
        const image = menu.locator(`[data-sf-carousel-product="${itemId}"] img`);
        return await image.count() === 1 && (await image.getAttribute('srcset') ?? '').includes(selected.w960_url)
          && (await menu.content()).includes(original.url);
      }, { timeout: 100000, intervals: [250, 500, 1000] }).toBe(true);
      const slide = menu.locator(`[data-sf-carousel-product="${itemId}"]`);
      await slide.scrollIntoViewIfNeeded();
      if (await slide.getAttribute('data-position') !== 'active') await slide.click();
      await expect(slide).toHaveAttribute('data-position', 'active');
      const sliderImage = slide.locator('img');
      await expect.poll(() => sliderImage.evaluate(img => img instanceof HTMLImageElement && img.complete && img.naturalWidth > 0)).toBe(true);
      const observe = async (selector: string) => menu.locator(selector).evaluate(node => {
        const img = node as HTMLImageElement, rect = img.getBoundingClientRect();
        return { currentSrc: img.currentSrc, naturalWidth: img.naturalWidth, naturalHeight: img.naturalHeight, rendered: { width: rect.width, height: rect.height, dpr: devicePixelRatio }, objectFit: getComputedStyle(img).objectFit };
      });
      const slider = await observe(`[data-sf-carousel-product="${itemId}"] img`);
      expect([selected.w480_url, selected.w960_url]).toContain(new URL(slider.currentSrc).pathname);
      await menu.screenshot({ path: resolve(dir, 'original-detail-same-product-slider.png') });
      await slide.click();
      const detail = menu.locator('[data-sf-sheet="product"] img[data-sf-detail-image="original"]');
      await expect(detail).toBeVisible();
      await expect.poll(() => detail.evaluate(img => (img as HTMLImageElement).complete && (img as HTMLImageElement).naturalWidth > 0)).toBe(true);
      const details = await observe('[data-sf-sheet="product"] img[data-sf-detail-image="original"]');
      expect(new URL(details.currentSrc).pathname).toBe(original.url); expect(details.objectFit).toBe('contain');
      expect(new URL(details.currentSrc).pathname).not.toBe(new URL(slider.currentSrc).pathname);
      expect([details.naturalWidth, details.naturalHeight]).toEqual([original.width, original.height]);
      await menu.screenshot({ path: resolve(dir, 'original-detail-same-product-details.png') });
      await menu.keyboard.press('Escape'); await expect(menu.locator('[data-sf-sheet="product"]')).toHaveCount(0);
      expect((await observe(`[data-sf-carousel-product="${itemId}"] img`)).currentSrc).toBe(slider.currentSrc);
      await slide.click(); await expect(detail).toBeVisible();
      expect(await detail.getAttribute('src')).toBe(details.currentSrc);
      for (const key of ['selection_version', 'selected_derivative_id']) expect((await readSelection())[key]).toEqual(selectedProof[key]);
      expect(denied).toBe(0); receipt.browser = { slider, details, sameProduct: itemId, selectionPreservedAfterReopen: true, denied };
    } finally { await context.close(); }
    receipt.status = 'ORIGINAL_DETAIL_IMAGE_ACCEPTED'; receipt.failedStage = null;
  } finally {
    if (receipt.status !== 'ORIGINAL_DETAIL_IMAGE_ACCEPTED') {
      receipt.failedStage = stage;
      await page.screenshot({ path: resolve(dir, 'original-detail-dashboard-failure.png') }).catch(() => {});
    }
    writeFileSync(resolve(dir, 'original-detail-result.json'), JSON.stringify(receipt, null, 2));
  }
}
