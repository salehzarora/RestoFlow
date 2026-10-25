// BIZBOT-STOREFRONT-CART-NAVIGATION-FIX-001: test-only process boundary.
// Load with --import BEFORE Next, Playwright, or any test workload.
import fs from 'node:fs';
import path from 'node:path';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import dgram from 'node:dgram';
import childProcess from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { syncBuiltinESMExports } from 'node:module';

export const NODE_SHA256 = '3602f2bb1a10f2cbab4c36886218a33c1ab3db87290e73b033c46c77147d0237';
export const CHROMIUM_SHA256 = '28016df6864d302434c9231e1f9f1a8a7ecc512cb2fe3faabb2a36130b96bcf1';
export const PUBLIC_ENV_TEMPLATE_SHA256 = '04346ccc6202ef7db373c7b37bf42d8d542f494a5150ec6b94afad8388638bd9';
export const SYNTHETIC_KEY = 'sb_publishable_SYNTHETIC_cart_navigation_only_000000';
// Logical origin is required by the unchanged LIVE adapter's admission rule.
// It is NEVER a socket destination: the one read is mapped below before fetch.
export const LOGICAL_ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
export const SYNTHETIC_SLUGS = ['sf-cart-nav-alpha', 'sf-cart-nav-bravo'];
// Diagnostics contain fixed categories and key/flag NAMES only. Never emit
// environment values, arguments, headers, request bodies, or connection data.
const DENIAL_PREFIX = 'cart_navigation_offline_boundary_denied';
const DENIAL_CATEGORIES = new Set(['POLICY', 'ENVIRONMENT_REQUIRED', 'ENVIRONMENT_KEY', 'PRELOAD_FORM', 'SYNTHETIC_SOURCE', 'SYNTHETIC_ORIGIN', 'SYNTHETIC_KEY', 'SETTINGS_BINDING', 'FORK_PHASE', 'FORK_MODULE', 'FORK_ARGUMENTS', 'FORK_OPTIONS', 'FORK_EXECARGV', 'SETTINGS_PATH', 'SETTINGS_SCHEMA', 'SETTINGS_MODE', 'SETTINGS_PORTS', 'NODE_PIN', 'CHROMIUM_PIN', 'SOURCE_ENV_FILE', 'SOURCE_ENV_TEMPLATE', 'NEXT_VERSION', 'NETWORK_TCP_TARGET', 'NETWORK_TCP_FORM', 'NETWORK_LISTEN', 'NETWORK_TLS', 'NETWORK_DNS', 'NETWORK_DNS_SERVICE', 'NETWORK_DNS_RESOLVE', 'NETWORK_DNS_RESOLVER', 'NETWORK_UDP', 'FETCH_NOT_APPROVED', 'SPAWN_OPTIONS', 'SPAWN_CHROMIUM_PIN', 'SPAWN_CHROMIUM_FLAGS', 'SPAWN_TARGET', 'SPAWN_ENTRY', 'SPAWN_ENTRY_PIN', 'SPAWN_CWD', 'SPAWN_ARGS', 'SPAWN_TYPESCRIPT_PHASE', 'SPAWN_TYPESCRIPT_CWD', 'SPAWN_TYPESCRIPT_ARGS', 'TYPESCRIPT_PIN', 'EXEC_DISABLED', 'CLEANUP_COMMAND', 'CLEANUP_SHAPE', 'CLEANUP_OWNED_PROCESS']);
const deny = (category = 'POLICY', names = []) => {
  const safeCategory = DENIAL_CATEGORIES.has(category) ? category : 'POLICY';
  const safeNames = (safeCategory !== 'POLICY' && Array.isArray(names) ? names : []).filter(name => typeof name === 'string' && /^[A-Za-z_][A-Za-z0-9_-]{0,79}$/.test(name)).slice(0, 12);
  throw new Error(`${DENIAL_PREFIX}:${safeCategory}${safeNames.length ? ':' + safeNames.join(',') : ''}`);
};
const canonical = value => path.resolve(value).toLowerCase();
export const hashFile = filename => createHash('sha256').update(fs.readFileSync(filename)).digest('hex');
const settingsPath = process.env.BIZBOT_CART_NAV_SETTINGS;
if (!settingsPath || !path.isAbsolute(settingsPath)) deny('SETTINGS_PATH');
export const settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
if (settings.schema !== 1 || !path.isAbsolute(settings.sourceDir) || !path.isAbsolute(settings.outputDir) || !path.isAbsolute(settings.chromiumPath)) deny('SETTINGS_SCHEMA');
if (!['old-desktop', 'fixed-matrix'].includes(settings.mode) || !['build', 'test'].includes(settings.phase)) deny('SETTINGS_MODE');
if (![settings.appPort, settings.rpcPort].every(port => Number.isInteger(port) && port > 1024 && port < 65536) || settings.appPort === settings.rpcPort) deny('SETTINGS_PORTS');
if (hashFile(process.execPath) !== NODE_SHA256) deny('NODE_PIN');
if (hashFile(settings.chromiumPath) !== CHROMIUM_SHA256) deny('CHROMIUM_PIN');
export function assertSourceEnvironmentNames(names) {
  if (names.some(name => /^\.env(?:\.|$)/i.test(name) && name !== '.env.example')) deny('SOURCE_ENV_FILE');
}
assertSourceEnvironmentNames(fs.readdirSync(settings.sourceDir));
if (hashFile(path.join(settings.sourceDir, '.env.example')) !== PUBLIC_ENV_TEMPLATE_SHA256) deny('SOURCE_ENV_TEMPLATE');
const nextBin = path.join(settings.sourceDir, 'node_modules/next/dist/bin/next');
const nextRoot = path.join(settings.sourceDir, 'node_modules/next');
if (JSON.parse(fs.readFileSync(path.join(nextRoot, 'package.json'), 'utf8')).version !== '16.4.3') deny('NEXT_VERSION');
const nextBinHash = hashFile(nextBin);
const typeScriptRoot = path.join(settings.sourceDir, 'node_modules/typescript');
const typeScriptBin = path.join(typeScriptRoot, 'bin/tsc');
const typeScriptPins = Object.freeze({
  'bin/tsc': '8d5fa5bd883fec0979fc2004f1fe1d99aef40570155d550eadc0b03b55513bf0',
  'lib/tsc.js': '2cffde0b8c6760dfb0b5b0382bbb7e00ba6a8b2d981b9205b256a700a481d983',
  'lib/_tsc.js': 'e8f349eabd48486bdb2bf9dc1a00c89d58297270c54b745838879e2859194419',
});
function verifyTypeScriptPins() {
  for (const [relative, expected] of Object.entries(typeScriptPins)) if (hashFile(path.join(typeScriptRoot, relative)) !== expected) deny('TYPESCRIPT_PIN');
}
verifyTypeScriptPins();
export function assertTypeScriptCommand(args, cwd, phase = settings.phase) {
  if (phase !== 'build') deny('SPAWN_TYPESCRIPT_PHASE');
  if (canonical(cwd ?? '') !== canonical(settings.sourceDir)) deny('SPAWN_TYPESCRIPT_CWD');
  const project = path.join(settings.sourceDir, 'tsconfig.json');
  const forms = [
    [typeScriptBin, '--showConfig', '--project', project, '--pretty', 'false'],
    [typeScriptBin, '--project', project, '--noEmit', '--declarationMap', 'false', '--emitDeclarationOnly', 'false', '--tsBuildInfoFile', path.join(settings.sourceDir, '.next/cache/.tsbuildinfo')],
  ];
  if (!Array.isArray(args) || !forms.some(form => args.length === form.length && form.every((value, index) => path.isAbsolute(value) ? typeof args[index] === 'string' && canonical(value) === canonical(args[index]) : value === args[index]))) deny('SPAWN_TYPESCRIPT_ARGS');
  verifyTypeScriptPins();
}
const preload = fileURLToPath(import.meta.url);
const preloadOption = `--import=${import.meta.url}`;
const host = value => value === '127.0.0.1';
const ports = new Set([settings.appPort, settings.rpcPort]);
const envKeys = /^(?:PATH|SYSTEMROOT|SYSTEMDRIVE|WINDIR|TEMP|TMP|USERPROFILE|LOCALAPPDATA|APPDATA|COMSPEC|PATHEXT|NODE_ENV|NODE_OPTIONS|NEXT_TELEMETRY_DISABLED|STOREFRONT_SOURCE|STOREFRONT_SUPABASE_URL|STOREFRONT_SUPABASE_ANON_KEY|BIZBOT_CART_NAV_SETTINGS|CI|NO_COLOR|FORCE_COLOR|TERM|JEST_WORKER_ID|__NEXT_PRIVATE_[A-Z_]+|__NEXT_PROCESSED_ENV|IS_NEXT_WORKER|RUST_MIN_STACK|BROWSERSLIST_IGNORE_OLD_DATA|TURBOPACK|NEXT_DEPLOYMENT_ID)$/;

