import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { baselineBannerEvidence } from './banner-responsive.ts';

test('responsive visual evidence pins the real prior CSS bytes and labels its replay limit', () => {
  const evidence = baselineBannerEvidence(fileURLToPath(new URL('../..', import.meta.url)));
  assert.equal(evidence.commit, '1e2ec4102d8d69b9f33d867e8b73a9cff97f3431');
  assert.equal(evidence.bytes, 41672);
  assert.equal(evidence.sha256, 'f1577b7819c9c8ed6907a25ce05e6485c094d4367c804958c9d43beb74003c62');
  assert.equal(evidence.kind, 'BASELINE_CSS_REPLAY_ON_CURRENT_RENDERER_NOT_A_MAIN_BUILD');
  assert.match(evidence.limit, /no claim.*separately built main/);
});

test('responsive helper does not relax the render-only iframe or provide a network/session transport', () => {
  const source = readFileSync(new URL('./banner-responsive.ts', import.meta.url), 'utf8');
  assert.doesNotMatch(source, /(?:removeAttribute|setAttribute)\(['"](?:sandbox|http-equiv)['"]|bypassCSP|addStyleTag|fetch\(|authorization|access_token|storageState/);
  assert.match(source, /Math\.min\(\.\.\.ratios\).*Math\.max\(\.\.\.ratios\)/);
  assert.doesNotMatch(source, /if \(el\.ownerDocument\.documentElement\.clientWidth > 650\)/, 'Phone replay must not be a no-op');
  assert.match(source, /'object-fit': 'cover'/);
  assert.match(source, /node\.style\.setProperty\(property, original\.value, original\.priority\)/);
  assert.doesNotMatch(source, /setAttribute\('style'/, 'CSSOM restoration must honor the real style-src policy');
});
