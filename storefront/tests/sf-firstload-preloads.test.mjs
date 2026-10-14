import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { measure } from '../scripts/measure-firstload.mjs';

test('first-load counts script preload/modulepreload once and excludes fonts/prefetch', () => {
  const parent = path.resolve(tmpdir());
  const dir = mkdtempSync(path.join(parent, 'bizbot-checkout-firstload-'));
  const names = ['index.html','eager.js','preload.js','module.js','later.js','font.woff2'];
  try {
    writeFileSync(path.join(dir,'index.html'), `<script src="/eager.js"></script>
      <link rel="preload" as="script" href="/eager.js">
      <link href="/preload.js" as="script" rel="preload">
      <link href="/module.js" rel="modulepreload">
      <link rel="prefetch" href="/later.js">
      <link rel="preload" as="font" href="/font.woff2">`);
    for (const [name, bytes] of [['eager.js',11],['preload.js',13],['module.js',17],['later.js',19],['font.woff2',23]]) writeFileSync(path.join(dir,name),'x'.repeat(bytes));
    const result = measure(dir).find((row)=>row.route==='/');
    assert.equal(result.firstLoadUncompressed,41);
    assert.equal(result.uniqueExternalScripts,3);
    assert.equal(result.speculativePrefetchBytes,19);
    assert.deepEqual(result.assets.map((row)=>row.url).sort(), ['/eager.js','module.js','preload.js'].map((s)=>s.startsWith('/')?s:`/${s}`).sort());
  } finally {
    assert.equal(path.dirname(path.resolve(dir)),parent);
    for (const name of names) unlinkSync(path.join(dir,name));
    rmdirSync(dir);
  }
});
