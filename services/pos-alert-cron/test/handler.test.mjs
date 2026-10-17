import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createHandler, DISPATCH_URL } from '../lib/handler.mjs';

// Public synthetic fixtures, never credentials from an environment or file.
const INBOUND = 'a'.repeat(64);
const OUTBOUND = 'b'.repeat(64);
const START = '2026-10-18T09:00:00.000Z';
const END = '2026-10-18T09:30:00.000Z';
const NOW = Date.parse(START);
const config = () => ({
  CRON_SECRET: INBOUND,
  POS_ORDER_ALERT_WORKER_SECRET: OUTBOUND,
  POS_ALERT_CRON_ENABLED: 'true',
  POS_ALERT_DISPATCH_URL: DISPATCH_URL,
  POS_ALERT_PILOT_START_UTC: START,
  POS_ALERT_PILOT_END_UTC: END,
  VERCEL: '1',
  VERCEL_ENV: 'production',
});
const request = (options = {}) => new Request('https://scheduler.invalid/api/dispatch', {
  headers: { Authorization: `Bearer ${INBOUND}` }, ...options,
});
const success = () => Response.json({ ok: true, sent: 1, deferred: 0 });
function fixture(env = config(), fetchImpl = async () => success(), timeoutMs, now = () => NOW) {
  const calls = [];
  const handler = createHandler({
    getEnv: (name) => env[name], timeoutMs, now,
    fetchImpl: (...args) => { calls.push(args); return fetchImpl(...args); },
  });
  return { handler, calls };
}

for (const value of [undefined, null, '', 123, '2026-10-18', '2026-10-18T09:00Z',
  '2026-10-18T09:00:00', '2026-10-18T09:00:00+00:00', '2026-10-18T09:00:00z',
  ' 2026-10-18T09:00:00Z', '2026-10-18T09:00:00Z ', '2026-10-18T09:00:00Z\n',
  '2026-10-18T09:00:00.1Z', '2026-10-18T09:00:00.0000Z',
  '2026-02-29T09:00:00Z', '2026-02-30T09:00:00Z', '2026-04-31T09:00:00Z',
  '2026-13-18T09:00:00Z', '2026-10-18T24:00:00Z', '2026-10-18T09:60:00Z',
  '2026-10-18T09:00:60Z']) {
  for (const name of ['POS_ALERT_PILOT_START_UTC', 'POS_ALERT_PILOT_END_UTC']) {
    test(`invalid strict UTC ${name} fails closed without forwarding`, async () => {
      const { handler, calls } = fixture({ ...config(), [name]: value });
      const response = await handler(request());
      assert.equal(response.status, 503);
      assert.deepEqual(await response.json(), { ok: false, error: 'unavailable' });
      assert.equal(calls.length, 0);
    });
  }
}

for (const [start, end] of [[START, START], [END, START],
  [START, '2026-10-18T09:30:00.001Z'], [START, '2026-10-19T09:00:00Z']]) {
  test('empty, reversed or longer than 30-minute pilot windows never forward', async () => {
    const { handler, calls } = fixture({ ...config(),
      POS_ALERT_PILOT_START_UTC: start, POS_ALERT_PILOT_END_UTC: end });
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
}

for (const [time, expectedCalls] of [[NOW - 1, 0], [NOW, 1],
  [Date.parse(END) - 1, 1], [Date.parse(END), 0], [Date.parse(END) + 1, 0],
  [NaN, 0], [Infinity, 0], ['2026-10-18T09:00:00Z', 0]]) {
  test('pilot admits start inclusively, ends exclusively, and denies invalid clocks', async () => {
    const { handler, calls } = fixture(config(), undefined, undefined, () => time);
    assert.equal((await handler(request())).status, expectedCalls ? 200 : 503);
    assert.equal(calls.length, expectedCalls);
  });
}

for (const [start, end] of [['2026-10-18T09:00:00Z', '2026-10-18T09:30:00Z'],
  ['2028-02-29T09:00:00.123Z', '2028-02-29T09:30:00.123Z']]) {
  test('valid UTC seconds, milliseconds, leap dates and exactly 30 minutes are admitted', async () => {
    const { handler, calls } = fixture({ ...config(),
      POS_ALERT_PILOT_START_UTC: start, POS_ALERT_PILOT_END_UTC: end },
    undefined, undefined, () => Date.parse(start));
    assert.equal((await handler(request())).status, 200);
    assert.equal(calls.length, 1);
  });
}

test('same retained handler rejects expired and removed pilot configuration', async () => {
  const env = config();
  let clock = NOW;
  const { handler, calls } = fixture(env, undefined, undefined, () => clock);
  assert.equal((await handler(request())).status, 200);
  clock = Date.parse(END);
  assert.equal((await handler(request())).status, 503);
  delete env.POS_ALERT_PILOT_END_UTC;
  clock = NOW;
  assert.equal((await handler(request())).status, 503);
  assert.equal(calls.length, 1);
});

test('UTC cutoff bounds concurrent in-flight HTTP waits and denies further forwarding', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: Date.parse(END) - 10 });
  const { handler, calls } = fixture(config(), (_, { signal }) => new Promise((resolve, reject) => {
    signal.addEventListener('abort', () => reject(new Error('synthetic_abort')));
  }), undefined, () => Date.now());
  const first = handler(request());
  const second = handler(request());
  assert.equal(calls.length, 2);
  t.mock.timers.tick(10);
  assert.deepEqual((await Promise.all([first, second])).map((r) => r.status), [504, 504]);
  assert.equal(calls.every(([, options]) => options.signal.aborted), true);
  assert.equal((await handler(request())).status, 503);
  assert.equal(calls.length, 2);
});