export function childEnvironment() {
  const env = {};
  for (const key of ['PATH', 'SYSTEMROOT', 'SYSTEMDRIVE', 'WINDIR', 'TEMP', 'TMP', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'COMSPEC', 'PATHEXT']) if (process.env[key]) env[key] = process.env[key];
  return { ...env, NODE_ENV: 'production', NODE_OPTIONS: preloadOption, NEXT_TELEMETRY_DISABLED: '1', CI: '1', NO_COLOR: '1', STOREFRONT_SOURCE: 'live', STOREFRONT_SUPABASE_URL: LOGICAL_ORIGIN, STOREFRONT_SUPABASE_ANON_KEY: SYNTHETIC_KEY, BIZBOT_CART_NAV_SETTINGS: settingsPath };
}
function assertEnvironment(env, nodeChild) {
  if (!env) deny('ENVIRONMENT_REQUIRED');
  const unknown = Object.keys(env).filter(key => !envKeys.test(key)
    && !(key === 'NEXT_PHASE' && env[key] === 'phase-production-build')
    && !(key === '__NEXT_PRERENDER_CLIENT_ASSET_SUFFIX' && env[key] === '')
    && !(key === 'NEXT_RUNTIME' && env[key] === 'nodejs')
    && !(key === 'NEXT_PRIVATE_START_TIME' && typeof env[key] === 'string' && /^[1-9][0-9]{12}$/.test(env[key])));
  if (unknown.length) deny('ENVIRONMENT_KEY', unknown.sort());
  if (nodeChild && ![preloadOption, preloadOption + ' --enable-source-maps'].includes(env.NODE_OPTIONS)) deny('PRELOAD_FORM', ['NODE_OPTIONS']);
  if (env.STOREFRONT_SOURCE && env.STOREFRONT_SOURCE !== 'live') deny('SYNTHETIC_SOURCE', ['STOREFRONT_SOURCE']);
  if (env.STOREFRONT_SUPABASE_URL && env.STOREFRONT_SUPABASE_URL !== LOGICAL_ORIGIN) deny('SYNTHETIC_ORIGIN', ['STOREFRONT_SUPABASE_URL']);
  if (env.STOREFRONT_SUPABASE_ANON_KEY && env.STOREFRONT_SUPABASE_ANON_KEY !== SYNTHETIC_KEY) deny('SYNTHETIC_KEY', ['STOREFRONT_SUPABASE_ANON_KEY']);
  if (env.BIZBOT_CART_NAV_SETTINGS && env.BIZBOT_CART_NAV_SETTINGS !== settingsPath) deny('SETTINGS_BINDING', ['BIZBOT_CART_NAV_SETTINGS']);
}
// Reject inherited credentials/proxies before any workload can run. The owner
// launcher supplies a closed environment; no authentication file is inspected.
assertEnvironment(process.env, true);

