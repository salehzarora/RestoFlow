// Architectural rules the UI layer must obey. These are the ones that are cheap
// to violate by accident and expensive to notice later: an inline style the CSP
// silently blocks, a tenant colour frozen into a component, a fixture escaping
// its layer, or a float creeping into money.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, readdirSync, existsSync, mkdirSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
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
// The locale dictionaries are the likeliest place for an invisible bidi
// character to hide, because they are the only files that legitimately contain
// right-to-left text. They live in messages/, outside app/ and src/, so the
// source-hygiene guard below scans them explicitly (Phase A review, MINOR-2).
const DICTIONARIES = walk(path.join(ROOT, 'messages')).filter((f) => f.endsWith('.json'));
const PUBLIC_JSON = walk(path.join(ROOT, 'public')).filter((f) => f.endsWith('.json'));
const TSX = ALL.filter((f) => /\.tsx?$/.test(f));
const CSS = ALL.filter((f) => f.endsWith('.css'));

/**
 * The ONE module allowed to make a network request (STOREFRONT-READ-001): the
 * server-only live read client. Every other file - client islands above all -
 * stays network-free; the runtime guard, the import discipline test and the
 * emitted-chunk scan (tests/output) are the other two layers.
 */
const LIVE_CLIENT_MODULE = 'src/source/live/client.ts';

// The demo tenant's data legitimately contains its own brand colours.
const FIXTURE_LAYER = [
  'src/source/fixtures.ts',
  'src/source/home.ts',
  'src/source/menu-fixture.ts',
  'src/source/scenarios.ts',
  // Phase D: the three cart notices and the four send failures have no honest
  // trigger yet - which lines changed is a server answer that does not exist -
  // so they are injected from a demo token. That machinery belongs HERE, with
  // the other fixtures it disappears with, and not inside a component.
  'src/source/flow-scenarios.ts',
  // Phase E: the one demo ref, the demo request, the demo status source and
  // the request route's own scenario allowlist.
  'src/source/request-fixture.ts',
  'src/source/request-ref.ts',
  'src/source/request-scenarios.ts',
];

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

/**
 * The hyphenated demo tokens. Deliberately NOT the typed result kinds: a
 * component legitimately names `server_error`, because that is the shape it
 * renders; what it must never name is the URL token that selects it.
 */
const DEMO_TOKENS = [
  'cart-changed', 'cart-price', 'cart-sold-out',
  'server-error', 'rate-limited', 'quote-race',
  // Phase E: the request route's tokens. A component renders a STATE it was
  // given; it never names the URL token that selects one.
  'status-received', 'status-waiting', 'status-accepted', 'status-preparing', 'status-ready',
  'status-completed', 'status-rejected', 'status-expired', 'status-cancelled',
  'status-accepts-late', 'status-expires-late', 'status-missing', 'wa-fallback',
];

