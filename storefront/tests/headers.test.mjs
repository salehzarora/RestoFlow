// The header/CSP policy is part of the committed contract, so it is asserted as
// a string. If the browser check later changes the CSP, this test changes with
// it and the no-mutation gate is re-run - a CSP decided after the gate that
// tests it is not a tested CSP.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const config = JSON.parse(readFileSync(path.join(ROOT, 'vercel.json'), 'utf8'));

const headersFor = (source) => {
  const rule = config.headers.find((h) => h.source === source);
  assert.ok(rule, `no header rule for ${source}`);
  return Object.fromEntries(rule.headers.map((h) => [h.key, h.value]));
};

test('every response carries the restrictive header set', () => {
  const h = headersFor('/(.*)');
  assert.equal(h['X-Content-Type-Options'], 'nosniff');
  assert.equal(h['X-Frame-Options'], 'DENY');
  assert.equal(h['Referrer-Policy'], 'strict-origin-when-cross-origin');
  assert.equal(h['Strict-Transport-Security'], 'max-age=63072000; includeSubDomains; preload');
  assert.equal(h['Permissions-Policy'], 'camera=(), microphone=(), geolocation=(), payment=()');
  // noindex is a crawler directive, NOT access control.
  assert.equal(h['X-Robots-Tag'], 'noindex, nofollow');
});

test('the CSP is restrictive where it can be, with only the recorded exceptions', () => {
  const csp = headersFor('/(.*)')['Content-Security-Policy'];
  const directives = Object.fromEntries(
    csp.split(';').map((d) => d.trim()).filter(Boolean).map((d) => {
      const [name, ...values] = d.split(/\s+/);
      return [name, values];
    }));

  assert.deepEqual(directives['default-src'], ["'self'"]);
  assert.deepEqual(directives['object-src'], ["'none'"]);
  assert.deepEqual(directives['frame-ancestors'], ["'none'"]);
  assert.deepEqual(directives['media-src'], ["'none'"]);
  assert.deepEqual(directives['base-uri'], ["'self'"]);
  assert.deepEqual(directives['form-action'], ["'self'"]);
  assert.deepEqual(directives['connect-src'], ["'self'"]);
  assert.deepEqual(directives['font-src'], ["'self'"]);
  assert.deepEqual(directives['img-src'], ["'self'", 'data:']);
  assert.ok('upgrade-insecure-requests' in directives);

  // D5 RESOLVED WITH EVIDENCE: the real exported output needs no style
  // exception. The plan proposed style-src 'self' 'unsafe-inline'; a Chromium
  // run against the actual output with the committed headers reported zero
  // style violations, and a deliberate style-src 'none' probe proved the
  // detector fails when it should. So the tighter policy ships.
  assert.deepEqual(directives['style-src'], ["'self'"]);

  // The single accepted script exception: Next emits inline hydration scripts
  // (self.__next_f.push) and a static export cannot mint a per-request nonce.
  // This is a bounded trade-off for a placeholder with no user content - NOT a
  // strict CSP, and it must be re-reviewed before tenant content or ordering.
  assert.deepEqual(directives['script-src'], ["'self'", "'unsafe-inline'"]);

  // No unsafe-eval anywhere in the served policy.
  assert.ok(!csp.includes("'unsafe-eval'"), 'unsafe-eval must never appear');
  // No wildcard or remote origin.
  assert.ok(!/\*|https?:\/\//.test(csp), 'no wildcard or remote origin in the CSP');
});

test('immutable caching applies only to fingerprinted static assets', () => {
  const h = headersFor('/_next/static/(.*)');
  assert.equal(h['Cache-Control'], 'public, max-age=31536000, immutable');
});
