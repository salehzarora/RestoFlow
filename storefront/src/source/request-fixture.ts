/**
 * THE REQUEST FIXTURE - one demo ref, one demo request, one demo status
 * source. FIXTURE LAYER ONLY: this whole module disappears with the fixtures
 * when a live status backend lands (DEFERRED STATUS-001, REQ-001).
 *
 * ONE SHARED REF AUTHORITY. Exactly one canonical opaque demo ref ships,
 * across four locale roots, and every consumer reads it from HERE: the four
 * `r/[ref]` static-params lists, the fixture gateway's accepted and duplicate
 * results, and this status source. Phase D derived a mock ref from the order's
 * shape; that ref would have pointed at a document the static export never
 * emitted, so it is reconciled to this one (FINISH 4.1). This is a fixture
 * allocation, not production ID generation and not an idempotency claim.
 *
 * WHAT A REF IS. The URL segment is OPAQUE (PACKET PD-11): it identifies the
 * document, it is never shown as the request's name, and the human-readable
 * code (`#MB-2487`, the prototype's REST.code) is a separate field. A real
 * capability format is a SEC-002 decision.
 *
 * NOTHING HERE IS A PERSON. The fixed demo request is a fixed demonstration,
 * not another customer's order; it carries item ids, a zone and money - no
 * name, no phone, no address, no note - and the screen that renders it says
 * it is a local demo.
 *
 * NO I/O. No fetch, no storage, no clock other than the one injected. Timers
 * exist only to make three source behaviours reproducible locally: expiry at
 * `expiresAt`, and two evidence scenarios where the restaurant answers while a
 * confirmation is open.
 */
import { buildQuote } from '@/money/quote';
import type { Minor, ModifierSelections, Tenant } from '@/source/types';
import {
  isPending,
  type CancelResult,
  type Clock,
  type RequestEvent,
  type RequestLine,
  type RequestSnapshot,
  type RequestState,
  type StatusSource,
} from '@/ui/storefront/request/status';
import { fixtureSource } from './fixtures';
import { DEMO_DISPLAY_CODE, DEMO_REQUEST_REF, DEMO_REQUEST_SLUG } from './request-ref';
import { MENU_ITEMS, MENU_VERSION, TAX_RATE } from './menu-fixture';
import { findZone } from './zones';

// ------------------------------------------------------------- the one ref

export { DEMO_DISPLAY_CODE, DEMO_REQUEST_REF, DEMO_REQUEST_SLUG } from './request-ref';
/** REST.ttlMin (storefront-data.js:6). Configurability is OPEN_QUESTIONS.md:48. */
export const REQUEST_TTL_MINUTES = 30;

/** The refs a request route pre-renders. Evidence scenarios add none. */
export function requestRefs(): readonly string[] {
  return [DEMO_REQUEST_REF];
}

export interface RequestResolution {
  readonly ref: string;
  readonly slug: string;
  readonly displayCode: string;
  /** The language the restaurant writes in; the message is composed in it. */
  readonly contentLocale: 'ar';
  readonly tenant: Tenant;
}

export function resolveRequest(ref: string): RequestResolution | null {
  if (ref !== DEMO_REQUEST_REF) return null;
  const tenant = fixtureSource.getTenant(DEMO_REQUEST_SLUG);
  if (tenant === null) return null;
  return { ref, slug: DEMO_REQUEST_SLUG, displayCode: DEMO_DISPLAY_CODE, contentLocale: 'ar', tenant };
}

// ------------------------------------------------------- the demo request

/**
 * A request summary. The seeded one comes from the visitor's own send; the
 * fixed one below is what a direct load of the demo ref shows.
 */
export interface RequestSeed {
  readonly service: 'pickup' | 'delivery';
  readonly zoneId: string;
  readonly lines: readonly { readonly itemId: string; readonly qty: number; readonly selections: ModifierSelections }[];
  /** Epoch ms of the send, from the injected clock at that moment. */
  readonly createdAt: number;
}

/**
 * The prototype's `small` seed (Storefront.dc.html, received capture): one
 * classic on brioche with extra cheese and no onion, two fries with garlic
 * mayo, delivered to Kafr Manda. Priced by the money authority, never here.
 */
const DEMO_LINES: RequestSeed['lines'] = [
  { itemId: '1', qty: 1, selections: { bun: ['brioche'], extras: ['cheese'], remove: ['onion'] } },
  { itemId: '7', qty: 2, selections: { sauce: ['garlic'] } },
];

