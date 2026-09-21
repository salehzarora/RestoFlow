// Modifier pricing. Every figure is an INTEGER number of minor units from the
// fixture to the CTA; nothing divides by 100 except the display formatter.
//
// The arithmetic below is not invented: it is the prototype's `unit()`
// (Storefront.dc.html:689) applied to the published GROUPS deltas, so the
// numbers are checkable by hand against storefront-data.js.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const p = await import('../src/money/pricing.ts');
const { MODIFIER_GROUPS, groupsFor, findGroup } = await import('../src/source/modifier-fixture.ts');
const { MENU_ITEMS } = await import('../src/source/menu-fixture.ts');
const { formatMoney } = await import('../src/money/format.ts');

const item = (id) => MENU_ITEMS.find((i) => i.id === id);

test('quantity clamps to the designed 1..20 and refuses a non-integer', () => {
  assert.equal(p.MIN_QTY, 1);
  assert.equal(p.MAX_QTY, 20);
  assert.equal(p.clampQty(0), 1);
  assert.equal(p.clampQty(-5), 1);
  assert.equal(p.clampQty(1), 1);
  assert.equal(p.clampQty(20), 20);
  assert.equal(p.clampQty(21), 20);
  assert.equal(p.clampQty(1e9), 20);
  // A fractional quantity is a bug upstream, not something to round away.
  for (const bad of [1.5, NaN, Infinity, -Infinity]) {
    assert.throws(() => p.clampQty(bad), `clampQty must refuse ${bad}`);
  }
});

test('a group delta is the SUM of the selected options, and only of real ones', () => {
  const extras = findGroup('extras');
  assert.ok(extras);
  assert.equal(p.groupDeltaMinor(extras, []), 0);
  assert.equal(p.groupDeltaMinor(extras, ['cheese']), 600);
  assert.equal(p.groupDeltaMinor(extras, ['cheese', 'bacon']), 1400);
  assert.equal(p.groupDeltaMinor(extras, ['cheese', 'bacon', 'egg']), 1900);
  // An id the group does not offer contributes nothing rather than throwing:
  // stored carts are untrusted and must degrade, not crash.
  assert.equal(p.groupDeltaMinor(extras, ['cheese', 'not-a-real-option']), 600);
  // A duplicate cannot be double charged. Two independent layers stop it, and
  // both are asserted, because either one alone would make this vacuous:
  //   1. the storage parser REJECTS a payload carrying a repeated option id;
  //   2. the pricer counts each option once regardless.
  assert.equal(p.groupDeltaMinor(extras, ['cheese', 'cheese']), 600);
});

test('THE PROTOTYPE PRICING BUG IS NOT REPRODUCED: a selection for a group the item does not offer is never priced', () => {
  // Storefront.dc.html:689 iterates the SELECTION MAP and prices every entry,
  // so seeding `sel.extras = ['cheese']` on item 7 - which has no `extras`
  // group - adds 600 and renders a CTA of the wrong total. That is exactly how
  // the canonical G18 screenshot ends up showing 2800 for a 2200 item.
  const fries = item('7');
  assert.ok(fries, 'item 7 must exist');
  assert.equal(fries.priceMinor, 2200);
  assert.ok(!fries.groupIds.includes('extras'), 'item 7 must not offer extras');

  const groups = groupsFor(fries.groupIds);
  const hostile = { extras: ['cheese'], sauce: ['ketchup'] };
  // 2200 + 0 (ketchup) and NOT + 600.
  assert.equal(p.unitPriceMinor(fries, groups, hostile), 2200);
});

test('a unit price is the base plus every selected delta, across several groups', () => {
  const classic = item('1');
  assert.equal(classic.priceMinor, 5500);
  const groups = groupsFor(classic.groupIds);
  assert.deepEqual(classic.groupIds, ['bun', 'extras', 'remove']);

  assert.equal(p.unitPriceMinor(classic, groups, {}), 5500);
  assert.equal(p.unitPriceMinor(classic, groups, { bun: ['classic'] }), 5500);
  assert.equal(p.unitPriceMinor(classic, groups, { bun: ['brioche'] }), 6000);
  assert.equal(
    p.unitPriceMinor(classic, groups, { bun: ['brioche'], extras: ['cheese', 'avo'] }),
    5500 + 500 + 600 + 700,
  );
  // A removal group is free, in both directions.
  assert.equal(
    p.unitPriceMinor(classic, groups, { bun: ['brioche'], remove: ['onion', 'pickle'] }),
    6000,
  );
});

