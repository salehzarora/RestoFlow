// Search filtering.
//
// THE CANONICAL SCREENSHOT IS THE PROOF. `search__ar__dark__results__390x844.png`
// shows the query "برجر" returning exactly four rows - Maps كلاسيك ₪55, فيجي
// برجر ₪48, فاميلي باكج ₪249, ميني برجر أطفال ₪35 - in that order. If this
// filter is right, it reproduces that list exactly; if it drifts, these
// assertions fail. That is a much stronger check than restating the code.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const { searchItems, EMPTY_QUERY_COUNT } = await import('../src/source/search.ts');
const { storefrontMessages } = await import('../src/i18n/storefront.ts');
const { MENU_ITEMS } = await import('../src/source/menu-fixture.ts');
const { formatMoney } = await import('../src/money/format.ts');

const ids = (query) => searchItems(MENU_ITEMS, query).map((i) => i.id);

test('G15: the canonical query reproduces the canonical four rows, in order', () => {
  const hits = searchItems(MENU_ITEMS, 'برجر');
  assert.deepEqual(hits.map((i) => i.id), ['1', '6', '17', '22']);
  assert.deepEqual(hits.map((i) => formatMoney(i.priceMinor)), ['₪55', '₪48', '₪249', '₪35']);
});

test('G15 also proves the search covers the DESCRIPTION, not just the name', () => {
  // "Maps كلاسيك" (id 1) does not contain "برجر" in its name; it matches
  // through its description. Dropping the description from the haystack would
  // silently lose the screenshot's FIRST row.
  const first = MENU_ITEMS.find((i) => i.id === '1');
  assert.ok(!first.name.includes('برجر'), 'fixture drift: id 1 now matches by name');
  assert.ok(first.description.includes('برجر'));
  assert.ok(ids('برجر').includes('1'));
});

test('G16: a query that matches nothing returns nothing', () => {
  assert.deepEqual(ids('سوشي'), []);
});

test('an empty query shows the first six items in MENU order, unfiltered', () => {
  assert.equal(EMPTY_QUERY_COUNT, 6);
  const initial = searchItems(MENU_ITEMS, '');
  assert.equal(initial.length, 6);
  assert.deepEqual(initial.map((i) => i.id), MENU_ITEMS.slice(0, 6).map((i) => i.id));
});

test('the initial six are NOT filtered by availability', () => {
  // The handoff says "the first six items" and the prototype slices the array
  // with no predicate, so a sold-out item appears. Any screenshot or browser
  // assertion over this screen must expect one.
  const initial = searchItems(MENU_ITEMS, '');
  assert.ok(
    initial.some((i) => i.soldOut),
    'fixture drift: the first six no longer include a sold-out item, ' +
      'so the sold-out search row is now unreachable and untestable',
  );
});

test('a whitespace-only query is treated as empty', () => {
  for (const blank of [' ', '   ', '\t', '\n ']) {
    assert.deepEqual(ids(blank), ids(''), `${JSON.stringify(blank)} must behave as empty`);
  }
});

test('matching is case-insensitive, which only matters for the Latin names', () => {
  const upper = ids('MAPS');
  const lower = ids('maps');
  assert.deepEqual(upper, lower);
  assert.ok(upper.length > 0, 'the fixture must contain a Latin-named item');
});

test('matching is a plain SUBSTRING, not tokenised', () => {
  const item = MENU_ITEMS[0];
  const middle = item.name.slice(1, 4);
  assert.ok(ids(middle).includes(item.id), 'an interior substring must match');

  // Two words that both occur but NOT contiguously must not match: the
  // prototype uses String.includes over the joined string, with no tokenising.
  const joined = `${item.name} ${item.description}`;
  const firstWord = joined.split(' ')[0];
  const lastWord = joined.split(' ').at(-1);
  if (firstWord && lastWord && firstWord !== lastWord) {
    assert.ok(
      !ids(`${lastWord} ${firstWord}`).includes(item.id),
      'a reordered pair must not match - that would imply tokenising',
    );
  }
});

test('results keep MENU order; there is no relevance ranking', () => {
  const hits = searchItems(MENU_ITEMS, 'برجر');
  const order = MENU_ITEMS.map((i) => i.id);
  const positions = hits.map((i) => order.indexOf(i.id));
  assert.deepEqual(positions, [...positions].sort((a, b) => a - b));
  // And specifically: the description-only match (id 1) ranks ABOVE the
  // name match (id 6), which a relevance sort would invert.
  assert.ok(order.indexOf('1') < order.indexOf('6'));
  assert.deepEqual(hits.slice(0, 2).map((i) => i.id), ['1', '6']);
});

