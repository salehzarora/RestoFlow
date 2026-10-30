// Explicit local integration only: run after a LIVE Next build, never through
// the default unit glob. All merchant responses are synthetic loopback bytes.
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { syntheticV4Envelope } from '../support/content-envelope.mjs';
import { NOT_FOUND_ENVELOPE } from '../support/envelope.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const LOGICAL_ORIGIN = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const SYNTHETIC_KEY = 'sb_publishable_SYNTHETIC_seo_loopback_only_000000';
const ROOTS = ['', '/ar', '/he', '/en'];
const CRAWLER = 'Googlebot';
const NORMAL_BROWSER = 'Mozilla/5.0 SyntheticLocalMetadataTest';
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

async function listen(server) {
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
  return server.address().port;
}
async function freePort() {
  const server = createServer();
  const port = await listen(server);
  await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  return port;
}
function plainHtml(value) {
  return value.replace(/&quot;/g, '"').replace(/&#x27;|&#39;/g, "'").replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&');
}
function attribute(tag, key) {
  return tag.match(new RegExp(`\\b${key}="([^"]*)"`, 'i'))?.[1];
}
function metadataFrom(html) {
  const head = html.match(/<head>([\s\S]*?)<\/head>/i)?.[1];
  assert.ok(head, 'real response has a head');
  const metas = [...head.matchAll(/<meta\b[^>]*>/gi)].map(match => match[0]);
  const links = [...head.matchAll(/<link\b[^>]*>/gi)].map(match => match[0]);
  const meta = name => metas.filter(tag => attribute(tag, 'name')?.toLowerCase() === name).map(tag => plainHtml(attribute(tag, 'content') ?? ''));
  return {
    head,
    title: plainHtml(head.match(/<title>([\s\S]*?)<\/title>/i)?.[1] ?? ''),
    descriptions: meta('description'),
    canonicals: links.filter(tag => attribute(tag, 'rel')?.toLowerCase() === 'canonical').map(tag => plainHtml(attribute(tag, 'href') ?? '')),
    alternates: links.filter(tag => attribute(tag, 'rel')?.toLowerCase() === 'alternate' && /\bhreflang=/i.test(tag)),
    robots: meta('robots'),
  };
}
function assertNoIndex(metadata) {
  assert.ok(metadata.robots.some(value => /\bnoindex\b/.test(value) && /\bnofollow\b/.test(value)), 'noindex/nofollow still emitted');
  assert.equal(metadata.alternates.length, 0, 'no unproven language variants advertised in head');
}
function testPreload(rpcPort, allowedSlugs) {
  return `
const originalFetch = globalThis.fetch;
const logical = ${JSON.stringify(LOGICAL_ORIGIN)};
const key = ${JSON.stringify(SYNTHETIC_KEY)};
const allowedSlugs = new Set(${JSON.stringify(allowedSlugs)});
globalThis.fetch = async function(input, init) {
 const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
 const headers = new Headers(init?.headers ?? input?.headers);
 const method = (init?.method ?? input?.method ?? 'GET').toUpperCase();
 if (url !== logical + '/rest/v1/rpc/storefront_menu_v4' || method !== 'POST' || headers.get('apikey') !== key || headers.get('authorization') !== 'Bearer ' + key) throw new Error('seo_loopback_boundary_denied');
 let body; try { body = JSON.parse(init?.body); } catch { throw new Error('seo_loopback_body_denied'); }
 if (!body || Object.keys(body).join(',') !== 'p_slug' || !allowedSlugs.has(body.p_slug)) throw new Error('seo_loopback_scope_denied');
 return originalFetch('http://127.0.0.1:${rpcPort}/rest/v1/rpc/storefront_menu_v4', { ...init, method, headers, redirect:'error' });
};
`;
}

test('real live Next emits scoped menu metadata while retaining noindex and one read per cold render', { timeout: 180000 }, async t => {
  const checkedSubtest = async (name, operation) => {
    let passed = false;
    await t.test(name, async () => { await operation(); passed = true; });
    assert.ok(passed, `${name}: stop after failed integration evidence`);
  };
  const manifestPath = path.join(ROOT, '.next/prerender-manifest.json');
  assert.ok(existsSync(manifestPath), 'a live local build is required; this test never builds');
  const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
  assert.deepEqual(Object.keys(manifest.routes ?? {}).filter(route => /\/(?:s|r)\//.test(route)), [], 'refuse fixture/stale tenant prerenders');
  const nonce = randomBytes(4).toString('hex');
  const kinds = ['alpha', 'beta', 'normal', 'unknown', 'unpublished', 'transport', 'malformed', 'mismatch', 'unknownbrowser', 'unpublishedbrowser', 'transportbrowser', 'malformedbrowser', 'mismatchbrowser'];
  const slugs = Object.fromEntries(kinds.map(kind => [kind, `sf-seo-it-${nonce}-${kind}`]));
  let publicSample = null;
  if (process.env.BIZBOT_SEO_PUBLIC_SAMPLE) {
    const text = readFileSync(process.env.BIZBOT_SEO_PUBLIC_SAMPLE, 'utf8');
    assert.ok(Buffer.byteLength(text, 'utf8') <= 65536, 'public SSR sample file is bounded');
    const raw = JSON.parse(text);
    assert.ok(typeof raw.slug === 'string' && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(raw.slug) && raw.slug.length >= 3 && raw.slug.length <= 48, 'public sample slug has the existing storage grammar');
    assert.ok(typeof raw.displayName === 'string' && raw.displayName.trim().length > 0 && Array.from(raw.displayName).length <= 60, 'public sample name is a bounded public field');
    assert.ok(raw.tagline === null || typeof raw.tagline === 'string' && Array.from(raw.tagline).length <= 90, 'public sample tagline is a bounded public field');
    assert.equal(raw.url, `https://menu.bizbot.systems/s/${raw.slug}/menu`, 'sample came from the exact public menu URL');
    publicSample = { slug: raw.slug, displayName: raw.displayName, tagline: raw.tagline };
    assert.ok(!Object.values(slugs).includes(publicSample.slug), 'public sample and synthetic test scopes are distinct');
    slugs.publicsample = publicSample.slug;
  }
  const hostileName = 'Synthetic Alpha </title><script>alert(1)</script> & Café';
  const description = 'Synthetic description <img src=x onerror=alert(1)> & text';
  const counts = new Map();
  const rejected = [];
  const rpc = createServer(async (req, res) => {
    let text = '';
    for await (const chunk of req) { text += chunk; if (text.length > 1024) { res.writeHead(413).end(); return; } }
    let body; try { body = JSON.parse(text); } catch { body = null; }
    const slug = body?.p_slug;
    if (req.method !== 'POST' || req.url !== '/rest/v1/rpc/storefront_menu_v4' || req.headers.apikey !== SYNTHETIC_KEY || req.headers.authorization !== `Bearer ${SYNTHETIC_KEY}` || !Object.values(slugs).includes(slug) || Object.keys(body).join(',') !== 'p_slug') {
      rejected.push({ method: req.method, path: req.url }); res.writeHead(403).end(); return;
    }
    counts.set(slug, (counts.get(slug) ?? 0) + 1);
    const kind = Object.entries(slugs).find(([, candidate]) => candidate === slug)?.[0];
    const behavior = kind.replace(/browser$/, '');
    if (behavior === 'transport') { res.writeHead(503, { 'Content-Type': 'application/json' }).end('{"error":"synthetic_transport_failure"}'); return; }
    let payload;
    if (['unknown', 'unpublished'].includes(behavior)) payload = NOT_FOUND_ENVELOPE;
    else {
      const base = syntheticV4Envelope();
      const beta = slug === slugs.beta;
      const sample = kind === 'publicsample';
      payload = syntheticV4Envelope({
        restaurant: { ...base.restaurant, slug: behavior === 'mismatch' ? slugs.beta : slug, display_name: sample ? publicSample.displayName : beta ? 'Synthetic Beta Closed' : hostileName, tagline: sample ? publicSample.tagline : beta ? null : description, phone: null, motion: 'calm', logo_url: null, hero_url: null },
        service: { state: beta ? 'closed' : 'open', ordering_enabled: false, pickup_enabled: true, delivery_enabled: false },
        hours: { ...base.hours, open_now: !beta },
        items: base.items.map(item => ({ ...item, image_url: null })),
      });
      if (behavior === 'malformed') payload = { ...payload, restaurant: { ...payload.restaurant, display_name: 12 } };
    }
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(payload));
  });
  let next;
  let nextOutput = '';
  try {
    const rpcPort = await listen(rpc);
    const appPort = await freePort();
    const require = createRequire(import.meta.url);
    const nextBin = path.join(path.dirname(require.resolve('next/package.json')), 'dist/bin/next');
    const preload = `data:text/javascript;base64,${Buffer.from(testPreload(rpcPort, Object.values(slugs))).toString('base64')}`;
    const env = Object.fromEntries(['PATH', 'Path', 'SystemRoot', 'SYSTEMROOT', 'WINDIR', 'ComSpec', 'TEMP', 'TMP', 'HOME', 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA'].filter(key => process.env[key] !== undefined).map(key => [key, process.env[key]]));
    Object.assign(env, { NODE_ENV: 'production', NEXT_TELEMETRY_DISABLED: '1', STOREFRONT_SOURCE: 'live', STOREFRONT_SUPABASE_URL: LOGICAL_ORIGIN, STOREFRONT_SUPABASE_ANON_KEY: SYNTHETIC_KEY });
    next = spawn(process.execPath, ['--import', preload, nextBin, 'start', '-p', String(appPort), '-H', '127.0.0.1'], { cwd: ROOT, env, stdio: ['ignore', 'pipe', 'pipe'], windowsHide: true });
    next.stdout.on('data', chunk => { nextOutput = (nextOutput + chunk).slice(-16000); });
    next.stderr.on('data', chunk => { nextOutput = (nextOutput + chunk).slice(-16000); });
    const origin = `http://127.0.0.1:${appPort}`;
    const deadline = Date.now() + 45000;
    while (true) {
      if (next.exitCode !== null) throw new Error(`owned_next_exited_${next.exitCode}`);
      try {
        const result = await fetch(`${origin}/healthz.json`, { signal: AbortSignal.timeout(1500), redirect: 'error' });
        if (result.status === 200) break;
      } catch { /* Bounded loopback readiness only; no tenant warmup. */ }
      assert.ok(Date.now() < deadline, 'owned Next startup timeout');
      await pause(150);
    }
    const document = async (pathname, userAgent = CRAWLER) => {
      const response = await fetch(`${origin}${pathname}`, { headers: { 'User-Agent': userAgent }, signal: AbortSignal.timeout(15000), redirect: 'error' });
      return { response, html: await response.text() };
    };
    for (const kind of ['alpha', 'beta']) {
      for (const prefix of ROOTS) {
        await checkedSubtest(`${kind} ${prefix || 'unprefixed'} real head, scoped canonical and one server read`, async () => {
          const slug = slugs[kind];
          const before = counts.get(slug) ?? 0;
          const { response, html } = await document(`${prefix}/s/${slug}/menu`);
          assert.equal(response.status, 200);
          const metadata = metadataFrom(html);
          assert.equal(metadata.title, kind === 'beta' ? 'Synthetic Beta Closed' : hostileName);
          assert.deepEqual(metadata.descriptions, [kind === 'beta' ? 'Synthetic Beta Closed' : description]);
          assert.deepEqual(metadata.canonicals, [`https://menu.bizbot.systems/s/${slug}/menu`]);
          assertNoIndex(metadata);
          assert.equal(counts.get(slug) - before, 1, 'metadata and page share exactly one real v4 read');
          assert.match(response.headers.get('cache-control') ?? '', /s-maxage=60\b/);
          assert.match(response.headers.get('cache-control') ?? '', /stale-while-revalidate=300\b/);
          assert.equal(response.headers.get('set-cookie'), null);
          assert.equal(html.includes(SYNTHETIC_KEY), false);
          assert.equal(metadata.head.includes('<script>alert(1)</script>'), false, 'hostile title is escaped markup');
          assert.equal(metadata.head.includes('<img src=x'), false, 'hostile description is an escaped attribute');
          assert.equal(metadata.title.includes(kind === 'beta' ? 'Alpha' : 'Beta Closed'), false);
        });
      }
    }
    await checkedSubtest('normal browser cold render also makes one read and ISR reuse does not double fetch', async () => {
      const pathname = `/s/${slugs.normal}/menu`;
      const first = await document(pathname, NORMAL_BROWSER);
      assert.equal(first.response.status, 200);
      assert.equal(counts.get(slugs.normal), 1);
      const second = await document(pathname, NORMAL_BROWSER);
      assert.equal(second.response.status, 200);
      assert.equal(counts.get(slugs.normal), 1, 'warm ISR document is reused');
      assert.equal(first.html.includes(SYNTHETIC_KEY), false);
    });
    const publicSampleHeads = [];
    if (publicSample) {
      for (const prefix of ROOTS) {
        await checkedSubtest(`read-only public name/tagline replay ${prefix || 'unprefixed'} with synthetic remaining envelope`, async () => {
          const before = counts.get(publicSample.slug) ?? 0;
          const { response, html } = await document(`${prefix}/s/${publicSample.slug}/menu`);
          assert.equal(response.status, 200);
          const metadata = metadataFrom(html);
          const normalized = value => value.replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/gu, ' ').trim();
          const expectedName = normalized(publicSample.displayName);
          const expectedDescription = publicSample.tagline ? normalized(publicSample.tagline) : expectedName;
          assert.equal(metadata.title, expectedName);
          assert.deepEqual(metadata.descriptions, [expectedDescription]);
          assert.deepEqual(metadata.canonicals, [`https://menu.bizbot.systems/s/${publicSample.slug}/menu`]);
          assertNoIndex(metadata);
          assert.equal(counts.get(publicSample.slug) - before, 1);
          publicSampleHeads.push({ route: `${prefix}/s/${publicSample.slug}/menu`, title: metadata.title, description: metadata.descriptions[0], canonical: metadata.canonicals[0], noindex: true, hreflangCount: metadata.alternates.length });
        });
      }
    }
    for (const kind of ['unknown', 'unpublished']) {
      await checkedSubtest(`${kind} remains 404 without a fabricated tenant canonical`, async () => {
        const { response, html } = await document(`/s/${slugs[kind]}/menu`);
        assert.equal(response.status, 404);
        const metadata = metadataFrom(html);
        assert.equal(metadata.canonicals.length, 0);
        assert.equal(metadata.title.includes('Synthetic'), false);
        assert.equal(metadata.alternates.length, 0);
        assert.ok(metadata.robots.some(value => /\bnoindex\b/.test(value)));
        assert.equal(html.includes(SYNTHETIC_KEY), false);
      });
    }
    for (const kind of ['transport', 'malformed', 'mismatch']) {
      await checkedSubtest(`${kind} failure propagates without tenant metadata or fixture fallback`, async () => {
        const { response, html } = await document(`/s/${slugs[kind]}/menu`);
        assert.equal(response.status, 500);
        assert.doesNotMatch(html, /<link\b[^>]*rel="canonical"/i);
        assert.doesNotMatch(html, /<title>[^<]*Synthetic/i);
        assert.equal(html.includes('Maps Burger'), false);
        assert.equal(html.includes(SYNTHETIC_KEY), false);
      });
    }
    for (const kind of ['unknown', 'unpublished', 'transport', 'malformed', 'mismatch']) {
      await checkedSubtest(`${kind} normal-browser cold status remains authoritative without streamed tenant fallback`, async () => {
        const { response, html } = await document(`/s/${slugs[`${kind}browser`]}/menu`, NORMAL_BROWSER);
        assert.equal(response.status, ['unknown', 'unpublished'].includes(kind) ? 404 : 500);
        assert.doesNotMatch(html, /<link\b[^>]*rel="canonical"/i);
        assert.doesNotMatch(html, /<title>[^<]*Synthetic/i);
        assert.equal(html.includes(SYNTHETIC_KEY), false);
      });
    }
    assert.deepEqual(rejected, [], 'every reached stub call is the exact authorized local read');
    console.log(JSON.stringify({ kind: 'SYNTHETIC_LOCAL_SEO_INTEGRATION', realNext: true, publicCalls: 0, orderCalls: 0, roots: ROOTS.length, tenantMatrix: 8, metadataPageReadDedup: true, noIndexRetained: true, stubCounts: Object.fromEntries(counts), hostedServicesContacted: false, publicSampleReplay: publicSample ? { source: 'READ_ONLY_PUBLIC_SSR_NAME_AND_TAGLINE_REPLAYED', remainingEnvelope: 'SYNTHETIC_NOT_A_LIVE_RPC_SNAPSHOT', heads: publicSampleHeads } : 'NOT_RUN_NO_OPTIONAL_PUBLIC_SAMPLE' }));
  } catch (error) {
    error.message += `\nOwned Next diagnostic tail (synthetic/local only):\n${nextOutput}`;
    throw error;
  } finally {
    try {
      if (next && next.exitCode === null) {
        next.kill();
        let timer;
        try {
          await Promise.race([new Promise(resolve => next.once('close', resolve)), new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('owned Next cleanup timeout')), 10000); })]);
        } finally { clearTimeout(timer); }
      }
    } finally {
      rpc.closeAllConnections();
      if (rpc.listening) await new Promise((resolve, reject) => rpc.close(error => error ? reject(error) : resolve()));
    }
  }
});
