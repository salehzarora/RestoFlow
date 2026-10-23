import { MAX_BODY_BYTES, WEB_ORDER_ENDPOINT, WEB_ORDER_ORIGIN } from './contract';
import type { OrderIdentity, OrderOutcome, OrderTransport, WebOrder, WebOrderErrorCode, WebOrderResult, WebOrderStatus } from './contract';
import { parseOrderJson } from './json';
import { exactObject, invalid, normalizeWebOrder, validateIdentity } from './validation';
import { decodeAcceptanceEta } from './acceptanceEta';

export const ORDER_RESPONSE_VERSION_HEADER = 'X-BIZBOT-Order-Response-Version';

const FAILURE_STATUS: Readonly<Record<string, number>> = {
  invalid_request: 400, not_found: 404, ordering_unavailable: 503, idempotency_conflict: 409,
  item_unavailable: 422, modifier_selection_invalid: 422, menu_unavailable: 422,
  rate_limited: 429, capacity_reached: 429, invalid_json: 400, payload_too_large: 413,
  unsupported_media_type: 415, origin_not_allowed: 403, invalid_preflight: 403, method_not_allowed: 405,
};
const STATUSES: readonly string[] = ['pending', 'accepted', 'rejected', 'expired'];
export class OrderConfigurationError extends Error {
  constructor() { super('configuration_invalid'); this.name = 'OrderConfigurationError'; }
}
export function validateOrderOrigin(origin: string): typeof WEB_ORDER_ORIGIN {
  if (origin !== WEB_ORDER_ORIGIN) throw new OrderConfigurationError();
  return WEB_ORDER_ORIGIN;
}
/** Exact response projection, including rejection of extra customer/credential fields. */
export function decodeOrderResponse(value: unknown, status: number, identity: OrderIdentity, action: 'submit' | 'status', representation: 'legacy' | '2' = 'legacy'): OrderOutcome {
  const etaKeys = action === 'status' && representation === '2' ? ['acceptance_eta'] : [];
  const object = exactObject(value, ['ok'], ['request_id', 'status', 'expires_at', 'totals', 'replayed', 'customer_rejection_reason', 'error', 'uncertain', ...etaKeys]);
  if (object.ok === true) {
    exactObject(object, ['ok', 'request_id', 'status', 'expires_at', 'totals', 'replayed'], ['customer_rejection_reason', ...etaKeys]);
    if (status !== 200 || object.request_id !== identity.request_id || typeof object.status !== 'string' || !STATUSES.includes(object.status) || typeof object.replayed !== 'boolean') invalid();
    if (typeof object.expires_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(object.expires_at) || !Number.isFinite(Date.parse(object.expires_at))) invalid();
    const totals = exactObject(object.totals, ['currency_code', 'subtotal_minor', 'tax_total_minor', 'grand_total_minor']);
    const amounts = [totals.subtotal_minor, totals.tax_total_minor, totals.grand_total_minor];
    if (totals.currency_code !== 'ILS' || amounts.some((amount) => typeof amount !== 'number' || !Number.isSafeInteger(amount) || amount < 0 || amount > 10_000_000)) invalid();
    const subtotal_minor = totals.subtotal_minor as number;
    const tax_total_minor = totals.tax_total_minor as number;
    const grand_total_minor = totals.grand_total_minor as number;
    if (subtotal_minor + tax_total_minor !== grand_total_minor) invalid();
    const hasReason = Object.hasOwn(object, 'customer_rejection_reason');
    const reason = object.customer_rejection_reason;
    if (hasReason && (object.status !== 'rejected' || typeof reason !== 'string' || reason !== reason.trim() || [...reason].length < 1 || [...reason].length > 240 || /[\x00-\x1f\x7f\p{Cs}]/u.test(reason))) invalid();
    const hasEta = Object.hasOwn(object, 'acceptance_eta');
    if (hasEta && object.status !== 'accepted') invalid();
    const acceptance_eta = hasEta ? decodeAcceptanceEta(object.acceptance_eta) : undefined;
    const result: WebOrderResult = Object.freeze({ ok: true, request_id: identity.request_id, status: object.status as WebOrderStatus, expires_at: object.expires_at, totals: Object.freeze({ currency_code: 'ILS', subtotal_minor, tax_total_minor, grand_total_minor }), replayed: object.replayed, ...(hasReason ? { customer_rejection_reason: reason as string } : {}), ...(acceptance_eta ? { acceptance_eta } : {}) });
    return { kind: 'known', result };
  }
  exactObject(object, ['ok', 'error'], ['request_id', 'uncertain']);
  if (object.ok !== false || typeof object.error !== 'string') invalid();
  if (Object.hasOwn(object, 'request_id') && object.request_id !== identity.request_id) invalid();
  if (object.error === 'submission_outcome_unknown') {
    if (action !== 'submit' || ![502, 503].includes(status) || object.request_id !== identity.request_id || object.uncertain !== true) invalid();
    return { kind: 'unknown', error: 'submission_outcome_unknown' };
  }
  if (object.error === 'status_unavailable') {
    if (action !== 'status' || ![502, 503].includes(status) || object.uncertain !== false) invalid();
    return { kind: 'unavailable', error: 'status_unavailable' };
  }
  // The Edge's outer catch is not a proof that a submit never committed.
  if (object.error === 'service_unavailable' && status === 503 && !Object.hasOwn(object, 'uncertain')) {
    return action === 'submit' ? { kind: 'unknown', error: 'submission_outcome_unknown' } : { kind: 'unavailable', error: 'status_unavailable' };
  }
  if (!Object.hasOwn(FAILURE_STATUS, object.error) || FAILURE_STATUS[object.error] !== status || (Object.hasOwn(object, 'uncertain') && object.uncertain !== false)) invalid();
  return { kind: 'failure', error: object.error as WebOrderErrorCode };
}

