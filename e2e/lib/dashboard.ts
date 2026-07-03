// RF-112B — Dashboard interaction helpers.
//
// Driving a Flutter CanvasKit app from a browser: once the semantics tree is on
// (RF-112A), text fields are real <input> elements inside flt-semantics nodes and
// buttons are role="button" nodes, both reachable by ARIA role + accessible name
// (verified live). Typing is Flutter-reliable only via real key events, so fills
// focus the field, clear it, then send keystrokes (NOT .fill(), which sets the
// value property Flutter may ignore).

import { expect, type Page } from '@playwright/test';
import { DASHBOARD } from './constants';
import { assertLocalOnly } from './guards';
import {
  bootOrDiagnose,
  collectPageErrors,
  enableFlutterSemantics,
  readAccessibleText,
} from './flutter';

/** Open the Dashboard fresh, wait for boot, and turn on the semantics tree. */
export async function openDashboard(page: Page): Promise<void> {
  assertLocalOnly(DASHBOARD.url);
  const collectors = collectPageErrors(page);
  const response = await page.goto(DASHBOARD.url, {
    waitUntil: 'domcontentloaded',
  });
  await bootOrDiagnose(page, 'Dashboard', {
    responseStatus: response ? response.status() : null,
    ...collectors,
  });
  const ready = await enableFlutterSemantics(page);
  if (!ready) {
    throw new Error(
      'Dashboard semantics tree did not come up — cannot drive the UI. ' +
        'See e2e/README.md (semantics).',
    );
  }
}

/** Read the accessible text, polling until it is non-empty. */
export async function readText(page: Page): Promise<string> {
  let text = '';
  for (let attempt = 0; attempt < 12; attempt++) {
    text = await readAccessibleText(page);
    if (text.trim().length > 0) break;
    await page.waitForTimeout(250);
  }
  return text;
}

/** Wait until the accessible text contains `needle` — a screen-transition signal. */
export async function waitForText(
  page: Page,
  needle: string | RegExp,
  timeout = 25_000,
): Promise<void> {
  await expect
    .poll(async () => await readAccessibleText(page), {
      timeout,
      intervals: [300, 500, 800, 1200],
    })
    .toEqual(needle instanceof RegExp ? needle : expect.stringContaining(needle));
}

/** True if the accessible text currently contains `needle`. */
export async function hasText(page: Page, needle: string): Promise<boolean> {
  return (await readAccessibleText(page)).includes(needle);
}

/** Tap a button by its accessible name (exact by default for short labels). */
export async function tapButton(
  page: Page,
  name: string,
  opts: { exact?: boolean; which?: 'first' | 'last'; timeout?: number } = {},
): Promise<void> {
  const { exact = true, which = 'first', timeout = 15_000 } = opts;
  const matches = page.getByRole('button', { name, exact });
  const button = which === 'last' ? matches.last() : matches.first();
  await button.waitFor({ state: 'attached', timeout });
  await button.click();
}

/**
 * Tap a dynamic tile / list option / menu item by the text in its accessible
 * name. Flutter exposes this via the semantic node's `aria-label` (often a
 * concatenation, e.g. "<name> · N items"), NOT element textContent — so getByText
 * misses it while an aria-label substring match works.
 */
export async function tapText(
  page: Page,
  text: string,
  which: 'first' | 'last' = 'first',
  timeout = 15_000,
): Promise<void> {
  // Prefer the interactive (button-role) node so we hit the tile/option, not a
  // plain label child that happens to share the text.
  const byRole = page.getByRole('button', { name: text });
  if (await byRole.count()) {
    await (which === 'last' ? byRole.last() : byRole.first()).click();
    return;
  }
  const byLabel = page.locator(`[aria-label*=${JSON.stringify(text)}]`);
  const target = which === 'last' ? byLabel.last() : byLabel.first();
  await target.waitFor({ state: 'attached', timeout });
  await target.click();
}

/** Open a Flutter DropdownButtonFormField (by its current visible value) and pick an option. */
export async function selectDropdown(
  page: Page,
  currentValue: string,
  optionText: string,
  timeout = 15_000,
): Promise<void> {
  // The collapsed dropdown's aria-label carries its current value; tap to open.
  // Use the LAST match: the same value can appear on an already-created tile
  // behind the modal, while the dropdown lives in the dialog (later in the DOM).
  await tapText(page, currentValue, 'last', timeout);
  await page.waitForTimeout(500);
  // The overlay renders each option as a semantic node; the wanted option is the
  // newest match (last in the DOM).
  await tapText(page, optionText, 'last', timeout);
  await page.waitForTimeout(400);
}

/** Focus a field, clear it, then type — the Flutter-reliable fill. */
async function typeInto(
  page: Page,
  locator: ReturnType<Page['locator']>,
  text: string,
  timeout: number,
): Promise<void> {
  await locator.waitFor({ state: 'attached', timeout });
  await locator.click();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Delete');
  await page.keyboard.type(text, { delay: 12 });
}

/** Fill a text field found by its accessible name (label). */
export async function fillField(
  page: Page,
  name: string | RegExp,
  text: string,
  timeout = 15_000,
): Promise<void> {
  const box = page.getByRole('textbox', { name }).first();
  await typeInto(page, box, text, timeout);
}

/** Fill an obscured password/PIN field by index (0 = first on the form). */
export async function fillPasswordAt(
  page: Page,
  index: number,
  text: string,
  timeout = 15_000,
): Promise<void> {
  const pw = page.locator('input[type="password"]').nth(index);
  await typeInto(page, pw, text, timeout);
}

/** Fill the (single) obscured password field on the current form. */
export async function fillPassword(
  page: Page,
  text: string,
  timeout = 15_000,
): Promise<void> {
  await fillPasswordAt(page, 0, text, timeout);
}

/**
 * Navigate via a side-nav tile. Self-heals first: a still-open dialog or the
 * full-screen inline item editor covers the side-nav and drops it from the
 * accessibility tree, so if the target label is absent we close lingering
 * overlays (Escape closes a dialog; the editor closes via its Cancel button)
 * before waiting patiently for the tile to (re)appear on a cold DDC build.
 */
export async function tapNav(
  page: Page,
  label: string,
  timeout = 30_000,
): Promise<void> {
  // The side-nav tiles expose their name via text content, so match by ARIA
  // role + accessible name (NOT an aria-label attribute, which they don't carry).
  const button = page.getByRole('button', { name: label, exact: true }).first();
  try {
    await button.waitFor({ state: 'attached', timeout: 8_000 });
  } catch {
    // Not there yet — a lingering dialog / the full-screen inline editor may be
    // covering the side-nav. Close overlays, then wait patiently.
    for (let attempt = 0; attempt < 3 && !(await button.count()); attempt++) {
      await page.keyboard.press('Escape').catch(() => {});
      await page.waitForTimeout(300);
      // 'إلغاء' = Cancel (default Arabic locale) — closes the inline item editor.
      const cancel = page.getByRole('button', { name: 'إلغاء', exact: true });
      if (await cancel.count()) await cancel.last().click().catch(() => {});
      await page.waitForTimeout(500);
    }
    await button.waitFor({ state: 'attached', timeout });
  }
  await button.click();
  await page.waitForTimeout(700);
}
