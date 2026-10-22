export const SLUG = 'test-kitchen';
export const NOW = Date.parse('2026-10-14T10:00:00Z');
export const REQUEST_ID = '11111111-1111-4111-8111-111111111111';
export const ITEM_ID = '22222222-2222-4222-8222-222222222222';
export const OPTION_ID = '33333333-3333-4333-8333-333333333333';
export const TOKEN = Buffer.alloc(32, 1).toString('base64url');
export const identity = () => ({ slug: SLUG, request_id: REQUEST_ID, status_token: TOKEN });
export const record = (over = {}) => ({ ...identity(), created_at: NOW, expires_at: NOW + 86_400_000, ...over });
export const order = (over = {}) => ({ order_type: 'takeaway', customer: { name: 'Test Customer', phone: '+972501234567' }, items: [{ menu_item_id: ITEM_ID, quantity: 2, modifiers: [{ modifier_option_id: OPTION_ID, quantity: 3 }], notes: 'No onion' }], notes: 'Pickup after 12', ...over });
export const result = (status = 'pending', over = {}) => ({ ok: true, request_id: REQUEST_ID, status, expires_at: new Date(NOW + 3_600_000).toISOString(), totals: { currency_code: 'ILS', subtotal_minor: 1000, tax_total_minor: 180, grand_total_minor: 1180 }, replayed: false, ...over });
// Negotiation-capable synthetic backend. Submit ignores this harmless response
// header; explicit missing/incorrect acknowledgments are tested separately.
export const response = (body, status = 200, headers = {}) => new Response(typeof body === 'string' ? body : JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-BIZBOT-Order-Response-Version': '2', ...headers } });
export function memoryStorage(initial = []) {
  const map = new Map(initial);
  return { map, getItem: (key) => map.get(key) ?? null, setItem: (key, value) => { map.set(key, value); }, removeItem: (key) => { map.delete(key); } };
}
export const testCrypto = () => ({ randomUUID: () => REQUEST_ID, getRandomValues: (bytes) => { bytes.fill(1); return bytes; } });
