import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { responseEvidence, summarizePrivateLog, summarizeStartupLog, capturePublisherRuntime, correlateLogWindows, isAuthenticatedReadiness, waitForAuthenticatedPublisher } from './publisher-diagnostics.mjs';
import { createHandler } from '../../supabase/functions/storefront-media-publish/lib/handler.mjs';

test('response sanitizer exports only fixed classifications, primitives and known content types', () => {
  const secret = 'SYNTHETIC_PRIVATE_PASSWORD_123';
  const token = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJwcml2YXRlIn0.signature';
  const path = 'secret-org/secret-restaurant/logo/secret.jpg';
  const value = responseEvidence({ status: 502, contentType: `application/json; token=${token}`,
    runtimeCode: secret, headers: { Authorization: token }, bytes: path,
    data: { status: secret, code: token, message: `https://storage.test/${path}?token=${token}`, retryable: secret, uncertain: false } }, 41.2);
  assert.deepEqual(value, { httpStatus: 502, contentType: 'application/json', durationMs: 41,
    runtimeCode: 'unclassified', runtimeBodyCode: 'unclassified', applicationStatus: 'unclassified', retryable: null, uncertain: false });
  for (const privateValue of [secret, token, path, 'https://storage.test']) assert.equal(JSON.stringify(value).includes(privateValue), false);
  assert.equal(responseEvidence({ runtimeCode: 'BOOT_ERROR', contentType: secret }, 1).runtimeCode, 'BOOT_ERROR');
  assert.equal(responseEvidence({ data: { code: 'WORKER_ERROR', message: secret } }, 1).runtimeBodyCode, 'WORKER_ERROR');
  assert.equal(responseEvidence({ status: secret }, Infinity).httpStatus, null);
});

test('raw CLI/runtime/gateway lines reduce to enum counts even when synthetic secrets are embedded', () => {
  const secrets = ['SYNTHETIC_PASSWORD', 'eyJabcdefghijk.eyJ1234567890.signature',
    'https://private.test/path?token=secret', 'org-private/rest-private/logo/object.jpg'];
  const result = summarizePrivateLog(`CPU time limit ${secrets.join(' ')}\nupstream prematurely closed connection\nstorefront-media-publish internal_error: Error\n${secrets.join('\n')}`);
  assert.equal(result.classifications.runtime_cpu_limit, 1);
  assert.equal(result.classifications.gateway_upstream_closed, 1);
  assert.equal(result.classifications.handler_internal_error, 1);
  assert.equal(Object.values(result.classifications).every(Number.isInteger), true);
  for (const secret of secrets) assert.equal(JSON.stringify(result).includes(secret), false);
});

test('startup classification never exports raw credentials, SQL or arbitrary error text', () => {
  const secrets = ['SYNTHETIC_PRIVATE_PASSWORD', 'eyJabcdefghijk.eyJ1234567890.signature',
    'postgresql://private:secret@localhost/db', 'private-table secret-object.jpg'];
  const result = summarizeStartupLog(`Starting database\nApplying migration ${secrets[3]}\nERROR ${secrets.join(' ')} (SQLSTATE 42601)\ncontainer is not healthy\nno space left on device\nfailed to pull image\n${secrets.join('\n')}`);
  for (const name of ['database_started', 'migrations_started', 'sql_syntax', 'container_unhealthy', 'disk_full', 'image_pull_failed']) {
    assert.equal(result.classifications[name], 1);
  }
  assert.equal(result.classifications.stack_started, 0);
  assert.ok(Object.values(result.classifications).every(Number.isInteger));
  for (const secret of secrets) assert.equal(JSON.stringify(result).includes(secret), false);
  assert.ok(Object.values(summarizeStartupLog('unknown secret failure').classifications).every(value => value === 0));
  assert.equal(summarizeStartupLog('failed to pull\n'.repeat(10001)).classifications.image_pull_failed, 9999);
});

