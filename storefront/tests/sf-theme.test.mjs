// Theme derivation: golden vectors against the approved handoff, plus the
// contrast floors the design promises. The handoff says "Implement the
// derivation, not the hex codes" — so these tests feed the demo tenant's INPUTS
// and assert the published TOKENS.json OUTPUTS fall out of the rules.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const { buildTheme, AA, AA_LARGE } = await import('../src/theme/buildTheme.ts');
const { contrast, mix, tone, inkOn, walk, isHex } = await import('../src/theme/contrast.ts');

// The demo tenant's INPUTS, exactly as TOKENS.json -> presets records them.
const DARK_IN = { primary: '#123027', accent: '#FF8A2A' };
const LIGHT_IN = { primary: '#123027', accent: '#C2410C' };

// Hex is case-insensitive by definition; the handoff's JSON mixes cases because
// some values pass through untouched and others are computed. Compare meaning.
const sameColour = (a, b) => assert.equal(String(a).toLowerCase(), String(b).toLowerCase());

const dark = buildTheme('dark', DARK_IN);
const light = buildTheme('light', LIGHT_IN);

test('dark surfaces reproduce the published Maps Burger vectors', () => {
  // TOKENS.json -> color.dark
  sameColour(dark.bg, '#101816');
  sameColour(dark.sf, '#17231f');
  sameColour(dark.sf2, '#1f302a');
  sameColour(dark.hero, '#123027');
  sameColour(dark.acc, '#FF8A2A');
  sameColour(dark.onhero, '#FFFFFF');
  sameColour(dark.onacc, '#0B1512');
  sameColour(dark.acct, '#ff8a2a');
  sameColour(dark.onDock2, '#c0cbc6');
  sameColour(dark.glassLine, 'rgba(255,255,255,.14)');
});

test('light surfaces reproduce the published vectors', () => {
  sameColour(light.bg, '#F4F6F5');
  sameColour(light.sf, '#FFFFFF');
  sameColour(light.sf2, '#EEF2F0');
  sameColour(light.acc, '#C2410C');
  sameColour(light.onacc, '#FFFFFF');
  sameColour(light.acct, '#c2410c');
  sameColour(light.onDock2, '#4B5563');
});

test('semantic colours are fixed per preset and never derive from the brand', () => {
  const other = buildTheme('dark', { primary: '#3b0764', accent: '#22d3ee' });
  for (const key of ['ok', 'okbg', 'warn', 'warnbg', 'bad', 'badbg', 'info', 'infobg']) {
    assert.equal(other[key], dark[key], `${key} must not move with the brand`);
  }
});

test('accent-as-text reaches AA on the card surface for both presets', () => {
  assert.ok(contrast(dark.acct, dark.sf) >= AA, `dark acct ${contrast(dark.acct, dark.sf)}`);
  assert.ok(contrast(light.acct, light.sf) >= AA, `light acct ${contrast(light.acct, light.sf)}`);
});

test('PX-4 focus ring clears 3:1 on EVERY surface it is drawn on', () => {
  for (const theme of [dark, light]) {
    for (const surface of [theme.bg, theme.sf, theme.sf2, theme.accs]) {
      assert.ok(
        contrast(theme.ring, surface) >= AA_LARGE,
        `ring ${theme.ring} on ${surface} = ${contrast(theme.ring, surface).toFixed(2)}`,
      );
    }
  }
});

test('PX-3 dark danger text clears AA on the danger bed', () => {
  // The uncorrected value is BELOW AA — assert that, so the correction is not
  // silently testing a case that never needed fixing.
  assert.ok(contrast('#F87171', '#7F1D1D') < AA, 'baseline was expected to fail AA');
  assert.ok(
    contrast(dark.badText, dark.badbg) >= AA,
    `corrected ${dark.badText} on ${dark.badbg} = ${contrast(dark.badText, dark.badbg).toFixed(2)}`,
  );
});

test('PX-3 danger-button ink is derived with inkOn, not assumed white', () => {
  assert.equal(dark.onBad, inkOn(dark.bad));
  assert.equal(light.onBad, inkOn(light.bad));
  assert.ok(contrast(dark.onBad, dark.bad) >= AA);
  assert.ok(contrast(light.onBad, light.bad) >= AA);
});

test('PX-3 light accent on the selection bed clears AA', () => {
  assert.ok(contrast('#C2410C', light.accs) < AA, 'baseline was expected to fail AA');
  assert.ok(
    contrast(light.accOnSelection, light.accs) >= AA,
    `corrected = ${contrast(light.accOnSelection, light.accs).toFixed(2)}`,
  );
});

test('PX-4 CTA ink clears AA against the LIGHTEST gradient stop', () => {
  for (const theme of [dark, light]) {
    const stops = /linear-gradient\(135deg, (#[0-9a-f]{6}) 0%, (#[0-9A-Fa-f]{6}) 52%, (#[0-9a-f]{6}) 100%\)/.exec(
      theme.cta,
    );
    assert.ok(stops, `cta gradient shape: ${theme.cta}`);
    for (const stop of [stops[1], stops[2], stops[3]]) {
      assert.ok(
        contrast(theme.onacc, stop) >= AA,
        `onacc ${theme.onacc} on stop ${stop} = ${contrast(theme.onacc, stop).toFixed(2)}`,
      );
    }
  }
});

test('hero ink reaches AA on the hero for every supported tenant primary', () => {
  for (const primary of ['#123027', '#13322a', '#1f2937', '#3b0764', '#7f1d1d']) {
    const theme = buildTheme('dark', { primary, accent: '#FF8A2A' });
    assert.ok(
      contrast(theme.onhero, theme.hero) >= AA,
      `${primary}: ${contrast(theme.onhero, theme.hero).toFixed(2)}`,
    );
  }
});

test('colour maths matches the handoff definitions', () => {
  sameColour(mix('#000000', '#FFFFFF', 0.5), '#808080');
  assert.equal(contrast('#FFFFFF', '#000000').toFixed(2), '21.00');
  assert.equal(contrast('#FFFFFF', '#FFFFFF'), 1);
  sameColour(inkOn('#FFFFFF'), '#0B1512');
  sameColour(inkOn('#000000'), '#FFFFFF');
  // tone() caps saturation at 0.32 and forces the role's lightness.
  assert.ok(isHex(tone('#FF0000', 0.09)));
  // walk() stops as soon as the floor is met, and never overshoots to the end
  // colour when the input already passes.
  sameColour(walk('#FFFFFF', '#000000', 4.5, '#FFFFFF'), '#FFFFFF');
});

test('every emitted token is a non-empty string and no token is undefined', () => {
  for (const theme of [dark, light]) {
    for (const [key, value] of Object.entries(theme)) {
      assert.equal(typeof value, 'string', `${key} must be a string`);
      assert.ok(value.trim().length > 0, `${key} is empty`);
      assert.ok(!value.includes('undefined'), `${key} contains "undefined": ${value}`);
      assert.ok(!value.includes('NaN'), `${key} contains NaN: ${value}`);
    }
  }
});
