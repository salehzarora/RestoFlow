// Reuse the unchanged canonical measurer, caps and response-by-response Brotli.
// Genuine local service HTML/chunks only; no fixture substitution or lazy load.
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { STOREFRONT_URL, assertEphemeralEnvironment } from './service.mjs';
const liveBudgetLane = { lane: 'actual ephemeral live application', method: 'unchanged storefront/scripts/measure-firstload.mjs and budgets.mjs' };
const canonicalRoute = value => typeof value === 'string' && /^\/(?:(?:ar|he|en)\/)?s\/maps-burger\/(?:menu|search|cart|checkout|review)$/.test(value) ? value : null;
const httpNumber = value => Number.isInteger(value) && value >= 0 && value <= 599 ? value : null;
export function liveBudgetTransportError(error) {
  const names = new Set(['Error','TypeError','RangeError','AbortError','TimeoutError','AssertionError','AggregateError',
    'SocketError','ConnectTimeoutError','HeadersTimeoutError','BodyTimeoutError','RequestAbortedError']);
  const codes = new Set(['ECONNREFUSED','ECONNRESET','ECONNABORTED','EPIPE','ETIMEDOUT','ENOTFOUND','EAI_AGAIN',
    'UND_ERR_SOCKET','UND_ERR_CONNECT_TIMEOUT','UND_ERR_HEADERS_TIMEOUT','UND_ERR_BODY_TIMEOUT','UND_ERR_ABORTED','ABORT_ERR','ERR_ASSERTION']);
  return { name: names.has(error?.name) ? error.name : 'unclassified',
    causeName: names.has(error?.cause?.name) ? error.cause.name : 'unclassified',
    causeCode: codes.has(error?.cause?.code) ? error.cause.code : 'unclassified' };
}
export function retainLiveBudgetFailure(error, { phase, route, mapped, status }, persist) {
  const receipt = { status: 'FAIL', ...liveBudgetLane,
    phase: ['fetch','body-read','http-status'].includes(phase) ? phase : 'unclassified',
    failedRoute: canonicalRoute(route), httpStatus: httpNumber(status),
    mapped: mapped.map(row => ({ canonicalRoute: canonicalRoute(row.canonicalRoute), status: httpNumber(row.status) })),
    rows: [], problems: [phase === 'http-status' ? 'http-status-error' : 'transport-error'], complete: false,
    transportError: liveBudgetTransportError(error) };
  try { persist(receipt); } catch { /* Evidence failure never replaces the original transport/assertion error. */ }
  throw error;
}

export async function measureLiveBudget(root, privateDir, publicDir, slug) {
  assertEphemeralEnvironment();
  assert.match(slug, /^cinematic-[a-z0-9-]+$/);
  const { measure, checkBudgets } = await import(pathToFileURL(resolve(root, 'storefront/scripts/measure-firstload.mjs')));
  const { ROUTES } = await import(pathToFileURL(resolve(root, 'storefront/scripts/budgets.mjs')));
  const out = resolve(privateDir, 'live-budget'); mkdirSync(out, { recursive: true });
  cpSync(resolve(root, 'storefront/.next/static'), resolve(out, '_next/static'), { recursive: true });
  const mapped = [];
  for (const route of ROUTES.filter(row => /\/(menu|search|cart|checkout|review)$/.test(row.route))) {
    const actualRoute = route.route.replace('maps-burger', slug);
    const retain = (error, phase, status = null) => retainLiveBudgetFailure(error,
      { phase, route: route.route, mapped, status },
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
  const receipt = { status: problems.length ? 'FAIL' : 'PASS', ...liveBudgetLane, mapped, rows, problems, complete: true };
  writeFileSync(resolve(publicDir, 'live-firstload-budget.json'), JSON.stringify(receipt, null, 2));
  return receipt;
}
