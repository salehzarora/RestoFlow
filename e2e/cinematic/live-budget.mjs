// Reuse the unchanged canonical measurer, caps and response-by-response Brotli.
// Genuine local service HTML/chunks only; no fixture substitution or lazy load.
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { channel as diagnosticChannel } from 'node:diagnostics_channel';
import { STOREFRONT_URL, assertEphemeralEnvironment } from './service.mjs';
const liveBudgetLane = { lane: 'actual ephemeral live application', method: 'unchanged storefront/scripts/measure-firstload.mjs and budgets.mjs' };
const canonicalRoute = value => typeof value === 'string' && /^\/(?:(?:ar|he|en)\/)?s\/maps-burger\/(?:menu|search|cart|checkout|review)$/.test(value) ? value : null;
const httpNumber = value => Number.isInteger(value) && value >= 0 && value <= 599 ? value : null;
// Observe the existing readiness connection and first measured request only.
// No fetch/dispatcher/socket operation is replaced, retried or configured here.
export function observeLiveBudgetTransport({ channel = diagnosticChannel, now = Date.now } = {}) {
  const began = now(), events = [], sockets = new Map(), requests = new WeakMap(), subscriptions = [];
  let phase = 'startup', firstMeasured = null, firstTerminal = false, stopped = false, overflow = 0, unavailable = 0, requestCount = 0;
  const add = value => { if (events.length < 64) events.push({ ms: Math.max(0, now() - began), ...value }); else overflow++; };
  const state = socket => ({ destroyed: typeof socket.destroyed === 'boolean' ? socket.destroyed : null,
    readableEnded: typeof socket.readableEnded === 'boolean' ? socket.readableEnded : null,
    writableEnded: typeof socket.writableEnded === 'boolean' ? socket.writableEnded : null });
  const socketRecord = socket => {
    if (!socket || socket.remoteAddress !== '127.0.0.1' || socket.remotePort !== 3000) return null;
    if (sockets.has(socket)) return sockets.get(socket);
    if (sockets.size >= (phase === 'startup' ? 8 : 9)) { overflow++; return null; }
    const record = { label: `c${sockets.size + 1}`, startupUsed: false, closed: false, onClose: null };
    record.onClose = hadError => { try { record.closed = true; add({ event: 'socket-close', phase, connection: record.label, hadError: hadError === true, ...state(socket) }); } catch { unavailable++; } };
    sockets.set(socket, record); socket.on('close', record.onClose);
    return record;
  };
  const admitted = request => {
    if (!request || request.origin !== STOREFRONT_URL) return null;
    if (requests.has(request)) return requests.get(request);
    if (phase === 'measure' && firstMeasured !== null) return null;
    if (requestCount >= (phase === 'startup' ? 16 : 17)) { overflow++; return null; }
    requests.set(request, { label: `r${++requestCount}`, phase });
    if (phase === 'measure') firstMeasured = request;
    return requests.get(request);
  };
  const subscribe = (name, listener) => {
    const source = channel(name), guarded = value => { if (!stopped) { try { listener(value); } catch { unavailable++; } } };
    source.subscribe(guarded); subscriptions.push([source, guarded]);
  };
  subscribe('undici:client:connected', ({ socket }) => {
    if (phase === 'measure' && firstTerminal) return;
    const record = socketRecord(socket);
    if (record) add({ event: 'connected', phase, connection: record.label, ...state(socket) });
  });
  subscribe('undici:client:sendHeaders', ({ request, socket }) => {
    const id = admitted(request); if (!id) return;
    const record = socketRecord(socket); if (!record) return;
    add({ event: 'send', phase, request: id.label, requestPhase: id.phase, connection: record.label,
      reusedFromStartup: phase === 'measure' && record.startupUsed, previouslyClosed: record.closed, ...state(socket) });
    if (phase === 'startup') record.startupUsed = true;
  });
  subscribe('undici:request:error', ({ request, error }) => {
    const id = admitted(request); if (id) add({ event: 'request-error', phase, request: id.label, requestPhase: id.phase,
      error: liveBudgetTransportError({ name: error?.name, cause: error }) });
    if (request === firstMeasured) firstTerminal = true;
  });
  subscribe('undici:request:trailers', ({ request }) => {
    const id = admitted(request); if (id) add({ event: 'request-complete', phase, request: id.label, requestPhase: id.phase });
    if (request === firstMeasured) firstTerminal = true;
  });
  return {
    beginMeasure() { phase = 'measure'; add({ event: 'first-live-measurement-started', phase }); },
    snapshot() { return { scope: 'passive-loopback-storefront-readiness-and-first-measurement',
      phase, overflow, unavailable, events: events.map(value => ({ ...value })) }; },
    stop() {
      if (stopped) return; stopped = true;
      for (const [source, listener] of subscriptions) { try { source.unsubscribe(listener); } catch { unavailable++; } }
      for (const [socket, record] of sockets) { try { socket.off('close', record.onClose); } catch { unavailable++; } }
    },
  };
}
export function liveBudgetTransportError(error) {
  const names = new Set(['Error','TypeError','RangeError','AbortError','TimeoutError','AssertionError','AggregateError',
    'SocketError','ConnectTimeoutError','HeadersTimeoutError','BodyTimeoutError','RequestAbortedError']);
  const codes = new Set(['ECONNREFUSED','ECONNRESET','ECONNABORTED','EPIPE','ETIMEDOUT','ENOTFOUND','EAI_AGAIN',
    'UND_ERR_SOCKET','UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','UND_ERR_BODY_TIMEOUT','UND_ERR_ABORTED','ABORT_ERR','ERR_ASSERTION']);
  return { name: names.has(error?.name) ? error.name : 'unclassified',
    causeName: names.has(error?.cause?.name) ? error.cause.name : 'unclassified',
    causeCode: codes.has(error?.cause?.code) ? error.cause.code : 'unclassified' };
}
export function retainLiveBudgetFailure(error, { phase, route, mapped, status, socketObservation }, persist) {
  const receipt = { status: 'FAIL', ...liveBudgetLane,
    phase: ['fetch','body-read','http-status'].includes(phase) ? phase : 'unclassified',
    failedRoute: canonicalRoute(route), httpStatus: httpNumber(status),
    mapped: mapped.map(row => ({ canonicalRoute: canonicalRoute(row.canonicalRoute), status: httpNumber(row.status) })),
    rows: [], problems: [phase === 'http-status' ? 'http-status-error' : 'transport-error'], complete: false,
    transportError: liveBudgetTransportError(error), ...(socketObservation ? { socketObservation } : {}) };
  try { persist(receipt); } catch { /* Evidence failure never replaces the original transport/assertion error. */ }
  throw error;
}

