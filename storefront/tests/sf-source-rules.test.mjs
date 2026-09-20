// Architectural rules the UI layer must obey. These are the ones that are cheap
// to violate by accident and expensive to notice later: an inline style the CSP
// silently blocks, a tenant colour frozen into a component, a fixture escaping
// its layer, or a float creeping into money.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { buildTheme } = await import('../src/theme/buildTheme.ts');
const { NEUTRAL_PRIMARY, NEUTRAL_ACCENT_DARK, NEUTRAL_ACCENT_LIGHT } = await import(
  '../src/theme/sanitize.ts'
);

function walk(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const full = path.join(dir, e.name);
    return e.isDirectory() ? walk(full) : [full];
  });
}

const rel = (f) => path.relative(ROOT, f).split(path.sep).join('/');

/**
 * These guards are about CODE, not prose. A file is allowed to NAME a forbidden
 * construct while explaining why it does not use one, so comments are removed
 * before any rule is applied.
 */
function code(file) {
  return readFileSync(file, 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*/gm, '$1 ');
}
const ALL = [...walk(path.join(ROOT, 'app')), ...walk(path.join(ROOT, 'src'))];
const TSX = ALL.filter((f) => /\.tsx?$/.test(f));
const CSS = ALL.filter((f) => f.endsWith('.css'));

// The demo tenant's data legitimately contains its own brand colours.
const FIXTURE_LAYER = ['src/source/fixtures.ts'];

