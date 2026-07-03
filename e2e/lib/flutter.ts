// RF-112 local browser smoke — Flutter web helpers.
//
// The RestoFlow apps are Flutter web builds. Locally they are served by
// `flutter run` in DEBUG mode, which uses the Dart Development Compiler (DDC):
// the page loads ~1000 module scripts via ddc_module_loader.js before main()
// runs and the engine attaches a view. That first boot is SLOW (tens of seconds,
// slower still if several apps boot at once), so the suite runs serially
// (workers=1) and the boot wait is generous + configurable.
//
// Rendering is CanvasKit, so there is NO DOM text until Flutter's accessibility
// (semantics) tree is turned on. These helpers (1) wait for the engine to attach
// a view host (proves the app booted without white-screening), with actionable
// diagnostics on failure, and (2) activate + read the semantics tree so the
// real-mode content checks are meaningful rather than trivially-true.

import type { Page } from '@playwright/test';

// DOM hosts the Flutter engine attaches once it has initialised / mounted a view.
// Any one of these being present means the framework booted (vs a blank/crashed
// page). `flutter-view` lives in the light DOM; Playwright's CSS engine also
// pierces open shadow roots, so `flt-glass-pane` is matched even when it is
// nested inside the view's shadow root in recent Flutter.
export const FLUTTER_HOST_SELECTORS =
  'flutter-view, flt-glass-pane, flt-scene-host, flt-semantics-placeholder, canvas';

/** Boot-wait budget (ms). Override with RF_E2E_BOOT_TIMEOUT_MS for a slow machine. */
export function bootTimeoutMs(): number {
  const raw = Number(process.env.RF_E2E_BOOT_TIMEOUT_MS);
  return Number.isFinite(raw) && raw > 0 ? raw : 90_000;
}

/** Resolve once the Flutter engine has attached its view host, or throw on timeout. */
export async function waitForFlutterBoot(
  page: Page,
  timeout = bootTimeoutMs(),
): Promise<void> {
  await page.waitForSelector(FLUTTER_HOST_SELECTORS, {
    state: 'attached',
    timeout,
  });
}

export interface ErrorCollectors {
  readonly consoleErrors: string[];
  readonly pageErrors: string[];
}

/** Start recording console-error + uncaught page-error events for diagnostics. */
export function collectPageErrors(page: Page): ErrorCollectors {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => pageErrors.push(String(err)));
  return { consoleErrors, pageErrors };
}

export interface BootDiagnostics {
  url: string;
  title: string;
  responseStatus: number | null;
  flutterViewCount: number;
  flutterHostPresent: boolean;
  hasBootstrapScript: boolean;
  ddcOrMainScriptPresent: boolean;
  bodyTextSnippet: string;
  consoleErrors: string[];
  pageErrors: string[];
}

/**
 * Snapshot what the page actually is at a boot failure. Runs while the page is
 * still open (the boot wait times out BELOW the test timeout, by design). The
 * body-text snippet is safe: it is rendered text only (the anon key / secrets
 * never appear in the DOM), and it is length-capped.
 */
export async function captureBootDiagnostics(
  page: Page,
  opts: { responseStatus: number | null } & ErrorCollectors,
): Promise<BootDiagnostics> {
  const dom = await page
    .evaluate(() => {
      const has = (sel: string) => !!document.querySelector(sel);
      return {
        flutterViewCount: document.querySelectorAll('flutter-view').length,
        flutterHostPresent: has(
          'flutter-view, flt-glass-pane, flt-scene-host, flt-semantics-placeholder, canvas',
        ),
        hasBootstrapScript:
          has('script[src*="flutter_bootstrap.js"]') ||
          has('script[src*="flutter.js"]'),
        ddcOrMainScriptPresent:
          has('script[src*="ddc_module_loader.js"]') ||
          has('script[src*="main.dart.js"]'),
        bodyTextSnippet: (document.body?.innerText ?? '').trim().slice(0, 300),
      };
    })
    .catch(() => ({
      flutterViewCount: 0,
      flutterHostPresent: false,
      hasBootstrapScript: false,
      ddcOrMainScriptPresent: false,
      bodyTextSnippet: '(page.evaluate failed — page may be closed)',
    }));

  let title = '';
  try {
    title = await page.title();
  } catch {
    // Page already closed — leave title blank.
  }

  return {
    url: page.url(),
    title,
    responseStatus: opts.responseStatus,
    ...dom,
    consoleErrors: opts.consoleErrors.slice(0, 20),
    pageErrors: opts.pageErrors.slice(0, 20),
  };
}

