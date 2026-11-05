import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtempSync, writeFileSync, unlinkSync, rmdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createMenuTransport, LOGICAL_ORIGIN, LOCAL_API, localMediaTarget, localProductMediaTarget, logicalMediaUrl } from './live-transport.mjs';

const anonKey = `test.${Buffer.from(JSON.stringify({ role: 'anon' })).toString('base64url')}.test`;
const slug = 'cinematic-transport-test';
const headers = { accept: 'application/json', 'content-type': 'application/json', apikey: anonKey, authorization: `Bearer ${anonKey}` };
const init = { method: 'POST', headers, body: JSON.stringify({ p_slug: slug }) };
const url = `${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v7`;
const derivative = `/storage/v1/object/public/storefront-media/${'a'.repeat(32)}/${'b'.repeat(64)}.webp`;

test('transport preserves the exact Response and sends only the fixed local request', async () => {
  const bytes = Buffer.from([0, 1, 2, 254, 255]);
  const response = new Response(bytes, { status: 206, headers: { 'content-type': 'application/octet-stream', 'x-proof': 'unchanged' } });
  let count = 0;
  const transport = createMenuTransport(async (target, forwarded) => {
    count++;
    assert.equal(target, `${LOCAL_API}/rest/v1/rpc/storefront_menu_v7`);
    assert.equal(forwarded.body, init.body);
    assert.deepEqual(Object.fromEntries(forwarded.headers), headers);
    assert.equal(forwarded.redirect, 'error');
    return response;
  }, { anonKey, slug });
  assert.equal(await transport(url, init), response);
  assert.equal(count, 1);
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), bytes);
});

test('all unapproved request shapes fail before any native transport', async () => {
  let sent = 0;
  const transport = createMenuTransport(() => { sent++; throw new Error('native call forbidden'); }, { anonKey, slug });
  for (const target of [
    'https://example.invalid/', `${LOCAL_API}/rest/v1/rpc/storefront_menu_v7`,
    `${LOGICAL_ORIGIN}/functions/v1/web-order-submit`, `${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v4`,
    `${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v5`, `${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v6`,
    `${url}?x=1`, `${url}#x`, `${LOGICAL_ORIGIN}:443/rest/v1/rpc/storefront_menu_v7`,
    `https://x@${new URL(LOGICAL_ORIGIN).host}/rest/v1/rpc/storefront_menu_v7`,
    `${LOGICAL_ORIGIN}/x/../rest/v1/rpc/storefront_menu_v7`,
  ]) await assert.rejects(transport(target, init), /cinematic_transport_denied/);
  for (const changed of [
    { method: 'GET' }, { method: 'DELETE' }, { body: JSON.stringify({ p_slug: 'cinematic-other' }) },
    { body: JSON.stringify({ p_slug: slug, extra: true }) }, { redirect: 'follow' },
    { headers: { ...headers, authorization: 'Bearer other' } },
    { headers: { ...headers, apikey: 'other' } }, { headers: { ...headers, cookie: 'private' } },
    { headers: { ...headers, 'x-extra': 'header' } },
  ]) await assert.rejects(transport(url, { ...init, ...changed }), /cinematic_transport_denied/);
  assert.equal(sent, 0);
  assert.throws(() => createMenuTransport(fetch, { anonKey: 'test.bad.test', slug }));
  assert.throws(() => createMenuTransport(fetch, { anonKey: `test.${Buffer.from('{"role":"service_role"}').toString('base64url')}.test`, slug }));
});

