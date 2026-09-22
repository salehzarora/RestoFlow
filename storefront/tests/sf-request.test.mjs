// Phase E: the request status model, the fixture status source, the message
// composer and the dictionary keys the received / status screens consume.
// Everything typed here is synthetic.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const status = await import('../src/ui/storefront/request/status.ts');
const { composeMessage } = await import('../src/ui/storefront/request/message.ts');
const { PUBLIC_ORIGIN, absoluteUrl } = await import('../src/routes/origin.ts');
const { requestPath } = await import('../src/routes/routes.ts');
const { isValidRef } = await import('../src/theme/sanitize.ts');
const fixture = await import('../src/source/request-fixture.ts');
const { DEMO_REQUEST_REF, DEMO_DISPLAY_CODE, DEMO_REQUEST_SLUG } = await import('../src/source/request-ref.ts');
const { buildQuote } = await import('../src/money/quote.ts');
const { MENU_ITEMS, MENU_VERSION, TAX_RATE } = await import('../src/source/menu-fixture.ts');
const { findZone } = await import('../src/source/zones.ts');
const { buildTheme, AA } = await import('../src/theme/buildTheme.ts');
const { contrast } = await import('../src/theme/contrast.ts');

const NOW = 1_800_000_000_000; // a fixed instant; nothing here reads a real clock
const clock = () => NOW;

/** Wait for the fixture's timers without wall-clock coupling. */
const settle = (ms = 5) => new Promise((r) => setTimeout(r, ms));

/** Subscribe and resolve with the first snapshot (or 'missing'). */
function first(source, ref = DEMO_REQUEST_REF) {
  return new Promise((resolve) => {
    const stop = source.subscribe(
      ref,
      (s) => {
        stop();
        resolve(s);
      },
      () => {
        stop();
        resolve('missing');
      },
    );
  });
}

// ------------------------------------------------------------ the state table

test('nine states, one table: pending, ttl, terminal and the action set per state', () => {
  assert.deepEqual(status.REQUEST_STATES, [
    'received', 'waiting', 'accepted', 'preparing', 'ready', 'completed', 'rejected', 'expired', 'cancelled',
  ]);
  // The pending predicate is the prototype's canCancel (:847): received OR waiting.
  assert.deepEqual(status.REQUEST_STATES.filter(status.isPending), ['received', 'waiting']);
  // The TTL pill is narrower than pending: waiting only (:847 showTtl).
  assert.deepEqual(status.REQUEST_STATES.filter((s) => status.STATE_TABLE[s].ttl), ['waiting']);
  // Terminal outcomes replace the tail; completed is NOT terminal but gets order-again.
  assert.deepEqual(status.TERMINAL_STATES, ['rejected', 'expired', 'cancelled']);
  assert.equal(status.STATE_TABLE.completed.terminal, false);
  assert.deepEqual(status.STATE_TABLE.completed.actions, ['orderAgain']);
  // Action sets (:567-:569): chat+cancel while pending, chat only while active.
  for (const s of ['received', 'waiting']) assert.deepEqual(status.STATE_TABLE[s].actions, ['chat', 'cancel']);
  for (const s of ['accepted', 'preparing', 'ready']) assert.deepEqual(status.STATE_TABLE[s].actions, ['chat']);
  for (const s of ['rejected', 'expired', 'cancelled']) assert.deepEqual(status.STATE_TABLE[s].actions, ['orderAgain']);
  // Tones (COMPONENT_INVENTORY.md:164).
  assert.equal(status.STATE_TABLE.received.tone, 'info');
  assert.equal(status.STATE_TABLE.waiting.tone, 'warn');
  assert.equal(status.STATE_TABLE.expired.tone, 'warn');
  assert.equal(status.STATE_TABLE.rejected.tone, 'bad');
  assert.equal(status.STATE_TABLE.cancelled.tone, 'neutral');
  for (const s of ['accepted', 'preparing', 'ready', 'completed']) assert.equal(status.STATE_TABLE[s].tone, 'ok');
  // Cancel is the pending predicate, applied to a snapshot.
  assert.equal(status.canCancel({ state: 'waiting' }), true);
  assert.equal(status.canCancel({ state: 'accepted' }), false);
});

