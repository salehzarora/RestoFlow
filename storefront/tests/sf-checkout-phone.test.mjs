import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ITEM_ID, OPTION_ID, SLUG, REQUEST_ID, memoryStorage, testCrypto, result, response } from './sf-web-orders-fixtures.mjs';

const { normalizeCheckoutPhone, validCustomerPhone } = await import('../src/orders/customer.ts');
const { orderFromCart, normalizeWebOrder, createOrderController, WEB_ORDER_ORIGIN, WebOrderValidationError } = await import('../src/orders/index.ts');
const { NOW } = await import('./sf-web-orders-fixtures.mjs');

const accepted = [
  ['0521234567', '+972521234567'],
  ['052-123-4567', '+972521234567'],
  ['050 123 4567', '+972501234567'],
  [' 0521234567 ', '+972521234567'],
  ['0592345678', '+972592345678'],
  ['02-234-5678', '+97222345678'],
  ['03 234 5678', '+97232345678'],
  ['042345678', '+97242345678'],
  ['082345678', '+97282345678'],
  ['092345678', '+97292345678'],
  ['072-234-5678', '+972722345678'],
  ['0792345678', '+972792345678'],
  ['+972521234567', '+972521234567'],
  ['+97222345678', '+97222345678'],
  ['+9721599123456', '+9721599123456'],
  ['+972718123456', '+972718123456'],
  ['+447700900123', '+447700900123'],
  ['+33123456789', '+33123456789'],
  ['+12345678', '+12345678'],
  ['+123456789012345', '+123456789012345'],
];
const rejected = [
  null, undefined, 521234567, {}, '', ' ', '052123456', '05212345678',
  '1234567', '521234567', '972521234567', '00972521234567', '00521234567',
  '012345678', '0621234567', '0702345678', '0712345678', '03234567',
  '1800123456', '*1234', '052--123-4567', '052  123 4567', '-0521234567',
  '0521234567-', '(052)1234567', '052.123.4567', '052/123/4567', '052ABC4567',
  '0521234567 ext 1', '052\t1234567', '\n0521234567', '0521234567\r',
  '052\u00a01234567', '\u202e0521234567', '٠٥٢١٢٣٤٥٦٧',
  '++972521234567', '+97252', '+972-52-1234567', '+447700900123\n',
  '+012345678', '+1234567', '+1234567890123456',
];

test('checkout phone normalizes complete Israeli mobile/landline shapes and preserves international E.164', () => {
  for (const [input, expected] of accepted) {
    assert.equal(normalizeCheckoutPhone(input), expected, input);
    assert.equal(validCustomerPhone(expected), true);
    assert.equal(normalizeCheckoutPhone(expected), expected, 'canonicalization is stable');
  }
});

test('checkout phone rejects malformed, incomplete, ambiguous and unsupported input without guessing digits', () => {
  for (const input of rejected) assert.equal(normalizeCheckoutPhone(input), null, String(input));
});

const cart = () => ({ schema: 1, slug: SLUG, menuVersion: 'v1', lines: [
  { lineId: 'one', itemId: ITEM_ID, qty: 2, selections: { extras: [OPTION_ID, OPTION_ID] }, note: 'Saved item note' },
] });

test('cart payload canonicalizes a copy before freezing; local display, quantities, modifiers and notes remain intact', () => {
  for (const [input, expected] of accepted) {
    const customer = Object.freeze({ name: 'Synthetic Phone Guest', phone: input });
    const outgoing = orderFromCart(cart(), customer, 'Saved order note');
    assert.equal(customer.phone, input, 'editable checkout/review input is not rewritten');
    assert.equal(outgoing.customer.phone, expected);
    assert.equal(outgoing.items[0].quantity, 2);
    assert.deepEqual(outgoing.items[0].modifiers, [{ modifier_option_id: OPTION_ID, quantity: 2 }]);
    assert.equal(outgoing.items[0].notes, 'Saved item note');
    assert.equal(outgoing.notes, 'Saved order note');
    assert.ok(Object.isFrozen(outgoing) && Object.isFrozen(outgoing.customer));
    assert.deepEqual(normalizeWebOrder(outgoing), outgoing);
  }
  const raw = { order_type: 'takeaway', customer: { name: 'Synthetic Guest', phone: '0521234567' }, items: [{ menu_item_id: ITEM_ID, quantity: 1 }] };
  assert.throws(() => normalizeWebOrder(raw), WebOrderValidationError, 'API parsing still requires E.164');
});

test('invalid checkout phones fail before immutable identity, storage or transport work', () => {
  let identities = 0; let sends = 0;
  const crypto = testCrypto();
  const storage = memoryStorage();
  const controller = createOrderController({ slug: SLUG, origin: WEB_ORDER_ORIGIN, now: () => NOW, storage,
    cryptoImpl: { ...crypto, randomUUID: () => { identities++; return crypto.randomUUID(); } },
    fetchImpl: async () => { sends++; return response(result()); },
  });
  for (const phone of rejected.filter((value) => typeof value === 'string')) {
    assert.throws(() => controller.submit(orderFromCart(cart(), { name: 'Synthetic Guest', phone })), WebOrderValidationError);
  }
  assert.equal(identities, 0); assert.equal(sends, 0); assert.equal(storage.map.size, 0);
});

test('uncertain local-phone submissions retry the byte-identical canonical body without another identity or phone storage', async () => {
  const customer = { name: 'Synthetic Phone Guest', phone: '052-123-4567' };
  const sent = []; let writes = 0; let identities = 0;
  const crypto = testCrypto(); const storage = memoryStorage();
  const controller = createOrderController({ slug: SLUG, origin: WEB_ORDER_ORIGIN, now: () => NOW, storage,
    cryptoImpl: { ...crypto, randomUUID: () => { identities++; return crypto.randomUUID(); } },
    fetchImpl: async (_url, init) => {
      const body = JSON.parse(init.body);
      if (body.action === 'status') return response({ ok: false, error: 'not_found' }, 404);
      sent.push(init.body); writes++;
      return writes === 1 ? response({ ok: false, error: 'submission_outcome_unknown', request_id: REQUEST_ID, uncertain: true }, 503) : response(result());
    },
  });
  const first = await controller.submit(orderFromCart(cart(), customer));
  assert.equal(first.canRetry, true); assert.equal(identities, 1);
  customer.phone = '0501234567';
  await controller.retry();
  assert.equal(sent.length, 2); assert.equal(sent[0], sent[1]); assert.equal(identities, 1);
  assert.equal(JSON.parse(sent[0]).order.customer.phone, '+972521234567');
  await controller.submit(orderFromCart(cart(), customer));
  assert.equal(sent.length, 2, 'a second click cannot create another submitted identity');
  for (const value of storage.map.values()) {
    for (const privateValue of ['Synthetic Phone Guest', '052-123-4567', '+972521234567', customer.phone]) assert.ok(!value.includes(privateValue));
  }
});
