import { expect, type BrowserContext, type Page, type Response } from '@playwright/test';
import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { LOCAL_API, LOGICAL_ORIGIN, localMediaTarget } from './live-transport.mjs';
export const backgroundFixture = resolve(__dirname, 'fixtures/background-quality/background-2816.jpg');
const source = { width: 2816, height: 2112, bytes: 1463022, sha256: '3e6b8197d0f1e17da8a86b5f0db95330394e11bc30c34b16ca0a076959346d54' };
const base = { width: 960, height: 720, bytes: 111406, sha256: '211a00daf75bb8f868cec1c95aaa1e4c5e7d1d9aba8b46e6867d2753a8ff2ed3' };
const high = { width: 2560, height: 1920, bytes: 459258, sha256: 'c0120cc575b08c4227d3c060ac78af28ee4ec7085ec4fd85f510778933fcd85f' };
const sha = (bytes: Buffer) => createHash('sha256').update(bytes).digest('hex');
type PublicPair = {
    baseUrl: string;
    highUrl: string;
};
type Fixture = {
    anonKey: string;
    ownerA: {
        slug: string;
        orgId: string;
        restaurantId: string;
        branchId: string;
    };
};
type Json = Record<string, any>;
export class BackgroundQuality {
    readonly views: Record<string, unknown>[] = [];
    private readonly requests: Json[] = [];
    private readonly responses: Promise<{
        status: number;
        body: Json;
    }>[] = [];
    private confirmed = false;
    private retried = false;
    private readonly originalReads: {bytes:number; sha256:string}[] = [];
    private readonly publishedReads: {width:number; height:number; bytes:number; sha256:string}[] = [];
    private publisherResult?: {recipe:string; variant:string; rung:number; width:number; height:number; bytes:number; sha256:string};
    constructor(private readonly dir: string) {
        const uploaded = readFileSync(backgroundFixture);
        expect([uploaded.length, sha(uploaded)], 'The selected file is the documented full-resolution camera copy')
            .toEqual([source.bytes, source.sha256]);
    }
    observe(page: Page) {
        const isBackground = (url: string, method: string, body: Json | null) => url === LOCAL_API + '/functions/v1/storefront-media-publish' && method === 'POST' && body?.slot === 'background';
        page.on('request', r => {
            if (r.url() !== LOCAL_API + '/functions/v1/storefront-media-publish' || r.method() !== 'POST')
                return;
            const body = r.postDataJSON();
            if (isBackground(r.url(), r.method(), body))
                this.requests.push(body);
        });
        page.on('response', r => {
            if (r.url() !== LOCAL_API + '/functions/v1/storefront-media-publish' || r.request().method() !== 'POST')
                return;
            if (isBackground(r.url(), 'POST', r.request().postDataJSON())) {
                this.responses.push(r.json().catch(() => ({})).then(body => ({ status: r.status(), body })));
            }
        });
    }
    record(phase: string) {
        writeFileSync(resolve(this.dir, 'background-quality.json'), JSON.stringify({
            phase, data: 'authorized isolated fixture', expectedOriginal: source, expectedBase: base, expectedHigh: high,
            companionPublished: this.confirmed, explicitRetry: this.retried, originalVerifiedReads: this.originalReads, publishedReads:this.publishedReads, publisherResult:this.publisherResult,
            // Only bounded fixed-resource facts enter this receipt.
            views: this.views,
        }, null, 2));
    }
    async verifyPublication(baseMediaId: string, retry: () => Promise<void>) {
        this.record('checking-companion');
        const getSuccess = async () => {
            const replies = await Promise.all(this.responses);
            return replies.find(r => r.status === 200 && r.body.status === 'published' && r.body.media?.base_media_id === baseMediaId)?.body;
        };
        let ok = await getSuccess();
        if (!ok) {
            // The app already bounds its automatic retry for an unknown HTTP outcome.
            // Only that actual state enables an explicit same-request UI retry after Save.
            const before = this.requests.length;
            expect(before).toBeGreaterThan(0);
            const pending = this.requests[before - 1];
            await retry();
            await expect.poll(getSuccess, { timeout: 120000, message: 'The user-visible retry publishes the same verified companion' }).toBeTruthy();
            expect(this.requests.length).toBeGreaterThan(before);
            const replay = this.requests[before];
            expect(replay.request_id === pending.request_id && replay.base_media_id === baseMediaId && replay.rung === pending.rung
                && replay.base_rung === pending.base_rung, 'The actual UI retries the identical uncertain request').toBe(true);
            this.retried = true;
            ok = await getSuccess();
        }
        const media = ok!.media;
        expect(ok!.recipe).toBe('storefront-background-b1');
        expect(ok!.rung).toBe(0);
        expect([media.variant, media.state, media.width, media.height, media.bytes, media.content_hash])
            .toEqual(['bg2560', 'published', high.width, high.height, high.bytes, high.sha256]);
        this.publisherResult={ recipe:ok!.recipe, variant:media.variant, rung:ok!.rung, width:media.width, height:media.height, bytes:media.bytes, sha256:media.content_hash };
        this.confirmed = true;
        this.record('companion-published');
    }
    async privateOriginal(f: Fixture, token: string, mediaId: string) {
        const sourceReply = await fetch(LOCAL_API + '/rest/v1/rpc/get_storefront_background_source_v1', {
            method: 'POST', redirect: 'error', headers: { apikey: f.anonKey, authorization: 'Bearer ' + token, 'content-type': 'application/json' },
            body: JSON.stringify({ p_organization_id: f.ownerA.orgId, p_restaurant_id: f.ownerA.restaurantId, p_branch_id: f.ownerA.branchId, p_base_media_id: mediaId }),
        });
        expect(sourceReply.status, 'Authorized manager reads the base association').toBe(200);
        const rule = await sourceReply.json();
        expect(rule.ok && rule.base_media_id === mediaId && rule.source_bucket === 'restaurant-logos'
            && rule.base_hash === base.sha256 && rule.base_width === base.width && rule.base_height === base.height).toBe(true);
        const parts = typeof rule.source_key === 'string' ? rule.source_key.split('/') : [];
        expect(parts.length === 4 && parts[0] === f.ownerA.orgId && parts[1] === f.ownerA.restaurantId
            && parts[2] === 'logo' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.jpg$/.test(parts[3]), 'Only the scoped original can be downloaded').toBe(true);
        const result = await fetch(LOCAL_API + '/storage/v1/object/authenticated/restaurant-logos/' + parts.map(encodeURIComponent).join('/'), {
            redirect: 'error', headers: { apikey: f.anonKey, authorization: 'Bearer ' + token },
        });
        expect(result.status).toBe(200);
        const bytes = Buffer.from(await result.arrayBuffer());
        expect([bytes.length, sha(bytes)], 'The retained private original is byte-identical to the chosen file')
            .toEqual([source.bytes, source.sha256]);
        this.originalReads.push({bytes:bytes.length,sha256:sha(bytes)});
        this.record('original-verified');
    }
    async readManifest(f: Fixture): Promise<PublicPair> {
        const menus = await Promise.all(['storefront_menu_v6', 'storefront_menu_v7'].map(async (name) => {
            const result = await fetch(LOCAL_API + '/rest/v1/rpc/' + name, { method: 'POST', redirect: 'error',
                headers: { apikey: f.anonKey, authorization: 'Bearer ' + f.anonKey, 'content-type': 'application/json' }, body: JSON.stringify({ p_slug: f.ownerA.slug }) });
            expect(result.status).toBe(200);
            const menu = await result.json();
            expect(menu.ok).toBe(true);
            delete menu.server_ts;
            return menu;
        }));
        const [v6, v7] = menus;
        const manifest = v7.menu_background_images_v1;
        delete v7.menu_background_images_v1;
        expect(v7, 'v7 projects exactly to v6 with independently live reads').toEqual(v6);
        expect(manifest?.base_url).toBe(v6.content_v1.appearance.menu_background_url);
        expect(manifest, 'The selected genuine background has a real responsive pair').toBeTruthy();
        expect(Object.keys(manifest).sort()).toEqual(['base_url', 'variants']);
        expect(manifest.variants).toHaveLength(2);
        const urls: string[] = [];
        for (const [index, spec] of [base, high].entries()) {
            const row = manifest.variants[index];
            expect(Object.keys(row).sort()).toEqual(['height', 'url', 'width']);
            expect([row.width, row.height]).toEqual([spec.width, spec.height]);
            if (index === 0)
                expect(row.url).toBe(manifest.base_url);
            expect(row.url.endsWith('/' + spec.sha256 + '.webp'), 'The public address identifies these exact bytes').toBe(true);
            const logical = LOGICAL_ORIGIN + row.url;
            const res = await fetch(localMediaTarget(logical), { redirect: 'error' });
            expect(res.status).toBe(200);
            expect(res.headers.get('content-type')).toContain('image/webp');
            const bytes = Buffer.from(await res.arrayBuffer());
            expect([bytes.length, sha(bytes)]).toEqual([spec.bytes, spec.sha256]);
            this.publishedReads.push({width:row.width,height:row.height,bytes:bytes.length,sha256:sha(bytes)});
            urls.push(logical);
        }
        this.record('public-pair-verified');
        return { baseUrl: urls[0], highUrl: urls[1] };
    }
    async captureScene(browser: NonNullable<ReturnType<BrowserContext['browser']>>, route: string, pair: PublicPair, scene: 'legacy' | 'reference_dark', guard: (context: BrowserContext) => Promise<{
        check: () => Promise<void>;
    }>) {
        for (const [name, width, height, dpr] of [
            ['desktop', 1440, 1000, 1], ['phone-portrait', 390, 844, 1], ['phone-landscape', 844, 390, 1], ['phone-landscape-retina', 844, 390, 2],
        ] as const) {
            this.record('verifying-'+scene+'-'+name);
            const context = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: dpr, locale: 'ar', serviceWorkers: 'block' });
            try {
                const network = await guard(context);
                const page = await context.newPage();
                const selectedResponses: Response[] = [];
                page.on('response', r => {
                    if (r.url() === pair.baseUrl || r.url() === pair.highUrl) selectedResponses.push(r);
                });
                await page.goto(route, { waitUntil: 'domcontentloaded' });
                const root = page.locator('[data-sf-root]');
                if (scene === 'reference_dark')
                    await expect(root).toHaveAttribute('data-sf-scene', scene);
                else
                    await expect(root).not.toHaveAttribute('data-sf-scene', 'reference_dark');
                const img = page.locator('[data-sf-menu-background="custom"] img');
                await expect(img).toHaveAttribute('src', pair.baseUrl);
                await expect(img).toHaveAttribute('srcset', pair.baseUrl + ' 960w, ' + pair.highUrl + ' 2560w');
                const coverWidth = Math.max(width, height * high.width / high.height);
                const useHigh = coverWidth * dpr > base.width;
                const selected = useHigh ? pair.highUrl : pair.baseUrl;
                const spec = useHigh ? high : base;
                await expect.poll(() => img.evaluate((n: HTMLImageElement) => n.complete && n.currentSrc), 'Native srcset selection settles').toBe(selected);
                await expect.poll(() => selectedResponses.length).toBe(1);
                const res = selectedResponses[0];
                expect(res.url()).toBe(selected);
                expect(res.status()).toBe(200);
                const bytes = await res.body();
                expect([bytes.length, sha(bytes)]).toEqual([spec.bytes, spec.sha256]);
                const decoded = await page.evaluate(async (encoded) => {
                    const raw = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
                    const bmp = await createImageBitmap(new Blob([raw], { type: 'image/webp' }));
                    const size = [bmp.width, bmp.height];
                    bmp.close();
                    return size;
                }, bytes.toString('base64'));
                expect(decoded, 'Encoded pixels of the actual browser response').toEqual([spec.width, spec.height]);
                const inspect = () => img.evaluate(async (n: HTMLImageElement) => {
                    await n.decode();
                    const b = n.getBoundingClientRect(), style = getComputedStyle(n), overlay = getComputedStyle(n.parentElement!, '::after');
                    return { x: b.x, y: b.y, width: b.width, height: b.height, dpr: devicePixelRatio, fit: style.objectFit, position: style.position,
                        dim: Number(overlay.opacity), naturalWidth: n.naturalWidth, naturalHeight: n.naturalHeight, currentSrc: n.currentSrc, sizes: n.sizes, center: style.objectPosition, filter: style.filter, layoutWidth: document.documentElement.clientWidth };
                });
                const top = await inspect();
                expect([top.x, top.y, top.width, top.height, top.fit, top.position, top.dpr, top.dim, top.center, top.filter])
                    .toEqual([0, 0, top.layoutWidth, height, 'cover', 'fixed', dpr, 0.15, '50% 50%', 'none']);
                expect(top.naturalWidth).toBeGreaterThan(0);
                if (name === 'desktop' || name === 'phone-portrait') {
                    // Only the verified synthetic restaurant and the pinned public photo reach this capture.
                    await page.evaluate(() => {
                        const label = document.createElement('div');
                        label.textContent = 'ISOLATED CI — CC0 BACKGROUND';
                        label.setAttribute('data-background-test-label', '');
                        Object.assign(label.style, { position: 'fixed', bottom: '0', left: '0', zIndex: '2147483647', background: '#fff', color: '#111', padding: '8px', font: '12px sans-serif' });
                        document.body.append(label);
                    });
                    try {
                        await page.screenshot({ path: resolve(this.dir, 'background-quality-' + scene + '-' + name + '-test-data.png'), animations: 'disabled' });
                    }
                    finally {
                        await page.locator('[data-background-test-label]').evaluateAll(nodes => nodes.forEach(node => node.remove()));
                    }
                }
                const sections = page.locator('[data-sf-module="sections"]');
                await expect(sections).toHaveCount(4);
                for (const target of [sections.nth(2), page.locator('[data-sf-module="footer"]')]) {
                    await target.scrollIntoViewIfNeeded();
                    await expect(target).toBeInViewport();
                    expect(await page.evaluate(() => scrollY)).toBeGreaterThan(0);
                    expect(await inspect(), 'The same photo and viewport geometry survive scrolling').toEqual(top);
                }
                await page.waitForLoadState('networkidle');
                expect(selectedResponses.length, 'No second background resource fetched on scroll').toBe(1);
                this.views.push({ scene, viewport: name, width, height, dpr, selected: useHigh ? 'bg2560' : 'w960', encodedWidth: spec.width,
                    encodedHeight: spec.height, encodedBytes: bytes.length, sha256: spec.sha256, coverWidth, requiredPhysicalWidth: coverWidth * dpr,
                    naturalWidth: top.naturalWidth, naturalHeight: top.naturalHeight, sizes: top.sizes, dim: top.dim, paintWidth: coverWidth, paintHeight: coverWidth * spec.height / spec.width, topMiddleFooterMatch: true, backgroundRequests: 1 });
                this.record('responsive-scene-view');
                await network.check();
            }
            finally {
                await context.close();
            }
        }
    }
    complete() {
        expect(this.originalReads).toHaveLength(2);
        expect(this.confirmed).toBe(true);
        expect(this.views).toHaveLength(8);
        this.record('PASS');
    }
}
