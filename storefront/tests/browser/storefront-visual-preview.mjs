// Local Next renderer evidence over the real captured public photograph bytes.
// Never a substitute for the Actions-only Dashboard/publication acceptance run.
import assert from 'node:assert/strict';
import { mkdirSync, writeFileSync } from 'node:fs';
import { isAbsolute, join } from 'node:path';
import { chromium, expect } from '@playwright/test';

const base = new URL(process.env.SF_PREVIEW_BASE_URL ?? 'http://127.0.0.1:47619');
if (base.hostname !== '127.0.0.1' || base.protocol !== 'http:' || base.username || base.password) throw new Error('Local preview only');
const out = process.env.SF_PREVIEW_EVIDENCE_DIR;
if (!out || !isAbsolute(out)) throw new Error('Absolute evidence directory required');
mkdirSync(out, { recursive: true });
const browser = await chromium.launch({ executablePath: process.env.SF_BROWSER_EXECUTABLE || undefined, headless: true });
const records = [];
try {
  for (const width of [390, 1440]) {
    let before = null;
    for (const scene of ['legacy', 'reference']) {
      const context = await browser.newContext({ viewport: { width, height: 1000 }, deviceScaleFactor: 1, reducedMotion: 'reduce' });
      let external = 0;
      await context.route('**/*', route => {
        if (new URL(route.request().url()).origin !== base.origin) { external++; return route.abort('blockedbyclient'); }
        return route.continue();
      });
      const page = await context.newPage();
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      const response = await page.goto(`${base.origin}/s/sf-design-preview/menu?scene=${scene}`, { waitUntil: 'domcontentloaded' });
      assert.equal(response.status(), 200);
      const root = page.locator('[data-sf-root]');
      await expect.poll(() => root.evaluate(el => el.style.getPropertyValue('--bg'))).toBe(scene === 'reference' ? '#151515' : '#151513');
      assert.equal(await root.getAttribute('data-sf-scene'), scene === 'reference' ? 'reference_dark' : null);
      await expect(page.locator('[data-sf-carousel]')).toHaveCount(4);
      for (const section of await page.locator('[data-sf-module="sections"]').all()) {
        await section.scrollIntoViewIfNeeded();
        await expect.poll(() => section.locator('[data-position="active"] img').evaluateAll(images => images.every(img => img.complete && img.naturalWidth > 0))).toBe(true);
      }
      const state = await page.evaluate(async () => {
        await document.fonts.ready;
        const root = document.querySelector('[data-sf-root]');
        const tokens = getComputedStyle(root);
        return {
          products: Array.from(document.querySelectorAll('[data-sf-carousel-product] img'), img => new URL(img.src).pathname),
          background: document.querySelector('main > [aria-hidden="true"] img').getAttribute('src'),
          font: tokens.getPropertyValue('--font'), dim: tokens.getPropertyValue('--menu-image-dim'),
          accent: tokens.getPropertyValue('--acc'), text: tokens.getPropertyValue('--tx'),
          sectionCount: document.querySelectorAll('[data-sf-module="sections"]').length,
          overflow: document.documentElement.scrollWidth > innerWidth,
        };
      });
      assert.equal(state.overflow, false);
      assert.ok(state.products.every(path => path.startsWith('/cinematic-preview/originals/')));
      if (before) assert.deepEqual(state, before, 'Only the scene treatment changes between captures'); else before = state;
      await page.evaluate(() => window.scrollTo(0, 0));
      const filename = `same-source-${scene}-${width}.png`;
      await page.screenshot({ path: join(out, filename), fullPage: true });
      const carousel = page.locator('[data-sf-carousel]').first();
      const previous = await carousel.getAttribute('data-sf-selected');
      await carousel.locator('[data-sf-carousel-next]').click();
      await expect(carousel).not.toHaveAttribute('data-sf-selected', previous);
      assert.equal(external, 0, 'Preview renders from local snapshot assets without API reads');
      assert.deepEqual(errors, []);
      records.push({ scene, width, screenshot: filename, ...state, errors: errors.length, externalRequests: external, carouselNext: true });
      await context.close();
    }
  }
  writeFileSync(join(out, 'preview-results.json'), JSON.stringify({ status: 'PASS', scope: 'local Next dev renderer; captured public bytes; no publication/hosted claim', records }, null, 2));
  console.log(`PASS: ${records.length} same-source menu captures, actual carousel interaction, no external requests`);
} finally { await browser.close(); }
