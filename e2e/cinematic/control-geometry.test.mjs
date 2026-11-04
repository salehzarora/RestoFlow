import test from 'node:test';
import assert from 'node:assert/strict';
import { controlGeometry, visibleGeometry } from './control-geometry.mjs';
const viewport = { width: 1440, height: 1000 };

test('noninteractive status can be read without qualifying as a pointer-reachable control', () => {
  const status = { x: 900, y: 450, width: 170, height: 20 };
  assert.equal(visibleGeometry(status, viewport), true);
  assert.equal(controlGeometry(status, viewport, false).ready, false);
  assert.equal(visibleGeometry({ ...status, y: -100 }, viewport), false);
  assert.equal(visibleGeometry({ ...status, y: 930 }, viewport), false);
  assert.equal(visibleGeometry(null, viewport), false);
});
test('attached control clipped at the CI screenshot bottom requires a real downward wheel', () => {
  const result = controlGeometry({ x: 900, y: 983, width: 170, height: 40 }, viewport, true);
  assert.equal(result.ready, false);
  assert.ok(result.deltaY > 0);
});
test('a fully visible, pointer-hit control is ready without force click', () => {
  assert.equal(controlGeometry({ x: 900, y: 450, width: 170, height: 40 }, viewport, true).ready, true);
});
test('a control hidden behind another hit target is not ready', () => {
  assert.equal(controlGeometry({ x: 900, y: 450, width: 170, height: 40 }, viewport, false).ready, false);
});
test('a visible enabled control can be reached through its own Flutter input surface', () => {
  assert.equal(controlGeometry({ x: 991, y: 500, width: 173, height: 32 }, viewport, false, true).ready, true);
  assert.equal(controlGeometry({ x: 991, y: 983, width: 173, height: 32 }, viewport, false, true).ready, false);
});
test('missing or above-viewport controls need bounded scrolling', () => {
  assert.equal(controlGeometry(null, viewport, false).deltaY, 600);
  const above = controlGeometry({ x: 900, y: -500, width: 170, height: 40 }, viewport, false);
  assert.equal(above.ready, false);
  assert.equal(above.deltaY, -600);
});
