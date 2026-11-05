import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const { buildCinematicTheme } = await import('../src/theme/buildCinematicTheme.ts');
const { AA } = await import('../src/theme/buildTheme.ts');
const { contrast, mix } = await import('../src/theme/contrast.ts');
const { menuBackground } = await import('../src/ui/storefront/home/menuBackground.ts');

test('reference scene is explicit and no existing palette silently opts in', () => {
  for (const primary of ['#151515', '#151513', '#00ff00', '#ffff00', '#ffffff', '#13322a']) {
    const brand = Object.freeze({ primary, accent: '#ff00ff' });
    const legacy = buildCinematicTheme(brand);
    assert.equal(legacy.bg, primary);
    assert.deepEqual(buildCinematicTheme(brand, null), legacy);
    assert.deepEqual(buildCinematicTheme(brand, undefined), legacy);
    assert.deepEqual(buildCinematicTheme(brand, 'unknown'), legacy);
    assert.equal(Object.hasOwn(legacy, 'sceneGlass'), false);
    assert.deepEqual(brand, { primary, accent: '#ff00ff' });
  }
});

test('bright primary and accent never tint reference scene surfaces', () => {
  const neutral = buildCinematicTheme({ primary: '#151515', accent: '#e4ad83' }, 'reference_dark');
  for (const primary of ['#00ff00', '#ffff00', '#ffffff', '#ff00ff']) {
    for (const accent of ['#ff0000', '#00ff00', '#0000ff', '#ffff00']) {
      const reference = buildCinematicTheme({ primary, accent }, 'reference_dark');
      for (const key of ['bg', 'sf', 'sf2', 'hero', 'glass', 'glassDock', 'sceneGlass', 'sceneGlassSoft']) {
        assert.equal(reference[key], neutral[key], `${key} is scene presentation, not branding`);
      }
      assert.equal(reference.acc, accent);
      assert.equal(reference.cta, accent);
    }
  }
});

test('reference glass preserves photograph visibility and readable automatic navigation/footer copy', () => {
  const reference = buildCinematicTheme({ primary: '#00ff00', accent: '#ff00ff' }, 'reference_dark');
  for (const [key, base, opacity] of [['sceneGlass', '#151515', 0.76], ['sceneGlassSoft', '#252525', 0.8]]) {
    assert.ok(reference[key].endsWith(`,${opacity})`));
    // Worst photographic pixel is white. The glass must retain AA for
    // both normal navigation copy and the footer's secondary automatic copy.
    const lightestComposite = mix('#ffffff', base, opacity);
    for (const ink of ['tx', 'tx2']) assert.ok(contrast(reference[ink], lightestComposite) >= AA, `${key}/${ink}`);
  }
});

test('reference does not rewrite explicit colour or font choices', () => {
  const brand = Object.freeze({ primary: '#ff00ff', accent: '#aabbcc', text: '#123456', buttonText: '#654321', fontFamily: 'system' });
  const reference = buildCinematicTheme(brand, 'reference_dark');
  assert.equal(reference.tx, '#123456');
  assert.equal(reference.onacc, '#654321');
  assert.equal(reference.acc, '#aabbcc');
  assert.match(reference.font, /^system-ui/);
  assert.equal(brand.primary, '#ff00ff');
});

test('reference menu retains independent sources, valid zero/15/80 and default15 even for hero fallback', () => {
  for (const menuBackgroundImage of [null, '/menu.webp']) {
    for (const menuBackgroundDim of [0, 15, 80, null, undefined, -1, 81, 15.5, NaN]) {
      const tenant = Object.freeze({ heroImage: '/welcome.webp', menuBackgroundImage, menuBackgroundDim });
      const background = menuBackground(tenant, 'reference_dark');
      assert.equal(background.image, menuBackgroundImage ?? '/welcome.webp');
      assert.equal(background.kind, menuBackgroundImage ? 'custom' : 'legacy');
      assert.equal(background.dim, [0, 15, 80].includes(menuBackgroundDim) ? menuBackgroundDim : 15);
      assert.equal(tenant.heroImage, '/welcome.webp');
      if (!menuBackgroundImage) assert.equal(menuBackground(tenant).dim, null, 'legacy fallback unchanged');
    }
  }
  assert.deepEqual(menuBackground({ heroImage: null }, 'reference_dark'), { kind: 'legacy', image: null, dim: 15 });
});
