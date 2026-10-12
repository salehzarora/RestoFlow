// STOREFRONT-PUBLISH-001 — test group A: exact enum validation.
//
// Regression for the Option C spike's round-3 BLOCKER: the spike looked variants and
// source buckets up as `RECIPE.variants[variant]` / `RECIPE.sources[source]`, so an
// inherited name such as `constructor` resolved to a truthy function and the call ran
// with NO resize box and NO byte cap. These tests prove that no prototype-chain
// property, case / whitespace variant, empty string, non-string value or unknown
// future name can pass ANY of the three validation layers:
//   1. the recipe helpers (variantWidth / sourceMaxBytes),
//   2. derive() itself (refuses before reading a single byte),
//   3. the function's request validator (validateRequest).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DerivationError, RECIPE, sourceMaxBytes, variantWidth } from '../lib/recipe.mjs';
import { hasDuplicateTopLevelKey, REQUEST_KEYS, slotSpec, validateRequest } from '../lib/validate.mjs';
import { encodeKey, isPublisherPrincipal } from '../lib/caller.mjs';
import { deriver } from './engine.mjs';
import { fixture } from './fixtures.mjs';

const PROTOTYPE_NAMES = [
  ...new Set([
    ...Object.getOwnPropertyNames(Object.prototype), // constructor, __proto__, toString, valueOf, hasOwnProperty, ...
    ...Object.getOwnPropertyNames(Function.prototype), // call, apply, bind, length, name, ...
    ...Object.getOwnPropertyNames(Array.prototype),
    ...Object.getOwnPropertyNames(String.prototype),
    'prototype', 'constructor', '__proto__', 'toString', 'valueOf', '__defineGetter__', '__lookupSetter__',
  ]),
];
const NEAR_MISSES = [
  '', ' ', '\t', '\n', 'w480 ', ' w480', 'w480\n', 'w480\u0000', 'W480', 'w 480', 'w48', 'w4800', 'w0', 'w1920', 'w960 ', 'W960',
  "ｗ480", "w４80", // full-width look-alikes
  'menu-images ', ' menu-images', 'Menu-Images', 'MENU-IMAGES', 'menu_images', 'menu-image', 'menu-images/',
  'restaurant-logos ', 'Restaurant-Logos', 'restaurant_logos', 'restaurant-logo', 'storefront-media',
  'logo ', 'Logo', 'LOGO', 'hero ', 'Hero', 'items', 'item', 'banner', 'favicon', 'w720', 'w1440', 'originals',
];
const NON_STRINGS = [
  null, undefined, 0, 480, 960, true, false, NaN, [], ['w480'], ['menu-images'], {}, { toString: () => 'w480' },
  { valueOf: () => 'w480' }, new String('w480'), new String('menu-images'), Object.create(null), () => 'w480', 480n, Symbol('w480'),
];

test('A1. the accepted variants are EXACTLY w480 -> 480 and w960 -> 960', () => {
  assert.equal(variantWidth('w480'), 480);
  assert.equal(variantWidth('w960'), 960);
  assert.deepEqual(RECIPE.variants.map(([k, v]) => [k, v]), [['w480', 480], ['w960', 960]]);
});

test('A2. the accepted source buckets are EXACTLY restaurant-logos (2 MiB) and menu-images (5 MiB)', () => {
  assert.equal(sourceMaxBytes('restaurant-logos'), 2097152);
  assert.equal(sourceMaxBytes('menu-images'), 5242880);
  assert.deepEqual(RECIPE.sources.map(([k, v]) => [k, v]).sort(), [['menu-images', 5242880], ['restaurant-logos', 2097152]]);
});

test('A3. no prototype-chain property name passes the variant, source or slot allowlist', () => {
  assert.ok(PROTOTYPE_NAMES.includes('constructor') && PROTOTYPE_NAMES.includes('__proto__') && PROTOTYPE_NAMES.includes('prototype')
    && PROTOTYPE_NAMES.includes('toString') && PROTOTYPE_NAMES.includes('valueOf'), 'the probe list covers the named cases');
  for (const name of PROTOTYPE_NAMES) {
    assert.equal(variantWidth(name), null, `variant ${JSON.stringify(name)}`);
    assert.equal(sourceMaxBytes(name), null, `source ${JSON.stringify(name)}`);
    assert.equal(slotSpec(name), null, `slot ${JSON.stringify(name)}`);
  }
});