test('the timeline shows a time ONLY for a recorded event, and terminal states replace the tail', () => {
  const base = {
    ref: DEMO_REQUEST_REF, slug: DEMO_REQUEST_SLUG, displayCode: DEMO_DISPLAY_CODE, service: 'pickup',
    zoneName: null, payment: 'cash', lines: [], subtotalMinor: 0, feeMinor: 0, taxMinor: 0, totalMinor: 0,
    createdAt: NOW, expiresAt: null, ttlMinutes: 30, version: 1,
  };
  // Preparing with events for received and waiting only: accepted has NO time.
  const prep = status.timelineFor({
    ...base, state: 'preparing',
    events: [{ state: 'received', at: NOW }, { state: 'waiting', at: NOW + 20_000 }],
  });
  assert.deepEqual(prep.map((n) => [n.state, n.kind, n.at]), [
    ['received', 'done', NOW], ['waiting', 'done', NOW + 20_000], ['accepted', 'done', null],
    ['preparing', 'current', null], ['ready', 'future', null], ['completed', 'future', null],
  ]);
  assert.equal(prep.filter((n) => n.kind === 'current').length, 1);
  // A terminal outcome: received + waiting done, ONE terminal node, three in all.
  const rej = status.timelineFor({ ...base, state: 'rejected', events: [{ state: 'received', at: NOW }, { state: 'rejected', at: NOW + 1 }] });
  assert.deepEqual(rej.map((n) => [n.state, n.kind, n.at]), [
    ['received', 'done', NOW], ['waiting', 'done', null], ['rejected', 'terminal', NOW + 1],
  ]);
  // The countdown sub-line sits on the CURRENT waiting node only.
  const wait = status.timelineFor({ ...base, state: 'waiting', events: [] });
  assert.deepEqual(wait.filter((n) => n.countdown).map((n) => n.state), ['waiting']);
  assert.deepEqual(status.timelineFor({ ...base, state: 'accepted', events: [] }).filter((n) => n.countdown), []);
});

test('the TTL comes from expiresAt and the injected instant, formats M:SS, clamps at 0:00, and exists only while waiting', () => {
  const snap = { state: 'waiting', expiresAt: NOW + 23 * 60_000 + 39_000 };
  assert.deepEqual(status.ttlFor(snap, NOW), { msLeft: 23 * 60_000 + 39_000, text: '23:39' });
  assert.equal(status.ttlFor(snap, NOW + 23 * 60_000 + 30_000).text, '0:09');
  assert.equal(status.ttlFor(snap, NOW + 60 * 60_000).text, '0:00');
  assert.equal(status.ttlFor({ state: 'received', expiresAt: NOW + 1000 }, NOW), null, 'received ticks but shows no pill');
  assert.equal(status.ttlFor({ state: 'accepted', expiresAt: NOW + 1000 }, NOW), null);
  assert.equal(status.ttlFor({ state: 'waiting', expiresAt: null }, NOW), null, 'no window, no pill');
});

test('a snapshot may replace the current one only when it is a NEWER version of the SAME ref', () => {
  const a = { ref: DEMO_REQUEST_REF, version: 1 };
  const b = { ref: DEMO_REQUEST_REF, version: 2 };
  assert.equal(status.supersedes(null, a, DEMO_REQUEST_REF), true);
  assert.equal(status.supersedes(a, b, DEMO_REQUEST_REF), true);
  assert.equal(status.supersedes(b, a, DEMO_REQUEST_REF), false, 'an older answer never wins');
  assert.equal(status.supersedes(a, a, DEMO_REQUEST_REF), false, 'the same version is not news');
  assert.equal(status.supersedes(null, { ref: 'OTHER-1', version: 9 }, DEMO_REQUEST_REF), false, 'a foreign ref is refused');
});

// ---------------------------------------------------------- the one ref