test('only exact public derivative GETs map and image identity retains the same path', () => {
  assert.equal(localMediaTarget(LOGICAL_ORIGIN + derivative), LOCAL_API + derivative);
  assert.equal(logicalMediaUrl(LOCAL_API + derivative), LOGICAL_ORIGIN + derivative);
  for (const path of ['/functions/v1/web-order-submit', '/rest/v1/rpc/storefront_menu_v7', '/storage/v1/object/public/other/file.webp', derivative + '?download=1', derivative + '#hash', derivative.replace('.webp', '.jpg'), derivative.replace('/public/', '/sign/'), '/x/..' + derivative]) {
    assert.throws(() => localMediaTarget(LOGICAL_ORIGIN + path));
    assert.throws(() => logicalMediaUrl(LOCAL_API + path));
  }
  for (const method of ['HEAD', 'POST', 'PUT', 'DELETE']) assert.throws(() => localMediaTarget(LOGICAL_ORIGIN + derivative, method));
  for (const origin of ['https://other.supabase.co', LOCAL_API, 'http://localhost:54321', LOGICAL_ORIGIN + '.evil.test']) assert.throws(() => localMediaTarget(origin + derivative));
});

test('product SQL relative derivative paths map exactly without admitting caller origins or normalization', () => {
  for (const path of [derivative, derivative.replace('b'.repeat(64), 'c'.repeat(64))]) {
    // The old logical-origin adapter must keep rejecting this separate contract.
    assert.throws(() => localMediaTarget(path), /cinematic_transport_denied/);
    assert.equal(localProductMediaTarget(path), LOCAL_API + path);
  }
  for (const value of [
    undefined, null, 1, { toString: () => derivative },
    `${LOGICAL_ORIGIN}${derivative}`, `${LOCAL_API}${derivative}`, `//example.invalid${derivative}`,
    derivative + '?download=1', derivative + '#hash', derivative + '\n',
    ' ' + derivative, derivative.replace('/public/', '/authenticated/'),
    derivative.replace('/public/', '/sign/'), derivative.replace('storefront-media', 'menu-images'),
    derivative.replace('.webp', '.png'), derivative.replace('/public/', '/%70ublic/'),
    '/x/..' + derivative, derivative.replace('/public/', '/public/../public/'),
    derivative.replace('/public/', '/public\\'),
  ]) assert.throws(() => localProductMediaTarget(value), /cinematic_transport_denied/);
  for (const method of ['HEAD', 'POST', 'PUT', 'DELETE']) {
    assert.throws(() => localProductMediaTarget(derivative, method), /cinematic_transport_denied/);
  }
});

