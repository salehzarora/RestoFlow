// RF-112A — real-mode UI safety smoke.
//
// Protects three visible-MVP invariants in each surface's INITIAL reachable
// state (real mode, before onboarding/pairing/sign-in):
//   • Dashboard shows no demo banner/pill (a demo build must not reach a real port).
//   • First launch is Arabic/RTL by default.
//   • The KDS never exposes money (kitchen is money-redacted — SECURITY T-003).
//
// All three read the Flutter accessibility tree (see lib/flutter.ts). Because the
// apps paint to canvas, the checks first REQUIRE that content was actually read —
// an empty tree fails the check loudly rather than passing on an empty DOM. If the
// semantics tree needs calibration on the first live run, that surfaces here as a
// clear red result, not a false green (deferred tuning tracked for RF-112B).

import { test, expect } from '@playwright/test';
import { DASHBOARD, KDS } from '../lib/constants';
import { waitForFlutterBoot, collectAccessibleText } from '../lib/flutter';
import { DEMO_BANNER_PHRASES, KDS_MONEY_TOKENS, ARABIC_SCRIPT } from '../lib/tokens';

test.describe('real-mode UI safety (initial reachable state)', () => {
  test('Dashboard real mode shows no demo banner/pill', async ({ page }) => {
    await page.goto(DASHBOARD.url, { waitUntil: 'domcontentloaded' });
    await waitForFlutterBoot(page);

    const text = await collectAccessibleText(page);
    expect(
      text.trim().length,
      'Could not read any Dashboard content via the accessibility tree, so the ' +
        'demo-absence check would be meaningless. Calibrate semantics (RF-112B) ' +
        'or confirm the app is in real mode. See e2e/README.md.',
    ).toBeGreaterThan(0);

    for (const phrase of DEMO_BANNER_PHRASES) {
      expect(
        text,
        `Dashboard real mode exposed a DEMO banner/pill phrase: "${phrase}". ` +
          `A real build must never show demo provenance UI.`,
      ).not.toContain(phrase);
    }
  });

  test('Dashboard first launch is Arabic/RTL by default', async ({ page }) => {
    await page.goto(DASHBOARD.url, { waitUntil: 'domcontentloaded' });
    await waitForFlutterBoot(page);

    const text = await collectAccessibleText(page);
    expect(
      text.trim().length,
      'Could not read any Dashboard content via the accessibility tree; the ' +
        'Arabic-first check needs the semantics tree. See e2e/README.md.',
    ).toBeGreaterThan(0);
    expect(
      ARABIC_SCRIPT.test(text),
      'Expected Arabic-script text on first launch (default locale is ar).',
    ).toBeTruthy();
  });

  test('KDS never exposes money symbols/totals', async ({ page }) => {
    await page.goto(KDS.url, { waitUntil: 'domcontentloaded' });
    await waitForFlutterBoot(page);

    const text = await collectAccessibleText(page);
    expect(
      text.trim().length,
      'Could not read any KDS content via the accessibility tree, so the ' +
        'money-redaction check would be meaningless. See e2e/README.md.',
    ).toBeGreaterThan(0);

    for (const token of KDS_MONEY_TOKENS) {
      expect(
        text,
        `KDS exposed a money token "${token}". The kitchen surface must stay ` +
          `money-free (SECURITY T-003).`,
      ).not.toContain(token);
    }
  });
});
