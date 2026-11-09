// `free_order` (API_CONTRACT section 4.55.6; DECISION D-058 point 9): the role is proven before any
// attempt lookup; only a manager+ proof opens the service-role client; the evidence rules are SQL's.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { ATTEMPT, blocked, CALLER, contextOk, DEVICE, envelope, freeInput, PIN, settleAll, stray, TOKEN, world } from "./fixtures.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const freed = envelope("unknown", { mode: "live", classification: "freed" });

test("a cashier is refused a generic permission_denied before any attempt lookup or service call", async () => {
  const w = world({ rpc: { card_attempt_context: contextOk({ role: "cashier" }), card_attempt_free_order: freed } });
  const out = await w.run(freeInput());
  assert.deepEqual(out.body, { ok: false, error: "permission_denied" });
  assert.deepEqual(w.rpcNames(), ["card_attempt_context"]);
  assert.equal(w.calls.rpc[0].body.p_attempt_id, null, "the role proof looks up no attempt");
  assert.deepEqual(w.calls.provider, []);
});

test("a manager+ proof opens the service-role client for exactly one free_order call with the same request's binding", async () => {
  for (const role of ["manager", "restaurant_owner", "org_owner"]) {
    const w = world({ rpc: { card_attempt_context: contextOk({ role }), card_attempt_free_order: freed } });
    const out = await w.run(freeInput());
    assert.equal(out.status, 200);
    assert.deepEqual(out.body, freed);
    assert.deepEqual(w.rpcNames(), ["card_attempt_context", "card_attempt_free_order"]);
    assert.deepEqual(w.calls.rpc[1].body, { p_pin_session_id: PIN, p_device_id: DEVICE, p_device_session_token: TOKEN,
      p_attempt_id: ATTEMPT, p_reason: "Provider report shows no charge", p_confirmation_source: "provider_report",
      p_confirmation_reference: "RPT-2026-10-27/syn", p_caller_auth_user_id: CALLER });
    assert.deepEqual(w.calls.provider, [], "free_order never calls the provider");
  }
});

test("the evidence-bound refusals of the body are returned unchanged", async () => {
  for (const answer of [
    { ok: false, error: "precondition_failed", detail: "confirmation_required", attempt_id: ATTEMPT, attempt_state: "unknown" },
    { ok: false, error: "precondition_failed", detail: "charge_may_exist", attempt_id: ATTEMPT, attempt_state: "unknown" },
    { ok: false, error: "precondition_failed", detail: "attempt_not_freeable", attempt_id: ATTEMPT, attempt_state: "approved" },
    { ok: false, error: "precondition_failed", detail: "out_of_contract" },
    { ok: false, error: "attempt_not_found" },
    { ok: false, error: "conflict" },
    { ok: false, error: "permission_denied" },
  ]) {
    const w = world({ rpc: { card_attempt_context: contextOk({ role: "manager" }), card_attempt_free_order: answer } });
    assert.deepEqual((await w.run(freeInput())).body, answer);
  }
  const lapsed = world({ rpc: { card_attempt_context: contextOk({ role: "manager" }),
    card_attempt_free_order: { ok: false, error: "invalid_session" } } });
  assert.equal((await lapsed.run(freeInput())).status, 401);
});

test("an absent reason or reference passes the boundary; the body answers confirmation_required", async () => {
  const w = world({ rpc: { card_attempt_context: contextOk({ role: "manager" }),
    card_attempt_free_order: { ok: false, error: "precondition_failed", detail: "confirmation_required",
      attempt_id: ATTEMPT, attempt_state: "unknown" } } });
  const out = await w.run(freeInput({ reason: "   ", confirmation_reference: "", confirmation_source: "manager_says" }));
  assert.equal(out.body.detail, "confirmation_required");
  assert.equal(w.calls.rpc[1].body.p_reason, "   ");
});

test("a refused proof makes no service call", async () => {
  for (const error of ["invalid_session", "permission_denied", "invalid_request"]) {
    const w = world({ rpc: { card_attempt_context: { ok: false, error }, card_attempt_free_order: freed } });
    await w.run(freeInput());
    assert.deepEqual(w.rpcNames(), ["card_attempt_context"]);
  }
});
