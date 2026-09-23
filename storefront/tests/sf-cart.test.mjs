// The cart: its storage boundary and its pure model.
//
// STORED CART CONTENT IS UNTRUSTED INPUT. It is attacker-controllable in the
// ordinary sense (anyone can open devtools and rewrite it) and corruptible in
// the boring sense (a half-written value, an older build's shape). Every test
// below feeds parseCart something hostile or malformed and asserts it degrades
// to a usable EMPTY cart rather than crashing, mis-pricing or poisoning an
// object prototype.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const s = await import('../src/cart/cartStorage.ts');
const model = await import('../src/cart/cartModel.ts');
const { MENU_ITEMS, MENU_VERSION } = await import('../src/source/menu-fixture.ts');
const { MODIFIER_GROUPS } = await import('../src/source/modifier-fixture.ts');

const SLUG = 'maps-burger';
const empty = () => s.emptyCart(SLUG, MENU_VERSION);
const parse = (value) => s.parseCart(value, SLUG, MENU_VERSION);
const line = (over = {}) => ({
  lineId: 'l1abc',
  itemId: '1',
  qty: 2,
  selections: { bun: ['brioche'], extras: ['cheese'] },
  note: 'no onion',
  ...over,
});
const payload = (over = {}) =>
  JSON.stringify({ schema: 1, slug: SLUG, menuVersion: MENU_VERSION, lines: [line()], ...over });

// ------------------------------------------------------------------- the key

test('the storage key is EXACTLY the approved shape', () => {
  assert.equal(s.cartKey(SLUG), 'sf:v1:cart:maps-burger');
});

test('the key builder refuses anything that is not a resolved slug', () => {
  for (const bad of ['', 'Bad Slug', '../etc', 'a/b', 'UPPER', 'x'.repeat(64), null, undefined, 7]) {
    assert.equal(s.cartKey(bad), null, `cartKey must refuse ${JSON.stringify(bad)}`);
  }
});

// --------------------------------------------------------------- the parser

test('a well-formed payload round-trips exactly', () => {
  const parsed = parse(payload());
  assert.equal(parsed.lines.length, 1);
  assert.equal(parsed.lines[0].itemId, '1');
  assert.equal(parsed.lines[0].qty, 2);
  assert.deepEqual(parsed.lines[0].selections.extras, ['cheese']);
  // Serialise -> parse is a fixed point.
  assert.deepEqual(parse(s.serialiseCart(parsed)), parsed);
});

test('every malformed payload degrades to an EMPTY cart, never a throw', () => {
  const hostile = [
    null,
    undefined,
    '',
    'not json',
    '[]',
    '"a string"',
    '42',
    'null',
    '{}',
    '{"schema":2,"slug":"maps-burger","menuVersion":"' + MENU_VERSION + '","lines":[]}',
    payload({ slug: 'other-tenant' }),
    payload({ menuVersion: 'stale-version' }),
    payload({ lines: 'not an array' }),
    payload({ lines: [null] }),
    payload({ lines: [{}] }),
    payload({ lines: [line({ qty: 0 })] }),
    payload({ lines: [line({ qty: 21 })] }),
    payload({ lines: [line({ qty: 1.5 })] }),
    payload({ lines: [line({ qty: '2' })] }),
    payload({ lines: [line({ lineId: 'bad id' })] }),
    payload({ lines: [line({ itemId: '../../etc/passwd' })] }),
    payload({ lines: [line({ selections: 'nope' })] }),
    payload({ lines: [line({ selections: { bun: 'brioche' } })] }),
    payload({ lines: [line({ selections: { 'bad group': ['x'] } })] }),
    payload({ lines: [line({ selections: { bun: ['bad option'] } })] }),
    payload({ lines: [line({ note: 42 })] }),
  ];
  for (const value of hostile) {
    let parsed;
    assert.doesNotThrow(() => {
      parsed = parse(value);
    }, `parseCart threw on ${String(value).slice(0, 60)}`);
    assert.deepEqual(parsed, empty(), `not emptied: ${String(value).slice(0, 60)}`);
  }
});

test('ONE bad line invalidates the WHOLE payload, so a cart is never partly trusted', () => {
  const mixed = payload({ lines: [line(), line({ lineId: 'l2def', qty: 999 })] });
  assert.deepEqual(parse(mixed), empty());
});

