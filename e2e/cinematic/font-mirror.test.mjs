import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, copyFileSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fallbackFonts, installDashboardFontMirror, localFontBootstrap } from './font-mirror.mjs';

const fixtures = resolve(dirname(fileURLToPath(import.meta.url)), 'fonts');
function tree() {
  const root = mkdtempSync(resolve(tmpdir(), 'cinematic-font-mirror-'));
  mkdirSync(resolve(root, 'apps/dashboard/build/web'), { recursive: true });
  mkdirSync(resolve(root, 'e2e/cinematic/fonts'), { recursive: true });
  for (const font of fallbackFonts) for (const file of [font.file, font.license]) copyFileSync(resolve(fixtures, file), resolve(root, 'e2e/cinematic/fonts', file));
  writeFileSync(resolve(root, 'apps/dashboard/build/web/flutter_bootstrap.js'), '/* generated loader */\n_flutter.loader.load();\n');
  return root;
}
test('only the default loader call gains a local font fallback URL', () => {
  const result = localFontBootstrap('/* original generated loader */\n_flutter.loader.load();\n');
  assert.ok(result.startsWith('/* original generated loader */\n'));
  assert.match(result, /fontFallbackBaseUrl: "\/cinematic-fonts\/"/);
  const withWorker = localFontBootstrap('_flutter.loader.load({serviceWorkerSettings: {serviceWorkerVersion: "1234"}});');
  assert.match(withWorker, /serviceWorkerVersion: "1234"/);
  assert.throws(() => localFontBootstrap('_flutter.loader.load({config:{unexpected:1}});'));
});
test('the pinned SDK generated service-worker deprecation comment is preserved', () => {
  const footer = `_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: "1997262592" /* Flutter's service worker is deprecated and will be removed in a future Flutter release. */
  }
});`;
  const result = localFontBootstrap(footer);
  assert.match(result, /fontFallbackBaseUrl: "\/cinematic-fonts\/"/);
  assert.ok(result.includes(footer.slice(footer.indexOf('serviceWorkerSettings:'), footer.lastIndexOf('}'))));
  assert.throws(() => localFontBootstrap(footer.replace('Flutter\'s service worker is deprecated', 'unreviewed comment')));
});
test('mirror serves byte-identical SDK fallback faces and their licenses', () => {
  const root = tree();
  try {
    const result = installDashboardFontMirror(root);
    assert.equal(result.status, 'PASS');
    assert.equal(result.fonts.length, 4);
    for (const font of fallbackFonts) {
      assert.deepEqual(readFileSync(resolve(root, 'apps/dashboard/build/web/cinematic-fonts', font.path)), readFileSync(resolve(fixtures, font.file)));
      assert.ok(readFileSync(resolve(root, 'apps/dashboard/build/web/cinematic-fonts', font.license)).length > 1000);
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test('modified fallback bytes are rejected before the generated bootstrap changes', () => {
  const root = tree();
  try {
    writeFileSync(resolve(root, 'e2e/cinematic/fonts/arabic.woff2'), 'untrusted bytes');
    assert.throws(() => installDashboardFontMirror(root), /Pinned Noto Sans Arabic bytes changed/);
    assert.equal(readFileSync(resolve(root, 'apps/dashboard/build/web/flutter_bootstrap.js'), 'utf8'), '/* generated loader */\n_flutter.loader.load();\n');
  } finally { rmSync(root, { recursive: true, force: true }); }
});
