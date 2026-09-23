#!/usr/bin/env node
// Vercel's contract is inverted: 0 cancels an unaffected build; 1 builds.
// Only bounded baseline Git fetches are allowed; refs and working files stay put.
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, realpathSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Absolute end assertion: JavaScript's $ alone also accepts a final newline.
const SHA = /^[a-f0-9]{40}(?![\s\S])/i;
const ENGINE = 'tools/vercel/ignore-build.mjs';
const BUILD_SCRIPT_HASH = '9ea4df7bef84320e65d416c490cd5562d97c6542f01c2c50ca965f52a51cac49';
const SITE_BUILDER_HASH = 'fb6cb2b72d9f889f29787fa64b84a931786324e79c8497c707d6c5d995f0d15e';
// Exported so storefront/tests/config-hash.test.mjs can pin the file it
// describes without exposing hash(). A changed next.config always BUILDs
// until this pin is reviewed: that file decides what the build reads.
export const STOREFRONT_CONFIG_HASH = '59bff99cca265f1246073aec3da7dbbff69a3699bdadaf9587e9baf1d7b01705';
const STOREFRONT_RUNTIME_ROOTS = ['storefront/app', 'storefront/src', 'storefront/public', 'storefront/messages', 'storefront/components', 'storefront/lib', 'storefront/styles'];
const STOREFRONT_PUBLIC_TYPES = ['.svg', '.ico', '.txt', '.json', '.webmanifest', '.png', '.webp'];
// STAGE 7 R3 static-shell module contract: the ONLY bare specifiers storefront
// source may import. Node builtins are deliberately absent. A static export has
// no server runtime, so filesystem/process capability is unnecessary here, and
// allowing it would let build-time code read repository paths this engine does
// not track. Adding a BFF must re-review this list (SEC-002 / READ-001).
const STOREFRONT_BARE_IMPORTS = ['react', 'react-dom', 'next'];
// npm runs pre/post hooks around `npm ci` and `npm run build` on its own, so a
// lifecycle entry is arbitrary code executing inside the build and outside this
// contract — `prebuild` reading ../docs is ordinary monorepo practice, not a
// bypass. Only these keys may appear, and none of them is auto-run.
const STOREFRONT_SCRIPT_KEYS = ['build', 'dev', 'start', 'lint', 'typecheck', 'test'];
// Direct, no-import handles to a Node builtin. Syntactic only: dot, optional
// chaining and quoted index. This is a dependency-integrity guard for trusted
// source, NOT a hostile-code sandbox — see the threat model in DEPLOYMENT.md §15.
const STOREFRONT_BUILTIN_HANDLES = /\bprocess\s*(?:\?\.|\.|\[\s*["'])\s*(?:getBuiltinModule|mainModule|binding|_linkedBinding)\b/;
// Storefront-local support roots. As of STAGE 7 R2 these are NOT ignored: they
// BUILD the storefront like any other storefront path (see category()). The
// constant survives because guard step 7 still keeps them out of the TypeScript
// program, which is now build-graph containment rather than a licence to ignore.
const STOREFRONT_LOCAL_ROOTS = ['storefront/tests', 'storefront/docs', 'storefront/review', 'storefront/scripts'];
// Storefront support files: the four local roots plus repository metadata and the
// lint/format/test tooling configs. ONE definition, used by the classifier (where
// they still BUILD the storefront like every storefront path) and by the module
// scan (where the application import contract does not apply to them). `next
// build` does not execute them — the npm lifecycle hooks that could are refused at
// step 4 — and they legitimately depend on Node and on devDependencies, so holding
// them to the front-end contract would BUILD the storefront on every single run.
function storefrontLocal(file) {
  return STOREFRONT_LOCAL_ROOTS.some((dir) => below(file, dir))
    || /^storefront\/(?:README(?:\.[^/]*)?|AGENTS\.md|\.gitignore|\.env\.example)(?![\s\S])/.test(file)
    || /^storefront\/(?:eslint\.config|\.eslintrc|\.prettierrc|vitest\.config|playwright\.config)[^/]*(?![\s\S])/.test(file);
}
// Approved storefront deployment values. STOREFRONT-READ-001: the storefront is
// a SERVER-RENDERED Next.js app (revalidate + expireTime, no `output: 'export'`);
// the Next.js preset creates its function, so `functions` stays absent and the
// ignore command must invoke THIS engine with the storefront selector.
// HOST-FIX-001: the storefront config declares NO outputDirectory. Vercel's
// Next.js preset locates the framework build directory (.next) itself and then
// serves the static export from out/; an explicit outputDirectory in vercel.json
// overrides that lookup for the deployment (it is not merely a project-settings
// default), and 'out' made the hosted builder fail with NEXT_NO_ROUTES_MANIFEST
// after a successful next build. Any explicit value - 'out', '.next', 'dist',
// null - is therefore unsupported and fails safe to BUILD. The export itself is
// unchanged: next.config.mjs (pinned below) still writes out/.
const STOREFRONT_IGNORE_COMMAND = `if node ../${ENGINE} storefront; then exit 0; else exit 1; fi`;
const APPS = ['apps/dashboard', 'apps/pos', 'apps/kds', 'apps/kiosk'];
// Three linked projects use main. First-preview fallback also checks the source
// CI policy; changing the hosted production branch requires reviewing this map.
const PRODUCTION_BRANCH = 'main';
// Reviewed public source, independent of Vercel's internal checkout remote.
const TRUSTED_REPOSITORY_URL = 'https://github.com/salehzarora/RestoFlow.git';
const FETCH_TIMEOUT_MS = 10000;
const fail = (reason) => { throw new Error(reason); };
const hash = (value) => createHash('sha256').update(value.replace(/\r\n/g, '\n')).digest('hex');
const object = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);
const below = (file, directory) => file.startsWith(`${directory}/`);
const insideStorefront = (target) => target === 'storefront' || below(target, 'storefront');
const decode = (bytes) => {
  try { return new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes); }
  catch { fail('unsupported_encoding'); }
};

function git(repo, args, { allowOne = false, input, buffer = false } = {}) {
  const result = spawnSync('git', ['-C', repo, ...args], {
    encoding: null, input, maxBuffer: 64 * 1024 * 1024,
    timeout: 15000, windowsHide: true,
    env: { ...process.env, GIT_OPTIONAL_LOCKS: '0', GIT_NO_REPLACE_OBJECTS: '1', GIT_NO_LAZY_FETCH: '1', GIT_TERMINAL_PROMPT: '0' },
  });
  if (result.error || (result.status !== 0 && !(allowOne && result.status === 1))) fail('git_error');
  return { text: buffer ? result.stdout : decode(result.stdout), status: result.status };
}

function commit(repo, value) {
  if (!SHA.test(value)) fail('invalid_sha');
  const resolved = git(repo, ['rev-parse', '--verify', `${value}^{commit}`]).text.trim();
  // An annotated tag object must not silently peel into a different commit.
  if (!SHA.test(resolved) || resolved.toLowerCase() !== value.toLowerCase()) fail('invalid_sha');
  git(repo, ['cat-file', '-e', `${resolved}^{tree}`]);
  return resolved.toLowerCase();
}

function read(repo, revision, file) {
  return git(repo, ['show', `${revision}:${file}`]).text;
}

function readBatch(repo, revision, files) {
  if (!SHA.test(revision) || files.some((file) => /[\0\r\n]/.test(file))) fail('unsupported_graph');
  const bytes = git(repo, ['cat-file', '--batch'], {
    input: files.map((file) => `${revision}:${file}\n`).join(''), buffer: true,
  }).text;
  const result = new Map();
  let offset = 0;
  for (const file of files) {
    const end = bytes.indexOf(10, offset);
    if (end < 0) fail('git_error');
    const header = /^([a-f0-9]{40}) blob ([0-9]+)$/.exec(bytes.subarray(offset, end).toString('ascii'));
    if (!header) fail('unsupported_graph');
    const size = Number(header[2]);
    offset = end + 1;
    if (!Number.isSafeInteger(size) || size > 8 * 1024 * 1024 || offset + size >= bytes.length || bytes[offset + size] !== 10) fail('unsupported_graph');
    result.set(file, decode(bytes.subarray(offset, offset + size)));
    offset += size + 1;
  }
  if (offset !== bytes.length) fail('git_error');
  return result;
}

// Sizes only, never contents. storefront/public holds binary assets whose
// fatal UTF-8 decode in readBatch would classify every one of them as
// unsupported_encoding and BUILD on every single run.
function blobSizes(repo, revision, files) {
  if (!SHA.test(revision) || files.some((file) => /[\0\r\n]/.test(file))) fail('unsupported_graph');
  const listing = git(repo, ['cat-file', '--batch-check'], {
    input: files.map((file) => `${revision}:${file}\n`).join(''),
  }).text.split('\n');
  const result = new Map();
  files.forEach((file, index) => {
    const header = /^([a-f0-9]{40}) blob ([0-9]+)$/.exec(listing[index] ?? '');
    if (!header) fail('unsupported_graph');
    const size = Number(header[2]);
    if (!Number.isSafeInteger(size)) fail('unsupported_graph');
    result.set(file, size);
  });
  return result;
}

// Deliberately small, strict YAML subset: the repository uses block mappings,
// lists, and single-line scalars. Anchors, flow syntax, duplicate keys, tags,
// multiline scalars, and unrecognized indentation fail open to BUILD.
function parseManifest(source) {
  const tokens = [];
  for (const raw of source.replace(/\r\n/g, '\n').split('\n')) {
    if (/\t/.test(raw)) fail('unsupported_manifest');
    let quote = null;
    let end = raw.length;
    for (let i = 0; i < raw.length; i++) {
      const c = raw[i];
      if (quote && c === quote) {
        if (quote === "'" && raw[i + 1] === "'") { i++; continue; }
        if (quote !== '"' || raw[i - 1] !== '\\') quote = null;
      } else if (!quote && (c === '"' || c === "'") && (i === 0 || /[\s:]/.test(raw[i - 1]))) quote = c;
      else if (!quote && c === '#' && (i === 0 || /\s/.test(raw[i - 1]))) { end = i; break; }
    }
    if (quote) fail('unsupported_manifest');
    const line = raw.slice(0, end).trimEnd();
    if (!line.trim()) continue;
    const indent = line.length - line.trimStart().length;
    if (indent % 2) fail('unsupported_manifest');
    const text = line.trimStart();
    const listMap = /^- ([A-Za-z_][\w.-]*:)(?:\s|$)/.test(text);
    if (listMap) {
      tokens.push({ indent, text: '-' });
      tokens.push({ indent: indent + 2, text: text.slice(2) });
    } else tokens.push({ indent, text });
  }
  function scalar(value) {
    if (/^[\[\]{}&*!|>%@`]/.test(value) || /(?:^|\s)[&*][\w-]+/.test(value)) fail('unsupported_manifest');
    if (value.startsWith('"')) {
      try { return JSON.parse(value); } catch { fail('unsupported_manifest'); }
    }
    if (value.startsWith("'")) {
      if (!value.endsWith("'")) fail('unsupported_manifest');
      return value.slice(1, -1).replace(/''/g, "'");
    }
    return value;
  }
  let cursor = 0;
  function block(indent) {
    const sequence = /^-(?:\s|$)/.test(tokens[cursor].text);
    const out = sequence ? [] : Object.create(null);
    while (cursor < tokens.length && tokens[cursor].indent === indent) {
      const token = tokens[cursor++];
      const match = sequence ? /^-(?: (.*))?$/.exec(token.text) : /^([A-Za-z_][\w.-]*):(?: (.*))?$/.exec(token.text);
      if (!match) fail('unsupported_manifest');
      const key = sequence ? null : match[1];
      const value = (sequence ? match[1] : match[2]) ?? '';
      let parsed;
      if (value) {
        parsed = scalar(value);
        if (cursor < tokens.length && tokens[cursor].indent > indent) fail('unsupported_manifest');
      } else if (cursor < tokens.length && tokens[cursor].indent > indent) {
        if (tokens[cursor].indent !== indent + 2) fail('unsupported_manifest');
        parsed = block(indent + 2);
      } else parsed = null;
      if (sequence) out.push(parsed);
      else {
        if (Object.hasOwn(out, key)) fail('unsupported_manifest');
        out[key] = parsed;
      }
    }
    return out;
  }
  if (!tokens.length || tokens[0].indent !== 0) fail('unsupported_manifest');
  const result = block(0);
  if (cursor !== tokens.length || !object(result)) fail('unsupported_manifest');
  return result;
}

function safeRelative(member, value) {
  if (typeof value !== 'string' || !value || /[\\\0\r\n:*?\[\]{}]/.test(value) || path.posix.isAbsolute(value)) fail('unsupported_graph');
  const resolved = path.posix.normalize(path.posix.join(member, value));
  if (resolved === '..' || resolved.startsWith('../')) fail('unsupported_graph');
  return resolved;
}

function validateDevDependencies(dependencies) {
  if (dependencies == null) return;
  if (!object(dependencies)) fail('unsupported_graph');
  // A path/git dev dependency can still be imported by production Dart and
  // introduce an input outside the regular runtime dependency graph.
  if (Object.values(dependencies).some((dependency) => object(dependency) && (dependency.path || dependency.git))) fail('unsupported_graph');
}

function unsupportedEntrypoint(file, prefix, includeApi) {
  if (!file.startsWith(prefix)) return false;
  const local = file.slice(prefix.length);
  return (includeApi && (local === 'api' || local.startsWith('api/')))
    || /^(?:src\/)?(?:middleware|proxy)\.[^/]+$/.test(local)
    || /^(?:vercel\.(?:[cm]?[jt]s|toml)|now\.json)$/.test(local);
}

// A lexer for boundary checks only; it never evaluates source. Keeping string
// literals separate from comments covers multiline and comment-separated
// directives without treating a sample import inside a comment as code.
function sourceTokens(source) {
  const tokens = [];
  let i = 0;
  while (i < source.length) {
    if (/\s/.test(source[i])) { i++; continue; }
    if (source.startsWith('//', i)) {
      const end = source.indexOf('\n', i + 2);
      i = end < 0 ? source.length : end + 1;
      continue;
    }
    if (source.startsWith('/*', i)) {
      let depth = 1;
      i += 2;
      while (i < source.length && depth) {
        if (source.startsWith('/*', i)) { depth++; i += 2; }
        else if (source.startsWith('*/', i)) { depth--; i += 2; }
        else i++;
      }
      if (depth) fail('unsupported_graph');
      continue;
    }
    const raw = source[i] === 'r' && /["']/.test(source[i + 1] ?? '');
    if (raw) i++;
    if (/["'`]/.test(source[i])) {
      const quote = source[i];
      const delimiter = quote !== '`' && source.startsWith(quote.repeat(3), i) ? quote.repeat(3) : quote;
      i += delimiter.length;
      const start = i;
      let escaped = false;
      while (i < source.length && !source.startsWith(delimiter, i)) {
        if (!raw && source[i] === '\\') { escaped = true; i += 2; }
        else i++;
      }
      if (i >= source.length) fail('unsupported_graph');
      tokens.push({ string: source.slice(start, i), escaped, template: quote === '`' });
      i += delimiter.length;
      continue;
    }
    const word = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(source.slice(i));
    if (word) { tokens.push({ word: word[0] }); i += word[0].length; }
    else tokens.push({ word: source[i++] });
  }
  return tokens;
}

function ordinaryUri(token) {
  if (!token || typeof token.string !== 'string' || token.escaped || token.template || /[\r\n$%#?]/.test(token.string)) fail('unsupported_graph');
  return token.string;
}

function treeFiles(repo, revision, roots) {
  // Listing modes before filtering also exposes a symlink/gitlink ancestor of
  // a declared nested asset, which a leaf-only Git pathspec could miss.
  const listing = git(repo, ['ls-tree', '-r', '-z', revision]).text;
  if (listing && !listing.endsWith('\0')) fail('git_error');
  const files = [];
  for (const entry of listing ? listing.slice(0, -1).split('\0') : []) {
    const match = /^(\d+) (?:blob|commit) [a-f0-9]{40}\t([\s\S]+)$/.exec(entry);
    if (!match) fail('git_error');
    if (!roots.some((root) => match[2] === root || below(match[2], root) || below(root, match[2]))) continue;
    if (!['100644', '100755'].includes(match[1])) fail('unsupported_file_mode');
    files.push(match[2]);
  }
  return files;
}

function validateDartImports(repo, revision, manifests, reachable) {
  // Two batched Git reads, not one subprocess per Dart file. Reading complete
  // modules covers multiline/conditional directives and relative part files.
  const roots = [...reachable].map((member) => `${member}/lib`);
  const names = new Map([...reachable].map((member) => [manifests.get(member).name, member]));
  const files = treeFiles(repo, revision, roots).filter((file) => file.endsWith('.dart'));
  if (!files.length) fail('unsupported_graph');
  const sources = readBatch(repo, revision, files);
  for (const [filename, source] of sources) {
    const tokens = sourceTokens(source);
    for (let i = 0; i < tokens.length; i++) {
      if (!['import', 'export', 'part'].includes(tokens[i].word)) continue;
      if (tokens[i].word === 'part' && tokens[i + 1]?.word !== 'of' && typeof tokens[i + 1]?.string !== 'string') continue;
      const uris = [];
      const namedPart = tokens[i].word === 'part' && tokens[i + 1]?.word === 'of';
      while (++i < tokens.length && tokens[i].word !== ';') {
        if (typeof tokens[i].string === 'string') uris.push(ordinaryUri(tokens[i]));
      }
      if (i === tokens.length || (!uris.length && !namedPart)) fail('unsupported_graph');
      for (const uri of uris) {
        if (uri.startsWith('dart:')) continue;
        if (uri.startsWith('package:')) {
          const match = /^package:([a-z][a-z0-9_]*)\/(.+)$/.exec(uri);
          if (!match) fail('unsupported_graph');
          const packageTarget = safeRelative('package/lib', match[2]);
          if (!below(packageTarget, 'package/lib')) fail('unsupported_graph');
          if (!match[1].startsWith('restoflow_')) continue;
          if (!names.has(match[1])) fail('undeclared_workspace_import');
          const target = safeRelative(`${names.get(match[1])}/lib`, match[2]);
          if (!roots.some((root) => below(target, root))) fail('unsupported_graph');
        } else {
          const target = safeRelative(path.posix.dirname(filename), uri);
          if (uri.includes('$') || !roots.some((root) => below(target, root))) fail('unsupported_graph');
        }
      }
    }
  }
}

/** Derive and validate the product input graph at an immutable Git revision. */
export function inspectGraph(repoRoot, revision = 'HEAD') {
  const resolved = git(repoRoot, ['rev-parse', '--verify', `${revision}^{commit}`]).text.trim();
  if (!SHA.test(resolved)) fail('git_error');
  const root = parseManifest(read(repoRoot, resolved, 'pubspec.yaml'));
  if (Object.keys(root).some((key) => !['name', 'description', 'publish_to', 'environment', 'workspace', 'dev_dependencies', 'melos'].includes(key))) fail('unsupported_graph');
  validateDevDependencies(root.dev_dependencies);
  if (!Array.isArray(root.workspace) || !root.workspace.length || root.dependency_overrides) fail('unsupported_graph');
  const members = root.workspace;
  if (new Set(members).size !== members.length || members.some((p) => typeof p !== 'string' || !/^(?:apps|packages)\/[a-z][a-z0-9_]*$/.test(p))) fail('unsupported_graph');
  if (root.dependencies && Object.keys(root.dependencies).length) fail('unsupported_graph');
  const manifests = new Map();
  const names = new Map();
  const controls = git(repoRoot, ['ls-tree', '-r', '-z', '--name-only', resolved]).text.split('\0');
  if (controls.some((file) => unsupportedEntrypoint(file, '', true))) fail('unsupported_build_contract');
  if (controls.some((file) => file === '.vercelignore' || file === 'pubspec_overrides.yaml' || members.some((member) => file === `${member}/pubspec_overrides.yaml` || file === `${member}/build.yaml` || below(file, `${member}/hook`) || below(file, `${member}/hooks`)))) fail('unsupported_build_contract');
  const files = readBatch(repoRoot, resolved, [...members.map((member) => `${member}/pubspec.yaml`), 'tools/vercel_build_web.sh', 'vercel.json']);
  for (const member of members) {
    const parsed = parseManifest(files.get(`${member}/pubspec.yaml`));
    if (Object.keys(parsed).some((key) => !['name', 'description', 'publish_to', 'version', 'environment', 'resolution', 'dependencies', 'dev_dependencies', 'flutter'].includes(key))) fail('unsupported_graph');
    validateDevDependencies(parsed.dev_dependencies);
    if (!/^restoflow_[a-z0-9_]+$/.test(parsed.name ?? '') || parsed.resolution !== 'workspace' || names.has(parsed.name) || parsed.dependency_overrides || parsed.workspace) fail('unsupported_graph');
    names.set(parsed.name, member);
    manifests.set(member, { ...parsed, edges: [], internalNames: new Set() });
  }
  for (const [member, manifest] of manifests) {
    if (manifest.dependencies != null && !object(manifest.dependencies)) fail('unsupported_graph');
    for (const [name, dependency] of Object.entries(manifest.dependencies ?? {})) {
      if (names.has(name)) {
        if (!object(dependency) || Object.keys(dependency).some((key) => !['path', 'version'].includes(key))) fail('unsupported_graph');
        const destination = safeRelative(member, dependency.path);
        if (names.get(name) !== destination) fail('unsupported_graph');
        manifest.edges.push(destination);
        manifest.internalNames.add(name);
      } else if (object(dependency)) {
        if (dependency.path || dependency.git || Object.keys(dependency).some((key) => !['sdk', 'hosted', 'version'].includes(key))) fail('unsupported_graph');
      } else if (typeof dependency !== 'string' && dependency !== null) fail('unsupported_graph');
      if (name.startsWith('restoflow_') && !names.has(name)) fail('unsupported_graph');
    }
  }
  const script = files.get('tools/vercel_build_web.sh');
  // This contract guard must be reviewed with changes to the build pipeline.
  // A changed builder always builds until its new input graph is understood.
  if (hash(script) !== BUILD_SCRIPT_HASH) fail('unsupported_build_contract');
  const actualApps = [...script.matchAll(/^\(cd (apps\/[a-z0-9_]+) && "\$FLUTTER" build web /gm)].map((m) => m[1]);
  if (JSON.stringify(actualApps) !== JSON.stringify(APPS)) fail('unsupported_build_contract');
  const config = JSON.parse(files.get('vercel.json'));
  if (Object.keys(config).some((key) => !['$schema', 'framework', 'installCommand', 'buildCommand', 'outputDirectory', 'ignoreCommand', 'rewrites', 'redirects', 'headers', 'cleanUrls', 'trailingSlash'].includes(key))) fail('unsupported_build_contract');
  if (config.buildCommand !== 'bash tools/vercel_build_web.sh' || config.outputDirectory !== 'apps/dashboard/build/web' || config.framework !== null || config.installCommand !== 'if [ ! -d flutter ]; then git clone https://github.com/flutter/flutter.git --depth 1 -b 3.44.2 flutter; fi && flutter/bin/flutter config --enable-web && flutter/bin/flutter pub get') fail('unsupported_build_contract');
  const reachable = new Set();
  function visit(member) {
    if (reachable.has(member)) return;
    if (!manifests.has(member)) fail('unsupported_graph');
    reachable.add(member);
    for (const edge of manifests.get(member).edges) visit(edge);
  }
  APPS.forEach(visit);
  const assets = [];
  for (const member of reachable) {
    const flutter = manifests.get(member).flutter;
    if (flutter == null) continue;
    if (!object(flutter) || Object.keys(flutter).some((key) => !['uses-material-design', 'generate', 'assets', 'fonts'].includes(key))) fail('unsupported_graph');
    if (flutter.generate != null && flutter.generate !== 'false') fail('unsupported_build_contract');
    if (flutter.assets != null) {
      if (!Array.isArray(flutter.assets)) fail('unsupported_graph');
      for (const asset of flutter.assets) {
        const location = safeRelative(member, asset);
        assets.push({ path: location.replace(/\/$/, ''), directory: asset.endsWith('/') });
      }
    }
    if (flutter.fonts != null) {
      if (!Array.isArray(flutter.fonts)) fail('unsupported_graph');
      for (const font of flutter.fonts) {
        if (!object(font) || !Array.isArray(font.fonts) || Object.keys(font).some((key) => !['family', 'fonts'].includes(key))) fail('unsupported_graph');
        for (const face of font.fonts) {
          if (!object(face) || Object.keys(face).some((key) => !['asset', 'weight', 'style'].includes(key))) fail('unsupported_graph');
          assets.push({ path: safeRelative(member, face.asset), directory: false });
        }
      }
    }
  }
  treeFiles(repoRoot, resolved, [...assets.map((asset) => asset.path), ...APPS.map((app) => `${app}/web`)]);
  validateDartImports(repoRoot, resolved, manifests, reachable);
  return { members: [...members], deployedApps: [...APPS], reachableMembers: [...reachable].sort(), assets };
}

function inspectMarketing(repo, revision) {
  const controls = git(repo, ['ls-tree', '-r', '-z', '--name-only', revision, '--', '.vercelignore', 'site']).text.split('\0');
  if (controls.some((file) => ['.vercelignore', 'site/.vercelignore'].includes(file) || unsupportedEntrypoint(file, 'site/', false))) fail('unsupported_build_contract');
  const runtimeFiles = treeFiles(repo, revision, ['site/src', 'site/api', 'site/lib', 'site/public']);
  if (runtimeFiles.some((file) => below(file, 'site/api') && !/\.(?:m?js|cjs|ts)$/.test(file))) fail('unsupported_build_contract');
  const modules = runtimeFiles.filter((file) => /\.(?:m?js|cjs|ts)$/.test(file) && !below(file, 'site/public'));
  const files = readBatch(repo, revision, ['site/vercel.json', 'site/package.json', 'site/scripts/build.mjs', ...modules]);
  const config = JSON.parse(files.get('site/vercel.json'));
  const manifest = JSON.parse(files.get('site/package.json'));
  if (Object.keys(config).some((key) => !['$schema', 'framework', 'installCommand', 'buildCommand', 'outputDirectory', 'ignoreCommand', 'trailingSlash', 'cleanUrls', 'functions', 'redirects', 'headers', 'rewrites'].includes(key))) fail('unsupported_build_contract');
  if (!object(config.functions) || Object.keys(config.functions).some((key) => key !== 'api/lead.js') || !object(config.functions['api/lead.js']) || Object.keys(config.functions['api/lead.js']).some((key) => !['maxDuration', 'memory'].includes(key))) fail('unsupported_build_contract');
  if (Object.keys(manifest).some((key) => !['name', 'version', 'private', 'description', 'type', 'engines', 'scripts'].includes(key)) || manifest.type !== 'module') fail('unsupported_build_contract');
  if (config.framework !== null || config.installCommand !== 'echo skip-install' || config.buildCommand !== 'node scripts/build.mjs' || config.outputDirectory !== 'dist' || manifest.dependencies || manifest.devDependencies) fail('unsupported_build_contract');
  if (hash(files.get('site/scripts/build.mjs')) !== SITE_BUILDER_HASH) fail('unsupported_build_contract');
  // Relative imports must stay inside watched runtime trees. The only current
  // filesystem reader is the guarded builder; new dynamic loaders fail open.
  for (const filename of modules) {
    const source = files.get(filename);
    if (/\b(?:import|require)\s*\(/.test(source) || /\b(?:import|require|from)\s*\/[/*]/.test(source)) fail('unsupported_graph');
    for (const match of source.matchAll(/(?:\bfrom\s*|\bimport\s*)["']([^"']+)["']/g)) {
      const uri = match[1];
      if (/[\\%#?$\r\n]/.test(uri)) fail('unsupported_graph');
      if (!uri.startsWith('.')) fail('unsupported_graph');
      const target = safeRelative(path.posix.dirname(filename), uri);
      if (!['site/src', 'site/api', 'site/lib', 'site/public'].some((root) => below(target, root))) fail('unsupported_graph');
    }
  }
}

// The literal directory prefix of a tsconfig include/exclude pattern, i.e. the
// shallowest path TypeScript can reach through it. Trailing glob segments mean
// "everything below here"; a literal segment after a glob is not modelled and
// fails safe. '**/*.ts' reduces to '.', exactly the unsafe contract the caller
// must reject, while 'app/**/*.tsx' reduces to the safe 'app'.
function tsconfigGraphRoot(entry) {
  if (typeof entry !== 'string' || !entry) fail('unsupported_build_contract');
  const prefix = [];
  let globbed = false;
  for (const segment of entry.split('/')) {
    if (!/[*?[\]{}]/.test(segment)) {
      if (globbed) fail('unsupported_build_contract');
      if (segment !== '' && segment !== '.') prefix.push(segment);
      continue;
    }
    globbed = true;
    if (!/^(?:\*\*|\*(?:\.[A-Za-z0-9]+)?)(?![\s\S])/.test(segment)) fail('unsupported_build_contract');
  }
  return prefix.join('/') || '.';
}

// Guarded input contract for the server-built storefront (STOREFRONT-READ-001:
// a Next.js server build, no static export), run at BOTH the baseline and the
// head revision like inspectMarketing. Every failure BUILDs: an input this
// engine does not understand must never be silently ignored. Consequence: the
// first push after a contract change (e.g. a STOREFRONT_CONFIG_HASH re-pin)
// fails the guard at the OLD baseline and builds the storefront by fail-safe
// exactly once; the next push classifies normally.
function inspectStorefront(repo, revision) {
  const controls = git(repo, ['ls-tree', '-r', '-z', '--name-only', revision, '--', '.vercelignore', 'storefront']).text.split('\0');
  // 1-2. No checkout override, and no request-time entrypoint: an exported
  // site has none, so adding one must be a reviewed engine change.
  if (controls.some((file) => ['.vercelignore', 'storefront/.vercelignore'].includes(file) || unsupportedEntrypoint(file, 'storefront/', false))) fail('unsupported_build_contract');
  // 5. Pre-check existence: without it cat-file --batch prints "<spec> missing",
  // the header regex fails, and the reason degrades to unsupported_graph.
  for (const required of ['storefront/package.json', 'storefront/package-lock.json', 'storefront/vercel.json', 'storefront/next.config.mjs', 'storefront/tsconfig.json']) {
    if (!controls.includes(required)) fail('unsupported_build_contract');
  }
  const files = readBatch(repo, revision, ['storefront/vercel.json', 'storefront/package.json', 'storefront/next.config.mjs', 'storefront/tsconfig.json']);
  // 3. Deployment config.
  const config = JSON.parse(files.get('storefront/vercel.json'));
  if (Object.keys(config).some((key) => !['$schema', 'framework', 'installCommand', 'buildCommand', 'ignoreCommand', 'trailingSlash', 'cleanUrls', 'headers', 'redirects', 'rewrites'].includes(key))) fail('unsupported_build_contract');
  if (config.framework !== 'nextjs' || config.installCommand !== 'npm ci' || config.buildCommand !== 'npm run build' || config.functions) fail('unsupported_build_contract');
  // Exact values, not merely allowed keys: an explicit outputDirectory (any value,
  // null included - the key is what overrides the preset) is outside the
  // contract, and a different ignoreCommand means the project is filtered by
  // something other than this reviewed engine.
  if (Object.hasOwn(config, 'outputDirectory') || config.ignoreCommand !== STOREFRONT_IGNORE_COMMAND) fail('unsupported_build_contract');
  for (const key of ['rewrites', 'redirects']) {
    if (config[key] != null && (!Array.isArray(config[key]) || config[key].length)) fail('unsupported_build_contract');
  }
  // 4. Package manifest: private, exact versions, allowlisted runtime deps.
  const manifest = JSON.parse(files.get('storefront/package.json'));
  if (!object(manifest) || Object.keys(manifest).some((key) => !['name', 'version', 'private', 'description', 'engines', 'scripts', 'dependencies', 'devDependencies'].includes(key))) fail('unsupported_build_contract');
  if (manifest.private !== true || !object(manifest.scripts) || manifest.scripts.build !== 'next build') fail('unsupported_build_contract');
  if (Object.keys(manifest.scripts).some((key) => !STOREFRONT_SCRIPT_KEYS.includes(key))) fail('unsupported_build_contract');
  if (manifest.dependencies != null && (!object(manifest.dependencies) || Object.keys(manifest.dependencies).some((name) => !['next', 'react', 'react-dom'].includes(name)))) fail('unsupported_build_contract');
  if (manifest.devDependencies != null && !object(manifest.devDependencies)) fail('unsupported_build_contract');
  // The Vercel project's Node.js Version setting is authoritative for the runtime
  // (DEPLOYMENT.md §15); this engine never reads engines/.nvmrc to decide
  // relevance, it only bounds their shape. Both are storefront_runtime, so editing
  // either one BUILDs regardless of what it says.
  if (manifest.engines != null && (!object(manifest.engines) || Object.keys(manifest.engines).some((key) => key !== 'node') || typeof manifest.engines.node !== 'string')) fail('unsupported_build_contract');
  for (const group of [manifest.dependencies, manifest.devDependencies]) {
    for (const value of Object.values(group ?? {})) {
      if (typeof value !== 'string' || !/^\d+\.\d+\.\d+(?![\s\S])/.test(value)) fail('unsupported_build_contract');
    }
  }
  // 6. The config that decides what the build reads is pinned by hash.
  if (hash(files.get('storefront/next.config.mjs')) !== STOREFRONT_CONFIG_HASH) fail('unsupported_build_contract');
  // 7. TypeScript build-graph boundary. STAGE 7 R2 moved this from load-bearing
  // to defence in depth: the classifier no longer ignores anything under
  // storefront/, so this no longer licenses an IGNORE. It still earns its keep by
  // holding the build graph inside the reviewed runtime roots, which is what makes
  // changes OUTSIDE storefront/ safe to ignore for the storefront, and by keeping
  // the contract small enough to review. A TypeScript program is
  // files ∪ (include − exclude) ∪ transitive imports ∪ ambient type roots, all
  // inheritable through extends, and `next build` type-checks exactly that
  // program. Only `include` and the import graph can add repository paths to it,
  // so: extends/files/references are refused by the top-level key allowlist;
  // `include` is REQUIRED because its default is **/* (which DOES type-check the
  // tests); no include entry may overlap a storefront-local root in either direction;
  // ambient-declaration keys are refused; and `paths` is pinned to the single
  // mapping step 8 resolves. Widening it fails inspection, which BUILDs.
  const tsconfig = JSON.parse(files.get('storefront/tsconfig.json'));
  if (!object(tsconfig) || Object.keys(tsconfig).some((key) => !['$schema', 'compilerOptions', 'include', 'exclude'].includes(key))) fail('unsupported_build_contract');
  const compiler = tsconfig.compilerOptions;
  if (compiler != null && !object(compiler)) fail('unsupported_build_contract');
  if (compiler?.baseUrl != null && compiler.baseUrl !== '.') fail('unsupported_build_contract');
  // types/typeRoots/rootDirs each pull declaration files in from an arbitrary
  // directory, storefront/tests included. Their defaults reach node_modules only.
  if (['types', 'typeRoots', 'rootDirs'].some((key) => compiler?.[key] != null)) fail('unsupported_build_contract');
  // Pinned rather than merely contained, because step 8 RESOLVES `@/x` as
  // storefront/src/x. A remapped alias would make that resolution a fiction.
  const aliases = compiler?.paths;
  if (aliases != null) {
    const keys = Object.keys(aliases);
    const targets = aliases['@/*'];
    if (keys.length !== 1 || keys[0] !== '@/*' || !Array.isArray(targets) || targets.length !== 1 || targets[0] !== './src/*') fail('unsupported_build_contract');
  }
  if (!Array.isArray(tsconfig.include) || !tsconfig.include.length) fail('unsupported_build_contract');
  for (const entry of tsconfig.include) {
    const root = safeRelative('storefront', tsconfigGraphRoot(entry));
    // safeRelative only rejects a NORMALISED '../' result, and '../docs' normalises
    // to 'docs' — inside the repository, so not an escape by that test. Containment
    // must be asserted positively or the TypeScript program can reach another
    // project's source, which the storefront selector then ignores.
    if (!insideStorefront(root)) fail('unsupported_build_contract');
    // Overlap in EITHER direction: '.' contains storefront/tests, and
    // 'tests/unit' is contained by it. Both widen the program past the runtime roots.
    if (STOREFRONT_LOCAL_ROOTS.some((dir) => root === dir || below(root, dir) || below(dir, root))) fail('unsupported_build_contract');
  }
  // exclude only ever subtracts from include, so it cannot widen the program;
  // it still may not name a path outside the Root Directory.
  if (tsconfig.exclude != null) {
    if (!Array.isArray(tsconfig.exclude)) fail('unsupported_build_contract');
    for (const entry of tsconfig.exclude) { if (!insideStorefront(safeRelative('storefront', tsconfigGraphRoot(entry)))) fail('unsupported_build_contract'); }
  }
  // 8. Module containment: every specifier resolves inside the runtime roots, or
  // is one of the allowlisted front-end bare imports. A future shared JS package
  // therefore BUILDs until the engine is taught about it. STAGE 7 R3 removed the
  // blanket `node:` allowance: with dynamic import()/require() already refused and
  // relative/alias specifiers already contained, dropping Node builtins closes the
  // last route by which storefront build-time code could read a repository path
  // outside storefront/ and make a later change to it a false IGNORE.
  // Scanned by DEFAULT: the file set is the storefront ROOT minus STOREFRONT_UNSCANNED,
  // never an enumeration of code directories. Enumerating is what left
  // storefront/pages and every root-level config module unread, and a module the
  // scan never opens is an escape hatch whatever the contract above says. Extensions
  // are spelled out because .jsx is a DEFAULT Next pageExtension and .mts/.cts are
  // valid TypeScript. next.config is excluded because it is pinned by hash at step 6
  // and its JSDoc `import('next')` annotation would trip the dynamic-import test
  // forever; .json is excluded because it declares no imports and reading the
  // lockfile here would be pure cost.
  const moduleFiles = treeFiles(repo, revision, ['storefront']).filter((file) => /\.(?:ts|tsx|mts|cts|js|jsx|mjs|cjs)(?![\s\S])/.test(file)
    && !below(file, 'storefront/public') && !storefrontLocal(file)
    && !/^storefront\/next\.config\.(?:mjs|js|ts)(?![\s\S])/.test(file));
  if (moduleFiles.length) {
    const sources = readBatch(repo, revision, moduleFiles);
    for (const [filename, source] of sources) {
      if (/\b(?:import|require)\s*\(/.test(source)) fail('unsupported_graph');
      if (STOREFRONT_BUILTIN_HANDLES.test(source)) fail('unsupported_graph');
      for (const match of source.matchAll(/(?:\bfrom\s*|\bimport\s*)["']([^"']+)["']/g)) {
        const uri = match[1];
        if (/[\\%#?$\r\n]/.test(uri)) fail('unsupported_graph');
        if (uri.startsWith('.')) {
          const target = safeRelative(path.posix.dirname(filename), uri);
          if (!STOREFRONT_RUNTIME_ROOTS.some((root) => below(target, root))) fail('unsupported_graph');
        } else if (uri.startsWith('@/')) {
          const target = safeRelative('storefront/src', uri.slice(2));
          if (!below(target, 'storefront/src')) fail('unsupported_graph');
        } else if (!STOREFRONT_BARE_IMPORTS.includes(uri) && !uri.startsWith('next/')) {
          fail('unsupported_graph');
        }
      }
    }
  }
  // 9. public/ is the engine-level enforcement of "reference videos = ZERO".
  const publicFiles = treeFiles(repo, revision, ['storefront/public']).filter((file) => below(file, 'storefront/public'));
  if (publicFiles.some((file) => !STOREFRONT_PUBLIC_TYPES.includes(path.posix.extname(file).toLowerCase()))) fail('unsupported_build_contract');
  if (publicFiles.length) {
    for (const size of blobSizes(repo, revision, publicFiles).values()) {
      if (size > 256 * 1024) fail('unsupported_build_contract');
    }
  }
}

function fetchBaseline(repo, spec, acquisition, repositoryUrl) {
  if (!SHA.test(spec) && spec !== `refs/heads/${PRODUCTION_BRANCH}`) fail('invalid_fetch_target');
  // Resolve this literal URL without a network request. Never accept an
  // insteadOf/config rewrite as an alternative authority (or inspect origin).
  const effective = git(repo, ['ls-remote', '--get-url', repositoryUrl]).text.replace(/\r?\n$/, '');
  if (effective !== repositoryUrl) fail('baseline_source_rewritten');
  // Empty refmap suppresses configured remote-tracking updates. Explicit
  // no-prune flags override inherited config. Only objects/shallow/FETCH_HEAD
  // metadata may change; no local or remote-tracking branch is moved.
  acquisition.fetched = true; // attempted, including failures/timeouts
  const result = spawnSync('git', ['-C', repo, '-c', 'core.hooksPath=/dev/null',
    '-c', 'credential.helper=', '-c', 'http.extraHeader=', '-c', 'http.followRedirects=false',
    'fetch', '--no-tags', '--depth=1', '--no-recurse-submodules',
    '--no-auto-maintenance', '--no-write-commit-graph', '--no-prune',
    '--no-prune-tags', '--refmap=', repositoryUrl, spec], {
    encoding: null, maxBuffer: 1024 * 1024, timeout: FETCH_TIMEOUT_MS,
    killSignal: 'SIGKILL', windowsHide: true,
    env: { ...process.env, GIT_OPTIONAL_LOCKS: '0', GIT_NO_REPLACE_OBJECTS: '1',
      GIT_NO_LAZY_FETCH: '1', GIT_TERMINAL_PROMPT: '0', GCM_INTERACTIVE: 'Never' },
  });
  // Git stderr may contain transport/config details. Never forward it.
  if (result.error || result.status !== 0) fail('baseline_fetch_failed');
  const receiptPath = git(repo, ['rev-parse', '--git-path', 'FETCH_HEAD']).text.trim();
  const receipts = readFileSync(path.resolve(repo, receiptPath), 'utf8').trimEnd().split('\n');
  if (receipts.length !== 1) fail('invalid_fetch_result');
  const receipt = /^([a-f0-9]{40})\t\t([^\r\n]+)\r?$/.exec(receipts[0]);
  if (!receipt || (SHA.test(spec) && receipt[1].toLowerCase() !== spec.toLowerCase())) fail('invalid_fetch_result');
  if (!SHA.test(spec) && !receipt[2].startsWith(`branch '${PRODUCTION_BRANCH}' of `)) fail('invalid_fetch_result');
  return commit(repo, receipt[1]);
}

function verifyProductionBranch(repo, revision) {
  // The checked-in CI trigger establishes the source's main-only production
  // policy. Unsupported/ambiguous syntax BUILDs instead of guessing a branch.
  const source = read(repo, revision, '.github/workflows/ci.yml').replace(/\r\n/g, '\n');
  const events = [...source.matchAll(/^(?:on|'on'|"on"):[^\n]*$/gm)];
  if (events.length !== 1 || events[0][0] !== 'on:') fail('production_branch_unproven');
  const lines = [];
  for (const line of source.slice(events[0].index + events[0][0].length).split('\n')) {
    if (!line.trim() || line.trimStart().startsWith('#')) continue;
    if (!line.startsWith(' ')) break;
    lines.push(line.trimEnd());
  }
  if (lines.join('\n') !== `  pull_request:\n  push:\n    branches: [${PRODUCTION_BRANCH}]`) fail('production_branch_unproven');
}

function selectBaseline(repo, head, env, acquisition, repositoryUrl) {
  const previous = env.VERCEL_GIT_PREVIOUS_SHA ?? '';
  if (previous) {
    acquisition.baselineSource = 'previous_success';
    if (!SHA.test(previous)) fail('invalid_previous_sha');
    try { acquisition.baseline = commit(repo, previous); }
    catch (error) {
      if (error?.message === 'invalid_sha') throw error;
      acquisition.baseline = fetchBaseline(repo, previous.toLowerCase(), acquisition, repositoryUrl);
    }
    // Vercel supplies the last success for this project AND branch. Its tree
    // is authoritative even after a rebase or non-ancestor deployment.
    return;
  }
  if (env.VERCEL_ENV !== 'preview') fail('missing_baseline');
  acquisition.baselineSource = 'production_main';
  const ref = env.VERCEL_GIT_COMMIT_REF ?? '';
  // Optional consistency metadata only. Hosted HEAD may be detached or use a
  // local branch name unrelated to Vercel's ref. Neither chooses our baseline.
  if (ref) {
    if ([PRODUCTION_BRANCH, 'HEAD'].includes(ref) || !/^[A-Za-z0-9][A-Za-z0-9_./-]*(?![\s\S])/.test(ref) || ref.includes('..')) fail('untrusted_feature_ref');
    try { git(repo, ['check-ref-format', '--branch', ref]); }
    catch { fail('untrusted_feature_ref'); }
  }
  verifyProductionBranch(repo, head);
  // origin/main can exist but be stale in a branch clone. Refresh exactly main
  // to FETCH_HEAD without moving origin/main; compare current main's TREE,
  // never a merge base that could hide runtime changes on main.
  acquisition.baseline = fetchBaseline(repo, `refs/heads/${PRODUCTION_BRANCH}`, acquisition, repositoryUrl);
  verifyProductionBranch(repo, acquisition.baseline);
}

// Diagnostic only. Every storefront path is relevant to the storefront selector
// whatever this returns; the name exists so `categories` stays readable in the
// decision JSON and in hosted evidence. Do not make a decision from it.
function storefrontCategory(file) {
  if (STOREFRONT_RUNTIME_ROOTS.some((dir) => below(file, dir))
    || ['storefront/package.json', 'storefront/package-lock.json', 'storefront/npm-shrinkwrap.json', 'storefront/pnpm-lock.yaml', 'storefront/yarn.lock', 'storefront/.npmrc', 'storefront/.nvmrc', 'storefront/tsconfig.json', 'storefront/vercel.json', 'storefront/.vercelignore'].includes(file)
    || /^storefront\/next\.config\.(?:mjs|js|ts)(?![\s\S])/.test(file)
    || /^storefront\/postcss\.config\.[^/]+(?![\s\S])/.test(file)
    || /^storefront\/(?:src\/)?(?:middleware|proxy|instrumentation)\.[^/]+(?![\s\S])/.test(file)) return 'storefront_runtime';
  if (storefrontLocal(file)) return 'storefront_local';
  return 'unknown_storefront_input';
}

function category(file, selector, graphs) {
  if (file === ENGINE) return { relevant: true, name: 'shared_engine' };
  if (file === '.gitattributes' || file === '.vercelignore') return { relevant: true, name: 'checkout_config' };
  if (selector === 'product') {
    if (graphs.some((g) => g.assets.some((a) => file === a.path || (a.directory && below(file, a.path))))) return { relevant: true, name: 'declared_asset' };
    if (['pubspec.yaml', 'pubspec.lock', 'vercel.json', 'tools/vercel_build_web.sh', 'pubspec_overrides.yaml', '.vercelignore'].includes(file) || /^(?:apps|packages)\/[^/]+\/pubspec(?:_overrides)?\.yaml$/.test(file)) return { relevant: true, name: 'product_config' };
    const runtime = new Set(graphs.flatMap((g) => g.reachableMembers));
    for (const member of runtime) {
      if (below(file, `${member}/lib`) || (APPS.includes(member) && below(file, `${member}/web`)) || file === `${member}/l10n.yaml` || file === `${member}/.metadata`) return { relevant: true, name: 'product_runtime' };
    }
  }
  if (file.startsWith('site/')) {
    const runtime = ['site/src', 'site/public', 'site/api', 'site/lib'].some((dir) => below(file, dir)) || ['site/scripts/build.mjs', 'site/vercel.json', 'site/package.json', 'site/package-lock.json', 'site/npm-shrinkwrap.json', 'site/pnpm-lock.yaml', 'site/yarn.lock', 'site/.npmrc', 'site/.vercelignore'].includes(file);
    if (runtime) return { relevant: selector === 'marketing', name: 'marketing_runtime' };
    if (['site/tests', 'site/review', 'site/docs'].some((dir) => below(file, dir)) || /^site\/(?:README(?:\.[^/]*)?|AGENTS\.md|\.gitignore)$/.test(file) || file === 'site/scripts/dev.mjs') return { relevant: false, name: 'tests_docs' };
    return { relevant: selector === 'marketing', name: 'unknown_marketing_input' };
  }
  // STAGE 7 R2. Exactly ONE relevance expression governs the whole storefront
  // subtree: every path under storefront/ is relevant to the storefront and to no
  // other project. storefrontCategory() names the path for diagnostics and decides
  // nothing, so no later edit to those patterns can reintroduce a false IGNORE.
  //
  // Why nothing here may be ignored: proving a path is outside TypeScript's
  // type-check graph (guard step 7) does not prove it is outside the BUILD's
  // dependency graph, and this engine does not model build-time file reads at all.
  // R3's module contract has since closed the node:fs route, but this stays as an
  // INDEPENDENT layer: `eslint.config.*` needs no file read to matter (next build
  // runs ESLint when it is a devDependency, and devDependencies are only
  // shape-checked), the engine guards trusted source rather than sandboxing it so
  // it never proves a file unconsumed, and a later BFF phase that admits a builtin
  // must not silently reopen this. A false BUILD costs one storefront deployment;
  // a false IGNORE serves stale customer-facing output. No exceptions here.
  if (file.startsWith('storefront/')) return { relevant: selector === 'storefront', name: storefrontCategory(file) };
  if (/^(?:apps|packages)\//.test(file)) {
    if (selector !== 'product') return { relevant: false, name: 'product_only' };
    const member = file.split('/').slice(0, 2).join('/');
    if (!graphs.some((g) => g.members.includes(member))) return { relevant: true, name: 'unknown_product_input' };
    const suffix = file.slice(member.length + 1);
    if (/^(?:test|tests|integration_test|android|ios|linux|macos|windows|docs|review|build)\//.test(suffix) || /^(?:README(?:\.[^/]*)?|CHANGELOG\.md|LICENSE(?:\.[^/]*)?|analysis_options\.yaml|\.gitignore)$/.test(suffix)) return { relevant: false, name: 'tests_native_docs' };
    if (!graphs.some((g) => g.reachableMembers.includes(member)) && /^(?:lib|web|assets)\//.test(suffix)) return { relevant: false, name: 'unreachable_member' };
    return { relevant: true, name: 'unknown_product_input' };
  }
  if (['docs', '.github', 'e2e', 'supabase', 'test', 'tests', 'dist'].some((dir) => below(file, dir)) || file === `${ENGINE.slice(0, -4)}.test.mjs` || /^tools\/vercel\/(?:README(?:\.[^/]*)?|docs\/.*)$/.test(file)) return { relevant: false, name: 'tests_docs' };
  if (file.startsWith('tools/') && !file.startsWith('tools/vercel/')) return { relevant: false, name: 'unconsumed_tools' };
  if (/^(?:README(?:\.[^/]*)?|AGENTS\.md|CLAUDE\.md|GEMINI\.md|LICENSE(?:\.[^/]*)?|CHANGELOG\.md|analysis_options\.yaml|melos\.yaml|\.gitignore|\.gitattributes|\.editorconfig)$/.test(file)) return { relevant: false, name: 'repository_metadata' };
  if (selector !== 'product' && ['pubspec.yaml', 'pubspec.lock', 'pubspec_overrides.yaml', 'vercel.json'].includes(file)) return { relevant: false, name: 'product_only' };
  return { relevant: true, name: 'unknown_input' };
}

/** Tests may inject an owned local source via code, never via env/CLI options. */
export function decide({ selector, cwd = process.cwd(), env = process.env, helperFile } = {}, { repositoryUrl = TRUSTED_REPOSITORY_URL } = {}) {
  let head = null;
  const acquisition = { baseline: null, baselineSource: null, fetched: false };
  const categories = {};
  try {
    if (!['product', 'marketing', 'storefront'].includes(selector)) fail('invalid_selector');
    const repo = git(cwd, ['rev-parse', '--show-toplevel']).text.trim();
    const expected = selector === 'product' ? repo : path.join(repo, selector === 'marketing' ? 'site' : 'storefront');
    if (realpathSync(cwd) !== realpathSync(expected)) fail('invalid_cwd');
    if (helperFile && realpathSync(helperFile) !== realpathSync(path.join(repo, ENGINE))) fail('invalid_helper_location');
    const candidateHead = git(repo, ['rev-parse', '--verify', 'HEAD^{commit}']).text.trim().toLowerCase();
    if (!SHA.test(candidateHead)) fail('git_error');
    head = candidateHead;
    if (env.VERCEL_GIT_COMMIT_SHA && (!SHA.test(env.VERCEL_GIT_COMMIT_SHA) || env.VERCEL_GIT_COMMIT_SHA.toLowerCase() !== head)) fail('head_mismatch');
    selectBaseline(repo, head, env, acquisition, repositoryUrl);
    const { baseline } = acquisition;
    const changed = git(repo, ['diff', '--no-ext-diff', '--no-textconv', '--name-only', '--no-renames', '-z', baseline, head, '--']).text;
    if (changed && !changed.endsWith('\0')) fail('git_error');
    const files = changed ? changed.slice(0, -1).split('\0') : [];
    const graphs = selector === 'product' ? [inspectGraph(repo, baseline), inspectGraph(repo, head)] : [];
    if (selector === 'marketing') { inspectMarketing(repo, baseline); inspectMarketing(repo, head); }
    if (selector === 'storefront') { inspectStorefront(repo, baseline); inspectStorefront(repo, head); }
    let relevant = false;
    for (const file of files) {
      const item = category(file, selector, graphs);
      categories[item.name] = (categories[item.name] ?? 0) + 1;
      relevant ||= item.relevant;
    }
    return { decision: relevant ? 'BUILD' : 'IGNORE', reason: relevant ? 'relevant_changes' : files.length ? 'unaffected_changes' : 'no_changes', ...acquisition, head, categories };
  } catch (error) {
    const known = new Set(['git_error', 'invalid_selector', 'invalid_cwd', 'invalid_helper_location', 'head_mismatch', 'invalid_sha', 'invalid_previous_sha', 'missing_baseline', 'untrusted_feature_ref', 'baseline_source_rewritten', 'baseline_fetch_failed', 'invalid_fetch_target', 'invalid_fetch_result', 'production_branch_unproven', 'unsupported_manifest', 'unsupported_graph', 'unsupported_build_contract', 'undeclared_workspace_import', 'unsupported_encoding', 'unsupported_file_mode']);
    return { decision: 'BUILD', reason: known.has(error?.message) ? error.message : 'helper_error', ...acquisition, head, categories };
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const result = decide({ selector: process.argv.length === 3 ? process.argv[2] : null, helperFile: fileURLToPath(import.meta.url) });
  process.stdout.write(`${JSON.stringify(result)}\n`);
  process.exitCode = result.decision === 'IGNORE' ? 0 : 1;
}
