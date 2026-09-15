// Pure comparator for two static-export inventories.
//
// Importing this module does nothing: no install, no build, no filesystem
// cleanup. It is separated from isolated-build.mjs precisely so its behaviour
// can be unit-tested against small synthetic fixtures.
//
// DESIGN RULE, learned from a real defect at head 67bbd76a: compare everything
// EXACTLY, except narrowly documented build-ID metadata taken from each build's
// OWN known values. The previous version additionally rewrote every
// `/_next/static/chunks/<name>.js` reference to a single `<CHUNK>.js`
// placeholder. That is not build-ID normalisation - it erases WHICH script a
// document loads, so two exports whose pages reference different chunks could
// compare equal. A generic placeholder substitution is never an acceptable
// stand-in for a content-preserving one-to-one mapping.
import { createHash } from 'node:crypto';

const sha = (value) => createHash('sha256').update(value).digest('hex');

/** File extensions compared as normalised text; everything else byte-for-byte. */
const TEXT = /\.(?:html|js|css|json|txt|svg|map|webmanifest)$/;

/**
 * The ONLY permitted normalisation: replace a build's own build-ID literals.
 *
 * Each id is read from that build's own output and replaced as an exact string.
 * No pattern is applied, so a difference that merely LOOKS like an id - a
 * different chunk name, a different RSC query, a changed asset reference -
 * survives into the comparison and fails.
 */
export function normaliseWith(text, buildIds) {
  let out = text;
  for (const id of buildIds) {
    if (!id) continue;
    out = out.split(id).join('<BUILD_ID>');
  }
  return out;
}

/**
 * Build-ID literals discoverable from an export's own index.html: the static
 * asset directory segment and the RSC flight payload "b" field.
 */
export function buildIdsFrom(indexHtml) {
  const ids = new Set();
  if (typeof indexHtml !== 'string') return [];
  const asset = /\/_next\/static\/([A-Za-z0-9_-]{10,})\//.exec(indexHtml);
  if (asset) ids.add(asset[1]);
  for (const m of indexHtml.matchAll(/\\"b\\":\\"([A-Za-z0-9_-]{15,})\\"/g)) ids.add(m[1]);
  for (const m of indexHtml.matchAll(/"b":"([A-Za-z0-9_-]{15,})"/g)) ids.add(m[1]);
  return [...ids];
}

/**
 * @param {Map<string, {bytes:number, content:string|Buffer}>} files
 * @returns {{ entries: Map<string, {digest:string, bytes:number, sourcePaths:string[]}>, problems: string[], buildIds: string[] }}
 */
export function inventoryOf(files, label) {
  const problems = [];
  if (!(files instanceof Map) || files.size === 0) {
    problems.push(`${label}: inventory is missing or empty`);
    return { entries: new Map(), problems, buildIds: [] };
  }
  const index = files.get('index.html');
  if (!index) problems.push(`${label}: index.html is missing, so build IDs cannot be established`);
  const buildIds = index ? buildIdsFrom(String(index.content)) : [];

  const entries = new Map();
  for (const [rawPath, meta] of files) {
    // Paths are normalised too, but only by the same literal rule.
    const key = normaliseWith(rawPath, buildIds);
    const isText = TEXT.test(rawPath);
    const content = meta.content;
    const digest = isText
      ? sha(normaliseWith(typeof content === 'string' ? content : content.toString('utf8'), buildIds))
      : sha(Buffer.isBuffer(content) ? content : Buffer.from(String(content)));

    if (entries.has(key)) {
      // A collision would silently overwrite a file and could hide a real
      // difference. It must fail, never win the last write.
      const existing = entries.get(key);
      existing.sourcePaths.push(rawPath);
      problems.push(`${label}: two files normalise to the same key "${key}": ${existing.sourcePaths.join(', ')}`);
      continue;
    }
    entries.set(key, { digest, bytes: meta.bytes ?? 0, sourcePaths: [rawPath] });
  }
  return { entries, problems, buildIds };
}

/**
 * Compare two inventories. Returns every difference; never "passes" by being
 * permissive. Missing, extra, duplicate-mapped and content differences all fail.
 */
export function compareInventories(aFiles, bFiles, { labelA = 'A', labelB = 'B' } = {}) {
  const a = inventoryOf(aFiles, labelA);
  const b = inventoryOf(bFiles, labelB);
  const problems = [...a.problems, ...b.problems];

  for (const key of a.entries.keys()) {
    if (!b.entries.has(key)) problems.push(`only in ${labelA}: ${key}`);
  }
  for (const key of b.entries.keys()) {
    if (!a.entries.has(key)) problems.push(`only in ${labelB}: ${key}`);
  }

  const differing = [];
  for (const [key, left] of a.entries) {
    const right = b.entries.get(key);
    if (!right) continue;
    if (left.digest !== right.digest) {
      differing.push(key);
      problems.push(`content differs: ${key} (${left.bytes} vs ${right.bytes} bytes)`);
    }
  }

  const routes = (entries) => [...entries.keys()].filter((f) => f.endsWith('.html')).sort();
  const routesA = routes(a.entries);
  const routesB = routes(b.entries);
  if (JSON.stringify(routesA) !== JSON.stringify(routesB)) {
    problems.push(`route inventory differs:\n  ${labelA}: ${routesA.join(', ')}\n  ${labelB}: ${routesB.join(', ')}`);
  }

  return {
    ok: problems.length === 0,
    problems,
    stats: {
      countA: a.entries.size,
      countB: b.entries.size,
      buildIdsA: a.buildIds,
      buildIdsB: b.buildIds,
      routes: routesA,
      differing,
    },
  };
}

/** What was normalised, for the report. There is exactly one rule. */
export const NORMALISATION_DESCRIPTION = [
  'build-ID literals only: each build\'s own id strings, taken from its own index.html',
  '(the /_next/static/<id>/ asset directory segment and the RSC flight "b" field),',
  'replaced as exact literals. No pattern rule is applied, so a differing chunk name,',
  'a differing _rsc query or any changed asset reference is reported, not absorbed.',
].join(' ');
