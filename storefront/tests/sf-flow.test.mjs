// PHASE D - the money, the validation and the submit contract.
//
// These are the rules that are cheap to break silently and expensive to break
// in public: a tax base, a fee that is really "no delivery", a shortfall
// measured against the wrong number, a reference that leaks a phone number.
//
// Every figure below is pinned to something that already exists - the approved
// prototype's own arithmetic, or a number visible in a canonical screenshot -
// so a drifting implementation fails here rather than in review.
import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readFileSync } from 'node:fs';

const { buildQuote, quoteKey } = await import('../src/money/quote.ts');
const { DELIVERY_ZONES, findZone, isServed } = await import('../src/source/zones.ts');
const { MENU_ITEMS, MENU_VERSION, TAX_RATE } = await import('../src/source/menu-fixture.ts');
const { addLine } = await import('../src/cart/cartModel.ts');
const { validateCheckout, FIELD_LIMITS } = await import(
  '../src/ui/storefront/checkout/validation.ts'
);
const { EMPTY_DRAFT } = await import('../src/ui/storefront/checkout/draft.ts');
const submit = await import('../src/ui/storefront/checkout/submit.ts');

const empty = () => ({ schema: 1, slug: 'maps-burger', menuVersion: MENU_VERSION, lines: [] });

/**
 * The cart behind every canonical cart/review screenshot: one Maps Classic
 * with brioche (+500) and extra cheese (+600), and two crispy fries.
 * 5500 + 500 + 600 = 6600, plus 2 x 2200 = 4400, so the subtotal is 11000.
 */
function seeded() {
  let state = addLine(empty(), {
    itemId: '1',
    qty: 1,
    selections: { bun: ['brioche'], extras: ['cheese'] },
    note: '',
  });
  state = addLine(state, { itemId: '7', qty: 2, selections: {}, note: '' });
  return state;
}

const quoteFor = (over = {}) =>
  buildQuote({
    cart: seeded(),
    items: MENU_ITEMS,
    service: 'pickup',
    zone: null,
    taxRate: TAX_RATE,
    ...over,
  });

// ------------------------------------------------------------------- money

test('the canonical PICKUP totals match the approved screenshot exactly', () => {
  // home__ar__light__wide__1280x820 and cart/review pickup: 110 / 19.80 / 129.80
  const q = quoteFor();
  assert.equal(q.subtotalMinor, 11000);
  assert.equal(q.feeApplies, false);
  assert.equal(q.feeMinor, 0);
  assert.equal(q.taxMinor, 1980);
  assert.equal(q.totalMinor, 12980);
});

test('the canonical DELIVERY totals match the approved screenshot exactly', () => {
  // cart__ar__dark__populated and checkout delivery: 110 / 10 / 21.60 / 141.60
  const q = quoteFor({ service: 'delivery', zone: findZone('kafrmanda') });
  assert.equal(q.subtotalMinor, 11000);
  assert.equal(q.feeMinor, 1000);
  assert.equal(q.feeApplies, true);
  // THE TAX BASE IS SUBTOTAL PLUS FEE. round((11000 + 1000) * 0.18) = 2160.
  // Taxing the subtotal alone gives 1980 and under-charges every delivery.
  assert.equal(q.taxMinor, 2160);
  assert.notEqual(q.taxMinor, Math.round(q.subtotalMinor * TAX_RATE));
  assert.equal(q.totalMinor, 14160);
  assert.equal(q.totalMinor, q.subtotalMinor + q.feeMinor + q.taxMinor);
});

test('every amount stays an INTEGER number of minor units', () => {
  for (const zone of [null, ...DELIVERY_ZONES]) {
    for (const service of ['pickup', 'delivery']) {
      const q = buildQuote({
        cart: seeded(),
        items: MENU_ITEMS,
        service,
        zone,
        taxRate: TAX_RATE,
      });
      for (const [name, value] of Object.entries({
        subtotal: q.subtotalMinor,
        fee: q.feeMinor,
        tax: q.taxMinor,
        total: q.totalMinor,
        shortfall: q.shortfallMinor,
      })) {
        assert.ok(Number.isInteger(value), `${service}/${zone?.id ?? 'none'} ${name} is not an integer`);
      }
    }
  }
});

