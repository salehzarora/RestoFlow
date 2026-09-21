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

// The demo tenant's data legitimately contains its own brand colours.
const FIXTURE_LAYER = [
  'src/source/fixtures.ts',
  'src/source/home.ts',
  'src/source/menu-fixture.ts',
  'src/source/scenarios.ts',
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

test('the fixture scenario switch never leaves the fixture layer', () => {
  for (const f of [...TSX, ...CSS]) {
    if (FIXTURE_LAYER.includes(rel(f))) continue;
    const src = code(f);
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

/** Banned in EVERY app/ and src/ file, the allowlisted module included. */
const BANNED_EVERYWHERE = ['fetch(', 'XMLHttpRequest', 'WebSocket', 'navigator.sendBeacon',
  'localStorage', 'indexedDB', 'document.cookie'];

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
  if (relPath !== UI_SESSION_MODULE && src.includes('sessionStorage')) {
    return `${relPath}: sessionStorage is allowed ONLY in ${UI_SESSION_MODULE}`;
  }
  return null;
}

test('browser storage is confined to the one allowlisted UI-session module', () => {
  for (const f of TSX) {
    assert.equal(storageOffence(rel(f), readFileSync(f, 'utf8')), null);
  }
  // Non-vacuity: the allowlisted file must exist AND must actually use the API,
  // or the allowlist is guarding nothing.
  const helper = TSX.find((f) => rel(f) === UI_SESSION_MODULE);
  assert.ok(helper, `${UI_SESSION_MODULE} must exist`);
  assert.ok(code(helper).includes('sessionStorage'),
    `${UI_SESSION_MODULE} must actually use sessionStorage`);
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

    // The allowlist covers sessionStorage ONLY: a long-lived store in the SAME
    // file is still a failure.
    writeFileSync(helperCopy,
      readFileSync(helperCopy, 'utf8') + '\nconst leak = localStorage.getItem("x");\n', 'utf8');
    assert.ok(storageOffence(relOf(helperCopy), readFileSync(helperCopy, 'utf8')) !== null,
      'the allowlist must NOT extend to a long-lived store');

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
