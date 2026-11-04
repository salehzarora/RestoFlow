import { test, expect, type Page, type Locator, type Response, type Route } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { enableFlutterSemantics, waitForFlutterBoot } from '../lib/flutter';
import { fillField, tapButton, tapNav, tapText, waitForText } from '../lib/dashboard';
import { API_URL, DASHBOARD_URL, readFixture, scope, rpc, request, storagePath, readInvariants } from './service.mjs';
import { localMediaTarget } from './live-transport.mjs';

// Real owner session + shipped uploader/worker/repository/publisher. The guard
// rejects execution outside the disposable Actions stack, even for local runs.
const samples = [
  { name: 'burger', file: 'burger.webp', category: 'وجبات اختبار', item: 'TEST 1', alpha: false },
  { name: 'fries-cup', file: 'fries-cup.webp', category: 'مقبلات اختبار', item: 'TEST 2', alpha: false },
  { name: 'platter', file: 'platter.webp', category: 'كاسات اختبار', item: 'TEST 3', alpha: false },
  { name: 'drink', file: 'drink.webp', category: 'مشروبات اختبار', item: 'TEST 4', alpha: true },
];
const L = { pick: 'اختيار صورة', save: 'حفظ الصورة', original: 'الأصل', remove: 'إزالة الخلفية',
  publish: 'نشر الصورة المختارة', published: 'تم نشر الاختيار.', dark: 'فحص الحواف على خلفية داكنة',
  prepare: 'تحضير إزالة الخلفية', cancel: 'إلغاء المعالجة',
  failed: 'تعذرت إزالة الخلفية. الصورة الأصلية محفوظة. أعد المحاولة أو احتفظ بالأصل.',
  transparent: 'هذه الصورة شفافة بالفعل؛ لم تُجرَ عملية فصل.' };
const sha = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
function post(response: Response, path: string) {
  const url = new URL(response.url());
  return url.origin === API_URL && url.pathname === path && response.request().method() === 'POST';
}

// Flutter owns scroll position. Use actual wheel input over the observed
// editor body; do not assign scrollTop or click a hidden semantics node.
async function reveal(page: Page, target: Locator): Promise<void> {
  let direction = 1, previous = '', stalled = 0, reversed = false;
  for (let attempt = 0; attempt < 80; attempt++) {
    const box = await target.first().boundingBox();
    if (box && box.width > 0 && box.height > 0 && box.y > 100 && box.y + box.height < 950) return;
    const view = await page.locator('flutter-view').boundingBox();
    if (!view) throw new Error('Dashboard view is not rendered');
    const signature = await page.locator('flt-semantics').evaluateAll(nodes => nodes.map(node => {
      const r = node.getBoundingClientRect();
      return r.width > 0 && r.height > 0 && r.bottom > 100 && r.top < 950 ? `${node.id}:${Math.round(r.y)}` : '';
    }).join('|'));
    stalled = signature === previous ? stalled + 1 : 0; previous = signature;
    if (stalled >= 2 && !box) {
      if (reversed) break;
      direction *= -1; reversed = true; stalled = 0;
    }
    if (box) direction = box.y < 100 ? -1 : 1;
    await page.mouse.move(view.x + view.width / 2, view.y + Math.min(650, view.height * .7));
    await page.mouse.wheel(0, direction * 420);
    await page.waitForTimeout(250);
  }
  throw new Error('Product editor control did not become visible');
}
async function click(page: Page, name: string) {
  const control = page.getByRole('button', { name, exact: true }).first();
  await reveal(page, control);
  await control.click();
}
async function login(page: Page, email: string, password: string): Promise<string> {
  await page.goto(DASHBOARD_URL, { waitUntil: 'domcontentloaded' });
  await waitForFlutterBoot(page);
  expect(await enableFlutterSemantics(page)).toBe(true);
  await fillField(page, 'البريد الإلكتروني', email);
  const input = page.locator('input[type="password"]').first();
  await input.click();
  await page.keyboard.press('ControlOrMeta+A');
  await page.keyboard.press('Delete');
  let prefix = '';
  for (const character of password) {
    await page.keyboard.type(character); prefix += character;
    await expect.poll(() => input.evaluate((el, value) =>
      el instanceof HTMLInputElement && el.value === value, prefix),
    { message: 'The actual password control reflects each ordinary key' }).toBe(true);
  }
  await page.keyboard.press('Tab');
  const grant = page.waitForResponse(r => post(r, '/auth/v1/token') && new URL(r.url()).searchParams.get('grant_type') === 'password');
  await tapButton(page, 'تسجيل الدخول');
  const response = await grant;
  expect(response.status(), 'Real UI sign-in succeeds').toBe(200);
  const data = await response.json();
  expect(typeof data.access_token).toBe('string');
  return data.access_token; // stays in test memory; never written to evidence
}