const connect = net.Socket.prototype.connect;
net.Socket.prototype.connect = function (...args) {
  const a = Array.isArray(args[0]) ? args[0] : args;
  const target = a[0];
  if (target && typeof target === 'object') {
    if (target.path || !host(target.host ?? target.hostname) || !ports.has(Number(target.port))) deny('NETWORK_TCP_TARGET');
  } else if (typeof target === 'number') {
    if (!ports.has(target) || !host(a[1])) deny('NETWORK_TCP_TARGET');
  } else deny('NETWORK_TCP_FORM');
  return connect.apply(this, args);
};
const listen = net.Server.prototype.listen;
net.Server.prototype.listen = function (...args) {
  const target = args[0];
  const address = target && typeof target === 'object' ? target.host : args[1];
  const port = target && typeof target === 'object' ? target.port : target;
  if (target?.path || !host(address) || !ports.has(Number(port))) deny('NETWORK_LISTEN');
  return listen.apply(this, args);
};
tls.connect = () => deny('NETWORK_TLS');
const lookup = dns.lookup;
dns.lookup = (name, ...args) => { if (!host(name)) deny('NETWORK_DNS'); return lookup(name, ...args); };
const promiseLookup = dns.promises.lookup;
dns.promises.lookup = (name, ...args) => { if (!host(name)) deny('NETWORK_DNS'); return promiseLookup(name, ...args); };
dns.lookupService = () => deny('NETWORK_DNS_SERVICE'); dns.promises.lookupService = () => deny('NETWORK_DNS_SERVICE');
for (const name of Object.keys(dns)) if (/^(?:resolve|reverse|setServers)/.test(name)) dns[name] = () => deny('NETWORK_DNS_RESOLVE');
for (const name of Object.keys(dns.promises)) if (/^(?:resolve|reverse|setServers)/.test(name)) dns.promises[name] = () => deny('NETWORK_DNS_RESOLVE');
dns.Resolver = class { constructor() { deny('NETWORK_DNS_RESOLVER'); } };
dns.promises.Resolver = class { constructor() { deny('NETWORK_DNS_RESOLVER'); } };
dgram.createSocket = () => deny('NETWORK_UDP'); dgram.Socket = class { constructor() { deny('NETWORK_UDP'); } };
const originalFetch = globalThis.fetch;
export const transportEvidence = { mappedSyntheticReads: 0, rejectedFetches: 0 };
globalThis.fetch = async (input, init) => {
  const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
  const method = (init?.method ?? input?.method ?? 'GET').toUpperCase();
  const read = url.port === String(settings.appPort) && ['GET', 'HEAD'].includes(method);
  if (url.protocol === 'http:' && host(url.hostname) && !url.username && !url.password && read) return originalFetch(input, init);
  const headers = new Headers(init?.headers ?? input?.headers);
  const text = typeof init?.body === 'string' ? init.body : input instanceof Request ? await input.clone().text() : '';
  let body; try { body = text.length <= 1024 ? JSON.parse(text) : null; } catch { body = null; }
  const mapped = url.origin === LOGICAL_ORIGIN && url.pathname === '/rest/v1/rpc/storefront_menu_v4' && !url.search && !url.hash && !url.username && !url.password && method === 'POST'
    && JSON.stringify([...headers.keys()].sort()) === JSON.stringify(['accept', 'apikey', 'authorization', 'content-type'])
    && headers.get('accept') === 'application/json' && headers.get('content-type') === 'application/json'
    && headers.get('apikey') === SYNTHETIC_KEY && headers.get('authorization') === `Bearer ${SYNTHETIC_KEY}`
    && body && Object.keys(body).length === 1 && SYNTHETIC_SLUGS.includes(body.p_slug);
  if (!mapped) { transportEvidence.rejectedFetches++; deny('FETCH_NOT_APPROVED'); }
  transportEvidence.mappedSyntheticReads++;
  // No call to originalFetch has seen the logical production URL. Only this
  // fixed loopback target is passed to the actual network implementation.
  return originalFetch(`http://127.0.0.1:${settings.rpcPort}/rest/v1/rpc/storefront_menu_v4`, { ...init, method: 'POST', headers, body: text, signal: init?.signal ?? input?.signal, redirect: 'error' });
};
const spawn = childProcess.spawn;
const owned = new Map();
childProcess.spawn = (command, args, options) => {
  if (!Array.isArray(args) || !options || options.shell || options.detached) deny('SPAWN_OPTIONS');
  const chrome = canonical(command) === canonical(settings.chromiumPath);
  if (chrome) {
    if (hashFile(command) !== CHROMIUM_SHA256) deny('SPAWN_CHROMIUM_PIN');
    if (!args.includes('--remote-debugging-pipe') || !args.includes('--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1') || args.some(arg => /^(?:https?:|--proxy-server|--load-extension|--remote-debugging-port)/i.test(arg))) deny('SPAWN_CHROMIUM_FLAGS');
  } else {
    if (canonical(command) !== canonical(process.execPath)) deny('SPAWN_TARGET');
    if (canonical(args[0] ?? '') === canonical(typeScriptBin)) assertTypeScriptCommand(args, options.cwd);
    else {
      if (canonical(args[0] ?? '') !== canonical(nextBin)) deny('SPAWN_ENTRY');
      if (hashFile(nextBin) !== nextBinHash) deny('SPAWN_ENTRY_PIN');
      if (canonical(options.cwd ?? '') !== canonical(settings.sourceDir)) deny('SPAWN_CWD');
      const build = settings.phase === 'build' && args.length === 2 && args[1] === 'build';
      const start = settings.phase === 'test' && args.length === 6 && args[1] === 'start' && args[2] === '-p' && args[3] === String(settings.appPort) && args[4] === '-H' && args[5] === '127.0.0.1';
      if (!build && !start) deny('SPAWN_ARGS');
    }
  }
  assertEnvironment(options.env, !chrome);
  const child = spawn(command, args, options);
  owned.set(child.pid, child); child.once('close', () => owned.delete(child.pid));
  return child;
};
const fork = childProcess.fork;
childProcess.fork = (filename, args, options) => {
  if (!Array.isArray(args)) { options = args; args = []; }
  const worker = path.join(nextRoot, 'dist/compiled/jest-worker/processChild.js');
  if (settings.phase !== 'build') deny('FORK_PHASE');
  if (canonical(filename) !== canonical(worker)) deny('FORK_MODULE');
  if (args.length) deny('FORK_ARGUMENTS');
  if (!options || options.shell || options.detached) deny('FORK_OPTIONS');
  if (options.execArgv?.some(arg => !['--enable-source-maps', '--inspect-port=0'].includes(arg))) deny('FORK_EXECARGV', options.execArgv.map(arg => /^--([A-Za-z][A-Za-z0-9_-]*)/.exec(arg)?.[1]).filter(Boolean));
  assertEnvironment(options.env, true);
  return fork(filename, args, options);
};
for (const name of ['exec', 'execSync', 'execFile', 'execFileSync']) childProcess[name] = () => deny('EXEC_DISABLED');
childProcess.spawnSync = (command, args, options) => {
  let pid;
  if (Array.isArray(args)) {
    if (command !== 'taskkill' || args.length !== 4 || args[0] !== '/pid' || !/^[1-9][0-9]*$/.test(args[1]) || args[2] !== '/T' || args[3] !== '/F' || options?.shell) deny('CLEANUP_COMMAND');
    pid = Number(args[1]);
  } else {
    const match = /^taskkill \/pid ([1-9][0-9]*) \/T \/F$/.exec(command);
    if (!match || args?.shell !== true) deny('CLEANUP_SHAPE');
    pid = Number(match[1]);
  }
  const child = owned.get(pid);
  if (!child || child.exitCode !== null || child.killed || !child.kill()) deny('CLEANUP_OWNED_PROCESS');
  return { status: 0, signal: null, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0) };
};
syncBuiltinESMExports();
export async function boundaryCanaries() {
  const cases = [
    ['external_tcp', () => net.connect({ host: 'example.invalid', port: 443 })],
    ['wrong_local_port', () => net.connect({ host: '127.0.0.1', port: 1 })],
    ['external_tls', () => tls.connect({ host: 'example.invalid', port: 443 })],
    ['external_dns', () => dns.lookup('example.invalid', () => undefined)],
    ['udp', () => dgram.createSocket('udp4')],
    ['native_child', () => childProcess.execSync('not-a-real-approved-command')],
  ];
  const results = cases.map(([name, invoke]) => {
    let rejected = false;
    try { invoke(); } catch (error) { rejected = error.message.startsWith(DENIAL_PREFIX + ':'); }
    if (!rejected) throw new Error(`boundary_canary_failed_${name}`);
    return { name, status: 'PASS_REJECTED_BEFORE_NATIVE_OPERATION' };
  });
  const generatedEnvironment = { ...childEnvironment(), NEXT_RUNTIME: 'nodejs', NEXT_PRIVATE_START_TIME: '1700000000000' };
  assertEnvironment(generatedEnvironment, true);
  assertEnvironment({ ...generatedEnvironment, NODE_OPTIONS: preloadOption + ' --enable-source-maps' }, true);
  for (const [name, options] of [
    ['preload_duplicate', `${preloadOption} ${preloadOption}`],
    ['preload_other_import', '--import=file:///not-approved.mjs'],
    ['preload_eval', `${preloadOption} --eval=synthetic`],
    ['preload_inspect', `${preloadOption} --inspect`],
    ['preload_missing_import', '--enable-source-maps'],
    ['preload_reordered', `--enable-source-maps ${preloadOption}`],
  ]) {
    let rejected = false;
    try { assertEnvironment({ ...generatedEnvironment, NODE_OPTIONS: options }, true); } catch (error) { rejected = error.message.startsWith(DENIAL_PREFIX + ':PRELOAD_FORM:'); }
    if (!rejected) throw new Error(`boundary_canary_failed_${name}`);
    results.push({ name, status: 'PASS_REJECTED_BEFORE_NATIVE_OPERATION' });
  }
  for (const [name, entries] of [
    ['next_runtime_edge', { NEXT_RUNTIME: 'edge' }],
    ['next_runtime_empty', { NEXT_RUNTIME: '' }],
    ['next_start_time_malformed', { NEXT_PRIVATE_START_TIME: 'not-an-epoch' }],
    ['next_start_time_zero', { NEXT_PRIVATE_START_TIME: '0' }],
    ['next_start_time_short', { NEXT_PRIVATE_START_TIME: '170000000000' }],
    ['next_start_time_long', { NEXT_PRIVATE_START_TIME: '17000000000000' }],
    ['next_start_time_leading_zero', { NEXT_PRIVATE_START_TIME: '0700000000000' }],
    ['next_private_unknown_key', { NEXT_PRIVATE_UNAPPROVED: 'synthetic' }],
  ]) {
    let rejected = false;
    try { assertEnvironment({ ...generatedEnvironment, ...entries }, true); } catch (error) { rejected = error.message.startsWith(DENIAL_PREFIX + ':ENVIRONMENT_KEY:'); }
    if (!rejected) throw new Error(`boundary_canary_failed_${name}`);
    results.push({ name, status: 'PASS_REJECTED_BEFORE_NATIVE_OPERATION' });
  }
  // Pure validation only: neither accepted nor rejected TSC forms spawn here.
  const showConfig = [typeScriptBin, '--showConfig', '--project', path.join(settings.sourceDir, 'tsconfig.json'), '--pretty', 'false'];
  assertTypeScriptCommand(showConfig, settings.sourceDir, 'build');
  for (const [name, args, cwd, phase] of [
    ['typescript_extra_argument', [...showConfig, '--eval=not-allowed'], settings.sourceDir, 'build'],
    ['typescript_wrong_project', [typeScriptBin, '--showConfig', '--project', path.join(settings.sourceDir, 'other.json'), '--pretty', 'false'], settings.sourceDir, 'build'],
    ['typescript_wrong_cwd', showConfig, path.dirname(settings.sourceDir), 'build'],
    ['typescript_not_build_phase', showConfig, settings.sourceDir, 'test'],
  ]) {
    let rejected = false;
    try { assertTypeScriptCommand(args, cwd, phase); } catch (error) { rejected = error.message.startsWith(DENIAL_PREFIX + ':'); }
    if (!rejected) throw new Error(`boundary_canary_failed_${name}`);
    results.push({ name, status: 'PASS_REJECTED_BEFORE_NATIVE_OPERATION' });
  }
  assertSourceEnvironmentNames(['.env.example']);
  for (const name of ['.env', '.env.local', '.env.production', '.env.production.local', '.ENV']) {
    let rejected = false;
    try { assertSourceEnvironmentNames([name]); } catch (error) { rejected = error.message.startsWith(DENIAL_PREFIX + ':'); }
    if (!rejected) throw new Error('boundary_canary_failed_autoloadable_env_file');
    results.push({ name: `autoloadable_environment_file_${name}`, status: 'PASS_REJECTED_BEFORE_FILE_ACCESS' });
  }
  for (const [name, url] of [
    ['external_fetch', 'https://example.invalid/'],
    ['production_edge_fetch', `${LOGICAL_ORIGIN}/functions/v1/web-order-submit`],
    ['production_v4_wrong_method', `${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v4`],
  ]) {
    let rejected = false;
    try { await globalThis.fetch(url, { method: 'GET' }); } catch (error) { rejected = error.message.startsWith(DENIAL_PREFIX + ':'); }
    if (!rejected) throw new Error(`boundary_canary_failed_${name}`);
    results.push({ name, status: 'PASS_REJECTED_BEFORE_NATIVE_OPERATION' });
  }
  return results;
}
export const boundaryEvidence = Object.freeze({ nodeSha256: NODE_SHA256, chromiumSha256: CHROMIUM_SHA256, publicEnvTemplateSha256: PUBLIC_ENV_TEMPLATE_SHA256, nextBinSha256: nextBinHash, typeScriptPins, preload, tcpHosts: ['127.0.0.1'], ports: [...ports], externalNetwork: 'DENY', browserWrites: 'DENY' });
