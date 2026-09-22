// OWNER-APPROVED, SCOPED ACCEPTANCE DECISIONS for STOREFRONT-UI-001 - the
// exception table the validators read. It is deliberately NOT in budgets.mjs:
// the written limits there are unchanged and still reported; what this file
// adds is an explicit, bounded, owner-chosen acceptance rule on top of them.
//
// Authority: the owner's activation "OWNER APPROVED - UI-001 SCOPED
// ACCEPTANCE EXCEPTIONS" (2026-09-23) with the packet "BIZBOT STOREFRONT
// UI-001 - SCOPED ACCEPTANCE DECISION / LOCAL CLOSEOUT", decisions
// CSS-UI001-01 and PERF-UI001-01. Nothing else is excepted. The table is
// frozen, keyed by exact canonical route, read by no environment variable
// and by no frontend code; the only way to widen it is an edit here, which
// is a reviewed change. Review it when the pinned bundler / architecture is
// replaced or the shipped route / design scope expands - it is not a
// permanent budget for every BIZBOT project.
import { BUDGETS } from './budgets.mjs';

const DECISION = 'OWNER APPROVED - UI-001 SCOPED ACCEPTANCE EXCEPTIONS (2026-09-23)';

/**
 * CSS-UI001-01 - a temporary, UI-001-specific raw-CSS exception.
 *
 * The original target stays recorded and is still reported per route:
 * 70,000 raw bytes per direct-load route (BUDGETS.cssPerRouteBytes). For the
 * EXACT routes listed below - the thirty-two storefront documents measured
 * over that target on the final source-bound build of head 1387d23b
 * (84,175 / 84,177 B on the flow, request and search documents; 93,812 /
 * 93,814 B on the home and intro documents) - the effective raw ceiling is
 * 100,000 decimal bytes: a NEW owner-chosen limit for this acceptance
 * decision, not a framework figure, not a pre-existing approval and not
 * measured x 1.2 (it allows at most 6,186 B above the reported worst value).
 * The Brotli ceiling (14,000 B per route) is unchanged and must ALSO pass.
 * Any route not listed keeps the 70,000 B raw target. A route over 100,000 B
 * raw, over 14,000 B Brotli, without a measurement, with a missing referenced
 * stylesheet, or a measurement with zero route coverage FAILS; nothing is
 * skipped, warned about or excluded. This is a scoped performance tradeoff,
 * NOT evidence that 93,814 B passes 70,000 B: compressed bytes are not CSS
 * parsing / rendering work, so the raw axis is kept, reported and reviewed.
 */
export const CSS_RAW_EXCEPTION = Object.freeze({
  id: 'CSS-UI001-01',
  decision: DECISION,
  originalLimitBytes: BUDGETS.cssPerRouteBytes,        // 70,000 - recorded, unchanged, always reported
  approvedLimitBytes: 100000,                          // exact decimal bytes, owner-chosen for this decision only
  brotliLimitBytes: BUDGETS.cssPerRouteBrotliBytes,    // 14,000 - unchanged, must pass as well
  measuredOn: 'head 1387d23b, shipped build (SF_EVIDENCE_ROUTES unset), measurements/measure-firstload-final.json of the sealed correction pack',
  reviewWhen: 'the pinned bundler / architecture is replaced, or the shipped route / design scope expands',
  routes: Object.freeze([
    // intro (the storefront root document) - 4 stylesheets, 93,812 / 93,814 B raw
    '/s/maps-burger', '/ar/s/maps-burger', '/en/s/maps-burger', '/he/s/maps-burger',
    // home - 4 stylesheets, 93,812 / 93,814 B raw
    '/s/maps-burger/menu', '/ar/s/maps-burger/menu', '/en/s/maps-burger/menu', '/he/s/maps-burger/menu',
    // search - 3 stylesheets, 84,175 / 84,177 B raw
    '/s/maps-burger/search', '/ar/s/maps-burger/search', '/en/s/maps-burger/search', '/he/s/maps-burger/search',
    // flow: cart / checkout / payment / review - 3 stylesheets, 84,175 / 84,177 B raw
    '/s/maps-burger/cart', '/ar/s/maps-burger/cart', '/en/s/maps-burger/cart', '/he/s/maps-burger/cart',
    '/s/maps-burger/checkout', '/ar/s/maps-burger/checkout', '/en/s/maps-burger/checkout', '/he/s/maps-burger/checkout',
    '/s/maps-burger/payment', '/ar/s/maps-burger/payment', '/en/s/maps-burger/payment', '/he/s/maps-burger/payment',
    '/s/maps-burger/review', '/ar/s/maps-burger/review', '/en/s/maps-burger/review', '/he/s/maps-burger/review',
    // request (received | status on one document) - 3 stylesheets, 84,175 / 84,177 B raw
    '/r/DEMO-7K4XM2D9P3', '/ar/r/DEMO-7K4XM2D9P3', '/en/r/DEMO-7K4XM2D9P3', '/he/r/DEMO-7K4XM2D9P3',
    // NOT listed: the four locale-root placeholders (/, /ar, /en, /he - 2,201 B)
    // and every future route; they keep the 70,000 B target.
  ]),
});

/**
 * PERF-UI001-01 - which local lane decides LCP acceptance.
 *
 * The documented COMPRESSED local lab (Brotli q11 / gzip for text types,
 * served by the lab server, every other protocol parameter unchanged:
 * canonical AR Home, 390x844 @2x mobile, 4x CPU slowdown, 1.6 Mbps /
 * 150 ms RTT, cold state, five runs, the established median) becomes the
 * primary LCP acceptance transport for UI-001. The target is unchanged at
 * 2,500 ms - not 2,700, not 3,000. The original UNCOMPRESSED lane is kept as
 * a diagnostic record with its observed FAIL; it is not relabelled, erased
 * or described as passing. Compression is the sole transport distinction:
 * no cached or prewarmed run, hidden resource, reduced design, other clock
 * or changed throttling. The other lab limits stay as written on BOTH
 * transports. Hosted compression and hosted performance remain UNVERIFIED
 * until a separately authorised hosted gate measures the real serving path;
 * a local compressor's quality level is not a proved edge quality level.
 */
export const PERF_LCP_ACCEPTANCE = Object.freeze({
  id: 'PERF-UI001-01',
  decision: DECISION,
  lcpTargetMs: 2500,                                   // unchanged
  acceptanceTransport: 'compressed local lab (Brotli q11 / gzip for text types; lab server serve-out-br.mjs)',
  diagnosticTransport: 'uncompressed local lab (scripts/serve-out.mjs) - retained as a diagnostic record, FAIL kept as observed',
  unchanged: Object.freeze({
    longTaskOver50Ms: 300,                             // sum above 50 ms, on BOTH recorded transports
    cls: 0.05,
    clsHard: 0.1,
    fontSwapShift: 0.02,
  }),
  hosted: 'UNVERIFIED - a separately authorised hosted gate must verify negotiated compression and content types on the actual serving path',
});