test('the fixture scenario switch never leaves the fixture layer', () => {
  for (const f of [...TSX, ...CSS]) {
    if (FIXTURE_LAYER.includes(rel(f))) continue;
    const src = code(f);
    assert.ok(!/\bfx=/.test(src), `${rel(f)}: ?fx= outside the fixture layer`);
    assert.ok(!/applyScenario|FIXTURE_SCENARIOS/.test(src), `${rel(f)}: scenario API leaked`);
    // Building the parameter out of pieces is the same leak with one extra
    // step, so the bare token is forbidden too - otherwise the rule above is
    // satisfied by concatenation rather than by the machinery staying put.
    assert.ok(!/['"`]fx['"`]/.test(src), `${rel(f)}: the scenario parameter leaked`);
    for (const token of DEMO_TOKENS) {
      assert.ok(!src.includes(token), `${rel(f)}: the demo token ${token} leaked`);
    }
  }
});

test('NEGATIVE CONTROL: the scenario rule catches every way of spelling it', () => {
  // A guard that cannot fail proves nothing, and this one grew two clauses
  // precisely because the first was satisfiable by writing the parameter in
  // two halves.
  const attempts = [
    `const url = '/s/x/cart?fx=' + token;`,
    `const PARAM = 'fx';`,
    `if (token === "quote-race") slow();`,
    `params.set(\`fx\`, 'cart-sold-out');`,
  ];
  for (const attempt of attempts) {
    const caught =
      /\bfx=/.test(attempt) ||
      /['"`]fx['"`]/.test(attempt) ||
      DEMO_TOKENS.some((t) => attempt.includes(t));
    assert.ok(caught, `the rule would MISS: ${attempt}`);
  }
  // And it does not fire on ordinary source that merely contains those letters.
  for (const innocent of ['const effects = fixtures.map(f => f.x);', 'const fxRate = 1;']) {
    const caught =
      /\bfx=/.test(innocent) ||
      /['"`]fx['"`]/.test(innocent) ||
      DEMO_TOKENS.some((t) => innocent.includes(t));
    assert.ok(!caught, `the rule is too broad: ${innocent}`);
  }
});

/**
 * STOREFRONT-READ-001 - the SERVER-ONLY boundary of the live read.
 *
 * The source switch (src/source/storefront.ts) and everything under
 * src/source/live may be imported by route files (server components) only.
 * A client module ('use client') that imported them would drag the env reads
 * and the network client into a browser bundle; nothing under src/ui may
 * import them at all. `process.env` is read in exactly the named server
 * modules, never in a component.
 */
const SERVER_ONLY_MODULES = ['@/source/storefront', '@/source/live/', './live/', '../live/'];
const ENV_READERS = ['src/source/storefront.ts', 'src/source/live/client.ts', 'src/source/home.ts', 'src/source/request-fixture.ts'];

test('the live read stays server-only: no client module and no UI module imports it', () => {
  for (const f of TSX) {
    const src = code(f);
    const imports = SERVER_ONLY_MODULES.filter((m) => src.includes(`from '${m}`) || src.includes(`from "${m}`));
    if (imports.length === 0) continue;
    const where = rel(f);
    assert.ok(!/^\s*'use client'/m.test(readFileSync(f, 'utf8')), `${where}: a client module imports the live read (${imports.join(', ')})`);
    assert.ok(!where.startsWith('src/ui/'), `${where}: a UI module imports the live read (${imports.join(', ')})`);
  }
  // Non-vacuity: the route files DO import the switch.
  const routes = TSX.filter((f) => rel(f).startsWith('app/') && code(f).includes("from '@/source/storefront'"));
  assert.equal(routes.length, 28, `expected the 28 slug route files to import the switch, got ${routes.length}`);
});

test('process.env is read only in the named server modules, and never in a component', () => {
  const readers = TSX.filter((f) => /\bprocess\.env\b/.test(code(f))).map(rel).sort();
  assert.deepEqual(readers, [...ENV_READERS].sort());
  for (const f of TSX) {
    if (rel(f).endsWith('.tsx')) assert.ok(!/\bprocess\.env\b/.test(code(f)), `${rel(f)}: a component reads the environment`);
  }
  // Every env name is server-only: no NEXT_PUBLIC_ name anywhere in the CODE
  // (a comment may name it while explaining why it is not used).
  for (const f of TSX) assert.ok(!/NEXT_PUBLIC_/.test(code(f)), `${rel(f)}: NEXT_PUBLIC_ would reach the browser`);
});

test('the live client guards against a browser at runtime and names the two server-only variables', () => {
  const src = code(path.join(ROOT, LIVE_CLIENT_MODULE));
  assert.ok(src.includes("typeof window !== 'undefined'"), 'the runtime guard must exist');
  assert.ok(src.includes('STOREFRONT_SUPABASE_URL') && src.includes('STOREFRONT_SUPABASE_ANON_KEY'));
  assert.ok(src.includes('AbortSignal.timeout('), 'the read must be bounded by a timeout');
  // Exactly one fetch( call site in the whole tree, and it is here.
  const sites = TSX.filter((f) => code(f).includes('fetch(')).map(rel);
  assert.deepEqual(sites, [LIVE_CLIENT_MODULE]);
});

test('the category icon path never comes from tenant data: the adapter resolves it from the registry', () => {
  const adapter = code(path.join(ROOT, 'src/source/live/adapter.ts'));
  assert.ok(adapter.includes('iconPath: iconPathFor(c.icon_key)'), 'iconPath must come from iconPathFor()');
  assert.ok(!/iconPath:\s*c\.(?!icon_key)/.test(adapter), 'no wire field may become an SVG path');
  const icons = code(path.join(ROOT, 'src/source/live/icons.ts'));
  const keys = [...icons.matchAll(/^  ([a-z][a-z0-9_]*): '/gm)].map((m) => m[1]);
  assert.equal(keys.length, 49, `the registry mirrors the 49 Dashboard keys, got ${keys.length}`);
  assert.equal(new Set(keys).size, 49, 'no duplicate key');
  for (const k of ['burger', 'pizza', 'coffee', 'salad', 'offers', 'menu']) assert.ok(keys.includes(k), `missing key ${k}`);
  // Every path is 24-grid path data: digits, letters of the SVG path grammar, dots, spaces, minus.
  for (const m of icons.matchAll(/^  [a-z][a-z0-9_]*: '([^']+)'/gm)) {
    assert.match(m[1], /^[MmLlHhVvCcSsQqTtAaZz0-9 .,-]+$/, `path data only: ${m[1].slice(0, 30)}`);
    assert.ok(m[1].startsWith('M'), 'every path starts with a moveto');
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

/**
 * The ONE module allowed to touch a browser store, named by the same POSIX
 * relative path `rel()` produces, because that is what the file walk yields.
 *
 * The blanket ban this replaces was a Phase A convention, not an approved rule:
 * the handoff REQUIRES a real per-slug session flag (DESIGN_HANDOFF.md:27,
 * INTERACTIONS.md:10 "Nature: product behaviour", COMPONENT_INVENTORY.md:9), so
 * the guard is narrowed to an exact allowlist rather than the design degraded.
 */
const UI_SESSION_MODULE = 'src/session/uiSession.ts';

/**
 * The ONE module allowed to touch the LONG-LIVED store, added for Phase C.
 *
 * WIDENED DELIBERATELY, not routed around. `localStorage` was previously in
 * BANNED_EVERYWHERE because nothing was allowed to persist. Phase C's approved
 * contract requires a per-slug cart at the exact key `sf:v1:cart:<slug>`, so
 * the ban becomes a second EXACT allowlist entry rather than a hole: the two
 * stores are confined independently, and neither module may reach the other's
 * store (proved by the negative control below).
 */
const CART_STORAGE_MODULE = 'src/cart/cartStorage.ts';

/**
 * The ONE module allowed to WRITE to the clipboard, added for Phase E. The
 * copy control copies the composed demo message only; confining the API to
 * one file is what makes "only that text" a checkable claim.
 */
const CLIPBOARD_MODULE = 'src/ui/storefront/request/clipboard.ts';

/** The store each module owns. Every other file may touch neither. */
const STORE_OWNERS = [
  ['sessionStorage', UI_SESSION_MODULE],
  ['localStorage', CART_STORAGE_MODULE],
  ['fetch(', LIVE_CLIENT_MODULE],
  // Any spelling of the clipboard object - navigator.clipboard, a local alias,
  // window.navigator.clipboard - contains this member access.
  ['.clipboard', CLIPBOARD_MODULE],
];

/** Banned in EVERY app/ and src/ file, the allowlisted modules included. */
const BANNED_EVERYWHERE = ['XMLHttpRequest', 'WebSocket', 'navigator.sendBeacon',
  'indexedDB', 'document.cookie',
  // Phase E: no real WhatsApp navigation of any kind (DEFERRED WA-001), and no
  // clipboard READ path anywhere - the write path has exactly one owner below.
  'wa.me', 'whatsapp://', 'api.whatsapp.com', 'window.open(', 'readText('];


/**
 * The rule as a pure function of (path, text), so the negative controls below
 * can run the SAME logic over files that are not in the repository. Comments are
 * stripped first: these rules are about CODE, not prose.
 */
function storageOffence(relPath, source) {
  const src = source
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*/gm, '$1 ');
  for (const api of BANNED_EVERYWHERE) {
    if (src.includes(api)) return `${relPath}: ${api} is not permitted anywhere`;
  }
  for (const [api, owner] of STORE_OWNERS) {
    if (relPath !== owner && src.includes(api)) {
      return `${relPath}: ${api} is allowed ONLY in ${owner}`;
    }
  }
  return null;
}

test('each browser store is confined to its own allowlisted module', () => {
  for (const f of TSX) {
    assert.equal(storageOffence(rel(f), readFileSync(f, 'utf8')), null);
  }
  // Non-vacuity: each allowlisted file must exist AND must actually use the API
  // it is allowlisted for, or that allowlist entry is guarding nothing.
  for (const [api, owner] of STORE_OWNERS) {
    const helper = TSX.find((f) => rel(f) === owner);
    assert.ok(helper, `${owner} must exist`);
    assert.ok(code(helper).includes(api), `${owner} must actually use ${api}`);
  }
});

test('the UI-session module stores only the two approved boolean flags', () => {
  const src = code(path.join(ROOT, UI_SESSION_MODULE));
  // Exactly two key shapes, one namespace, one value, and no generic accessor.
  assert.match(src, /const NAMESPACE = 'sf:v1:';/);
  assert.match(src, /type Flag = 'seen' \| 'announcement-dismissed';/);
  assert.match(src, /const TRUE_VALUE = '1';/);
  // setItem is called in exactly one place, and never with a caller-supplied value.
  assert.equal((src.match(/\.setItem\(/g) ?? []).length, 1);
  assert.match(src, /found\.setItem\(key, TRUE_VALUE\)/);
  // No JSON payload can be smuggled through this module.
  assert.ok(!src.includes('JSON.stringify'), 'no JSON payload may be stored');
  assert.ok(!src.includes('JSON.parse'), 'no JSON payload may be read back');
  // The slug is validated, never trusted.
  assert.match(src, /isValidSlug\(slug\)/);
});

test('NEGATIVE CONTROL: the storage rule fails on an unauthorised FILE and an unauthorised STORE', () => {
  // Copies in a temp tree. The committed source is never written to.
  const dir = mkdtempSync(path.join(tmpdir(), 'sf-storage-'));
  try {
    const copy = (relPath) => {
      const dest = path.join(dir, relPath);
      mkdirSync(path.dirname(dest), { recursive: true });
      writeFileSync(dest, readFileSync(path.join(ROOT, relPath), 'utf8'), 'utf8');
      return dest;
    };
    const relOf = (f) => path.relative(dir, f).split(path.sep).join('/');
    const helperCopy = copy(UI_SESSION_MODULE);
    const otherCopy = copy('src/ui/storefront/Intro.tsx');

    // Verbatim copies behave exactly as the real tree does.
    assert.equal(storageOffence(relOf(helperCopy), readFileSync(helperCopy, 'utf8')), null,
      'the allowlisted module must be allowed');
    assert.equal(storageOffence(relOf(otherCopy), readFileSync(otherCopy, 'utf8')), null);

    // An unauthorised FILE using the allowlisted API must be caught.
    writeFileSync(otherCopy,
      readFileSync(otherCopy, 'utf8') + '\nconst leak = sessionStorage.getItem("sf:v1:seen:x");\n',
      'utf8');
    const caughtFile = storageOffence(relOf(otherCopy), readFileSync(otherCopy, 'utf8'));
    assert.ok(caughtFile !== null, 'the rule MISSED sessionStorage in an unauthorised file');
    assert.match(caughtFile, /sessionStorage is allowed ONLY/);

    // The two allowlists are SEPARATE. The session module may not reach the
    // long-lived store...
    writeFileSync(helperCopy,
      readFileSync(helperCopy, 'utf8') + '\nconst leak = localStorage.getItem("x");\n', 'utf8');
    const crossed = storageOffence(relOf(helperCopy), readFileSync(helperCopy, 'utf8'));
    assert.ok(crossed !== null, 'the session allowlist must NOT extend to a long-lived store');
    assert.match(crossed, /localStorage is allowed ONLY/);

    // ...and the cart module may not reach the session store.
    const cartCopy = copy(CART_STORAGE_MODULE);
    assert.equal(storageOffence(relOf(cartCopy), readFileSync(cartCopy, 'utf8')), null,
      'the cart storage module must be allowed its own store');
    writeFileSync(cartCopy,
      readFileSync(cartCopy, 'utf8') + '\nconst leak = sessionStorage.getItem("x");\n', 'utf8');
    const crossedBack = storageOffence(relOf(cartCopy), readFileSync(cartCopy, 'utf8'));
    assert.ok(crossedBack !== null, 'the cart allowlist must NOT extend to the session store');
    assert.match(crossedBack, /sessionStorage is allowed ONLY/);

    // An unauthorised file making a NETWORK request must be caught too
    // (STOREFRONT-READ-001: fetch( has exactly one owner, the server client).
    const islandCopy = copy('src/ui/storefront/StorefrontRuntime.tsx');
    assert.equal(storageOffence(relOf(islandCopy), readFileSync(islandCopy, 'utf8')), null);
    writeFileSync(islandCopy,
      readFileSync(islandCopy, 'utf8') + "\nconst leak = fetch('/rest/v1/rpc/storefront_menu');\n", 'utf8');
    const caughtFetch = storageOffence(relOf(islandCopy), readFileSync(islandCopy, 'utf8'));
    assert.ok(caughtFetch !== null, 'the rule MISSED fetch( in a client island');
    assert.match(caughtFetch, /fetch\( is allowed ONLY/);

    // An unauthorised file using the LONG-LIVED store must be caught too.
    // The checkout draft module is the sharpest subject for it: it is the one
    // file whose whole contract is that customer fields never reach a store.
    const thirdCopy = copy('src/ui/storefront/checkout/CheckoutDraftProvider.tsx');
    assert.equal(storageOffence(relOf(thirdCopy), readFileSync(thirdCopy, 'utf8')), null);
    writeFileSync(thirdCopy,
      readFileSync(thirdCopy, 'utf8') + '\nconst leak = localStorage.getItem("sf:v1:cart:x");\n',
      'utf8');
    const caughtLong = storageOffence(relOf(thirdCopy), readFileSync(thirdCopy, 'utf8'));
    assert.ok(caughtLong !== null, 'the rule MISSED localStorage in an unauthorised file');
    assert.match(caughtLong, /localStorage is allowed ONLY/);

    // ...and naming the API in prose is not an offence.
    assert.equal(
      storageOffence('src/ui/storefront/Intro.tsx',
        '// this file deliberately does not use sessionStorage\nexport const a = 1;\n'),
      null,
    );
  } finally {
    rmSync(dir, { recursive: true, force: true });
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

/**
 * Characters that must never appear LITERALLY in source.
 *
 * Writing them as escape sequences is one careless edit away from writing the
 * characters themselves: that makes a file BINARY to git, so its diff cannot be
 * reviewed, and a stray bidi override can reorder how the surrounding source
 * reads. Both happened for real in Phase A.
 */
function offendingCodePoint(cp) {
  return (
    (cp < 0x20 && cp !== 0x09 && cp !== 0x0a && cp !== 0x0d) || // C0, keeping tab/LF/CR
    cp === 0x7f || // DEL
    (cp >= 0x202a && cp <= 0x202e) || // bidi embeddings and overrides
    (cp >= 0x2066 && cp <= 0x2069) || // bidi isolates
    cp === 0x200e || // LRM
    cp === 0x200f || // RLM
    cp === 0xfeff // BOM / zero-width no-break space
  );
}

/** Every literal offender in one file, as {codePoint, offset}. */
function scanFile(file) {
  const text = readFileSync(file, 'utf8');
  const hits = [];
  for (let i = 0; i < text.length; i += 1) {
    const cp = text.codePointAt(i);
    if (offendingCodePoint(cp)) hits.push({ codePoint: cp, offset: i });
  }
  return hits;
}

const HYGIENE_SCOPE = [...TSX, ...CSS, ...DICTIONARIES, ...PUBLIC_JSON,
  ...ALL.filter((x) => x.endsWith('.json'))];

test('the source-hygiene guard actually covers the locale dictionaries', () => {
  // Guards against the Phase A MINOR-2 regression: the scope must include the
  // RTL dictionaries, or the check is vacuous exactly where it matters most.
  assert.ok(DICTIONARIES.length >= 6, `expected the locale dictionaries, found ${DICTIONARIES.length}`);
  const covered = new Set(HYGIENE_SCOPE.map(rel));
  for (const code of ['ar', 'he', 'en']) {
    assert.ok(covered.has(`messages/${code}.json`), `messages/${code}.json must be scanned`);
    assert.ok(covered.has(`messages/storefront.${code}.json`), `messages/storefront.${code}.json must be scanned`);
  }
  assert.ok(HYGIENE_SCOPE.length >= 45, `scope looks too small: ${HYGIENE_SCOPE.length}`);
});

test('no source file or dictionary contains a literal control or bidi character', () => {
  for (const f of HYGIENE_SCOPE) {
    for (const hit of scanFile(f)) {
      assert.fail(
        `${rel(f)}: literal U+${hit.codePoint.toString(16).padStart(4, '0').toUpperCase()} at offset ${hit.offset}`,
      );
    }
  }
});

test('NEGATIVE CONTROL: the guard fails on an injected bad dictionary', () => {
  // A clean run only means something if the scanner can see a dirty file. The
  // fixture is BUILT AT RUNTIME from code points, so this repository never
  // contains the literal characters it is testing for, and it is removed again
  // immediately.
  const dir = mkdtempSync(path.join(tmpdir(), 'sf-hygiene-'));
  const ch = (cp) => String.fromCharCode(cp);
  try {
    const cases = [
      ['rlo', 0x202e, 'bidi override'],
      ['lri', 0x2066, 'bidi isolate'],
      ['nul', 0x0000, 'C0 control'],
      ['del', 0x007f, 'DEL'],
      ['rlm', 0x200f, 'right-to-left mark'],
      ['bom', 0xfeff, 'zero-width no-break space'],
    ];
    for (const [name, cp, label] of cases) {
      const file = path.join(dir, `bad-${name}.json`);
      // Written as RAW text, not via JSON.stringify: stringify escapes C0
      // controls back into escape sequences, which would leave this fixture
      // clean and the negative control vacuous. The guard is a character scan,
      // so the character has to actually be present in the bytes.
      writeFileSync(file, `{"welcome":"a${ch(cp)}b"}`, 'utf8');
      const hits = scanFile(file);
      assert.ok(hits.length > 0, `guard MISSED ${label} (U+${cp.toString(16)})`);
      assert.equal(hits[0].codePoint, cp);
    }
    // ...and a clean dictionary with real RTL text must NOT be flagged.
    const good = path.join(dir, 'good.json');
    writeFileSync(good, '{"ar":"مفتوح الآن","he":"פתוח עכשיו","en":"Open now"}', 'utf8');
    assert.deepEqual(scanFile(good), [], 'real Arabic/Hebrew text must not be flagged');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// ------------------------------------------------- logical properties in CSS

/**
 * Physical, direction-sensitive CSS. One tree serves ar/he RTL and en LTR, so a
 * physical inline side is a mirroring bug waiting to happen.
 *
 * This guard replaces one that scanned home.module.css ALONE - 1 of 5
 * stylesheets - and matched only seven property names. It missed shorthands,
 * physical VALUES, and every other sheet. LanguageMenu.module.css carries a
 * real physical declaration that the old guard could never have seen.
 */
const PHYSICAL_PATTERNS = [
  ['margin-left/right', /(?<![-\w])margin-(?:left|right)\s*:/],
  ['padding-left/right', /(?<![-\w])padding-(?:left|right)\s*:/],
  ['border-left/right', /(?<![-\w])border-(?:left|right)\s*:/],
  ['bare left/right offset', /(?<![-\w])(?:left|right)\s*:\s*[^;]+;/],
  ['text-align: left|right', /text-align\s*:\s*(?:left|right)\b/],
  ['float|clear: left|right', /(?:float|clear)\s*:\s*(?:left|right)\b/],
  ['background-position left|right', /background-position\s*:[^;]*(?<![-\w])(?:left|right)\b/],
  ['scroll-padding/margin l|r', /scroll-(?:padding|margin)-(?:left|right)\s*:/],
];

/**
 * Documented, deliberate exceptions. Each entry must STILL MATCH something, so
 * a stale exemption fails instead of quietly widening the guard. An over-strict
 * guard that has to be suppressed everywhere is a failed guard; an unaudited
 * exemption list is worse. Keep this short and justified.
 */
const PHYSICAL_EXCEPTIONS = [
  {
    file: 'src/ui/storefront/LanguageMenu.module.css',
    snippet: 'border-right: 2px solid currentColor;',
    why:
      'The caret is a SHAPE, not a layout offset: an 8x8 box with its right and ' +
      'bottom borders, rotated 45deg, draws a chevron pointing DOWN. A down ' +
      'chevron is identical under mirroring, and switching to border-inline-end ' +
      'would rotate the glyph sideways in RTL - a regression, not a fix.',
  },
];

/** Split a shorthand on top-level whitespace, so env(a, b) stays one value. */
function shorthandValues(value) {
  const out = [];
  let depth = 0;
  let current = '';
  for (const ch of value) {
    if (ch === '(') depth += 1;
    if (ch === ')') depth -= 1;
    if (depth === 0 && /\s/.test(ch)) {
      if (current) out.push(current);
      current = '';
    } else {
      current += ch;
    }
  }
  if (current) out.push(current);
  return out;
}

/** All physical-CSS problems in one stylesheet, comments stripped. */
function physicalProblems(relPath, source) {
  let text = source.replace(/\/\*[\s\S]*?\*\//g, ' ');
  for (const e of PHYSICAL_EXCEPTIONS) {
    if (e.file === relPath) text = text.split(e.snippet).join(' /* allowed */ ');
  }
  const problems = [];
  for (const [name, rx] of PHYSICAL_PATTERNS) {
    if (rx.test(text)) problems.push(`${relPath}: physical ${name}`);
  }
  // A four-value margin/padding/inset whose INLINE sides differ is
  // direction-sensitive even though every part is physical-by-design.
  for (const prop of ['margin', 'padding', 'inset']) {
    const rx = new RegExp('(?<![-\\w])' + prop + '\\s*:\\s*([^;{}]+);', 'g');
    for (const m of text.matchAll(rx)) {
      const parts = shorthandValues(m[1].trim());
      if (parts.length === 4 && parts[1] !== parts[3]) {
        problems.push(`${relPath}: asymmetric 4-value ${prop}: ${m[1].trim()}`);
      }
    }
  }
  return problems;
}

test('every storefront stylesheet uses logical properties, not physical sides', () => {
  // COVERAGE FIRST. The Phase A dictionary guard passed while matching zero
  // files; a scan whose scope can silently fall to zero proves nothing.
  const sheets = CSS.map(rel).sort();
  assert.ok(sheets.length >= 5, `expected at least 5 stylesheets, scanned ${sheets.length}`);
  for (const expected of [
    'src/ui/storefront/Intro.module.css',
    'src/ui/storefront/LanguageMenu.module.css',
    'src/ui/storefront/Unknown.module.css',
    'src/ui/storefront/home/home.module.css',
    'src/ui/storefront/storefront.module.css',
  ]) {
    assert.ok(sheets.includes(expected), `${expected} must be in scope`);
  }

  const problems = [];
  for (const f of CSS) problems.push(...physicalProblems(rel(f), readFileSync(f, 'utf8')));
  assert.deepEqual(problems, [], problems.join('\n'));

  // Every exception must still be real, or it is rot.
  for (const e of PHYSICAL_EXCEPTIONS) {
    const src = readFileSync(path.join(ROOT, e.file), 'utf8');
    assert.ok(src.includes(e.snippet), `stale exception: ${e.file} no longer has ${e.snippet}`);
    assert.ok(e.why.length > 40, 'every exception must carry a justification');
  }

  // And the logical vocabulary is genuinely in use.
  const all = CSS.map((f) => readFileSync(f, 'utf8')).join('\n');
  for (const logical of ['inset-inline', 'margin-inline', 'padding-inline', 'border-inline-start']) {
    assert.ok(all.includes(logical), `expected logical property ${logical}`);
  }
});

test('NEGATIVE CONTROL: the logical-CSS guard catches every physical form', () => {
  const clean = '.a {\n  margin-inline: 4px;\n  inset-inline-start: 0;\n}\n';
  assert.deepEqual(physicalProblems('x.css', clean), [], 'a clean sheet must pass');

  const offenders = [
    '.a { margin-left: 4px; }',
    '.a { padding-right: 4px; }',
    '.a { border-left: 1px solid red; }',
    '.a { position: absolute; left: 0; }',
    '.a { text-align: left; }',
    '.a { float: right; }',
    '.a { background-position: left center; }',
    '.a { scroll-padding-left: 4px; }',
    '.a { margin: 1px 2px 3px 4px; }',
    '.a { inset: 0 8px 0 0; }',
  ];
  for (const css of offenders) {
    assert.ok(
      physicalProblems('x.css', css).length > 0,
      `the guard MISSED: ${css}`,
    );
  }

  // Symmetric shorthands and function values must NOT be flagged.
  for (const ok of [
    '.a { margin: 8px 0; }',
    '.a { padding: 0 var(--gutter) env(safe-area-inset-bottom, 0); }',
    '.a { margin: 1px 2px 3px 2px; }',
    '.a { inset: 0; }',
  ]) {
    assert.deepEqual(physicalProblems('x.css', ok), [], `false positive on: ${ok}`);
  }

  // A comment naming a physical property is prose, not code.
  assert.deepEqual(physicalProblems('x.css', '/* never use margin-left here */\n.a { margin-inline: 0; }'), []);

  // The exception applies ONLY to its own file.
  const caret = 'border-right: 2px solid currentColor;';
  assert.deepEqual(
    physicalProblems('src/ui/storefront/LanguageMenu.module.css', `.caret { ${caret} }`),
    [],
    'the documented caret exception must hold',
  );
  assert.ok(
    physicalProblems('src/ui/storefront/home/home.module.css', `.caret { ${caret} }`).length > 0,
    'the exception must NOT leak to another stylesheet',
  );
});

// ----------------------------------------------- structural bidi isolation

/**
 * `dir="auto"` on a BLOCK-level element is a layout defect, not a text feature.
 *
 * It resolves direction from the first strong character, so the element's
 * `text-align: start` then resolves against its OWN direction and the text
 * jumps to the opposite edge from every direction-fixed neighbour - the accent
 * rule beside a heading, the price row under a card name, the sibling rows in a
 * footer. Menu content is single-language in MVP (CONTENT_AND_LOCALIZATION.md:3),
 * so Arabic copy on an English page is the DESIGNED case and the split is
 * plainly visible. 57 such instances shipped before this guard existed.
 *
 * The isolation run itself is fine and must NOT be banned: a bare inline
 * `<span dir="auto">` (what `TenantText` renders) is the approved pattern
 * (prototype Storefront.dc.html:140/:142, CONTENT_AND_LOCALIZATION.md:223).
 */
const TENANT_TEXT_RUN = /<span dir="auto">/g;

/**
 * Classes whose element is alignment-NEUTRAL, so `dir="auto"` on it cannot move
 * anything: each sits in a centred container or shrink-wraps to its content.
 * Every entry names the rule that neutralises it, and the test below proves
 * that rule still exists - a stale exemption fails instead of quietly widening
 * the guard.
 */
const NEUTRAL_BIDI_BLOCKS = [
  { cls: 'brandName', sheet: 'home.module.css', neutraliser: '.lockupText', why: 'centred lockup' },
  { cls: 'brandCity', sheet: 'home.module.css', neutraliser: '.lockupText', why: 'centred lockup' },
  { cls: 'chipLabel', sheet: 'home.module.css', neutraliser: '.chip', why: 'inline-flex chip, shrink-wrapped' },
  { cls: 'orbLabel', sheet: 'home.module.css', neutraliser: '.orbLabel', why: 'own text-align: center' },
  { cls: 'emptyBody', sheet: 'home.module.css', neutraliser: '.empty', why: 'centred empty card' },
  { cls: 'fact', sheet: 'home.module.css', neutraliser: '.fact', why: 'inline-flex pill, shrink-wrapped' },
  { cls: 'name', sheet: 'Intro.module.css', neutraliser: '.centre', why: 'centred intro block' },
  { cls: 'tagline', sheet: 'Intro.module.css', neutraliser: '.centre', why: 'centred intro block' },
];

/** Every `dir="auto"` that is NOT a bare isolation run, as [file, snippet]. */
function structuralBidiSites(files) {
  const found = [];
  for (const f of files) {
    const src = code(f).replace(TENANT_TEXT_RUN, ' ');
    for (const m of src.matchAll(/<(\w+)[^>]*\sdir="auto"[^>]*>/g)) {
      found.push({ file: rel(f), tag: m[1], snippet: m[0].replace(/\s+/g, ' ').trim() });
    }
  }
  return found;
}

test('dir="auto" never sits on a structural block', () => {
  const sites = structuralBidiSites(TSX);
  const offenders = sites.filter(
    (s) => !NEUTRAL_BIDI_BLOCKS.some((n) => s.snippet.includes(`styles.${n.cls}`)),
  );
  assert.deepEqual(
    offenders.map((o) => `${o.file}: ${o.snippet}`),
    [],
    'move dir="auto" onto an inner run - use <TenantText> - so the block keeps the page direction',
  );

  // Non-vacuity: the approved isolation pattern must actually be in use, or
  // this guard would pass on a tree that had simply deleted all bidi handling.
  const runs = TSX.map((f) => (code(f).match(TENANT_TEXT_RUN) ?? []).length).reduce((a, b) => a + b, 0);
  assert.ok(runs >= 1, 'the TenantText isolation run must exist');
  const users = TSX.filter((f) => code(f).includes('<TenantText>'));
  assert.ok(users.length >= 4, `expected TenantText across the card/section/story/footer surfaces, got ${users.length}`);

  // Every documented exemption must still be neutralised by a real CSS rule.
  for (const n of NEUTRAL_BIDI_BLOCKS) {
    const sheet = CSS.find((f) => rel(f).endsWith(n.sheet));
    assert.ok(sheet, `${n.sheet} must be in scope`);
    const css = readFileSync(sheet, 'utf8');
    const rule = new RegExp('\\' + n.neutraliser + '\\s*\\{[^}]*(text-align:\\s*center|align-items:\\s*center|display:\\s*inline-flex)');
    assert.match(css, rule, `${n.cls}: ${n.neutraliser} no longer neutralises alignment (${n.why})`);
  }
});

test('NEGATIVE CONTROL: the structural-bidi guard catches a block-level dir="auto"', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'sf-bidi-'));
  try {
    const write = (name, body) => {
      const f = path.join(dir, name);
      writeFileSync(f, body, 'utf8');
      return f;
    };

    // The approved pattern must pass.
    const ok = write(
      'ok.tsx',
      'export const A = () => (\n  <p className={styles.cardName}>\n    <span dir="auto">{item.name}</span>\n  </p>\n);\n',
    );
    assert.deepEqual(structuralBidiSites([ok]), [], 'an inner isolation run must be allowed');

    // Each of these is the defect and must be caught.
    const bad = [
      ['heading', '<h2 className={styles.sectionTitle} dir="auto">{x}</h2>'],
      ['paragraph', '<p className={styles.cardDesc} dir="auto">{x}</p>'],
      ['wrapper', '<div className={styles.footerRow} dir="auto">{x}</div>'],
      ['template className', '<p className={`${styles.cardName} ${styles.cardNameSmall}`} dir="auto">{x}</p>'],
      ['span with a layout class', '<span className={styles.announceText} dir="auto">{x}</span>'],
    ];
    for (const [label, jsx] of bad) {
      const f = write(`bad-${label.replace(/\s/g, '-')}.tsx`, `export const A = () => (\n  ${jsx}\n);\n`);
      assert.ok(structuralBidiSites([f]).length > 0, `the guard MISSED a ${label}`);
    }

    // A comment naming the pattern is prose, not code.
    const prose = write('prose.tsx', '// never put dir="auto" on a block\nexport const A = 1;\n');
    assert.deepEqual(structuralBidiSites([prose]), []);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// ------------------------------------------------------------ Phase E rules

/**
 * The request handoff, the status snapshot, the message and the copy path may
 * never carry a contact field. The rule is by IDENTIFIER: none of these files
 * may even name one, so a field cannot be threaded through under its own name.
 * `note` is excluded from the list because the runtime must construct a
 * CartLine (which has a note slot) to resolve item names; that slot is always
 * the empty string there, which the assertion below pins.
 */
const CONTACT_IDENTIFIERS = ['fullName', 'phone', 'street', 'building', 'apartment', 'deliveryNotes', 'area'];
const CONTACT_FREE_FILES = [
  'src/ui/storefront/request/RequestHandoffProvider.tsx',
  'src/ui/storefront/request/status.ts',
  'src/ui/storefront/request/message.ts',
  'src/ui/storefront/request/clipboard.ts',
  'src/ui/storefront/request/RequestRuntime.tsx',
  'src/ui/storefront/request/ReceivedScreen.tsx',
  'src/ui/storefront/request/StatusScreen.tsx',
  'src/ui/storefront/request/requestParts.tsx',
  'src/source/request-fixture.ts',
];

test('nothing on the request side can name a contact field', () => {
  for (const relPath of CONTACT_FREE_FILES) {
    const file = path.join(ROOT, relPath);
    assert.ok(existsSync(file), `${relPath} must exist`);
    const src = code(file);
    for (const id of CONTACT_IDENTIFIERS) {
      assert.ok(!new RegExp(`\\b${id}\\b`).test(src), `${relPath} names the contact field ${id}`);
    }
  }
  // The one CartLine the runtime builds carries an EMPTY note, always.
  const runtime = code(path.join(ROOT, 'src/ui/storefront/request/RequestRuntime.tsx'));
  assert.match(runtime, /note: ''/);
  assert.ok(!/note: (?!'')/.test(runtime), 'the runtime must never forward a note');
  // The flow side hands the handoff only what the quote and the cart lines hold.
  const flow = code(path.join(ROOT, 'src/ui/storefront/checkout/FlowRuntime.tsx'));
  const handoffBlock = flow.slice(flow.indexOf('const handoffFor'), flow.indexOf('const complete'));
  assert.ok(handoffBlock.length > 100, 'the handoff builder must exist');
  for (const id of [...CONTACT_IDENTIFIERS, 'draft.', 'note']) {
    assert.ok(!handoffBlock.includes(id), `the handoff builder reads ${id}`);
  }
});

test('NEGATIVE CONTROL: the contact-identifier rule catches a threaded field', () => {
  const planted = "export interface RequestHandoff { readonly phone: string; }";
  assert.ok(CONTACT_IDENTIFIERS.some((id) => new RegExp(`\\b${id}\\b`).test(planted)));
  // And it does not fire on the words it must tolerate.
  const innocent = "const phoneme = 1; const areaCode = 2; const building2 = 3;";
  assert.ok(!CONTACT_IDENTIFIERS.some((id) => new RegExp(`\\b${id}\\b`).test(innocent)));
});

test('the launcher opens nothing and the clipboard module only writes', () => {
  const launcher = code(path.join(ROOT, 'src/ui/storefront/request/launcher.ts'));
  assert.ok(launcher.includes("return 'simulated'"), 'the demo launcher must report a simulated launch');
  assert.ok(!/location|href|navigate|open\(/.test(launcher.replace(/open\(digits/, '').replace(/open\(\)/, '')),
    'the demo launcher must not navigate');
  const clipboard = code(path.join(ROOT, CLIPBOARD_MODULE));
  assert.ok(clipboard.includes('writeText'), 'the clipboard module must actually write');
  assert.ok(!clipboard.includes('readText'), 'the clipboard module must never read');
  assert.ok(clipboard.includes('return false'), 'a failed write must report false');
  // Exactly one file touches the clipboard at all.
  const touching = TSX.filter((f) => /navigator\.clipboard|\.clipboard\b/.test(code(f))).map(rel);
  assert.deepEqual(touching, [CLIPBOARD_MODULE]);
});

test('the request route pre-renders one ref and the status source never answers synchronously', () => {
  const fixture = code(path.join(ROOT, 'src/source/request-fixture.ts'));
  assert.match(fixture, /return \[DEMO_REQUEST_REF\];/);
  // The first snapshot is delivered from a timer, never during subscribe().
  assert.ok(fixture.includes('later(0, () => {'), 'the first answer must arrive after mount');
  // The route files read the ONE authority.
  for (const root of ['(root)', 'ar', 'en', 'he']) {
    const page = code(path.join(ROOT, `app/${root}/r/[ref]/page.tsx`));
    assert.ok(page.includes('requestRefs()'), `${root}: static params come from requestRefs()`);
    assert.ok(page.includes('resolveRequest(ref)'), `${root}: the ref resolves through the fixture`);
    assert.ok(page.includes('dynamicParams = false'));
  }
  // No synthesised timestamps: the timeline reads events, never a formula.
  const status = code(path.join(ROOT, 'src/ui/storefront/request/status.ts'));
  assert.ok(!/createdAt\s*\+/.test(status), 'status.ts must not add to createdAt');
  const screen = code(path.join(ROOT, 'src/ui/storefront/request/StatusScreen.tsx'));
  assert.ok(!/createdAt/.test(screen), 'the screen never derives a time from createdAt');
  assert.ok(screen.includes('node.at === null ? null'), 'a node without an event shows no time');
  // The countdown lives outside the live region.
  assert.ok(screen.includes('role="timer" aria-live="off"'), 'the TTL must not announce every second');
});

test('the message never carries the literal the prototype hard-coded', () => {
  for (const f of TSX) {
    assert.ok(!code(f).includes('bizbot.app'), `${rel(f)}: the dead status-link literal`);
  }
  const message = code(path.join(ROOT, 'src/ui/storefront/request/message.ts'));
  assert.ok(message.includes('statusUrl'), 'the status link is an input, built from the configured origin');
  const origin = code(path.join(ROOT, 'src/routes/origin.ts'));
  assert.match(origin, /export const PUBLIC_ORIGIN = 'https:\/\/[a-z0-9.-]+';/);
});
