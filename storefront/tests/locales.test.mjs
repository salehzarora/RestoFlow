// The locale seam is the only place language metadata is defined, so copies
// cannot drift. These run BEFORE the build, against source.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LOCALES = ['ar', 'en', 'he'];
const DIR = { ar: 'rtl', en: 'ltr', he: 'rtl' };

test('every locale has a layout and a page, and there is no top-level app/layout', () => {
  assert.equal(existsSync(path.join(ROOT, 'app/layout.tsx')), false,
    'a top-level app/layout.tsx would stop the locale layouts being root layouts');
  assert.ok(existsSync(path.join(ROOT, 'app/(root)/layout.tsx')));
  assert.ok(existsSync(path.join(ROOT, 'app/(root)/page.tsx')));
  for (const code of LOCALES) {
    assert.ok(existsSync(path.join(ROOT, `app/${code}/layout.tsx`)), `${code} layout`);
    assert.ok(existsSync(path.join(ROOT, `app/${code}/page.tsx`)), `${code} page`);
  }
});

test('each root layout declares the correct lang and dir', () => {
  const check = (file, lang) => {
    const source = readFileSync(path.join(ROOT, file), 'utf8');
    assert.match(source, new RegExp(`<html lang="${lang}" dir="${DIR[lang]}">`),
      `${file} must declare lang=${lang} dir=${DIR[lang]}`);
  };
  check('app/(root)/layout.tsx', 'ar');
  for (const code of LOCALES) check(`app/${code}/layout.tsx`, code);
});

test('every locale has complete copy with identical keys', () => {
  const sets = LOCALES.map((code) => {
    const data = JSON.parse(readFileSync(path.join(ROOT, `messages/${code}.json`), 'utf8'));
    return [code, data];
  });
  const reference = Object.keys(sets[0][1]).sort();
  for (const [code, data] of sets) {
    assert.deepEqual(Object.keys(data).sort(), reference, `messages/${code}.json key drift`);
    for (const [key, value] of Object.entries(data)) {
      if (typeof value === 'string') assert.ok(value.trim().length > 0, `${code}.${key} is empty`);
    }
    assert.deepEqual(Object.keys(data.languageNames).sort(), [...LOCALES].sort(),
      `${code}.languageNames must name every locale`);
  }
});

test('the locale seam agrees with the route table', () => {
  const source = readFileSync(path.join(ROOT, 'src/i18n/locales.ts'), 'utf8');
  assert.match(source, /LOCALES = \['ar', 'en', 'he'\] as const/);
  assert.match(source, /DEFAULT_LOCALE: Locale = 'ar'/);
});

test('one shared component renders every locale', () => {
  for (const file of ['app/(root)/page.tsx', ...LOCALES.map((c) => `app/${c}/page.tsx`)]) {
    assert.match(readFileSync(path.join(ROOT, file), 'utf8'), /Placeholder/,
      `${file} must render the shared Placeholder`);
  }
});