test('one opaque demo ref, distinct from the display code, is the only pre-rendered request', () => {
  assert.deepEqual(fixture.requestRefs(), [DEMO_REQUEST_REF]);
  assert.ok(isValidRef(DEMO_REQUEST_REF), 'the ref must satisfy the route shape');
  assert.notEqual(DEMO_REQUEST_REF, DEMO_DISPLAY_CODE);
  assert.ok(!DEMO_REQUEST_REF.includes('2487'), 'the ref is not the display code in disguise');
  assert.equal(DEMO_DISPLAY_CODE, '#MB-2487', 'the prototype REST.code');
  const r = fixture.resolveRequest(DEMO_REQUEST_REF);
  assert.equal(r.slug, DEMO_REQUEST_SLUG);
  assert.equal(r.tenant.slug, DEMO_REQUEST_SLUG);
  assert.equal(r.contentLocale, 'ar');
  assert.equal(fixture.resolveRequest('MB-2487'), null, 'the display code is not a route');
  assert.equal(fixture.resolveRequest('demo-closed'), null);
  // Evidence builds add NO request document: the env flag does not reach this list.
  process.env.SF_EVIDENCE_ROUTES = '1';
  try {
    assert.deepEqual(fixture.requestRefs(), [DEMO_REQUEST_REF]);
  } finally {
    delete process.env.SF_EVIDENCE_ROUTES;
  }
});

test('the request scenario switch is a closed allowlist', () => {
  assert.deepEqual(fixture.readRequestScenario(''), null);
  assert.deepEqual(fixture.readRequestScenario('?fx=status-accepted'), { kind: 'state', state: 'accepted' });
  assert.deepEqual(fixture.readRequestScenario('?fx=status-bogus'), null);
  assert.deepEqual(fixture.readRequestScenario('?fx=wa-fallback'), { kind: 'fallback' });
  assert.deepEqual(fixture.readRequestScenario('?fx=status-accepts-late'), { kind: 'accepts-late' });
  assert.deepEqual(fixture.readRequestScenario('?fx=status-expires-late'), { kind: 'expires-late' });
  assert.deepEqual(fixture.readRequestScenario('?fx=status-missing'), { kind: 'missing' });
  assert.deepEqual(fixture.readRequestScenario('?fx=server-error'), null, 'a FLOW token selects nothing here');
  assert.deepEqual(fixture.readRequestScenario('?fx=<script>'), null);
  assert.equal(fixture.REQUEST_SCENARIOS.length, 13);
});

// ------------------------------------------------------- the status source

test('the fixture source never answers synchronously, prices through the money authority, and invents no times', async () => {
  const source = fixture.demoStatusSource({ scenario: null, clock, cancelDelayMs: 0 });
  let sync = null;
  const stop = source.subscribe(DEMO_REQUEST_REF, (s) => { sync = s; }, () => { sync = 'missing'; });
  assert.equal(sync, null, 'subscribe() must not deliver during the call');
  await settle();
  stop();
  const snap = sync;
  assert.equal(snap.state, 'waiting', 'a direct load opens waiting (:723, :731)');
  assert.equal(snap.ref, DEMO_REQUEST_REF);
  assert.equal(snap.displayCode, DEMO_DISPLAY_CODE);
  assert.equal(snap.version, 1);
  // The demo request is the prototype's small seed, delivered to Kafr Manda: 141.60.
  const quote = buildQuote({
    cart: { schema: 1, slug: DEMO_REQUEST_SLUG, menuVersion: MENU_VERSION, lines: snap.lines.map((l, i) => ({ lineId: `q${i}`, itemId: l.itemId, qty: l.qty, selections: l.selections, note: '' })) },
    items: MENU_ITEMS, service: 'delivery', zone: findZone('kafrmanda'), taxRate: TAX_RATE,
  });
  assert.equal(snap.totalMinor, quote.totalMinor);
  assert.equal(snap.totalMinor, 14160);
  assert.equal(snap.subtotalMinor, 11000);
  assert.equal(snap.feeMinor, 1000);
  assert.equal(snap.taxMinor, 2160);
  assert.equal(snap.zoneName, 'كفر مندا');
  // Every event is a RECORD; the timeline never reads createdAt + n.
  assert.deepEqual(snap.events.map((e) => e.state), ['received', 'waiting']);
  for (const e of snap.events) assert.ok(e.at >= snap.createdAt && e.at <= NOW);
  assert.equal(snap.expiresAt, snap.createdAt + 30 * 60_000);
  // No contact field exists on a snapshot at all.
  for (const k of Object.keys(snap)) assert.ok(!['fullName', 'phone', 'street', 'building', 'apartment', 'deliveryNotes', 'area', 'note', 'contact', 'customer'].includes(k), `snapshot carries ${k}`);
});

