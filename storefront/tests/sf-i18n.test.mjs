// Storefront dictionaries. The handoff is explicit: "Every key exists in all
// three dictionaries; there is no runtime fallback chain and no missing-key
// state." These tests enforce that, plus the approved a11y strings and the
// placeholder contract.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOCALES = ['ar', 'he', 'en'];
const read = (code) =>
  JSON.parse(readFileSync(path.join(ROOT, `messages/storefront.${code}.json`), 'utf8'));

const DICTS = Object.fromEntries(LOCALES.map((c) => [c, read(c)]));
const { storefrontMessages, fill } = await import('../src/i18n/storefront.ts');

test('every dictionary has identical keys', () => {
  const reference = Object.keys(DICTS.ar).sort();
  for (const code of LOCALES) {
    assert.deepEqual(Object.keys(DICTS[code]).sort(), reference, `storefront.${code}.json key drift`);
  }
});

test('no string is empty and no string is left in another language', () => {
  for (const code of LOCALES) {
    for (const [key, value] of Object.entries(DICTS[code])) {
      if (typeof value !== 'string') continue;
      assert.ok(value.trim().length > 0, `${code}.${key} is empty`);
    }
  }
  // A Hebrew or Arabic value identical to the English one is almost always an
  // untranslated copy-paste. languageNames are exempt: they are endonyms.
  for (const code of ['ar', 'he']) {
    for (const [key, value] of Object.entries(DICTS[code])) {
      if (typeof value !== 'string') continue;
      assert.notEqual(value, DICTS.en[key], `${code}.${key} looks untranslated`);
    }
  }
});

test('language names are endonyms and identical across dictionaries', () => {
  for (const code of LOCALES) {
    assert.deepEqual(Object.keys(DICTS[code].languageNames).sort(), [...LOCALES].sort());
    assert.deepEqual(DICTS[code].languageNames, DICTS.ar.languageNames,
      'a language is named the same in its own script everywhere');
  }
  assert.equal(DICTS.ar.languageNames.ar, 'العربية');
  assert.equal(DICTS.ar.languageNames.he, 'עברית');
  assert.equal(DICTS.ar.languageNames.en, 'English');
});

test('the approved a11y rail strings are present verbatim', () => {
  assert.equal(DICTS.ar.prevCategory, 'الفئة السابقة');
  assert.equal(DICTS.ar.nextCategory, 'الفئة التالية');
  assert.equal(DICTS.he.prevCategory, 'הקטגוריה הקודמת');
  assert.equal(DICTS.he.nextCategory, 'הקטגוריה הבאה');
  assert.equal(DICTS.en.prevCategory, 'Previous category');
  assert.equal(DICTS.en.nextCategory, 'Next category');
});

test('placeholders match across languages', () => {
  const placeholders = (s) => (s.match(/\{(\w+)\}/g) ?? []).sort().join(',');
  for (const key of Object.keys(DICTS.ar)) {
    if (typeof DICTS.ar[key] !== 'string') continue;
    const reference = placeholders(DICTS.ar[key]);
    for (const code of LOCALES) {
      assert.equal(placeholders(DICTS[code][key]), reference,
        `${code}.${key} placeholder set differs from ar`);
    }
  }
});

test('the keys the design gives are the keys we ship', () => {
  // Spot-check against CONTENT_AND_LOCALIZATION.md so a silent reword is caught.
  assert.equal(DICTS.ar.welcome, 'أهلاً بك في');
  assert.equal(DICTS.he.welcome, 'ברוכים הבאים אל');
  assert.equal(DICTS.en.welcome, 'Welcome to');
  assert.equal(DICTS.ar.unknownTitle, 'هذا المتجر غير متاح');
  assert.equal(DICTS.en.unknownBody, 'Check the link, or ask the restaurant for their current one.');
  assert.equal(DICTS.ar.poweredBy, 'مدعوم من');
});

test('the typed accessor returns each locale and never falls back', () => {
  for (const code of LOCALES) {
    assert.equal(storefrontMessages(code).welcome, DICTS[code].welcome);
  }
});

test('fill substitutes known placeholders and leaves unknown ones visible', () => {
  assert.equal(fill('closes {t}', { t: '23:00' }), 'closes 23:00');
  assert.equal(fill('from {f}', { f: '₪10' }), 'from ₪10');
  // An unsupplied placeholder stays visible rather than rendering as a blank.
  assert.equal(fill('a {missing} b', {}), 'a {missing} b');
  assert.equal(fill('no placeholders', { t: 'x' }), 'no placeholders');
});

test('the TypeScript interface covers exactly the shipped keys', () => {
  const source = readFileSync(path.join(ROOT, 'src/i18n/storefront.ts'), 'utf8');
  const block = /export interface StorefrontMessages \{([\s\S]*?)\n\}/.exec(source);
  assert.ok(block, 'StorefrontMessages interface not found');
  const declared = [...block[1].matchAll(/readonly (\w+)\s*:/g)].map((m) => m[1]).sort();
  assert.deepEqual(declared, Object.keys(DICTS.ar).sort(),
    'the interface and the JSON dictionaries must not drift');
});
