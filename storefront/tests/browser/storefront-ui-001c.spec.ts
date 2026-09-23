// STOREFRONT-UI-001 Phase C evidence.
//
//   G15/G16  search results and no-results, measured
//   G17/G18  product sheet: blocked-from-open vs error-after-submit
//   H07      the search initial six
//   X06      `?item=` deep link skips the intro, opens the sheet, Back closes it
//   X12      focus trap, Esc, focus restore
//   CART     add -> dock appears, count and SUBTOTAL correct, survives a reload
//
// Runs against the SHIPPED build (`npm run build`), not an evidence build: none
// of this needs a demo scenario route.
import { test, expect, type Page } from '@playwright/test';
import { spawn, type ChildProcess } from 'node:child_process';
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const STOREFRONT = path.resolve(process.cwd());
const PORT = Number(process.env.STOREFRONT_C_PORT ?? 4407);
const BASE = `http://127.0.0.1:${PORT}`;
const SHOTS = process.env.SF_C_SHOT_DIR ?? path.join(STOREFRONT, 'ui001c-evidence');
const RESULTS: Record<string, unknown> = {};

const SLUG = 'maps-burger';
const MENU = `/s/${SLUG}/menu`;
const SEARCH = `/s/${SLUG}/search`;
const CART_KEY = `sf:v1:cart:${SLUG}`;

let server: ChildProcess;

test.beforeAll(async () => {
  mkdirSync(SHOTS, { recursive: true });
  server = spawn(process.execPath, ['scripts/serve-out.mjs'], {
    cwd: STOREFRONT,
    env: { ...process.env, PORT: String(PORT) },
    stdio: 'ignore',
  });
  const deadline = Date.now() + 20_000;
  for (;;) {
    try {
      if ((await fetch(`${BASE}/healthz.json`)).ok) break;
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error('serve-out.mjs did not start');
    await new Promise((r) => setTimeout(r, 200));
  }
  const probe = await fetch(`${BASE}${SEARCH}`);
  if (!probe.ok) throw new Error(`the search route is missing: ${probe.status}`);
});

test.afterAll(() => {
  server?.kill();
  writeFileSync(path.join(SHOTS, 'results.json'), `${JSON.stringify(RESULTS, null, 2)}\n`, 'utf8');
});

/** A phone viewport, the size every canonical screenshot was taken at. */
async function phone(page: Page) {
  await page.setViewportSize({ width: 390, height: 844 });
}

/** Mark the intro as seen so a menu load is not bounced. */
async function seen(page: Page) {
  await page.addInitScript((slug) => {
    try {
      sessionStorage.setItem(`sf:v1:seen:${slug}`, '1');
    } catch {
      /* ignore */
    }
  }, SLUG);
}

// ----------------------------------------------------------------- G15 / G16

test('G15 search renders 78px rows with a 56px thumb, and the price is NOT accent', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}${SEARCH}`);

  // The field is autofocused, so typing needs no click.
  await expect(page.locator('input[type="search"]')).toBeFocused();
  await page.keyboard.type('برجر');

  const rows = page.locator('[data-sf-item]');
  await expect(rows).toHaveCount(4);

  const rowBox = await rows.first().boundingBox();
  const thumbBox = await rows.first().locator('span').first().boundingBox();
  expect(Math.round(rowBox!.height)).toBe(78);
  expect(Math.round(thumbBox!.width)).toBe(56);
  expect(Math.round(thumbBox!.height)).toBe(56);

  // The price ink must be the primary ink, not the accent: reusing home's
  // <Price> would have made it accent and silently diverged from G15.
  const priceColour = await rows.first().locator('span[dir="ltr"]').last()
    .evaluate((el) => getComputedStyle(el).color);
  const accent = await page.locator('[data-sf-item]').first()
    .evaluate((el) => getComputedStyle(el).getPropertyValue('--acct').trim());
  RESULTS.g15 = { rowHeight: rowBox!.height, thumb: thumbBox!.width, priceColour, accent };
  expect(priceColour).not.toBe(accent);

  await page.screenshot({ path: path.join(SHOTS, 'G15-search-results.png') });
});

test('G16 no-results shows the query as TEXT, with no icon tile and no action', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}${SEARCH}`);
  await page.keyboard.type('سوشي');

  await expect(page.locator('[data-sf-item]')).toHaveCount(0);
  const title = page.getByText('سوشي', { exact: false }).first();
  await expect(title).toBeVisible();

  // The query is rendered as text inside a <bdi>, never as markup.
  const bdi = page.locator('bdi');
  await expect(bdi).toHaveCount(1);
  await expect(bdi).toHaveText('سوشي');

  // The canonical screenshot has NO icon tile and NO action button: the empty
  // state is a title and a body, nothing else.
  const region = page.locator('bdi').locator('xpath=ancestor::div[1]');
  await expect(region.locator('button')).toHaveCount(0);
  await expect(region.locator('svg')).toHaveCount(0);

  await page.screenshot({ path: path.join(SHOTS, 'G16-search-no-results.png') });
});

test('an injected query is never interpreted as markup', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}${SEARCH}`);
  await page.keyboard.type('<img src=x onerror=alert(1)>');
  await expect(page.locator('bdi img')).toHaveCount(0);
  await expect(page.locator('bdi')).toContainText('<img');
});

test('H07 an empty query shows exactly six rows, sold-out included and disabled', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}${SEARCH}`);
  const rows = page.locator('[data-sf-item]');
  await expect(rows).toHaveCount(6);

  const disabled = page.locator('[data-sf-item][aria-disabled="true"]');
  await expect(disabled).toHaveCount(1);
  await expect(disabled).toHaveAttribute('tabindex', '-1');

  // Clearing a typed query restores the initial six AND returns focus.
  await page.keyboard.type('برجر');
  await expect(rows).toHaveCount(4);
  await page.locator('[role="search"] button').click();
  await expect(rows).toHaveCount(6);
  await expect(page.locator('input[type="search"]')).toBeFocused();
  RESULTS.h07 = { initial: 6, soldOutRows: 1 };
});

