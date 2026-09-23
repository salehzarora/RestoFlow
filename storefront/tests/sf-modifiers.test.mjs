// The modifier contract.
//
// The GROUPS data is transcribed from prototype/storefront-data.js, which is
// the only place the approved modifier content exists - it is NOT in any .md or
// .json handoff file. These tests pin the transcription so a later edit cannot
// drift from the source, and pin the INVARIANTS the sheet's rules rely on.
//
// TWO OWNER-APPROVED CONTENT CORRECTIONS are asserted explicitly, so nobody
// later "restores" the prototype strings and silently reintroduces the doubled
// verb recorded at OPEN_QUESTIONS.md:13.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const {
  MODIFIER_GROUPS,
  MODIFIER_GROUP_IDS,
  findGroup,
  groupsFor,
} = await import('../src/source/modifier-fixture.ts');
const { MENU_ITEMS } = await import('../src/source/menu-fixture.ts');
const { storefrontMessages, fill } = await import('../src/i18n/storefront.ts');

test('the five approved groups exist, in the published order', () => {
  assert.deepEqual([...MODIFIER_GROUP_IDS], ['bun', 'extras', 'remove', 'sauce', 'meal']);
});

test('OWNER-APPROVED CORRECTION: the sauce and drink groups are named as nouns', () => {
  // The prototype names these "اختر الصوص" / "اختر المشروب" ("choose the
  // sauce"). The required-group alert is `requiredError` = "يرجى اختيار {g}"
  // ("please choose {g}"), so interpolating the prototype name produces
  // "please choose choose the sauce" - visible in canonical screenshot G18 and
  // recorded as a defect at OPEN_QUESTIONS.md:13. The owner approved the noun
  // form, which is what makes the sentence read correctly.
  assert.equal(findGroup('sauce').name, 'الصوص');
  assert.equal(findGroup('meal').name, 'المشروب');

  const m = storefrontMessages('ar');
  const sentence = fill(m.requiredError, { g: findGroup('sauce').name });
  assert.ok(!sentence.includes('اختيار اختر'), 'the verb must not be doubled');
});

test('the published deltas are exactly the prototype values', () => {
  const expected = {
    bun: { classic: 0, brioche: 500, lettuce: 0 },
    extras: { cheese: 600, bacon: 800, egg: 500, jal: 300, avo: 700 },
    remove: { onion: 0, pickle: 0, tomato: 0, sauce: 0 },
    sauce: { ketchup: 0, garlic: 0, bbq: 0, ranch: 200 },
    meal: { cola: 0, sprite: 0, water: 0, lemon: 500 },
  };
  for (const group of MODIFIER_GROUPS) {
    const want = expected[group.id];
    assert.ok(want, `unexpected group ${group.id}`);
    const got = Object.fromEntries(group.options.map((o) => [o.id, o.priceDeltaMinor]));
    assert.deepEqual(got, want, `${group.id} deltas drifted`);
  }
});

test('the required/single/max flags match the approved behaviour', () => {
  const shape = MODIFIER_GROUPS.map((g) => ({
    id: g.id,
    required: g.required,
    single: g.single,
    max: g.max ?? null,
    removal: g.removal ?? false,
  }));
  assert.deepEqual(shape, [
    { id: 'bun', required: true, single: true, max: null, removal: false },
    { id: 'extras', required: false, single: false, max: 3, removal: false },
    { id: 'remove', required: false, single: false, max: null, removal: true },
    { id: 'sauce', required: true, single: true, max: null, removal: false },
    { id: 'meal', required: true, single: true, max: null, removal: false },
  ]);
});

test('INVARIANT: a required group is single-select, so "choose 1" is always true', () => {
  // The sheet renders the badge "required - choose 1" for every required group.
  // A required MULTI group would need a minimum count the schema does not have,
  // and the badge would then be a lie. None exists; this pins that.
  for (const group of MODIFIER_GROUPS) {
    if (!group.required) continue;
    assert.ok(group.single, `${group.id}: a required group must be single-select`);
  }
});

test('INVARIANT: every removal option is free, so the empty delta label is always right', () => {
  // The sheet prints nothing beside a removal option. A priced removal would
  // therefore charge silently.
  for (const group of MODIFIER_GROUPS) {
    if (group.removal !== true) continue;
    for (const option of group.options) {
      assert.equal(option.priceDeltaMinor, 0, `${group.id}/${option.id} must be free`);
    }
  }
});

test('INVARIANT: a capped group offers more options than its cap', () => {
  // Otherwise the cap is unreachable and the approved max-reached toast is dead
  // code that no test could ever exercise.
  for (const group of MODIFIER_GROUPS) {
    if (group.max === undefined) continue;
    assert.ok(
      group.options.length > group.max,
      `${group.id}: cap ${group.max} is unreachable with ${group.options.length} options`,
    );
  }
});

test('option ids are unique WITHIN a group, and group ids are unique', () => {
  assert.equal(new Set(MODIFIER_GROUP_IDS).size, MODIFIER_GROUP_IDS.length);
  for (const group of MODIFIER_GROUPS) {
    const ids = group.options.map((o) => o.id);
    assert.equal(new Set(ids).size, ids.length, `${group.id} has a duplicate option id`);
    assert.ok(ids.length > 0, `${group.id} has no options`);
  }
});

test('an option id may repeat ACROSS groups, so nothing may key on it alone', () => {
  // `sauce` is both a group id and an option id inside `remove`. Any DOM id or
  // state key built from an option id alone would collide.
  assert.ok(findGroup('remove').options.some((o) => o.id === 'sauce'));
  assert.ok(MODIFIER_GROUP_IDS.includes('sauce'));
});

test('every groupId on every menu item resolves to a real group', () => {
  for (const item of MENU_ITEMS) {
    for (const id of item.groupIds) {
      assert.ok(findGroup(id), `item ${item.id} references unknown group ${id}`);
    }
    // groupsFor preserves the item's own order and drops nothing.
    assert.deepEqual(groupsFor(item.groupIds).map((g) => g.id), [...item.groupIds]);
  }
});

test('hasOptions is exactly "this item has at least one group"', () => {
  for (const item of MENU_ITEMS) {
    assert.equal(
      item.hasOptions,
      item.groupIds.length > 0,
      `item ${item.id}: hasOptions disagrees with groupIds`,
    );
  }
});

test('groupsFor ignores an unknown id rather than throwing', () => {
  assert.deepEqual(groupsFor(['bun', 'no-such-group']).map((g) => g.id), ['bun']);
  assert.deepEqual(groupsFor([]), []);
});

test('at least one item reaches each group, so no group is unreachable content', () => {
  const used = new Set(MENU_ITEMS.flatMap((i) => [...i.groupIds]));
  for (const id of MODIFIER_GROUP_IDS) {
    assert.ok(used.has(id), `group ${id} is not offered by any item`);
  }
});

test('at least one item is fully unconfigurable, and one carries a required group', () => {
  // Both branches of the sheet's CTA (immediately addable vs blocked) must be
  // reachable from the shipped fixture, or the blocked state is untestable.
  assert.ok(MENU_ITEMS.some((i) => i.groupIds.length === 0), 'no as-is item exists');
  assert.ok(
    MENU_ITEMS.some((i) => groupsFor(i.groupIds).some((g) => g.required)),
    'no item with a required group exists',
  );
});
