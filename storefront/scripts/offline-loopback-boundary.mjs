// Test-process boundary only; never imported by the Storefront runtime.
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import dgram from 'node:dgram';
import childProcess from 'node:child_process';
import path from 'node:path';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { syncBuiltinESMExports } from 'node:module';

export const NODE_SHA256 = '3602f2bb1a10f2cbab4c36886218a33c1ab3db87290e73b033c46c77147d0237';
export const CHROME_SHA256 = '36a30716f0994b377f1ce6b47cfe35399b9719e31d597fe0ea0d8f3b62aed532';
export const CHROME = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
export const isLoopbackHost = value => value === '127.0.0.1' || value === '::1';
const deny = () => { throw new Error('offline_operation_denied'); };
const canonical = value => path.resolve(value).toLowerCase();
const TYPESCRIPT_PINS = {
  'bin/tsc': '8d5fa5bd883fec0979fc2004f1fe1d99aef40570155d550eadc0b03b55513bf0',
  'lib/tsc.js': '2cffde0b8c6760dfb0b5b0382bbb7e00ba6a8b2d981b9205b256a700a481d983',
  'lib/_tsc.js': 'e8f349eabd48486bdb2bf9dc1a00c89d58297270c54b745838879e2859194419',
};

export function assertConnectArgs(args) {
  const normalized = Array.isArray(args[0]) ? args[0] : args;
  const target = normalized[0];
  if (target && typeof target === 'object') {
    // No Unix socket or UNC/named-pipe destination is needed by this test.
    if (target.path || !isLoopbackHost(target.host ?? target.hostname) || !Number.isInteger(Number(target.port)) || Number(target.port) < 1 || Number(target.port) > 65535) deny();
  } else if (typeof target === 'number') {
    if (target < 1 || target > 65535 || !isLoopbackHost(normalized[1])) deny();
  } else deny();
}

export function assertChildOptions(options, preload) {
  if (!options || options.shell || options.detached || !options.env || options.execPath && canonical(options.execPath) !== canonical(process.execPath)) deny();
  if (![ `--import=${preload}`, `--import=${preload} --enable-source-maps` ].includes(options.env.NODE_OPTIONS)) deny();
  for (const key of Object.keys(options.env)) {
    // @next/env sets this exact marker after processing the copied app's
    // configuration. It carries no credentials and must remain boolean text.
    if (key === '__NEXT_PROCESSED_ENV' && options.env[key] === 'true') continue;
    if (key === 'IS_NEXT_WORKER' && options.env[key] === 'true') continue;
    if (key === 'RUST_MIN_STACK' && options.env[key] === '8388608') continue;
    if (key === '__NEXT_PRERENDER_CLIENT_ASSET_SUFFIX' && options.env[key] === '') continue;
    if (key === 'PLAYWRIGHT_TEST' && options.env[key] === '1') continue;
    if (/^(?:PG|DATABASE|DB_|SUPABASE|VERCEL|FIREBASE|GOOGLE|AWS|CRON|POS_ORDER_ALERT|POS_ALERT)/i.test(key)) deny();
    if (!/^(?:PATH|SYSTEMROOT|SYSTEMDRIVE|WINDIR|HOMEDRIVE|HOMEPATH|LOGONSERVER|USERDOMAIN|USERNAME|TEMP|TMP|USERPROFILE|LOCALAPPDATA|APPDATA|COMSPEC|PATHEXT|NODE_ENV|NODE_OPTIONS|NEXT_TELEMETRY_DISABLED|STOREFRONT_SOURCE|STOREFRONT_SUPABASE_URL|STOREFRONT_SUPABASE_ANON_KEY|SF_WEB_ORDER_BASE|SF_WEB_ORDER_RUN_DIR|SF_WEB_ORDER_ORIGINAL|SF_WEB_ORDER_APP_DIR|FORCE_COLOR|DEBUG_COLORS|NO_COLOR|TERM|CI|JEST_WORKER_ID|TEST_WORKER_INDEX|TEST_PARALLEL_INDEX|PW_TEST_WORKER_INDEX|PW_TEST_WORKER_PARALLEL_INDEX|__NEXT_PRIVATE_[A-Z_]+|NEXT_[A-Z_]+)$/i.test(key)) deny();
  }
  if (options.env.STOREFRONT_SUPABASE_ANON_KEY && options.env.STOREFRONT_SUPABASE_ANON_KEY !== 'sb_publishable_SYNTHETIC_browser_local_only_000000') deny();
  if (options.execArgv?.some(arg => !/^--(?:inspect-port=0|enable-source-maps)$/.test(arg))) deny();
}