test('the clear button appears whenever there is TEXT, not only non-blank text', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}${SEARCH}`);
  const clear = page.locator('[role="search"] button');
  await expect(clear).toHaveCount(0);
  await page.keyboard.type('   ');
  // The prototype hides it here, stranding characters with no way to clear
  // them. That defect is deliberately not reproduced.
  await expect(clear).toHaveCount(1);
});

test('the search screen shows NO cart dock, even with a cart', async ({ page }) => {
  await phone(page);
  await page.addInitScript(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 2, selections: {}, note: '' }],
    })],
  );
  await page.goto(`${BASE}${SEARCH}`);
  await expect(page.locator('[data-sf-dock]')).toHaveCount(0);
});

// ----------------------------------------------------------------- G17 / G18

test('G17 the CTA is blocked from the moment the sheet opens, with NO alert yet', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=2`);

  const sheet = page.locator('[data-sf-sheet="product"]');
  await expect(sheet).toBeVisible();
  const cta = page.locator('[data-sf-cta="product"]');

  // Blocked immediately: item 2 has a required `bun` group and nothing chosen.
  await expect(cta).toHaveAttribute('aria-disabled', 'true');
  // ...but NOTHING has been submitted, so there is no alert and no red badge.
  await expect(sheet.locator('[role="alert"]')).toHaveCount(0);

  const ctaBg = await cta.evaluate((el) => getComputedStyle(el).backgroundImage);
  expect(ctaBg).toBe('none'); // the grey blocked bed, not the gradient

  RESULTS.g17 = { blockedOnOpen: true, alertsOnOpen: 0 };
  await page.screenshot({ path: path.join(SHOTS, 'G17-product-blocked.png') });
});

test('G18 tapping a blocked CTA does NOT close the sheet: it alerts and stays', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=2`);

  const sheet = page.locator('[data-sf-sheet="product"]');
  const cta = page.locator('[data-sf-cta="product"]');

  // THE CTA IS aria-disabled BUT OPERABLE, which is the whole point: tapping it
  // is how the visitor learns WHICH group is unmet (SCREEN_MAP.json:174). Only
  // the native `disabled` attribute stops a real tap, and this button must not
  // have it - asserted here so `force` below cannot hide a genuine defect.
  await expect(cta).not.toHaveAttribute('disabled', /.*/);
  await expect(cta).toHaveJSProperty('disabled', false);
  // Playwright's actionability check treats aria-disabled as "not enabled", so
  // the real user gesture has to be forced past that tooling opinion.
  await cta.click({ force: true });

  await expect(sheet).toBeVisible(); // still open
  const alert = sheet.locator('[role="alert"]');
  await expect(alert).toHaveCount(1);
  // The alert belongs to the FIRST unmet group.
  await expect(sheet.locator('[data-sf-group="bun"] [role="alert"]')).toHaveCount(1);
  // Nothing was added.
  const stored = await page.evaluate((k) => localStorage.getItem(k), CART_KEY);
  expect(stored).toBeNull();

  RESULTS.g18 = { sheetStayedOpen: true, alerts: 1 };
  await page.screenshot({ path: path.join(SHOTS, 'G18-product-required-missing.png') });
});

test('the live total is unit x quantity in integer minor units', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=1`); // base 5500
  const sheet = page.locator('[data-sf-sheet="product"]');
  const price = page.locator('[data-sf-cta="product"] span[dir="ltr"]');

  await expect(price).toHaveText('₪55');
  await sheet.locator('[data-sf-group="bun"] [role="radio"]').nth(1).click(); // brioche +500
  await expect(price).toHaveText('₪60');
  await sheet.locator('[data-sf-group="extras"] [role="checkbox"]').first().click(); // cheese +600
  await expect(price).toHaveText('₪66');

  // Quantity multiplies the whole unit, not just the base.
  await sheet.locator('[data-sf-step="inc"]').click();
  await expect(sheet.locator('[aria-live="polite"]')).toHaveText('2');
  await expect(price).toHaveText('₪132');

  // ...and the BASE price beside the name never moves.
  await expect(sheet.locator('h2 + span')).toHaveText('₪55');

  // The stepper clamps at 1: decrementing twice cannot reach 0.
  await sheet.locator('[data-sf-step="dec"]').click();
  await expect(sheet.locator('[aria-live="polite"]')).toHaveText('1');
  await expect(sheet.locator('[data-sf-step="dec"]')).toBeDisabled();
  RESULTS.pricing = { unitMinor: 6600, qty: 2, totalMinor: 13200 };
});

test('a single-select group REPLACES, a multi-select toggles, and the cap refuses with a toast', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=1`);
  const sheet = page.locator('[data-sf-sheet="product"]');

  const buns = sheet.locator('[data-sf-group="bun"] [role="radio"]');
  await buns.nth(0).click();
  await expect(buns.nth(0)).toHaveAttribute('aria-checked', 'true');
  await buns.nth(1).click();
  await expect(buns.nth(0)).toHaveAttribute('aria-checked', 'false');
  await expect(buns.nth(1)).toHaveAttribute('aria-checked', 'true');

  const extras = sheet.locator('[data-sf-group="extras"] [role="checkbox"]');
  await extras.nth(0).click();
  await expect(extras.nth(0)).toHaveAttribute('aria-checked', 'true');
  await extras.nth(0).click();
  await expect(extras.nth(0)).toHaveAttribute('aria-checked', 'false');

  // extras is capped at 3. A fourth tap is REFUSED and answered with a toast.
  for (const i of [0, 1, 2]) await extras.nth(i).click();
  await extras.nth(3).click();
  await expect(extras.nth(3)).toHaveAttribute('aria-checked', 'false');
  // Targeted at the toast specifically: the announcement strip is also a
  // role="status", so a bare role query matches two live regions.
  await expect(page.locator('[data-sf-toast="product"]')).toContainText('3');
  RESULTS.maxReached = true;
});

// ------------------------------------------------------------------ X06 / X12

test('X06 an ?item= deep link SKIPS the intro, opens the sheet, and Back closes it', async ({ page }) => {
  await phone(page);
  // No `seen` flag: this is a genuine first visit to the intro route.
  await page.goto(`${BASE}/s/${SLUG}?item=1`);

  // The intro is skipped and the query is carried to the menu.
  await page.waitForURL(/\/s\/maps-burger\/menu\?item=1$/);
  const sheet = page.locator('[data-sf-sheet="product"]');
  await expect(sheet).toBeVisible();

  await page.goBack();
  await expect(sheet).toHaveCount(0);
  RESULTS.x06 = { skippedIntro: true, backClosed: true };
});

test('opening from a card pushes ONE history entry, and closing returns to the menu', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}`);

  await page.locator('[data-sf-item]').first().click();
  const sheet = page.locator('[data-sf-sheet="product"]');
  await expect(sheet).toBeVisible();
  expect(page.url()).toContain('?item=');

  // The close button and Back agree: one entry, so one Back returns to a clean
  // menu URL rather than leaving the site or stacking entries.
  await page.locator('[data-sf-sheet="product"] button').first().click();
  await expect(sheet).toHaveCount(0);
  await expect(page).toHaveURL(new RegExp(`${MENU}$`));
});

