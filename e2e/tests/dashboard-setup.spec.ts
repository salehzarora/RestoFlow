// RF-112B — Dashboard setup browser smoke.
//
// Drives the real Dashboard (localhost:57026) through the owner setup that
// prepares a branch for POS/KDS: sign up → onboard → menu category + item →
// (best-effort) modifier → table → POS + KDS devices with pairing codes → cashier
// + kitchen staff with PINs → assert the Setup Center reflects real progress.
//
// The flow itself lives in lib/setup_flow.ts (shared with the RF-112C POS/KDS
// smoke). It creates UNIQUE data each run (timestamped) and needs NO db reset;
// each test gets a fresh Playwright context (isolated storage → signed out). It
// targets elements by ARIA role + accessible name from the Arabic (default) l10n
// — no Flutter app changes. POS/KDS deep flow is RF-112C, intentionally NOT here.

import { test } from '@playwright/test';
import { createBranchSetup } from '../lib/setup_flow';

// A wide viewport so the shell's side-nav (with always-visible labels) is used.
test.use({ viewport: { width: 1600, height: 1200 } });

test('Dashboard setup: prepare a fresh branch for POS/KDS', async ({ page }) => {
  test.slow(); // long real-mode flow with several DDC debug screen loads
  const setup = await createBranchSetup(page);
  // eslint-disable-next-line no-console
  console.log(
    `RF-112B setup OK — modifier ${setup.modifierAttached ? 'attached' : 'skipped'}` +
      (setup.notes.length ? ` | ${setup.notes.join(' | ')}` : ''),
  );
});
