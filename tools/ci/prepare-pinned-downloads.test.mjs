import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { access, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { MODEL } from '../../apps/dashboard/web/product-cutout/limits.mjs';
import { artifacts, ensureArtifact, installCli, officialUrl, publishFile, verifyFile } from './prepare-pinned-downloads.mjs';

const payload = Buffer.from('the exact pinned fixture bytes');
const fixture = Object.freeze({ file: 'fixture.bin', bytes: payload.length,
  sha256: createHash('sha256').update(payload).digest('hex'),
  url: 'https://api.github.com/repos/supabase/cli/releases/assets/450240354' });

async function temporary(t) {
  const root = await mkdtemp(join(tmpdir(), 'bizbot-pinned-download-test-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  return root;
}

test('fixed model, CLI and Kotlin identities retain the approved bytes and versions', () => {
  assert.equal(artifacts.model.sha256, MODEL.sha256);
  assert.equal(artifacts.model.bytes, MODEL.bytes);
  assert.equal(artifacts.cli.sha256, 'ea233b337be698cee5bbca0795ee3e63b9dd154948c515c03cb72f191b3d103c');
  assert.equal(artifacts.cli.bytes, 73202139);
  assert.equal(artifacts.kotlin.sha1, 'bb8331b7585e36ea311825b01a1c06860c055fd1');
  assert.equal(artifacts.kotlin.sha256, '1c6c3f810bfe6a41abcbc34b3a2ef639f1e3f4aeed3a953a4b0974eea4f41889');
  assert.equal(artifacts.kotlin.url, 'https://api.github.com/repos/JetBrains/kotlin/releases/assets/587886256');
  assert.ok(Object.isFrozen(artifacts) && Object.values(artifacts).every(Object.isFrozen));
});

test('a valid cached file is rehashed and reused without a request', async t => {
  const root = await temporary(t);
  await writeFile(join(root, fixture.file), payload);
  const cached = await ensureArtifact(fixture, root, () => { throw new Error('Network must remain unused'); });
  assert.equal(await verifyFile(cached, fixture), true);
});

test('corrupt same-size cache bytes are replaced only by fully verified bytes', async t => {
  const root = await temporary(t);
  await writeFile(join(root, fixture.file), Buffer.alloc(payload.length));
  let requests = 0;
  const cached = await ensureArtifact(fixture, root, async () => {
    requests += 1;
    return new Response(payload);
  });
  assert.equal(requests, 1);
  assert.deepEqual(await readFile(cached), payload);
  assert.deepEqual(await readdir(root), [fixture.file]);
});

test('a directory cannot masquerade as a restored cache file', async t => {
  const root = await temporary(t);
  await mkdir(join(root, fixture.file));
  await assert.rejects(ensureArtifact(fixture, root, () => { throw new Error('No network'); }), /regular file/);
});

test('a partial stream failure preserves the prior cache and removes temporary bytes', async t => {
  const root = await temporary(t);
  const prior = Buffer.from('prior incomplete cache');
  await writeFile(join(root, fixture.file), prior);
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(payload.subarray(0, 4));
      controller.error(new Error('simulated transport interruption'));
    },
  });
  await assert.rejects(ensureArtifact(fixture, root, async () => new Response(stream)), /transport interruption/);
  assert.deepEqual(await readFile(join(root, fixture.file)), prior);
  assert.deepEqual(await readdir(root), [fixture.file]);
});

test('oversized and checksum-mismatched responses cannot publish a cache file', async t => {
  for (const bad of [Buffer.concat([payload, Buffer.from('x')]), Buffer.alloc(payload.length)]) {
    const root = await temporary(t);
    await assert.rejects(ensureArtifact(fixture, root, async () => new Response(bad)), /pinned size|checksum mismatch/);
    assert.deepEqual(await readdir(root), []);
  }
});

test('an HTTP504 failure makes one request and cannot publish a successful cache', async t => {
  const root = await temporary(t);
  let requests = 0;
  await assert.rejects(ensureArtifact(fixture, root, async () => {
    requests += 1;
    return new Response('Gateway Time-out', { status: 504 });
  }), /HTTP 504/);
  assert.equal(requests, 1);
  assert.deepEqual(await readdir(root), []);
});

test('only HTTPS official hosts without user credentials can receive requests', () => {
  for (const url of ['http://api.github.com/asset', 'https://random-mirror.example/asset',
    'https://api.github.com.evil.example/asset', 'https://user:secret@api.github.com/asset']) {
    assert.throws(() => officialUrl(url), /Untrusted/);
  }
});

test('an untrusted redirect is refused before a second fetch', async t => {
  const root = await temporary(t);
  let requests = 0;
  await assert.rejects(ensureArtifact(fixture, root, async () => {
    requests += 1;
    return new Response(null, { status: 302, headers: { location: 'https://random-mirror.example/asset' } });
  }), /Untrusted/);
  assert.equal(requests, 1);
  assert.deepEqual(await readdir(root), []);
});

test('official asset redirects still require the exact full bytes', async t => {
  const root = await temporary(t);
  const visited = [];
  const cached = await ensureArtifact(fixture, root, async (url, options) => {
    visited.push(url.hostname);
    assert.equal(options.redirect, 'manual');
    assert.equal(Object.hasOwn(options.headers, 'Authorization'), false);
    return visited.length === 1
      ? new Response(null, { status: 302, headers: { location: 'https://release-assets.githubusercontent.com/exact-asset' } })
      : new Response(payload);
  });
  assert.deepEqual(visited, ['api.github.com', 'release-assets.githubusercontent.com']);
  assert.equal(await verifyFile(cached, fixture), true);
});

test('unverified source bytes cannot replace an existing destination', async t => {
  const root = await temporary(t);
  const source = join(root, 'bad-source');
  const destination = join(root, 'existing');
  await writeFile(source, Buffer.alloc(payload.length));
  await writeFile(destination, payload);
  await assert.rejects(publishFile(source, destination, fixture), /Unverified/);
  assert.deepEqual(await readFile(destination), payload);
});

test('publishing a verified dependency keeps its exact hash', async t => {
  const root = await temporary(t);
  const source = join(root, 'source');
  const destination = join(root, 'output', 'dependency');
  await writeFile(source, payload);
  await publishFile(source, destination, fixture);
  assert.equal(await verifyFile(destination, fixture), true);
});

test('an unverified CLI archive never reaches extraction or GITHUB_PATH', async t => {
  const root = await temporary(t);
  const archive = join(root, 'untrusted.tar.gz');
  const githubPath = join(root, 'github-path');
  await writeFile(archive, payload);
  await assert.rejects(installCli(archive, root, githubPath), /not verified/);
  await assert.rejects(access(githubPath), { code: 'ENOENT' });
  assert.deepEqual(await readdir(root), ['untrusted.tar.gz']);
});