test('A4. empty / whitespace / case / look-alike / unknown future names are refused', () => {
  for (const name of NEAR_MISSES) {
    assert.equal(variantWidth(name), null, `variant ${JSON.stringify(name)}`);
    assert.equal(sourceMaxBytes(name), null, `source ${JSON.stringify(name)}`);
    assert.equal(slotSpec(name), null, `slot ${JSON.stringify(name)}`);
  }
});

test('A5. non-string values (including String objects and toString tricks) are refused', () => {
  for (const v of NON_STRINGS) {
    assert.equal(variantWidth(v), null, `variant ${String(typeof v)}`);
    assert.equal(sourceMaxBytes(v), null, `source ${String(typeof v)}`);
    assert.equal(slotSpec(v), null, `slot ${String(typeof v)}`);
  }
});

test('A6. a polluted Object.prototype cannot add an accepted name', () => {
  const names = ['w1234', 'menu-images-x', 'banner'];
  try {
    for (const n of names) Object.prototype[n] = 4096; // eslint-disable-line no-extend-native
    for (const n of names) {
      assert.equal(variantWidth(n), null);
      assert.equal(sourceMaxBytes(n), null);
      assert.equal(slotSpec(n), null);
    }
  } finally {
    for (const n of names) delete Object.prototype[n];
  }
});

test('A7. derive() refuses a hostile variant / source BEFORE reading any byte (null bytes never reach the sniffer)', async () => {
  const d = await deriver();
  for (const variant of [...PROTOTYPE_NAMES, ...NEAR_MISSES, ...NON_STRINGS]) {
    await assert.rejects(d.derive(null, { variant, source: 'menu-images', rung: 0 }),
      (e) => e instanceof DerivationError && e.code === 'unknown_variant', `variant ${typeof variant === 'string' ? JSON.stringify(variant) : typeof variant}`);
  }
  for (const source of [...PROTOTYPE_NAMES, ...NEAR_MISSES, ...NON_STRINGS]) {
    await assert.rejects(d.derive(null, { variant: 'w480', source, rung: 0 }),
      (e) => e instanceof DerivationError && e.code === 'unknown_source', `source ${typeof source === 'string' ? JSON.stringify(source) : typeof source}`);
  }
  for (const rung of ['0', '__proto__', 0.5, -1, 5, NaN, Infinity, null, [0], { valueOf: () => 0 }]) {
    await assert.rejects(d.derive(null, { variant: 'w480', source: 'menu-images', rung }),
      (e) => e instanceof DerivationError && e.code === 'unknown_rung', `rung ${String(rung)}`);
  }
});

test('A8. the exact spike failure: a real image with variant "constructor" is refused, not derived without a box or cap', async () => {
  const d = await deriver();
  const bytes = await fixture('logo_alpha_2000x1000');
  for (const variant of ['constructor', '__proto__', 'toString', 'valueOf', 'prototype']) {
    await assert.rejects(d.derive(bytes, { variant, source: 'restaurant-logos', rung: 0 }), (e) => e.code === 'unknown_variant');
  }
  for (const source of ['constructor', '__proto__', 'toString', 'valueOf', 'prototype']) {
    await assert.rejects(d.derive(bytes, { variant: 'w480', source, rung: 0 }), (e) => e.code === 'unknown_source');
  }
  // The honest request still derives (the fix did not break the happy path).
  const ok = await d.derive(bytes, { variant: 'w480', source: 'restaurant-logos', rung: 0 });
  assert.equal(ok.status, 'derived');
  assert.ok(ok.width <= 480 && ok.height <= 480 && ok.byteLength <= 524288);
});

// ----------------------------------------------------------------- request validator
const ORG = '0b5e0000-0000-4000-8000-000000000001';
const RESTO = '0b5e0000-0000-4000-8000-000000000002';
const LOGO_KEY = `${ORG}/${RESTO}/logo/0b5e0000-0000-4000-8000-0000000000a1.png`;
const MENU_KEY = `${ORG}/${RESTO}/global/menu_item/0b5e0000-0000-4000-8000-0000000000b1/0b5e0000-0000-4000-8000-0000000000c1.jpg`;
const base = (over = {}) => ({
  request_id: '0b5e0000-0000-4000-8000-0000000000ff', organization_id: ORG, restaurant_id: RESTO,
  slot: 'logo', variant: 'w480', source_bucket: 'restaurant-logos', source_key: LOGO_KEY, rung: 0, ...over,
});

