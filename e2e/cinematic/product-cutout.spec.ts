import { test, expect, type BrowserContext, type Page, type Locator, type Response, type Route } from '@playwright/test';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { enableFlutterSemantics, waitForFlutterBoot } from '../lib/flutter';
import { fillField, tapButton, tapNav, tapText, waitForText } from '../lib/dashboard';
import { API_URL, DASHBOARD_URL, readFixture, scope, rpc, request, storagePath, readInvariants } from './service.mjs';
import { localProductMediaTarget } from './live-transport.mjs';
import { captureProductResponse, createProductProgress, type ProductProgress } from './product-progress.mjs';
import { captureHighResolutionMenu, type PublishedProductImage } from './product-quality';
import { observeResponse, responseAfterAction } from './control-progress.mjs';

// Real owner session + shipped uploader/worker/repository/publisher. The guard
// rejects execution outside the disposable Actions stack, even for local runs.
const samples = [
  { name: 'burger', file: 'burger.webp', category: 'وجبات اختبار', item: 'TEST 1', alpha: false },
  { name: 'fries-cup', file: 'fries-cup.webp', category: 'مقبلات اختبار', item: 'TEST 2', alpha: false },
  { name: 'platter', file: 'platter.webp', category: 'كاسات اختبار', item: 'TEST 3', alpha: false },
  { name: 'drink', file: 'drink.webp', category: 'مشروبات اختبار', item: 'TEST 4', alpha: true },
  // A fifth pass replaces only the disposable first item, after its ordinary
  // source/cancel/retry/restore coverage. No fixture catalogue/schema expansion.
  { name: 'burger-highres', file: 'burger-highres.jpg', category: 'وجبات اختبار', item: 'TEST 1', alpha: false },
] as const;
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
  type LoginStage = 'boot' | 'email-entry' | 'password-focus' | 'password-clear'
    | 'password-prefix' | 'password-blur' | 'auth-submit' | 'auth-response' | 'complete';
  let stage: LoginStage = 'boot', passed = false;
  const completedStages: LoginStage[] = [];
  const advance = (next: LoginStage) => { completedStages.push(stage); stage = next; };
  try {
    await page.goto(DASHBOARD_URL, { waitUntil: 'domcontentloaded' });
    await waitForFlutterBoot(page);
    expect(await enableFlutterSemantics(page)).toBe(true);
    advance('email-entry');
    await fillField(page, 'البريد الإلكتروني', email);
    const input = page.locator('input[type="password"]').first();
    advance('password-focus');
    await input.click();
    // Match the proven Dashboard helper: a click completing does not prove
    // Flutter has installed its focused editing control or applied clearing.
    await expect.poll(() => input.evaluate(el => el.matches(':focus')), {
      message: 'Actual Dashboard password control receives focus',
    }).toBe(true);
    advance('password-clear');
    await page.keyboard.press('ControlOrMeta+A');
    await page.keyboard.press('Delete');
    const matches = (expected: string) => input.evaluate((el, value) =>
      el instanceof HTMLInputElement && el.value === value, expected);
    await expect.poll(() => matches(''), {
      message: 'Actual Dashboard password control is cleared by keyboard input',
    }).toBe(true);
    advance('password-prefix');
    let prefix = '';
    for (const character of password) {
      await page.keyboard.type(character); prefix += character;
      await expect.poll(() => matches(prefix), {
        message: 'The actual password control reflects each ordinary key',
      }).toBe(true);
    }
    advance('password-blur');
    await page.keyboard.press('Tab');
    await expect.poll(() => matches(password), {
      message: 'Complete Dashboard password remains correct after blur',
    }).toBe(true);
    advance('auth-submit');
    // The actual Arabic screen has two identical labels: the first selects
    // sign-in mode; the last is auth-submit. The widget regression proves that
    // clicking the already-selected mode sends no Auth call. Match main login.
    await expect(page.getByRole('button', { name: 'تسجيل الدخول', exact: true })).toHaveCount(2);
    const grant = page.waitForResponse(r => post(r, '/auth/v1/token') && new URL(r.url()).searchParams.get('grant_type') === 'password');
    await tapButton(page, 'تسجيل الدخول', { which: 'last' });
    advance('auth-response');
    const response = await grant;
    expect(response.status(), 'Real UI sign-in succeeds').toBe(200);
    const data = await response.json();
    expect(typeof data.access_token).toBe('string');
    advance('complete');
    passed = true;
    return data.access_token; // stays in test memory; never written to evidence
  } finally {
    // Fixed stage names only. Never retain values, prefixes, character counts,
    // request/response bodies, raw exceptions, screenshots or credential fields.
    writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'product-login-result.json'), JSON.stringify({
      status: passed ? 'PASS' : 'FAIL', failedStage: passed ? null : stage, completedStages,
    }, null, 2));
  }
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

