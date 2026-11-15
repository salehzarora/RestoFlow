import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { readFileSync } from 'node:fs';
import { baselineBannerEvidence, completeResponsiveFixture, responsiveFixtureMismatch } from './banner-responsive.ts';

test('fixture restoration clears only its five omitted optional keys under the existing writer merge semantics', () => {
  const original = { appearance: { text_color: '#112233', menu_banner_media_id: 'published-banner',
    menu_background_media_id: 'independent-background', menu_banner_enabled: false, menu_banner_focal_x: 0 },
    announcement_text: 'retained announcement', hero: { title: 'retained hero' } };
  const untouched = structuredClone(original);
  const priorAppearance = { ...original.appearance, site_theme: 'light', menu_intro_visible: false, menu_banner_focal_y: 9 };
  // This is the precise failure: omitting an optional field does not clear the
  // existing SQL writer's previously validated appearance value on conflict.
  const omittedRestore = { ...priorAppearance, ...original.appearance };
  assert.equal(omittedRestore.menu_intro_visible, false);
  const completed = completeResponsiveFixture(original);
  assert.deepEqual(completed.materializedNullKeys, ['site_theme', 'menu_intro_visible', 'menu_banner_focal_y']);
  const explicitRestore = { ...priorAppearance, ...completed.document.appearance };
  assert.equal(explicitRestore.menu_intro_visible, null);
  assert.equal(explicitRestore.site_theme, null);
  assert.equal(explicitRestore.menu_banner_focal_y, null);
  assert.equal(explicitRestore.menu_banner_enabled, false);
  assert.equal(explicitRestore.menu_banner_focal_x, 0);
  assert.equal(explicitRestore.menu_banner_media_id, 'published-banner');
  assert.equal(explicitRestore.menu_background_media_id, 'independent-background');
  assert.deepEqual(original, untouched, 'The original readback object is never mutated');
  assert.notEqual(completed.document, original);
  assert.deepEqual(Object.keys(completed.document.appearance).filter(key => !Object.hasOwn(original.appearance, key)), completed.materializedNullKeys);
  assert.deepEqual(Object.keys(completed.document).sort(), Object.keys(original).sort());
  assert.deepEqual(completed.document.hero, original.hero);
});

test('fixture completion has exactly five explicit null defaults and preserves every already-present value', () => {
  const absent = completeResponsiveFixture({ appearance: { independent: 'unchanged' } });
  assert.deepEqual(absent.materializedNullKeys, ['site_theme', 'menu_intro_visible', 'menu_banner_enabled', 'menu_banner_focal_x', 'menu_banner_focal_y']);
  assert.deepEqual(absent.document.appearance, { independent: 'unchanged', site_theme: null, menu_intro_visible: null,
    menu_banner_enabled: null, menu_banner_focal_x: null, menu_banner_focal_y: null });
  const present = { appearance: { site_theme: null, menu_intro_visible: true, menu_banner_enabled: false,
    menu_banner_focal_x: 38, menu_banner_focal_y: 9, extra: { retained: true } } };
  assert.deepEqual(completeResponsiveFixture(present), { document: present, materializedNullKeys: [] });
});

test('fixture mismatch diagnostic reports only the five named values and an equality boolean for everything else', () => {
  const expected = { appearance: { menu_intro_visible: null, privateUnrelated: 'never include this value' }, secretOtherField: 'withheld' };
  const actual = { secretOtherField: 'withheld', appearance: { privateUnrelated: 'never include this value', menu_intro_visible: false } };
  const diagnostic = responsiveFixtureMismatch(expected, actual);
  assert.deepEqual(diagnostic.knownAppearance.menu_intro_visible, { expected: { present: true, value: null }, actual: { present: true, value: false } });
  assert.deepEqual(diagnostic.knownAppearance.site_theme, { expected: { present: false }, actual: { present: false } });
  assert.equal(diagnostic.allOtherDocumentFieldsEqual, true);
  assert.equal(Object.keys(diagnostic.knownAppearance).length, 5);
  assert.doesNotMatch(JSON.stringify(diagnostic), /withheld|never include|secretOtherField|privateUnrelated/);
  assert.equal(responsiveFixtureMismatch(expected, { ...actual, secretOtherField: 'different' }).allOtherDocumentFieldsEqual, false);
});

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
