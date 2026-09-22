/**
 * THE ONE FIXTURE REF - the constants only.
 *
 * Split from request-fixture.ts so the flow's gateway can name the demo ref
 * without pulling the whole status fixture (its scenarios, snapshots and
 * timers) into the flow routes' first load, which sits within 0.5% of its
 * ceiling. Route-scoped imports, not a second authority: request-fixture.ts
 * re-exports these and every other consumer reads them from there.
 */

/** Opaque. Matches the route's REF shape; says "DEMO" so the URL itself does. */
export const DEMO_REQUEST_REF = 'DEMO-7K4XM2D9P3';
/** The prototype's REST.code (storefront-data.js:6), shown as the request's name. */
export const DEMO_DISPLAY_CODE = '#MB-2487';
export const DEMO_REQUEST_SLUG = 'maps-burger';

/**
 * The display code for a ref, resolved on the CLIENT after mount. The static
 * document must not carry it: for a real request the code is request data,
 * and the served bytes are identical for everyone.
 */
export function displayCodeFor(ref: string): string | null {
  return ref === DEMO_REQUEST_REF ? DEMO_DISPLAY_CODE : null;
}