for (const headers of [{}, { Authorization: 'Basic invalid' },
  { Authorization: `Bearer ${'c'.repeat(64)}` },
  { Authorization: `bearer ${INBOUND}` },
  { Authorization: `Bearer ${OUTBOUND}` },
  { Authorization: `Bearer ${INBOUND}, Bearer ${INBOUND}` }]) {
  test('missing, wrong, ambiguous or outbound bearer cannot authenticate inbound', async () => {
    const { handler, calls } = fixture();
    assert.equal((await handler(request({ headers }))).status, 401);
    assert.equal(calls.length, 0);
  });
}

test('method, query and body injection never reach upstream', async () => {
  const { handler, calls } = fixture();
  for (const method of ['POST', 'HEAD', 'PUT', 'DELETE', 'OPTIONS']) {
    assert.equal((await handler(request({ method }))).status, 405);
  }
  assert.equal((await handler(request({ method: 'POST', body: '{"target":"injected"}' }))).status, 405);
  const query = new Request('https://scheduler.invalid/api/dispatch?target=elsewhere', {
    headers: { Authorization: `Bearer ${INBOUND}` },
  });
  assert.equal((await handler(query)).status, 400);
  // The Web Request API forbids GET bodies, but keep an explicit boundary.
  assert.equal((await handler({ method: 'GET', headers: query.headers,
    url: 'https://scheduler.invalid/api/dispatch', body: '{}' })).status, 400);
  assert.equal(calls.length, 0);
});