/** A human-readable, actionable boot-failure message (no secrets). */
export function formatBootDiagnostics(
  name: string,
  d: BootDiagnostics,
): string {
  const stillLoading = d.hasBootstrapScript && !d.flutterHostPresent;
  return [
    `${name} did not boot a Flutter view within ${bootTimeoutMs()}ms.`,
    `  final URL:         ${d.url}`,
    `  HTTP status:       ${d.responseStatus ?? 'n/a'}`,
    `  document.title:    ${JSON.stringify(d.title)}`,
    `  flutter-view count:${d.flutterViewCount}`,
    `  flutter host?:     ${d.flutterHostPresent}`,
    `  bootstrap script?: ${d.hasBootstrapScript}`,
    `  DDC/main script?:  ${d.ddcOrMainScriptPresent}`,
    `  body text (<=300): ${JSON.stringify(d.bodyTextSnippet)}`,
    `  page errors:       ${d.pageErrors.length ? d.pageErrors.join(' | ') : '(none)'}`,
    `  console errors:    ${d.consoleErrors.length ? d.consoleErrors.join(' | ') : '(none)'}`,
    stillLoading
      ? `  → The Flutter bootstrap is present but no view attached yet. This is ` +
        `usually a slow DDC debug build still loading. Boot only one app at a ` +
        `time (workers=1) and/or raise RF_E2E_BOOT_TIMEOUT_MS.`
      : !d.hasBootstrapScript
        ? `  → No Flutter bootstrap on the page — this may not be a Flutter build, ` +
          `a wrong URL, or a non-app (proxy/error) page.`
        : `  → A Flutter host is present but the wait still failed; inspect the ` +
          `trace/screenshot artifact.`,
  ].join('\n');
}

/** Wait for boot; on failure throw a rich diagnostic instead of a bare timeout. */
export async function bootOrDiagnose(
  page: Page,
  name: string,
  opts: { responseStatus: number | null } & ErrorCollectors,
): Promise<void> {
  try {
    await waitForFlutterBoot(page);
  } catch {
    const diagnostics = await captureBootDiagnostics(page, opts);
    throw new Error(formatBootDiagnostics(name, diagnostics));
  }
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
 *
 * The placeholder is a 1px element positioned at NEGATIVE coordinates
 * (left:-1px; top:-1px), so a coordinate-based `.click()` (even forced) misses it.
 * `dispatchEvent('click')` fires the DOM click straight at the element regardless
 * of position — this is what actually activates semantics (verified live: the tree
 * goes from 0 to N nodes). Flutter then REMOVES the placeholder, so we click once
 * and wait for the tree rather than retrying on a now-detached element.
 */
export async function enableFlutterSemantics(
  page: Page,
  timeout = 20_000,
): Promise<boolean> {
  try {
    const placeholder = page.locator(SEMANTICS_PLACEHOLDER).first();
    await placeholder.waitFor({ state: 'attached', timeout: 10_000 });
    await placeholder.dispatchEvent('click');
  } catch {
    // No placeholder (already enabled, or a build without it) — probe for the tree.
  }
  try {
    await page.waitForSelector(SEMANTICS_TREE, { state: 'attached', timeout });
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
  // The tree fills in over a few frames after activation; poll until it carries
  // text rather than reading once on a possibly-empty root node.
  let text = '';
  for (let attempt = 0; attempt < 12; attempt++) {
    text = await readAccessibleText(page);
    if (text.trim().length > 0) break;
    await page.waitForTimeout(250);
  }
  return text;
}