test('LAYER 1 of the double-charge defence: a repeated option id is REJECTED outright', () => {
  // The pricer counts each option once as well (tests/sf-money.test.mjs), but
  // that is defence in depth. This is the primary boundary, and asserting it
  // here is what stops the money test's claim from being vacuous.
  const doubled = payload({ lines: [line({ selections: { extras: ['cheese', 'cheese'] } })] });
  assert.deepEqual(parse(doubled), empty());
});

test('a forbidden key is REJECTED, and the vector really reaches the parser', () => {
  // WHY THIS IS BUILT FROM RAW JSON TEXT, NOT AN OBJECT LITERAL.
  //
  // In an object LITERAL, `{ __proto__: [...] }` is a PROTOTYPE ASSIGNMENT: the
  // object gets NO own property, and JSON.stringify emits `{}`. A test written
  // that way never sends a __proto__ key anywhere and proves nothing.
  // `JSON.parse` is different - it creates a real OWN property - and that is
  // the path untrusted storage actually takes.
  for (const key of ['__proto__', 'constructor', 'prototype']) {
    const raw =
      '{"schema":1,"slug":"' + SLUG + '","menuVersion":"' + MENU_VERSION +
      '","lines":[{"lineId":"l1abc","itemId":"1","qty":1,"selections":' +
      '{"' + key + '":["cheese"],"extras":["bacon"]},"note":""}]}';

    // NON-VACUITY: prove the forbidden key is an OWN property of what the
    // parser receives. Without this the assertion below could pass simply
    // because the key never existed.
    const asParsed = JSON.parse(raw);
    assert.ok(
      Object.prototype.hasOwnProperty.call(asParsed.lines[0].selections, key),
      `${key} never became an own property, so this vector is vacuous`,
    );

    // REJECTED, not silently dropped: a partly-trusted cart is worse than an
    // empty one, and dropping the key would under-price the line.
    assert.deepEqual(parse(raw), empty(), `${key} must invalidate the payload`);
  }

  // The same at the line level and at the top level of the payload.
  const atLine =
    '{"schema":1,"slug":"' + SLUG + '","menuVersion":"' + MENU_VERSION +
    '","lines":[{"__proto__":{"x":1},"lineId":"l1abc","itemId":"1","qty":1,' +
    '"selections":{},"note":""}]}';
  assert.deepEqual(parse(atLine), empty(), 'a forbidden key on the LINE must be rejected');

  const atTop =
    '{"__proto__":{"polluted":true},"schema":1,"slug":"' + SLUG +
    '","menuVersion":"' + MENU_VERSION + '","lines":[]}';
  assert.deepEqual(parse(atTop), empty(), 'a forbidden key on the PAYLOAD must be rejected');

  // And nothing was polluted along the way.
  assert.equal({}.polluted, undefined, 'Object.prototype was polluted');
  assert.equal(Object.prototype.polluted, undefined, 'Object.prototype was polluted');
  assert.equal({}.x, undefined, 'Object.prototype was polluted');
});

test('the 64 KiB ceiling is measured in UTF-8 BYTES, not UTF-16 code units', () => {
  const CAP = 64 * 1024;
  const bytes = (text) => new TextEncoder().encode(text).length;
  const build = (pad) =>
    '{"schema":1,"slug":"' + SLUG + '","menuVersion":"' + MENU_VERSION +
    '","lines":[],"pad":"' + pad + '"}';

  // ASCII: one code unit, one byte - length and bytes agree.
  const asciiUnder = build('a'.repeat(CAP - 200));
  assert.ok(bytes(asciiUnder) < CAP);
  assert.deepEqual(parse(asciiUnder), empty()); // empty because `pad` is not a cart key
  const asciiOver = build('a'.repeat(CAP + 200));
  assert.ok(bytes(asciiOver) > CAP);
  assert.deepEqual(parse(asciiOver), empty());

  // ARABIC is the case that `.length` got wrong: one code unit, TWO UTF-8
  // bytes. This payload is comfortably under the cap by length and comfortably
  // OVER it by bytes, so it distinguishes the two implementations.
  const arabic = build('م'.repeat(40000));
  assert.ok(arabic.length < CAP, 'must be UNDER the cap when counted as code units');
  assert.ok(bytes(arabic) > CAP, 'must be OVER the cap when counted as UTF-8 bytes');
  assert.deepEqual(parse(arabic), empty(), 'an over-size payload must be refused');

  // A REAL cart that is legitimately under the byte cap still parses, so the
  // stricter measure did not break the normal case.
  const good = payload();
  assert.ok(bytes(good) < CAP);
  assert.equal(parse(good).lines.length, 1);
});

