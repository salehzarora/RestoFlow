// BIZBOT-STOREFRONT-CINEMATIC-001B: fixed-enum diagnostics for the disposable
// publisher acceptance lane. Never serialize a response body, header collection,
// request, storage key, exception message, or raw runtime/gateway log.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, openSync, readSync, closeSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { request } from './service.mjs';

const stages = new Set(['authenticated_handler_probe', 'fixture_hero_publish']);
const applicationCodes = new Set(['published', 'invalid_request', 'unauthenticated',
  'permission_denied', 'internal_error', 'upstream_unavailable', 'engine_unavailable',
  'refused', 'ladder_next', 'method_not_allowed', 'unsupported_media_type']);
const runtimeCodes = new Set(['BOOT_ERROR', 'WORKER_ERROR', 'WORKER_LIMIT',
  'WORKER_RESOURCE_LIMIT', 'WORKER_REQUEST_CANCELLED', 'WORKER_SHUTDOWN',
  'EDGE_FUNCTION_ERROR', 'IDLE_TIMEOUT', 'FUNCTION_NOT_FOUND', 'INVALID_JWT', 'MISSING_JWT', 'RATE_LIMITED']);
const mimeTypes = new Set(['application/json', 'text/html', 'text/plain', 'application/octet-stream']);
const integer = (value, maximum) => Number.isInteger(value) && value >= 0 && value <= maximum ? value : null;
const fixedCode = (value, allowed) => typeof value === 'string' && allowed.has(value) ? value : 'unclassified';
const iso = () => new Date().toISOString();

export function responseEvidence(result, durationMs) {
  const mime = typeof result?.contentType === 'string' ? result.contentType.split(';')[0].trim().toLowerCase() : '';
  return {
    httpStatus: integer(result?.status, 599),
    contentType: mime === '' ? 'missing' : fixedCode(mime, mimeTypes),
    durationMs: integer(Math.round(durationMs), 120_000),
    runtimeCode: fixedCode(result?.runtimeCode, runtimeCodes),
    runtimeBodyCode: fixedCode(result?.data?.code, runtimeCodes),
    applicationStatus: fixedCode(result?.data?.status, applicationCodes),
    retryable: typeof result?.data?.retryable === 'boolean' ? result.data.retryable : null,
    uncertain: typeof result?.data?.uncertain === 'boolean' ? result.data.uncertain : null,
  };
}

// This exact response is emitted only AFTER GoTrue verifies the real user, and
// BEFORE any media lookup, engine initialization, staging or publication.
export function isAuthenticatedReadiness(result) {
  const value = result?.data;
  return result?.status === 400 && value !== null && typeof value === 'object'
    && Object.keys(value).sort().join(',') === 'field,ok,reason,status'
    && value.ok === false && value.status === 'invalid_request'
    && value.field === 'request_id' && value.reason === 'missing';
}

export function createPublisherDiagnostics(publicDir) {
  const path = resolve(publicDir, 'publisher-requests.json');
  const receipt = { scope: 'ephemeral synthetic services', startedAt: iso(),
    publicationRetries: 0, events: [] };
  const flush = () => writeFileSync(path, `${JSON.stringify(receipt, null, 2)}\n`);
  flush();
  return {
    async observe(stage, operation) {
      assert.ok(stages.has(stage), 'Unknown diagnostic stage');
      const started = performance.now();
      const event = { stage, startedAt: iso(), state: 'started' };
      receipt.events.push(event); flush();
      try {
        const result = await operation();
        Object.assign(event, responseEvidence(result, performance.now() - started), { state: 'response', endedAt: iso() });
        flush();
        return result;
      } catch {
        Object.assign(event, { state: 'transport_failure', endedAt: iso(), durationMs: integer(Math.round(performance.now() - started), 120_000) });
        flush();
        throw new Error(`Publisher ${stage} transport failure; safe evidence retained`);
      }
    },
  };
}

