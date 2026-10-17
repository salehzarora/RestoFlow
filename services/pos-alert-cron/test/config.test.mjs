import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { GET } from '../api/dispatch.mjs';
import { TIMEOUT_MS } from '../lib/handler.mjs';

test('deployable configuration has no Cron schedule or embedded environment values', async () => {
  const config = JSON.parse(await readFile(new URL('../vercel.json', import.meta.url), 'utf8'));
  assert.deepEqual(Object.keys(config).sort(), ['$schema', 'framework', 'functions']);
  assert.equal(config.framework, null);
  assert.deepEqual(config.functions, { 'api/dispatch.mjs': { maxDuration: 125 } });
  assert.equal(TIMEOUT_MS < config.functions['api/dispatch.mjs'].maxDuration * 1000, true);
});

test('isolated Node package has no dependencies, lifecycle scripts or deploy scripts', async () => {
  const config = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
  assert.equal(config.private, true);
  assert.equal(config.type, 'module');
  assert.deepEqual(config.engines, { node: '24.x' });
  assert.deepEqual(config.scripts, { test: 'node --test test/*.test.mjs' });
  assert.equal(config.dependencies, undefined);
  assert.equal(config.devDependencies, undefined);
});

test('actual Vercel entry point is inert with all runtime configuration absent', async () => {
  const names = ['CRON_SECRET', 'POS_ORDER_ALERT_WORKER_SECRET', 'POS_ALERT_CRON_ENABLED',
    'POS_ALERT_DISPATCH_URL', 'VERCEL', 'VERCEL_ENV'];
  const previous = Object.fromEntries(names.map((name) => [name, process.env[name]]));
  const fetch = globalThis.fetch;
  let calls = 0;
  try {
    for (const name of names) delete process.env[name];
    globalThis.fetch = () => { calls++; throw new Error('network_forbidden'); };
    assert.equal((await GET(new Request('https://scheduler.invalid/api/dispatch'))).status, 503);
    assert.equal(calls, 0);
  } finally {
    globalThis.fetch = fetch;
    for (const name of names) {
      if (previous[name] === undefined) delete process.env[name];
      else process.env[name] = previous[name];
    }
  }
});