test('no app file emits an inline style attribute or style prop', () => {
  // `style-src 'self'` has no 'unsafe-inline': an inline style is silently
  // dropped by the browser, so this must be caught at source.
  for (const f of TSX) {
    const src = readFileSync(f, 'utf8');
    assert.ok(!/\bstyle\s*=\s*\{/.test(src), `${rel(f)}: React style prop`);
    assert.ok(!/\bstyle\s*=\s*"/.test(src), `${rel(f)}: literal style attribute`);
  }
});

test('no app file uses dangerouslySetInnerHTML', () => {
  for (const f of TSX) {
    assert.ok(!code(f).includes('dangerouslySetInnerHTML'), `${rel(f)}: dangerouslySetInnerHTML`);
  }
});

test('the only inline-style mechanism is CSSOM setProperty, in one file', () => {
  const users = TSX.filter((f) => /\.style\.setProperty\(/.test(code(f)));
  assert.deepEqual(users.map(rel), ['src/ui/storefront/ThemeScope.tsx'],
    'CSSOM theming must stay in exactly one place');
});

test('no Maps Burger derived colour is hard-coded in the UI or stylesheets', () => {
  // Computed, not hand-listed: anything the DEMO tenant's inputs derive that the
  // BIZBOT-neutral inputs do NOT is a tenant-specific value and must not appear
  // in a component or a stylesheet.
  const hexes = (tokens) =>
    new Set(
      Object.values(tokens)
        .flatMap((v) => v.match(/#[0-9a-fA-F]{6}/g) ?? [])
        .map((h) => h.toLowerCase()),
    );
  const demo = new Set([
    ...hexes(buildTheme('dark', { primary: '#123027', accent: '#FF8A2A' })),
    ...hexes(buildTheme('light', { primary: '#123027', accent: '#C2410C' })),
    '#123027', '#ff8a2a', '#c2410c',
  ]);
  const neutral = new Set([
    ...hexes(buildTheme('dark', { primary: NEUTRAL_PRIMARY, accent: NEUTRAL_ACCENT_DARK })),
    ...hexes(buildTheme('light', { primary: NEUTRAL_PRIMARY, accent: NEUTRAL_ACCENT_LIGHT })),
  ]);
  const tenantOnly = [...demo].filter((h) => !neutral.has(h));
  assert.ok(tenantOnly.length > 0, 'the guard must have something to look for');

  for (const f of [...TSX, ...CSS]) {
    if (FIXTURE_LAYER.includes(rel(f))) continue;
    const src = code(f).toLowerCase();
    for (const hex of tenantOnly) {
      assert.ok(!src.includes(hex), `${rel(f)}: hard-coded tenant colour ${hex}`);
    }
  }
});

test('the fixture scenario switch never leaves the fixture layer', () => {
  for (const f of [...TSX, ...CSS]) {
    if (FIXTURE_LAYER.includes(rel(f))) continue;
    const src = readFileSync(f, 'utf8');
    assert.ok(!/\bfx=/.test(src), `${rel(f)}: ?fx= outside the fixture layer`);
    assert.ok(!/applyScenario|FIXTURE_SCENARIOS/.test(src), `${rel(f)}: scenario API leaked`);
  }
});

test('the Unknown screen receives no tenant data at all', () => {
  const src = code(path.join(ROOT, 'src/ui/storefront/Unknown.tsx'));
  for (const forbidden of ['Tenant', 'fixtureSource', 'buildTheme', 'storefront.module.css']) {
    assert.ok(!src.includes(forbidden), `Unknown.tsx must not reference ${forbidden}`);
  }
  // And its own stylesheet must not read a tenant custom property.
  const css = code(path.join(ROOT, 'src/ui/storefront/Unknown.module.css'));
  for (const token of ['--bg', '--sf', '--acc', '--hero', '--tx']) {
    assert.ok(!css.includes(`var(${token})`), `Unknown.module.css must not use var(${token})`);
  }
});

test('money never touches a float', () => {
  for (const f of TSX.filter((x) => !x.includes('money'))) {
    const src = code(f);
    assert.ok(!/Minor\s*[:=]\s*\d+\.\d/.test(src), `${rel(f)}: fractional minor units`);
    assert.ok(!/parseFloat\s*\(/.test(src), `${rel(f)}: parseFloat near money`);
    assert.ok(!/toFixed\s*\(\s*2\s*\)/.test(src), `${rel(f)}: toFixed(2) money formatting`);
  }
  const fixtures = code(path.join(ROOT, 'src/source/fixtures.ts'));
  for (const m of fixtures.matchAll(/Minor:\s*([\d.]+)/g)) {
    assert.ok(Number.isInteger(Number(m[1])), `fixtures.ts: ${m[1]} is not an integer`);
  }
});

test('the app layer makes no network call and reads no browser storage', () => {
  for (const f of TSX) {
    const src = code(f);
    for (const api of ['fetch(', 'XMLHttpRequest', 'WebSocket', 'navigator.sendBeacon',
      'localStorage', 'sessionStorage', 'indexedDB', 'document.cookie']) {
      assert.ok(!src.includes(api), `${rel(f)}: ${api} is not part of Phase A`);
    }
  }
});

test('no component hard-codes a route string instead of using the builders', () => {
  for (const f of TSX.filter((x) => !x.includes('routes'))) {
    const src = code(f);
    // A literal href to a locale-prefixed storefront path would bypass
    // switchLocalePath and rot the moment the route shape changes.
    assert.ok(!/href="\/(ar|he|en)\//.test(src), `${rel(f)}: hard-coded locale route`);
    assert.ok(!/href="\/s\//.test(src), `${rel(f)}: hard-coded storefront route`);
  }
});

test('every storefront stylesheet is a CSS Module', () => {
  for (const f of CSS) {
    const name = path.basename(f);
    if (rel(f).startsWith('app/')) continue; // globals.css is the shell's
    assert.ok(name.endsWith('.module.css'), `${rel(f)}: must be a CSS Module`);
  }
});

test('no source file contains a literal control or bidi-override character', () => {
  // Writing these as escape sequences is one edit away from writing them as the
  // characters themselves. That makes the file BINARY to git - unreviewable in a
  // diff - and a stray bidi override can reorder how the source itself reads.
  // Found for real in this phase, in sanitize.ts and its own test.
  const offending = (cp) =>
    (cp < 0x20 && cp !== 0x09 && cp !== 0x0a && cp !== 0x0d) ||
    cp === 0x7f ||
    (cp >= 0x202a && cp <= 0x202e) ||
    (cp >= 0x2066 && cp <= 0x2069);
  for (const f of [...TSX, ...CSS, ...ALL.filter((x) => x.endsWith('.json'))]) {
    const text = readFileSync(f, 'utf8');
    for (let i = 0; i < text.length; i += 1) {
      const cp = text.codePointAt(i);
      assert.ok(
        !offending(cp),
        `${rel(f)}: literal U+${cp.toString(16).padStart(4, '0').toUpperCase()} at offset ${i}`,
      );
    }
  }
});
