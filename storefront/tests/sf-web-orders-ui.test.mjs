import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { SYNTH_IDS, syntheticEnvelope } from './support/envelope.mjs';

const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { decodeStorefrontMenu, EnvelopeError } = await import('../src/source/live/decode.ts');
const { LIVE_ORDERING_RELEASED, ORDER_PROJECT_ORIGIN, orderEndpointOrigin } = await import('../src/source/live/ordering.ts');
const { modifierSelectionValid, unitPriceMinor } = await import('../src/money/pricing.ts');
const { addLine, summarise, optionSummary } = await import('../src/cart/cartModel.ts');
const { orderFromCart, validOrderNotes } = await import('../src/orders/index.ts');
const { EMPTY_DRAFT } = await import('../src/ui/storefront/checkout/draft.ts');
const { validateCheckout } = await import('../src/ui/storefront/checkout/validation.ts');
const { orderMessages, orderStatusCopy, orderSnapshotCopy, orderErrorCopy } = await import('../src/i18n/orders.ts');
const { reviewPath, switchLocalePath } = await import('../src/routes/routes.ts');
const { buildQuote } = await import('../src/money/quote.ts');

const customer = { name: 'Synthetic Guest', phone: '+972501234567' };
const read = (file) => readFileSync(new URL(`../src/${file}`, import.meta.url), 'utf8');
function catalog() {
  const raw = syntheticEnvelope();
  raw.modifiers[1] = { ...raw.modifiers[1], min_select: 1, max_select: 2, allow_quantity: true, max_quantity: 12 };
  raw.modifier_options.push({ id: '04000000-0000-4000-8000-000000000099', modifier_id: SYNTH_IDS.extras, name: 'Synthetic Extra B', price_delta_minor: 200, display_order: 9 });
  return adaptStorefront(decodeStorefrontMenu(raw), ORDER_PROJECT_ORIGIN);
}

test('the independent release gate stays false even when the server admission flag is true', () => {
  assert.equal(LIVE_ORDERING_RELEASED, false);
  const raw = syntheticEnvelope({ service: { ordering_enabled: true } });
  const resolved = adaptStorefront(decodeStorefrontMenu(raw), ORDER_PROJECT_ORIGIN);
  assert.equal(resolved.view.tenant.service.orderingEnabled, false);
  assert.equal(resolved.view.tenant.service.deliveryEnabled, false);
  assert.equal(resolved.orderEndpointOrigin, ORDER_PROJECT_ORIGIN);
  for (const origin of ['http://oqmevrndtivqxgyvcmwy.supabase.co', `${ORDER_PROJECT_ORIGIN}/anything`, `${ORDER_PROJECT_ORIGIN}?token=secret`, `${ORDER_PROJECT_ORIGIN}#secret`, 'https://other.supabase.co', 'https://user:secret@oqmevrndtivqxgyvcmwy.supabase.co']) assert.throws(() => orderEndpointOrigin(origin));
});

test('the old hosted catalog remains browseable; quantity fields are an atomic optional extension', () => {
  const old = syntheticEnvelope();
  for (const modifier of old.modifiers) { delete modifier.allow_quantity; delete modifier.max_quantity; }
  const decoded = decodeStorefrontMenu(old);
  assert.equal(decoded.modifiers[0].allow_quantity, false);
  assert.equal(decoded.modifiers[0].max_quantity, null);
  assert.ok(adaptStorefront(decoded, ORDER_PROJECT_ORIGIN).view.items.length > 0);
  for (const mutate of [
    (m) => { delete m.allow_quantity; },
    (m) => { delete m.max_quantity; },
    (m) => { m.allow_quantity = 'true'; },
    (m) => { m.max_quantity = 0; },
  ]) {
    const bad = syntheticEnvelope(); mutate(bad.modifiers[0]);
    assert.throws(() => decodeStorefrontMenu(bad), EnvelopeError);
  }
});

