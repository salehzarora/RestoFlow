import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { identity, order, result, response, REQUEST_ID } from './sf-web-orders-fixtures.mjs';
const { createOrderTransport, decodeOrderResponse, WEB_ORDER_ORIGIN, WEB_ORDER_ENDPOINT, OrderConfigurationError, WebOrderValidationError } = await import('../src/orders/index.ts');
const { MAX_BODY_BYTES } = await import('../src/orders/contract.ts');

test('transport uses the exact Edge endpoint, no ambient credentials and only two public headers', async () => {
  const calls = [];
  const transport = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async (...args) => { calls.push(args); return response(result()); } });
  const outcome = await transport.submit(identity(), order());
  assert.equal(outcome.kind, 'known'); assert.equal(outcome.result.status, 'pending');
  const [url, init] = calls[0];
  assert.equal(url, WEB_ORDER_ENDPOINT); assert.equal(init.method, 'POST');
  assert.deepEqual(init.headers, { 'Content-Type': 'application/json', Accept: 'application/json' });
  assert.equal(init.credentials, 'omit'); assert.equal(init.cache, 'no-store'); assert.equal(init.redirect, 'error'); assert.equal(init.referrerPolicy, 'no-referrer'); assert.equal(init.mode, 'cors'); assert.ok(init.signal instanceof AbortSignal);
  assert.deepEqual(JSON.parse(init.body), { action: 'submit', ...identity(), order: order() });
  assert.equal(calls.length, 1);
});
test('status sends only identity and capability in POST body, never in URL', async () => {
  let captured;
  const transport = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async (url, init) => { captured = { url, init }; return response(result('accepted')); } });
  assert.equal((await transport.status(identity())).result.status, 'accepted');
  assert.deepEqual(JSON.parse(captured.init.body), { action: 'status', ...identity() });
  assert.equal(captured.url.includes(identity().status_token), false); assert.equal(captured.url.includes(REQUEST_ID), false);
});
test('origin accepts only the configured exact HTTPS project origin', () => {
  for (const origin of ['https://other.supabase.co', WEB_ORDER_ORIGIN + '/', WEB_ORDER_ORIGIN + '/functions/v1', WEB_ORDER_ORIGIN.toUpperCase(), ' http://oqmevrndtivqxgyvcmwy.supabase.co', WEB_ORDER_ORIGIN + '?x=1', '']) assert.throws(() => createOrderTransport({ origin }), OrderConfigurationError);
  for (const timeoutMs of [0, -1, 30_001, 1.5, NaN]) assert.throws(() => createOrderTransport({ origin: WEB_ORDER_ORIGIN, timeoutMs }), OrderConfigurationError);
});
test('invalid identity or body is rejected before network I/O', async () => {
  let calls = 0;
  const transport = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => { calls++; return response(result()); } });
  await assert.rejects(transport.submit({ ...identity(), request_id: 'bad' }, order()), WebOrderValidationError);
  await assert.rejects(transport.submit(identity(), order({ total_minor: 0 })), WebOrderValidationError);
  await assert.rejects(transport.status({ ...identity(), token: 'extra' }), WebOrderValidationError);
  assert.equal(calls, 0);
});
test('all real states and authoritative integer totals decode without local arithmetic', () => {
  for (const status of ['pending', 'accepted', 'rejected', 'expired']) {
    const decoded = decodeOrderResponse(result(status), 200, identity(), 'status');
    assert.equal(decoded.result.status, status); assert.equal(decoded.result.totals.grand_total_minor, 1180);
    assert.ok(Object.isFrozen(decoded.result) && Object.isFrozen(decoded.result.totals));
  }
});
test('future customer-designated rejection reasons decode unchanged, while old responses stay field-free', () => {
  for (const reason of ['الصنف غير متوفر', 'הפריט אזל', 'Item unavailable', '🍔'.repeat(240), '<img src=x onerror="alert(1)">']) {
    const decoded = decodeOrderResponse(result('rejected', { customer_rejection_reason: reason }), 200, identity(), 'status');
    assert.equal(decoded.result.customer_rejection_reason, reason);
    assert.ok(Object.isFrozen(decoded.result));
  }
  for (const state of ['pending', 'accepted', 'rejected', 'expired']) {
    assert.equal(Object.hasOwn(decodeOrderResponse(result(state), 200, identity(), 'status').result, 'customer_rejection_reason'), false);
  }
});
test('customer rejection reason is rejected outside its exact bounded, rejected-only contract', () => {
  for (const customer_rejection_reason of [null, undefined, 1, true, {}, [], '', ' ', ' untrimmed', 'untrimmed ', '🍔'.repeat(241), 'x'.repeat(241), 'A\nB', 'A\tB', 'A\rB', 'A\x00B', 'A\x7fB', '\ud800']) {
    assert.throws(() => decodeOrderResponse(result('rejected', { customer_rejection_reason }), 200, identity(), 'status'), WebOrderValidationError);
  }
  for (const state of ['pending', 'accepted', 'expired']) {
    assert.throws(() => decodeOrderResponse(result(state, { customer_rejection_reason: 'Do not expose here' }), 200, identity(), 'status'), WebOrderValidationError);
  }
  for (const extra of [{ reason: 'Staff only' }, { rejection_reason: 'Staff only' }, { customer_rejection_reason: 'Public', reason: 'Staff only' }]) {
    assert.throws(() => decodeOrderResponse(result('rejected', extra), 200, identity(), 'status'), WebOrderValidationError);
  }
  assert.throws(() => decodeOrderResponse({ ok: false, error: 'not_found', customer_rejection_reason: 'Private' }, 404, identity(), 'status'), WebOrderValidationError);
});
test('strict response decoding rejects mismatched IDs, unknown state, noninteger/invalid money and extras', () => {
  for (const value of [result('saved'), result('pending', { request_id: '22222222-2222-4222-8222-222222222222' }), result('pending', { expires_at: 'tomorrow' }), result('pending', { replayed: 'yes' }), result('pending', { customer: 'PRIVATE' }), result('pending', { totals: { currency_code: 'USD', subtotal_minor: 1000, tax_total_minor: 180, grand_total_minor: 1180 } }), result('pending', { totals: { currency_code: 'ILS', subtotal_minor: 1000.5, tax_total_minor: 180, grand_total_minor: 1180 } }), result('pending', { totals: { currency_code: 'ILS', subtotal_minor: 1000, tax_total_minor: 180, grand_total_minor: 1000 } }), result('pending', { totals: { currency_code: 'ILS', subtotal_minor: 10_000_001, tax_total_minor: 0, grand_total_minor: 10_000_001 } }), result('pending', { totals: { ...result().totals, service_key: 'PRIVATE' } })]) assert.throws(() => decodeOrderResponse(value, 200, identity(), 'submit'), WebOrderValidationError);
  assert.throws(() => decodeOrderResponse(result(), 503, identity(), 'submit'), WebOrderValidationError);
});
test('business failures retain fixed error codes with exact HTTP mapping', () => {
  for (const [error, status] of Object.entries({ invalid_request: 400, not_found: 404, ordering_unavailable: 503, idempotency_conflict: 409, item_unavailable: 422, modifier_selection_invalid: 422, menu_unavailable: 422, rate_limited: 429, capacity_reached: 429 })) {
    assert.deepEqual(decodeOrderResponse({ ok: false, error }, status, identity(), 'submit'), { kind: 'failure', error });
    assert.throws(() => decodeOrderResponse({ ok: false, error }, 200, identity(), 'submit'), WebOrderValidationError);
  }
  assert.throws(() => decodeOrderResponse({ ok: false, error: 'SQLSTATE PRIVATE' }, 500, identity(), 'submit'), WebOrderValidationError);
});
test('uncertain envelopes require the matching request ID and uncertainty flag', () => {
  assert.equal(decodeOrderResponse({ ok: false, error: 'submission_outcome_unknown', request_id: REQUEST_ID, uncertain: true }, 502, identity(), 'submit').kind, 'unknown');
  assert.equal(decodeOrderResponse({ ok: false, error: 'status_unavailable', request_id: REQUEST_ID, uncertain: false }, 503, identity(), 'status').kind, 'unavailable');
  assert.equal(decodeOrderResponse({ ok: false, error: 'service_unavailable' }, 503, identity(), 'submit').kind, 'unknown');
  for (const value of [{ ok: false, error: 'submission_outcome_unknown', request_id: REQUEST_ID, uncertain: false }, { ok: false, error: 'submission_outcome_unknown', uncertain: true }, { ok: false, error: 'not_found', uncertain: true }]) assert.throws(() => decodeOrderResponse(value, 502, identity(), 'submit'), WebOrderValidationError);
});
test('network failures and lost responses are unknown, with no automatic write repeat', async () => {
  let calls = 0;
  const transport = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => { calls++; throw new Error('PRIVATE'); } });
  assert.deepEqual(await transport.submit(identity(), order()), { kind: 'unknown', error: 'submission_outcome_unknown' });
  assert.equal(calls, 1);
  assert.deepEqual(await transport.status(identity()), { kind: 'unavailable', error: 'status_unavailable' }); assert.equal(calls, 2);
});
test('timeout bounds both fetch and response-body reads even if upstream ignores abort', async () => {
  let aborted = false;
  const timeoutFetch = createOrderTransport({ origin: WEB_ORDER_ORIGIN, timeoutMs: 10, fetchImpl: async (_url, init) => { init.signal.addEventListener('abort', () => { aborted = true; }); return new Promise(() => {}); } });
  assert.equal((await timeoutFetch.submit(identity(), order())).kind, 'unknown'); assert.equal(aborted, true);
  const slowBody = createOrderTransport({ origin: WEB_ORDER_ORIGIN, timeoutMs: 10, fetchImpl: async () => new Response(new ReadableStream({ start() {} }), { headers: { 'Content-Type': 'application/json' } }) });
  assert.equal((await slowBody.status(identity())).kind, 'unavailable');
});
test('bounded strict UTF-8 JSON rejects duplicate decoded keys, BOM, malformed JSON and unknown fields', async () => {
  const valid = JSON.stringify(result());
  for (const body of [valid.replace('"ok":true', '"ok":false,"\\u006fk":true'), '\ufeff' + valid, '{bad', valid.slice(0, -1) + ',"status_token":"PRIVATE"}', new Uint8Array([0xc0, 0xaf])]) {
    const transport = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => new Response(body, { headers: { 'Content-Type': 'application/json' } }) });
    assert.equal((await transport.submit(identity(), order())).kind, 'unknown');
  }
});
test('response limits apply to actual streamed bytes, declared size and content type', async () => {
  const cases = [() => response(result(), 200, { 'Content-Length': String(MAX_BODY_BYTES + 1) }), () => response(' '.repeat(MAX_BODY_BYTES + 1)), () => response(result(), 200, { 'Content-Type': 'text/html' }), () => response(result(), 200, { 'Content-Length': 'invalid' })];
  for (const make of cases) {
    const transport = createOrderTransport({ origin: WEB_ORDER_ORIGIN, fetchImpl: async () => make() });
    assert.equal((await transport.status(identity())).kind, 'unavailable');
  }
});