async function saveDecodedPublicPreview(page: Page, bytes: Buffer, name: string) {
  const png = await page.evaluate(async base64 => {
    const image = await createImageBitmap(new Blob([Uint8Array.from(atob(base64), value => value.charCodeAt(0))]));
    const canvas = new OffscreenCanvas(image.width, image.height);
    canvas.getContext('2d')!.drawImage(image, 0, 0); image.close();
    const data = new Uint8Array(await (await canvas.convertToBlob({ type: 'image/png' })).arrayBuffer());
    let text = ''; for (const value of data) text += String.fromCharCode(value);
    return btoa(text);
  }, bytes.toString('base64'));
  writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, name), Buffer.from(png, 'base64'));
}

async function runProductJourney(page: Page, context: BrowserContext, progress: ProductProgress) {
  const fixture = readFixture();
  const advance = progress.advance;
  advance('route-setup');
  let violation = false, modelReads = 0, registerCalls = 0;
  let fileChoosers = 0, originalUploads = 0, itemSaves = 0;
  let modelFault: 'none' | 'hold' | 'fail' = 'none';
  let heldModelRequest: Route | undefined;
  let injectedModelFailures = 0;
  const publisherCalls: { variant: string; status: number }[] = [];
  const registrations: Record<string, unknown>[] = [];
  const publishedReplies: Promise<void>[] = [];
  page.on('filechooser', () => { fileChoosers++; });
  await context.route('**/*', async route => {
    const url = new URL(route.request().url());
    if (url.protocol !== 'http:' || ![API_URL, DASHBOARD_URL].includes(url.origin) || url.username || url.password) {
      violation = true; await route.abort('blockedbyclient'); return;
    }
    if (url.origin === API_URL && ['POST', 'PUT', 'PATCH'].includes(route.request().method())
      && url.pathname.startsWith('/storage/v1/object/menu-images/')) originalUploads++;
    if (url.origin === API_URL && route.request().method() === 'POST'
      && url.pathname === '/rest/v1/rpc/menu_upsert_item') itemSaves++;
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
  advance('login');
  const token = await login(page, fixture.ownerA.email, fixture.ownerA.password);
  advance('baseline-invariants');
  const initialInvariants = await readInvariants(fixture, token);
  advance('initial-model-count');
  expect(modelReads, 'No model is loaded for login or ordinary Dashboard navigation').toBe(0);
  const evidence: Record<string, unknown>[] = [];
  const qualityEvidence: Record<string, unknown>[] = [];
  for (const sample of samples) {
    const beforeChoose = { fileChoosers, originalUploads, itemSaves };
    advance('open-product', sample.name);
    await tapNav(page, 'القائمة');
    await tapText(page, sample.category);
    await tapText(page, sample.item);
    const picker = page.getByRole('button', { name: L.pick, exact: true });
    advance('choose-source');
    await reveal(page, picker);
    const chooser = page.waitForEvent('filechooser');
    await picker.click();
    const path = resolve(__dirname, 'fixtures/product-cutout', sample.file);
    const source = readFileSync(path);
    const sourceGeometry = await decodedAlpha(page, source);
    if (sample.name === 'burger-highres') {
      advance('highres-source-metadata');
      expect(source.length).toBe(4_989_591);
      expect(sha(source)).toBe('81f08a1cb0256293b862db2a661b76f9f9a54067ae5651469a454f7899b50bb3');
      expect([sourceGeometry.width, sourceGeometry.height]).toEqual([2816, 2112]);
      expect(sourceGeometry.width * sourceGeometry.height).toBeLessThanOrEqual(8_388_608);
      expect(source.length).toBeLessThanOrEqual(5 * 1024 * 1024);
    }
    await (await chooser).setFiles(path);
    const previousModelReads = modelReads, previousRegisters = registerCalls;
    if (sample.name === 'burger' || sample.name === 'fries-cup') modelFault = 'hold';
    advance('save-source');
    const saved = page.waitForResponse(response => post(response, '/rest/v1/rpc/menu_upsert_item'));
    await click(page, L.save);
    const sourceWrite = await saved;
    // Parse only for bounded facts; a diagnostic parse failure is swallowed.
    // The existing status and JSON assertions below keep their original order.
    await captureProductResponse(progress, 'save-source', sourceWrite.status(), () => sourceWrite.json());
    advance('save-source-status');
    expect(sourceWrite.status()).toBe(200);
    advance('save-source-result');
    expect((await sourceWrite.json()).ok).toBe(true);
    advance('save-source-identifiers');
    const payload = sourceWrite.request().postDataJSON();
    const itemId = payload.p_id as string, originalKey = payload.p_image_path as string;
    expect(typeof itemId).toBe('string'); expect(typeof originalKey).toBe('string');
    const readOriginal = () => rpc(fixture, token, 'get_storefront_product_original_v1', { ...scope(fixture.ownerA), p_item_id: itemId });
    advance('original-read-status');
    const before = await readOriginal();
    progress.recordResponse('original-read', before.status, before.data);
    expect(before.status).toBe(200);
    advance('original-read-result');
    expect(before.data.ok).toBe(true);
    advance('original-source-key');
    expect(before.data.source_key).toBe(originalKey);
    advance('original-selection-default');
    expect(before.data.selected_derivative_id).toBeNull();
    const downloadOriginal = () => request(fixture, token,
      `/storage/v1/object/authenticated/menu-images/${storagePath(originalKey)}`);
    advance('private-original-status');
    const privateBefore = await downloadOriginal();
    expect(privateBefore.status).toBe(200);
    advance('private-original-bytes');
    expect(sha(privateBefore.bytes), 'The real private upload retains exact source bytes').toBe(sha(source));
    let successfulModelStart = previousModelReads;
    let existingBaseline: typeof beforeChoose | undefined;
    if (sample.name === 'fries-cup') {
      advance('existing-await-auto');
      await expect.poll(() => heldModelRequest !== undefined).toBe(true);
      // First prove these observers saw the ordinary upload. Unchanged counts
      // later can then prove the reopened path performs no chooser/upload/save.
      expect(fileChoosers).toBe(beforeChoose.fileChoosers + 1);
      expect(originalUploads).toBe(beforeChoose.originalUploads + 1);
      expect(itemSaves).toBe(beforeChoose.itemSaves + 1);
      existingBaseline = { fileChoosers, originalUploads, itemSaves };
      const worker = page.workers().find(worker => new URL(worker.url()).pathname.endsWith('/product-cutout/worker.mjs'));
      expect(worker, 'Automatic preparation owns an actual worker').toBeDefined();
      advance('existing-close');
      // The held first chunk prevents inference from completing naturally.
      // Observe actual disposal before releasing the route or resetting counts.
      await responseAfterAction(observeResponse(worker!.waitForEvent('close')),
        () => tapButton(page, 'إلغاء'));
      await expect(page.getByRole('button', { name: L.prepare, exact: true })).toHaveCount(0);
      await heldModelRequest!.abort('aborted').catch(() => {});
      heldModelRequest = undefined;
      expect(page.workers().filter(worker => new URL(worker.url()).pathname.endsWith('/product-cutout/worker.mjs'))).toHaveLength(0);
      advance('existing-reopen');
      await tapNav(page, 'القائمة');
      await tapText(page, sample.category);
      await tapText(page, sample.item);
      await expect(page.getByRole('button', { name: L.prepare, exact: true })).toBeEnabled();
      await expect(page.getByRole('button', { name: L.remove, exact: true })).toHaveCount(0);
      successfulModelStart = modelReads;
      advance('existing-prepare');
      await click(page, L.prepare);
    }
    if (sample.name === 'burger') {
      advance('cancel-await-model-download');
      await expect.poll(() => heldModelRequest !== undefined,
        { message: 'Automatic preparation reaches a real model download' }).toBe(true);
      advance('cancel-worker');
      await click(page, L.cancel);
      await expect(page.getByRole('button', { name: L.cancel, exact: true })).toHaveCount(0);
      // Termination normally cancels this request itself; releasing the held
      // route also keeps the test's fault injection bounded after cancellation.
      await heldModelRequest!.abort('aborted').catch(() => {});
      heldModelRequest = undefined;
      advance('cancel-no-automatic-publication');
      await expect(page.getByRole('button', { name: L.publish, exact: true })).toBeEnabled();
      expect(registerCalls, 'Cancelling processing never publishes').toBe(previousRegisters);
      advance('cancel-original-bytes');
      expect(sha((await downloadOriginal()).bytes)).toBe(sha(source));

      modelFault = 'fail';
      advance('fault-start-worker');
      await click(page, L.prepare);
      await waitForText(page, L.failed);
      advance('fault-observed');
      expect(injectedModelFailures).toBe(1);
      advance('fault-no-automatic-publication');
      expect(registerCalls, 'A failed model fetch never publishes').toBe(previousRegisters);
      await expect(page.getByRole('button', { name: L.publish, exact: true })).toBeEnabled();
      advance('fault-original-bytes');
      expect(sha((await downloadOriginal()).bytes), 'Failure retains actual private original bytes').toBe(sha(source));
      successfulModelStart = modelReads;
      advance('retry-worker');
      await click(page, L.prepare); // Retry the actual worker, without mocked inference.
    }
    advance('worker-ready');
    const publish = page.getByRole('button', { name: L.publish, exact: true });
    await reveal(page, publish);
    await expect(publish).toBeEnabled({ timeout: 150_000 });
    if (sample.alpha) {
      advance('alpha-bypass-review');
      await waitForText(page, L.transparent);
      expect(modelReads, 'Real alpha returns original bytes without loading model weights').toBe(previousModelReads);
      await expect(page.getByRole('button', { name: L.remove, exact: true })).toBeDisabled();
    } else {
      // Publish also permits Original after failure; candidate readiness must
      // precede observing the completed retry's exact model downloads.
      advance('cutout-choice-enabled');
      await expect(page.getByRole('button', { name: L.remove, exact: true })).toBeEnabled({ timeout: 150_000 });
      advance('model-chunk-count');
      expect(modelReads - successfulModelStart, 'Successful retry fetches all eleven pinned model chunks').toBe(11);
    }
    if (existingBaseline) {
      advance('existing-verify');
      expect({ fileChoosers, originalUploads, itemSaves },
        'Reopening and preparing an existing photo uses no chooser, upload or source save').toEqual(existingBaseline);
      const existing = await readOriginal();
      expect(existing.status).toBe(200); expect(existing.data.ok).toBe(true);
      expect(existing.data.source_key).toBe(originalKey);
      expect(existing.data.source_snapshot).toEqual(before.data.source_snapshot);
      expect(existing.data.selected_derivative_id).toBeNull();
      const unchanged = await downloadOriginal();
      expect(unchanged.status).toBe(200);
      expect(sha(unchanged.bytes)).toBe(sha(privateBefore.bytes));
    }
    advance('prepublication-no-register');
    expect(registerCalls, 'Saving an original and automatic local review never publishes a candidate').toBe(previousRegisters);
    const dark = page.getByRole('switch', { name: L.dark, exact: true });
    advance('light-review-capture');
    await reveal(page, dark);
    await page.screenshot({ path: resolve(process.env.CINEMATIC_ARTIFACT_DIR!, `product-${sample.name}-light.png`) });
    advance('dark-review-capture');
    await dark.click();
    await page.screenshot({ path: resolve(process.env.CINEMATIC_ARTIFACT_DIR!, `product-${sample.name}-dark.png`) });
    advance('publish-selection');
    if (!sample.alpha) await click(page, L.remove);
    await click(page, L.publish);
    await waitForText(page, L.published, 180_000);
    advance('selection-readback');
    const after = await readOriginal();
    expect(after.data.ok).toBe(true); expect(after.data.source_key).toBe(originalKey);
    expect(after.data.source_snapshot).toEqual(before.data.source_snapshot);
    expect(after.data.selected_derivative_id).toEqual(expect.any(String));
    expect(after.data.selection_version).toBe(before.data.selection_version + 1);
    advance('original-after-publication');
    const privateAfter = await downloadOriginal();
    expect(privateAfter.status).toBe(200);
    expect(sha(privateAfter.bytes), 'Publication preserves exact private original bytes').toBe(sha(privateBefore.bytes));
    advance('registration-proof');
    const registered = registrations.at(-1)!;
    expect(registered.p_treatment).toBe(sample.alpha ? 'original' : 'cutout');
    expect(registered.p_original_key).toBe(originalKey);
    if (sample.alpha) expect(registered.p_candidate_key).toBe(originalKey);
    else expect(registered.p_candidate_key).not.toBe(originalKey);
    advance('selected-private-read');
    const selectedPrivate = await request(fixture, token,
      `/storage/v1/object/authenticated/menu-images/${storagePath(registered.p_candidate_key as string)}`);
    expect(selectedPrivate.status).toBe(200);
    const selectedAlpha = await decodedAlpha(page, selectedPrivate.bytes);
    advance('live-menu-readback');
    const live = await rpc(fixture, null, 'storefront_menu_v6', { p_slug: fixture.ownerA.slug });
    expect(live.status).toBe(200); expect(live.data.ok).toBe(true);
    const row = live.data.product_images_v1.find((r: { item_id: string }) => r.item_id === itemId);
    expect(row).toBeDefined();
    const dimensions: Record<string, number> = {};
    const publishedImages: PublishedProductImage[] = [];
    for (const size of [480, 960]) {
      advance('published-image-fetch');
      const target = localProductMediaTarget(row[`w${size}_url`], 'GET');
      const response = await fetch(target, { redirect: 'error', signal: AbortSignal.timeout(15_000) });
      expect(response.status).toBe(200);
      expect(response.headers.get('content-type')).toContain('image/webp');
      const bytes = Buffer.from(await response.arrayBuffer());
      expect(bytes.length).toBeGreaterThan(0);
      advance('published-image-alpha');
      const alpha = await decodedAlpha(page, bytes);
      expect(alpha.width).toBe(row[`width${size}`]);
      expect(alpha.height).toBe(row[`height${size}`]);
      expect(alpha.transparent, 'Actual published WebP preserves transparent background pixels').toBeGreaterThan(0);
      expect(alpha.opaque, 'Actual published WebP retains opaque subject pixels').toBeGreaterThan(0);
      if (alpha.width === selectedAlpha.width && alpha.height === selectedAlpha.height) {
        expect(alpha.alphaSha256, 'Lossless alpha at unchanged geometry matches the real private source/candidate').toBe(selectedAlpha.alphaSha256);
      }
      publishedImages.push({ variant: `w${size}`, path: row[`w${size}_url`], bytes: bytes.length, sha256: sha(bytes), ...alpha });
      if (sample.name === 'burger-highres') {
        expect([alpha.width, alpha.height], 'The high-res input produces actual 480/960 derivatives').toEqual([size, size * .75]);
        if (size === 960) await saveDecodedPublicPreview(page, bytes, 'quality-highres-published-cutout-w960.png');
      }
      dimensions[`width${size}`] = row[`width${size}`];
      dimensions[`height${size}`] = row[`height${size}`];
    }
    // The same open editor must refresh its optimistic selection proof after
    // success: switching back must not fail with selection_stale.
    if (sample.name === 'burger-highres') {
      advance('highres-cutout-render');
      // The unchanged worker caps the original's longest side at 1600, then
      // c4 independently derives 480/960. Reject a premature smaller raster.
      expect([selectedAlpha.width, selectedAlpha.height]).toEqual([1600, 1200]);
      expect(selectedAlpha.width / selectedAlpha.height).toBeCloseTo(sourceGeometry.width / sourceGeometry.height, 6);
      writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'quality-highres-processed.png'), selectedPrivate.bytes);
      const rendered = await captureHighResolutionMenu(context.browser()!, fixture.ownerA.slug, itemId,
        'experimental-cutout', publishedImages, process.env.CINEMATIC_ARTIFACT_DIR!);
      qualityEvidence.push({ treatment: 'experimental-cutout', sourceBytes: source.length, sourceSha256: sha(source),
        sourceGeometry, processedBytes: selectedPrivate.bytes.length, processedSha256: sha(selectedPrivate.bytes),
        processedGeometry: selectedAlpha, publishedImages, rendered,
        visualMaskAcceptance: 'not-established; saliency alpha may lose plate/food detail; inspect original and processed pixels' });
      writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'quality-highres.json'), JSON.stringify({
        status: 'PARTIAL', buildContext: 'Isolated Actions review build; SF_PRODUCT_CUTOUT_REVIEW=true; removal unavailable by default',
        source: 'Wikimedia Commons Hamburger (9).jpg; Miansari66; CC0 1.0; unmodified original', cases: qualityEvidence,
      }, null, 2));
    }
    if (sample.name === 'burger' || sample.name === 'burger-highres') {
      advance('restore-original-selection');
      await click(page, L.original);
      await click(page, L.publish);
      await waitForText(page, L.published, 180_000);
      advance('restore-original-readback');
      const restored = await readOriginal();
      expect(restored.data.source_key).toBe(originalKey);
      expect(restored.data.selection_version).toBe(after.data.selection_version + 1);
      expect(registrations.at(-1)!.p_treatment).toBe('original');
      const privateRestored = await downloadOriginal();
      expect(privateRestored.status).toBe(200);
      expect(sha(privateRestored.bytes)).toBe(sha(source));
      if (sample.name === 'burger-highres') {
        advance('highres-original-render');
        const originalMenu = await rpc(fixture, null, 'storefront_menu_v6', { p_slug: fixture.ownerA.slug });
        expect(originalMenu.status).toBe(200); expect(originalMenu.data.ok).toBe(true);
        const originalRow = originalMenu.data.product_images_v1.find((r: { item_id: string }) => r.item_id === itemId);
        expect(originalRow).toBeDefined();
        const originalImages: PublishedProductImage[] = [];
        for (const size of [480, 960]) {
          const response = await fetch(localProductMediaTarget(originalRow[`w${size}_url`], 'GET'),
            { redirect: 'error', signal: AbortSignal.timeout(15_000) });
          expect(response.status).toBe(200); expect(response.headers.get('content-type')).toContain('image/webp');
          const bytes = Buffer.from(await response.arrayBuffer()), alpha = await decodedAlpha(page, bytes);
          expect([alpha.width, alpha.height]).toEqual([size, size * .75]);
          expect(alpha.width).toBe(originalRow[`width${size}`]); expect(alpha.height).toBe(originalRow[`height${size}`]);
          expect(alpha.transparent).toBe(0); expect(alpha.opaque).toBe(alpha.width * alpha.height);
          originalImages.push({ variant: `w${size}`, path: originalRow[`w${size}_url`], bytes: bytes.length, sha256: sha(bytes), ...alpha });
          if (size === 960) await saveDecodedPublicPreview(page, bytes, 'quality-highres-published-original-w960.png');
        }
        const rendered = await captureHighResolutionMenu(context.browser()!, fixture.ownerA.slug, itemId,
          'original', originalImages, process.env.CINEMATIC_ARTIFACT_DIR!, source);
        qualityEvidence.push({ treatment: 'original', sourceBytes: source.length, sourceSha256: sha(source), sourceGeometry,
          privateOriginalSha256AfterBothPublications: sha(privateRestored.bytes), originalPreserved: true,
          publishedImages: originalImages, rendered });
        writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'quality-highres.json'), JSON.stringify({
          status: 'PASS', scope: 'Actual isolated service publication and shipped menu rendering; no clean-mask acceptance claim',
          buildContext: 'Isolated Actions review build; SF_PRODUCT_CUTOUT_REVIEW=true; removal unavailable by default',
          source: 'Wikimedia Commons Hamburger (9).jpg; Miansari66; CC0 1.0; unmodified original', cases: qualityEvidence,
        }, null, 2));
      }
    }
    evidence.push({ sample: sample.name, sourceKind: sample.name === 'burger-highres'
      ? 'Genuine licensed camera original, 2816x2112; Wikimedia Commons, Miansari66, CC0 1.0'
      : 'Existing published c4/w480 copy, not private original', sourceGeometry,
      sourceBytes: source.length, sourceSha256: sha(source), treatment: sample.alpha ? 'original-alpha-bypass' : 'u2net-cutout',
      processedBytes: selectedPrivate.bytes.length, processedSha256: sha(selectedPrivate.bytes), processedGeometry: selectedAlpha,
      modelPartReads: modelReads - previousModelReads, originalPreserved: sha(privateAfter.bytes) === sha(privateBefore.bytes),
      privateBeforeSha256: sha(privateBefore.bytes), privateAfterSha256: sha(privateAfter.bytes),
      cancelAndFailedFetchRetainedOriginal: sample.name === 'burger', publishedImages,
      existingOriginalPreparedWithoutUpload: sample.name === 'fries-cup',
      explicitPublication: true, ...dimensions });
    advance('close-product');
    await tapButton(page, 'إلغاء'); // close the item editor; already saved source/presentation remain
  }
  advance('publication-counts', null);
  await Promise.all(publishedReplies);
  expect(publisherCalls.filter(call => call.status === 200 && call.variant === 'w480')).toHaveLength(7);
  expect(publisherCalls.filter(call => call.status === 200 && call.variant === 'w960')).toHaveLength(7);
  advance('unchanged-invariants');
  expect(await readInvariants(fixture, token), 'Hero, logo and receipt settings remain unchanged').toEqual(initialInvariants);
  advance('transport-boundary');
  expect(violation, 'No image bytes or runtime requests leave the allowed loopback services').toBe(false);
  advance('success-evidence');
  writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'product-cutout.json'), JSON.stringify({
    buildContext: 'Isolated Actions review build; SF_PRODUCT_CUTOUT_REVIEW=true; removal unavailable by default',
    model: 'U2Net FP32', modelNativeHeapLimitBytes: 536870912,
    fixturesArePublishedCopies: false, fixtureKinds: ['four-existing-published-copies', 'one-unmodified-licensed-highres-original'], cases: evidence,
  }, null, 2));
}

test('product originals survive local review, explicit selection and publication', async ({ page, context }) => {
  const progress = createProductProgress();
  try {
    await runProductJourney(page, context, progress);
    progress.complete();
  } finally {
    // Fixed enum receipt survives assertion failures. No values or raw error
    // text are recorded; login retains its separate credential-free receipt.
    writeFileSync(resolve(process.env.CINEMATIC_ARTIFACT_DIR!, 'product-progress.json'),
      JSON.stringify(progress.snapshot(), null, 2));
  }
});