export function assertNativeCommand(command, args, { root, app, config }) {
  if (!Array.isArray(args)) deny();
  if (canonical(command) === canonical(CHROME)) {
    if (!args.includes('--remote-debugging-pipe') || !args.includes('--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1') || args.some(arg => /^(?:https?:|--proxy-server|--load-extension|--remote-debugging-port)/i.test(arg))) deny();
    return 'chrome';
  }
  if (canonical(command) !== canonical(process.execPath)) deny();
  const next = [path.join(root, 'node_modules/next/dist/bin/next'), path.join(app, 'node_modules/next/dist/bin/next')].map(canonical);
  if (next.includes(canonical(args[0] ?? '')) && args.length === 3 && args[1] === 'build' && args[2] === '--webpack') return 'node';
  if (next.includes(canonical(args[0] ?? '')) && args.length === 6 && args[1] === 'start' && args[2] === '-p' && /^\d{1,5}$/.test(args[3]) && Number(args[3]) > 0 && Number(args[3]) <= 65535 && args[4] === '-H' && args[5] === '127.0.0.1') return 'node';
  if (canonical(args[0] ?? '') === canonical(path.join(root, 'node_modules/@playwright/test/cli.js')) && args.length === 4 && args[1] === 'test' && args[2] === '--config' && canonical(args[3]) === canonical(config)) return 'node';
  const tsc = path.join(root, 'node_modules/typescript/bin/tsc');
  const project = path.join(app, 'tsconfig.json');
  const forms = [
    [tsc, '--showConfig', '--project', project, '--pretty', 'false'],
    [tsc, '--project', project, '--noEmit', '--declarationMap', 'false', '--emitDeclarationOnly', 'false', '--tsBuildInfoFile', path.join(app, '.next/cache/.tsbuildinfo')],
  ];
  if (forms.some(form => args.length === form.length && form.every((arg, i) => path.isAbsolute(arg) ? typeof args[i] === 'string' && canonical(args[i]) === canonical(arg) : args[i] === arg))) return 'typescript';
  deny();
}

export function installLoopbackBoundary(settings, verifyBinaries = () => {
  const hash = filename => createHash('sha256').update(readFileSync(filename)).digest('hex');
  if (hash(process.execPath) !== NODE_SHA256 || hash(CHROME) !== CHROME_SHA256) deny();
  for (const [relative, expected] of Object.entries(TYPESCRIPT_PINS)) if (hash(path.join(settings.root, 'node_modules/typescript', relative)) !== expected) deny();
}) {
  const { root, app, preload } = settings;
  verifyBinaries();
  const connect = net.Socket.prototype.connect;
  net.Socket.prototype.connect = function (...args) { assertConnectArgs(args); return connect.apply(this, args); };
  const tlsConnect = tls.connect;
  tls.connect = (...args) => { assertConnectArgs(args); return tlsConnect(...args); };
  const lookup = dns.lookup;
  dns.lookup = (host, ...args) => { if (!isLoopbackHost(host)) deny(); return lookup(host, ...args); };
  const promiseLookup = dns.promises.lookup;
  dns.promises.lookup = (host, ...args) => { if (!isLoopbackHost(host)) deny(); return promiseLookup(host, ...args); };
  dns.lookupService = deny;
  dns.promises.lookupService = deny;
  for (const name of Object.keys(dns)) if (/^(?:resolve|reverse|setServers)/.test(name)) dns[name] = deny;
  for (const name of Object.keys(dns.promises)) if (/^(?:resolve|reverse|setServers)/.test(name)) dns.promises[name] = deny;
  dns.Resolver = class { constructor() { deny(); } };
  dns.promises.Resolver = class { constructor() { deny(); } };
  dgram.createSocket = deny;
  dgram.Socket = class { constructor() { deny(); } };
  const spawn = childProcess.spawn;
  const owned = new Map();
  childProcess.spawn = (command, args, options) => {
    const kind = assertNativeCommand(command, args, settings);
    if (kind === 'typescript' && canonical(options?.cwd ?? '') !== canonical(app)) deny();
    assertChildOptions(options, preload);
    const child = spawn(command, args, options);
    owned.set(child.pid, child);
    child.once('close', () => owned.delete(child.pid));
    return child;
  };
  const fork = childProcess.fork;
  childProcess.fork = (filename, args, options) => {
    if (!Array.isArray(args)) { options = args; args = []; }
    const modules = [root, app].flatMap(base => [path.join(base, 'node_modules/next/dist/compiled/jest-worker/processChild.js'), path.join(base, 'node_modules/playwright/lib/worker/workerProcessEntry.js')]).map(canonical);
    if (!modules.includes(canonical(filename)) || args.length) deny();
    assertChildOptions(options, preload);
    return fork(filename, args, options);
  };
  for (const name of ['exec', 'execSync', 'execFile', 'execFileSync']) childProcess[name] = deny;
  // Playwright's Windows emergency cleanup normally starts taskkill via a
  // shell. Intercept only its exact owned-child PID form, and terminate the
  // already held ChildProcess object instead. No shell/native utility runs.
  childProcess.spawnSync = (command, args, options) => {
    let pid;
    if (Array.isArray(args)) {
      if (command !== 'taskkill' || args.length !== 4 || args[0] !== '/pid' || !/^[1-9][0-9]*$/.test(args[1]) || args[2] !== '/T' || args[3] !== '/F' || options?.shell) deny();
      pid = Number(args[1]);
    } else {
      const match = /^taskkill \/pid ([1-9][0-9]*) \/T \/F$/.exec(command);
      if (!match || args?.shell !== true) deny();
      pid = Number(match[1]);
    }
    const child = owned.get(pid);
    if (!child || child.exitCode !== null || child.killed) deny();
    if (child.kill() !== true) throw new Error('offline_owned_cleanup_failed');
    return { status: 0, signal: null, stdout: Buffer.alloc(0), stderr: Buffer.alloc(0) };
  };
  syncBuiltinESMExports();
}