test('a line total is unit x quantity, and a subtotal is the sum of line totals', () => {
  const classic = item('1');
  const groups = groupsFor(classic.groupIds);
  const sel = { bun: ['brioche'], extras: ['cheese'] };
  const unit = p.unitPriceMinor(classic, groups, sel);
  assert.equal(unit, 6600);
  assert.equal(p.lineTotalMinor(classic, groups, sel, 1), 6600);
  assert.equal(p.lineTotalMinor(classic, groups, sel, 3), 19800);
  assert.equal(p.subtotalMinor([6600, 19800, 0]), 26400);
  assert.equal(p.subtotalMinor([]), 0);
});

test('every arithmetic result stays an integer, so formatMoney never throws', () => {
  for (const it of MENU_ITEMS) {
    const groups = groupsFor(it.groupIds);
    // Select EVERY option of every group at once: the widest possible total.
    const all = {};
    for (const g of groups) all[g.id] = g.options.map((o) => o.id);
    const unit = p.unitPriceMinor(it, groups, all);
    assert.ok(Number.isInteger(unit), `${it.id}: unit ${unit} is not an integer`);
    for (const qty of [1, 7, 20]) {
      const total = p.lineTotalMinor(it, groups, all, qty);
      assert.ok(Number.isInteger(total), `${it.id} x${qty}: ${total} is not an integer`);
      assert.doesNotThrow(() => formatMoney(total));
    }
  }
});

test('the note cap is the designed 140 characters', () => {
  assert.equal(p.MAX_NOTE, 140);
});

test('no published modifier delta is negative or fractional', () => {
  for (const group of MODIFIER_GROUPS) {
    for (const option of group.options) {
      assert.ok(
        Number.isInteger(option.priceDeltaMinor),
        `${group.id}/${option.id}: ${option.priceDeltaMinor} is not an integer`,
      );
      assert.ok(
        option.priceDeltaMinor >= 0,
        `${group.id}/${option.id}: a negative delta would let an item be priced below its base`,
      );
    }
  }
});

test('a RESTORED selection is clamped to what the group actually allows', () => {
  // The storage parser validates SHAPE but is menu-agnostic: it cannot know
  // that `extras` admits at most three or that `bun` admits exactly one. A
  // hand-edited cart would otherwise be priced outside the designed bounds.
  const extras = findGroup('extras');
  const bun = findGroup('bun');

  // Five extras, all real, all distinct - accepted by the parser, capped here.
  const all = ['cheese', 'bacon', 'egg', 'jal', 'avo'];
  assert.equal(p.boundedSelection(extras, all).length, 3);
  assert.equal(p.groupDeltaMinor(extras, all), 600 + 800 + 500); // the first three

  // A single-select group takes exactly one, whatever was stored.
  assert.deepEqual([...p.boundedSelection(bun, ['brioche', 'classic'])], ['brioche']);
  assert.equal(p.groupDeltaMinor(bun, ['brioche', 'classic']), 500);

  // Unknown ids are dropped before the cap is applied, so they cannot displace
  // real options out of the allowance.
  assert.deepEqual(
    [...p.boundedSelection(extras, ['nope', 'cheese', 'bacon', 'egg'])],
    ['cheese', 'bacon', 'egg'],
  );
});

test('the clamp cannot raise a price above the designed maximum for a group', () => {
  const extras = findGroup('extras');
  const everyDelta = extras.options.map((o) => o.priceDeltaMinor).sort((a, b) => b - a);
  const dearest = everyDelta.slice(0, extras.max).reduce((a, b) => a + b, 0);
  const asked = p.groupDeltaMinor(extras, extras.options.map((o) => o.id));
  assert.ok(asked <= dearest, `${asked} exceeds the dearest legal ${extras.max} (${dearest})`);
});
