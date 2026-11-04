// Installed before Next captures any network implementation. This boundary is
// confined to the CI child process, never imported by application source.
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import dgram from 'node:dgram';
import childProcess from 'node:child_process';
import { resolve } from 'node:path';
import { syncBuiltinESMExports } from 'node:module';
const deny = () => { throw new Error('cinematic_network_denied'); };
export function installLoopbackNetworkBoundary() {
  const connect = net.Socket.prototype.connect;
  net.Socket.prototype.connect = function (...args) {
    const a = Array.isArray(args[0]) ? args[0] : args;
    const target = a[0];
    if (target && typeof target === 'object') {
      if (target.path || (target.host ?? target.hostname) !== '127.0.0.1' || Number(target.port) !== 54321) deny();
    } else if (typeof target !== 'number' || target !== 54321 || a[1] !== '127.0.0.1') deny();
    return connect.apply(this, args);
  };
  tls.connect = deny;
  const lookup = dns.lookup, promiseLookup = dns.promises.lookup;
  dns.lookup = (name, ...args) => { if (name !== '127.0.0.1') deny(); return lookup(name, ...args); };
  dns.promises.lookup = (name, ...args) => { if (name !== '127.0.0.1') deny(); return promiseLookup(name, ...args); };
  dns.lookupService = deny; dns.promises.lookupService = deny;
  for (const name of Object.keys(dns)) if (/^(?:resolve|reverse|setServers)/.test(name)) dns[name] = deny;
  for (const name of Object.keys(dns.promises)) if (/^(?:resolve|reverse|setServers)/.test(name)) dns.promises[name] = deny;
  dns.Resolver = class { constructor() { deny(); } };
  dns.promises.Resolver = class { constructor() { deny(); } };
  dgram.createSocket = deny; dgram.Socket = class { constructor() { deny(); } };
  syncBuiltinESMExports();
}
export function networkCanaries() {
  const attempts = [
    () => net.connect({ host: 'oqmevrndtivqxgyvcmwy.supabase.co', port: 443 }),
    () => net.connect({ host: '127.0.0.1', port: 1 }),
    () => net.connect({ host: 'localhost', port: 54321 }),
    () => net.connect({ path: '/tmp/not-an-approved-socket' }),
    () => tls.connect({ host: 'oqmevrndtivqxgyvcmwy.supabase.co', port: 443 }),
    () => dns.lookup('oqmevrndtivqxgyvcmwy.supabase.co', () => undefined),
    () => dns.resolve('oqmevrndtivqxgyvcmwy.supabase.co', () => undefined),
    () => dgram.createSocket('udp4'),
  ];
  for (const attempt of attempts) {
    let rejected = false;
    try { attempt(); } catch (error) { rejected = error.message === 'cinematic_network_denied'; }
    if (!rejected) throw new Error('cinematic_network_canary_failed');
  }
  return attempts.length;
}

export function installChildProcessBoundary(sourceDir, preload, phase) {
  const canonical = path => resolve(path).toLowerCase();
  const allowedEnvironment = env => {
    const actual = env ?? process.env;
    if (![preload, `${preload} --enable-source-maps`].includes(actual.NODE_OPTIONS)) deny();
    for (const key of ['STOREFRONT_SOURCE', 'STOREFRONT_SUPABASE_URL', 'STOREFRONT_SUPABASE_ANON_KEY',
      'CINEMATIC_FIXTURE_FILE', 'CINEMATIC_STATUS_FILE', 'CINEMATIC_ARTIFACT_DIR', 'CINEMATIC_EPHEMERAL',
      'GITHUB_WORKSPACE', 'RUNNER_TEMP', 'CI', 'GITHUB_ACTIONS', 'GITHUB_RUN_ID']) {
      if (actual[key] !== process.env[key]) deny();
    }
  };
  const fork = childProcess.fork;
  childProcess.fork = (filename, args, options) => {
    if (!Array.isArray(args)) { options = args; args = []; }
    if (phase !== 'build' || canonical(filename) !== canonical(resolve(sourceDir, 'node_modules/next/dist/compiled/jest-worker/processChild.js')) || args.length ||
      !options || options.shell || options.detached || options.execPath ||
      options.execArgv?.some(arg => !['--enable-source-maps', '--inspect-port=0'].includes(arg))) deny();
    allowedEnvironment(options.env);
    return fork(filename, args, options);
  };
  const spawn = childProcess.spawn;
  childProcess.spawn = (command, args, options) => {
    if (phase !== 'build' || canonical(command) !== canonical(process.execPath) || !Array.isArray(args) ||
        canonical(args[0] ?? '') !== canonical(resolve(sourceDir, 'node_modules/typescript/bin/tsc')) ||
        !options || canonical(options.cwd ?? '') !== canonical(sourceDir) || options.shell ||
        // Next 16.4.3 runTypeScriptCli uses a process group on non-Windows so
        // termination reaches the compiler. Only this exact guarded tsc form
        // may use it; runtime children and other build commands stay denied.
        options.detached !== (process.platform !== 'win32')) deny();
    const project = resolve(sourceDir, 'tsconfig.json');
    const forms = [
      ['--showConfig', '--project', project, '--pretty', 'false'],
      ['--project', project, '--noEmit', '--declarationMap', 'false', '--emitDeclarationOnly', 'false', '--tsBuildInfoFile', resolve(sourceDir, '.next/cache/.tsbuildinfo')],
    ];
    if (!forms.some(form => args.length === form.length + 1 && form.every((value, index) => args[index + 1] === value))) deny();
    allowedEnvironment(options.env);
    return spawn(command, args, options);
  };
  for (const name of ['exec', 'execSync', 'execFile', 'execFileSync', 'spawnSync']) childProcess[name] = deny;
  syncBuiltinESMExports();
}
