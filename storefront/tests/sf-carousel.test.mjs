import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const { carouselPosition, cycleIndex, swipeStep } = await import('../src/ui/storefront/home/carousel.ts');

test('one or two products never fabricate an extra neighbour, and every count wraps both ways', () => {
  for (const count of [1, 2, 3, 7, 20]) {
    for (let active = 0; active < count; active++) {
      const slots = Array.from({ length: count }, (_, i) => carouselPosition(i, active, count));
      assert.equal(slots.filter(slot => slot === 'active').length, 1);
      assert.equal(slots.filter(slot => slot === 'previous').length, count > 1 ? 1 : 0);
      assert.equal(slots.filter(slot => slot === 'next').length, count > 2 ? 1 : 0);
      assert.equal(cycleIndex(cycleIndex(active, 1, count), -1, count), active);
    }
    assert.equal(cycleIndex(count - 1, 1, count), 0);
    assert.equal(cycleIndex(0, -1, count), count - 1);
  }
  assert.equal(cycleIndex(0, 1, 0), 0);
});

test('vertical and short touch gestures do not change products; horizontal swipes respect RTL', () => {
  for (const rtl of [true, false]) for (const [dx, dy] of [[0, 150], [12, 2], [80, 90], [-30, -10]]) {
    assert.equal(swipeStep(dx, dy, rtl), 0);
  }
  assert.equal(swipeStep(100, 8, true), 1);
  assert.equal(swipeStep(-100, 8, true), -1);
  assert.equal(swipeStep(100, 8, false), -1);
  assert.equal(swipeStep(-100, 8, false), 1);
});
