import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { LIMITS, MODEL, outputSize, inputTensor, alphaMatte } from '../../web/product-cutout/limits.mjs';
import { sniffSource } from '../../web/product-cutout/vendor/sniff.mjs';

test('predecode validation refuses oversized/truncated and unsupported originals', () => {
  assert.throws(() => sniffSource(new Uint8Array(LIMITS.maxInputBytes + 1), LIMITS), /input_too_large/);
  assert.throws(() => sniffSource(new Uint8Array([1, 2, 3]), LIMITS), /unsupported_format/);
  assert.throws(() => sniffSource(new Uint8Array(), LIMITS), /empty/);
});
test('geometry never stretches, crops or upscales', () => {
  assert.deepEqual(outputSize(800, 600), {width: 800, height: 600});
  assert.deepEqual(outputSize(4000, 2000), {width: 1600, height: 800});
});
test('actual model tensor normalization and matte reject invalid outputs', () => {
  const rgba = new Uint8ClampedArray(LIMITS.modelSide ** 2 * 4).fill(255);
  assert.ok(Math.abs(inputTensor(rgba)[0] - (1 - .485) / .229) < .00001);
  assert.throws(() => alphaMatte(new Float32Array(1)), /Invalid model output/);
  assert.throws(() => alphaMatte(new Float32Array(LIMITS.modelSide ** 2)), /No clear subject/);
  const logits = new Float32Array(LIMITS.modelSide ** 2); logits[1] = 1;
  const alpha = alphaMatte(logits); assert.equal(alpha[0], 0); assert.equal(alpha[4], 255);
});
test('model parts assemble to licensed pinned artifact and native heap is capped', async () => {
  const digest = createHash('sha256'); let bytes = 0;
  for (let i = 0; i < MODEL.parts.length; i++) {
    const part = await readFile(new URL(`../../web/product-cutout/vendor/u2net-${String(i).padStart(2,'0')}.bin`, import.meta.url));
    assert.ok(part.length <= MODEL.partBytes);
    assert.equal(createHash('sha256').update(part).digest('hex'), MODEL.parts[i]);
    digest.update(part); bytes += part.length;
  }
  assert.equal(bytes, MODEL.bytes); assert.equal(digest.digest('hex'), MODEL.sha256);
  const runtime = await readFile(new URL('../../web/product-cutout/vendor/ort-wasm-simd-threaded.mjs', import.meta.url), 'utf8');
  assert.ok(runtime.includes('initial:256,maximum:8192,shared:!0'));
  assert.ok(!runtime.includes('initial:256,maximum:65536,shared:!0'));
});
test('one worker only, owner-scoped cancel, timeout, retry and original retention', async () => {
  const workers = [];
  globalThis.Worker = class {
    constructor() { workers.push(this); this.terminated = false; }
    postMessage(message) { this.message = message; }
    terminate() { this.terminated = true; }
  };
  const { process, cancel } = await import('../../web/product-cutout/bridge.mjs');
  const original = new Uint8Array([1, 2, 3]);
  const pending = process(original, 'image/png', () => {}, 'first');
  await assert.rejects(process(original, 'image/png', () => {}, 'second'), /Another product/);
  cancel('second'); assert.equal(workers[0].terminated, false);
  cancel('first'); await assert.rejects(pending, /Cancelled/);
  assert.deepEqual([...original], [1,2,3]); assert.equal(workers[0].terminated, true);
  const retry = process(original, 'image/png', () => {}, 'first');
  workers[1].onmessage({data:{done:true,bytes:new ArrayBuffer(2)}});
  assert.equal((await retry).bytes.length, 2); assert.equal(workers[1].terminated, true);
  const previous = globalThis.setTimeout;
  globalThis.setTimeout = (callback) => previous(callback, 1);
  try { await assert.rejects(process(original,'image/png'), /timed out/); }
  finally { globalThis.setTimeout = previous; }
  assert.equal(workers[2].terminated, true);
});
