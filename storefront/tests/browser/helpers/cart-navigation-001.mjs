import { settings, SYNTHETIC_KEY, LOGICAL_ORIGIN, SYNTHETIC_SLUGS, childEnvironment, transportEvidence, boundaryCanaries } from './cart-navigation-boundary-001.mjs';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { syntheticV4Envelope } from '../../support/content-envelope.mjs';
import { SYNTH_IDS } from '../../support/envelope.mjs';

export const SLUGS = SYNTHETIC_SLUGS;
export const NOTE = 'Synthetic navigation note בלי בצל بدون بصل';
export const ITEM = SYNTH_IDS.burger;
export const REQUIRED = SYNTH_IDS.classic;
export const EXTRA = SYNTH_IDS.cheese;
export const EXPECTED_PRICE = '₪92';
export const messages = Object.fromEntries(['ar', 'he', 'en'].map(locale => [locale, JSON.parse(readFileSync(path.join(settings.sourceDir, `messages/storefront.${locale}.json`), 'utf8'))]));
export const appOrigin = `http://127.0.0.1:${settings.appPort}`;
function envelope(slug) {
  const bravo = slug === SLUGS[1];
  return syntheticV4Envelope({
    restaurant: { ...syntheticV4Envelope().restaurant, slug, display_name: bravo ? 'Synthetic Bravo' : 'Synthetic Alpha', tagline: 'Synthetic local navigation', phone: null, card_mode: 'grid', motion: 'calm' },
    service: { state: 'open', ordering_enabled: true, pickup_enabled: true, delivery_enabled: false },
    tax: { enabled: false, rate_bp: 0, mode: 'exclusive' },
    items: syntheticV4Envelope().items.filter(item => item.id !== SYNTH_IDS.orphan && item.id !== SYNTH_IDS.soldOut).map(item => ({ ...item, name: `${bravo ? 'Bravo' : 'Alpha'} ${item.id === ITEM ? 'Burger' : 'Cola'}`, image_url: null })),
  });
}
export function itemName(slug = SLUGS[0]) { return slug === SLUGS[1] ? 'Bravo Burger' : 'Alpha Burger'; }
export async function startFixture() {
  const canaries = await boundaryCanaries();
  const calls = [];
  const rejected = [];
  const server = createServer(async (req, res) => {
    let body = '';
    for await (const chunk of req) { body += chunk; if (body.length > 1024) { res.writeHead(413); res.end(); return; } }
    let json; try { json = JSON.parse(body); } catch { json = null; }
    const valid = req.method === 'POST' && req.url === '/rest/v1/rpc/storefront_menu_v4' && req.headers.apikey === SYNTHETIC_KEY && req.headers.authorization === `Bearer ${SYNTHETIC_KEY}` && json && Object.keys(json).length === 1 && SLUGS.includes(json.p_slug);
    if (!valid) { rejected.push({ method: req.method, path: req.url }); res.writeHead(403); res.end(); return; }
    calls.push({ method: req.method, path: req.url, slug: json.p_slug });
    res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(JSON.stringify(envelope(json.p_slug)));
  });
  await new Promise((resolve, reject) => { server.once('error', reject); server.listen(settings.rpcPort, '127.0.0.1', resolve); });
  let next;
  let stdout = '', stderr = '';
  try {
  // Demonstrate that the exact logical read maps to synthetic bytes, while
  // near-misses reject before the original fetch/socket implementation.
  const request = { method: 'POST', headers: { apikey: SYNTHETIC_KEY, authorization: `Bearer ${SYNTHETIC_KEY}`, 'content-type': 'application/json', accept: 'application/json' }, body: JSON.stringify({ p_slug: SLUGS[0] }) };
  const positive = await fetch(`${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v4`, request);
  assert.equal(positive.status, 200); assert.equal((await positive.json()).restaurant.slug, SLUGS[0]);
  const beforeRejectedCalls = calls.length;
  const negatives = [
    [`${LOGICAL_ORIGIN}/functions/v1/web-order-submit`, request],
    [`${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v4`, { ...request, method: 'GET', body: undefined }],
    [`${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v3`, request],
    [`${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v4`, { ...request, body: JSON.stringify({ p_slug: 'not-approved' }) }],
    [`${LOGICAL_ORIGIN}/rest/v1/rpc/storefront_menu_v4?unexpected=1`, request],
    ['https://example.invalid/', { method: 'GET' }],
  ];
  for (const [url, init] of negatives) await assert.rejects(fetch(url, init), /cart_navigation_offline_boundary_denied/);
  assert.equal(calls.length, beforeRejectedCalls);
  const mappingProof = { positive: 'exact synthetic v4 read mapped to owned loopback', negativeCases: negatives.length, hardBoundaryCanaries: canaries, noNegativeReachedStub: calls.length === beforeRejectedCalls, ...transportEvidence };
  const env = childEnvironment();
  next = spawn(process.execPath, [path.join(settings.sourceDir, 'node_modules/next/dist/bin/next'), 'start', '-p', String(settings.appPort), '-H', '127.0.0.1'], { cwd: settings.sourceDir, env, stdio: ['ignore', 'pipe', 'pipe'] });
  next.stdout.on('data', data => { stdout = (stdout + data).slice(-32000); });
  next.stderr.on('data', data => { stderr = (stderr + data).slice(-32000); });
  const deadline = Date.now() + 45000;
  while (true) {
    if (next.exitCode !== null) throw new Error(`isolated_next_exited_${next.exitCode}`);
    try { const res = await fetch(`${appOrigin}/en/s/${SLUGS[0]}/menu`, { signal: AbortSignal.timeout(3000) }); if (res.status === 200) break; } catch { /* Bounded TCP readiness; no alternate endpoint. */ }
    if (Date.now() > deadline) throw new Error('isolated_next_readiness_timeout');
    await new Promise(resolve => setTimeout(resolve, 150));
  }
  return { calls, rejected, mappingProof, processId: next.pid, output: () => ({ stdout, stderr }), stop: async () => { if (next.exitCode === null) { next.kill(); await Promise.race([new Promise(resolve => next.once('close', resolve)), new Promise((_, reject) => setTimeout(() => reject(new Error('owned_next_cleanup_timeout')), 10000))]); } await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve())); } };
  } catch (error) {
    if (next && next.exitCode === null) { next.kill(); await Promise.race([new Promise(resolve => next.once('close', resolve)), new Promise(resolve => setTimeout(resolve, 10000))]); }
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
    error.fixtureEvidence = { stdout, stderr, calls, rejected, ownedCleanupAttempted: true };
    throw error;
  }
}
export async function guardBrowser(context) {
  const denied = [];
  const localBrandAssetExists = existsSync(path.join(settings.sourceDir, 'public/bizbot-symbol-256.png'));
  await context.route('**/*', async route => {
    const req = route.request(); const url = new URL(req.url());
    const allowedPath = url.pathname.startsWith('/_next/static/') || url.pathname === '/favicon.ico' || (url.pathname === '/bizbot-symbol-256.png' && localBrandAssetExists) || /^\/(?:ar\/|he\/|en\/)?s\/sf-cart-nav-(?:alpha|bravo)(?:\/menu|\/cart)?$/.test(url.pathname);
    if (url.origin !== appOrigin || !['GET', 'HEAD'].includes(req.method()) || !allowedPath) { denied.push({ origin: url.origin, path: url.pathname, method: req.method() }); await route.abort('blockedbyclient'); return; }
    await route.continue();
  });
  await context.routeWebSocket('**/*', socket => { denied.push({ websocket: true }); socket.close(); });
  return denied;
}
export async function cartSnapshot(page, selector) {
  return page.locator(selector).evaluateAll(lines => lines.map(line => ({ lineId: line.getAttribute('data-sf-cart-line') ?? line.getAttribute('data-sf-aside-line'), itemId: line.querySelector('[data-sf-item]')?.getAttribute('data-sf-item'), qty: line.querySelector('[data-sf-stepper] > span')?.textContent?.trim(), text: line.innerText.replace(/\s+/g, ' ').trim() })));
}
export async function privacyState(page) {
  return page.evaluate(slugs => ({ cartKeys: Object.keys(localStorage).filter(key => /cart/i.test(key)), values: slugs.map(slug => ({ slug, value: localStorage.getItem(`sf:v1:cart:${slug}`) })) }), SLUGS);
}
