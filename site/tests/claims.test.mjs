// Product-truth contract for the public marketing copy.
//
// The site may only market capabilities that are live in the product. These
// tests fail the build if copy silently reintroduces claims that were removed
// in the release review (advanced inventory, delivery/third-party channels,
// weight-based selling, pre-orders, guaranteed same-day setup, "no hidden
// fees", "no training"). Changing this contract is a deliberate product
// decision: update the list here in the same PR that ships the capability.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const LOCALES = ['ar', 'en', 'he'];
const read = (c) => JSON.parse(readFileSync(join(process.cwd(), 'src', 'locales', `${c}.json`), 'utf8'));

function strings(node, path = '', out = []) {
  if (typeof node === 'string') out.push({ path, value: node });
  else if (Array.isArray(node)) node.forEach((v, i) => strings(v, `${path}[${i}]`, out));
  else if (node && typeof node === 'object') for (const [k, v] of Object.entries(node)) strings(v, path ? `${path}.${k}` : k, out);
  return out;
}

// Forbidden claims per locale. Each entry: [label, regexp].
const FORBIDDEN = {
  ar: [
    ['advanced inventory', /المخزون|(?<![\u0600-\u06FF])جرد(?![\u0600-\u06FF])|استهلاك المكوّنات|وصفات/],
    ['delivery / third-party channels', /توصيل|تطبيقات التوصيل|قنوات متعددة|متعددة القنوات/],
    ['weight-based selling', /بالوزن|الوزن/],
    ['pre-orders', /طلبات مسبقة|حجز مسبق/],
    ['same-day guarantee', /نفس اليوم|خلال ساعات/],
    ['no hidden fees', /رسوم خفية|بدون رسوم/],
    ['no-training claim', /لا تدريب|بدون تدريب|في دقائق/],
    ['fake scale / SLA', /مئات المطاعم|آلاف|99[.,]9|ضمان وقت التشغيل/],
  ],
  en: [
    ['advanced inventory', /\binventory\b|stock count|stock level|depletion|purchas|recipe|\bBOM\b/i],
    ['delivery / third-party channels', /\bdelivery\b|multi-?channel|aggregator|Wolt|Uber|Deliveroo/i],
    ['weight-based selling', /by weight|weigh/i],
    ['pre-orders', /pre-?orders?/i],
    ['same-day guarantee', /same[- ]day|within hours/i],
    ['no hidden fees', /hidden fees|no fees/i],
    ['no-training claim', /no (long )?training|in minutes/i],
    ['fake scale / SLA', /hundreds of|thousands of|99[.,]9|uptime guarantee/i],
  ],
  he: [
    ['advanced inventory', /מלאי|ספירת|מתכונים/],
    ['delivery / third-party channels', /משלוח|רב-?ערוצי|וולט|אפליקציות משלוחים/],
    ['weight-based selling', /במשקל|שקילה/],
    ['pre-orders', /הזמנות מראש|הזמנה מראש/],
    ['same-day guarantee', /באותו היום|תוך שעות/],
    ['no hidden fees', /עלויות נסתרות|ללא עמלות/],
    ['no-training claim', /בלי הדרכות|ללא הדרכה|בדקות/],
    ['fake scale / SLA', /מאות מסעדות|אלפי|99[.,]9|התחייבות זמינות/],
  ],
};

for (const code of LOCALES) {
  test(`${code}: no unsupported product claims in the locale copy`, () => {
    const hits = [];
    for (const { path, value } of strings(read(code))) {
      for (const [label, re] of FORBIDDEN[code]) if (re.test(value)) hits.push(`${label} @ ${path}: "${value}"`);
    }
    assert.deepEqual(hits, []);
  });
}

