import type { OrderController, OrderIdentity, OrderOutcome, OrderSnapshot, OrderTransport, RecoveryRecord, RecoveryStorage, WebOrder, WebOrderErrorCode } from './contract';
import { createOrderIdentity, OrderIdentityError } from './identity';
import { browserRecoveryStorage, clearRecovery, readRecovery, saveRecovery } from './recovery';
import { createOrderTransport } from './transport';
import { isCanonicalSlug, normalizeWebOrder, invalid } from './validation';

export interface OrderControllerOptions {
  readonly slug: string;
  readonly origin: string;
  readonly storage?: RecoveryStorage | null;
  readonly fetchImpl?: typeof fetch;
  readonly cryptoImpl?: Crypto;
  readonly now?: () => number;
  readonly timeoutMs?: number;
  /** Offline unit tests can inject this boundary. Production uses the strict transport. */
  readonly transport?: OrderTransport;
}

/**
 * One private controller per tenant/tab flow. Its frozen submission lives only here.
 * After reload the saved identity authorizes status reads, never a reconstructed write.
 */
export function createOrderController(options: OrderControllerOptions): OrderController {
  const { slug, now = Date.now } = options;
  if (!isCanonicalSlug(slug)) invalid();
  // Always validate the configured origin, including when tests inject a transport.
  const strictTransport = createOrderTransport(options);
  const transport = options.transport ?? strictTransport;
  const storage = () => options.storage === undefined ? browserRecoveryStorage() : options.storage;
  let record: RecoveryRecord | null = null;
  let original: WebOrder | null = null;
  let inFlight: Promise<OrderSnapshot> | null = null;
  let snapshot: OrderSnapshot = Object.freeze({ phase: 'idle', result: null, error: null, canRetry: false, recovered: false });
  const listeners = new Set<() => void>();
  const update = (changes: Partial<OrderSnapshot>): OrderSnapshot => {
    snapshot = Object.freeze({ ...snapshot, ...changes });
    for (const listener of listeners) { try { listener(); } catch { /* A view observer cannot interrupt a request. */ } }
    return snapshot;
  };
  const fail = (error: WebOrderErrorCode): OrderSnapshot => update({ phase: 'failure', error, canRetry: false });
  const identity = (): OrderIdentity => {
    if (!record) return invalid();
    return { slug: record.slug, request_id: record.request_id, status_token: record.status_token };
  };
  const liveRecord = (): boolean => {
    if (!record) return false;
    if (record.expires_at > now() && record.created_at <= now()) return true;
    clearRecovery(storage(), slug);
    record = null; original = null;
    fail('recovery_expired');
    return false;
  };
  const load = (): boolean => {
    if (record) return liveRecord();
    const recovered = readRecovery(storage(), slug, now());
    if (recovered.kind === 'record') {
      record = recovered.record;
      original = null;
      update({ recovered: true, canRetry: false });
      return true;
    }
    if (recovered.kind === 'blocked') fail('storage_unavailable');
    else if (recovered.kind === 'invalid') fail('recovery_invalid');
    else if (recovered.kind === 'expired') fail('recovery_expired');
    return false;
  };
  const receive = (outcome: OrderOutcome, checking: boolean): OrderSnapshot => {
    if (outcome.kind === 'known') {
      if (record) {
        const expiry = Math.min(record.expires_at, Date.parse(outcome.result.expires_at));
        if (outcome.result.status === 'expired' || expiry <= now()) {
          clearRecovery(storage(), slug);
        } else if (expiry > record.created_at) {
          record = Object.freeze({ ...record, expires_at: expiry });
          // Storage failure cannot erase a result the server has already confirmed.
          saveRecovery(storage(), record, now());
        }
      }
      return update({ phase: 'status', result: outcome.result, error: null, canRetry: false });
    }
    if (checking && outcome.kind === 'failure' && outcome.error === 'not_found') {
      return update({ phase: 'not_found', error: 'not_found', canRetry: original !== null && liveRecord() });
    }
    if (outcome.kind === 'unknown') return update({ phase: 'unknown', error: outcome.error, canRetry: false });
    if (outcome.kind === 'unavailable') return update({ phase: snapshot.result ? 'unavailable' : 'unknown', error: outcome.error, canRetry: false });
    if (!checking && outcome.kind === 'failure') {
      // A definitive admission/business failure permits a later, explicit new attempt.
      if (!clearRecovery(storage(), slug)) return fail('storage_unavailable');
      record = null; original = null;
    }
    return fail(outcome.error);
  };
  const check = async (): Promise<OrderSnapshot> => {
    if (!load()) return snapshot;
    update({ phase: 'reconciling', error: null, canRetry: false });
    return receive(await transport.status(identity()), true);
  };
  const write = async (): Promise<OrderSnapshot> => {
    if (!liveRecord() || !original) return snapshot;
    update({ phase: 'submitting', error: null, canRetry: false });
    const outcome = await transport.submit(identity(), original);
    receive(outcome, false);
    // Reads are safe to repeat. An uncertain write is never automatically repeated.
    return outcome.kind === 'unknown' ? check() : snapshot;
  };
  const run = (operation: () => Promise<OrderSnapshot>): Promise<OrderSnapshot> => {
    if (inFlight) return inFlight;
    // Defer operation until the promise is assigned so synchronous observers cannot re-enter.
    inFlight = Promise.resolve().then(operation).catch(() => fail('invalid_request')).finally(() => { inFlight = null; });
    return inFlight;
  };
  return Object.freeze({
    getSnapshot: () => snapshot,
    subscribe(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; },
    recover: () => run(check),
    refresh: () => run(check),
    submit: (order: WebOrder) => run(async () => {
      // A saved or active identity takes precedence over any newly supplied cart.
      if (record) return check();
      const stored = readRecovery(storage(), slug, now());
      if (stored.kind !== 'missing') { load(); return record ? check() : snapshot; }
      const frozen = normalizeWebOrder(order);
      let created: RecoveryRecord;
      try { created = createOrderIdentity(slug, now(), options.cryptoImpl); }
      catch (error) { return fail(error instanceof OrderIdentityError ? 'crypto_unavailable' : 'invalid_request'); }
      if (!saveRecovery(storage(), created, now())) return fail('storage_unavailable');
      record = created; original = frozen;
      update({ recovered: false, result: null });
      return write();
    }),
    retry: () => run(async () => {
      if (!snapshot.canRetry || !original || !liveRecord()) return snapshot;
      // Reconcile again immediately before the owner's explicit retry, using the same capability.
      await check();
      return snapshot.phase === 'not_found' && snapshot.canRetry ? write() : snapshot;
    }),
  });
}