export async function measureLiveBudget(root, privateDir, publicDir, slug, transportObservation) {
  assertEphemeralEnvironment();
  assert.match(slug, /^cinematic-[a-z0-9-]+$/);
  const { measure, checkBudgets } = await import(pathToFileURL(resolve(root, 'storefront/scripts/measure-firstload.mjs')));
  const { ROUTES } = await import(pathToFileURL(resolve(root, 'storefront/scripts/budgets.mjs')));
  const out = resolve(privateDir, 'live-budget'); mkdirSync(out, { recursive: true });
  cpSync(resolve(root, 'storefront/.next/static'), resolve(out, '_next/static'), { recursive: true });
  const mapped = [];
  transportObservation?.beginMeasure();
  for (const route of ROUTES.filter(row => /\/(menu|search|cart|checkout|review)$/.test(row.route))) {
    const actualRoute = route.route.replace('maps-burger', slug);
    const retain = (error, phase, status = null) => retainLiveBudgetFailure(error,
      { phase, route: route.route, mapped, status, socketObservation: transportObservation?.snapshot() },
      receipt => writeFileSync(resolve(publicDir, 'live-firstload-budget.json'), JSON.stringify(receipt, null, 2)));
    let response;
    try { response = await fetch(STOREFRONT_URL + actualRoute, { redirect: 'error', signal: AbortSignal.timeout(30000) }); }
    catch (error) { retain(error, 'fetch'); }
    try { assert.equal(response.status, 200, 'Actual live route must render before measurement'); }
    catch (error) { retain(error, 'http-status', response.status); }
    let text;
    try { text = await response.text(); }
    catch (error) { retain(error, 'body-read', response.status); }
    const file = resolve(out, route.file); mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, text); mapped.push({ canonicalRoute: route.route, actualRoute, status: response.status });
  }
  const rows = measure(out), problems = checkBudgets(rows);
  const receipt = { status: problems.length ? 'FAIL' : 'PASS', ...liveBudgetLane, mapped, rows, problems, complete: true,
    ...(transportObservation ? { socketObservation: transportObservation.snapshot() } : {}) };
  writeFileSync(resolve(publicDir, 'live-firstload-budget.json'), JSON.stringify(receipt, null, 2));
  return receipt;
}
