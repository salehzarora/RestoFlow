// Build-time recovery for the three immutable dependencies that returned HTTP504.
// No credentials, alternate versions, application settings or hosted operations.
import { createHash, randomUUID } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { appendFile, chmod, copyFile, lstat, mkdir, mkdtemp, open, rename, rm } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { Readable, Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';

const execute = promisify(execFile);
class PinnedDownloadError extends Error {}
const officialHosts = new Set(['api.github.com', 'release-assets.githubusercontent.com',
  'objects.githubusercontent.com', 'repo.maven.apache.org']);
export const artifacts = Object.freeze({
  cli: Object.freeze({
    file: 'supabase-2.107.0-linux-amd64.tar.gz', bytes: 73202139,
    sha256: 'ea233b337be698cee5bbca0795ee3e63b9dd154948c515c03cb72f191b3d103c',
    url: 'https://api.github.com/repos/supabase/cli/releases/assets/450240354',
  }),
  model: Object.freeze({
    file: 'u2net-v0.0.0.onnx', bytes: 175997641,
    sha256: '8d10d2f3bb75ae3b6d527c77944fc5e7dcd94b29809d47a739a7a728a912b491',
    url: 'https://api.github.com/repos/danielgatis/rembg/releases/assets/85857932',
  }),
  kotlin: Object.freeze({
    file: 'kotlin-compiler-embeddable-2.2.20.jar', bytes: 56907103,
    sha256: '1c6c3f810bfe6a41abcbc34b3a2ef639f1e3f4aeed3a953a4b0974eea4f41889',
    sha1: 'bb8331b7585e36ea311825b01a1c06860c055fd1',
    url: 'https://api.github.com/repos/JetBrains/kotlin/releases/assets/587886256',
  }),
});
const cliMembers = Object.freeze([
  Object.freeze({ file: 'supabase', bytes: 109390144,
    sha256: 'd794e3902bd53a72e88de39e588259fc255f550a283db32955d74c86d9c48b9d' }),
  Object.freeze({ file: 'supabase-go', bytes: 100102328,
    sha256: 'c651b52f9977b1d62851ebf2a9c8b2f654000b0585c94354549b9a3b3b809ac6' }),
]);

async function regularFile(path) {
  try {
    const stat = await lstat(path);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new PinnedDownloadError('Pinned artifact must be a regular file');
    return stat;
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

export async function verifyFile(path, expected) {
  const stat = await regularFile(path);
  if (!stat || stat.size !== expected.bytes) return false;
  const digest = createHash('sha256');
  const sha1 = expected.sha1 ? createHash('sha1') : null;
  for await (const bytes of createReadStream(path)) {
    digest.update(bytes);
    sha1?.update(bytes);
  }
  return digest.digest('hex') === expected.sha256 && (!sha1 || sha1.digest('hex') === expected.sha1);
}

async function directory(path) {
  await mkdir(path, { recursive: true });
  const stat = await lstat(path);
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new PinnedDownloadError('Pinned output directory must be a real directory');
}

export function officialUrl(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password || url.port || !officialHosts.has(url.hostname)) {
    throw new PinnedDownloadError('Untrusted dependency download origin');
  }
  return url;
}

async function responseFor(spec, fetchImpl, signal) {
  let url = officialUrl(spec.url);
  for (let redirects = 0; redirects <= 3; redirects += 1) {
    const response = await fetchImpl(url, { redirect: 'manual', signal,
      headers: { Accept: 'application/octet-stream', 'User-Agent': 'BIZBOT-pinned-CI-downloads' } });
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get('location');
      await response.body?.cancel();
      if (!location) throw new PinnedDownloadError('Dependency redirect has no location');
      url = officialUrl(new URL(location, url));
      continue;
    }
    if (!response.ok || !response.body) {
      await response.body?.cancel();
      throw new PinnedDownloadError(`Pinned dependency download failed with HTTP ${response.status}`);
    }
    return response;
  }
  throw new PinnedDownloadError('Too many dependency redirects');
}

// Exported for network-free regression tests. Production callers select only the fixed manifest above.
export async function ensureArtifact(spec, cacheRoot, fetchImpl = fetch) {
  await directory(cacheRoot);
  const destination = join(cacheRoot, spec.file);
  if (await verifyFile(destination, spec)) return destination;
  const temporary = join(cacheRoot, `.partial-${randomUUID()}`);
  try {
    const signal = AbortSignal.timeout(5 * 60_000);
    const response = await responseFor(spec, fetchImpl, signal);
    let size = 0;
    const limit = new Transform({
      transform(bytes, encoding, callback) {
        size += bytes.length;
        callback(size > spec.bytes ? new PinnedDownloadError('Dependency exceeds its pinned size') : null, bytes);
      },
    });
    await pipeline(Readable.fromWeb(response.body), limit,
      createWriteStream(temporary, { flags: 'wx', mode: 0o600 }), { signal });
    if (!await verifyFile(temporary, spec)) throw new PinnedDownloadError('Dependency size or checksum mismatch');
    const file = await open(temporary, 'r+');
    try { await file.sync(); } finally { await file.close(); }
    await rename(temporary, destination);
    return destination;
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function publishFile(source, destination, expected) {
  if (!await verifyFile(source, expected)) throw new PinnedDownloadError('Unverified dependency cannot be published');
  await directory(dirname(destination));
  if (await verifyFile(destination, expected)) return;
  const temporary = join(dirname(destination), `.partial-${randomUUID()}`);
  try {
    await copyFile(source, temporary);
    if (!await verifyFile(temporary, expected)) throw new PinnedDownloadError('Copied dependency checksum mismatch');
    await rename(temporary, destination);
  } finally {
    await rm(temporary, { force: true });
  }
}

export async function installCli(archive, runnerTemp, githubPath) {
  if (!await verifyFile(archive, artifacts.cli)) throw new PinnedDownloadError('CLI archive is not verified');
  const listed = await execute('tar', ['-tzf', archive]);
  const names = listed.stdout.trim().split(/\r?\n/).sort();
  if (JSON.stringify(names) !== JSON.stringify(cliMembers.map(member => member.file).sort())) {
    throw new PinnedDownloadError('Unexpected CLI archive members');
  }
  const staging = await mkdtemp(join(runnerTemp, 'bizbot-cli-'));
  try {
    await execute('tar', ['-xzf', archive, '-C', staging, '--no-same-owner']);
    for (const member of cliMembers) {
      const file = join(staging, member.file);
      if (!await verifyFile(file, member)) throw new PinnedDownloadError('CLI executable checksum mismatch');
      await chmod(file, 0o755);
    }
    await appendFile(githubPath, `${staging}\n`);
  } catch (error) {
    await rm(staging, { recursive: true, force: true });
    throw error;
  }
}

async function main(target) {
  if (process.platform !== 'linux' || process.arch !== 'x64' || process.env.GITHUB_ACTIONS !== 'true') {
    throw new PinnedDownloadError('This installer is restricted to the existing Linux x64 CI jobs');
  }
  if (!Object.hasOwn(artifacts, target)) throw new PinnedDownloadError('Expected cli, model or kotlin');
  const runnerTemp = process.env.RUNNER_TEMP;
  if (!runnerTemp || !process.env.GITHUB_PATH) throw new PinnedDownloadError('GitHub runner paths are unavailable');
  const spec = artifacts[target];
  const cached = await ensureArtifact(spec, join(runnerTemp, 'bizbot-ci-pinned-downloads'));
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
  if (target === 'cli') await installCli(cached, runnerTemp, process.env.GITHUB_PATH);
  if (target === 'model') {
    await publishFile(cached, join(root, 'apps/dashboard/cutout/.cache/u2net.onnx'), spec);
  }
  if (target === 'kotlin') {
    const gradle = process.env.GRADLE_USER_HOME || join(homedir(), '.gradle');
    await publishFile(cached, join(gradle, 'caches/modules-2/files-2.1/org.jetbrains.kotlin',
      'kotlin-compiler-embeddable/2.2.20', spec.sha1, spec.file), spec);
  }
  console.log(`Verified pinned ${target}: ${spec.bytes} bytes, SHA256 ${spec.sha256}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv[2]).catch(error => {
    // Do not print signed redirect URLs, response bodies, environment or credentials.
    console.error(error instanceof PinnedDownloadError ? error.message : 'Pinned CI dependency I/O failed');
    process.exitCode = 1;
  });
}
