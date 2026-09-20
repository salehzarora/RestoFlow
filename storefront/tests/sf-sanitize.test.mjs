// Tenant input sanitation. The supported colour domain is deliberately narrow
// (approved decision 7): a primary that cannot carry white ink at AA on the
// hero AND on the hero glass is REJECTED, not rendered at a failing ratio.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const s = await import('../src/theme/sanitize.ts');
const { contrast } = await import('../src/theme/contrast.ts');

test('the demo tenant primary is inside the supported domain', () => {
  const v = s.inspectPrimary('#123027');
  assert.equal(v.supported, true);
  assert.ok(v.heroRatio >= 4.5);
  assert.ok(v.glassRatio >= 4.5);
});

test('a light primary is REJECTED, with a reason, and falls back to neutral', () => {
  for (const tooLight of ['#FFFFFF', '#F4F6F5', '#FBBF24', '#43E3AC', '#93C5FD']) {
    const v = s.inspectPrimary(tooLight);
    assert.equal(v.supported, false, `${tooLight} must be rejected`);
    assert.ok(typeof v.reason === 'string' && v.reason.length > 0);
    assert.equal(s.sanitizePrimary(tooLight), s.NEUTRAL_PRIMARY);
  }
});

test('the glass composite is checked, not just the flat hero', () => {
  // A primary can pass flat-on-hero and still fail once composited at 74% over
  // a light photo. That is exactly the case the second check exists for.
  const marginal = '#4a5f57';
  const flat = contrast('#FFFFFF', marginal);
  const glass = contrast('#FFFFFF', s.glassOverWhite(marginal));
  assert.ok(glass < flat, 'glass composite must be lighter, hence lower contrast');
  const v = s.inspectPrimary(marginal);
  if (flat >= 4.5 && glass < 4.5) {
    assert.equal(v.supported, false);
    assert.equal(v.reason, 'white ink below AA on hero glass');
  }
});

test('the BIZBOT-neutral fallback is itself inside the supported domain', () => {
  assert.equal(s.inspectPrimary(s.NEUTRAL_PRIMARY).supported, true);
});

test('non-colours are rejected rather than interpolated into CSS', () => {
  for (const bad of ['', 'red', 'rgb(1,2,3)', '#12', '#1234567', 'javascript:alert(1)',
    'var(--x)', '#12302;}body{display:none', null, undefined, 123]) {
    assert.equal(s.sanitizePrimary(bad), s.NEUTRAL_PRIMARY, `rejected: ${String(bad)}`);
  }
});

test('accent falls back per preset but any real hex is accepted', () => {
  assert.equal(s.sanitizeAccent('not-a-colour', 'dark'), s.NEUTRAL_ACCENT_DARK);
  assert.equal(s.sanitizeAccent(null, 'light'), s.NEUTRAL_ACCENT_LIGHT);
  assert.equal(s.sanitizeAccent('#FF8A2A', 'dark'), '#ff8a2a');
  assert.equal(s.sanitizeAccent('#abc', 'dark'), '#aabbcc');
});

test('slugs accept only a conservative shape', () => {
  for (const ok of ['maps-burger', 'a', 'a1', 'demo-cafe-2']) assert.ok(s.isValidSlug(ok), ok);
  for (const bad of ['', '-lead', 'trail-', 'Upper', 'has space', 'has/slash', 'has.dot',
    '..', 'a'.repeat(64), 'sl%2Fash', 'ünïcode']) {
    assert.equal(s.isValidSlug(bad), false, `must reject: ${bad}`);
  }
});

test('request refs accept only the documented shape', () => {
  assert.ok(s.isValidRef('MB-2487'));
  for (const bad of ['mb-2487', 'MB2487', 'MB-', '-2487', 'MB-2487-X'.repeat(4), '../etc']) {
    assert.equal(s.isValidRef(bad), false, `must reject: ${bad}`);
  }
});

test('tenant text is stripped of control characters and bidi overrides', () => {
  // Built with fromCharCode so this FILE stays pure ASCII: writing the literal
  // characters here is what made it binary to git the first time round.
  const ch = (cp) => String.fromCharCode(cp);
  assert.equal(s.sanitizeText('Maps Burger', 40), 'Maps Burger');
  // A bidi override can reverse how a mixed-direction line READS without
  // changing the characters, so it must not survive into the document.
  assert.equal(s.sanitizeText('a' + ch(0x202e) + 'b', 40), 'ab');
  assert.equal(s.sanitizeText('a' + ch(0x2066) + 'b' + ch(0x2069) + 'c', 40), 'abc');
  assert.equal(s.sanitizeText('a' + ch(0x00) + 'b' + ch(0x1f) + 'c', 40), 'abc');
  assert.equal(s.sanitizeText('a' + ch(0x7f) + 'b', 40), 'ab');
  assert.equal(s.sanitizeText('  padded  ', 40), 'padded');
  assert.equal(s.sanitizeText('x'.repeat(50), 10).length, 10);
  assert.equal(s.sanitizeText(null, 10), '');
  // Tabs and newlines are legitimate in a tagline and are NOT stripped.
  assert.equal(s.sanitizeText('a' + ch(0x0a) + 'b', 10), 'a' + ch(0x0a) + 'b');
  assert.equal(s.sanitizeText('a' + ch(0x09) + 'b', 10), 'a' + ch(0x09) + 'b');
});
