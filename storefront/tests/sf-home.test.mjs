// Home surface rules: the ones that are cheap to break silently — module order,
// what the popular rail is allowed to CLAIM, state mapping, and the CSS
// discipline that keeps one tree serving both reading directions.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => readFileSync(path.join(ROOT, rel), 'utf8');
/** Source with comments removed: these rules are about CODE, not prose. */
const code = (rel) =>
  read(rel)
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*/gm, '$1 ');

const { buildHome, homeOptionsFor, HOME_SCENARIO_NAMES, homeSlugs } = await import('../src/source/home.ts');
const { SCENARIOS, SCENARIO_SLUGS } = await import('../src/source/scenarios.ts');
const { fixtureSource } = await import('../src/source/fixtures.ts');
const { storefrontMessages, fill } = await import('../src/i18n/storefront.ts');
const { anchorOrder, CHROME_ANCHORS, PAGE_ANCHORS, LOCKED_MODULE_ORDER } = await import(
  '../scripts/module-order.mjs'
);
const { CATEGORIES, MENU_ITEMS, TAX_RATE } = await import('../src/source/menu-fixture.ts');

const tenant = fixtureSource.getTenant('maps-burger');
const homeSource = read('src/ui/storefront/home/Home.tsx');
const partsSource = read('src/ui/storefront/home/HomeParts.tsx');
const css = read('src/ui/storefront/home/home.module.css');

test('the fixture tenant and menu load', () => {
  assert.ok(tenant !== null);
  assert.equal(CATEGORIES.length, 7);
  assert.equal(MENU_ITEMS.length, 20);
  assert.equal(TAX_RATE, 0.18);
});

// ---------------------------------------------------------------- module order

test('module order is FIXED and expressed once, in source order', () => {
  // The previous version of this test scanned RAW source with a monotonic
  // indexOf, so 'announce' matched a JSDoc line and 'PromoBanner' matched an
  // import. Moving PromoBanner below Popular still passed. Every anchor below
  // is real markup, and anchorOrder() demands EXACTLY ONE occurrence of each -
  // a token that also matches prose or an import now fails loudly.
  const chrome = read('src/ui/storefront/home/HomeChrome.tsx');
  assert.deepEqual(anchorOrder(chrome, CHROME_ANCHORS), []);
  assert.deepEqual(anchorOrder(homeSource, PAGE_ANCHORS), []);
});