async function decodedAlpha(page: Page, bytes: Buffer) {
  // Decode actual returned image bytes in the browser; no synthetic mask or
  // mocked codec. Counts, dimensions and a content hash are safe evidence.
  return page.evaluate(async base64 => {
    const data = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
    const image = await createImageBitmap(new Blob([data]));
    const canvas = new OffscreenCanvas(image.width, image.height);
    const ctx = canvas.getContext('2d')!;
    ctx.drawImage(image, 0, 0);
    const rgba = ctx.getImageData(0, 0, image.width, image.height).data;
    const alphaBytes = new Uint8Array(image.width * image.height);
    let transparent = 0, partial = 0, opaque = 0;
    for (let i = 3; i < rgba.length; i += 4) {
      alphaBytes[(i - 3) / 4] = rgba[i];
      if (rgba[i] === 0) transparent++; else if (rgba[i] === 255) opaque++; else partial++;
    }
    const dimensions = { width: image.width, height: image.height };
    image.close();
    const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', alphaBytes));
    const alphaSha256 = Array.from(digest, b => b.toString(16).padStart(2, '0')).join('');
    return { ...dimensions, transparent, partial, opaque, alphaSha256 };
  }, bytes.toString('base64'));
}

test('product originals survive local review, explicit selection and publication', async ({ page, context }) => {
  const fixture = readFixture();
  let violation = false, modelReads = 0, registerCalls = 0;
  let modelFault: 'none' | 'hold' | 'fail' = 'none';
  let heldModelRequest: Route | undefined;
  let injectedModelFailures = 0;
  const publisherCalls: { variant: string; status: number }[] = [];
  const registrations: Record<string, unknown>[] = [];
  const publishedReplies: Promise<void>[] = [];
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.protocol !== 'http:' || ![API_URL, DASHBOARD_URL].includes(url.origin) || url.username || url.password) {
      violation = true; await route.abort('blockedbyclient'); return;
    }
    if (url.origin === DASHBOARD_URL && /\/product-cutout\/vendor\/u2net-\d+\.bin$/.test(url.pathname)) {
      modelReads++;
      if (modelFault === 'hold') {
        modelFault = 'none'; heldModelRequest = route;
        return; // Stop a real in-flight model download until UI cancel.
      }
      if (modelFault === 'fail') {
        modelFault = 'none'; injectedModelFailures++;
        await route.abort('failed'); return; // One controlled network failure.
      }
    }
    if (url.origin === API_URL && url.pathname === '/rest/v1/rpc/register_storefront_product_derivative_v1') {
      registerCalls++; registrations.push(route.request().postDataJSON());
    }
    await route.continue();
  });
  page.on('response', response => {
    if (post(response, '/functions/v1/storefront-media-publish')) {
      const body = response.request().postDataJSON();
      if (body.slot === 'product') publishedReplies.push(response.finished().then(() => {
        publisherCalls.push({ variant: body.variant, status: response.status() });
      }));
    }
  });
  const token = await login(page, fixture.ownerA.email, fixture.ownerA.password);
  const initialInvariants = await readInvariants(fixture, token);
  expect(modelReads, 'No model is loaded for login or ordinary Dashboard navigation').toBe(0);
  const evidence: Record<string, unknown>[] = [];
  for (const sample of samples) {
    await tapNav(page, 'القائمة');
    await tapText(page, sample.category);
    await tapText(page, sample.item);
    const picker = page.getByRole('button', { name: L.pick, exact: true });
    await reveal(page, picker);
    const chooser = page.waitForEvent('filechooser');
    await picker.click();
    const path = resolve(__dirname, 'fixtures/product-cutout', sample.file);
    const source = readFileSync(path);
    await (await chooser).setFiles(path);
    const previousModelReads = modelReads, previousRegisters = registerCalls;
    if (sample.name === 'burger') modelFault = 'hold';
    const saved = page.waitForResponse(response => post(response, '/rest/v1/rpc/menu_upsert_item'));
    await click(page, L.save);
    const sourceWrite = await saved;
    expect(sourceWrite.status()).toBe(200);
    expect((await sourceWrite.json()).ok).toBe(true);
    const payload = sourceWrite.request().postDataJSON();
    const itemId = payload.p_id as string, originalKey = payload.p_image_path as string;
    expect(typeof itemId).toBe('string'); expect(typeof originalKey).toBe('string');
    const readOriginal = () => rpc(fixture, token, 'get_storefront_product_original_v1', { ...scope(fixture.ownerA), p_item_id: itemId });
    const before = await readOriginal();
    expect(before.status).toBe(200); expect(before.data.ok).toBe(true);
    expect(before.data.source_key).toBe(originalKey);
    expect(before.data.selected_derivative_id).toBeNull();
    const downloadOriginal = () => request(fixture, token,
      `/storage/v1/object/authenticated/menu-images/${storagePath(originalKey)}`);
    const privateBefore = await downloadOriginal();
    expect(privateBefore.status).toBe(200);
    expect(sha(privateBefore.bytes), 'The real private upload retains exact source bytes').toBe(sha(source));
    let successfulModelStart = previousModelReads;
    if (sample.name === 'burger') {
      await expect.poll(() => heldModelRequest !== undefined,
        { message: 'Automatic preparation reaches a real model download' }).toBe(true);
      await click(page, L.cancel);
      await expect(page.getByRole('button', { name: L.cancel, exact: true })).toHaveCount(0);
      // Termination normally cancels this request itself; releasing the held
      // route also keeps the test's fault injection bounded after cancellation.
      await heldModelRequest!.abort('aborted').catch(() => {});
      heldModelRequest = undefined;
      await expect(page.getByRole('button', { name: L.publish, exact: true })).toBeEnabled();
      expect(registerCalls, 'Cancelling processing never publishes').toBe(previousRegisters);
      expect(sha((await downloadOriginal()).bytes)).toBe(sha(source));

      modelFault = 'fail';
      await click(page, L.prepare);
      await waitForText(page, L.failed);
      expect(injectedModelFailures).toBe(1);
      expect(registerCalls, 'A failed model fetch never publishes').toBe(previousRegisters);
      await expect(page.getByRole('button', { name: L.publish, exact: true })).toBeEnabled();
      expect(sha((await downloadOriginal()).bytes), 'Failure retains actual private original bytes').toBe(sha(source));
      successfulModelStart = modelReads;
      await click(page, L.prepare); // Retry the actual worker, without mocked inference.
    }
    const publish = page.getByRole('button', { name: L.publish, exact: true });
    await reveal(page, publish);
    await expect(publish).toBeEnabled({ timeout: 150_000 });
    if (sample.alpha) {
      await waitForText(page, L.transparent);
      expect(modelReads, 'Real alpha returns original bytes without loading model weights').toBe(previousModelReads);
      await expect(page.getByRole('button', { name: L.remove, exact: true })).toBeDisabled();
    } else {
      expect(modelReads - successfulModelStart, 'Successful retry fetches all eleven pinned model chunks').toBe(11);
      await expect(page.getByRole('button', { name: L.remove, exact: true })).toBeEnabled();
    }
    expect(registerCalls, 'Saving an original and automatic local review never publishes a candidate').toBe(previousRegisters);
    const dark = page.getByRole('switch', { name: L.dark, exact: true });
    await reveal(page, dark);
    await page.screenshot({ path: resolve(process.env.CINEMATIC_ARTIFACT_DIR!, `product-${sample.name}-light.png`) });
    await dark.click();
    await page.screenshot({ path: resolve(process.env.CINEMATIC_ARTIFACT_DIR!, `product-${sample.name}-dark.png`) });
    if (!sample.alpha) await click(page, L.remove);
    await click(page, L.publish);
    await waitForText(page, L.published, 180_000);
    const after = await readOriginal();
    expect(after.data.ok).toBe(true); expect(after.data.source_key).toBe(originalKey);
    expect(after.data.source_snapshot).toEqual(before.data.source_snapshot);
    expect(after.data.selected_derivative_id).toEqual(expect.any(String));
    expect(after.data.selection_version).toBe(before.data.selection_version + 1);
    const privateAfter = await downloadOriginal();
    expect(privateAfter.status).toBe(200);
    expect(sha(privateAfter.bytes), 'Publication preserves exact private original bytes').toBe(sha(privateBefore.bytes));
    const registered = registrations.at(-1)!;
    expect(registered.p_treatment).toBe(sample.alpha ? 'original' : 'cutout');
    expect(registered.p_original_key).toBe(originalKey);
    if (sample.alpha) expect(registered.p_candidate_key).toBe(originalKey);
    else expect(registered.p_candidate_key).not.toBe(originalKey);
    const selectedPrivate = await request(fixture, token,
      `/storage/v1/object/authenticated/menu-images/${storagePath(registered.p_candidate_key as string)}`);
    expect(selectedPrivate.status).toBe(200);
    const selectedAlpha = await decodedAlpha(page, selectedPrivate.bytes);
    const live = await rpc(fixture, null, 'storefront_menu_v6', { p_slug: fixture.ownerA.slug });
    expect(live.status).toBe(200); expect(live.data.ok).toBe(true);
    const row = live.data.product_images_v1.find((r: { item_id: string }) => r.item_id === itemId);
    expect(row).toBeDefined();
    const dimensions: Record<string, number> = {};
    const publishedImages: Record<string, unknown>[] = [];
    for (const size of [480, 960]) {
      const target = localMediaTarget(row[`w${size}_url`], 'GET');
      const response = await fetch(target, { redirect: 'error', signal: AbortSignal.timeout(15_000) });
      expect(response.status).toBe(200);
      expect(response.headers.get('content-type')).toContain('image/webp');
      const bytes = Buffer.from(await response.arrayBuffer());
      expect(bytes.length).toBeGreaterThan(0);
      const alpha = await decodedAlpha(page, bytes);
      expect(alpha.width).toBe(row[`width${size}`]);
      expect(alpha.height).toBe(row[`height${size}`]);
      expect(alpha.transparent, 'Actual published WebP preserves transparent background pixels').toBeGreaterThan(0);
      expect(alpha.opaque, 'Actual published WebP retains opaque subject pixels').toBeGreaterThan(0);
      if (alpha.width === selectedAlpha.width && alpha.height === selectedAlpha.height) {
        expect(alpha.alphaSha256, 'Lossless alpha at unchanged geometry matches the real private source/candidate').toBe(selectedAlpha.alphaSha256);
      }
      publishedImages.push({ variant: `w${size}`, bytes: bytes.length, sha256: sha(bytes), ...alpha });
      dimensions[`width${size}`] = row[`width${size}`];
      dimensions[`height${size}`] = row[`height${size}`];
    }
    // The same open editor must refresh its optimistic selection proof after
    // success: switching back must not fail with selection_stale.
    if (sample.name === 'burger') {
      await click(page, L.original);
      await click(page, L.publish);
      await waitForText(page, L.published, 180_000);
      const restored = await readOriginal();
      expect(restored.data.source_key).toBe(originalKey);
      expect(restored.data.selection_version).toBe(after.data.selection_version + 1);
      expect(registrations.at(-1)!.p_treatment).toBe('original');
      const privateRestored = await downloadOriginal();
      expect(privateRestored.status).toBe(200);
      expect(sha(privateRestored.bytes)).toBe(sha(source));
    }
    evidence.push({ sample: sample.name, sourceKind: 'Existing published c4/w480 copy, not private original',
      sourceBytes: source.length, sourceSha256: sha(source), treatment: sample.alpha ? 'original-alpha-bypass' : 'u2net-cutout',
      modelPartReads: modelReads - previousModelReads, originalPreserved: sha(privateAfter.bytes) === sha(privateBefore.bytes),
      privateBeforeSha256: sha(privateBefore.bytes), privateAfterSha256: sha(privateAfter.bytes),
      cancelAndFailedFetchRetainedOriginal: sample.name === 'burger', publishedImages,
      explicitPublication: true, ...dimensions });
    await tapButton(page, 'إلغاء'); // close the item editor; already saved source/presentation remain
  }
  await Promise.all(publishedReplies);
  expect(publisherCalls.filter(call => call.status === 200 && call.variant === 'w480')).toHaveLength(5);
  expect(publisherCalls.filter(call => call.status === 200 && call.variant === 'w960')).toHaveLength(5);
  expect(await readInvariants(fixture, token), 'Hero, logo and receipt settings remain unchanged').toEqual(initialInvariants);
  expect(violation, 'No image bytes or runtime requests leave the allowed loopback services').toBe(false);
  writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'product-cutout.json'), JSON.stringify({
    model: 'U2Net FP32', modelNativeHeapLimitBytes: 536870912,
    fixturesArePublishedCopies: true, cases: evidence,
  }, null, 2));
});