test('every state opens deterministically, with explicit event records and a TTL only while pending', async () => {
  for (const state of status.REQUEST_STATES) {
    const source = fixture.demoStatusSource({ scenario: { kind: 'state', state }, clock, cancelDelayMs: 0 });
    const snap = await first(source);
    assert.equal(snap.state, state);
    assert.equal(snap.expiresAt === null, !status.isPending(state), `${state}: expiresAt only while pending`);
    const nodes = status.timelineFor(snap);
    // Every done / current / terminal node has a recorded time; every future node has none.
    for (const n of nodes) assert.equal(n.at !== null, n.kind !== 'future', `${state}/${n.state}: ${n.kind} at=${n.at}`);
    // And the ages are the fixture's own records, not a formula: strictly increasing.
    const ats = snap.events.map((e) => e.at);
    assert.deepEqual(ats, [...ats].sort((a, b) => a - b));
    assert.ok(ats.every((t) => t <= NOW), `${state}: an event in the future`);
  }
});

test('cancel is refused once the restaurant has answered - the source guards, not the screen', async () => {
  // While pending: cancel succeeds and every subscriber sees the new version.
  const pending = fixture.demoStatusSource({ scenario: null, clock, cancelDelayMs: 0 });
  const seen = [];
  const stop = pending.subscribe(DEMO_REQUEST_REF, (s) => seen.push(s), () => {});
  await settle();
  const cancelled = await pending.cancel(DEMO_REQUEST_REF, 1);
  assert.equal(cancelled.kind, 'cancelled');
  assert.equal(cancelled.snapshot.state, 'cancelled');
  assert.equal(cancelled.snapshot.version, 2);
  assert.equal(cancelled.snapshot.expiresAt, null);
  assert.deepEqual(seen.map((s) => s.state), ['waiting', 'cancelled']);
  stop();

  // Accepted while the confirmation was open: the cancel is refused and the
  // caller receives the accepted snapshot, never a cancelled one.
  // A screen keeps its subscription open while the sheet is up; so does this.
  const late = fixture.demoStatusSource({ scenario: { kind: 'accepts-late' }, clock, cancelDelayMs: 0, lateMs: 5 });
  const lateSeen = [];
  const stopLate = late.subscribe(DEMO_REQUEST_REF, (s) => lateSeen.push(s), () => {});
  await settle(30);
  const firstSnap = lateSeen[0];
  assert.equal(firstSnap.state, 'waiting');
  assert.deepEqual(lateSeen.map((s) => s.state), ['waiting', 'accepted'], 'the restaurant answered while the sheet was open');
  const refused = await late.cancel(DEMO_REQUEST_REF, firstSnap.version);
  stopLate();
  assert.equal(refused.kind, 'not_pending');
  assert.equal(refused.snapshot.state, 'accepted');
  assert.equal(refused.snapshot.version, 2);
  assert.ok(refused.snapshot.events.some((e) => e.state === 'accepted'), 'acceptance is a recorded event');

  // A stale version is refused even while still pending.
  const stale = fixture.demoStatusSource({ scenario: null, clock, cancelDelayMs: 0 });
  await first(stale);
  const r = await stale.cancel(DEMO_REQUEST_REF, 99);
  assert.equal(r.kind, 'not_pending');
  assert.equal(r.snapshot.state, 'waiting', 'nothing was cancelled');

  // An unknown ref is unknown.
  assert.deepEqual(await stale.cancel('NOPE-1', 1), { kind: 'unknown' });
});