test('the corrected claims are the ones shipped (spot checks)', () => {
  const ar = read('ar');
  assert.equal(ar.features.items[2].title, 'إدارة القائمة');
  assert.match(ar.features.items[0].desc, /طاولات وسفري/);
  assert.match(ar.business.items[2].desc, /قوائم مرنة/);
  assert.match(ar.business.items[4].desc, /شاشة مطبخ واضحة/);
  assert.match(ar.features.items[9].desc, /بأقل خطوات/);
  assert.match(ar.features.items[6].desc, /تقلّل وقت التعلم/);
  assert.match(ar.pricing.subtitle, /عرض سعر واضح/);
});

test('ar / en / he carry the same structure (content parity)', () => {
  const shape = (node) => {
    if (Array.isArray(node)) return `[${node.map(shape).join(',')}]`;
    if (node && typeof node === 'object')
      return `{${Object.keys(node)
        .sort()
        .map((k) => `${k}:${shape(node[k])}`)
        .join(',')}}`;
    return typeof node;
  };
  const [ar, en, he] = LOCALES.map(read);
  const strip = (o) => {
    const c = JSON.parse(JSON.stringify(o));
    for (const k of ['code', 'dir', 'htmlLang', 'ogLocale', 'path', 'name']) delete c[k];
    return c;
  };
  assert.equal(shape(strip(en)), shape(strip(ar)), 'en shape differs from ar');
  assert.equal(shape(strip(he)), shape(strip(ar)), 'he shape differs from ar');
  // Non-text identifiers must match exactly across locales.
  const ids = (o) => ({
    products: o.products.items.map((i) => i.id),
    tabs: o.showcase.tabs.map((t) => [t.id, t.shots.map((s) => s.src)]),
    icons: [o.features.items, o.business.items, o.why.items, o.hero.trust].map((a) => a.map((i) => i.icon)),
    typeValues: o.contact.form.typeOptions.map((x) => x.value),
    branchValues: o.contact.form.branchesOptions.map((x) => x.value),
  });
  assert.deepEqual(ids(en), ids(ar));
  assert.deepEqual(ids(he), ids(ar));
  // Every string is non-empty in every locale.
  for (const code of LOCALES) for (const { path, value } of strings(strip(read(code)))) assert.ok(value.trim().length > 0, `${code} ${path} empty`);
});

test('vercel.json keeps every product route alive on the brand root and redirects www to the apex', () => {
  const cfg = JSON.parse(readFileSync(join(process.cwd(), 'vercel.json'), 'utf8'));
  const r = cfg.redirects;
  const find = (source) => r.find((x) => x.source === source);
  for (const [source, dest] of [
    ['/pos', 'https://app.bizbot.systems/pos'],
    ['/pos/:path*', 'https://app.bizbot.systems/pos/:path*'],
    ['/kds', 'https://app.bizbot.systems/kds'],
    ['/kds/:path*', 'https://app.bizbot.systems/kds/:path*'],
    ['/kiosk', 'https://app.bizbot.systems/kiosk'],
    ['/kiosk/:path*', 'https://app.bizbot.systems/kiosk/:path*'],
    ['/dashboard', 'https://app.bizbot.systems/'],
    ['/dashboard/:path*', 'https://app.bizbot.systems/:path*'],
    ['/login', 'https://app.bizbot.systems/'],
    ['/auth/:path*', 'https://app.bizbot.systems/auth/:path*'],
  ]) {
    const rule = find(source);
    assert.ok(rule, `missing redirect for ${source}`);
    assert.equal(rule.destination, dest, source);
    assert.equal(rule.permanent, false, `${source} must stay a temporary redirect`);
  }
  const www = r.find((x) => x.has && x.has.some((h) => h.type === 'host' && h.value === 'www.bizbot.systems'));
  assert.ok(www, 'www → apex rule missing');
  assert.equal(www.destination, 'https://bizbot.systems/:path*');
  assert.equal(www.permanent, true);
  // Security headers must stay in place.
  const all = cfg.headers.find((h) => h.source === '/(.*)').headers.map((h) => h.key);
  for (const k of ['Content-Security-Policy', 'X-Frame-Options', 'Strict-Transport-Security', 'Referrer-Policy']) assert.ok(all.includes(k), k);
});
