// RF-112 local browser smoke — Flutter web helpers.
//
// The RestoFlow apps are Flutter web builds served with the default bootstrap
// (no renderer override), so they paint to a CanvasKit <canvas>: there is NO DOM
// text to read until Flutter's accessibility (semantics) tree is turned on. These
// helpers (1) wait for the engine to attach a view (proves the app booted without
// white-screening) and (2) activate + read the semantics tree so the real-mode
// content checks are meaningful rather than trivially-true against an empty DOM.

import type { Page } from '@playwright/test';

// DOM hosts the Flutter engine attaches once a view is mounted. Any one of these
// being present means the framework booted (as opposed to a blank/crashed page).
export const FLUTTER_HOST_SELECTORS =
  'flutter-view, flt-glass-pane, flt-scene-host, canvas';

/** Resolve once the Flutter engine has attached its view host, or throw on timeout. */
export async function waitForFlutterBoot(
  page: Page,
  timeout = 45_000,
): Promise<void> {
  await page.waitForSelector(FLUTTER_HOST_SELECTORS, {
    state: 'attached',
    timeout,
  });
}

// Flutter web injects an off-screen "Enable accessibility" placeholder button.
// Activating it builds the semantics DOM tree (flt-semantics nodes carrying
// aria-labels + text). This is the supported way to make a CanvasKit build's
// content observable to a browser driver.
const SEMANTICS_PLACEHOLDER =
  'flt-semantics-placeholder, [aria-label="Enable accessibility"]';
const SEMANTICS_TREE =
  'flt-semantics-host flt-semantics, flt-semantics, [id^="flt-semantic-node-"]';

/**
 * Turn on the Flutter semantics tree. Best-effort: some builds/timings expose no
 * placeholder or auto-populate. Returns true if a populated tree became available.
 */
export async function enableFlutterSemantics(
  page: Page,
  timeout = 20_000,
): Promise<boolean> {
  try {
    const placeholder = page.locator(SEMANTICS_PLACEHOLDER).first();
    await placeholder.waitFor({ state: 'attached', timeout: 5_000 });
    // The placeholder is intentionally off-screen; force past visibility checks.
    await placeholder.click({ force: true, timeout: 5_000 });
  } catch {
    // No placeholder / already enabled — fall through and probe for the tree.
  }
  try {
    await page.waitForSelector(SEMANTICS_TREE, {
      state: 'attached',
      timeout,
    });
    return true;
  } catch {
    return false;
  }
}

/** Aggregate the text Flutter exposes to assistive tech (aria-labels + text). */
export async function readAccessibleText(page: Page): Promise<string> {
  return page.evaluate(() => {
    const parts: string[] = [];
    const nodes = document.querySelectorAll(
      'flt-semantics, [id^="flt-semantic-node-"], [aria-label], [title], [role]',
    );
    nodes.forEach((node) => {
      const el = node as HTMLElement;
      const label = el.getAttribute('aria-label');
      if (label) parts.push(label);
      const title = el.getAttribute('title');
      if (title) parts.push(title);
      const text = el.textContent;
      if (text) parts.push(text);
    });
    // Fallback for any HTML-rendered text / input values.
    if (document.body && document.body.innerText) {
      parts.push(document.body.innerText);
    }
    return parts.join('\n');
  });
}

/**
 * Enable semantics and return the accessible text. Returns '' if the semantics
 * tree could not be brought up — callers treat that as "content unreadable" and
 * fail their check loudly rather than passing on an empty DOM.
 */
export async function collectAccessibleText(page: Page): Promise<string> {
  const ready = await enableFlutterSemantics(page);
  if (!ready) return '';
  // Let the tree finish populating after activation.
  await page.waitForTimeout(750);
  return readAccessibleText(page);
}
