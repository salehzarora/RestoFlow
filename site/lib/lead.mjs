// POST /api/lead — demo-request form for bizbot.systems (Vercel Node function).
//
// Validates the submission, drops bots (honeypot + minimum fill time + a small
// per-instance rate limit) and forwards the lead by e-mail through Resend
// (https://resend.com/docs/api-reference/emails/send-email).
//
// Configuration is by ENVIRONMENT VARIABLE NAME only — no value ever lives in
// source (repo guardrail: tools/check_secrets.sh):
//   RESEND_API_KEY   required to send. Absent → 503 {code:"not_configured"};
//                    the page then shows the direct e-mail fallback.
//   LEAD_TO          recipient (default sales@bizbot.systems)
//   LEAD_FROM        verified sender (default "BIZBOT <leads@bizbot.systems>")
//
// No database, no cookies, no third-party scripts. The lead's own e-mail is
// used only as Reply-To so the owner can answer in one click.

const DEFAULT_TO = 'sales@bizbot.systems';
const DEFAULT_FROM = 'BIZBOT <leads@bizbot.systems>';
const RESEND_URL = 'https://api.resend.com/emails';

const TYPES = new Set(['restaurant', 'cafe', 'sweets', 'fastfood', 'cloud', 'other']);
const BRANCHES = new Set(['1', '2-3', '4-10', '10+']);
const LOCALES = new Set(['ar', 'en', 'he']);
const MIN_FILL_MS = 2500;
const RATE = { windowMs: 10 * 60 * 1000, max: 6 };

const LABELS = {
  ar: { subject: 'طلب عرض جديد', name: 'الاسم', business: 'اسم النشاط', phone: 'الهاتف', email: 'البريد', type: 'نوع النشاط', branches: 'عدد الفروع', notes: 'ملاحظات', locale: 'اللغة', page: 'الصفحة' },
  en: { subject: 'New demo request', name: 'Name', business: 'Business', phone: 'Phone', email: 'Email', type: 'Business type', branches: 'Branches', notes: 'Notes', locale: 'Language', page: 'Page' },
  he: { subject: 'בקשת הדגמה חדשה', name: 'שם', business: 'עסק', phone: 'טלפון', email: 'אימייל', type: 'סוג העסק', branches: 'סניפים', notes: 'הערות', locale: 'שפה', page: 'עמוד' },
};

const buckets = new Map(); // ip → { count, reset }

const str = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const EMAIL_RE = /^[^\s@]{1,64}@[^\s@]{1,255}\.[^\s@]{2,}$/;
const PHONE_RE = /^\+?[\d\s().-]{6,25}$/;

export function validate(body) {
  const b = body && typeof body === 'object' ? body : {};
  const lead = {
    name: str(b.name, 80),
    business: str(b.business, 120),
    phone: str(b.phone, 25),
    email: str(b.email, 120).toLowerCase(),
    type: str(b.type, 20),
    branches: str(b.branches, 10),
    notes: str(b.notes, 1500),
    locale: LOCALES.has(b.locale) ? b.locale : 'ar',
    page: str(b.page, 300),
  };
  const fields = [];
  if (lead.name.length < 2) fields.push('name');
  if (lead.business.length < 2) fields.push('business');
  if (!PHONE_RE.test(lead.phone)) fields.push('phone');
  if (!EMAIL_RE.test(lead.email)) fields.push('email');
  if (!TYPES.has(lead.type)) fields.push('type');
  if (!BRANCHES.has(lead.branches)) fields.push('branches');
  return { lead, fields };
}

export function isBot(body, now = Date.now()) {
  if (!body || typeof body !== 'object') return true;
  if (typeof body.website === 'string' && body.website.trim() !== '') return true; // honeypot
  const t0 = Number(body.t0);
  if (!Number.isFinite(t0) || now - t0 < MIN_FILL_MS) return true;
  return false;
}

export function rateLimited(ip, now = Date.now()) {
  const key = ip || 'unknown';
  const b = buckets.get(key);
  if (!b || b.reset < now) {
    buckets.set(key, { count: 1, reset: now + RATE.windowMs });
    if (buckets.size > 5000) buckets.clear();
    return false;
  }
  b.count += 1;
  return b.count > RATE.max;
}