test('an actual CLI retry is separate from its returned pull error after cleanup', () => {
  const ref = 'public.ecr.aws/supabase/realtime:v2.107.5';
  const privateValue = 'PRIVATE_URL?key=synthetic-private-value';
  const failed = `failed to pull docker image: unexpected status from HEAD request to "https://public.ecr.aws/v2/supabase/realtime/manifests/v2.107.5": 403 Forbidden ${privateValue}`;
  const log = [
    'Starting database...', 'Initialising schema...', failed, `Retrying after 4s: ${ref}`,
    `failed to display json stream: toomanyrequests: ${privateValue}`, `Retrying after 8s: ${ref}`,
    'Stopping containers...', failed, 'failed to pull docker image: manifest unknown',
  ].join('\r\n');
  const result = summarizeStartupLog(log);
  assert.equal(result.classifications.schema_initializing, 1);
  assert.deepEqual(result.imagePulls, {
    retries: [{ image: 'realtime:v2.107.5', error: 'http_forbidden' }, { image: 'realtime:v2.107.5', error: 'rate_limited' }],
    firstTerminalPull: { image: 'realtime:v2.107.5', error: 'http_forbidden' },
  });
  assert.ok(!JSON.stringify(result).includes(privateValue));
  assert.ok(!JSON.stringify(result).includes('public.ecr.aws'));
  const recovered = summarizeStartupLog(log.split('Stopping containers...')[0] + '\nStarted supabase local development setup.');
  assert.equal(recovered.imagePulls.firstTerminalPull, null);
});

test('pull diagnostics reject foreign references, arbitrary tags and blind attribution', () => {
  const secret = 'SYNTHETIC_PRIVATE_MARKER';
  const lines = [
    `failed to pull docker image: unexpected status from registry: ${secret}`,
    `Retrying after 4s: public.ecr.aws/supabase/postgres:${secret}`,
    `failed to pull docker image: ${secret} (status code: 429)`,
    'Retrying after 8s: public.ecr.aws/supabase/postgres:17.6.1.136',
    'Stopping containers...',
    `failed to pull docker image: error from https://foreign.invalid/public.ecr.aws/supabase/postgres:17.6.1.136: ${secret} 403 Forbidden`,
  ];
  const result = summarizeStartupLog(lines.join('\n'));
  assert.deepEqual(result.imagePulls, {
    retries: [{ image: null, error: 'unexpected_status' }, { image: 'postgres:17.6.1.136', error: 'rate_limited' }],
    firstTerminalPull: { image: null, error: 'http_forbidden' },
  });
  assert.ok(!JSON.stringify(result).includes(secret));
  assert.ok(!JSON.stringify(result).includes('foreign.invalid'));
  assert.equal(summarizeStartupLog(Array(50).fill(lines[1]).join('\n')).imagePulls.retries.length, 16);
});

