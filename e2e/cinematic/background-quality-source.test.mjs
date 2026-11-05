import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { deriver } from '../../supabase/functions/storefront-media-publish/test/engine.mjs';

test('the Dashboard background fixture fits the private bucket and reproduces both real publication goldens', async () => {
  const bytes = await readFile(new URL('./fixtures/background-quality/background-2816.jpg', import.meta.url));
  assert.equal(bytes.length, 1463022);
  assert.equal(createHash('sha256').update(bytes).digest('hex'), '3e6b8197d0f1e17da8a86b5f0db95330394e11bc30c34b16ca0a076959346d54');
  const engine = await deriver();
  const base = await engine.derive(bytes, { variant:'w960', source:'restaurant-logos', rung:0 });
  const high = await engine.deriveBackground(bytes, { source:'restaurant-logos', rung:0 });
  assert.deepEqual([base.source.width, base.source.height, high.source.width, high.source.height], [2816,2112,2816,2112]);
  assert.deepEqual([base.status, base.width, base.height, base.byteLength, base.sha256],
    ['derived',960,720,111406,'211a00daf75bb8f868cec1c95aaa1e4c5e7d1d9aba8b46e6867d2753a8ff2ed3']);
  assert.deepEqual([high.status, high.width, high.height, high.byteLength, high.sha256],
    ['derived',2560,1920,459258,'c0120cc575b08c4227d3c060ac78af28ee4ec7085ec4fd85f510778933fcd85f']);
});
