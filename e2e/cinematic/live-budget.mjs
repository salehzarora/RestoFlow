// Reuse the unchanged canonical measurer, caps and response-by-response Brotli.
// Genuine local service HTML/chunks only; no fixture substitution or lazy load.
import assert from 'node:assert/strict';
import { cpSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { STOREFRONT_URL, assertEphemeralEnvironment } from './service.mjs';
export async function measureLiveBudget(root, privateDir, publicDir, slug) {
  assertEphemeralEnvironment();
  assert.match(slug, /^cinematic-[a-z0-9-]+$/);
  const { measure, checkBudgets } = await import(pathToFileURL(resolve(root, 'storefront/scripts/measure-firstload.mjs')));
  const { ROUTES } = await import(pathToFileURL(resolve(root, 'storefront/scripts/budgets.mjs')));
  const out = resolve(privateDir, 'live-budget'); mkdirSync(out, { recursive: true });
  cpSync(resolve(root, 'storefront/.next/static'), resolve(out, '_next/static'), { recursive: true });
  const mapped = [];
  for (const route of ROUTES.filter(row => /\/(menu|search|cart|checkout|review)$/.test(row.route))) {
    const actualRoute = route.route.replace('maps-burger', slug);
    const response = await fetch(STOREFRONT_URL + actualRoute, { redirect: 'error', signal: AbortSignal.timeout(30000) });
    assert.equal(response.status, 200, 'Actual live route must render before measurement');
    const file = resolve(out, route.file); mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, await response.text()); mapped.push({ canonicalRoute: route.route, actualRoute, status: response.status });
  }
  const rows = measure(out), problems = checkBudgets(rows);
  const receipt = { status: problems.length ? 'FAIL' : 'PASS', lane: 'actual ephemeral live application', method: 'unchanged storefront/scripts/measure-firstload.mjs and budgets.mjs', mapped, rows, problems };
  writeFileSync(resolve(publicDir, 'live-firstload-budget.json'), JSON.stringify(receipt, null, 2));
  return receipt;
}