test('startup failure evidence survives absence of fixture and publisher receipts', () => {
  const dir = mkdtempSync(join(tmpdir(), 'cinematic-startup-diagnostics-'));
  const privateDir = join(dir, 'private'); const publicDir = join(dir, 'public');
  try {
    mkdirSync(privateDir); mkdirSync(publicDir);
    writeFileSync(join(privateDir, 'start.log'), 'Starting database\nTLS handshake timeout private-secret');
    capturePublisherRuntime(privateDir, publicDir);
    assert.deepEqual(readdirSync(publicDir), ['stack-startup.json']);
    const text = readFileSync(join(publicDir, 'stack-startup.json'), 'utf8');
    const evidence = JSON.parse(text);
    assert.equal(evidence.localStatusFilePresent, false);
    assert.equal(evidence.logBytes, Buffer.byteLength('Starting database\nTLS handshake timeout private-secret'));
    assert.equal(evidence.tailLimitBytes, 4 * 1024 * 1024);
    assert.equal(evidence.tailTruncated, false);
    assert.equal(evidence.classifications.network_timeout, 1);
    assert.equal(text.includes('private-secret'), false);
    assert.equal(evidence.bounded, true);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('official CLI readiness and HTTP errors expose only fixed counts, never private suffixes', () => {
  const secret = 'SYNTHETIC_PRIVATE_SUFFIX';
  const lines = [
    `supabase_storage_${secret} container is not ready: starting`,
    `supabase_rest_${secret} container is not running: exited`,
    `failed to inspect container health: ${secret}`,
    `Error status 503: ${secret}`,
    `failed to execute http request: https://private.invalid/${secret}`,
  ];
  const result = summarizeStartupLog(lines.join('\n'));
  for (const key of ['container_not_ready', 'container_not_running', 'container_health_inspection_failed', 'http_unexpected_status', 'http_execute_failed', 'readiness_storage', 'readiness_rest'])
    assert.equal(result.classifications[key], 1);
  assert.equal(result.classifications.stack_started, 0);
  assert.ok(Object.values(result.classifications).every(Number.isInteger));
  assert.equal(JSON.stringify(result).includes(secret), false);
  assert.equal(JSON.stringify(result).includes('private.invalid'), false);
  const generic = summarizeStartupLog(`Error status 503: ${secret}\nsupabase_auth_${secret} container logs:`);
  for (const key of ['readiness_db', 'readiness_auth', 'readiness_rest', 'readiness_kong', 'readiness_storage', 'readiness_edge_runtime'])
    assert.equal(generic.classifications[key], 0, 'HTTP or a log-dump header cannot attribute a failed service');
  const named = summarizeStartupLog(['db', 'auth', 'rest', 'kong', 'storage', 'edge_runtime'].map(service =>
    `supabase_${service}_${secret} container is not ready: starting`).join('\n'));
  for (const key of ['readiness_db', 'readiness_auth', 'readiness_rest', 'readiness_kong', 'readiness_storage', 'readiness_edge_runtime'])
    assert.equal(named.classifications[key], 1);
  assert.equal(JSON.stringify(named).includes(secret), false);
  assert.equal(summarizeStartupLog('container is not ready: starting\n'.repeat(10001)).classifications.container_not_ready, 9999);
});

test('a truncated startup tail reports its bound without exporting the omitted private prefix', () => {
  const dir = mkdtempSync(join(tmpdir(), 'cinematic-startup-tail-'));
  const privateDir = join(dir, 'private'); const publicDir = join(dir, 'public');
  try {
    mkdirSync(privateDir); mkdirSync(publicDir);
    const log = 'SYNTHETIC_OMITTED_PRIVATE_PREFIX\n' + 'x'.repeat(4 * 1024 * 1024) + '\ncontainer is not ready: starting';
    writeFileSync(join(privateDir, 'start.log'), log);
    capturePublisherRuntime(privateDir, publicDir);
    const text = readFileSync(join(publicDir, 'stack-startup.json'), 'utf8'), evidence = JSON.parse(text);
    assert.equal(evidence.logBytes, Buffer.byteLength(log));
    assert.equal(evidence.tailTruncated, true);
    assert.equal(evidence.classifications.container_not_ready, 1);
    assert.equal(evidence.localStatusFilePresent, false);
    assert.equal(evidence.classifications.stack_started, 0);
    assert.equal(text.includes('SYNTHETIC_OMITTED_PRIVATE_PREFIX'), false);
    assert.equal(text.includes('container is not ready'), false);
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('authenticated readiness exact response cannot accept gateway401, typed503, or body lookalikes', () => {
  const data = { ok: false, status: 'invalid_request', field: 'request_id', reason: 'missing' };
  assert.equal(isAuthenticatedReadiness({ status: 400, data }), true);
  for (const result of [{ status: 401, data }, { status: 503, data }, { status: 400, data: { ...data, private: 'secret' } },
    { status: 400, data: { ...data, reason: 'value' } }, { status: 400, data: { ...data, field: 'body' } }]) {
    assert.equal(isAuthenticatedReadiness(result), false);
  }
});

test('timestamp correlation distinguishes a publisher window from earlier startup errors without exporting lines', () => {
  const log = [
    '2026-11-03T01:00:00.000000000Z CPU time limit secret-before',
    '2026-11-03T01:00:10.500000000Z upstream prematurely closed secret-during',
    '2026-11-03T01:00:20.000000000Z WORKER_ERROR secret-after',
    'untimestamped CPU time limit secret-untimed',
  ].join('\n');
  const result = correlateLogWindows(log, [{ stage: 'fixture_hero_publish', startedAt: '2026-11-03T01:00:10.000Z', endedAt: '2026-11-03T01:00:11.000Z' }]);
  assert.equal(result[0].timestampedLines, 1);
  assert.equal(result[0].classifications.gateway_upstream_closed, 1);
  assert.equal(result[0].classifications.runtime_cpu_limit, 0);
  assert.equal(result[0].classifications.runtime_worker_error, 0);
  assert.equal(JSON.stringify(result).includes('secret-'), false);
  assert.deepEqual(correlateLogWindows(log, [{ stage: 'fixture_hero_publish', startedAt: 'secret-path', endedAt: 'secret-token' }]), []);
});

test('readiness authenticates through actual handler and refuses before media, engine or mutation', async () => {
  const seen = [];
  const handler = createHandler({ supabaseUrl: 'http://127.0.0.1:54321', anonKey: 'synthetic-anon',
    engine: () => { throw new Error('readiness must never initialize codecs'); },
    retireWorker: () => { throw new Error('readiness must never retire a worker'); },
    fetchImpl: async (url, options) => {
      seen.push(new URL(url).pathname);
      assert.equal(new URL(url).pathname, '/auth/v1/user', 'No RPC or Storage access is allowed');
      assert.equal(options.headers.authorization, 'Bearer aaa.bbb.ccc');
      return Response.json({ id: '00000000-0000-4000-8000-000000000001', role: 'authenticated', aud: 'authenticated', is_anonymous: false });
    } });
  const response = await handler(new Request('http://127.0.0.1:54321/functions/v1/storefront-media-publish', {
    method: 'POST', headers: { authorization: 'Bearer aaa.bbb.ccc', 'content-type': 'application/json' }, body: '{}',
  }));
  assert.equal(isAuthenticatedReadiness({ status: response.status, data: await response.json() }), true);
  assert.deepEqual(seen, ['/auth/v1/user']);
});

test('only side-effect-free readiness polls bounded startup failures; a publication is never retried', async () => {
  const calls = [];
  const diagnostics = { observe: async (stage, action) => { assert.equal(stage, 'authenticated_handler_probe'); return action(); } };
  const send = async (_fixture, token, path, options) => {
    assert.equal(token, 'real-session-marker');
    assert.equal(path, '/functions/v1/storefront-media-publish');
    assert.deepEqual(options.body, {});
    calls.push(options);
    return calls.length < 3 ? { status: 502 } : { status: 400, data: { ok: false, status: 'invalid_request', field: 'request_id', reason: 'missing' } };
  };
  await waitForAuthenticatedPublisher({}, 'real-session-marker', diagnostics, { send, pause: async () => {} });
  assert.equal(calls.length, 3);
  let failures = 0;
  await assert.rejects(waitForAuthenticatedPublisher({}, 'real-session-marker', diagnostics,
    { send: async () => { failures += 1; return { status: 502 }; }, pause: async () => {} }), /readiness contract failed/);
  assert.equal(failures, 6);
  failures = 0;
  await assert.rejects(waitForAuthenticatedPublisher({}, 'real-session-marker', diagnostics,
    { send: async () => { failures += 1; return { status: 401 }; }, pause: async () => {} }), /readiness contract failed/);
  assert.equal(failures, 1);
});