test('an ?item= that names nothing, or a sold-out item, opens no sheet and does not crash', async ({ page }) => {
  await phone(page);
  await seen(page);
  for (const bad of ['nope', '../etc', '5']) {
    await page.goto(`${BASE}${MENU}?item=${encodeURIComponent(bad)}`);
    await expect(page.locator('[data-sf-sheet="product"]')).toHaveCount(0);
    // The menu itself still renders.
    await expect(page.locator('[data-sf-item]').first()).toBeVisible();
  }
});

test('X12 the sheet traps focus, closes on Esc, and restores focus to the opener', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}`);

  const opener = page.locator('[data-sf-item]').first();
  await opener.focus();
  await page.keyboard.press('Enter'); // role="button" must answer Enter

  const sheet = page.locator('[data-sf-sheet="product"]');
  await expect(sheet).toBeVisible();

  // Tab many times: focus must never leave the sheet.
  let escaped = 0;
  for (let i = 0; i < 25; i += 1) {
    await page.keyboard.press('Tab');
    const inside = await page.evaluate(() => {
      const s = document.querySelector('[data-sf-sheet="product"]');
      return s !== null && s.contains(document.activeElement);
    });
    if (!inside) escaped += 1;
  }
  expect(escaped).toBe(0);

  await page.keyboard.press('Escape');
  await expect(sheet).toHaveCount(0);

  // Focus returns to the card that opened it.
  const restored = await page.evaluate(
    () => document.activeElement?.getAttribute('data-sf-item') ?? null,
  );
  expect(restored).not.toBeNull();
  RESULTS.x12 = { tabsTried: 25, escapes: 0, focusRestored: restored };
});

// ------------------------------------------------------------------- the cart

test('adding an item makes the dock appear with the right count and SUBTOTAL, and it persists', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=7`); // fries 2200, one required sauce group

  const sheet = page.locator('[data-sf-sheet="product"]');
  await sheet.locator('[data-sf-group="sauce"] [role="radio"]').last().click(); // ranch +200
  await expect(page.locator('[data-sf-cta="product"] span[dir="ltr"]')).toHaveText('₪24');
  await page.locator('[data-sf-cta="product"]').click();

  await expect(sheet).toHaveCount(0);
  const dock = page.locator('[data-sf-dock="live"]');
  await expect(dock).toBeVisible();
  await expect(dock.locator('span[dir="ltr"]')).toHaveText('₪24');

  // It is really persisted, under the approved key, with no extra fields.
  const raw = await page.evaluate((k) => localStorage.getItem(k), CART_KEY);
  expect(raw).not.toBeNull();
  const parsed = JSON.parse(raw!);
  expect(Object.keys(parsed).sort()).toEqual(['lines', 'menuVersion', 'schema', 'slug']);
  expect(Object.keys(parsed.lines[0]).sort()).toEqual([
    'itemId', 'lineId', 'note', 'qty', 'selections',
  ]);

  // ...and it survives a reload, which is the whole point of persisting it.
  await page.reload();
  await expect(page.locator('[data-sf-dock="live"]')).toBeVisible();
  await expect(page.locator('[data-sf-dock="live"] span[dir="ltr"]')).toHaveText('₪24');

  RESULTS.cart = { stored: parsed, subtotal: '₪24' };
  await page.screenshot({ path: path.join(SHOTS, 'CART-dock-live.png') });
});

test('the dock count BUMPS on an add, and the bump keyframe really resolves', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.addInitScript(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 1, selections: {}, note: '' }],
    })],
  );
  // Item 9 offers no modifier groups at all, so its CTA is addable immediately
  // - which is what lets this test measure the bump rather than the block.
  await page.goto(`${BASE}${MENU}?item=9`);

  const count = page.locator('[data-sf-dock="live"] [class*="dockCount"]');
  const cta = page.locator('[data-sf-cta="product"]');
  await expect(cta).toHaveAttribute('aria-disabled', 'false');

  // Catch the animation while it is running: it lasts 200ms by design.
  const [animation] = await Promise.all([
    page.locator('[data-sf-dock="live"] [class*="dockCount"]').evaluate(
      (el) =>
        new Promise<string>((resolve) => {
          const timer = setTimeout(() => resolve('none'), 3000);
          const tick = setInterval(() => {
            const name = getComputedStyle(el).animationName;
            if (name && name !== 'none') {
              clearInterval(tick);
              clearTimeout(timer);
              resolve(name);
            }
          }, 10);
        }),
    ),
    cta.click(),
  ]);

  // The name must RESOLVE to a real keyframe: a CSS-module keyframe referenced
  // from another module file compiles to a name nothing defines, and would
  // silently animate nothing.
  expect(animation).toMatch(/sfBump/);
  const defined = await page.evaluate((name) => {
    for (const sheet of Array.from(document.styleSheets)) {
      let rules: CSSRuleList;
      try {
        rules = sheet.cssRules;
      } catch {
        continue;
      }
      for (const rule of Array.from(rules)) {
        if (rule instanceof CSSKeyframesRule && rule.name === name) return true;
      }
    }
    return false;
  }, animation);
  expect(defined, `${animation} is consumed but not defined`).toBe(true);

  await expect(count).toHaveText('2');
  RESULTS.bump = { animation, defined };
});

