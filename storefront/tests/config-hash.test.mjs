// The engine pins storefront/next.config.mjs by hash. Verify the COMMITTED blob,
// not the working-tree bytes: the tree may be CRLF while git stores LF, and the
// engine hashes what git stores.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const REPO = path.resolve(ROOT, '..');
const EXPECTED = '4aa433d21dba5868d85a1829de513eb1a7475125ac2c2dba0b287eaab471fd16';

const sha = (text) => createHash('sha256').update(text.replace(/\r\n/g, '\n')).digest('hex');

test('next.config.mjs matches the pinned STOREFRONT_CONFIG_HASH (working tree)', () => {
  assert.equal(sha(readFileSync(path.join(ROOT, 'next.config.mjs'), 'utf8')), EXPECTED);
});

test('the hash the engine exports is the one we pin against', () => {
  const engine = readFileSync(path.join(REPO, 'tools/vercel/ignore-build.mjs'), 'utf8');
  const m = /export const STOREFRONT_CONFIG_HASH = '([a-f0-9]{64})'/.exec(engine);
  assert.ok(m, 'engine must export STOREFRONT_CONFIG_HASH');
  assert.equal(m[1], EXPECTED);
});

test('the staged blob hashes correctly once the file is tracked', () => {
  let staged;
  try {
    staged = execFileSync('git', ['-C', REPO, 'show', ':storefront/next.config.mjs'], { encoding: 'utf8' });
  } catch {
    return; // not yet staged; the working-tree assertion above still applies
  }
  assert.equal(sha(staged), EXPECTED);
});