test('modifier min/max count DISTINCT choices and option quantities retain their own bounds', () => {
  const resolved = catalog();
  const group = resolved.groups.find((g) => g.id === SYNTH_IDS.extras);
  const [a, b] = group.options.map((option) => option.id);
  const minTwo = { ...group, min: 2 };
  assert.equal(modifierSelectionValid(minTwo, [a, a]), false);
  assert.equal(modifierSelectionValid(minTwo, [a, a, b]), true);
  assert.equal(modifierSelectionValid(group, Array(12).fill(a)), true);
  assert.equal(modifierSelectionValid(group, Array(13).fill(a)), false);
  assert.equal(modifierSelectionValid({ ...group, allowQuantity: false }, [a, a]), false);
  assert.equal(modifierSelectionValid({ ...group, max: 0, min: 0 }, [a]), false);
});

test('cart quantities, both distinct line notes, modifier quantities and order notes reach the real adapter without price fields', () => {
  const resolved = catalog();
  const extras = resolved.groups.find((g) => g.id === SYNTH_IDS.extras);
  const [a, b] = extras.options.map((option) => option.id);
  const selections = { [SYNTH_IDS.weight]: [SYNTH_IDS.classic], [SYNTH_IDS.extras]: [...Array(11).fill(a), ...Array(11).fill(b)] };
  let cart = { schema: 1, slug: 'sf-synth-a', menuVersion: resolved.menuVersion, lines: [] };
  cart = addLine(cart, { itemId: SYNTH_IDS.burger, qty: 2, selections, note: '  First\nitem note  ' });
  cart = addLine(cart, { itemId: SYNTH_IDS.burger, qty: 1, selections, note: 'Different note' });
  const order = orderFromCart(cart, customer, 'Order note stays separate');
  assert.equal(order.items.length, 2);
  assert.deepEqual(order.items.map((item) => item.quantity), [2, 1]);
  assert.deepEqual(order.items.map((item) => item.notes), ['First\nitem note', 'Different note']);
  assert.equal(order.notes, 'Order note stays separate');
  assert.deepEqual(order.items[0].modifiers.filter((m) => m.modifier_option_id !== SYNTH_IDS.classic).map((m) => m.quantity), [11, 11]);
  assert.deepEqual(Object.keys(order.items[0]).sort(), ['menu_item_id', 'modifiers', 'notes', 'quantity']);
  const summary = summarise(cart, resolved.view.items, resolved.groups);
  assert.match(optionSummary(summary.lines[0]), /11×/);
  assert.equal(unitPriceMinor(resolved.view.items[0], resolved.groups, selections), 4000 + 11 * 600 + 11 * 200);
});

test('live validation accepts E.164 and Unicode note boundaries, then rejects oversized raw notes without truncation', () => {
  const resolved = catalog();
  let cart = { schema: 1, slug: 'sf-synth-a', menuVersion: resolved.menuVersion, lines: [] };
  cart = addLine(cart, { itemId: SYNTH_IDS.burger, qty: 1, selections: {}, note: '😀'.repeat(140) });
  assert.equal(orderFromCart(cart, customer).items[0].notes, '😀'.repeat(140));
  for (const note of ['😀'.repeat(141), 'x\u0000y', 'x\u0085y', 'x\ud800y']) assert.throws(() => orderFromCart({ ...cart, lines: [{ ...cart.lines[0], note }] }, customer));
  assert.equal(validOrderNotes('😀'.repeat(500)), true);
  assert.equal(validOrderNotes('😀'.repeat(501)), false);
  const quote = buildQuote({ cart, items: resolved.view.items, groups: resolved.groups, service: 'pickup', zone: null, taxRateBp: 1800 });
  const draft = { ...EMPTY_DRAFT, fullName: customer.name, phone: customer.phone, orderNotes: '😀'.repeat(500) };
  const available = { pickup: true, delivery: false };
  assert.equal(validateCheckout(draft, quote, available, true).ok, true);
  for (const phone of ['0501234567', '050-123-4567', '02 234 5678', '+447700900123']) {
    assert.equal(validateCheckout({ ...draft, phone }, quote, available, true).ok, true);
  }
  assert.deepEqual(validateCheckout({ ...draft, phone: '050123456' }, quote, available, true).invalid, ['phone']);
  assert.deepEqual(validateCheckout({ ...draft, orderNotes: '😀'.repeat(501) }, quote, available, true).invalid, ['orderNotes']);
});

