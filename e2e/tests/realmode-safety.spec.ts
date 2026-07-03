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
// an empty tree fails the check loudly rather than passing on an empty DOM. Boot
// failures report rich diagnostics (via bootOrDiagnose) rather than a bare timeout.

import { test, expect } from '@playwright/test';
import { DASHBOARD, KDS } from '../lib/constants';
import {
  bootOrDiagnose,
  collectPageErrors,
  collectAccessibleText,
} from '../lib/flutter';
import { DEMO_BANNER_PHRASES, KDS_MONEY_TOKENS, ARABIC_SCRIPT } from '../lib/tokens';

async function openReadable(page: import('@playwright/test').Page, url: string, name: string): Promise<string> {
  const collectors = collectPageErrors(page);
  const response = await page.goto(url, { waitUntil: 'domcontentloaded' });
  await bootOrDiagnose(page, name, {
    responseStatus: response ? response.status() : null,
    ...collectors,
  });
  return collectAccessibleText(page);
}

test.describe('real-mode UI safety (initial reachable state)', () => {
  test('Dashboard real mode shows no demo banner/pill', async ({ page }) => {
    const text = await openReadable(page, DASHBOARD.url, 'Dashboard');
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
    const text = await openReadable(page, DASHBOARD.url, 'Dashboard');
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
    const text = await openReadable(page, KDS.url, 'KDS');
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
