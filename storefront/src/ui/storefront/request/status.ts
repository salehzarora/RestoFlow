/**
 * THE REQUEST STATUS MODEL - pure, framework-free.
 *
 * Nine lifecycle states on one axis, exactly the prototype's
 * (Storefront.dc.html:643 `status` enum, :835 `order` + `terminal`), and ONE
 * explicit table that says, per state, which timeline node is current, which
 * hero tone applies, which actions exist and whether a TTL is shown - derived
 * from the prototype's `stMap` (:837), `st` (:847) and step derivation
 * (:843-846) rather than from nine scattered booleans.
 *
 * WHAT THIS MODEL REFUSES TO DO. It never invents a time: a timeline node
 * shows a clock reading only when the SOURCE recorded an event for that state
 * (PACKET PX-10). The prototype's `createdAt + n x 4 minutes` (:842, :846) is
 * a demo shortcut and is not reproduced. It never advances a state on its own:
 * expiry, acceptance and rejection are things the source says, and a TTL that
 * reaches 0:00 is displayed as 0:00 until the source says `expired`.
 *
 * THE PENDING PREDICATE, resolved from the source and used everywhere:
 * `canCancel: key === 'waiting' || key === 'received'` (:847) - the two states
 * before the restaurant has answered. The TTL pill is narrower: `showTtl: key
 * === 'waiting'` (:847), so `received` ticks but shows no pill.
 */
import type { Minor, ModifierSelections } from '@/source/types';

export type RequestState =
  | 'received'
  | 'waiting'
  | 'accepted'
  | 'preparing'
  | 'ready'
  | 'completed'
  | 'rejected'
  | 'expired'
  | 'cancelled';

export const REQUEST_STATES: readonly RequestState[] = [
  'received',
  'waiting',
  'accepted',
  'preparing',
  'ready',
  'completed',
  'rejected',
  'expired',
  'cancelled',
];

/** The happy path, in timeline order (:835 `order`). */
export const PROGRESS_STATES: readonly RequestState[] = [
  'received',
  'waiting',
  'accepted',
  'preparing',
  'ready',
  'completed',
];

/** Outcomes that replace the tail after "waiting" (:835 `terminal`). */
export const TERMINAL_STATES: readonly RequestState[] = ['rejected', 'expired', 'cancelled'];

export function isRequestState(value: unknown): value is RequestState {
  return typeof value === 'string' && (REQUEST_STATES as readonly string[]).includes(value);
}

/** The restaurant has not answered yet: cancel is offered (:847 `canCancel`). */
export function isPending(state: RequestState): boolean {
  return state === 'received' || state === 'waiting';
}

export function isTerminal(state: RequestState): boolean {
  return TERMINAL_STATES.includes(state);
}

/** The hero-card tones the inventory lists (COMPONENT_INVENTORY.md:164). */
export type StatusTone = 'info' | 'warn' | 'ok' | 'bad' | 'neutral';

/** The action set the prototype renders per state (:567-569, :847). */
export type StatusAction = 'chat' | 'cancel' | 'orderAgain';

export interface StateRow {
  readonly tone: StatusTone;
  /** Index into PROGRESS_STATES for a progress state; null for a terminal one. */
  readonly step: number | null;
  readonly terminal: boolean;
  readonly pending: boolean;
  /** `showTtl` (:847): the countdown pill renders in exactly one state. */
  readonly ttl: boolean;
  readonly actions: readonly StatusAction[];
}

const CHAT_AND_CANCEL: readonly StatusAction[] = ['chat', 'cancel'];
const CHAT_ONLY: readonly StatusAction[] = ['chat'];
const AGAIN: readonly StatusAction[] = ['orderAgain'];

/**
 * One table, transcribed from :835-:847. `completed` is not in the prototype's
 * `terminal` array but DOES get "order again" (`showAgain: isTerm || key ===
 * 'completed'`), which is why `terminal` and `actions` are separate columns.
 */
export const STATE_TABLE: Readonly<Record<RequestState, StateRow>> = {
  received: { tone: 'info', step: 0, terminal: false, pending: true, ttl: false, actions: CHAT_AND_CANCEL },
  waiting: { tone: 'warn', step: 1, terminal: false, pending: true, ttl: true, actions: CHAT_AND_CANCEL },
  accepted: { tone: 'ok', step: 2, terminal: false, pending: false, ttl: false, actions: CHAT_ONLY },
  preparing: { tone: 'ok', step: 3, terminal: false, pending: false, ttl: false, actions: CHAT_ONLY },
  ready: { tone: 'ok', step: 4, terminal: false, pending: false, ttl: false, actions: CHAT_ONLY },
  completed: { tone: 'ok', step: 5, terminal: false, pending: false, ttl: false, actions: AGAIN },
  rejected: { tone: 'bad', step: null, terminal: true, pending: false, ttl: false, actions: AGAIN },
  expired: { tone: 'warn', step: null, terminal: true, pending: false, ttl: false, actions: AGAIN },
  cancelled: { tone: 'neutral', step: null, terminal: true, pending: false, ttl: false, actions: AGAIN },
};

/** A state change the source recorded, with the instant it happened. */
export interface RequestEvent {
  readonly state: RequestState;
  /** Epoch milliseconds. Never synthesised by the UI. */
  readonly at: number;
}