test('AR/HE/EN cover all four real states, recovery uncertainty and the same tenant review route', () => {
  const keys = Object.keys(orderMessages('en')).sort();
  for (const locale of ['ar', 'he', 'en']) {
    const m = orderMessages(locale);
    assert.deepEqual(Object.keys(m).sort(), keys);
    assert.ok(m.payAtPickup.length > 0 && m.orderNotes.length > 0 && m.itemNotesLimit.length > 0);
    assert.equal(m.phoneHint, '0521234567');
    assert.ok(m.phoneHelp.includes('0521234567') && m.phoneError.includes('0521234567'));
    for (const state of ['pending', 'accepted', 'rejected', 'expired']) {
      const copy = orderStatusCopy(state, m);
      assert.ok(copy.title.length > 0 && copy.body.length > 0);
    }
    assert.equal(orderSnapshotCopy({ phase: 'unknown' }, m), m.unknown);
    assert.equal(orderSnapshotCopy({ phase: 'not_found', canRetry: false }, m), m.noRecovery);
    const url = reviewPath(locale, 'sf-synth-a');
    assert.equal(switchLocalePath(url, 'en'), '/en/s/sf-synth-a/review');
    assert.ok(!url.includes('?') && !url.includes('token'));
  }
});

test('live checkout uses memory carts and private status; no demo gateway or destructive note sanitization enters its flow', () => {
  const live = read('ui/storefront/checkout/LiveFlowBody.tsx');
  const review = read('ui/storefront/checkout/LiveReviewScreen.tsx');
  const status = read('ui/storefront/request/LiveRequestRuntime.tsx');
  for (const source of [live, review, status]) for (const banned of ['fixtureGateway', 'request-fixture', 'withFlowScenario', 'Math.random', 'localStorage', 'sessionStorage', 'console.']) assert.ok(!source.includes(banned), banned);
  assert.ok(read('ui/storefront/StorefrontRuntime.tsx').includes("groups, source === 'fixture')"));
  assert.ok(read('cart/useCart.ts').includes('persist ? loadCart'));
  assert.ok(read('cart/useCart.ts').includes('if (!persist) clearPersistedCart(slug)'));
  assert.ok(read('ui/storefront/product/ProductSheet.tsx').includes('note: live ? note : sanitizeText'));
  assert.ok(live.includes('controller?.getSnapshot()'), 'recovery guard must read the effect-started controller before redirecting');
  assert.ok(!status.includes('snapshot.displayCode') && !status.includes('timelineFor') && !status.includes('CancelSheet'));
  assert.ok(status.includes('result.totals.grand_total_minor'), 'confirmed totals come from the server');
});

test('storage failures after an uncertain write or confirmed acceptance never claim a request was unsent in AR/HE/EN', () => {
  const unsent = {
    en: /not been sent|was not sent|not sent|unsent/i,
    ar: /لم يتم إرسال|لم يُرسل|لم يرسل/,
    he: /לא נשלחה|לא נשלח/,
  };
  for (const locale of ['ar', 'he', 'en']) {
    const m = orderMessages(locale);
    assert.equal(orderErrorCopy('storage_unavailable', m), m.recoveryUnavailable);
    for (const result of [null, { status: 'accepted' }]) {
      const snapshot = { phase: 'failure', error: 'storage_unavailable', result, canRetry: false, recovered: false };
      assert.equal(orderSnapshotCopy(snapshot, m), m.recoveryUnavailable);
      assert.equal(snapshot.result, result, 'availability copy must preserve the known server result');
      assert.doesNotMatch(orderSnapshotCopy(snapshot, m), unsent[locale]);
    }
    assert.equal(orderSnapshotCopy({ phase: 'unknown', error: 'storage_unavailable', result: null }, m), m.unknown);
    for (const error of ['storage_unavailable', 'configuration_invalid', 'crypto_unavailable']) assert.doesNotMatch(orderErrorCopy(error, m), unsent[locale]);
  }
});

