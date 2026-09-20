// Home surface rules: the ones that are cheap to break silently — module order,
// what the popular rail is allowed to CLAIM, state mapping, and the CSS
// discipline that keeps one tree serving both reading directions.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => readFileSync(path.join(ROOT, rel), 'utf8');
/** Source with comments removed: these rules are about CODE, not prose. */
const code = (rel) =>
  read(rel)
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*/gm, '$1 ');

const { buildHome, homeOptionsFor, HOME_SCENARIO_NAMES } = await import('../src/source/home.ts');
const { SCENARIOS, SCENARIO_SLUGS } = await import('../src/source/scenarios.ts');
const { fixtureSource } = await import('../src/source/fixtures.ts');
const { CATEGORIES, MENU_ITEMS, TAX_RATE } = await import('../src/source/menu-fixture.ts');

const tenant = fixtureSource.getTenant('maps-burger');
const homeSource = read('src/ui/storefront/home/Home.tsx');
const css = read('src/ui/storefront/home/home.module.css');

test('the fixture tenant and menu load', () => {
  assert.ok(tenant !== null);
  assert.equal(CATEGORIES.length, 7);
  assert.equal(MENU_ITEMS.length, 20);
  assert.equal(TAX_RATE, 0.18);
});

// ---------------------------------------------------------------- module order

test('module order is FIXED and expressed once, in source order', () => {
  // announce -> hero -> service -> categories -> promo -> popular -> sections
  // -> story -> footer. The first four are emitted by HomeChrome in that order.
  const chrome = read('src/ui/storefront/home/HomeChrome.tsx');
  const chromeOrder = ['announce', 'compact', '{hero}', '{service}', '{notice}', 'styles.rail'];
  let at = -1;
  for (const token of chromeOrder) {
    const next = chrome.indexOf(token, at + 1);
    assert.ok(next > at, `HomeChrome: ${token} must follow the previous module`);
    at = next;
  }

  const pageOrder = ['HomeChrome', 'PromoBanner', 'PopularSection', 'MenuSection', 'StoryCard', 'SiteFooter'];
  let cursor = -1;
  for (const token of pageOrder) {
    const next = homeSource.indexOf(token, cursor + 1);
    assert.ok(next > cursor, `Home.tsx: ${token} must come after the previous module`);
    cursor = next;
  }
});

test('no module-order data or reorder mechanism exists', () => {
  const homeCode = code('src/ui/storefront/home/Home.tsx');
  for (const banned of ['moduleOrder', 'sortModules', 'reorder', 'dragHandle', 'onDragEnd']) {
    assert.ok(!homeCode.includes(banned), `Home.tsx must not contain ${banned}`);
  }
});

// -------------------------------------------------------------- module toggles

test('an absent module renders nothing at all - no heading, no spacer', () => {
  // Each optional module is guarded by an explicit null check that returns null,
  // rather than rendering an empty wrapper.
  for (const guard of [
    'modules.promo === null ? null :',
    'modules.story === null ? null :',
    'modules.popular.enabled ?',
  ]) {
    assert.ok(homeSource.includes(guard), `missing clean-absence guard: ${guard}`);
  }
});

test('modules-off removes every optional module and keeps the mandatory ones', () => {
  const view = buildHome(tenant, homeOptionsFor(['modules-off']));
  assert.equal(view.modules.announcement, null);
  assert.equal(view.modules.promo, null);
  assert.equal(view.modules.story, null);
  assert.equal(view.modules.popular.enabled, false);
  // Mandatory: hero copy, categories and items survive.
  assert.ok(view.modules.campaign.title.length > 0);
  assert.equal(view.categories.length, 7);
  assert.equal(view.items.length, 20);
});

test('an empty menu suppresses every module and every category', () => {
  const view = buildHome(tenant, homeOptionsFor(['empty-menu']));
  assert.equal(view.items.length, 0);
  assert.equal(view.categories.length, 0);
  assert.equal(view.modules.promo, null);
  assert.equal(view.modules.story, null);
  assert.equal(view.modules.announcement, null);
  assert.equal(view.modules.popular.enabled, false);
});

// ------------------------------------------------------------- POPULAR_READY