test('expiry is a SOURCE event at expiresAt, and the missing scenario answers missing', async () => {
  const source = fixture.demoStatusSource({ scenario: { kind: 'expires-late' }, clock, lateMs: 10, cancelDelayMs: 0 });
  const seen = [];
  const stop = source.subscribe(DEMO_REQUEST_REF, (s) => seen.push(s), () => {});
  await settle(40);
  stop();
  assert.deepEqual(seen.map((s) => s.state), ['waiting', 'expired']);
  assert.equal(seen[0].expiresAt, NOW + 10);
  assert.equal(seen[1].expiresAt, null);
  assert.equal(seen[1].version, 2);
  // Once unsubscribed, nothing more is delivered.
  const after = seen.length;
  await settle(20);
  assert.equal(seen.length, after);

  const missing = fixture.demoStatusSource({ scenario: { kind: 'missing' }, clock });
  assert.equal(await first(missing), 'missing');
  const foreign = fixture.demoStatusSource({ scenario: null, clock });
  assert.equal(await first(foreign, 'OTHER-REF1'), 'missing');
});

test('a seeded source shows the visitor\'s own send, priced as it was quoted', async () => {
  const seed = {
    service: 'pickup', zoneId: '',
    lines: [{ itemId: '7', qty: 3, selections: { sauce: ['ketchup'] } }],
    createdAt: NOW - 1000,
  };
  const source = fixture.demoStatusSource({ scenario: null, clock, seed, cancelDelayMs: 0 });
  const snap = await first(source);
  assert.equal(snap.service, 'pickup');
  assert.equal(snap.zoneName, null);
  assert.equal(snap.createdAt, NOW - 1000);
  assert.deepEqual(snap.lines.map((l) => [l.itemId, l.qty]), [['7', 3]]);
  assert.equal(snap.subtotalMinor, 6600);
  assert.equal(snap.totalMinor, 6600 + Math.round(6600 * 0.18));
  assert.equal(snap.expiresAt, NOW - 1000 + 30 * 60_000);
});

test('a seeded source never records an event in the future: the send instant is the seed, later stamps are held at the clock', async () => {
  const seed = { service: 'pickup', zoneId: '', lines: [{ itemId: '7', qty: 1, selections: {} }], createdAt: NOW - 1000 };
  // The visitor's own send opens waiting: "waiting" would be +20 s after the
  // send, which has not happened yet.
  const own = await first(fixture.demoStatusSource({ scenario: null, clock, seed, cancelDelayMs: 0 }));
  assert.deepEqual(own.events.map((e) => e.state), ['received', 'waiting']);
  assert.equal(own.events[0].at, NOW - 1000);
  for (const e of own.events) assert.ok(e.at <= NOW, `${e.state} recorded at ${e.at - NOW} ms after now`);
  // And with a state token carried from the review URL: every stamp is a
  // record at or before the clock, ascending, the first one the send itself.
  for (const state of status.REQUEST_STATES) {
    const snap = await first(fixture.demoStatusSource({ scenario: { kind: 'state', state }, clock, seed, cancelDelayMs: 0 }));
    assert.equal(snap.createdAt, NOW - 1000);
    const ats = snap.events.map((e) => e.at);
    assert.deepEqual(ats, [...ats].sort((a, b) => a - b));
    for (const e of snap.events) assert.ok(e.at <= NOW, `${state}/${e.state}: ${e.at - NOW} ms after now`);
    for (const n of status.timelineFor(snap)) if (n.at !== null) assert.ok(n.at <= NOW);
  }
});