test('a fee of ZERO is free delivery, and a fee of NULL is no delivery', () => {
  // The prototype tests `z.fee` for truthiness, so a served zone offering free
  // delivery would be reported as "we do not deliver here" AND would block
  // checkout. The fixture never exercises it; the type says null means unserved,
  // so the code must test null - and this is the control that proves it does.
  assert.equal(isServed({ id: 'x', name: 'x', feeMinor: 0, minimumMinor: 0 }), true);
  assert.equal(isServed({ id: 'y', name: 'y', feeMinor: null, minimumMinor: null }), false);

  const free = buildQuote({
    cart: seeded(),
    items: MENU_ITEMS,
    service: 'delivery',
    zone: { id: 'free', name: 'Free town', feeMinor: 0, minimumMinor: 0 },
    taxRate: TAX_RATE,
  });
  assert.deepEqual([...free.blockers], []);
  assert.equal(free.orderable, true);
  // It IS a real fee of zero, so the row applies and the tax base is unchanged.
  assert.equal(free.feeApplies, true);
  assert.equal(free.feeMinor, 0);
  assert.equal(free.taxMinor, 1980);
});

test('an unserved town is a BLOCKER, never a fee of zero', () => {
  const q = quoteFor({ service: 'delivery', zone: findZone('nazareth') });
  assert.deepEqual([...q.blockers], ['outside-zone']);
  assert.equal(q.orderable, false);
  // The fee row must not render: `feeApplies` is what every surface gates on.
  assert.equal(q.feeApplies, false);
  assert.equal(q.feeMinor, 0);
});

test('the shortfall is measured against the SUBTOTAL, not the total', () => {
  // The prototype's own worked case: one line at 2200 into sakhnin (min 8000).
  const small = addLine(empty(), { itemId: '7', qty: 1, selections: {}, note: '' });
  const q = buildQuote({
    cart: small,
    items: MENU_ITEMS,
    service: 'delivery',
    zone: findZone('sakhnin'),
    taxRate: TAX_RATE,
  });
  assert.equal(q.subtotalMinor, 2200);
  assert.equal(q.shortfallMinor, 5800);
  assert.deepEqual([...q.blockers], ['below-minimum']);
  // Measuring against the total (2200 + 2000 + tax) would understate it.
  assert.notEqual(q.shortfallMinor, 8000 - q.totalMinor);
});

test('a line whose item left the menu is skipped, never priced from stale data', () => {
  const stale = addLine(empty(), { itemId: 'gone', qty: 3, selections: {}, note: '' });
  const q = buildQuote({
    cart: stale,
    items: MENU_ITEMS,
    service: 'pickup',
    zone: null,
    taxRate: TAX_RATE,
  });
  assert.equal(q.lines.length, 0);
  assert.equal(q.subtotalMinor, 0);
  assert.deepEqual([...q.blockers], ['empty-cart']);
});

test('the quote KEY carries no customer field', () => {
  // A quote key can end up in a cache or a log. It must correlate a result
  // with the inputs that produced it and nothing else.
  const input = {
    cart: seeded(),
    items: MENU_ITEMS,
    service: 'delivery',
    zone: findZone('kafrmanda'),
    taxRate: TAX_RATE,
  };
  const key = quoteKey(input);
  for (const secret of ['SYNTH-NAME', '0521234567', 'Main Street', '12B']) {
    assert.ok(!key.includes(secret), `the key leaked ${secret}`);
  }
  // It DOES change with everything that changes the price...
  assert.notEqual(key, quoteKey({ ...input, service: 'pickup' }));
  assert.notEqual(key, quoteKey({ ...input, zone: findZone('sakhnin') }));
  assert.notEqual(key, quoteKey({ ...input, taxRate: 0.17 }));
  // ...and is stable when nothing that affects the price has.
  assert.equal(key, quoteKey({ ...input }));
});

// -------------------------------------------------------------- validation

