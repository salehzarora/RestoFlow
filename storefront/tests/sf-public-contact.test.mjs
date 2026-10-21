import './support/ts-resolver.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { syntheticEnvelope } from './support/envelope.mjs';

const { restaurantPhoneHref } = await import('../src/source/publicPhone.ts');
const { normalizeCheckoutPhone } = await import('../src/orders/customer.ts');
const { decodeStorefrontMenu } = await import('../src/source/live/decode.ts');
const { adaptStorefront } = await import('../src/source/live/adapter.ts');
const { storefrontMessages } = await import('../src/i18n/storefront.ts');
const { orderMessages } = await import('../src/i18n/orders.ts');
const read = (file) => readFileSync(new URL(`../src/${file}`, import.meta.url), 'utf8');

test('published contact preserves the existing wider public-phone contract without country inference', () => {
  for (const [stored, href] of [
    ['052-123-4567', 'tel:0521234567'], ['050 123 4567', 'tel:0501234567'],
    ['02-234-5678', 'tel:022345678'], ['03 123 4567', 'tel:031234567'],
    ['012-345-6789', 'tel:0123456789'], ['0521234567', 'tel:0521234567'],
    ['052123456', 'tel:052123456'],
    ['+1234567', 'tel:+1234567'], ['+447700900123', 'tel:+447700900123'],
    ['+972521234567', 'tel:+972521234567'], ['+123456789012345', 'tel:+123456789012345'],
  ]) assert.equal(restaurantPhoneHref(stored), href, stored);
  assert.equal(normalizeCheckoutPhone('+1234567'), null, 'public contact is not the customer-input normalizer');
  assert.equal(normalizeCheckoutPhone('03 123 4567'), null, 'preserve legacy public contacts instead of revalidating subscribers');
});

test('invalid or malicious public contact never becomes a telephone URI', () => {
  for (const value of [null, undefined, 521234567, {}, [], '', ' ', '05212345678',
    '052--123-4567', '(052)1234567', '+972 52 1234567', '+01234567', '+123456', '+1234567890123456',
    ' 0521234567', '0521234567 ', '+1234567\n', '0521234567\r', '0521234567\r\n',
    '052\t1234567', '052\u00a01234567', '\u202e0521234567', '٠٥٢١٢٣٤٥٦٧',
    'tel:0521234567', 'javascript:alert(1)', '//example.invalid', '+1234567;ext=2',
    '+1234567?body=private', '+1234567#x', '+1234567%0a', '0521234567 ext 1', '*1234',
    '<a href="tel:1">', '+1234567\u2028', '+1234567\u0000']) {
    assert.equal(restaurantPhoneHref(value), null, String(value));
  }
  for (let cp = 0; cp <= 127; cp += 1) {
    if (cp > 31 && cp !== 127) continue;
    assert.equal(restaurantPhoneHref(`+1234567${String.fromCharCode(cp)}`), null, `control ${cp}`);
  }
});

test('the published tenant source is the only public-contact authority and independent tenants stay separate', () => {
  const resolve = (slug, phone) => adaptStorefront(decodeStorefrontMenu(syntheticEnvelope({ restaurant: { slug, phone } })), 'https://oqmevrndtivqxgyvcmwy.supabase.co').view.tenant;
  const a = resolve('sf-synth-a', '052-123-4567');
  const b = resolve('sf-synth-b', '+447700900123');
  assert.equal(a.phone, '052-123-4567'); assert.equal(restaurantPhoneHref(a.phone), 'tel:0521234567');
  assert.equal(restaurantPhoneHref(b.phone), 'tel:+447700900123');
  assert.equal(restaurantPhoneHref(resolve('sf-synth-empty', null).phone), null);
  assert.equal(restaurantPhoneHref(resolve('sf-synth-invalid', 'javascript:alert(1)').phone), null);
  assert.equal(a.phone, '052-123-4567', 'resolving another tenant never overwrites the first');
});

test('both surfaces share the same user-activated action outside order state and private recovery', () => {
  const contact = read('ui/storefront/RestaurantContact.tsx');
  const helper = read('source/publicPhone.ts');
  const status = read('ui/storefront/request/LiveRequestRuntime.tsx');
  assert.ok(read('ui/storefront/home/HomeParts.tsx').includes('<RestaurantContact publicPhone={tenant.phone} label={m.callRestaurant} className={styles.promoCta} />'));
  assert.ok(read('ui/storefront/checkout/FlowScreen.tsx').includes('publicPhone: tenant.phone'));
  assert.ok(read('ui/storefront/checkout/LiveFlowBody.tsx').includes('publicPhone={tenant.publicPhone}'));
  assert.ok(status.includes('<RestaurantContact publicPhone={publicPhone} label={m.callRestaurant} className={s.chatOutline} />'));
  assert.match(status, /<RestaurantContact[^\n]+\/>\s*\{controller \?/);
  assert.ok(contact.includes('href={href}') && contact.includes('dir="ltr">{publicPhone}'));
  assert.ok(contact.includes('if (href === null) return null'));
  for (const source of [contact, helper]) for (const denied of ['onClick', 'useEffect', 'fetch(', 'window.', 'navigator.', 'localStorage', 'sessionStorage', 'draft', 'customer', 'normalizeCheckoutPhone']) {
    // The helper comment explicitly distinguishes customer input; inspect code only.
    assert.ok(!source.replace(/\/\*[\s\S]*?\*\//g, '').includes(denied), denied);
  }
  assert.match(read('ui/storefront/home/home.module.css'), /\.promoCta\s*\{[^}]*min-height:\s*44px/s);
  assert.match(read('ui/storefront/request/liveRequest.module.css'), /\.chatOutline\s*\{[^}]*height:\s*48px/s);
  for (const locale of ['ar', 'he', 'en']) {
    assert.ok(storefrontMessages(locale).callRestaurant.length > 0);
    assert.equal(orderMessages(locale).phoneError, storefrontMessages(locale).phoneError);
  }
});

test('checkout shows only a conditional phone error while retaining editable values and input accessibility', () => {
  const details = read('ui/storefront/checkout/DetailsScreen.tsx');
  assert.ok(details.includes("aria-describedby={bad('phone') ? ID.phoneError : undefined}"));
  assert.ok(details.includes("{bad('phone') ? (") && details.includes('id={ID.phoneError} role="alert"'));
  assert.ok(details.includes('value={draft.phone}') && details.includes('inputMode="tel"') && details.includes('autoComplete="tel"') && details.includes('dir="ltr"'));
  assert.ok(!details.includes('placeholder=') && !details.includes('phoneHint') && !details.includes('phoneHelp'));
  for (const locale of ['ar', 'he', 'en']) {
    const messages = orderMessages(locale);
    assert.ok(!('phoneHint' in messages) && !('phoneHelp' in messages));
    assert.ok(!/\d/.test(messages.phoneError), 'conditional error contains no example number');
  }
});