function priced(seed: Omit<RequestSeed, 'createdAt'>): {
  lines: readonly RequestLine[];
  subtotalMinor: Minor;
  feeMinor: Minor;
  taxMinor: Minor;
  totalMinor: Minor;
  zoneName: string | null;
} {
  const zone = seed.service === 'delivery' ? findZone(seed.zoneId) : null;
  const quote = buildQuote({
    cart: {
      schema: 1,
      slug: DEMO_REQUEST_SLUG,
      menuVersion: MENU_VERSION,
      lines: seed.lines.map((l, i) => ({ lineId: `r${i}`, itemId: l.itemId, qty: l.qty, selections: l.selections, note: '' })),
    },
    items: MENU_ITEMS,
    service: seed.service,
    zone,
    taxRate: TAX_RATE,
  });
  return {
    lines: quote.lines.map((l, i) => ({
      itemId: l.item.id,
      qty: l.qty,
      selections: seed.lines[i]?.selections ?? {},
      lineTotalMinor: l.lineTotalMinor,
    })),
    subtotalMinor: quote.subtotalMinor,
    feeMinor: quote.feeMinor,
    taxMinor: quote.taxMinor,
    totalMinor: quote.totalMinor,
    zoneName: quote.feeApplies && quote.zone !== null ? quote.zone.name : null,
  };
}

// ------------------------------------------------------------- scenarios

/**
 * The route's `?fx=` switch lives in request-scenarios.ts, a deliberately small
 * module the flow runtime can import without this file. Re-exported here so
 * the fixture layer stays one import for its other consumers.
 */
export {
  readRequestScenario,
  withRequestScenario,
  REQUEST_SCENARIOS,
  WA_FALLBACK,
  STATUS_MISSING,
  type RequestScenario,
} from './request-scenarios';
import type { RequestScenario } from './request-scenarios';

const LATE_MS = 1500;

/**
 * How old the demo request is when a state is opened directly, and when each
 * recorded event happened relative to its creation. EXPLICIT RECORDS, so a
 * timeline node shows a time only because one is written here - never
 * `createdAt + n x 4 minutes` (PACKET PX-10).
 */
const MINUTE = 60_000;
const DEMO_AGE_MS: Readonly<Record<RequestState, number>> = {
  received: 350_000,
  waiting: 350_000,
  accepted: 8 * MINUTE,
  preparing: 12 * MINUTE,
  ready: 25 * MINUTE,
  completed: 40 * MINUTE,
  rejected: 6 * MINUTE,
  expired: 36 * MINUTE,
  cancelled: 3 * MINUTE,
};
const EVENT_OFFSETS_MS: Readonly<Record<RequestState, number>> = {
  received: 0,
  waiting: 20_000,
  accepted: 6 * MINUTE,
  preparing: 9 * MINUTE,
  ready: 21 * MINUTE,
  completed: 32 * MINUTE,
  rejected: 4 * MINUTE,
  expired: REQUEST_TTL_MINUTES * MINUTE,
  cancelled: 2 * MINUTE,
};
const PROGRESS: readonly RequestState[] = ['received', 'waiting', 'accepted', 'preparing', 'ready', 'completed'];

function eventsFor(state: RequestState, createdAt: number): readonly RequestEvent[] {
  const idx = PROGRESS.indexOf(state);
  const reached: RequestState[] =
    idx >= 0 ? PROGRESS.slice(0, idx + 1) : ['received', 'waiting', state];
  return reached.map((s) => ({ state: s, at: createdAt + EVENT_OFFSETS_MS[s] }));
}

function snapshotFor(
  state: RequestState,
  seed: Omit<RequestSeed, 'createdAt'>,
  createdAt: number,
  version: number,
  overrides: Partial<Pick<RequestSnapshot, 'expiresAt' | 'events'>> = {},
): RequestSnapshot {
  const money = priced(seed);
  return {
    ref: DEMO_REQUEST_REF,
    slug: DEMO_REQUEST_SLUG,
    displayCode: DEMO_DISPLAY_CODE,
    service: seed.service,
    zoneName: money.zoneName,
    payment: 'cash',
    lines: money.lines,
    subtotalMinor: money.subtotalMinor,
    feeMinor: money.feeMinor,
    taxMinor: money.taxMinor,
    totalMinor: money.totalMinor,
    state,
    events: overrides.events ?? eventsFor(state, createdAt),
    createdAt,
    expiresAt:
      overrides.expiresAt !== undefined
        ? overrides.expiresAt
        : isPending(state)
          ? createdAt + REQUEST_TTL_MINUTES * MINUTE
          : null,
    ttlMinutes: REQUEST_TTL_MINUTES,
    version,
  };
}