test('A9. the request validator accepts exactly the two slot shapes', () => {
  const logo = validateRequest(base());
  assert.equal(logo.ok, true);
  assert.equal(logo.value.variantWidth, 480);
  assert.equal(logo.value.sourceMaxBytes, 2097152);
  for (const [bucket, key] of [['restaurant-logos', LOGO_KEY], ['menu-images', MENU_KEY]]) {
    const hero = validateRequest(base({ slot: 'hero', variant: 'w960', source_bucket: bucket, source_key: key, rung: 4 }));
    assert.equal(hero.ok, true, bucket);
    assert.equal(hero.value.variantWidth, 960);
  }
  // A branch-scoped menu original is accepted too.
  const branchKey = MENU_KEY.replace('/global/', '/0b5e0000-0000-4000-8000-0000000000d1/');
  assert.equal(validateRequest(base({ slot: 'hero', variant: 'w960', source_bucket: 'menu-images', source_key: branchKey })).ok, true);
});

test('A10. hostile slot / variant / source_bucket values are refused by the request validator', () => {
  for (const v of [...PROTOTYPE_NAMES, ...NEAR_MISSES, ...NON_STRINGS]) {
    const s = validateRequest(base({ slot: v }));
    assert.equal(s.ok, false); assert.equal(s.field, 'slot');
    const r = validateRequest(base({ variant: v }));
    assert.equal(r.ok, false); assert.equal(r.field, 'variant');
    const b = validateRequest(base({ source_bucket: v }));
    assert.equal(b.ok, false); assert.equal(b.field, 'source_bucket');
  }
});

test('A11. slot / variant / bucket combinations outside D3-D4 are refused (item images stay out)', () => {
  assert.deepEqual(validateRequest(base({ variant: 'w960' })), { ok: false, field: 'variant', reason: 'mismatch' });
  assert.deepEqual(validateRequest(base({ source_bucket: 'menu-images', source_key: MENU_KEY })), { ok: false, field: 'source_bucket', reason: 'mismatch' });
  assert.deepEqual(validateRequest(base({ slot: 'hero', variant: 'w480', source_bucket: 'menu-images', source_key: MENU_KEY })), { ok: false, field: 'variant', reason: 'mismatch' });
});

test('A12. the key set is exact: prototype keys (JSON __proto__, constructor), extra and missing keys are refused', () => {
  const polluted = JSON.parse(JSON.stringify(base()).replace('{', '{"__proto__":{"slot":"hero"},'));
  assert.equal(Object.prototype.hasOwnProperty.call(polluted, '__proto__'), true, 'JSON.parse makes __proto__ an own key');
  assert.deepEqual(validateRequest(polluted), { ok: false, field: '__proto__', reason: 'unknown_field' });
  assert.deepEqual(validateRequest({ ...base(), constructor: 'x' }), { ok: false, field: 'constructor', reason: 'unknown_field' });
  assert.deepEqual(validateRequest({ ...base(), 'x y': 1 }), { ok: false, field: '?', reason: 'unknown_field' });
  for (const k of REQUEST_KEYS) {
    const b = base(); delete b[k];
    assert.deepEqual(validateRequest(b), { ok: false, field: k, reason: 'missing' }, k);
  }
  // Inherited (non-own) fields do not count as present.
  const inherited = Object.create(base());
  assert.equal(validateRequest(inherited).ok, false);
  for (const body of [null, [], 'x', 1, true, undefined]) assert.equal(validateRequest(body).ok, false);
});

