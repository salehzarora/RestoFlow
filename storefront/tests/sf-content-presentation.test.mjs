import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { headlineParts, productCardClass, productFrameClass, productImageClass, sectionGridClass, sectionLayout } from '../src/ui/storefront/contentPresentation.ts';

const item = (id, layout) => ({ id, categoryId: 'one', cardLayout: layout });
test('ordinary category determines columns independently of opposite item overrides; list always wins', () => {
  const cutout = [item('one', 'cutout')];
  const standard = [item('two', 'standard')];
  assert.equal(sectionLayout('grid', cutout, { cardLayout: 'standard' }), 'standard');
  assert.equal(sectionLayout('grid', standard, { cardLayout: 'cutout' }), 'cutout');
  assert.equal(sectionLayout('grid', cutout, {}), 'standard');
  for (const category of [undefined, { cardLayout: 'cutout' }, { cardLayout: 'standard' }]) {
    assert.equal(sectionLayout('list', cutout, category), 'list');
  }
});
test('aggregate search and picks require every nonempty result to resolve cutout, including one-category results', () => {
  assert.equal(sectionLayout('grid', [item('one', 'cutout'), item('two', 'cutout')]), 'cutout');
  assert.equal(sectionLayout('grid', [item('one', 'cutout'), item('two', 'standard')]), 'standard');
  assert.equal(sectionLayout('grid', [item('one', undefined)]), 'standard');
  assert.equal(sectionLayout('grid', []), 'standard');
  assert.equal(sectionGridClass('cutout', 'grid'), 'grid');
  assert.equal(sectionGridClass('standard', 'grid'), '');
  assert.equal(sectionGridClass('list', 'grid'), '');
});
test('whole-image removes inherited crop/zoom/mask and corner clipping without modifying the source item', () => {
  const saved = Object.freeze({ imageFit: 'whole-image', image: '/original.webp', name: 'צילום أصلي 🍔', priceMinor: 0 });
  assert.equal(productImageClass(saved, 'whole'), 'whole');
  assert.equal(productFrameClass(saved, 'frame'), 'frame');
  const css = readFileSync(new URL('../src/ui/storefront/content.module.css', import.meta.url), 'utf8');
  for (const rule of ['object-fit:contain', 'object-position:center', 'transform:none!important', 'clip-path:none', 'mask-image:none', 'overflow:visible']) assert.ok(css.includes(rule), rule);
  assert.equal(productImageClass({ imageFit: 'fill' }, 'whole'), '');
  assert.equal(productFrameClass({}, 'frame'), '');
  assert.equal(productCardClass({ cardLayout: 'standard' }, 'cutout'), '');
  assert.equal(saved.image, '/original.webp'); assert.equal(saved.priceMinor, 0);
});
test('Hero rendering slices codepoints, preserving original Arabic/Hebrew marks, spaces and non-BMP symbols', () => {
  for (const [text, start, end, breakBefore] of [
    ['طَعْم رائع', 6, 10, 6], ['שָׁלוֹם טעים', 8, 12, 8],
    ['🍔 טָעִים', 2, 8, 2], ['👩‍🍳 برجر', 4, 8, 4],
    ['A\u00a0 B', 3, 4, 3], ['Cafe\u0301 🍔', 6, 7, 6],
  ]) {
    const result = headlineParts(text, { text, highlight: { start, end }, break_before: breakBefore });
    assert.equal(result.map(part => part.text).join(''), text);
    assert.equal(result.filter(part => part.highlight).map(part => part.text).join(''), Array.from(text).slice(start, end).join(''));
    assert.equal(result.filter(part => part.breakBefore).length, 1);
  }
  assert.deepEqual(headlineParts('لا تغيير', null), [{ text: 'لا تغيير', highlight: false, breakBefore: false }]);
  assert.throws(() => headlineParts('NFC Café', { text: 'NFC Cafe\u0301', highlight: null, break_before: 4 }), /binding/);
  assert.throws(() => headlineParts('🍔', { text: '🍔', highlight: null, break_before: 2 }), /scalar offset/);
});
test('all product media roles consume the same closed presentation helper, without changing order runtime', () => {
  const root = new URL('../src/ui/storefront/', import.meta.url);
  for (const file of ['home/MenuParts.tsx', 'home/HomeParts.tsx', 'search/SearchScreen.tsx', 'product/ProductSheet.tsx', 'cart/LiveCartAside.tsx', 'cart/LiveCartDock.tsx', 'checkout/CartScreen.tsx']) {
    assert.match(readFileSync(new URL(file, root), 'utf8'), /productImageClass\(/, file);
  }
  const parts = readFileSync(new URL('home/HomeParts.tsx', root), 'utf8');
  assert.match(parts, /data-sf-category=\{isCategory \? promo\.categoryId/);
  assert.match(parts, /data-sf-item=\{isCategory \? undefined : promo\.itemId/);
  assert.doesNotMatch(parts.slice(parts.indexOf('export function PromoBanner'), parts.indexOf('export function StoryCard')), /type="button" disabled/);
  const chrome = readFileSync(new URL('home/HomeChrome.tsx', root), 'utf8');
  assert.match(chrome, /<CategoryIcon path=\{category\.iconPath\} image=\{category\.image\}/);
  assert.match(chrome, /return image === null \? <svg/);
  assert.match(chrome, /heading\.focus\(\{ preventScroll: true \}\)/);
  assert.match(chrome, /setActive\(id\); setPicks\(false\); setQuery\(''\); setCategoryTarget\(id\)/);
});
