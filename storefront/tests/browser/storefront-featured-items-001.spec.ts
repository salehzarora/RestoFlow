/** Nonempty live-v3 contract → real Home cards/sheet, synthetic loopback only. */
import { test, expect } from '@playwright/test';
import { SYNTH_IDS } from '../support/envelope.mjs';

const BASE = process.env.SF_WEB_ORDER_BASE ?? '';
test.beforeAll(() => {
  expect(new URL(BASE).hostname).toBe('127.0.0.1');
  expect(new URL(BASE).protocol).toBe('http:');
});

for (const locale of ['ar', 'he', 'en']) {
  test(`${locale}: selected image-less cards once, sold-out inert, pointer and keyboard use existing sheet`, async ({ page, context }) => {
    const denied: string[] = [];
    const writes: string[] = [];
    const errors: string[] = [];
    page.on('pageerror', error => errors.push(error.message));
    await context.route('**/*', async route => {
      const request = route.request();
      const url = new URL(request.url());
      if (url.origin !== BASE) {
        denied.push(url.origin);
        await route.abort('blockedbyclient');
        return;
      }
      if (!['GET', 'HEAD'].includes(request.method())) {
        writes.push(request.method());
        await route.abort('blockedbyclient');
        return;
      }
      await route.continue();
    });
    await page.setViewportSize({ width: 390, height: 844 });
    const prefix = locale === 'ar' ? '' : `/${locale}`;
    const response = await page.goto(`${BASE}${prefix}/s/sf-browser-${locale}-featured/menu`);
    expect(response?.status()).toBe(200);
    await expect(page.locator('html')).toHaveAttribute('lang', locale);
    await expect(page.locator('html')).toHaveAttribute('dir', locale === 'en' ? 'ltr' : 'rtl');
    const section = page.locator(`[data-sf-module="sections"]#sf-cat-${SYNTH_IDS.catFood}`);
    const card = (id: string) => section.locator(`[data-sf-item="${id}"]`);
    for (const id of [SYNTH_IDS.burger, SYNTH_IDS.cola, SYNTH_IDS.soldOut]) {
      await expect(card(id)).toHaveCount(1);
      await expect(card(id).locator('[class*="cardMediaFeatured"]')).toHaveCount(1);
      await expect(card(id).locator('img')).toHaveCount(0);
    }
    const ids = await section.locator('[data-sf-item]').evaluateAll(nodes => nodes.map(node => node.getAttribute('data-sf-item')));
    expect(ids).toEqual([SYNTH_IDS.burger, SYNTH_IDS.cola, SYNTH_IDS.soldOut]);
    await expect(card(SYNTH_IDS.soldOut)).toHaveAttribute('aria-disabled', 'true');
    await expect(card(SYNTH_IDS.soldOut)).toHaveAttribute('tabindex', '-1');
    await card(SYNTH_IDS.soldOut).scrollIntoViewIfNeeded();
    const soldOutBox = await card(SYNTH_IDS.soldOut).boundingBox();
    expect(soldOutBox).not.toBeNull();
    await page.mouse.click(soldOutBox!.x + soldOutBox!.width / 2, soldOutBox!.y + soldOutBox!.height / 2);
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await card(SYNTH_IDS.burger).click();
    await expect(page.getByRole('dialog')).toBeVisible();
    await expect(page.getByRole('dialog').getByText('Synth Burger', { exact: true })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await card(SYNTH_IDS.cola).focus();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('dialog')).toBeVisible();
    await expect(page.getByRole('dialog').getByText('Synth Cola', { exact: true })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(card(SYNTH_IDS.cola)).toBeFocused();
    await page.keyboard.press('Space');
    await expect(page.getByRole('dialog')).toBeVisible();
    await page.keyboard.press('Escape');
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
    expect(denied).toEqual([]);
    expect(writes).toEqual([]);
    expect(errors).toEqual([]);
  });
}
