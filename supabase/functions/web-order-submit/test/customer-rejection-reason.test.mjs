import test from "node:test";
import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { createHandler } from "../handler.mjs";
const id = "35600000-0000-4000-8000-000000000001";
const base = { ok: true, request_id: id, status: "rejected", expires_at: "2026-10-21T10:00:00Z",
  totals: { currency_code: "ILS", subtotal_minor: 1000, tax_total_minor: 0, grand_total_minor: 1000 }, replayed: false };
async function project(upstream) {
  const handler = createHandler({ getEnv: (k) => ({ SUPABASE_URL: "https://synthetic.supabase.co",
    SUPABASE_SERVICE_ROLE_KEY: "synthetic" })[k], cryptoImpl: webcrypto,
    fetchImpl: async () => Response.json(upstream) });
  const response = await handler(new Request("https://edge.test/web-order-submit", { method: "POST",
    headers: { "content-type": "application/json" }, body: JSON.stringify({ action: "status", slug: "synthetic",
      request_id: id, status_token: Buffer.alloc(32, 41).toString("base64url") }) }));
  return { status: response.status, body: await response.json() };
}
test("rejected future explicit reason is projected as bounded plain text and no private field", async () => {
  const reason = '<script>alert("x")</script> المنتج غير متوفر';
  const result = await project({ ...base, customer_rejection_reason: reason, rejection_reason: "private", private_notes: "private" });
  assert.equal(result.status, 200); assert.deepEqual(result.body, { ...base, customer_rejection_reason: reason });
});
test("historical/legacy responses without the optional reason stay unchanged", async () => {
  for (const status of ["rejected", "pending", "accepted", "expired"]) {
    const result = await project({ ...base, status, rejection_reason: "never-public-private-reason" });
    assert.equal(result.status, 200); assert.deepEqual(result.body, { ...base, status });
  }
});
test("optional reason is rejected on non-rejected or malformed upstream responses", async () => {
  for (const changes of [{ status: "pending" }, { status: "accepted" }, { status: "expired" },
    { customer_rejection_reason: null }, { customer_rejection_reason: "" }, { customer_rejection_reason: " x" },
    { customer_rejection_reason: "x\n" }, { customer_rejection_reason: "\uD800" }, { customer_rejection_reason: "😀".repeat(241) }]) {
    const result = await project({ ...base, customer_rejection_reason: "Out of stock", ...changes });
    assert.equal(result.status, 502); assert.equal(result.body.error, "status_unavailable");
  }
  assert.equal((await project({ ...base, customer_rejection_reason: "😀".repeat(240) })).status, 200);
});