export function buildEmail(lead) {
  const L = LABELS[lead.locale] || LABELS.ar;
  const rtl = lead.locale !== 'en';
  const rows = [
    [L.name, lead.name],
    [L.business, lead.business],
    [L.phone, lead.phone],
    [L.email, lead.email],
    [L.type, lead.type],
    [L.branches, lead.branches],
    [L.notes, lead.notes || '—'],
    [L.locale, lead.locale],
    [L.page, lead.page || '—'],
  ];
  const text = rows.map(([k, v]) => `${k}: ${v}`).join('\n');
  const html = `<!doctype html><html dir="${rtl ? 'rtl' : 'ltr'}"><body style="font-family:Segoe UI,Arial,sans-serif;color:#111827;background:#F4F6F5;padding:24px">
<div style="max-width:560px;margin:auto;background:#fff;border-radius:16px;padding:24px;border:1px solid #E5E7EB">
<h2 style="margin:0 0 4px;color:#1F2937">${esc(L.subject)} — ${esc(lead.business)}</h2>
<p style="margin:0 0 18px;color:#6B7280;font-size:13px">bizbot.systems</p>
<table style="width:100%;border-collapse:collapse;font-size:15px">
${rows
  .map(
    ([k, v]) =>
      `<tr><td style="padding:8px 0;color:#6B7280;width:34%;vertical-align:top;border-top:1px solid #F4F6F5">${esc(k)}</td><td style="padding:8px 0;border-top:1px solid #F4F6F5;white-space:pre-wrap">${esc(v)}</td></tr>`,
  )
  .join('\n')}
</table>
<p style="margin:20px 0 0;font-size:13px;color:#6B7280">Reply to this e-mail to answer the lead directly.</p>
</div></body></html>`;
  return { subject: `${L.subject} — ${lead.business} (${lead.locale})`, text, html };
}

async function sendViaResend(lead, env, fetchImpl) {
  const { subject, text, html } = buildEmail(lead);
  const payload = {
    from: env.LEAD_FROM || DEFAULT_FROM,
    to: [env.LEAD_TO || DEFAULT_TO],
    reply_to: lead.email,
    subject,
    text,
    html,
    tags: [
      { name: 'source', value: 'bizbot-site' },
      { name: 'locale', value: lead.locale },
    ],
  };
  const r = await fetchImpl(RESEND_URL, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify(payload),
  });
  if (!r.ok) {
    const detail = await r.text().catch(() => '');
    throw new Error(`resend ${r.status}: ${detail.slice(0, 200)}`);
  }
  return r.json().catch(() => ({}));
}

function clientIp(req) {
  const h = req.headers || {};
  const xf = h['x-forwarded-for'];
  const first = Array.isArray(xf) ? xf[0] : xf;
  return (first ? String(first).split(',')[0].trim() : '') || h['x-real-ip'] || (req.socket && req.socket.remoteAddress) || '';
}

function parseBody(req) {
  if (req.body && typeof req.body === 'object') return req.body;
  if (typeof req.body === 'string') {
    try {
      return JSON.parse(req.body);
    } catch {
      return null;
    }
  }
  return null;
}

export function createHandler({ env = process.env, fetchImpl = globalThis.fetch, now = Date.now } = {}) {
  return async function handler(req, res) {
    res.setHeader('Cache-Control', 'no-store');
    res.setHeader('X-Content-Type-Options', 'nosniff');
    if (req.method === 'OPTIONS') return res.status(204).end();
    if (req.method !== 'POST') {
      res.setHeader('Allow', 'POST');
      return res.status(405).json({ ok: false, code: 'method_not_allowed' });
    }
    const body = parseBody(req);
    if (!body) return res.status(400).json({ ok: false, code: 'bad_json' });

    // Silent success for bots: nothing to learn, nothing sent.
    if (isBot(body, now())) return res.status(200).json({ ok: true });
    if (rateLimited(clientIp(req), now())) return res.status(429).json({ ok: false, code: 'rate_limited' });

    const { lead, fields } = validate(body);
    if (fields.length) return res.status(422).json({ ok: false, code: 'invalid', fields });

    if (!env.RESEND_API_KEY) return res.status(503).json({ ok: false, code: 'not_configured' });
    try {
      await sendViaResend(lead, env, fetchImpl);
      return res.status(200).json({ ok: true });
    } catch (err) {
      console.error('[lead] send failed:', err && err.message ? err.message : err);
      return res.status(502).json({ ok: false, code: 'send_failed' });
    }
  };
}
