// BIZBOT-STOREFRONT-VISUAL-PARITY-001: offline codec evidence only, not publication.
import assert from 'node:assert/strict';
import { readFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { deriver } from '../../../../supabase/functions/storefront-media-publish/test/engine.mjs';

const source = await readFile(new URL('../../../../e2e/cinematic/fixtures/product-cutout/burger-highres.jpg', import.meta.url));
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
assert.equal(source.length, 4989591);
assert.equal(hash(source), '81f08a1cb0256293b862db2a661b76f9f9a54067ae5651469a454f7899b50bb3');
const engine = await deriver(); // Verifies all five vendored WASM hashes and c4 golden self-test.
const variants = [];
for (const size of [480, 960]) {
  let output;
  for (let rung = 0; rung < 4; rung++) {
    output = await engine.derive(new Uint8Array(source), { source: 'menu-images', variant: `w${size}`, rung });
    if (output.status === 'derived') break;
  }
  assert.equal(output.status, 'derived');
  assert.deepEqual([output.source.width, output.source.height], [2816, 2112]);
  assert.deepEqual([output.width, output.height], [size, size * .75]);
  const file = `original-c4-w${size}.webp`;
  await writeFile(new URL(file, import.meta.url), output.bytes);
  variants.push({ file, width: output.width, height: output.height, bytes: output.byteLength,
    sha256: hash(output.bytes), quality: output.quality, rung: output.rung, hasAlpha: output.hasAlpha });
}
const receipt = {
  status: 'PASS', scope: 'Offline actual pinned c4 codec derivation; no Storage, service publication or browser rendering claim',
  recipe: 'storefront-media-c4', source: { file: '../../../../e2e/cinematic/fixtures/product-cutout/burger-highres.jpg',
    width: 2816, height: 2112, pixels: 5947392, bytes: source.length, sha256: hash(source) },
  variants,
};
await writeFile(new URL('offline-original-receipt.json', import.meta.url), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
