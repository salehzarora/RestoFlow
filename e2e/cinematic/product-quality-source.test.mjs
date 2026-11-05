import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { sniffSource } from '../../supabase/functions/storefront-media-publish/lib/sniff.mjs';
import { LIMITS } from '../../apps/dashboard/web/product-cutout/limits.mjs';

test('high-resolution acceptance input is the licensed camera original within unchanged input limits', () => {
  const bytes = readFileSync(new URL('./fixtures/product-cutout/burger-highres.jpg', import.meta.url));
  const provenance = JSON.parse(readFileSync(new URL('../../docs/visual-references/PR380-quality-review/highres/provenance.json', import.meta.url)));
  assert.equal(createHash('sha256').update(bytes).digest('hex'), provenance.originalSha256);
  assert.equal(bytes.length, provenance.originalBytes);
  const source = sniffSource(bytes, LIMITS);
  assert.equal(source.type, 'jpeg');
  assert.deepEqual([source.width, source.height], [2816, 2112]);
  assert.ok(Math.min(source.width, source.height) > 960, 'Both source dimensions exceed the maximum public variant');
  assert.ok(bytes.length <= LIMITS.maxInputBytes);
  assert.ok(source.width * source.height <= LIMITS.maxPixels);
  assert.equal(provenance.license, 'CC0 1.0 Universal');
});