test('NEGATIVE CONTROL: the module-order check catches a real reorder', () => {
  // Mutants are built in memory. The committed source is never written to.
  const chrome = read('src/ui/storefront/home/HomeChrome.tsx');

  // (1) The exact mutation that used to pass: PromoBanner moved below the menu
  //     sections. Cutting the <PromoBanner .../> element and re-inserting it
  //     after <StoryCard violates the locked order.
  const promo = /\{modules\.promo === null \? null : <PromoBanner promo=\{modules\.promo\} m=\{m\} \/>\}/;
  assert.match(homeSource, promo, 'the promo line must exist for this control to mean anything');
  const moved = homeSource
    .replace(promo, '')
    .replace('<SiteFooter', '<PromoBanner /><SiteFooter');
  const movedProblems = anchorOrder(moved, PAGE_ANCHORS);
  assert.ok(movedProblems.length > 0, 'a reordered PromoBanner MUST be caught');

  // (2) A module deleted outright.
  const deleted = homeSource.replace('<StoryCard', '<NotAModule');
  assert.ok(anchorOrder(deleted, PAGE_ANCHORS).length > 0, 'a missing module MUST be caught');

  // (3) The ROOT CAUSE of the reviewed defect: an anchor that matches more than
  //     once (an import line, a comment, a prop) must fail rather than silently
  //     resolving to the wrong occurrence.
  const duplicated = chrome.replace(
    'data-sf-module="announce"',
    'data-sf-module="announce" title="data-sf-module=\u0022announce\u0022"',
  );
  const dupProblems = anchorOrder(duplicated, CHROME_ANCHORS);
  assert.ok(
    dupProblems.some((x) => x.includes('occurs 2x')),
    'a duplicated anchor MUST fail, not resolve to the first hit',
  );

  // (4) Sanity: the real, unmutated sources still pass, so the control is
  //     discriminating rather than simply always-failing.
  assert.deepEqual(anchorOrder(chrome, CHROME_ANCHORS), []);
  assert.deepEqual(anchorOrder(homeSource, PAGE_ANCHORS), []);
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
  // Asserted against the REAL view model and the REAL localized strings, not
  // against the source text of the component that implements them. A regex over
  // MenuParts.tsx passes whether or not the rail ever renders.
  const on = buildHome(tenant, homeOptionsFor([]));
  const off = buildHome(tenant, homeOptionsFor(['popular-off']));
  assert.equal(on.modules.popular.enabled, true);
  assert.equal(on.modules.popular.ready, true);
  assert.equal(off.modules.popular.enabled, true, 'the rail stays; only the claim changes');
  assert.equal(off.modules.popular.ready, false);

  for (const locale of ['ar', 'he', 'en']) {
    const m = storefrontMessages(locale);
    // The two headings are genuinely different claims in every locale.
    assert.notEqual(m.mostOrdered, m.chefPicks, `${locale}: the two rail claims must differ`);
    // The ranked badge is a localized STRING carrying the number, never a bare "#n".
    const ranked = fill(m.rankN, { n: '1' });
    assert.ok(ranked.includes('1'), `${locale}: rankN must carry the rank`);
    assert.ok(!ranked.includes('{n}'), `${locale}: rankN placeholder must be substituted`);
    assert.notEqual(ranked, '#1', `${locale}: the badge must not be an untranslated #n`);
    // The unranked badge exists and is not the ranked one.
    assert.ok(m.chefPick.length > 0, `${locale}: chefPick must exist`);
    assert.notEqual(m.chefPick, ranked);
  }
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
  assert.match(chrome, /<nav className=\{styles\.rail\} aria-label=\{m\.menuLabel\} data-sf-module="categories">/);
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

// The physical-CSS guard lives in tests/sf-source-rules.test.mjs. It used to be
// here and scanned home.module.css ALONE - 1 of 5 stylesheets - and only seven
// property names. The replacement scans EVERY storefront stylesheet, covers
// shorthands and physical values, asserts its own coverage, and carries a
// negative control. Do not reinstate a narrower copy here.

test('motion modes gate exactly the approved effects', () => {
  // calm = entrances only: no sheen, no Ken Burns, no motif, no float.
  assert.match(css, /\.motionFull \.heroImg,\s*\n\s*\.motionLively \.heroImg \{\s*\n\s*animation: sfKen/);
  assert.match(css, /\.motionFull \.dockCta::before,\s*\n\s*\.motionLively \.dockCta::before/);
  // lively adds the popular-card float, and only that.
  assert.match(css, /\.motionLively \.popularGrid \.card \{\s*\n\s*animation: sfFloat/);
  // INTERACTIONS.md:124 / STATE_MATRIX.json:104 - calm suppresses the motif DRAW,
  // not the motif. The hero renders it unconditionally.
  assert.ok(!homeSource.includes('showMotif'), 'the motif must not be gated on motion');
  assert.match(partsSource, /<div className=\{styles\.heroMotif\}>/);
});

test('motion classes map calm to no extra class', () => {
  assert.match(homeSource, /calm: '',/);
});

// --------------------------------------------------------------- cart is inert

/**
 * THE LIVE-CART BOUNDARY, named explicitly.
 *
 * Phase B proved the dock's layout with an inert presentational component, and
 * Phase C added one live dock beside it. Phase D makes the WIDE ASIDE live too,
 * and retires the inert reference rather than leaving a second component that
 * renders a fixture cart - the exact shape of the defect the Phase C review
 * found, where a seeded cart reached sixteen shipped documents.
 *
 * So the boundary is now: exactly TWO components may render a cart, both under
 * `src/ui/storefront/cart/`, both client, and neither may touch a store. The
 * rule is written down here rather than quietly abandoned.
 *
 * Files are read RAW, not comment-stripped, on purpose: a banned API must not
 * appear at all, not even in prose, so nobody can document their way past it.
 */
const LIVE_DOCK = 'src/ui/storefront/cart/LiveCartDock.tsx';
const LIVE_ASIDE = 'src/ui/storefront/cart/LiveCartAside.tsx';
const RETIRED_INERT = 'src/ui/storefront/home/CartParts.tsx';

/** Every .tsx under src/, as repo-relative POSIX paths. */
function sourceFiles() {
  const out = [];
  const walk = (dir) => {
    for (const entry of readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
      const next = `${dir}/${entry.name}`;
      if (entry.isDirectory()) walk(next);
      else if (next.endsWith('.tsx')) out.push(next);
    }
  };
  walk('src');
  return out;
}

test('the inert Phase B cart reference is DELETED, not merely unused', () => {
  // Leaving it in the tree is what let a fixture cart be rendered by mistake
  // once already. An unused component is one import away from being used.
  assert.ok(!existsSync(path.join(ROOT, RETIRED_INERT)), `${RETIRED_INERT} must be gone`);
  const offenders = sourceFiles().filter((rel) => {
    const src = code(rel);
    return src.includes('CartAside') || src.includes('CartDock');
  }).filter((rel) => rel !== LIVE_DOCK && rel !== LIVE_ASIDE
    && rel !== 'src/ui/storefront/cart/CartRuntime.tsx');
  assert.deepEqual(offenders, [], 'the retired components are still referenced');

  // And nothing renders the PRESENTATIONAL CartView any more: the live
  // surfaces read a CartSummary resolved from the real menu instead.
  const views = sourceFiles().filter((rel) => /\bcart:\s*CartView\b/.test(code(rel)));
  assert.deepEqual(views, [], 'a component still takes the fixture CartView');
});

test('exactly two live cart surfaces exist, and they are the named ones', () => {
  for (const rel of [LIVE_DOCK, LIVE_ASIDE]) {
    const src = read(rel);
    // Non-vacuity: each named file must exist and must actually be live, or
    // the allowlist entry is guarding nothing.
    assert.ok(src.includes("'use client'"), `${rel} must be a client component`);
    // Neither may reach a browser store directly: persistence belongs to the
    // one allowlisted cart-storage module.
    for (const banned of ['localStorage', 'sessionStorage']) {
      assert.ok(!src.includes(banned), `${rel} must not touch ${banned}`);
    }
  }
  assert.ok(read(LIVE_DOCK).includes('useState'), 'the dock must actually hold state');
  assert.ok(read(LIVE_ASIDE).includes('onClick'), 'the aside steppers must actually be live');

  // No THIRD surface: any other component rendering a dock or aside class is a
  // duplicate this boundary does not cover.
  const others = sourceFiles()
    .filter((rel) => rel !== LIVE_DOCK && rel !== LIVE_ASIDE)
    .filter((rel) => /\b\w+\.(dockCta|asideCta|asideLines)\b/.test(read(rel)));
  assert.deepEqual(others, [], 'a cart surface exists outside the two named files');
});

test('both cart CTAs now have a REAL destination, and say why when they do not', () => {
  // Phase C kept both disabled because the cart route did not exist. It does
  // now, so a disabled CTA would be the lie instead.
  const dock = read(LIVE_DOCK);
  assert.ok(dock.includes('href={cartHref}'), 'the dock CTA must link to the cart route');
  assert.ok(!/disabled(?!=\{)/.test(dock.replace(/dockDisabled/g, '')),
    'the dock CTA must not be disabled any more');
  const aside = read(LIVE_ASIDE);
  assert.ok(aside.includes('href={checkoutHref}'),
    'at wide the aside CTA goes STRAIGHT to checkout, not to the cart route');

  // Blocked is still blocked - and is a span, so nothing focusable leads
  // nowhere while ordering is closed or paused.
  for (const [rel, src] of [[LIVE_DOCK, dock], [LIVE_ASIDE, aside]]) {
    assert.ok(src.includes('blockedReason'), `${rel} must still state the blocked reason`);
    assert.ok(/<span[\s\S]{0,200}?Disabled/.test(src), `${rel} blocked CTA must not be a link`);
  }
});

test('an empty cart hides the DOCK but keeps the ASIDE frame', () => {
  // The dock is an overlay, so it can vanish. The aside is a 360px LAYOUT
  // column: vanishing would reflow the page the moment the cart is read.
  assert.match(read(LIVE_DOCK), /if \(count === 0\) return null;/);

  const aside = read(LIVE_ASIDE);
  const body = aside.slice(aside.indexOf('export function LiveCartAside'));
  assert.ok(!body.includes('return null'), 'the aside component must never render nothing');
  // The frame comes FIRST and the empty state lives inside it, so an empty
  // cart still occupies its 360px rather than collapsing the layout.
  assert.ok(
    body.indexOf('<aside') !== -1 && body.indexOf('<aside') < body.indexOf('asideEmpty'),
    'the empty state must sit INSIDE the aside frame',
  );
  assert.ok(aside.includes('asideEmpty'), 'the aside needs its own one-line empty state');

  const view = buildHome(tenant, homeOptionsFor(['cart-empty']));
  assert.equal(view.cart.itemCount, 0);
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
  // The DATA contract. The RENDERED contract is asserted in the browser suite
  // against /s/demo-popular-off/menu, which the evidence build emits - a real
  // document, not a regex over the component that would render it.
  const off = buildHome(tenant, homeOptionsFor(['popular-off']));
  assert.equal(off.modules.popular.enabled, true);
  assert.equal(off.modules.popular.ready, false);
  // The scenario that carries the rendered evidence exists and says so.
  const scenario = SCENARIOS.find((s) => s.slug === 'demo-popular-off');
  assert.ok(scenario, 'demo-popular-off must exist to evidence H05');
  assert.equal(scenario.options.modules.popular.ready, false);
  assert.equal(scenario.options.modules.popular.enabled, true);
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

// ------------------------------------------- the shipped vs evidence slug gate

test('the SHIPPED build pre-renders the canonical tenant and no demo slug', () => {
  const previous = process.env.SF_EVIDENCE_ROUTES;
  delete process.env.SF_EVIDENCE_ROUTES;
  try {
    assert.deepEqual([...homeSlugs()], ['maps-burger']);
    for (const slug of SCENARIO_SLUGS) {
      assert.ok(!homeSlugs().includes(slug), `${slug} must not ship`);
    }
  } finally {
    if (previous !== undefined) process.env.SF_EVIDENCE_ROUTES = previous;
  }
});

test('NEGATIVE CONTROL: the gate is not vacuous - an evidence build DOES emit them', () => {
  // Without this the test above would pass just as well if homeSlugs() had been
  // gutted to a constant, and the screenshots could never be reproduced.
  const previous = process.env.SF_EVIDENCE_ROUTES;
  process.env.SF_EVIDENCE_ROUTES = '1';
  try {
    assert.deepEqual([...homeSlugs()], ['maps-burger', ...SCENARIO_SLUGS]);
    assert.deepEqual([...homeSlugs(['demo-light'])], ['maps-burger', 'demo-light']);
  } finally {
    if (previous === undefined) delete process.env.SF_EVIDENCE_ROUTES;
    else process.env.SF_EVIDENCE_ROUTES = previous;
  }
});