test('a seed without a send instant (the duplicate recovery) is aged like a direct load, never stamped at the click', async () => {
  const seed = { service: 'pickup', zoneId: '', lines: [{ itemId: '7', qty: 1, selections: {} }] };
  const snap = await first(fixture.demoStatusSource({ scenario: null, clock, seed, cancelDelayMs: 0 }));
  const direct = await first(fixture.demoStatusSource({ scenario: null, clock, cancelDelayMs: 0 }));
  assert.equal(snap.createdAt, direct.createdAt);
  assert.ok(snap.createdAt < NOW - 60_000, 'aged, not created now');
  assert.equal(snap.expiresAt, direct.expiresAt);
  // The summary is still the visitor's own.
  assert.deepEqual(snap.lines.map((l) => [l.itemId, l.qty]), [['7', 1]]);
});

// ------------------------------------------------------------- the message

test('the message is composed in the restaurant\'s language, names no contact field, and links the configured origin', () => {
  const text = composeMessage({
    contentLocale: 'ar', displayCode: DEMO_DISPLAY_CODE, restaurantName: 'Maps Burger',
    lines: [
      { qty: 1, name: 'Maps كلاسيك', options: 'بريوش · جبنة إضافية · ✕ بصل' },
      { qty: 2, name: 'بطاطا مقلية مقرمشة', options: '' },
    ],
    totalMinor: 14160, service: 'delivery', zoneName: 'كفر مندا',
    statusUrl: absoluteUrl(requestPath('ar', DEMO_REQUEST_REF)),
  });
  const lines = text.split('\n');
  assert.equal(lines.length, 5, 'code+name, two items, total line, status line');
  assert.equal(lines[0], 'طلب جديد #MB-2487 — Maps Burger');
  assert.equal(lines[1], '1× Maps كلاسيك (بريوش · جبنة إضافية · ✕ بصل)');
  assert.equal(lines[2], '2× بطاطا مقلية مقرمشة');
  assert.equal(lines[3], 'الإجمالي: ₪141.60 · توصيل — كفر مندا · نقداً');
  assert.equal(lines[4], `الحالة: ${PUBLIC_ORIGIN}/r/${DEMO_REQUEST_REF}`);
  assert.ok(!text.includes('bizbot.app'), 'the dead literal never appears');
  assert.ok(text.includes('/r/'), 'the status link uses the /r/ route');
  assert.match(PUBLIC_ORIGIN, /^https:\/\/[a-z0-9.-]+$/);
  // Pickup wording, verbatim from the prototype (:768).
  const pickup = composeMessage({
    contentLocale: 'ar', displayCode: DEMO_DISPLAY_CODE, restaurantName: 'X', lines: [],
    totalMinor: 12980, service: 'pickup', zoneName: null, statusUrl: 'https://x/r/y',
  });
  assert.ok(pickup.includes('الإجمالي: ₪129.80 · استلام من المطعم · نقداً'));
  // Delivery without a zone name degrades to the word alone, never to "undefined".
  const noZone = composeMessage({ contentLocale: 'ar', displayCode: '#X', restaurantName: 'X', lines: [], totalMinor: 100, service: 'delivery', zoneName: null, statusUrl: 'u' });
  assert.ok(noZone.includes('· توصيل ·'));
  assert.ok(!noZone.includes('undefined') && !noZone.includes('null'));
});

// ---------------------------------------------------------- dictionary keys

