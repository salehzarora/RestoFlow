import { test } from 'node:test';
import assert from 'node:assert/strict';
import { buildEmail, createHandler, isBot, rateLimited, validate } from '../lib/lead.mjs';

const NOW = 1_800_000_000_000;
const good = () => ({
  name: 'Saleh Test',
  business: 'مطعم الزيتونة',
  phone: '+972 50-000-0000',
  email: 'Lead@Example.com',
  type: 'restaurant',
  branches: '2-3',
  notes: 'نريد عرضاً على 3 أجهزة',
  locale: 'ar',
  website: '',
  t0: String(NOW - 10_000),
  page: 'https://bizbot.systems/',
});

function fakeReq(body, extra = {}) {
  return { method: 'POST', headers: { 'x-forwarded-for': extra.ip || '203.0.113.7' }, body, ...extra };
}
function fakeRes() {
  const res = { statusCode: 200, headers: {}, body: undefined };
  res.setHeader = (k, v) => { res.headers[k.toLowerCase()] = v; };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (o) => { res.body = o; return res; };
  res.end = () => res;
  return res;
}

test('validate: accepts a complete lead and normalises the e-mail', () => {
  const { lead, fields } = validate(good());
  assert.deepEqual(fields, []);
  assert.equal(lead.email, 'lead@example.com');
  assert.equal(lead.locale, 'ar');
});

test('validate: reports every failing field by name', () => {
  const { fields } = validate({ ...good(), name: 'A', phone: 'abc', email: 'nope', type: 'x', branches: '99' });
  assert.deepEqual(fields.sort(), ['branches', 'email', 'name', 'phone', 'type']);
});

test('validate: truncates oversized input and defaults an unknown locale to ar', () => {
  const { lead } = validate({ ...good(), notes: 'x'.repeat(5000), locale: 'fr' });
  assert.equal(lead.notes.length, 1500);
  assert.equal(lead.locale, 'ar');
});

test('isBot: honeypot or a too-fast submission is a bot', () => {
  assert.equal(isBot(good(), NOW), false);
  assert.equal(isBot({ ...good(), website: 'http://spam' }, NOW), true);
  assert.equal(isBot({ ...good(), t0: String(NOW - 500) }, NOW), true);
  assert.equal(isBot({ ...good(), t0: 'nope' }, NOW), true);
});

test('rateLimited: allows six per window per ip, then blocks', () => {
  const ip = 'test-' + Math.random();
  for (let i = 0; i < 6; i++) assert.equal(rateLimited(ip, NOW), false, `call ${i}`);
  assert.equal(rateLimited(ip, NOW), true);
  assert.equal(rateLimited(ip, NOW + 11 * 60 * 1000), false, 'window reset');
});

test('buildEmail: RTL body for Arabic, escaped values, subject carries the business', () => {
  const { lead } = validate({ ...good(), business: 'Café <b>x</b>' });
  const mail = buildEmail(lead);
  assert.ok(mail.subject.includes('Café <b>x</b>'));
  assert.ok(mail.html.includes('dir="rtl"'));
  assert.ok(mail.html.includes('&lt;b&gt;x&lt;/b&gt;'));
  assert.ok(!mail.html.includes('<b>x</b>'));
  assert.ok(mail.text.includes('البريد: lead@example.com'));
});

test('handler: sends through Resend with reply_to and the configured recipient', async () => {
  const calls = [];
  const fetchImpl = async (url, init) => {
    calls.push({ url, init });
    return { ok: true, status: 200, json: async () => ({ id: 'em_123' }), text: async () => '' };
  };
  const handler = createHandler({
    env: { RESEND_API_KEY: 'test-key', LEAD_TO: 'owner@example.com', LEAD_FROM: 'BIZBOT <leads@example.com>' },
    fetchImpl,
    now: () => NOW,
  });
  const res = fakeRes();
  await handler(fakeReq(good()), res);
  assert.equal(res.statusCode, 200);
  assert.deepEqual(res.body, { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://api.resend.com/emails');
  assert.equal(calls[0].init.headers.Authorization, 'Bearer test-key');
  const payload = JSON.parse(calls[0].init.body);
  assert.deepEqual(payload.to, ['owner@example.com']);
  assert.equal(payload.from, 'BIZBOT <leads@example.com>');
  assert.equal(payload.reply_to, 'lead@example.com');
  assert.ok(payload.subject.includes('مطعم الزيتونة'));
  assert.equal(res.headers['cache-control'], 'no-store');
});

test('handler: 503 not_configured when no API key is present (nothing is sent)', async () => {
  let called = false;
  const handler = createHandler({ env: {}, fetchImpl: async () => { called = true; }, now: () => NOW });
  const res = fakeRes();
  await handler(fakeReq(good()), res);
  assert.equal(res.statusCode, 503);
  assert.equal(res.body.code, 'not_configured');
  assert.equal(called, false);
});

test('handler: 422 with field names for an invalid lead; 405 for GET; 400 for bad JSON', async () => {
  const handler = createHandler({ env: { RESEND_API_KEY: 'k' }, fetchImpl: async () => { throw new Error('should not send'); }, now: () => NOW });
  let res = fakeRes();
  await handler(fakeReq({ ...good(), email: 'bad' }), res);
  assert.equal(res.statusCode, 422);
  assert.deepEqual(res.body, { ok: false, code: 'invalid', fields: ['email'] });

  res = fakeRes();
  await handler({ method: 'GET', headers: {} }, res);
  assert.equal(res.statusCode, 405);

  res = fakeRes();
  await handler(fakeReq('{not json'), res);
  assert.equal(res.statusCode, 400);
});

test('handler: bots get a silent 200 and nothing is sent', async () => {
  let called = false;
  const handler = createHandler({ env: { RESEND_API_KEY: 'k' }, fetchImpl: async () => { called = true; }, now: () => NOW });
  const res = fakeRes();
  await handler(fakeReq({ ...good(), website: 'spam' }), res);
  assert.equal(res.statusCode, 200);
  assert.equal(called, false);
});

test('handler: 502 send_failed when Resend rejects, without leaking the response body', async () => {
  const handler = createHandler({
    env: { RESEND_API_KEY: 'k' },
    fetchImpl: async () => ({ ok: false, status: 401, text: async () => 'secret detail', json: async () => ({}) }),
    now: () => NOW,
  });
  const res = fakeRes();
  await handler(fakeReq(good(), { ip: '198.51.100.9' }), res);
  assert.equal(res.statusCode, 502);
  assert.deepEqual(res.body, { ok: false, code: 'send_failed' });
});