const draft = (over = {}) => ({ ...EMPTY_DRAFT, ...over });
const okPickup = draft({ service: 'pickup', fullName: 'SYNTH NAME', phone: '052-123-4567' });

/**
 * What the restaurant offers. `validateCheckout` takes this as a REQUIRED third
 * argument: a default of "both available" is exactly the assumption that let a
 * checkout validate against a service the tenant had switched off.
 */
const BOTH = { pickup: true, delivery: true };
const NEITHER = { pickup: false, delivery: false };

test('the prototype validation rules are transcribed exactly', () => {
  const q = quoteFor();

  assert.equal(validateCheckout(okPickup, q, BOTH).ok, true);
  assert.deepEqual([...validateCheckout(draft({ ...okPickup, fullName: '   ' }), q, BOTH).invalid], [
    'fullName',
  ]);
  assert.deepEqual([...validateCheckout(draft({ ...okPickup, phone: '123' }), q, BOTH).invalid], [
    'phone',
  ]);
  // area, apartment and deliveryNotes are NEVER required - the prototype does
  // not validate them, and inventing a requirement is inventing product.
  const delivery = draft({
    ...okPickup,
    service: 'delivery',
    zoneId: 'kafrmanda',
    street: 'SYNTH ST',
    building: '7',
  });
  const dq = quoteFor({ service: 'delivery', zone: findZone('kafrmanda') });
  assert.equal(validateCheckout(delivery, dq, BOTH).ok, true);
  assert.equal(validateCheckout(draft({ ...delivery, area: '' }), dq, BOTH).ok, true);
  assert.equal(validateCheckout(draft({ ...delivery, apartment: '' }), dq, BOTH).ok, true);
  assert.equal(validateCheckout(draft({ ...delivery, deliveryNotes: '' }), dq, BOTH).ok, true);
  // ...but street and building are.
  assert.deepEqual([...validateCheckout(draft({ ...delivery, street: ' ' }), dq, BOTH).invalid], [
    'street',
  ]);
  assert.deepEqual([...validateCheckout(draft({ ...delivery, building: '' }), dq, BOTH).invalid], [
    'building',
  ]);
});

test('the phone shape is the prototype regex, and nothing looser', () => {
  const q = quoteFor();
  const accepts = ['0521234567', '052-123-4567', '052 123 4567', '02-123-4567', '021234567'];
  const rejects = ['', '52-123-4567', '052-123-456', '052-123-45678', 'abc', '+972521234567',
                   '052--123-4567', ' 052-123-4567 x'];
  for (const phone of accepts) {
    assert.equal(validateCheckout(draft({ ...okPickup, phone }), q, BOTH).ok, true, `rejected ${phone}`);
  }
  for (const phone of rejects) {
    assert.ok(
      validateCheckout(draft({ ...okPickup, phone }), q, BOTH).invalid.includes('phone'),
      `accepted ${phone}`,
    );
  }
  // A leading/trailing space is trimmed before the test, as the prototype does.
  assert.equal(validateCheckout(draft({ ...okPickup, phone: '  052-123-4567  ' }), q, BOTH).ok, true);
});

test('"first invalid" means first in DOM ORDER, not first declared', () => {
  const dq = quoteFor({ service: 'delivery', zone: null });
  const nothing = draft({ service: 'delivery' });
  const v = validateCheckout(nothing, dq, BOTH);
  assert.equal(v.firstInvalid, 'fullName');
  assert.deepEqual([...v.invalid], ['fullName', 'phone', 'zoneId', 'street', 'building']);
  // With the name filled, the phone is next - not the town, which appears
  // later on screen even though it is a "bigger" problem.
  const named = draft({ ...nothing, fullName: 'SYNTH NAME' });
  assert.equal(validateCheckout(named, dq, BOTH).firstInvalid, 'phone');
});

