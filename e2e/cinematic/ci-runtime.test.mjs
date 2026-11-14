import test from 'node:test';
import assert from 'node:assert/strict';
import { localStatus, assertHeightVideoEvidence, HEIGHT_VIDEO_FILE, acceptanceRunArgs, PUBLISHER_PROBE_TITLE } from './ci-runtime.mjs';
import { readFileSync } from 'node:fs';
const key = role => `test.${Buffer.from(JSON.stringify({ role })).toString('base64url')}.test`;

test('the short publisher reproduction runs once and never excludes an original case', () => {
  const probe = acceptanceRunArgs('probe'), full = acceptanceRunArgs('full');
  assert.deepEqual(probe, ['--no-install', 'playwright', 'test', '--config', 'cinematic/playwright.config.ts', '--grep', `(?:^|\\s)${PUBLISHER_PROBE_TITLE}$`, '--reporter=json']);
  assert.deepEqual(full, probe.map(value => value === '--grep' ? '--grep-invert' : value));
  for (const mode of [undefined, null, '', 'retry', 'skip']) assert.throws(() => acceptanceRunArgs(mode));
  const source = readFileSync(new URL('./dashboard.spec.ts', import.meta.url), 'utf8');
  const titles = [...source.matchAll(/^test\('([^']+)'/gm)].map(match => match[1]);
  const pattern = new RegExp(probe.at(-2));
  assert.equal(pattern.test(`dashboard.spec.ts ${PUBLISHER_PROBE_TITLE}`), true);
  assert.equal(pattern.test(`project suite dashboard.spec.ts ${PUBLISHER_PROBE_TITLE}`), true);
  assert.equal(pattern.test(`dashboard.spec.ts ${PUBLISHER_PROBE_TITLE} extra`), false);
  assert.deepEqual(titles.filter(title => pattern.test(title)), [PUBLISHER_PROBE_TITLE]);
  assert.deepEqual(titles.filter(title => !pattern.test(title)), [
    'real owner Dashboard → Storage → publisher → save → live menu; replacement, clear and appearance',
    'independent banner → actual Edge → save/reload → replace/clear preserves other media',
  ]);
});
test('only the local gateway and anon role enter application builds', () => {
  assert.equal(localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: key('anon') }).url, 'http://127.0.0.1:54321');
  for (const url of ['https://test.supabase.co', 'http://localhost:54321', 'http://127.0.0.1:54321.evil.test', 'http://127.0.0.1:54321/path']) {
    assert.throws(() => localStatus({ API_URL: url, ANON_KEY: key('anon') }));
  }
  for (const role of ['service_role', 'authenticated', undefined]) {
    assert.throws(() => localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: key(role) }));
  }
  assert.throws(() => localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: 'malformed' }));
});

test('only the exact bounded WebM evidence filename and header are admitted', () => {
  const header = Buffer.alloc(64); header.set(Buffer.from('1a45dfa3', 'hex')); header.write('webm', 16);
  assert.doesNotThrow(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, header));
  for (const name of ['other.webm', 'trace.zip', '../' + HEIGHT_VIDEO_FILE, HEIGHT_VIDEO_FILE.toUpperCase()]) assert.throws(() => assertHeightVideoEvidence(name, header));
  assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, Buffer.from('not a WebM')));
  assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, Buffer.alloc(8 * 1024 * 1024 + 1)));
  const invalid = Buffer.from(header); invalid[0] = 0; assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, invalid));
  const missingType = Buffer.from(header); missingType.fill(0, 16, 20); assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, missingType));
});
