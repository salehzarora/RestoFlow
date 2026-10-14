import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ITEM_ID, OPTION_ID, SLUG, order } from './sf-web-orders-fixtures.mjs';
const { normalizeWebOrder, orderFromCart, validCustomerName, validCustomerPhone, validOrderNotes, WebOrderValidationError } = await import('../src/orders/index.ts');

test('pickup payload preserves line quantities, modifier quantities and both note levels', () => {
  const value = normalizeWebOrder(order());
  assert.equal(value.items[0].quantity, 2);
  assert.equal(value.items[0].modifiers[0].quantity, 3);
  assert.equal(value.items[0].notes, 'No onion');
  assert.equal(value.notes, 'Pickup after 12');
  assert.ok(Object.isFrozen(value) && Object.isFrozen(value.customer) && Object.isFrozen(value.items[0].modifiers[0]));
});
test('cart mapping counts repeated selected IDs and preserves distinct lines and individual notes', () => {
  const lines = [{ lineId: 'one', itemId: ITEM_ID, qty: 2, selections: { extras: [OPTION_ID, OPTION_ID] }, note: ' No onion ' }, { lineId: 'two', itemId: ITEM_ID, qty: 1, selections: { extras: [OPTION_ID] }, note: 'Extra onion' }];
  const value = orderFromCart({ schema: 1, slug: SLUG, menuVersion: 'v1', lines }, { name: '  Test  ', phone: '+972501234567' }, 'Order note');
  assert.equal(value.customer.name, 'Test');
  assert.deepEqual(value.items.map((item) => [item.quantity, item.modifiers[0].quantity, item.notes]), [[2, 2, 'No onion'], [1, 1, 'Extra onion']]);
  lines[0].selections.extras.push(OPTION_ID);
  assert.equal(value.items[0].modifiers[0].quantity, 2, 'frozen payload is independent of the cart');
});
test('note-free legacy requests retain the original normalized shape', () => {
  const value = normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity: 1 }] }));
  assert.deepEqual(value.items, [{ menu_item_id: ITEM_ID, quantity: 1, modifiers: [] }]);
  assert.equal(normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity: 1, notes: ' \n ' }] })).items[0].notes, undefined);
});
test('Unicode note limits apply before item trim and preserve internal line breaks', () => {
  const withNote = (notes) => order({ items: [{ menu_item_id: ITEM_ID, quantity: 1, notes }] });
  assert.equal(normalizeWebOrder(withNote('🍔'.repeat(140))).items[0].notes, '🍔'.repeat(140));
  assert.equal(normalizeWebOrder(withNote(' A\n B ')).items[0].notes, 'A\n B');
  for (const notes of ['🍔'.repeat(141), ' '.repeat(141), 'A\tB', 'A\rB', '\u0085', '\u007f', '\ud800']) assert.throws(() => normalizeWebOrder(withNote(notes)), WebOrderValidationError);
  assert.equal(normalizeWebOrder(order({ notes: '🍔'.repeat(500) })).notes, '🍔'.repeat(500));
  assert.throws(() => normalizeWebOrder(order({ notes: '🍔'.repeat(501) })), WebOrderValidationError);
});
test('customer validation requires bounded Unicode names and E.164-compatible phone', () => {
  assert.ok(validCustomerName(' אבג ')); assert.ok(validCustomerName('محمد')); assert.ok(validCustomerName('🍔'.repeat(80)));
  for (const value of ['', '  ', 'x'.repeat(81), 'A\nB', '\ud800']) assert.equal(validCustomerName(value), false);
  for (const value of ['+972501234567', '+12345678', '+123456789012345']) assert.ok(validCustomerPhone(value));
  for (const value of ['0501234567', '+012345678', '+1234567', '+1234567890123456', ' +972501234567', '+972-50-1234567']) assert.equal(validCustomerPhone(value), false);
  assert.equal(validOrderNotes('A\nB'), true); assert.equal(validOrderNotes('A\tB'), false);
});
test('no client money, tenant IDs, delivery data or hidden nested fields enter the order', () => {
  for (const extra of [{ total_minor: 1 }, { currency_code: 'ILS' }, { branch_id: ITEM_ID }, { tenant_id: ITEM_ID }, { order_type: 'delivery' }]) assert.throws(() => normalizeWebOrder(order(extra)), WebOrderValidationError);
  assert.throws(() => normalizeWebOrder(order({ customer: { name: 'A', phone: '+972501234567', password: 'x' } })), WebOrderValidationError);
  assert.throws(() => normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity: 1, price_minor: 1 }] })), WebOrderValidationError);
  assert.throws(() => normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity: 1, modifiers: [{ modifier_option_id: OPTION_ID, quantity: 1, price_minor: 1 }] }] })), WebOrderValidationError);
});
test('line, item unit and modifier bounds reject rather than truncate or clamp', () => {
  for (const quantity of [0, 21, 1.5, '2', NaN]) {
    assert.throws(() => normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity }] })), WebOrderValidationError);
    assert.throws(() => normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity: 1, modifiers: [{ modifier_option_id: OPTION_ID, quantity }] }] })), WebOrderValidationError);
  }
  for (const items of [[], Array.from({ length: 21 }, () => ({ menu_item_id: ITEM_ID, quantity: 1 })), Array.from({ length: 3 }, () => ({ menu_item_id: ITEM_ID, quantity: 20 }))]) assert.throws(() => normalizeWebOrder(order({ items })), WebOrderValidationError);
  assert.throws(() => normalizeWebOrder(order({ items: [{ menu_item_id: ITEM_ID, quantity: 1, modifiers: [{ modifier_option_id: OPTION_ID, quantity: 1 }, { modifier_option_id: OPTION_ID.toUpperCase(), quantity: 2 }] }] })), WebOrderValidationError);
  assert.throws(() => normalizeWebOrder(order({ items: [{ menu_item_id: 'fixture-id', quantity: 1 }] })), WebOrderValidationError);
});
test('malformed cart selections never disappear silently from checkout', () => {
  const cart = (selections) => ({ schema: 1, slug: SLUG, menuVersion: 'v1', lines: [{ itemId: ITEM_ID, qty: 1, selections, note: '' }] });
  for (const selections of [null, [], { group: 'id' }, { group: [1] }, { group: Array(21).fill(OPTION_ID) }]) assert.throws(() => orderFromCart(cart(selections), order().customer), WebOrderValidationError);
});