test('a quote blocker is NOT a field error', () => {
  // The chosen town is a real answer; it simply cannot be delivered to. Marking
  // the select invalid would tell the visitor they typed something wrong.
  const dq = quoteFor({ service: 'delivery', zone: findZone('nazareth') });
  const d = draft({
    ...okPickup,
    service: 'delivery',
    zoneId: 'nazareth',
    street: 'SYNTH ST',
    building: '7',
  });
  const v = validateCheckout(d, dq, BOTH);
  assert.deepEqual([...v.invalid], []);
  assert.deepEqual([...v.blockers], ['outside-zone']);
  assert.equal(v.ok, false);
});

test('every draft field is bounded, so a paste cannot create an unbounded draft', () => {
  for (const [field, limit] of Object.entries(FIELD_LIMITS)) {
    assert.ok(Number.isInteger(limit) && limit > 0 && limit <= 140, `${field} bound looks wrong`);
  }
  assert.deepEqual(Object.keys(FIELD_LIMITS).sort(), Object.keys(EMPTY_DRAFT).sort());
});

// ------------------------------------------------------------------ submit

const submissionFor = (over = {}) =>
  submit.buildSubmission(
    'maps-burger',
    MENU_VERSION,
    quoteFor(),
    draft({
      ...okPickup,
      street: 'SYNTH ST',
      building: '7',
      area: 'SYNTH AREA',
      apartment: '3',
      deliveryNotes: 'SYNTH NOTE',
      ...over,
    }),
    'k-test',
  );

test('a reference is derived from ORDER SHAPE only - never from a customer field', () => {
  const a = submissionFor();
  const b = submissionFor({ fullName: 'SOMEONE ELSE', phone: '050-000-0000', street: 'OTHER' });
  const refA = submit.fixtureGateway();
  return Promise.all([refA(a), refA(b)]).then(([ra, rb]) => {
    assert.equal(ra.kind, 'accepted');
    assert.equal(ra.ref, rb.ref, 'the reference moved when only the contact changed');
    assert.ok(submit.isValidRef(ra.ref), `${ra.ref} is not a valid reference`);
    // And nothing recoverable about the visitor is in it.
    for (const secret of ['SYNTH', '0521234567', 'ST', 'NOTE']) {
      assert.ok(!ra.ref.includes(secret), `the reference leaked ${secret}`);
    }
  });
});

test('the reference DOES move when the order does - the control for the rule above', () => {
  const gateway = submit.fixtureGateway();
  const one = submissionFor();
  const other = {
    ...one,
    totalMinor: one.totalMinor + 100,
    lines: [{ itemId: '1', qty: 9 }],
  };
  return Promise.all([gateway(one), gateway(other)]).then(([a, b]) => {
    assert.notEqual(a.ref, b.ref, 'the reference must follow the order');
  });
});

test('the fixture gateway returns each typed outcome and retains nothing', async () => {
  for (const kind of ['accepted', 'duplicate', 'offline', 'server_error', 'rate_limited',
                      'cart_changed']) {
    const result = await submit.fixtureGateway({ outcome: kind })(submissionFor());
    assert.equal(result.kind, kind);
    // No customer field may come back out - not as a reference, not as a field.
    assert.ok(!JSON.stringify(result).includes('SYNTH'), `${kind} echoed a customer field`);
    assert.deepEqual(Object.keys(result).sort(), kind === 'accepted' || kind === 'duplicate'
      ? ['kind', 'ref'] : ['kind']);
  }
});

test('the gateway module holds no state and performs no I/O', () => {
  const src = readFileSync(
    new URL('../src/ui/storefront/checkout/submit.ts', import.meta.url), 'utf8');
  for (const banned of ['fetch(', 'XMLHttpRequest', 'navigator.', 'localStorage',
                        'sessionStorage', 'document.', 'wa.me', 'console.']) {
    assert.ok(!src.includes(banned), `submit.ts must not contain ${banned}`);
  }
  // A module-level mutable binding would leak one visitor's data into another's
  // render on a server, so there is none. Column 0 is what "module level"
  // means here: `let` inside a function body is ordinary local scope.
  assert.ok(!/^(let|var)\s/m.test(src), 'submit.ts must hold no module-level state');
  assert.ok(/^\s+let hash = 0;/m.test(src),
    'NON-VACUITY: the rule must not be passing because the file has no `let` at all');
});