test('WRITE SHAPE: only the approved key and the approved payload can be stored', () => {
  // The read side is tested above. This pins what the module may WRITE, which
  // nothing previously constrained: the file allowlist says WHICH file may use
  // localStorage, never WHAT it puts there.
  const src = readFileSync(new URL('../src/cart/cartStorage.ts', import.meta.url), 'utf8');

  // Exactly one namespace, and the key is always built from it.
  assert.match(src, /const NAMESPACE = 'sf:v1:cart:';/);
  assert.equal((src.match(/\.setItem\(/g) ?? []).length, 1, 'exactly one write site');
  assert.match(src, /found\.setItem\(key, text\)/);
  // The key always comes from cartKey(), which validates the slug.
  assert.match(src, /const key = cartKey\(state\.slug\);/);
  assert.match(src, /isValidSlug\(slug\)/);

  // The serialiser is explicit about its four fields and five per-line fields;
  // a spread would let any extra key through.
  assert.ok(!/\.\.\.state/.test(src), 'the serialiser must not spread the state');
  assert.ok(!/\.\.\.line/.test(src), 'the serialiser must not spread a line');

  // And the emitted text really carries nothing else.
  let state = empty();
  state = model.addLine(state, {
    itemId: '1',
    qty: 2,
    selections: { bun: ['brioche'] },
    note: 'no onion',
  });
  const text = s.serialiseCart(state);
  const back = JSON.parse(text);
  assert.deepEqual(Object.keys(back).sort(), ['lines', 'menuVersion', 'schema', 'slug']);
  assert.deepEqual(Object.keys(back.lines[0]).sort(),
    ['itemId', 'lineId', 'note', 'qty', 'selections']);

  for (const forbidden of [
    'fullName', 'phone', 'address', 'street', 'building', 'apartment',
    'deliveryNotes', 'payment', 'requestRef', 'status', 'token', 'secret',
  ]) {
    assert.ok(!text.includes(forbidden), `${forbidden} reached the stored payload`);
  }
});

test('the parser is bounded in every dimension an attacker controls', () => {
  // Byte ceiling.
  const huge = JSON.stringify({
    schema: 1,
    slug: SLUG,
    menuVersion: MENU_VERSION,
    lines: [line({ note: 'x'.repeat(200 * 1024) })],
  });
  assert.deepEqual(parse(huge), empty(), 'an oversized payload must be refused');

  // Line ceiling.
  const many = payload({
    lines: Array.from({ length: 60 }, (_, i) => line({ lineId: `l${i}aaa` })),
  });
  assert.deepEqual(parse(many), empty(), 'too many lines must be refused');

  // Groups-per-line ceiling.
  const groups = {};
  for (let i = 0; i < 20; i += 1) groups[`g${i}`] = ['x'];
  assert.deepEqual(parse(payload({ lines: [line({ selections: groups })] })), empty());

  // Options-per-group ceiling.
  const opts = Array.from({ length: 20 }, (_, i) => `o${i}`);
  assert.deepEqual(parse(payload({ lines: [line({ selections: { extras: opts } })] })), empty());
});

test('a stored note is sanitised and capped, never rendered raw', () => {
  const long = parse(payload({ lines: [line({ note: 'y'.repeat(200) })] }));
  assert.equal(long.lines.length, 1);
  assert.equal(long.lines[0].note.length, 140);
});

test('NO checkout, identity, payment or request field can survive into a stored cart', () => {
  // Phase C may persist ONLY ids, quantity, selections and a kitchen note. If
  // an extra key ever round-trips, the boundary has been widened by accident.
  const forbidden = {
    fullName: 'A Person',
    phone: '+972500000000',
    address: 'somewhere',
    city: 'somewhere',
    street: 'a street',
    building: '4',
    payment: 'card',
    cardNumber: '4111111111111111',
    requestRef: 'MB-2487',
    status: 'accepted',
    token: 'secret',
  };
  const smuggled = parse(payload({ lines: [{ ...line(), ...forbidden }] }));
  assert.equal(smuggled.lines.length, 1);
  assert.deepEqual(
    Object.keys(smuggled.lines[0]).sort(),
    ['itemId', 'lineId', 'note', 'qty', 'selections'],
    'a cart line carries exactly the five approved fields',
  );
  // And the serialiser cannot re-emit them either.
  const text = s.serialiseCart(smuggled);
  for (const key of Object.keys(forbidden)) {
    assert.ok(!text.includes(key), `${key} reached the serialised payload`);
  }
  for (const value of Object.values(forbidden)) {
    assert.ok(!text.includes(value), `a forbidden VALUE reached the serialised payload`);
  }
});

test('a top-level cart key that is not approved never round-trips', () => {
  const extra = parse(payload({ customer: { phone: '+972500000000' }, coupon: 'FREE' }));
  assert.deepEqual(Object.keys(extra).sort(), ['lines', 'menuVersion', 'schema', 'slug']);
  assert.ok(!s.serialiseCart(extra).includes('coupon'));
});

// ---------------------------------------------------------------- the model

test('a line whose item has left the menu is SKIPPED, never rendered from stale data', () => {
  const state = { schema: 1, slug: SLUG, menuVersion: MENU_VERSION, lines: [
    { lineId: 'l1', itemId: '1', qty: 1, selections: {}, note: '' },
    { lineId: 'l2', itemId: 'no-such-item', qty: 3, selections: {}, note: '' },
  ] };
  const summary = model.summarise(state, MENU_ITEMS, MODIFIER_GROUPS);
  assert.equal(summary.lines.length, 1);
  assert.equal(summary.lines[0].item.id, '1');
  // The vanished line contributes NOTHING to the count or the subtotal.
  assert.equal(summary.itemCount, 1);
  assert.equal(summary.subtotalMinor, 5500);
});

test('the summary counts UNITS, not lines, and subtotals them', () => {
  let state = empty();
  state = model.addLine(state, { itemId: '1', qty: 2, selections: { bun: ['brioche'] }, note: '' });
  state = model.addLine(state, { itemId: '7', qty: 3, selections: { sauce: ['ranch'] }, note: '' });
  const summary = model.summarise(state, MENU_ITEMS, MODIFIER_GROUPS);
  assert.equal(summary.lines.length, 2);
  assert.equal(summary.itemCount, 5);
  // (5500 + 500) * 2 + (2200 + 200) * 3
  assert.equal(summary.subtotalMinor, 12000 + 7200);
});

test('each add is its OWN line: identical configurations are never silently merged', () => {
  // The approved design does not specify merging, and coalescing two distinct
  // additions would be inventing a product behaviour.
  let state = empty();
  const draft = { itemId: '1', qty: 1, selections: { bun: ['classic'] }, note: '' };
  state = model.addLine(state, draft);
  state = model.addLine(state, draft);
  assert.equal(state.lines.length, 2);
  assert.notEqual(state.lines[0].lineId, state.lines[1].lineId);
});

test('every generated line id is accepted by the storage parser', () => {
  // A model that mints ids the parser rejects would produce carts that vanish
  // on the next page load.
  let state = empty();
  for (let i = 0; i < 40; i += 1) {
    state = model.addLine(state, { itemId: '1', qty: 1, selections: {}, note: '' });
  }
  assert.equal(state.lines.length, 40);
  assert.equal(new Set(state.lines.map((l) => l.lineId)).size, 40, 'ids must be unique');
  const reparsed = parse(s.serialiseCart(state));
  assert.equal(reparsed.lines.length, 40, 'a round trip must not lose lines');
});

test('updating an unknown line changes nothing and returns the SAME object', () => {
  const state = model.addLine(empty(), { itemId: '1', qty: 1, selections: {}, note: '' });
  const after = model.updateLine(state, 'nope', { qty: 9, selections: {}, note: 'x' });
  assert.equal(after, state, 'an unknown line id must be a no-op, not an append');
  assert.equal(after.lines.length, 1);
});

test('update replaces a line in place; remove drops exactly one', () => {
  let state = empty();
  state = model.addLine(state, { itemId: '1', qty: 1, selections: {}, note: '' });
  state = model.addLine(state, { itemId: '7', qty: 1, selections: { sauce: ['bbq'] }, note: '' });
  const first = state.lines[0].lineId;

  state = model.updateLine(state, first, { qty: 4, selections: { bun: ['brioche'] }, note: 'hot' });
  assert.equal(state.lines.length, 2);
  assert.equal(state.lines[0].qty, 4);
  assert.equal(state.lines[0].note, 'hot');
  assert.deepEqual(state.lines[0].selections.bun, ['brioche']);

  state = model.removeLine(state, first);
  assert.equal(state.lines.length, 1);
  assert.equal(state.lines[0].itemId, '7');
});

test('a quantity is clamped on the way in, so no line can persist out of range', () => {
  const state = model.addLine(empty(), { itemId: '1', qty: 999, selections: {}, note: '' });
  assert.equal(state.lines[0].qty, 20);
  const low = model.updateLine(state, state.lines[0].lineId, { qty: 0, selections: {}, note: '' });
  assert.equal(low.lines[0].qty, 1);
});

test('the line cap is enforced by the MODEL, not only by the parser', () => {
  // Past MAX_LINES the storage layer refuses to write. If the model kept
  // appending, the in-memory cart and the stored cart would diverge and the
  // next reload would silently discard everything added after the cap.
  let state = empty();
  for (let i = 0; i < s.MAX_LINES + 10; i += 1) {
    state = model.addLine(state, { itemId: '1', qty: 1, selections: {}, note: '' });
  }
  assert.equal(state.lines.length, s.MAX_LINES);
  // And what the model produced still round-trips, which is the point.
  assert.equal(parse(s.serialiseCart(state)).lines.length, s.MAX_LINES);
});

test('at the cap, addLine returns the SAME object so nothing re-renders', () => {
  let state = empty();
  for (let i = 0; i < s.MAX_LINES; i += 1) {
    state = model.addLine(state, { itemId: '1', qty: 1, selections: {}, note: '' });
  }
  assert.equal(model.addLine(state, { itemId: '7', qty: 1, selections: {}, note: '' }), state);
});

test('the WIDE ASIDE is wired to the cart - and to the SAME quote as every other surface', () => {
  // Phase C's aside was a deliberately non-functional seam because the cart
  // route did not exist. It does now, so this guard MOVES rather than being
  // deleted: what it pins is no longer "it cannot show a cart" but "it shows
  // the same cart, from the same authority, and computes nothing itself".
  //
  // The old `toCartView` projection stays gone: the live surfaces read a
  // CartSummary resolved from the CURRENT menu, never a presentational view.
  assert.equal(model.toCartView, undefined, 'the live->presentational projection must be gone');

  const aside = readFileSync(
    new URL('../src/ui/storefront/cart/LiveCartAside.tsx', import.meta.url), 'utf8');

  // It reads a resolved summary and a Quote; it never derives money. It MAY
  // read `quote.taxRateBp` to label the tax row (STOREFRONT-READ-001: the
  // rate is the tenant's, interpolated into the label), so the guard bans the
  // ARITHMETIC shapes, not the field name.
  assert.ok(aside.includes('summary: CartSummary | null'));
  assert.ok(aside.includes('quote: Quote | null'));
  for (const banned of ASIDE_MONEY_BANNED) {
    assert.ok(!aside.includes(banned), `the aside must not compute money: found ${banned}`);
  }

  // The fee row is gated on feeApplies - never on a truthy amount, or a served
  // zone with free delivery would be presented as no delivery at all.
  assert.ok(aside.includes('quote.feeApplies'), 'the aside must render the delivery-fee row');

  // What the aside deliberately does NOT SHOW, by design and not by omission:
  // thumbnails, the kitchen note, Edit, Remove, and the cart notices.
  for (const absent of ['lineMedia', 'NoteIcon', 'm.edit', 'm.remove', 'changedTitle']) {
    assert.ok(!aside.includes(absent), `the aside must not carry ${absent}`);
  }

  // But it must PRESERVE the note it does not show. A stepper that wrote back
  // a line without its note would silently erase a kitchen instruction the
  // visitor typed - invisible here, and invisible on the cart page afterwards.
  assert.match(aside, /note: line\.line\.note/,
    'the aside stepper must carry the kitchen note through an update');
  assert.match(aside, /selections: line\.line\.selections/,
    'the aside stepper must carry the modifier selections through an update');

  // And the runtime hands it the cart through one named slot.
  const runtime = readFileSync(
    new URL('../src/ui/storefront/cart/CartRuntime.tsx', import.meta.url), 'utf8');
  assert.ok(runtime.includes('AsideSlot'), 'the cart runtime must expose the aside slot');
  assert.ok(runtime.includes('LiveCartAside'));
});

/** The arithmetic a drifting aside would take: a rounding, a rate constant, a rate multiplication, the bp division. */
const ASIDE_MONEY_BANNED = ['Math.round', 'TAX_RATE', '* quote.taxRateBp', 'taxRateBp *', '/ 10000', '* 0.'];

test('NEGATIVE CONTROL: the aside money guard would notice a hand-rolled total', () => {
  // The rule above is worth something only if the banned strings really are
  // the shape a drifting implementation would take.
  const drifted = 'const taxMinor = Math.round(subtotal * TAX_RATE);';
  const caught = ASIDE_MONEY_BANNED.filter((b) => drifted.includes(b));
  assert.deepEqual(caught, ['Math.round', 'TAX_RATE']);
  const driftedBp = 'const taxMinor = (subtotal * quote.taxRateBp) / 10000;';
  assert.deepEqual(ASIDE_MONEY_BANNED.filter((b) => driftedBp.includes(b)), ['* quote.taxRateBp', '/ 10000']);
  // ...and the legitimate label read is not an offence.
  assert.deepEqual(ASIDE_MONEY_BANNED.filter((b) => 'fill(m.tax, { p: formatRateBp(quote.taxRateBp) })'.includes(b)), []);
});

test('a REMOVAL reads as a removal, never as an addition', () => {
  // "onion" and "no onion" are opposite instructions to a kitchen.
  // COMPONENT_INVENTORY.md:124 prefixes removals with the multiplication sign.
  const state = model.addLine(empty(), {
    itemId: '1',
    qty: 1,
    selections: { bun: ['brioche'], remove: ['onion'] },
    note: '',
  });
  const resolved = model.resolveLine(state.lines[0], MENU_ITEMS, MODIFIER_GROUPS);
  const summary = model.optionSummary(resolved);

  assert.ok(summary.includes('\u2715'), `removals must carry the marker: ${summary}`);
  // The separator is U+00B7 MIDDLE DOT. That is what the prototype joins with
  // (Storefront.dc.html:690 - the bytes are 20 B7 20) and what the approved
  // cart screenshots render. Phase C shipped U+2022 BULLET and this assertion
  // pinned the wrong character with it; Phase D corrects both together.
  assert.ok(!summary.includes('\u2022'), 'the separator must not be a BULLET');
  // The ADDED option must NOT carry the removal marker.
  const parts = summary.split(' \u00b7 ');
  assert.equal(parts.length, 2);
  assert.ok(!parts[0].includes('\u2715'), 'an added option must not be marked as removed');
  assert.ok(parts[1].startsWith('\u2715'), 'the removal must lead with the marker');
});

test('a resolved line is priced and summarised within the group bounds', () => {
  // Five extras stored; only three may be priced OR shown, and the two must
  // agree - a summary listing more than the price charged would be a lie.
  const line = {
    lineId: 'l1aaa',
    itemId: '1',
    qty: 1,
    selections: { extras: ['cheese', 'bacon', 'egg', 'jal', 'avo'] },
    note: '',
  };
  const resolved = model.resolveLine(line, MENU_ITEMS, MODIFIER_GROUPS);
  assert.equal(resolved.optionNames.length, 3);
  assert.equal(resolved.unitMinor, 5500 + 600 + 800 + 500);
});

test('lines naming an item the menu no longer has are PRUNED, not kept invisibly', () => {
  // Such a line renders as nothing and counts as nothing, so without pruning it
  // would sit in storage for ever - and Phase C has no cart screen from which a
  // visitor could remove it.
  const withOrphan = {
    schema: 1,
    slug: SLUG,
    menuVersion: MENU_VERSION,
    lines: [
      { lineId: 'l1aaa', itemId: '1', qty: 1, selections: {}, note: '' },
      { lineId: 'l2bbb', itemId: 'gone', qty: 20, selections: {}, note: '' },
    ],
  };
  const usable = model.summarise(withOrphan, MENU_ITEMS, MODIFIER_GROUPS);
  assert.equal(usable.lines.length, 1);
  assert.equal(usable.itemCount, 1);
  // The pruned state is what useCart writes back; assert the shape it produces.
  const pruned = { ...withOrphan, lines: usable.lines.map((l) => l.line) };
  assert.equal(pruned.lines.length, 1);
  assert.equal(pruned.lines[0].itemId, '1');
  assert.deepEqual(parse(s.serialiseCart(pruned)).lines.length, 1);
});