export async function waitForAuthenticatedPublisher(fixture, token, diagnostics,
  { send = request, pause = delay } = {}) {
  // Startup polling ONLY. The body deliberately cannot pass validation, so no
  // request identity, media path, or mutation can be created by any attempt.
  for (let attempt = 0; attempt < 6; attempt += 1) {
    let result;
    try {
      result = await diagnostics.observe('authenticated_handler_probe', () => send(fixture, token,
        '/functions/v1/storefront-media-publish', { method: 'POST', body: {}, timeoutMs: 3000 }));
    } catch {
      if (attempt === 5) throw new Error('Authenticated publisher startup did not complete; diagnostic transport evidence retained');
      await pause(1000); continue;
    }
    if (isAuthenticatedReadiness(result)) return;
    if (![502, 503, 504].includes(result.status) || attempt === 5) {
      throw new Error('Authenticated publisher readiness contract failed; safe HTTP evidence retained');
    }
    await pause(1000);
  }
}

const logPatterns = Object.freeze({
  runtime_boot_error: /BOOT_ERROR|worker boot error|failed to boot/i,
  runtime_worker_error: /WORKER_ERROR|worker exited due to an error/i,
  runtime_invalid_worker_response: /InvalidWorkerResponse|failed to get response from user worker|failed to send request to user worker/i,
  runtime_cpu_limit: /CPU time limit|cpu_time_limit|CPUTime/i,
  runtime_memory_limit: /memory limit|memory_limit|MemoryLimit/i,
  runtime_wall_clock_limit: /wall.clock.*(?:limit|timeout)|WallClockTime/i,
  runtime_resource_limit: /WORKER_RESOURCE_LIMIT|WORKER_LIMIT/i,
  runtime_worker_shutdown: /worker.*(?:shutdown|shutting down)|earlyDrop/i,
  runtime_request_cancelled: /WORKER_REQUEST_CANCELLED|request has been cancelled/i,
  runtime_import_error: /module not found|failed to resolve|failed to load module|failed to fetch module/i,
  runtime_wasm_trap: /RuntimeError:.*(?:unreachable|out of bounds)|wasm.*(?:trap|unreachable)/i,
  gateway_upstream_refused: /connect\(\) failed|connection refused|ECONNREFUSED/i,
  gateway_upstream_closed: /upstream.*(?:prematurely closed|reset)|connection reset by peer/i,
  gateway_upstream_timeout: /upstream timed out|ETIMEDOUT/i,
  handler_internal_error: /storefront-media-publish internal_error:/,
  handler_retiring_worker: /storefront-media-publish: retiring a worker whose engine is not trusted/,
});

export function summarizePrivateLog(text) {
  // Counts are intentionally coarse; they are correlated to the fixed stage
  // timestamps, not asserted as an exact request ID or a causal conclusion.
  const lines = String(text).split('\n');
  return { classifications: Object.fromEntries(Object.entries(logPatterns).map(([name, pattern]) =>
    [name, Math.min(9999, lines.filter(line => pattern.test(line)).length)])) };
}

export function correlateLogWindows(text, events) {
  const timestamped = String(text).split('\n').map(line => {
    const match = /^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z)\s/.exec(line);
    return { time: match ? Date.parse(match[1]) : NaN, line };
  }).filter(value => Number.isFinite(value.time));
  const timestamp = value => typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/.test(value);
  return events.slice(0, 8).filter(event => stages.has(event.stage) && timestamp(event.startedAt) && timestamp(event.endedAt)).map(event => {
    const from = Date.parse(event.startedAt); const to = Date.parse(event.endedAt);
    const selected = timestamped.filter(value => value.time >= from && value.time <= to + 1000);
    return { stage: event.stage, startedAt: event.startedAt, endedAt: event.endedAt,
      timestampedLines: selected.length, ...summarizePrivateLog(selected.map(value => value.line).join('\n')) };
  });
}

function privateLogTail(path) {
  const bytes = statSync(path).size; const length = Math.min(bytes, 4 * 1024 * 1024);
  const buffer = Buffer.alloc(length); const fd = openSync(path, 'r');
  try { readSync(fd, buffer, 0, length, bytes - length); } finally { closeSync(fd); }
  return buffer.toString('utf8');
}