for (const enabled of [undefined, '', 'false', 'TRUE', '1', 'true ']) {
  test('only exact explicit enabled=true admits forwarding', async () => {
    const env = { ...config(), POS_ALERT_CRON_ENABLED: enabled };
    const { handler, calls } = fixture(env);
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
}

for (const environment of ['preview', 'development', 'staging', undefined]) {
  test('preview, development and missing production environment fail closed', async () => {
    const { handler, calls } = fixture({ ...config(), VERCEL_ENV: environment });
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
}

for (const name of Object.keys(config())) {
  test(`missing ${name} fails closed without network`, async () => {
    const env = config(); delete env[name];
    const { handler, calls } = fixture(env);
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
}

for (const [name, value] of [
  ['CRON_SECRET', 'short'], ['CRON_SECRET', `${INBOUND}\n`],
  ['POS_ORDER_ALERT_WORKER_SECRET', 'short'],
  ['POS_ORDER_ALERT_WORKER_SECRET', OUTBOUND.toUpperCase()],
  ['POS_ORDER_ALERT_WORKER_SECRET', `${OUTBOUND}\n`],
  ['POS_ORDER_ALERT_WORKER_SECRET', INBOUND], ['VERCEL', '0'],
]) {
  test('malformed or reused credentials and non-Vercel runtime fail closed', async () => {
    const { handler, calls } = fixture({ ...config(), [name]: value });
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
}

for (const destination of [
  '', 'http://oqmevrndtivqxgyvcmwy.supabase.co/functions/v1/pos-order-alert-dispatch',
  'https://another.supabase.co/functions/v1/pos-order-alert-dispatch',
  `${DISPATCH_URL}/`, `${DISPATCH_URL}?extra=1`, `${DISPATCH_URL}#fragment`,
  DISPATCH_URL.replace('https://', 'https://user:password@'),
  DISPATCH_URL.replace('.supabase.co', '.supabase.co.attacker.invalid'),
  'http://127.0.0.1:54321/functions/v1/pos-order-alert-dispatch',
]) {
  test('destination variations and alternate projects fail closed', async () => {
    const { handler, calls } = fixture({ ...config(), POS_ALERT_DISPATCH_URL: destination });
    assert.equal((await handler(request())).status, 503);
    assert.equal(calls.length, 0);
  });
}

test('authorized forwarding is exactly one fixed empty JSON POST with outbound bearer only', async () => {
  const { handler, calls } = fixture();
  const result = await handler(request({ headers: { Authorization: `Bearer ${INBOUND}`,
    Origin: 'https://untrusted.invalid', 'X-Forwarded-Authorization': 'injected' } }));
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { ok: true });
  assert.equal(result.headers.get('cache-control'), 'no-store');
  assert.equal(calls.length, 1);
  const [url, options] = calls[0];
  assert.equal(url, DISPATCH_URL);
  assert.equal(options.method, 'POST');
  assert.equal(options.body, '{}');
  assert.equal(options.redirect, 'error');
  assert.equal(options.cache, 'no-store');
  assert.equal(options.signal instanceof AbortSignal, true);
  assert.equal(options.headers.Authorization === `Bearer ${OUTBOUND}`, true);
  assert.equal(JSON.stringify(options).includes(INBOUND), false);
  assert.deepEqual(Object.keys(options.headers).sort(), ['Authorization', 'Content-Type']);
});

for (const status of [301, 302, 307, 308, 400, 401, 403, 429, 500, 503]) {
  test('upstream errors or redirects never retry or leak upstream content', async () => {
    const { handler, calls } = fixture(config(), async () => new Response(OUTBOUND, { status }));
    const response = await handler(request());
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { ok: false, error: 'upstream_unavailable' });
    assert.equal(calls.length, 1);
  });
}

for (const body of ['not json', '{}', '{"ok":false}',
  '{"ok":true,"sent":11,"deferred":0}', '{"ok":true,"sent":-1,"deferred":0}',
  '{"ok":true,"sent":0.5,"deferred":0}', '{"ok":true,"sent":0}', 'x'.repeat(4097)]) {
  test('HTTP 200 alone is not a successful dispatcher result', async () => {
    const { handler, calls } = fixture(config(), async () => new Response(body));
    assert.equal((await handler(request())).status, 502);
    assert.equal(calls.length, 1);
  });
}

test('transport exceptions are sanitized without retry', async () => {
  const { handler, calls } = fixture(config(), async () => { throw new Error(OUTBOUND); });
  const response = await handler(request());
  assert.equal(response.status, 502);
  assert.equal((await response.text()).includes(OUTBOUND), false);
  assert.equal(calls.length, 1);
});

test('non-200 responses abort the upstream transfer even when its body never ends', async () => {
  const { handler, calls } = fixture(config(), async () => new Response(new ReadableStream({}), { status: 503 }));
  assert.equal((await handler(request())).status, 502);
  assert.equal(calls[0][1].signal.aborted, true);
  assert.equal(calls.length, 1);
});

test('deadline aborts a hung fetch with no retry', async () => {
  let signal;
  const { handler, calls } = fixture(config(), (_, options) => {
    signal = options.signal;
    return new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(new Error(OUTBOUND))));
  }, 5);
  assert.equal((await handler(request())).status, 504);
  assert.equal(signal.aborted, true);
  assert.equal(calls.length, 1);
});

test('deadline covers a stalled response body, not just receipt of headers', async () => {
  const { handler, calls } = fixture(config(), async () => new Response(new ReadableStream({})), 5);
  assert.equal((await handler(request())).status, 504);
  assert.equal(calls[0][1].signal.aborted, true);
  assert.equal(calls.length, 1);
});

test('overlapping and later duplicate invocations each forward once; no local exactly-once claim', async () => {
  let release;
  const wait = new Promise((resolve) => { release = resolve; });
  const { handler, calls } = fixture(config(), async () => { await wait; return success(); });
  const first = handler(request());
  const second = handler(request());
  assert.equal(calls.length, 2);
  release();
  assert.deepEqual((await Promise.all([first, second])).map((r) => r.status), [200, 200]);
  assert.equal((await handler(request())).status, 200);
  assert.equal(calls.length, 3);
});

test('success, failures and timeouts emit no application logs', async () => {
  const originals = {};
  let logCount = 0;
  for (const method of ['log', 'info', 'warn', 'error', 'debug']) {
    originals[method] = console[method];
    console[method] = () => { logCount++; };
  }
  try {
    await fixture().handler(request());
    await fixture().handler(request({ headers: {} }));
    await fixture(config(), async () => { throw new Error(OUTBOUND); }).handler(request());
    await fixture(config(), () => new Promise(() => {}), 5).handler(request());
    assert.equal(logCount, 0);
  } finally {
    for (const method of Object.keys(originals)) console[method] = originals[method];
  }
});