test('every key the received / status screens consume exists in all three dictionaries with matching placeholders', () => {
  const dicts = Object.fromEntries(['ar', 'en', 'he'].map((l) => [l, JSON.parse(readFileSync(new URL(`../messages/storefront.${l}.json`, import.meta.url), 'utf8'))]));
  const consumers = ['ReceivedScreen.tsx', 'StatusScreen.tsx', 'requestParts.tsx', 'RequestRuntime.tsx'].map((f) =>
    readFileSync(new URL(`../src/ui/storefront/request/${f}`, import.meta.url), 'utf8'),
  ).join('\n') + readFileSync(new URL('../src/ui/storefront/checkout/ReviewScreen.tsx', import.meta.url), 'utf8');
  const used = new Set([...consumers.matchAll(/\bm\.([a-zA-Z]+)\b/g)].map((m) => m[1]));
  assert.ok(used.size >= 40, `expected the E consumers to read many keys, found ${used.size}`);
  for (const key of used) {
    for (const [l, d] of Object.entries(dicts)) {
      assert.equal(typeof d[key], 'string', `${l} lacks ${key}`);
      assert.ok(d[key].length > 0, `${l}.${key} is empty`);
    }
    const holes = (t) => [...t.matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(',');
    assert.equal(holes(dicts.ar[key]), holes(dicts.en[key]), `${key}: ar/en placeholders differ`);
    assert.equal(holes(dicts.he[key]), holes(dicts.en[key]), `${key}: he/en placeholders differ`);
  }
  // The E-specific keys are present, and the demo notice is the one authored string.
  for (const key of ['received', 'receivedBody', 'continueWa', 'trackStatus', 'waFallback', 'waWeb', 'copyMsg', 'copied',
    'msgPreview', 'waiting', 'waitingBody', 'expiresIn', 'cancelTitle', 'cancelBody', 'keep', 'yesCancel', 'openChat',
    'orderAgain', 'stReceived', 'stCompleted', 'viewStatus', 'demoNotice']) {
    assert.ok(used.has(key), `${key} is defined but no E consumer reads it`);
  }
  assert.equal(dicts.en.demoNotice, 'Local demo — no order or message is sent.');
  assert.equal(dicts.en.expiresIn, 'Expires in {m} unless confirmed');
  assert.equal(dicts.ar.copied, 'تم النسخ');
});

// ------------------------------------------------------------- contrast

test('every status tone pairs its ink and bed at AA, in both presets', () => {
  for (const [preset, primary, accent] of [['dark', '#123027', '#FF8A2A'], ['light', '#123027', '#C2410C']]) {
    const t = buildTheme(preset, { primary, accent });
    const pairs = [
      ['info', t.info, t.infobg],
      ['warn', t.warn, t.warnbg],
      ['ok', t.ok, t.okbg],
      ['bad', t.badText, t.badbg],
      ['neutral', t.tx, t.sf2],
      ['yes-cancel ink', t.onBad, t.bad],
      ['terminal warn node', t.warnbg, t.warn],
      ['done node', t.okbg, t.ok],
      // The cancel control: the raw danger ink on the page surface (:567).
      ['cancel control', t.bad, t.bg],
    ];
    for (const [name, ink, bed] of pairs) {
      const ratio = contrast(ink, bed);
      assert.ok(ratio >= AA, `${preset} ${name}: ${ink} on ${bed} = ${ratio.toFixed(2)} < ${AA}`);
    }
    // The bad-tone icon disc and terminal node paint a non-text glyph in the
    // bed colour on the danger fill (the prototype's toneCss, :839): the
    // graphics threshold is 3:1.
    const glyph = contrast(t.badbg, t.bad);
    assert.ok(glyph >= 3, `${preset} bad glyph: ${t.badbg} on ${t.bad} = ${glyph.toFixed(2)} < 3`);
  }
});

test('the status body is not dimmed: composited at the prototype .92 the walked danger pair would fall under AA', () => {
  const css = readFileSync(new URL('../src/ui/storefront/request/request.module.css', import.meta.url), 'utf8');
  const body = css.match(/\.cardBody \{[^}]*\}/)?.[0] ?? '';
  assert.ok(body.length > 0, '.cardBody rule present');
  assert.ok(!/opacity\s*:/.test(body), '.cardBody carries no opacity');
  // Why: the AA walk is exact only at alpha 1. Show the .92 composite fails
  // for the shipped dark tenant, so the rule above is load-bearing.
  const t = buildTheme('dark', { primary: '#123027', accent: '#FF8A2A' });
  const composite = (ink, bed, a) => {
    const c = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
    const [i, b] = [c(ink), c(bed)];
    return `#${i.map((v, k) => Math.round(v * a + b[k] * (1 - a)).toString(16).padStart(2, '0')).join('')}`;
  };
  assert.ok(contrast(t.badText, t.badbg) >= AA);
  assert.ok(contrast(composite(t.badText, t.badbg, 0.92), t.badbg) < AA, 'the .92 composite is the failing case');
});