test('a submission carries EXACTLY the declared fields - never a spread', () => {
  const s = submissionFor();
  assert.deepEqual(Object.keys(s).sort(), [
    'contact', 'feeMinor', 'idempotencyKey', 'lines', 'menuVersion', 'service', 'slug',
    'subtotalMinor', 'taxMinor', 'totalMinor', 'zoneId',
  ]);
  assert.deepEqual(Object.keys(s.contact).sort(), [
    'apartment', 'area', 'building', 'deliveryNotes', 'fullName', 'phone', 'street',
  ]);
  // Lines carry ids and quantities only: no name, no price, no image.
  for (const line of s.lines) assert.deepEqual(Object.keys(line).sort(), ['itemId', 'qty']);
});

test('an idempotency key is opaque, unique per mint, and carries nothing typed', () => {
  const keys = new Set();
  for (let i = 0; i < 200; i += 1) keys.add(submit.newIdempotencyKey());
  assert.equal(keys.size, 200, 'keys collided');
  for (const key of keys) {
    assert.match(key, /^k[a-z0-9]{8,24}$/);
    assert.ok(!key.includes('SYNTH'));
  }
});

test('D knows which outcomes Phase E owns a destination for', () => {
  assert.equal(submit.isTerminal({ kind: 'accepted', ref: 'MB-0001' }), true);
  assert.equal(submit.isTerminal({ kind: 'duplicate', ref: 'MB-0001' }), true);
  for (const kind of ['offline', 'server_error', 'rate_limited', 'cart_changed']) {
    assert.equal(submit.isTerminal({ kind }), false);
  }
});