const startupPatterns = Object.freeze({
  image_pull_failed: /failed to pull|error pulling|pull access denied|manifest unknown/i,
  registry_rate_limited: /toomanyrequests|rate limit.*(?:registry|pull)|429 Too Many Requests/i,
  network_timeout: /i\/o timeout|TLS handshake timeout|context deadline exceeded|ETIMEDOUT/i,
  network_resolution: /no such host|temporary failure in name resolution|ENOTFOUND/i,
  disk_full: /no space left on device|disk quota exceeded/i,
  docker_unavailable: /cannot connect to the Docker daemon|docker daemon is not running/i,
  port_conflict: /port is already allocated|address already in use/i,
  container_unhealthy: /container.*(?:unhealthy|not healthy)|failed to start.*container/i,
  health_timeout: /health check.*(?:fail|timeout)|timed out.*health/i,
  sql_syntax: /SQLSTATE 42601/,
  sql_missing_relation: /SQLSTATE 42P01/,
  sql_missing_function: /SQLSTATE 42883/,
  sql_permission: /SQLSTATE 42501/,
  sql_constraint: /SQLSTATE 23(?:502|503|505|514)/,
  database_started: /Starting database/i,
  migrations_started: /Applying migration/i,
  containers_started: /Starting containers/i,
  health_checks_started: /Waiting for health checks/i,
  stack_started: /Started supabase local development setup/i,
});

export function summarizeStartupLog(text) {
  // Export fixed enum counts only. Even startup errors can embed local keys,
  // database URLs, environment values or SQL data; never retain raw lines.
  const lines = String(text).split('\n');
  return { classifications: Object.fromEntries(Object.entries(startupPatterns).map(([name, pattern]) =>
    [name, Math.min(9999, lines.filter(line => pattern.test(line)).length)])) };
}

export function capturePublisherRuntime(privateDir, publicDir) {
  const startupPath = resolve(privateDir, 'start.log');
  if (existsSync(startupPath)) {
    writeFileSync(resolve(publicDir, 'stack-startup.json'), `${JSON.stringify({
      source: 'private_start_log', bounded: true,
      localStatusFilePresent: existsSync(resolve(privateDir, 'status.json')),
      correlation: 'startup classifications only; counts do not establish cause or service acceptance',
      ...summarizeStartupLog(privateLogTail(startupPath)),
    }, null, 2)}\n`);
  }
  const requestsPath = resolve(publicDir, 'publisher-requests.json');
  if (!existsSync(requestsPath)) return; // Never mask a failure before fixtures.
  const requests = JSON.parse(readFileSync(requestsPath, 'utf8'));
  const { startedAt, events } = requests;
  assert.match(startedAt, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$/);
  const sources = [];
  const cliPath = resolve(privateDir, 'edge.log');
  if (existsSync(cliPath)) sources.push({ source: 'private_cli_log', window: 'function_start_to_capture', bounded: true,
    ...summarizePrivateLog(privateLogTail(cliPath)) });
  // Fixed containers only. Docker's output is captured in memory and reduced to
  // enum counts before a single byte is written to public evidence or stdout.
  for (const [source, container] of [['edge_runtime', 'supabase_edge_runtime_RestoFlow'], ['gateway', 'supabase_kong_RestoFlow']]) {
    const result = spawnSync('docker', ['logs', '--since', startedAt, '--timestamps', '--tail', '2000', container],
      { encoding: 'utf8', timeout: 10_000, maxBuffer: 4 * 1024 * 1024 });
    const log = `${result.stdout || ''}\n${result.stderr || ''}`;
    sources.push({ source, window: 'authenticated_probe_start_to_capture',
      available: result.status === 0, bounded: true,
      ...summarizePrivateLog(log), stageWindows: correlateLogWindows(log, events) });
  }
  writeFileSync(resolve(publicDir, 'publisher-runtime.json'), `${JSON.stringify({
    startedAt, capturedAt: iso(), correlation: 'serial fixture stages and bounded log time window; no causal inference from counts alone', sources,
  }, null, 2)}\n`);
}
