import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
const { carouselDragPosition, carouselOrbit, carouselPosition, cycleIndex, swipeIntent, swipeStep } = await import('../src/ui/storefront/home/carousel.ts');

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

test('intent preserves vertical scroll and ignores touch jitter and ambiguous diagonals', () => {
  for (const [dx, dy] of [[0, 0], [12, 0], [-8, 10], [20, 20], [25, 20]]) {
    assert.equal(swipeIntent(dx, dy), null);
  }
  for (const sign of [-1, 1]) {
    assert.equal(swipeIntent(sign * 13, 0), 'horizontal');
    assert.equal(swipeIntent(sign * 80, 30), 'horizontal');
    assert.equal(swipeIntent(0, sign * 13), 'vertical');
    assert.equal(swipeIntent(30, sign * 80), 'vertical');
  }
});

test('drag tracks the finger continuously before release and brings the correct real neighbour to centre in RTL and LTR', () => {
  const orbit = carouselOrbit(390);
  const close = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} != ${b}`);
  for (const count of [2, 6]) for (const rtl of [false, true]) for (const step of [-1, 1]) {
    const dx = (rtl ? 1 : -1) * step * orbit;
    const mid = carouselDragPosition(0, 0, count, dx / 2, orbit, rtl);
    close(mid.x, dx / 2);
    close(mid.scale, (1 + .57) / 2);
    close(mid.opacity, (1 + .85) / 2);
    const incoming = carouselDragPosition(cycleIndex(0, step, count), 0, count, dx, orbit, rtl);
    close(incoming.x, 0);
    close(incoming.scale, 1);
    close(incoming.opacity, 1);
    assert.equal(incoming.visible, true);
    assert.equal(swipeStep(dx, 0, rtl), step);
  }
});

test('drag is bounded to one selection and keeps single-neighbour geometry and hidden slides finite', () => {
  assert.equal(carouselOrbit(320), 99.2);
  assert.equal(carouselOrbit(390), 120.9);
  assert.equal(carouselOrbit(1440), 230);
  const orbit = carouselOrbit(390);
  assert.equal(carouselDragPosition(1, 0, 2, 0, orbit, false).x, -orbit);
  for (const count of [2, 3, 7, 20]) for (const rtl of [false, true]) {
    for (const dx of [-orbit * 10, -orbit, -orbit * .37, 0, orbit * .13, orbit / 2, orbit * .83, orbit, orbit * 10]) {
      for (let index = 0; index < count; index++) {
        const frame = carouselDragPosition(index, 0, count, dx, orbit, rtl);
        assert.ok(Number.isFinite(frame.x) && Math.abs(frame.x) <= orbit);
        assert.ok(frame.scale >= .34 && frame.scale <= 1);
        assert.ok(frame.opacity >= 0 && frame.opacity <= 1);
        assert.ok(Number.isInteger(frame.zIndex) && frame.zIndex >= 0 && frame.zIndex <= 3);
      }
    }
    assert.deepEqual(carouselDragPosition(0, 0, count, orbit, orbit, rtl), carouselDragPosition(0, 0, count, orbit * 10, orbit, rtl));
  }
});