test('bounded client choosers split fixture/live entries while preserving server rendering', () => {
  const server = read('ui/storefront/checkout/FlowScreen.tsx');
  const entry = read('ui/storefront/checkout/FlowEntry.tsx');
  const checkout = read('ui/storefront/checkout/CheckoutEntry.tsx');
  const fixture = read('ui/storefront/checkout/FlowRuntime.tsx');
  const live = read('ui/storefront/checkout/LiveFlowRuntime.tsx');
  const draft = read('ui/storefront/checkout/CheckoutDraftProvider.tsx');
  const provider = read('ui/storefront/checkout/LiveCheckoutProvider.tsx');
  assert.ok(server.includes('<FlowEntry') && !server.includes('import { FlowRuntime') && !server.includes('import { LiveFlowRuntime'));
  assert.ok(server.includes("orderCopy={resolution.source === 'live' ? orderMessages(locale) : undefined}"));
  assert.ok(entry.includes("import('./FlowRuntime')") && entry.includes("import('./LiveFlowRuntime')"));
  assert.ok(checkout.includes("import('./LiveCheckoutProvider')"));
  for (const chooser of [entry, checkout]) {
    assert.ok(chooser.includes("from 'next/dynamic'"));
    assert.ok(chooser.includes('ssr: true') && !chooser.includes('ssr: false'));
  }
  assert.equal([...entry.matchAll(/import\(/g)].length, 2, 'flow chooser has exactly two literal targets');
  assert.equal([...checkout.matchAll(/import\(/g)].length, 1, 'layout chooser has exactly one literal target');
  assert.ok(!fixture.includes('LiveFlowBody') && !fixture.includes('LiveFlowRuntime'));
  assert.ok(live.includes('<LiveFlowBody') && !live.includes('fixtureGateway'));
  assert.ok(!draft.includes('LiveOrderProvider'), 'fixture layout must not download the live transport through its draft provider');
  assert.ok(!read('ui/storefront/checkout/validation.ts').includes("from '@/orders/validation'"), 'shared field validation must not pull in the full order parser');
  assert.ok(!read('ui/storefront/StorefrontRuntime.tsx').includes("from '@/i18n/orders'"), 'shared product copy must not pull checkout/status messages into fixture first load');
  assert.ok(read('ui/storefront/StorefrontRuntime.tsx').includes("from './cart/CartContext'"));
  const context = read('ui/storefront/cart/CartContext.tsx');
  assert.ok(!context.includes('LiveCartAside') && !context.includes('LiveCartDock'), 'checkout context must not preload unused menu dock/aside components');
  for (const file of ['ui/storefront/checkout/LiveFlowBody.tsx', 'ui/storefront/checkout/LiveReviewScreen.tsx', 'ui/storefront/request/LiveRequestRuntime.tsx']) {
    assert.ok(!read(file).includes('orderMessages('), `${file}: the server supplies one locale instead of bundling three dictionaries`);
  }
  assert.ok(provider.includes('<CartMemoryProvider') && provider.includes('<LiveOrderProvider') && provider.includes('<CheckoutDraftProvider'));
  for (const locale of ['(root)', 'ar', 'he', 'en']) {
    const layout = readFileSync(new URL(`../app/${locale}/s/[slug]/layout.tsx`, import.meta.url), 'utf8');
    assert.ok(layout.includes('<CheckoutEntry source={sourceMode()}') && !layout.includes('LiveCheckoutProvider'));
  }
});