test('installed socket/DNS boundary forwards unchanged loopback HTTP bytes and rejects redirects before external access', async () => {
  // Transport unit fixture only, not Supabase acceptance. The CI lane runs this
  // before it starts the real disposable service on the fixed gateway port.
  const body = Buffer.from([0, 255, 7, 8, 9]);
  let received = 0;
  const server = createServer(async (request, response) => {
    received++;
    assert.equal(request.method, 'POST');
    assert.equal(request.url, '/rest/v1/rpc/storefront_menu_v7');
    assert.equal(request.headers.apikey, anonKey);
    const chunks = []; for await (const chunk of request) chunks.push(chunk);
    assert.equal(Buffer.concat(chunks).toString(), init.body);
    if (received === 1) { response.writeHead(207, { 'content-type': 'application/octet-stream', 'x-proof': 'same' }); response.end(body); }
    else { response.writeHead(302, { location: `${LOGICAL_ORIGIN}/functions/v1/web-order-submit` }); response.end(); }
  });
  server.listen(54321, '127.0.0.1');
  await once(server, 'listening');
  try {
    const script = `
      import assert from 'node:assert/strict';
      import childProcess from 'node:child_process';
      import { resolve } from 'node:path';
      import { installLoopbackNetworkBoundary, networkCanaries, installChildProcessBoundary } from ${JSON.stringify(new URL('./loopback-network.mjs', import.meta.url).href)};
      import { createMenuTransport } from ${JSON.stringify(new URL('./live-transport.mjs', import.meta.url).href)};
      installLoopbackNetworkBoundary();
      assert.equal(networkCanaries(), 8);
      const original = fetch;
      const transport = createMenuTransport(original, ${JSON.stringify({ anonKey, slug })});
      const response = await transport(${JSON.stringify(url)}, ${JSON.stringify(init)});
      assert.equal(response.status, 207);
      assert.equal(response.headers.get('x-proof'), 'same');
      assert.deepEqual([...new Uint8Array(await response.arrayBuffer())], [0,255,7,8,9]);
      await assert.rejects(transport(${JSON.stringify(url)}, ${JSON.stringify(init)}));
      await assert.rejects(original('https://oqmevrndtivqxgyvcmwy.supabase.co/'));
      // Exercise the installed full spawn guard for both platform forms. The
      // native spawn spy records admission only; no compiler/process starts.
      const platformDescriptor = Object.getOwnPropertyDescriptor(process, 'platform');
      const nativeSpawn = childProcess.spawn;
      const priorOptions = process.env.NODE_OPTIONS;
      const preload = '--import=file:///synthetic-boundary-only.mjs';
      process.env.NODE_OPTIONS = preload;
      for (const platform of ['linux', 'win32']) {
        Object.defineProperty(process, 'platform', { ...platformDescriptor, value: platform });
        let admissions = 0;
        childProcess.spawn = () => { admissions++; return { diagnosticOnly: true }; };
        installChildProcessBoundary(process.cwd(), preload, 'build');
        const args = [resolve('node_modules/typescript/bin/tsc'), '--showConfig', '--project', resolve('tsconfig.json'), '--pretty', 'false'];
        const options = { cwd: process.cwd(), shell: false, detached: platform !== 'win32', env: { ...process.env } };
        assert.deepEqual(childProcess.spawn(process.execPath, args, options), { diagnosticOnly: true });
        for (const [command, alteredArgs, alteredOptions] of [
          [process.execPath, args, { ...options, detached: !options.detached }],
          [process.execPath, args, { ...options, detached: undefined }],
          [process.execPath, [...args, '--eval=unapproved'], options],
          [process.execPath, ['other.js', ...args.slice(1)], options],
          ['unapproved-native-command', args, options],
          [process.execPath, args, { ...options, shell: true }],
          [process.execPath, args, { ...options, env: { ...options.env, NODE_OPTIONS: '' } }],
        ]) assert.throws(() => childProcess.spawn(command, alteredArgs, alteredOptions), /cinematic_network_denied/);
        assert.equal(admissions, 1);
      }
      Object.defineProperty(process, 'platform', platformDescriptor);
      childProcess.spawn = nativeSpawn;
      if (priorOptions === undefined) delete process.env.NODE_OPTIONS; else process.env.NODE_OPTIONS = priorOptions;
      installChildProcessBoundary(process.cwd(), '--import=file:///not-real.mjs', 'runtime');
      for (const attempt of [() => childProcess.exec('not-an-approved-command'), () => childProcess.spawn(process.execPath, ['-e', '']), () => childProcess.fork('not-approved.js'), () => childProcess.execSync('not-approved')]) assert.throws(attempt, /cinematic_network_denied/);
      console.log('PASS: 8 network canaries, identical HTTP bytes/status/header, redirect denied');
    `;
    const temp = mkdtempSync(join(tmpdir(), 'cinematic-boundary-test-'));
    const program = join(temp, 'boundary.mjs');
    writeFileSync(program, script);
    try {
      const child = spawn(process.execPath, [program], { stdio: ['ignore', 'pipe', 'pipe'] });
      let output = ''; child.stdout.on('data', value => { output += value; }); child.stderr.on('data', value => { output += value; });
      const [code] = await once(child, 'close');
      assert.equal(code, 0, output);
      assert.match(output, /PASS: 8 network canaries/);
      assert.equal(received, 2);
    } finally { unlinkSync(program); rmdirSync(temp); }
  } finally { server.closeAllConnections(); await new Promise(resolve => server.close(resolve)); }
});
