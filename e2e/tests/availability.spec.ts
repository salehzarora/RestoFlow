// RF-112A — app availability smoke.
//
// The renderer-INDEPENDENT backbone of the suite: each of the three surfaces is
// reachable on its fixed local port and boots the Flutter engine without a fatal
// error. These checks do not depend on the semantics tree, so they are robust and
// are the first thing to trust when triaging a failure. On a boot failure they
// report rich diagnostics (final URL, status, title, a safe body snippet, console
// + page errors) instead of a bare selector timeout — so a slow debug build or a
// config/help page is obvious at a glance.

import { test, expect } from '@playwright/test';
import { SURFACES } from '../lib/constants';
import { assertLocalOnly } from '../lib/guards';
import {
  bootOrDiagnose,
  collectPageErrors,
  FLUTTER_HOST_SELECTORS,
} from '../lib/flutter';

for (const surface of SURFACES) {
  test(`${surface.name} is reachable and boots without crashing (${surface.url})`, async ({
    page,
  }) => {
    assertLocalOnly(surface.url);

    const collectors = collectPageErrors(page);

    let response;
    try {
      response = await page.goto(surface.url, { waitUntil: 'domcontentloaded' });
    } catch (error) {
      // A refused connection throws here (not a null response). Turn it into an
      // actionable message rather than a raw ERR_CONNECTION_REFUSED.
      throw new Error(
        `Could not reach ${surface.name} at ${surface.url} (${String(error)}). ` +
          `Is it running in real mode? Start it with the matching _run_*_real.bat ` +
          `launcher and make sure the local Supabase stack is up (supabase start).`,
      );
    }
    expect(
      response,
      `No HTTP response from ${surface.url} — is ${surface.name} running?`,
    ).not.toBeNull();
    expect(
      response!.status(),
      `${surface.name} returned HTTP ${response!.status()} at ${surface.url}.`,
    ).toBeLessThan(400);

    // The engine attaching a view host proves the app booted (no white-screen).
    // On failure this throws a rich diagnostic while the page is still open.
    await bootOrDiagnose(page, surface.name, {
      responseStatus: response!.status(),
      ...collectors,
    });
    await expect(page.locator(FLUTTER_HOST_SELECTORS).first()).toBeAttached();

    // No uncaught Dart/JS exception surfaced to the page during boot.
    expect(
      collectors.pageErrors,
      `Uncaught page error(s) on ${surface.name}: ${collectors.pageErrors.join(' | ')}`,
    ).toEqual([]);
  });
}