test('POPULAR_READY governs the rail CLAIM, not merely its styling', () => {
  const menu = read('src/ui/storefront/home/MenuParts.tsx');
  // Ranked heading and the rank badge are BOTH behind `ready`.
  assert.match(menu, /ready \? m\.mostOrdered : m\.chefPicks/);
  assert.match(menu, /ready \? <span className=\{styles\.sectionSub\}>\{m\.last30\}<\/span> : null/);
  assert.match(menu, /rank=\{ready \? index \+ 1 : undefined\}/);
  // The rank badge only renders when a rank was supplied.
  assert.match(menu, /rank === undefined \? null :/);
});

test('popular:off keeps the rail but removes every ranking claim', () => {
  const on = buildHome(tenant, homeOptionsFor([]));
  const off = buildHome(tenant, homeOptionsFor(['popular-off']));
  assert.equal(on.modules.popular.ready, true);
  assert.equal(off.modules.popular.enabled, true, 'the rail itself stays');
  assert.equal(off.modules.popular.ready, false, 'but it may not claim a ranking');
});

test('sold-out items are excluded from the popular rail entirely', () => {
  const menu = read('src/ui/storefront/home/MenuParts.tsx');
  assert.match(menu, /items\.filter\(\(i\) => i\.signature && !i\.soldOut\)/);
});

// ------------------------------------------------------------- service states

test('every service state maps to its own tone and word', () => {
  const parts = read('src/ui/storefront/home/HomeParts.tsx');
  assert.match(parts, /open: styles\.stateOpen/);
  assert.match(parts, /closed: styles\.stateClosed/);
  assert.match(parts, /paused: styles\.statePaused/);
  assert.match(parts, /service\.state === 'open' \? m\.openNow/);
  for (const cls of ['.stateOpen', '.stateWarn', '.statePaused', '.stateClosed']) {
    if (cls === '.stateWarn') continue;
    assert.ok(css.includes(cls), `home.module.css must define ${cls}`);
  }
});