async function responseJson(response: Response): Promise<unknown> {
  const contentType = response.headers.get('content-type') ?? '';
  if (!/^application\/json(?:\s*;\s*charset\s*=\s*(?:utf-8|"utf-8"))?\s*$/i.test(contentType)) invalid();
  const declared = response.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > MAX_BODY_BYTES)) invalid();
  if (!response.body) invalid();
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) { void reader.cancel().catch(() => {}); invalid(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return parseOrderJson(new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes));
}

export interface OrderTransportOptions {
  readonly origin: string;
  readonly fetchImpl?: typeof fetch;
  readonly timeoutMs?: number;
}
/** One request per call. It never retries writes or forwards ambient credentials. */
export function createOrderTransport({ origin, fetchImpl = globalThis.fetch, timeoutMs = 12_000 }: OrderTransportOptions): OrderTransport {
  validateOrderOrigin(origin);
  if (typeof fetchImpl !== 'function' || !Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30_000) throw new OrderConfigurationError();
  const send = async (action: 'submit' | 'status', supplied: OrderIdentity, order?: WebOrder): Promise<OrderOutcome> => {
    const identity = validateIdentity(supplied);
    const body = JSON.stringify({ action, ...identity, ...(action === 'submit' ? { order: normalizeWebOrder(order) } : {}) });
    if (new TextEncoder().encode(body).byteLength > MAX_BODY_BYTES) invalid();
    const controller = new AbortController();
    let timer: ReturnType<typeof setTimeout> | undefined;
    const deadline = new Promise<never>((_, reject) => {
      timer = setTimeout(() => { controller.abort(); reject(new Error('request_timeout')); }, timeoutMs);
    });
    try {
      return await Promise.race([
        (async () => {
          const response = await fetchImpl(WEB_ORDER_ENDPOINT, {
            method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json', ...(action === 'status' ? { [ORDER_RESPONSE_VERSION_HEADER]: '2' } : {}) },
            body, credentials: 'omit', cache: 'no-store', redirect: 'error',
            referrerPolicy: 'no-referrer', mode: 'cors', signal: controller.signal,
          });
          // Never mask a missing/unsupported deployment by falling back to v1.
          if (action === 'status' && response.headers.get(ORDER_RESPONSE_VERSION_HEADER) !== '2') invalid();
          return decodeOrderResponse(await responseJson(response), response.status, identity, action, action === 'status' ? '2' : 'legacy');
        })(), deadline,
      ]);
    } catch {
      return action === 'submit' ? { kind: 'unknown', error: 'submission_outcome_unknown' } : { kind: 'unavailable', error: 'status_unavailable' };
    } finally { clearTimeout(timer); }
  };
  return Object.freeze({ submit: (identity: OrderIdentity, order: WebOrder) => send('submit', identity, order), status: (identity: OrderIdentity) => send('status', identity) });
}