// ---------------------------------------------------------- the status source

export interface DemoStatusOptions {
  readonly scenario: RequestScenario;
  readonly clock: Clock;
  /** The visitor's own just-sent request, when there is one. */
  readonly seed?: RequestSeed;
  /** Simulated round trip for a cancel; tests pass 0. */
  readonly cancelDelayMs?: number;
  /** How long the two `-late` scenarios wait before the restaurant answers. */
  readonly lateMs?: number;
}

/**
 * One instance per screen mount, holding one request. It is created by the
 * runtime with whatever seed that runtime has; it is never a module-level
 * object, so one visitor's request cannot be observed from another render.
 */
export function demoStatusSource(options: DemoStatusOptions): StatusSource {
  const { scenario, clock } = options;
  const lateMs = options.lateMs ?? LATE_MS;
  const cancelDelay = options.cancelDelayMs ?? 300;

  const seed: Omit<RequestSeed, 'createdAt'> =
    options.seed ?? {
      service: scenario?.kind === 'fallback' ? 'pickup' : 'delivery',
      zoneId: 'kafrmanda',
      lines: DEMO_LINES,
    };

  const initialState: RequestState =
    scenario?.kind === 'state' ? scenario.state : 'waiting';
  const createdAt = options.seed?.createdAt ?? clock() - DEMO_AGE_MS[initialState];

  let current: RequestSnapshot | null =
    scenario?.kind === 'missing'
      ? null
      : snapshotFor(
          initialState,
          seed,
          createdAt,
          1,
          scenario?.kind === 'expires-late' ? { expiresAt: clock() + lateMs } : {},
        );

  const listeners = new Set<(s: RequestSnapshot) => void>();
  const timers = new Set<ReturnType<typeof setTimeout>>();
  const later = (ms: number, fn: () => void) => {
    const t = setTimeout(() => {
      timers.delete(t);
      fn();
    }, ms);
    timers.add(t);
  };
  const emit = () => {
    if (current === null) return;
    for (const l of listeners) l(current);
  };
  const advance = (state: RequestState) => {
    if (current === null || !isPending(current.state)) return;
    const at = clock();
    current = snapshotFor(state, seed, current.createdAt, current.version + 1, {
      events: [...current.events, { state, at }],
      expiresAt: null,
    });
    emit();
  };

  // The three source-driven transitions, armed once.
  if (current !== null && isPending(current.state) && current.expiresAt !== null) {
    later(Math.max(0, current.expiresAt - clock()), () => advance('expired'));
  }
  if (scenario?.kind === 'accepts-late') later(lateMs, () => advance('accepted'));

  return {
    subscribe(ref, onSnapshot, onMissing) {
      let live = true;
      const listener = (s: RequestSnapshot) => {
        if (live) onSnapshot(s);
      };
      listeners.add(listener);
      // Never synchronous: the first answer arrives after mount, like a fetch.
      later(0, () => {
        if (!live) return;
        if (current === null || ref !== DEMO_REQUEST_REF) onMissing();
        else onSnapshot(current);
      });
      return () => {
        live = false;
        listeners.delete(listener);
        if (listeners.size === 0) {
          for (const t of timers) clearTimeout(t);
          timers.clear();
        }
      };
    },
    cancel(ref, seenVersion) {
      return new Promise<CancelResult>((resolve) => {
        later(cancelDelay, () => {
          if (current === null || ref !== DEMO_REQUEST_REF) {
            resolve({ kind: 'unknown' });
            return;
          }
          // The guard is the SOURCE'S state, not the caller's memory: a request
          // the restaurant answered while the sheet was open stays answered.
          if (!isPending(current.state) || current.version !== seenVersion) {
            resolve({ kind: 'not_pending', snapshot: current });
            return;
          }
          advance('cancelled');
          resolve({ kind: 'cancelled', snapshot: current });
        });
      });
    },
  };
}