test('a non-empty query has no result cap', () => {
  // Only the EMPTY query is capped at six. A common substring must be able to
  // return more than six rows.
  const common = searchItems(MENU_ITEMS, 'ا');
  assert.ok(common.length > EMPTY_QUERY_COUNT, `expected >6 hits, got ${common.length}`);
});

test('the filter never mutates or reorders the source array', () => {
  const before = MENU_ITEMS.map((i) => i.id);
  searchItems(MENU_ITEMS, 'برجر');
  searchItems(MENU_ITEMS, '');
  assert.deepEqual(MENU_ITEMS.map((i) => i.id), before);
});

test('a query of pure punctuation or a regex metacharacter is literal, not a pattern', () => {
  // The filter is String.includes, so these are searched literally and must not
  // throw or match everything the way a compiled regex would.
  for (const query of ['.*', '.+', '(', '[', '\\', '$', '^.*$']) {
    let out;
    assert.doesNotThrow(() => {
      out = searchItems(MENU_ITEMS, query);
    }, `threw on ${query}`);
    assert.ok(
      out.length < MENU_ITEMS.length,
      `${query} matched everything - it was treated as a pattern`,
    );
  }
});

// ---------------------------------------------------------------- C1 additions

test('R4: clearSearch is authored in all three dictionaries and is NOT `close`', () => {
  // The clear button previously reused `close` ("Close"), which tells a
  // screen-reader user the control leaves the screen. It empties the field.
  const expected = {
    ar: 'مسح البحث',
    he: 'נקה חיפוש',
    en: 'Clear search',
  };
  for (const [code, value] of Object.entries(expected)) {
    const m = storefrontMessages(code);
    assert.equal(m.clearSearch, value, `${code}: clearSearch`);
    assert.notEqual(m.clearSearch, m.close, `${code}: clearSearch must differ from close`);
    assert.notEqual(m.clearSearch, m.search, `${code}: clearSearch must differ from search`);
  }
});

test('R4: the search screen labels the clear button with clearSearch, not close', () => {
  const src = readFileSync(
    new URL('../src/ui/storefront/search/SearchScreen.tsx', import.meta.url), 'utf8');
  const clear = src.slice(src.indexOf('styles.clear'));
  assert.ok(clear.includes('aria-label={m.clearSearch}'), 'the clear button must use clearSearch');
  assert.ok(!/styles\.clear[\s\S]{0,400}aria-label=\{m\.close\}/.test(src),
    'the clear button must no longer reuse close');
});

test('R3: a sold-out search row carries a VISIBLE localized cue, not only sr-only text', () => {
  const src = readFileSync(
    new URL('../src/ui/storefront/search/SearchScreen.tsx', import.meta.url), 'utf8');
  // The cue must be rendered with a VISIBLE class, never the sr-only one.
  assert.ok(/item\.soldOut \? <span className=\{styles\.rowSoldOutTag\}>\{m\.soldOut\}<\/span>/.test(src),
    'the sold-out cue must be a visible, localized tag');
  assert.ok(!/home\.srOnly[^\n]*m\.soldOut/.test(src),
    'the sold-out reason must not be screen-reader-only');

  // And that class must actually paint something: a rule that only set opacity
  // would leave the cue invisible.
  const css = readFileSync(
    new URL('../src/ui/storefront/search/search.module.css', import.meta.url), 'utf8');
  const rule = css.slice(css.indexOf('.rowSoldOutTag'), css.indexOf('}', css.indexOf('.rowSoldOutTag')));
  for (const needed of ['background', 'color', 'font-size']) {
    assert.ok(rule.includes(needed), `.rowSoldOutTag must declare ${needed}`);
  }
  assert.ok(!/display:\s*none/.test(rule), '.rowSoldOutTag must not be hidden');
});

test('R3: the sold-out item is reachable in search but excluded from Popular', () => {
  const soldOut = MENU_ITEMS.filter((i) => i.soldOut);
  assert.ok(soldOut.length > 0, 'the fixture must contain a sold-out item');
  // Search lists it (it is inside the initial six).
  assert.ok(searchItems(MENU_ITEMS, '').some((i) => i.soldOut));
  // Popular never does: the rail is signature AND not sold out.
  for (const item of soldOut) {
    assert.ok(!(item.signature && !item.soldOut), 'a sold-out item must not qualify for Popular');
  }
});