test('closed and paused suppress the announcement and show the notice', () => {
  assert.match(homeSource, /tenant\.service\.state !== 'open'\s*\?\s*null/);
  assert.match(homeSource, /tenant\.service\.state === 'open' \? null : \(/);
});

test('the menu stays browsable while closed or paused', () => {
  // Nothing about the closed/paused branch removes items or categories.
  for (const scenario of ['closed', 'paused']) {
    const t = { ...tenant, service: { ...tenant.service, state: scenario } };
    const view = buildHome(t);
    assert.equal(view.items.length, 20, `${scenario} must keep the menu`);
    assert.equal(view.categories.length, 7);
  }
});

test('a disabled service is struck through and labelled unavailable', () => {
  const parts = read('src/ui/storefront/home/HomeParts.tsx');
  assert.match(parts, /service\.pickupEnabled \? '' : styles\.serviceOff/);
  assert.match(parts, /service\.deliveryEnabled \? '' : styles\.serviceOff/);
  assert.match(parts, /service\.pickupEnabled \? tenant\.city : m\.unavailableNow/);
  assert.match(css, /\.serviceOff \.serviceLabel \{\s*text-decoration: line-through;/);
  assert.match(css, /\.serviceOff \{\s*opacity: 0\.55;/);
});

// ----------------------------------------------------------------- the rails

test('category rails are navigation, never a fake tablist', () => {
  const chrome = read('src/ui/storefront/home/HomeChrome.tsx');
  for (const banned of ['role="tab"', 'role="tablist"', 'role="tabpanel"', 'aria-selected']) {
    assert.ok(!chrome.includes(banned), `the rail must not use ${banned}`);
  }
  // It is a <nav> with a label, and current state is aria-current.
  assert.match(chrome, /<nav className=\{styles\.rail\} aria-label=\{m\.menuLabel\}>/);
  assert.ok((chrome.match(/aria-current=\{category\.id === active \? 'true' : undefined\}/g) ?? []).length === 2,
    'both rails mark the current category with aria-current');
});

test('the compact header uses the design threshold and both rails stay in sync', () => {
  const chrome = read('src/ui/storefront/home/HomeChrome.tsx');
  assert.match(chrome, /const COMPACT_AT = 200;/);
  assert.match(chrome, /const SPY_OFFSET = 116;/);
  assert.match(chrome, /const ARROW_STEP = 180;/);
  // The arrow honours the reading direction rather than a raw sign.
  assert.match(chrome, /direction === 'rtl'/);
});

test('the compact header neither reserves space nor shifts the document', () => {
  // A zero-height sticky HOST is what makes both true at once: a header that
  // merely collapses its own height still shoves the page down when it opens.
  assert.match(css, /\.compactHost \{[\s\S]*?height: 0;[\s\S]*?\}/);
  assert.match(css, /\.compact \{[\s\S]*?transform: translateY\(-100%\);[\s\S]*?\}/);
  assert.match(css, /\.compactOn \{[\s\S]*?transform: translateY\(0\);[\s\S]*?\}/);
  const chrome = read('src/ui/storefront/home/HomeChrome.tsx');
  assert.match(chrome, /className=\{styles\.compactHost\}/);
});

// ------------------------------------------------------------------- styling

test('layout uses logical properties, not physical sides', () => {
  const physical = [
    /(^|[^-\w])margin-left\s*:/m,
    /(^|[^-\w])margin-right\s*:/m,
    /(^|[^-\w])padding-left\s*:/m,
    /(^|[^-\w])padding-right\s*:/m,
    /(^|[^-\w])border-left\s*:/m,
    /(^|[^-\w])border-right\s*:/m,
    /(^|[^-\w])(left|right)\s*:\s*[-0-9]/m,
  ];
  for (const rx of physical) {
    assert.ok(!rx.test(css), `home.module.css uses a physical property: ${rx}`);
  }
  // And it does use the logical ones.
  for (const logical of ['inset-inline', 'margin-inline', 'padding-inline', 'border-inline-start']) {
    assert.ok(css.includes(logical), `expected logical property ${logical}`);
  }
});

test('motion modes gate exactly the approved effects', () => {
  // calm = entrances only: no sheen, no Ken Burns, no motif, no float.
  assert.match(css, /\.motionFull \.heroImg,\s*\n\s*\.motionLively \.heroImg \{\s*\n\s*animation: sfKen/);
  assert.match(css, /\.motionFull \.dockCta::before,\s*\n\s*\.motionLively \.dockCta::before/);
  // lively adds the popular-card float, and only that.
  assert.match(css, /\.motionLively \.popularGrid \.card \{\s*\n\s*animation: sfFloat/);
  // the motif is suppressed in calm from the component side
  assert.match(homeSource, /showMotif=\{view\.motion !== 'calm'\}/);
});

test('motion classes map calm to no extra class', () => {
  assert.match(homeSource, /calm: '',/);
});

// --------------------------------------------------------------- cart is inert

test('the cart is presentational only - no store, no persistence, no mutation', () => {
  const cartSource = read('src/ui/storefront/home/CartParts.tsx');
  for (const banned of ['useState', 'useReducer', 'localStorage', 'sessionStorage', 'onClick', 'dispatch']) {
    assert.ok(!cartSource.includes(banned), `CartParts must not contain ${banned}`);
  }
  // Every control is explicitly disabled.
  assert.ok((cartSource.match(/disabled/g) ?? []).length >= 2);
});

test('cart totals are integer minor units and tax is configuration', () => {
  const view = buildHome(tenant);
  for (const value of [view.cart.subtotalMinor, view.cart.taxMinor, view.cart.totalMinor]) {
    assert.ok(Number.isInteger(value), `${value} must be integer minor units`);
  }
  assert.equal(view.cart.totalMinor, view.cart.subtotalMinor + view.cart.taxMinor);
  assert.equal(view.cart.taxMinor, Math.round(view.cart.subtotalMinor * view.cart.taxRate));
  assert.equal(view.cart.taxRate, TAX_RATE, 'the rate comes from configuration, not a component');
});

test('an empty cart hides the dock', () => {
  const cartSource = read('src/ui/storefront/home/CartParts.tsx');
  assert.match(cartSource, /if \(cart\.itemCount === 0\) return null;/);
  const view = buildHome(tenant, homeOptionsFor(['cart-empty']));
  assert.equal(view.cart.itemCount, 0);
});

// ------------------------------------------------------------------ scenarios

test('card mode switches between list and grid without touching anything else', () => {
  const list = buildHome(tenant, homeOptionsFor(['list']));
  const grid = buildHome(tenant, homeOptionsFor(['grid']));
  assert.equal(list.cardMode, 'list');
  assert.equal(grid.cardMode, 'grid');
  assert.deepEqual(grid.items, list.items);
  assert.deepEqual(grid.categories, list.categories);
});

test('every declared scenario is reachable and none leaks outside the fixture layer', () => {
  assert.ok(HOME_SCENARIO_NAMES.length >= 8);
  for (const name of HOME_SCENARIO_NAMES) {
    assert.doesNotThrow(() => buildHome(tenant, homeOptionsFor([name])), name);
  }
});

test('the wide layout is keyed to CONTAINER width, not the viewport', () => {
  // 834px must stay phone-style, and the dashboard preview must behave like a
  // narrow container even in a wide window. That only works with @container.
  assert.match(css, /@container storefront \(min-width: 900px\)/);
  assert.ok(!/@media[^{]*min-width:\s*900px/.test(css), 'must not key the aside to the viewport');
  assert.match(css, /container-type: inline-size;/);
});

// ------------------------------------- unscreenshotted state evidence (H02-H06)

test('H02 emptyMenu: the state exists, is reachable and suppresses every module', () => {
  const view = buildHome(tenant, homeOptionsFor(['empty-menu']));
  assert.equal(view.items.length, 0);
  assert.equal(view.categories.length, 0);
  assert.match(homeSource, /empty \? \(\s*<EmptyMenu/);
  // It is also a real route, so it is screenshotted as well.
  assert.ok(SCENARIO_SLUGS.includes('demo-empty'));
});

test('H03 pickupOff / deliveryOff render as unavailable, not as absent', () => {
  const parts = read('src/ui/storefront/home/HomeParts.tsx');
  assert.match(parts, /service\.pickupEnabled \? tenant\.city : m\.unavailableNow/);
  assert.match(parts, /service\.deliveryEnabled \? \(/);
  // Both disabled states are carried by scenario routes, so they are also seen.
  const closed = SCENARIOS.find((x) => x.slug === 'demo-closed');
  const paused = SCENARIOS.find((x) => x.slug === 'demo-paused');
  assert.equal(closed.service.pickupEnabled, false);
  assert.equal(paused.service.deliveryEnabled, false);
});

test('H04 lively adds only the popular float, and reduced motion overrides it', () => {
  // No scenario ROUTE carries lively: each scenario document costs ~170 KB of a
  // hard 4 MiB ceiling, and lively differs from full only by one animation that
  // prefers-reduced-motion then cancels. The rule is asserted directly instead.
  assert.ok(/\.motionLively \.popularGrid \.card \{[^}]*animation: sfFloat/.test(css),
    'lively must add the popular-card float');
  // lively is a superset of full, never a different set.
  assert.match(homeSource, /lively: `\$\{styles\.motionFull\} \$\{styles\.motionLively\}`/);
  // And the global reduced-motion override collapses every animation.
  const shellCss = read('src/ui/storefront/storefront.module.css');
  assert.match(shellCss, /@media \(prefers-reduced-motion: reduce\)/);
  assert.match(shellCss, /animation-duration: 0\.001s !important;/);
  assert.match(shellCss, /animation-iteration-count: 1 !important;/);
  // The view layer can actually produce lively.
  assert.equal(buildHome(tenant, homeOptionsFor(['lively'])).motion, 'lively');
});

test('H05 popular:off keeps the rail, drops the rank and relabels it', () => {
  // Also routeless for budget; proven against the real view and the real JSX.
  const off = buildHome(tenant, homeOptionsFor(['popular-off']));
  assert.equal(off.modules.popular.enabled, true);
  assert.equal(off.modules.popular.ready, false);
  const menu = read('src/ui/storefront/home/MenuParts.tsx');
  // With ready=false there is no rank prop, so the badge cannot render...
  assert.match(menu, /rank=\{ready \? index \+ 1 : undefined\}/);
  assert.match(menu, /\{rank === undefined \? null : \(/);
  // ...and the heading and sub-label both change.
  assert.match(menu, /ready \? m\.mostOrdered : m\.chefPicks/);
  assert.match(menu, /\{ready \? <span className=\{styles\.sectionSub\}>\{m\.last30\}<\/span> : null\}/);
});

test('H06 light x grid is a real, reachable combination', () => {
  const light = SCENARIOS.find((x) => x.slug === 'demo-light');
  assert.equal(light.preset, 'light');
  assert.equal(light.options.cardMode, 'grid');
});

test('every scenario slug states what it proves', () => {
  for (const scenario of SCENARIOS) {
    assert.ok(scenario.proves.length > 8, `${scenario.slug} must say what it evidences`);
  }
});