/** One line of the request, as the source reports it - ids only, no free text. */
export interface RequestLine {
  readonly itemId: string;
  readonly qty: number;
  readonly selections: ModifierSelections;
  readonly lineTotalMinor: Minor;
}

/**
 * What a status source answers for one ref. Everything here is what the
 * restaurant's system knows about the REQUEST; nothing here is a contact
 * field, an address or a kitchen note, and no implementation may add one.
 */
export interface RequestSnapshot {
  readonly ref: string;
  readonly slug: string;
  /** The human-readable code, e.g. "#MB-2487" - distinct from the opaque ref. */
  readonly displayCode: string;
  readonly service: 'pickup' | 'delivery';
  readonly zoneName: string | null;
  readonly payment: 'cash';
  readonly lines: readonly RequestLine[];
  readonly subtotalMinor: Minor;
  readonly feeMinor: Minor;
  readonly taxMinor: Minor;
  readonly totalMinor: Minor;
  readonly state: RequestState;
  readonly events: readonly RequestEvent[];
  readonly createdAt: number;
  /** The instant the pending window closes, or null when no window applies. */
  readonly expiresAt: number | null;
  readonly ttlMinutes: number;
  /** Monotonic per ref. A cancel names the version it saw. */
  readonly version: number;
}

export type CancelResult =
  | { readonly kind: 'cancelled'; readonly snapshot: RequestSnapshot }
  /** The source moved on before the cancel arrived: nothing was cancelled. */
  | { readonly kind: 'not_pending'; readonly snapshot: RequestSnapshot }
  | { readonly kind: 'unknown' };

/**
 * The seam a status backend will occupy (PACKET:612, DEFERRED STATUS-001).
 * `subscribe` delivers the current snapshot after mount and every later
 * change; it never resolves synchronously, so nothing can be prerendered from
 * it. Callbacks may arrive after the caller moved on: the caller checks the
 * ref and its own liveness, and the returned function stops delivery.
 */
export interface StatusSource {
  subscribe(
    ref: string,
    onSnapshot: (snapshot: RequestSnapshot) => void,
    onMissing: () => void,
  ): () => void;
  cancel(ref: string, seenVersion: number): Promise<CancelResult>;
}

export type Clock = () => number;

// ----------------------------------------------------------------- derivations

export type NodeKind = 'done' | 'current' | 'future' | 'terminal';

export interface TimelineNode {
  readonly state: RequestState;
  readonly kind: NodeKind;
  /** The recorded instant, or null when the source has no event for it. */
  readonly at: number | null;
  /** True on the current "waiting" node, which carries the countdown sub-line. */
  readonly countdown: boolean;
}

/**
 * The vertical timeline (:843-846). Progress states render all six nodes with
 * everything before the current one done; a terminal outcome renders
 * received + waiting as done and ONE terminal node in their place of the tail.
 * Times come only from `events`.
 */
export function timelineFor(snapshot: RequestSnapshot): readonly TimelineNode[] {
  const row = STATE_TABLE[snapshot.state];
  const eventAt = (state: RequestState): number | null =>
    snapshot.events.find((e) => e.state === state)?.at ?? null;

  if (row.terminal) {
    return [
      { state: 'received', kind: 'done', at: eventAt('received'), countdown: false },
      { state: 'waiting', kind: 'done', at: eventAt('waiting'), countdown: false },
      { state: snapshot.state, kind: 'terminal', at: eventAt(snapshot.state), countdown: false },
    ];
  }

  const current = row.step ?? 0;
  return PROGRESS_STATES.map((state, index) => {
    const kind: NodeKind = index < current ? 'done' : index === current ? 'current' : 'future';
    return {
      state,
      kind,
      at: kind === 'future' ? null : eventAt(state),
      countdown: kind === 'current' && state === 'waiting',
    };
  });
}

export interface Ttl {
  readonly msLeft: number;
  /** `M:SS`, clamped at 0:00 (CONTENT_AND_LOCALIZATION.md:236, :769). */
  readonly text: string;
}

/**
 * The countdown, from the source's `expiresAt` and an injected instant. Null
 * whenever the state does not show a TTL, so a consumer cannot render one by
 * accident in a state the design keeps quiet.
 */
export function ttlFor(snapshot: RequestSnapshot, now: number): Ttl | null {
  if (!STATE_TABLE[snapshot.state].ttl || snapshot.expiresAt === null) return null;
  const msLeft = Math.max(0, snapshot.expiresAt - now);
  const totalSeconds = Math.floor(msLeft / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return { msLeft, text: `${minutes}:${String(seconds).padStart(2, '0')}` };
}

/** The cancel guard, applied identically by the source and by the screen. */
export function canCancel(snapshot: RequestSnapshot): boolean {
  return STATE_TABLE[snapshot.state].pending;
}

/**
 * True when `next` may replace `current` on screen: a newer version of the
 * same ref. A stale or foreign callback is refused here, in one place.
 */
export function supersedes(current: RequestSnapshot | null, next: RequestSnapshot, ref: string): boolean {
  if (next.ref !== ref) return false;
  if (current === null) return true;
  return next.version > current.version;
}