test('A13. ids must be canonical lower-case UUIDs; the source key must match its bucket grammar and scope', () => {
  for (const field of ['request_id', 'organization_id', 'restaurant_id']) {
    for (const v of ['', 'x', ORG.toUpperCase(), `${ORG} `, `{${ORG}}`, ORG.replace(/-/g, ''), 42, null]) {
      const r = validateRequest(base({ [field]: v }));
      assert.equal(r.ok, false, `${field}=${String(v)}`); assert.equal(r.field, field);
    }
  }
  const bad = [
    '', 'x', `${ORG}/${RESTO}/logo/a.png`, `${ORG}/${RESTO}/logo/${ORG}.gif`, `${ORG}/${RESTO}/logo/${ORG}.PNG`,
    `${ORG}/${RESTO}/logo/../${ORG}.png`, `/${LOGO_KEY}`, `${LOGO_KEY}/`, `${LOGO_KEY}?x=1`, LOGO_KEY.replace('/logo/', '/Logo/'),
    `${ORG}/${RESTO}/extra/logo/${ORG}.png`, 'a'.repeat(513), MENU_KEY,
  ];
  for (const key of bad) {
    const r = validateRequest(base({ source_key: key }));
    assert.equal(r.ok, false, key.slice(0, 80)); assert.equal(r.field, 'source_key');
  }
  // A well-formed key of ANOTHER organization or restaurant is refused before any lookup.
  const OTHER = '0b5e0000-0000-4000-8000-0000000000ee';
  assert.deepEqual(validateRequest(base({ source_key: LOGO_KEY.replace(ORG, OTHER) })), { ok: false, field: 'source_key', reason: 'mismatch' });
  assert.deepEqual(validateRequest(base({ source_key: LOGO_KEY.replace(RESTO, OTHER) })), { ok: false, field: 'source_key', reason: 'mismatch' });
});

test('A14. rung must be an integer 0..4', () => {
  for (const rung of [0, 1, 2, 3, 4]) assert.equal(validateRequest(base({ rung })).ok, true);
  for (const rung of [-1, 5, 0.5, NaN, Infinity, '0', null, [0], true]) {
    const r = validateRequest(base({ rung }));
    assert.equal(r.ok, false, String(rung)); assert.equal(r.field, 'rung');
  }
});

// ----------------------------------------------------------------- review SEC-1 / SEC-4 helpers
test('A15. SEC-4: the duplicate-key scan sees exactly the TOP-LEVEL keys, after unescaping', () => {
  const dup = [
    '{"a":1,"a":2}', '{"a":1,"b":{"c":1},"a":3}', '{"a":"x","\\u0061":1}', '{ "a" : 1 , "a" : 1 }', '{"__proto__":1,"__proto__":1}',
    '{"s":"has \\"quotes\\", commas, {braces} and [brackets]","s":2}', '\n{"a":[1,{"a":2}],"a":0}',
  ];
  for (const t of dup) { JSON.parse(t); assert.equal(hasDuplicateTopLevelKey(t), true, t); }
  const unique = [
    '{}', '{"a":1,"b":2}', '{"a":{"b":1,"b":2}}', '{"a":[{"b":1},{"b":1}]}', '{"a":"\\"a\\":1,","b":"a"}', '[1,2,{"a":1,"a":1}]', '"a"', '1',
    '{"a":"}","b":"{","c":"\\\\"}', '{"a":1,"A":2}',
  ];
  for (const t of unique) { JSON.parse(t); assert.equal(hasDuplicateTopLevelKey(t), false, t); }
});

test('A16. SEC-4: storage keys are encoded per segment and an empty, "." or ".." segment is refused', () => {
  assert.equal(encodeKey('a/b c/d%e.png'), 'a/b%20c/d%25e.png');
  assert.equal(encodeKey(`${'a'.repeat(32)}/${'0'.repeat(64)}.webp`), `${'a'.repeat(32)}/${'0'.repeat(64)}.webp`);
  for (const key of ['../x', 'a/../b', 'a/./b', './a', 'a/.', 'a/..', 'a//b', '/a', 'a/', '', '.', '..', null, 42]) {
    assert.throws(() => encodeKey(key), TypeError, String(key));
  }
  // an encoded dot segment ('%2e%2e') is not a dot segment: it is encoded, never decoded here
  assert.equal(encodeKey('a/%2e%2e/b'), 'a/%252e%252e/b');
});

test('A17. SEC-1: only a signed-in, non-anonymous principal of role and audience authenticated may publish', () => {
  const base = { id: 'u', aud: 'authenticated', role: 'authenticated', is_anonymous: false };
  assert.equal(isPublisherPrincipal(base), true);
  assert.equal(isPublisherPrincipal({ id: 'u', aud: 'authenticated', role: 'authenticated' }), true, 'no is_anonymous field: not anonymous');
  for (const u of [{ ...base, is_anonymous: true }, { ...base, role: 'anon' }, { ...base, role: 'service_role' }, { ...base, aud: 'anon' },
    { ...base, aud: ['authenticated'] }, { ...base, role: 'Authenticated' }, { id: 'u' }, null, undefined, 'authenticated', []]) {
    assert.equal(isPublisherPrincipal(u), false, JSON.stringify(u));
  }
});
