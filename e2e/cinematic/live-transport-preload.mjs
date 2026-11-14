// --import for this one disposable CI lane. Never enabled in deployed builds.
import assert from 'node:assert/strict';
import { readFileSync, existsSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { requireEphemeralCi } from '../../supabase/tests/support/cinematic_001b_migration_contract.mjs';
import { createMenuTransport, LOGICAL_ORIGIN, LOCAL_API } from './live-transport.mjs';
import { installLoopbackNetworkBoundary, networkCanaries, installChildProcessBoundary } from './loopback-network.mjs';
import { bannerPublicProjection } from './banner-clear-trace.mjs';

requireEphemeralCi(process.env);
const root = resolve(process.env.GITHUB_WORKSPACE);
const privateDir = resolve(process.env.RUNNER_TEMP, 'cinematic-private');
assert.equal(process.env.CINEMATIC_STATUS_FILE, resolve(privateDir, 'status.json'));
assert.equal(process.env.CINEMATIC_FIXTURE_FILE, resolve(privateDir, 'fixtures.json'));
assert.equal(process.env.CINEMATIC_ARTIFACT_DIR, resolve(process.env.RUNNER_TEMP, 'cinematic-public'));
assert.equal(existsSync(resolve(root, 'supabase/.temp/project-ref')), false);
assert.ok(readdirSync(resolve(root, 'storefront')).every(name => !/^\.env(?:\.|$)/i.test(name) || name === '.env.example'));
for (const key of ['SUPABASE_SERVICE_ROLE_KEY', 'VERCEL_TOKEN', 'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']) assert.ok(!process.env[key]);
const status = JSON.parse(readFileSync(process.env.CINEMATIC_STATUS_FILE, 'utf8'));
const fixture = JSON.parse(readFileSync(process.env.CINEMATIC_FIXTURE_FILE, 'utf8'));
assert.equal(status.API_URL, LOCAL_API);
assert.equal(fixture.apiUrl, LOCAL_API);
assert.ok(fixture.anonKey === status.ANON_KEY, 'Fixture must use the local anon key');
assert.ok(process.env.STOREFRONT_SUPABASE_ANON_KEY === status.ANON_KEY, 'Build must use the local anon key');
assert.equal(process.env.STOREFRONT_SUPABASE_URL, LOGICAL_ORIGIN);
assert.equal(process.env.STOREFRONT_SOURCE, 'live');
const preload = `--import=${import.meta.url}`;
assert.ok([preload, `${preload} --enable-source-maps`].includes(process.env.NODE_OPTIONS));
installLoopbackNetworkBoundary();
const deniedNetworkCanaries = networkCanaries();
installChildProcessBoundary(resolve(root, 'storefront'), preload, process.argv.includes('build') ? 'build' : 'runtime');
const menuTransport = createMenuTransport(globalThis.fetch, { anonKey: status.ANON_KEY, slug: fixture.ownerA.slug });
let menuReadSequence = 0;
globalThis.fetch = async (...args) => {
  const sequence = ++menuReadSequence, startedAt = Date.now();
  let response;
  try { response = await menuTransport(...args); }
  catch (error) {
    if (sequence <= 400) console.log('CINEMATIC_BANNER_READ ' + JSON.stringify({ sequence, startedAt,
      endedAt: Date.now(), failed: true, classification: ['AbortError', 'TimeoutError', 'TypeError'].includes(error?.name) ? error.name : 'unclassified' }));
    throw error;
  }
  // Passive clone of the actual admitted loopback read. Return the original
  // Response unchanged; no request, cache option or transport rule is added.
  if (sequence <= 400) void response.clone().json().then(envelope => {
    console.log('CINEMATIC_BANNER_READ ' + JSON.stringify({ sequence, startedAt, endedAt: Date.now(),
      status: response.status, banner: bannerPublicProjection(envelope) }));
  }).catch(() => console.log('CINEMATIC_BANNER_READ ' + JSON.stringify({ sequence, startedAt,
    endedAt: Date.now(), status: response.status, body: 'unavailable' })));
  return response;
};
// Fixed scalar receipt, emitted by the real bounded child before Next starts.
writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR, 'storefront-transport-boundary.json'),
  JSON.stringify({ status: 'PASS', deniedNetworkCanaries, onlyMenuV11Read: true, onlyLoopbackDestination: true, responseRewriting: false }));
