// Synthetic calls only. Native/network leaves are replaced before installation.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { EventEmitter } from 'node:events';
import net from 'node:net';
import tls from 'node:tls';
import dns from 'node:dns';
import dgram from 'node:dgram';
import childProcess from 'node:child_process';
import path from 'node:path';
import { assertConnectArgs, assertChildOptions, assertNativeCommand, installLoopbackBoundary } from '../scripts/offline-loopback-boundary.mjs';

test('offline boundary denies unknown/remote/UNC network shapes and unsafe native command/env before any leaf', () => {
  const settings = { root: path.resolve('synthetic-root'), app: path.resolve('synthetic-app'), config: path.resolve('synthetic-config'), preload: 'file:///synthetic/preload.mjs' };
  const options = { env: { NODE_OPTIONS: `--import=${settings.preload}` }, stdio: ['ignore', 'pipe', 'pipe'] };
  for (const args of [[{ host: '127.0.0.1', port: 3210 }], [3210, '127.0.0.1'], [[{ host: '::1', port: 3210 }]]]) assert.doesNotThrow(() => assertConnectArgs(args));
  for (const args of [[], ['https://example.invalid'], ['\\\\remote\\pipe'], [{ path: '/tmp/db' }], [{ host: 'localhost', port: 5432 }], [{ host: '10.0.0.1', port: 5432 }], [{ host: '127.0.0.1' }], [5432]]) assert.throws(() => assertConnectArgs(args));
  for (const bad of [{}, { ...options, shell: true }, { ...options, detached: true }, { env: { NODE_OPTIONS: '--eval=unsafe' } }, { env: { ...options.env, PGPASSWORD: 'dummy' } }, { env: { ...options.env, STOREFRONT_SUPABASE_ANON_KEY: 'not-synthetic' } }]) assert.throws(() => assertChildOptions(bad, settings.preload));
  assert.doesNotThrow(() => assertChildOptions({ ...options, env: { NODE_OPTIONS: `--import=${settings.preload} --enable-source-maps` } }, settings.preload));
  for (const value of [`--import=${settings.preload} --eval=dummy`, `--import=${settings.preload} --enable-source-maps --inspect`, `--enable-source-maps --import=${settings.preload}`, '--enable-source-maps', '--import=file:///alternate.mjs', `--import=${settings.preload} --enable-source-maps --enable-source-maps`]) {
    assert.throws(() => assertChildOptions({ ...options, env: { NODE_OPTIONS: value } }, settings.preload));
  }
  assert.throws(() => assertNativeCommand(process.execPath, ['--eval', 'dummy'], settings));
  assert.throws(() => assertNativeCommand('psql.exe', [], settings));
  assert.doesNotThrow(() => assertChildOptions({ ...options, env: { ...options.env, __NEXT_PROCESSED_ENV: 'true' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, __NEXT_PROCESSED_ENV: 'false' } }, settings.preload));
  assert.doesNotThrow(() => assertChildOptions({ ...options, env: { ...options.env, IS_NEXT_WORKER: 'true' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, IS_NEXT_WORKER: 'false' } }, settings.preload));
  assert.doesNotThrow(() => assertChildOptions({ ...options, env: { ...options.env, RUST_MIN_STACK: '8388608' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, RUST_MIN_STACK: '8388609' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, RUST_MIN_STACK: 'false' } }, settings.preload));
  assert.doesNotThrow(() => assertChildOptions({ ...options, env: { ...options.env, __NEXT_PRERENDER_CLIENT_ASSET_SUFFIX: '' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, __NEXT_PRERENDER_CLIENT_ASSET_SUFFIX: '?dpl=unknown' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, __NEXT_PRERENDER_CLIENT_ASSET_SUFFIX: 'https://example.invalid' } }, settings.preload));
  assert.doesNotThrow(() => assertChildOptions({ ...options, env: { ...options.env, PLAYWRIGHT_TEST: '1' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, PLAYWRIGHT_TEST: '2' } }, settings.preload));
  assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, PLAYWRIGHT_TEST: 'false' } }, settings.preload));
  // Windows libuv 24.19.0 inserts these exact required OS names even when
  // spawn supplies an explicit sanitized environment. No arbitrary prefix.
  for (const key of ['HOMEDRIVE', 'HOMEPATH', 'LOGONSERVER', 'SYSTEMDRIVE', 'USERDOMAIN', 'USERNAME', 'WINDIR']) {
    assert.doesNotThrow(() => assertChildOptions({ ...options, env: { ...options.env, [key]: 'synthetic-os-metadata' } }, settings.preload));
  }
  for (const key of ['HOME', 'FOO', 'USERDOMAIN_TOKEN', 'HOMEDRIVE_PASSWORD', 'AWS_ACCESS_KEY_ID']) {
    assert.throws(() => assertChildOptions({ ...options, env: { ...options.env, [key]: 'dummy' } }, settings.preload));
  }
  const nextArgs = [path.join(settings.app, 'node_modules/next/dist/bin/next'), 'build', '--webpack'];
  assert.equal(assertNativeCommand(process.execPath, nextArgs, settings), 'node');
  const tsc = path.join(settings.root, 'node_modules/typescript/bin/tsc');
  const project = path.join(settings.app, 'tsconfig.json');
  const showConfig = [tsc, '--showConfig', '--project', project, '--pretty', 'false'];
  const typecheck = [tsc, '--project', project, '--noEmit', '--declarationMap', 'false', '--emitDeclarationOnly', 'false', '--tsBuildInfoFile', path.join(settings.app, '.next/cache/.tsbuildinfo')];
  assert.equal(assertNativeCommand(process.execPath, showConfig, settings), 'typescript');
  assert.equal(assertNativeCommand(process.execPath, typecheck, settings), 'typescript');
  for (const bad of [[...showConfig, '--watch'], [tsc, '--project', project, '--showConfig', '--pretty', 'false'], ['other-tsc.js', ...showConfig.slice(1)], [tsc, '--showConfig', '--project', path.resolve('foreign.json'), '--pretty', 'false'], [...typecheck.slice(0, -1), path.resolve('foreign.tsbuildinfo')], [tsc, '--project', project, '--noEmit', 'false'], [tsc, '--eval', 'dummy']]) assert.throws(() => assertNativeCommand(process.execPath, bad, settings));

  const leaves = { net: 0, tls: 0, dns: 0, spawn: 0, fork: 0, kill: 0 };
  net.Socket.prototype.connect = () => { leaves.net++; return 'synthetic'; };
  tls.connect = () => { leaves.tls++; return 'synthetic'; };
  dns.lookup = () => { leaves.dns++; return 'synthetic'; };
  dns.promises.lookup = () => { leaves.dns++; return Promise.resolve('synthetic'); };
  dgram.createSocket = () => { throw new Error('UNREACHABLE_UDP_LEAF'); };
  let killSucceeds = true;
  const child = () => Object.assign(new EventEmitter(), { pid: 7361, exitCode: null, killed: false, kill() { leaves.kill++; this.killed = killSucceeds; return killSucceeds; } });
  childProcess.spawn = () => { leaves.spawn++; return child(); };
  childProcess.fork = () => { leaves.fork++; return child(); };
  // All native/network leaves above are already synthetic. No platform binary
  // is launched or needed; the real harness uses the default pinned verifier.
  let binaryVerifierCalled = false;
  installLoopbackBoundary(settings, () => { binaryVerifierCalled = true; });
  assert.equal(binaryVerifierCalled, true);
  for (const callback of [
    () => new net.Socket().connect({ host: 'example.invalid', port: 5432 }),
    () => tls.connect({ host: 'example.invalid', port: 443 }),
    () => dns.lookup('example.invalid', () => {}),
    () => dns.promises.lookup('example.invalid'),
    () => dns.lookupService('10.0.0.1', 5432, () => {}),
    () => dns.promises.lookupService('10.0.0.1', 5432),
    () => dns.resolve4('example.invalid', () => {}),
    () => dns.promises.resolve4('example.invalid'),
    () => new dns.Resolver(),
    () => new dns.promises.Resolver(),
    () => dgram.createSocket('udp4'),
    () => new dgram.Socket('udp4'),
    () => childProcess.spawn('psql.exe', [], options),
    () => childProcess.fork('unknown.js', options),
    () => childProcess.exec('dummy'),
    () => childProcess.execFile('dummy'),
    () => childProcess.spawnSync('taskkill /pid 9999 /T /F', { shell: true }),
  ]) assert.throws(callback, /offline_operation_denied/);
  assert.deepEqual(leaves, { net: 0, tls: 0, dns: 0, spawn: 0, fork: 0, kill: 0 });
  childProcess.spawn(process.execPath, nextArgs, options);
  assert.equal(leaves.spawn, 1, 'allowed command reaches a synthetic leaf only');
  childProcess.spawnSync('taskkill /pid 7361 /T /F', { shell: true });
  assert.equal(leaves.kill, 1, 'cleanup uses owned object, never taskkill');
  assert.equal(leaves.spawn, 1);
  assert.throws(() => childProcess.spawnSync('taskkill', ['/pid', '7361', '/T', '/F'], { stdio: 'ignore' }), /offline_operation_denied/, 'already-killed PID is stale');
  childProcess.spawn(process.execPath, showConfig, { ...options, cwd: settings.app });
  childProcess.spawnSync('taskkill', ['/pid', '7361', '/T', '/F'], { stdio: 'ignore', windowsHide: true });
  assert.equal(leaves.kill, 2);
  assert.throws(() => childProcess.spawnSync('taskkill', ['/pid', '9999', '/T', '/F'], {}), /offline_operation_denied/);
  assert.throws(() => childProcess.spawn(process.execPath, showConfig, { ...options, cwd: path.resolve('foreign') }), /offline_operation_denied/);
  killSucceeds = false;
  childProcess.spawn(process.execPath, nextArgs, options);
  assert.throws(() => childProcess.spawnSync('taskkill /pid 7361 /T /F', { shell: true }), /offline_owned_cleanup_failed/);
});
