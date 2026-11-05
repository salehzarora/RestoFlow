import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, mkdir, writeFile, chmod, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { resolve, join, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { verifyPrepared, revisionFor } from '../prepare.mjs';
import { MODEL } from '../../web/product-cutout/limits.mjs';

const repo = fileURLToPath(new URL('../../../../', import.meta.url));
const script = await readFile(join(repo, 'tools/vercel_build_web.sh'), 'utf8');
const config = JSON.parse(await readFile(join(repo, 'vercel.json'), 'utf8'));

test('prepared delivery is complete, content addressed and contains only shared processor assets', async () => {
  const manifest = await verifyPrepared();
  assert.equal(manifest.modelBytes, MODEL.bytes);
  assert.equal(manifest.nativeHeapMaxBytes, 536870912);
  assert.equal(manifest.files.length, 20);
  assert.equal(manifest.files.filter(file => /u2net-\d{2}\.bin/.test(file.file)).length, 11);
  assert.equal(manifest.files.filter(file => /LICENSE|NOTICES/.test(file.file)).length, 4);
  for (const file of manifest.files) assert.ok(file.bytes > 0);
  const changed = structuredClone(manifest.files);
  changed[0].sha256 = '0'.repeat(64);
  assert.notEqual(revisionFor(changed), manifest.revision, 'Changed asset bytes require a new shared URL');
  changed[0].bytes++;
  assert.notEqual(revisionFor(changed), revisionFor(manifest.files));
  assert.equal(manifest.files.some(file => /original|token|tenant|restaurant|\.jpe?g|\.png/i.test(file.file)), false);
  const worker = await readFile(new URL('../../web/product-cutout/worker.mjs', import.meta.url), 'utf8');
  assert.match(worker, /import \{ vendorPath \} from '\.\/assets\.mjs'/);
  assert.match(worker, /wasmPaths = vendorRoot.href/);
  assert.doesNotMatch(worker, /\.\/vendor\//);
});

test('only the processor namespace gets immutable caching, explicit MIME and no SPA fallback', () => {
  const rules = config.headers;
  assert.ok(rules.every(rule => rule.source.startsWith('/product-cutout/')));
  const immutable = rules.filter(rule => rule.headers.some(header => header.value.includes('immutable')));
  assert.equal(immutable.length, 1);
  assert.equal(immutable[0].source, '/product-cutout/assets/:revision([0-9a-f]{64})/:file');
  const revalidated = rules.find(rule => rule.headers.some(header => header.value === 'no-cache'));
  assert.equal(revalidated.source, '/product-cutout/((?!assets/).*)');
  assert.equal(new RegExp(`^${revalidated.source}$`).test('/product-cutout/assets/' + 'a'.repeat(64) + '/u2net-00.bin'), false);
  for (const [extension, mime] of [['mjs', 'application/javascript'], ['wasm', 'application/wasm'], ['bin', 'application/octet-stream'], ['json', 'application/json'], ['txt', 'text/plain']]) {
    const rule = rules.find(rule => rule.source === `/product-cutout/(.*).${extension}`);
    assert.ok(rule.headers.find(header => header.key === 'Content-Type').value.startsWith(mime));
  }
  const fallback = new RegExp(`^${config.rewrites.at(-1).source}$`);
  for (const path of ['/product-cutout', '/product-cutout/worker.mjs', '/product-cutout/assets/' + 'a'.repeat(64) + '/missing.bin']) assert.equal(fallback.test(path), false);
  for (const path of ['/', '/dashboard', '/products/123', '/product-cutout-help']) assert.equal(fallback.test(path), true);
  assert.deepEqual(config.rewrites.slice(0, -1).map(rule => rule.source), ['/pos/(.*)', '/pos', '/kds/(.*)', '/kds', '/kiosk/(.*)', '/kiosk']);
});

// Execute the actual builder with harmless tool doubles: the assertions concern
// the commands/compile flags actually invoked, including reused-checkout cleanup.
for (const [environment, setting, enabled] of [['production', 'true', true], ['preview', 'true', false], ['production', '', false]]) {
  test(`actual build: ${environment}, editor=${setting || 'unset'} confines processor to enabled Dashboard`, async () => {
    const temp = await mkdtemp(join(tmpdir(), 'bizbot-release-build-'));
    const log = join(temp, 'calls.log');
    try {
      for (const app of ['dashboard', 'pos', 'kds', 'kiosk']) await mkdir(join(temp, `apps/${app}`), { recursive: true });
      await mkdir(join(temp, 'apps/dashboard/cutout'));
      await mkdir(join(temp, 'flutter/bin'), { recursive: true });
      await mkdir(join(temp, 'stubs'));
      await writeFile(join(temp, 'build.sh'), script.replace(/\r\n/g, '\n'));
      const flutter = '#!/usr/bin/env bash\nset -e\nprintf "flutter:%s:%s\\n" "$PWD" "$*" >> "$CALL_LOG"\nmkdir -p build/web\nprintf "fixture" > build/web/index.html\n';
      await writeFile(join(temp, 'flutter/bin/flutter'), flutter);
      await chmod(join(temp, 'flutter/bin/flutter'), 0o755);
      for (const tool of ['npm', 'node']) {
        await writeFile(join(temp, 'stubs', tool), `#!/usr/bin/env bash\nprintf "${tool}:%s:%s\\n" "$PWD" "$*" >> "$CALL_LOG"\n`);
        await chmod(join(temp, 'stubs', tool), 0o755);
      }
      // Set PATH inside bash: Windows' case-insensitive Path environment otherwise
      // defeats a child PATH override. No credential-bearing environment is logged.
      const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
      const result = spawnSync(bash, ['-c', 'export PATH="$PWD/stubs:$PATH"; bash build.sh'], {
        cwd: temp, encoding: 'utf8', env: { ...process.env, CALL_LOG: log,
          VERCEL_ENV: environment, RESTOFLOW_STOREFRONT_EDITOR: setting,
          RESTOFLOW_SUPABASE_URL: 'https://fixture.invalid', RESTOFLOW_SUPABASE_ANON_KEY: 'public-test-placeholder' },
      });
      assert.equal(result.status, 0, result.stderr);
      const calls = (await readFile(log, 'utf8')).trim().split(/\r?\n/);
      const builds = calls.filter(line => line.startsWith('flutter:'));
      assert.equal(builds.length, 4);
      assert.ok(builds[0].includes(`--dart-define=SF_PRODUCT_CUTOUT_REVIEW=${enabled}`));
      assert.ok(builds[0].includes(`--dart-define=RESTOFLOW_STOREFRONT_EDITOR=${enabled}`));
      for (const line of builds.slice(1)) assert.doesNotMatch(line, /SF_PRODUCT_CUTOUT_REVIEW|RESTOFLOW_STOREFRONT_EDITOR/);
      const npm = calls.filter(line => line.startsWith('npm:')).map(line => line.split(':').at(-1));
      assert.deepEqual(npm, enabled ? ['ci --ignore-scripts', 'run prepare'] : []);
      assert.equal(calls.some(line => line.endsWith('prepare.mjs --clean')), !enabled);
      assert.ok(calls.at(-1).endsWith(`prepare.mjs --verify-build ${enabled}`));
      for (const app of ['pos', 'kds', 'kiosk']) assert.equal(await readFile(join(temp, `apps/dashboard/build/web/${app}/index.html`), 'utf8'), 'fixture');
    } finally {
      const target = resolve(temp);
      assert.ok(target.startsWith(resolve(tmpdir()) + sep) && target.includes('bizbot-release-build-'));
      await rm(target, { recursive: true, force: true });
    }
  });
}
