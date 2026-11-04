// CI-only resources for the ACTUAL Flutter 3.44.2 Dashboard. CanvasKit's
// text fallback is separate from --no-web-resources-cdn. Mirror its exact
// Roboto/Noto bytes locally; do not replace fonts or relax browser egress.
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

export const fallbackFonts = Object.freeze([
  { family: 'Roboto', file: 'roboto.woff2', path: 'roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2', sha256: '35b02ca266b79eb4996590f15817425a1ce9ebf48f84471843233ff614656bf2', license: 'Roboto-LICENSE.txt' },
  { family: 'Noto Sans Arabic', file: 'arabic.woff2', path: 'notosansarabic/v28/nwpxtLGrOAZMl5nJ_wfgRg3DrWFZWsnVBJ_sS6tlqHHFlhQ5l3sQWIHPqzCfyGyvvnCBFQLaig.woff2', sha256: '53251baf8845f9b2c35517a8d157b76aa80ab871fa9848ff2374c7f5f0e4ef97', license: 'notosansarabic-OFL.txt' },
  { family: 'Noto Sans Hebrew', file: 'hebrew.woff2', path: 'notosanshebrew/v46/or3HQ7v33eiDljA1IufXTtVf7V6RvEEdhQlk0LlGxCyaeNKYZC0sqk3xXGiXd4qtpyJltutR2g.woff2', sha256: 'e7fab91f096a81841659cd55b571bba3c095763760ff19e305b857306873cff2', license: 'notosanshebrew-OFL.txt' },
  { family: 'Noto Sans Symbols', file: 'symbols.woff2', path: 'notosanssymbols/v43/rP2up3q65FkAtHfwd-eIS2brbDN6gxP34F9jRRCe4W3gfQ8gb_VFRkzrbQ.woff2', sha256: '08202e258ea583254c036cff46a7077bb5af4f82c41a6c0a6775f6e44d99f1aa', license: 'notosanssymbols-OFL.txt' },
]);
const sha = bytes => createHash('sha256').update(bytes).digest('hex');

export function localFontBootstrap(source) {
  // Accept only the pinned SDK's default terminal loader call. Preserve the
  // generated loader/build config and standard service-worker setting, including
  // the exact deprecation comment emitted by this pinned SDK's WebTemplate.
  const call = /_flutter\.loader\.load\(\s*(\{\s*serviceWorkerSettings:\s*\{\s*serviceWorkerVersion:\s*(?:null|"[a-zA-Z0-9_-]+"|[0-9]+)(?:\s*\/\* Flutter's service worker is deprecated and will be removed in a future Flutter release\. \*\/)?\s*\}\s*\})?\s*\);\s*$/;
  const match = source.match(call);
  assert.ok(match, 'Unexpected Flutter bootstrap; refusing an unreviewed transform');
  const body = match[1] ? match[1].trim().slice(1, -1) : '';
  return source.slice(0, match.index) + `_flutter.loader.load({\n  config: { fontFallbackBaseUrl: "/cinematic-fonts/" },${body}\n});\n`;
}

export function installDashboardFontMirror(root) {
  const from = resolve(root, 'e2e/cinematic/fonts');
  const build = resolve(root, 'apps/dashboard/build/web');
  const bootstrapPath = resolve(build, 'flutter_bootstrap.js');
  const before = readFileSync(bootstrapPath, 'utf8');
  const after = localFontBootstrap(before);
  const fonts = fallbackFonts.map(font => {
    const bytes = readFileSync(resolve(from, font.file));
    assert.equal(sha(bytes), font.sha256, `Pinned ${font.family} bytes changed`);
    assert.equal(bytes.subarray(0, 4).toString(), 'wOF2');
    const license = readFileSync(resolve(from, font.license));
    assert.ok(license.length > 1000, 'Font license must travel with the test mirror');
    return { ...font, bytes };
  });
  for (const font of fonts) {
    const target = resolve(build, 'cinematic-fonts', font.path);
    mkdirSync(dirname(target), { recursive: true });
    writeFileSync(target, font.bytes);
    copyFileSync(resolve(from, font.license), resolve(build, 'cinematic-fonts', font.license));
  }
  writeFileSync(bootstrapPath, after);
  return { status: 'PASS', scope: 'CI-generated Dashboard bootstrap and static font assets only',
    flutter: '3.44.2', fontFallbackBaseUrl: '/cinematic-fonts/',
    bootstrapBefore: sha(before), bootstrapAfter: sha(after),
    fonts: fonts.map(({ family, sha256, bytes }) => ({ family, sha256, bytes: bytes.length })) };
}