test('a corrupt stored cart is discarded silently and the dock stays hidden', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.addInitScript(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, '{"schema":1,"slug":"maps-burger","menuVersion":"mb-1","lines":[{"lineId":"bad id","itemId":"1","qty":999,"selections":{},"note":""}]}'],
  );
  await page.goto(`${BASE}${MENU}`);
  await expect(page.locator('[data-sf-item]').first()).toBeVisible();
  await expect(page.locator('[data-sf-dock="live"]')).toHaveCount(0);
});

test('the dock CTA LINKS to the cart route, now that Phase D has built it', async ({ page }) => {
  // In Phase C this CTA was disabled because its only approved destination did
  // not exist, and a control that looks active and goes nowhere is a lie. The
  // route exists now, so the assertion moves with the behaviour rather than
  // being deleted: what it pins is that the control is honest either way.
  await phone(page);
  await seen(page);
  await page.addInitScript(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 1, selections: {}, note: '' }],
    })],
  );
  await page.goto(`${BASE}${MENU}`);
  const cta = page.locator('[data-sf-dock-cta="cart"]');
  await expect(cta).toHaveCount(1);
  await expect(cta).toHaveAttribute('href', `/s/${SLUG}/cart`);
  // A real link, not a button pretending: it must open in a new tab too.
  expect(await cta.evaluate((el) => el.tagName)).toBe('A');
  await cta.click();
  await page.waitForURL(`**/s/${SLUG}/cart`);
  await expect(page.locator('[data-sf-screen="cart"]')).toBeVisible();
});

test('REGRESSION: the fixed scrim fills the VIEWPORT, not a container-query box', async ({ page }) => {
  // An ancestor with `container-type`, a `transform` or a `filter` becomes the
  // containing block for `position: fixed` descendants. `.shell` carries
  // `container-type: inline-size` for the wide layout, so a sheet rendered
  // inside it would be sized and positioned against .shell instead of the
  // viewport - the scrim would stop short and the sheet could be clipped.
  // The sheet is therefore mounted OUTSIDE .shell; this proves it stays there.
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=1`);

  const geometry = await page.evaluate(() => {
    const scrim = document.querySelector('[class*="scrim"]')!;
    const rect = scrim.getBoundingClientRect();
    let ancestor: string | null = null;
    let node = scrim.parentElement;
    while (node) {
      const cs = getComputedStyle(node);
      if ((cs.containerType && cs.containerType !== 'normal') ||
          cs.transform !== 'none' || cs.filter !== 'none') {
        ancestor = `${node.tagName}.${(node.getAttribute('class') ?? '').slice(0, 40)}`;
        break;
      }
      node = node.parentElement;
    }
    return {
      rect: { x: rect.x, y: rect.y, w: rect.width, h: rect.height },
      viewport: { w: window.innerWidth, h: window.innerHeight },
      containingAncestor: ancestor,
    };
  });

  expect(geometry.containingAncestor,
    'a container/transform/filter ancestor would trap the fixed sheet').toBeNull();
  expect(geometry.rect).toEqual({
    x: 0, y: 0, w: geometry.viewport.w, h: geometry.viewport.h,
  });
  RESULTS.fixedContainment = geometry;
});

test('REGRESSION: the max-reached toast is ON TOP of the open sheet, not behind it', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=1`);

  const extras = page.locator('[data-sf-group="extras"] [role="checkbox"]');
  for (const i of [0, 1, 2]) await extras.nth(i).click();
  await extras.nth(3).click(); // refused: the group is capped at 3

  const toast = page.locator('[data-sf-toast="product"]');
  await expect(toast).toBeVisible();

  // Visible is not enough - it has to be ON TOP. At the token z-index of 26 it
  // sat behind the sheet at 40 and the visitor was refused with an explanation
  // they could not see.
  //
  // `elementFromPoint` cannot answer this: the toast is `pointer-events: none`
  // by design, so hit testing skips it whether it is on top or not. The paint
  // order is decided instead by comparing z-index WITHIN A SHARED STACKING
  // CONTEXT, so the check first proves the two share one - otherwise the
  // numbers would not be comparable at all.
  const stack = await page.evaluate(() => {
    const formsStackingContext = (el: Element): boolean => {
      const cs = getComputedStyle(el);
      if (cs.position !== 'static' && cs.zIndex !== 'auto') return true;
      if (cs.transform !== 'none' || cs.filter !== 'none' || cs.perspective !== 'none') return true;
      if (cs.isolation === 'isolate' || cs.mixBlendMode !== 'normal') return true;
      if (cs.contain.includes('paint') || cs.contain.includes('layout')) return true;
      if (cs.willChange.includes('transform') || cs.willChange.includes('opacity')) return true;
      if (cs.position === 'fixed' || cs.position === 'sticky') return true;
      return Number(cs.opacity) < 1;
    };
    const rootOf = (el: Element): string => {
      let node = el.parentElement;
      while (node) {
        if (formsStackingContext(node)) {
          return `${node.tagName}.${(node.getAttribute('class') ?? '').slice(0, 40)}`;
        }
        node = node.parentElement;
      }
      return 'ROOT';
    };
    const toast = document.querySelector('[data-sf-toast="product"]')!;
    const sheet = document.querySelector('[data-sf-sheet="product"]')!;
    const tr = toast.getBoundingClientRect();
    const sr = sheet.getBoundingClientRect();
    return {
      toastZ: Number(getComputedStyle(toast).zIndex),
      sheetZ: Number(getComputedStyle(sheet).zIndex),
      toastRoot: rootOf(toast),
      sheetRoot: rootOf(sheet),
      // They must actually overlap, or the comparison proves nothing.
      overlaps: tr.x < sr.x + sr.width && tr.x + tr.width > sr.x &&
                tr.y < sr.y + sr.height && tr.y + tr.height > sr.y,
    };
  });

  expect(stack.overlaps, 'the toast does not overlap the sheet, so this proves nothing').toBe(true);
  expect(stack.toastRoot, 'the two are in different stacking contexts, so z-index cannot order them')
    .toBe(stack.sheetRoot);
  expect(stack.toastZ, 'the toast must paint above the sheet').toBeGreaterThan(stack.sheetZ);
  RESULTS.toastOverSheet = stack;
  await page.screenshot({ path: path.join(SHOTS, 'TOAST-over-sheet.png') });
});