test('nothing in Phase D navigates to the Phase E received route', () => {
  // An enabled control whose only outcome is a 404 is worse than an honest
  // block, so the boundary is asserted rather than trusted.
  const files = [
    'src/ui/storefront/checkout/ReviewScreen.tsx',
    'src/ui/storefront/checkout/FlowRuntime.tsx',
    'src/ui/storefront/checkout/submit.ts',
  ];
  for (const rel of files) {
    const raw = readFileSync(new URL(`../${rel}`, import.meta.url), 'utf8');
    // Comments are stripped first: this rule is about CODE. The files
    // deliberately DISCUSS the boundary in prose, and forbidding the words
    // would push the reasoning out of the source instead of the behaviour.
    const src = raw
      .replace(/\/\*[\s\S]*?\*\//g, ' ')
      .replace(/(^|[^:])\/\/.*/gm, '$1 ');
    assert.ok(!src.includes('requestPath'), `${rel} must not build the /r/:ref route`);
    assert.ok(!/['"`]\/r\//.test(src), `${rel} must not hard-code /r/`);
  }

  // The review screen in particular must not navigate AT ALL on a result: it
  // hands the outcome to an injected observer, which is the seam Phase E
  // replaces with the real navigation.
  const review = readFileSync(
    new URL('../src/ui/storefront/checkout/ReviewScreen.tsx', import.meta.url), 'utf8');
  assert.ok(!review.includes('useRouter'), 'the review screen must not own navigation');
  assert.ok(review.includes('onComplete'), 'the completion observer is the D/E seam');
});

// -------------------------------------------------------------- the zones

test('the delivery zones are the approved fixture, to the agora', () => {
  assert.deepEqual(
    DELIVERY_ZONES.map((z) => [z.id, z.feeMinor, z.minimumMinor]),
    [
      ['kafrmanda', 1000, 4000],
      ['sakhnin', 2000, 8000],
      ['arraba', 2000, 8000],
      ['nazareth', null, null],
    ],
  );
  // The advertised "from" fee is the LOWEST served fee, not a hard-coded one.
  const fees = DELIVERY_ZONES.filter(isServed).map((z) => z.feeMinor);
  assert.equal(Math.min(...fees), 1000);
  assert.equal(findZone('nope'), null);
});

// ------------------------------------------- D1-C2: service availability

test('a service the restaurant has switched off cannot be ordered', () => {
  const q = quoteFor();

  // Both available: the ordinary case, unchanged.
  assert.equal(validateCheckout(okPickup, q, BOTH).ok, true);

  // NEITHER available: there is no answer the visitor could give, so this is a
  // BLOCKER and not a field error - they have typed nothing wrong.
  const none = validateCheckout(okPickup, q, NEITHER);
  assert.equal(none.ok, false);
  assert.deepEqual([...none.blockers], ['service-unavailable']);
  assert.deepEqual([...none.invalid], []);
  assert.equal(none.firstInvalid, null);

  // The SELECTED service is what matters, not whether some service exists.
  const pickupOnly = { pickup: true, delivery: false };
  const deliveryOnly = { pickup: false, delivery: true };
  assert.equal(validateCheckout(okPickup, q, pickupOnly).ok, true);
  assert.ok(
    validateCheckout(okPickup, q, deliveryOnly).blockers.includes('service-unavailable'),
    'pickup selected while only delivery is offered must block',
  );

  // ...and the mirror case, so the rule is not one-directional like the
  // prototype's own (Storefront.dc.html:659 models delivery->pickup only).
  const okDelivery = draft({
    ...okPickup,
    service: 'delivery',
    zoneId: 'kafrmanda',
    street: 'SYNTH ST',
    building: '7',
  });
  const dq = quoteFor({ service: 'delivery', zone: findZone('kafrmanda') });
  assert.equal(validateCheckout(okDelivery, dq, deliveryOnly).ok, true);
  assert.ok(
    validateCheckout(okDelivery, dq, pickupOnly).blockers.includes('service-unavailable'),
    'delivery selected while only pickup is offered must block',
  );
});

test('NEGATIVE CONTROL: availability is REQUIRED, so it cannot be forgotten', () => {
  // The defect this closes was not a wrong answer - it was a question nobody
  // asked. A default of "both available" would let a caller reintroduce it
  // silently, so the parameter has none and omitting it throws.
  assert.throws(
    () => validateCheckout(okPickup, quoteFor()),
    /available|undefined|Cannot read/i,
    'validateCheckout must not accept a missing availability argument',
  );
});

test('every surface that gates progression passes REAL tenant availability', () => {
  // A rule enforced in one of the two places it is read is not enforced: the
  // CTA and the direct-route guard must reach the same verdict.
  const details = readFileSync(
    new URL('../src/ui/storefront/checkout/DetailsScreen.tsx', import.meta.url), 'utf8');
  const runtime = readFileSync(
    new URL('../src/ui/storefront/checkout/FlowRuntime.tsx', import.meta.url), 'utf8');

  for (const [name, src] of [['DetailsScreen', details], ['FlowRuntime', runtime]]) {
    assert.match(src, /validateCheckout\(/, `${name} must use the shared validation`);
    assert.match(
      src,
      /pickup:\s*tenant\.pickupEnabled/,
      `${name} must pass the tenant's real pickup availability`,
    );
    assert.match(
      src,
      /delivery:\s*tenant\.deliveryEnabled/,
      `${name} must pass the tenant's real delivery availability`,
    );
  }
  // And nobody hard-codes a permissive answer.
  for (const [name, src] of [['DetailsScreen', details], ['FlowRuntime', runtime]]) {
    assert.ok(
      !/pickup:\s*true/.test(src) && !/delivery:\s*true/.test(src),
      `${name} must not hard-code an available service`,
    );
  }
});

test('the evidence-only both-off tenant exists and never ships', async () => {
  // C2 needs a rendered proof, and no existing scenario turns BOTH off.
  const { SCENARIOS } = await import('../src/source/scenarios.ts');
  const both = SCENARIOS.find((s) => s.slug === 'demo-no-service');
  assert.ok(both, 'the both-off fixture must exist');
  assert.equal(both.service.pickupEnabled, false);
  assert.equal(both.service.deliveryEnabled, false);

  // It is evidence-only: the shipped slug list must not contain it.
  const { homeSlugs } = await import('../src/source/home.ts');
  assert.ok(
    !homeSlugs().includes('demo-no-service'),
    'a demo tenant must never reach the shipped export',
  );
});