test('REGRESSION: the drag handle is centred in RTL, not offset by its own width', async ({ page }) => {
  // `inset-inline-start: 50%` + `transform: translateX(-50%)` mixes a logical
  // offset with a PHYSICAL translate, which does not mirror: measured 40px -
  // exactly the handle's width - off centre in RTL.
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=1`);
  const offset = await page.evaluate(() => {
    const h = document.querySelector('[class*="handle"]')!.getBoundingClientRect();
    const m = document.querySelector('[class*="media"]')!.getBoundingClientRect();
    return Math.round(h.x + h.width / 2 - (m.x + m.width / 2));
  });
  expect(Math.abs(offset), `handle is ${offset}px off centre`).toBeLessThanOrEqual(1);
  RESULTS.handleOffset = offset;
});

test('REGRESSION: a ?line= naming ANOTHER item\'s line cannot rewrite it', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.addInitScript(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 3, selections: { bun: ['classic'] }, note: '' }],
    })],
  );
  // item 9 has no groups; the line belongs to item 1.
  await page.goto(`${BASE}${MENU}?item=9&line=l1aaa`);
  await expect(page.locator('[data-sf-sheet="product"]')).toBeVisible();
  // It must be an ADD, not an edit: the stepper starts at 1, not at the
  // other line's quantity of 3.
  await expect(page.locator('[data-sf-sheet="product"] [aria-live="polite"]')).toHaveText('1');
  await page.locator('[data-sf-cta="product"]').click();

  const after = JSON.parse(await page.evaluate((k) => localStorage.getItem(k), CART_KEY) as string);
  expect(after.lines).toHaveLength(2);
  const original = after.lines.find((l: { lineId: string }) => l.lineId === 'l1aaa');
  expect(original.itemId, "item 1's line was rewritten to another product").toBe('1');
  expect(original.qty).toBe(3);
});

test('REGRESSION: closing unmounts the sheet at once, so it cannot add twice', async ({ page }) => {
  await phone(page);
  await seen(page);
  await page.goto(`${BASE}${MENU}?item=9`);
  const cta = page.locator('[data-sf-cta="product"]');
  await cta.click();
  await expect(page.locator('[data-sf-sheet="product"]')).toHaveCount(0);

  const stored = JSON.parse(await page.evaluate((k) => localStorage.getItem(k), CART_KEY) as string);
  expect(stored.lines).toHaveLength(1);
});

// --------------------------------------------------------------- the wide seam

/** The wide container, where the dock is display:none and the aside is it. */
async function wide(page: Page) {
  await page.setViewportSize({ width: 1280, height: 900 });
}

test('R2/WIDE: the SERVED BYTES carry no cart, and the aside becomes one only after hydration', async ({ page }) => {
  // Phase C kept the wide aside inert because the cart route did not exist.
  // Phase D makes it functional, and the rule that mattered does NOT relax: a
  // static document is byte-identical for every visitor, so any cart in it is
  // a cart nobody owns. Both halves are asserted here.
  await wide(page);
  await seen(page);

  // HALF ONE: the bytes. Fetched, never rendered - no JavaScript can have run.
  const served = await (await fetch(`${BASE}${MENU}`)).text();
  const asideStart = served.indexOf('<aside');
  const asideBytes = served.slice(asideStart, served.indexOf('</aside>', asideStart));
  expect(asideStart, 'the aside FRAME must be prerendered').toBeGreaterThan(-1);
  for (const banned of ['asideLine', 'asideStepper', 'totalRow']) {
    expect(asideBytes, `the served bytes carry ${banned}`).not.toContain(banned);
  }
  expect(asideBytes).not.toMatch(/₪\s*\d/);

  // HALF TWO: with a real cart in this visitor's own storage, it fills in.
  await page.evaluate(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 2, selections: {}, note: '' }],
    })],
  ).catch(() => undefined);
  await page.goto(`${BASE}${MENU}`);
  await page.evaluate(
    ([key, value]) => localStorage.setItem(key as string, value as string),
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 2, selections: {}, note: '' }],
    })],
  );
  await page.reload();
  await expect(page.locator('[data-sf-item]').first()).toBeVisible();

  const aside = page.locator('[data-sf-aside="live"]');
  await expect(aside).toHaveCount(1);
  await expect(aside.locator('[data-sf-aside-line]')).toHaveCount(1);
  const after = (await aside.textContent()) ?? '';
  expect(after, 'the hydrated aside must show this visitor\'s money').toMatch(/₪\s*\d/);

  // And the dock IS rendered (the cart is real) but hidden by the container query.
  const dock = page.locator('[data-sf-dock="live"]');
  await expect(dock, 'the dock must exist so the hide is meaningful').toHaveCount(1);
  expect(await dock.evaluate((el) => getComputedStyle(el).display)).toBe('none');

  RESULTS.wideAside = {
    servedBytesCarryNoCart: true,
    hydratedShowsCart: /₪\s*\d/.test(after),
  };
  await page.screenshot({ path: path.join(SHOTS, 'WIDE-aside-live.png') });
});

/** Visible asides only: below 900 the seam stays in the document and the
    container query hides it, because a static export serves one set of bytes to
    every width and cannot pick a layout per device on the server. */
async function asideCounts(page: Page) {
  return page.evaluate(() => {
    const all = Array.from(document.querySelectorAll('aside'));
    const visible = all.filter((a) => {
      const cs = getComputedStyle(a);
      return cs.display !== 'none' && a.getBoundingClientRect().width > 0;
    });
    const a0 = visible[0];
    const r = a0?.getBoundingClientRect();
    return {
      dom: all.length,
      visible: visible.length,
      live: document.querySelectorAll('[data-sf-aside="live"]').length,
      text: a0 ? (a0.textContent ?? '').trim() : null,
      width: r ? Math.round(r.width) : null,
      x: r ? Math.round(r.x) : null,
      dir: document.documentElement.dir,
      viewport: window.innerWidth,
      overflow: document.documentElement.scrollWidth > window.innerWidth,
    };
  });
}

async function seedRealCart(page: Page) {
  await page.addInitScript(
    ([key, value]) => {
      try { localStorage.setItem(key as string, value as string); } catch { /* ignore */ }
    },
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [{ lineId: 'l1aaa', itemId: '1', qty: 2, selections: { bun: ['brioche'] }, note: '' }],
    })],
  );
}

test('C2-A/B: Search below 900 shows NO dock and NO visible aside, with a real cart', async ({ page }) => {
  await seen(page);
  await seedRealCart(page);
  for (const width of [360, 390, 430, 834]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(`${BASE}${SEARCH}`);
    await expect(page.locator('[data-sf-item]').first()).toBeVisible();
    const a = await asideCounts(page);
    expect(a.visible, `${width}: no aside may be visible below 900`).toBe(0);
    await expect(page.locator('[data-sf-dock]'), `${width}: no dock on Search`).toHaveCount(0);
    expect(a.overflow, `${width}: no horizontal overflow`).toBe(false);
    // Search itself still works.
    await expect(page.locator('[data-sf-item]')).toHaveCount(6);
  }
});

test('C2-C: Search at 1280 shows EXACTLY ONE aside, and it is the live one', async ({ page }) => {
  await seen(page);
  await seedRealCart(page);
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(`${BASE}${SEARCH}`);
  await expect(page.locator('[data-sf-item]').first()).toBeVisible();

  const a = await asideCounts(page);
  expect(a.visible, 'exactly one visible aside').toBe(1);
  expect(a.dom, 'exactly one aside in the document').toBe(1);
  expect(a.live, 'and it is the live cart column').toBe(1);
  expect(a.width, 'the approved 360px column').toBe(360);
  expect(a.overflow).toBe(false);
  await expect(page.locator('[data-sf-dock]'), 'no dock at wide').toHaveCount(0);

  // FUNCTIONAL, from Phase D: it carries this visitor's lines, their stepper
  // and their totals, and its CTA goes straight to checkout.
  const aside = page.locator('[data-sf-aside="live"]');
  await expect(aside.locator('[data-sf-aside-line]')).toHaveCount(1);
  await expect(aside.locator('[data-sf-aside-totals]')).toHaveCount(1);
  await expect(aside.locator('[data-sf-stepper="aside"]')).toHaveCount(1);
  expect(a.text, 'the hydrated aside carries money').toMatch(/₪\s*\d/);
  const cta = aside.locator('[data-sf-aside-cta="checkout"]');
  await expect(cta).toHaveCount(1);
  // E-stage repair of the D1 focus regression: the checkout control is ONE
  // persistent <button> whose activation is a soft navigation, no longer a
  // <Link> swapped in on settlement. Its destination is proven by activating
  // it, not by reading an href it no longer carries.
  expect(await cta.evaluate((el) => el.tagName)).toBe('BUTTON');
  await expect(cta).not.toHaveAttribute('aria-disabled', 'true');

  RESULTS.c2Wide = a;
  await page.screenshot({ path: path.join(SHOTS, 'C2-search-wide-aside.png') });

  await cta.click();
  await page.waitForURL(`**/s/${SLUG}/checkout**`);
  expect(new URL(page.url()).pathname).toBe(`/s/${SLUG}/checkout`);
});

test('C2-C: the Search aside reacts to THIS visitor\'s cart, and to nothing else', async ({ page }) => {
  await seen(page);
  await seedRealCart(page);
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(`${BASE}${SEARCH}`);
  const aside = page.locator('[data-sf-aside="live"]');
  const before = (await aside.textContent()) ?? '';

  // Replace it with a much larger cart and reload.
  //
  // It has to go through addInitScript, not page.evaluate: `seedRealCart`
  // installed an init script that re-seeds the ORIGINAL cart on every
  // navigation, so a value written to localStorage now would be overwritten by
  // the reload. Init scripts run in the order they were added, so this one
  // wins. (The Phase C version of this test could not notice: the seam it was
  // asserting on was inert either way.)
  await page.addInitScript(
    ([key, value]) => {
      try { localStorage.setItem(key as string, value as string); } catch { /* ignore */ }
    },
    [CART_KEY, JSON.stringify({
      schema: 1, slug: SLUG, menuVersion: 'mb-1',
      lines: [
        { lineId: 'l1aaa', itemId: '1', qty: 9, selections: {}, note: '' },
        { lineId: 'l2bbb', itemId: '7', qty: 4, selections: {}, note: '' },
      ],
    })],
  );
  await page.reload();
  await expect(page.locator('[data-sf-item]').first()).toBeVisible();
  const after = (await aside.textContent()) ?? '';
  expect(after, 'the aside must follow the cart').not.toBe(before);
  await expect(aside.locator('[data-sf-aside-line]')).toHaveCount(2);
  // 9 x 5500 + 4 x 2200 = 58300, tax 10494, total 68794.
  expect(after).toContain('₪583');
  expect(after).toContain('₪687.94');
  // And the count is UNITS, 13, not lines.
  expect((await aside.locator('[data-sf-aside-count]').textContent()) ?? '').toContain('13');
});

test('C2-D: the Search seam sits on the logical inline-END in both directions', async ({ page }) => {
  await seen(page);
  for (const [root, dir] of [['', 'rtl'], ['/en', 'ltr']] as const) {
    await page.setViewportSize({ width: 1280, height: 900 });
    await page.goto(`${BASE}${root}/s/${SLUG}/search`);
    await expect(page.locator('[data-sf-item]').first()).toBeVisible();
    const a = await asideCounts(page);
    expect(a.dir).toBe(dir);
    expect(a.visible).toBe(1);
    // inline-end is x=0 in RTL and the far side in LTR.
    if (dir === 'rtl') expect(a.x, 'RTL: inline-end is the left edge').toBeLessThan(40);
    else expect(a.x, 'LTR: inline-end is the right edge').toBeGreaterThan(a.viewport - 400);
    expect(a.overflow, `${dir}: no horizontal overflow`).toBe(false);
    RESULTS[`c2Dir_${dir}`] = a;
  }
});

test('C2-E: a NO-JS visitor sees the Search aside FRAME, and it carries no cart', async ({ browser }) => {
  // Without JavaScript nothing can read this visitor's storage, so the frame is
  // all there is - and the frame is what keeps 360px of layout from appearing
  // out of nowhere for everyone else.
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    javaScriptEnabled: false,
  });
  const page = await ctx.newPage();
  await page.goto(`${BASE}${SEARCH}`, { waitUntil: 'domcontentloaded' });
  await expect(page.locator('[data-sf-aside="live"]')).toHaveCount(1);
  await expect(page.locator('[data-sf-dock]')).toHaveCount(0);
  await expect(page.locator('[data-sf-aside-line]')).toHaveCount(0);
  await expect(page.locator('[class*="asideLine"]')).toHaveCount(0);
  await expect(page.locator('[class*="totalRow"]')).toHaveCount(0);
  const body = (await page.locator('body').textContent()) ?? '';
  expect(body).not.toContain('₪99');
  expect(body).not.toContain('₪116.82');
  await page.screenshot({ path: path.join(SHOTS, 'C2-nojs-search-aside.png') });
  await ctx.close();
});


test('R6: a NO-JAVASCRIPT visitor sees no cart anywhere', async ({ browser }) => {
  // This is the crawler and the no-JS visitor. Whatever is in the bytes is what
  // they get, so a fabricated cart is visible to them permanently.
  const ctx = await browser.newContext({
    viewport: { width: 1280, height: 900 },
    javaScriptEnabled: false,
  });
  const page = await ctx.newPage();
  for (const route of [MENU, SEARCH]) {
    await page.goto(`${BASE}${route}`, { waitUntil: 'domcontentloaded' });
    const body = (await page.locator('body').textContent()) ?? '';
    await expect(page.locator('[data-sf-dock]'), `${route}: a dock in no-JS bytes`).toHaveCount(0);
    await expect(page.locator('[class*="asideLine"]'), `${route}: a cart line`).toHaveCount(0);
    await expect(page.locator('[class*="totalRow"]'), `${route}: cart totals`).toHaveCount(0);
    expect(body, `${route}: the seeded subtotal is in the no-JS bytes`).not.toContain('₪99');
    expect(body, `${route}: the seeded total is in the no-JS bytes`).not.toContain('₪116.82');
  }
  // The menu still shows its aside FRAME, and the frame is truthful.
  await page.goto(`${BASE}${MENU}`, { waitUntil: 'domcontentloaded' });
  const seam = page.locator('[data-sf-aside="live"]');
  await expect(seam).toHaveCount(1);
  const seamText = (await seam.textContent()) ?? '';
  expect(seamText).not.toMatch(/₪\s*\d/);
  RESULTS.noJs = { seamText: seamText.slice(0, 80) };
  await page.screenshot({ path: path.join(SHOTS, 'NOJS-menu-no-cart.png') });
  await ctx.close();
});

test('R3: a sold-out search row shows a VISIBLE localized reason', async ({ page }) => {
  await phone(page);
  await page.goto(`${BASE}${SEARCH}`);
  const row = page.locator('[data-sf-item][aria-disabled="true"]');
  await expect(row).toHaveCount(1);

  // The cue must be a real, painted element - not sr-only, not opacity alone.
  const tag = row.locator('[class*="rowSoldOutTag"]');
  await expect(tag).toHaveCount(1);
  await expect(tag).toBeVisible();
  const box = await tag.boundingBox();
  expect(box!.width, 'the cue must occupy real space').toBeGreaterThan(8);
  expect(box!.height).toBeGreaterThan(8);
  const text = (await tag.textContent())?.trim() ?? '';
  expect(text.length, 'the cue must carry localized copy').toBeGreaterThan(0);

  // It must NOT be clipped away like an sr-only node.
  const clip = await tag.evaluate((el) => getComputedStyle(el).clipPath);
  expect(clip === 'none' || clip === '').toBe(true);

  RESULTS.soldOutCue = { text, box };
  await page.screenshot({ path: path.join(SHOTS, 'R3-soldout-visible.png') });
});

test('R4: the clear button says clear, not close, and has a >=44px hit target', async ({ page }) => {
  for (const [root, expected] of [
    ['', 'مسح البحث'],
    ['/he', 'נקה חיפוש'],
    ['/en', 'Clear search'],
  ] as const) {
    await phone(page);
    await page.goto(`${BASE}${root}/s/${SLUG}/search`);
    await page.keyboard.type('a');
    const clear = page.locator('[role="search"] button');
    await expect(clear).toHaveCount(1);
    await expect(clear).toHaveAttribute('aria-label', expected);

    // The PAINTED circle stays 28px; the HIT AREA must reach 44px. Measured on
    // the pseudo-element, which is what a finger actually lands on.
    const hit = await clear.evaluate((el) => {
      const r = el.getBoundingClientRect();
      const before = getComputedStyle(el, '::before');
      const extra = (v: string) => Math.abs(parseFloat(v) || 0);
      return {
        painted: { w: Math.round(r.width), h: Math.round(r.height) },
        hitW: Math.round(r.width + extra(before.insetInlineStart) + extra(before.insetInlineEnd)),
        hitH: Math.round(r.height + extra(before.top) + extra(before.bottom)),
      };
    });
    expect(hit.painted.w, `${root || '/'}: painted size must stay canonical`).toBe(28);
    expect(hit.hitW, `${root || '/'}: hit width`).toBeGreaterThanOrEqual(44);
    expect(hit.hitH, `${root || '/'}: hit height`).toBeGreaterThanOrEqual(44);

    // And it really clears.
    await clear.click();
    await expect(page.locator('input[type="search"]')).toHaveValue('');
    RESULTS[`clear${root || 'ar'}`] = hit;
  }
});

test('J: a blocked Add moves FOCUS into the first unmet group', async ({ page }) => {
  await phone(page);
  await seen(page);
  // Item 16 has TWO required groups (bun, meal), so "first" is meaningful.
  await page.goto(`${BASE}${MENU}?item=16`);
  const sheet = page.locator('[data-sf-sheet="product"]');
  await expect(sheet).toBeVisible();

  await page.locator('[data-sf-cta="product"]').click({ force: true });

  // Sheet stays open, nothing added, the alert fires.
  await expect(sheet).toBeVisible();
  await expect(sheet.locator('[role="alert"]').first()).toBeVisible();
  expect(await page.evaluate((k) => localStorage.getItem(k), CART_KEY)).toBeNull();

  // Focus is INSIDE the first unmet group, not left on the CTA.
  const where = await page.evaluate(() => {
    const active = document.activeElement;
    const group = active?.closest('[data-sf-group]');
    return {
      groupId: group?.getAttribute('data-sf-group') ?? null,
      isCta: active?.getAttribute('data-sf-cta') === 'product',
    };
  });
  expect(where.isCta, 'focus must leave the CTA').toBe(false);
  expect(where.groupId, 'focus must land in the FIRST unmet group').toBe('bun');

  // tabIndex=-1 keeps it programmatically focusable WITHOUT adding a tab stop.
  const tabindex = await sheet.locator('[data-sf-group="bun"]').getAttribute('tabindex');
  expect(tabindex).toBe('-1');

  RESULTS.blockedFocus = where;
  await page.screenshot({ path: path.join(SHOTS, 'J-first-unmet-focused.png') });
});

test('K: the localized "included" word is NOT forced into an LTR island', async ({ page }) => {
  // Only numerals belong in an LTR island. Wrapping a localized WORD in
  // dir="ltr" mislabels its direction.
  for (const root of ['', '/he'] as const) {
    await phone(page);
    await seen(page);
    await page.goto(`${BASE}${root}/s/${SLUG}/menu?item=7`);
    const opts = page.locator('[data-sf-group="sauce"] [role="radio"]');
    await expect(opts.first()).toBeVisible();

    const deltas = await page.locator('[data-sf-group="sauce"] [class*="delta"]').evaluateAll(
      (els) => els.map((e) => ({
        text: (e.textContent ?? '').trim(),
        dir: e.getAttribute('dir'),
        isMoney: /₪/.test(e.textContent ?? ''),
      })),
    );
    expect(deltas.length).toBeGreaterThan(0);
    for (const d of deltas) {
      if (d.isMoney) {
        expect(d.dir, `${root || 'ar'}: a money delta stays an LTR island`).toBe('ltr');
      } else {
        expect(d.dir, `${root || 'ar'}: "${d.text}" must not be forced LTR`).toBeNull();
      }
    }
    RESULTS[`included${root || 'ar'}`] = deltas;
  }
});

test('the CSP is real: no NEW inline style source appears on either screen', async ({ page }) => {
  // The rule is `style-src 'self'` with no 'unsafe-inline', so no inline style
  // may be AUTHORED. Two things are checked, because either alone is weak:
  //
  //   1. the SERVED BYTES carry no style attribute at all (asserted over the
  //      exported HTML, which is what a no-script visitor and a crawler get);
  //   2. at runtime the browser reports no CSP violation, and every element
  //      that has a style PROPERTY set is one of the two approved sources -
  //      ThemeScope's CSSOM setProperty (a CSSOM mutation, not an inline-style
  //      source, which is why CSP permits it) and Next's own route announcer.
  //
  // Pinning the approved set is what makes this catch a NEW inline style
  // instead of merely counting to three.
  const violations: string[] = [];
  page.on('console', (msg) => {
    if (/Content Security Policy/i.test(msg.text())) violations.push(msg.text());
  });
  await phone(page);
  await seen(page);

  const served: Record<string, number> = {};
  const runtime: Record<string, unknown[]> = {};
  for (const route of [SEARCH, `${MENU}?item=1`]) {
    const html = await (await fetch(`${BASE}${route.split('?')[0]}`)).text();
    served[route] = (html.match(/\sstyle="/g) ?? []).length;
    expect(served[route], `${route}: the served bytes carry an inline style`).toBe(0);

    await page.goto(`${BASE}${route}`);
    await expect(page.locator('[data-sf-item]').first()).toBeVisible();
    const unexpected = await page.$$eval('[style]', (els) =>
      els
        .map((el) => ({
          tag: el.tagName.toLowerCase(),
          style: el.getAttribute('style') ?? '',
        }))
        // ThemeScope: nothing but custom properties, applied via setProperty.
        .filter((e) => !/^(?:\s*--[\w-]+:[^;]*;?)+\s*$/.test(e.style))
        // Next.js route announcer and its visually-hidden inner node.
        .filter((e) => e.tag !== 'next-route-announcer')
        .filter((e) => !/clip:\s*rect\(0px, 0px, 0px, 0px\)/.test(e.style)));
    runtime[route] = unexpected;
    expect(unexpected, `${route}: an unapproved inline style appeared`).toEqual([]);
  }

  RESULTS.csp = { violations, servedInlineStyles: served, unapprovedRuntime: runtime };
  expect(violations).toEqual([]);
});
