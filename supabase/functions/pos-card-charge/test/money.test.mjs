// Money (DECISION D-052 point 4, D-056 point 9): integer minor units, the canonical two-decimal
// lexeme by integer division and modulo, the unquoted number token in the outbound BYTES, the
// bounded inbound grammar converted by integer arithmetic - no Number, float or locale anywhere.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { blocked, contextOk, envelope, freshClaim, LIVE_ENV, providerReply, settleAll, startLive, startTest, stray,
  world } from "./fixtures.mjs";
import { AMOUNT_LEXEME, amountToken, lexemeFromMinor, MAX_MINOR, minorFromLexeme, minorFromToken } from "../lib/money.mjs";
import { JsonNumber } from "../lib/json.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

test("the lexeme is exact at every position and boundary", () => {
  const cases = [[1n, "0.01"], [9n, "0.09"], [10n, "0.10"], [99n, "0.99"], [100n, "1.00"], [101n, "1.01"], [1234n, "12.34"],
    [5000n, "50.00"], [123456n, "1234.56"], [MAX_MINOR - 1n, "999999999.98"], [MAX_MINOR, "999999999.99"]];
  for (const [minor, lexeme] of cases) {
    assert.equal(lexemeFromMinor(minor), lexeme);
    assert.equal(amountToken(minor).text, lexeme);
    assert.equal(minorFromLexeme(lexeme), minor);
  }
  for (const bad of [0n, -1n, MAX_MINOR + 1n, 1234, "1234", 12.34, null]) {
    assert.throws(() => lexemeFromMinor(bad), RangeError, String(bad));
  }
  // Round trip over a dense sample: integer arithmetic only, no drift.
  for (let minor = 1n; minor <= 20_000n; minor += 7n) assert.equal(minorFromLexeme(lexemeFromMinor(minor)), minor);
  for (let minor = MAX_MINOR; minor > MAX_MINOR - 2_000n; minor -= 3n) assert.equal(minorFromLexeme(lexemeFromMinor(minor)), minor);
});

test("the canonical lexeme (outbound, and the finish rule) accepts only ^(0|[1-9][0-9]{0,8})\\.[0-9]{2}$", () => {
  assert.equal(String(AMOUNT_LEXEME), String(/^(0|[1-9][0-9]{0,8})\.[0-9]{2}$/));
  for (const ok of ["0.00", "0.01", "12.34", "999999999.99"]) assert.notEqual(minorFromLexeme(ok), null, ok);
  for (const bad of ["12.3", "012.34", "1e3", "-1.00", "1,234.00", " 12.34", "12.34 ", "12.340", "1234", "+1.00", ".50", "1.",
    "1000000000.00", "00.00", "1_000.00", "\u0661.\u0660\u0660", "\uff11.\uff10\uff10", "12.34\n", "NaN", "Infinity", "", null, 12.34]) {
    assert.equal(minorFromLexeme(bad), null, JSON.stringify(bad));
  }
});

test("request amounts are canonical integer tokens within 1 .. 99 999 999 999", () => {
  assert.equal(minorFromToken(new JsonNumber("1")), 1n);
  assert.equal(minorFromToken(new JsonNumber(String(MAX_MINOR))), MAX_MINOR);
  for (const bad of ["0", "-5", String(MAX_MINOR + 1n), "12.0", "1e3", "1E3", "-0"]) {
    assert.equal(minorFromToken(new JsonNumber(bad)), null, bad);
  }
  assert.equal(minorFromToken(1234), null, "a JavaScript number is never accepted");
  assert.throws(() => new JsonNumber("01234"));
});

test("the provider request BYTES carry the exact unquoted token (0.01, 1.00, 12.34, a TEST cap, a LIVE cap, the bound)", async () => {
  const testCap = 5_000; // e.g. a revision's max_test_amount_minor
  const liveCap = 2_500_000; // e.g. a revision's max_live_amount_minor
  for (const [amount, mode, token] of [[1, "test", "0.01"], [100, "test", "1.00"], [1234, "test", "12.34"],
    [testCap, "test", "50.00"], [liveCap, "live", "25000.00"], [99_999_999_999, "live", "999999999.99"]]) {
    const claim = { ...freshClaim(mode), amount_minor: amount };
    const w = world({ env: mode === "live" ? LIVE_ENV : {}, rpc: { card_attempt_context: contextOk(), card_attempt_claim: claim,
      card_attempt_finish: () => ({ ...envelope("approved", { mode }), amount_minor: amount }) },
    provider: { commit: providerReply() } });
    const input = mode === "test" ? startTest({ amount_minor: amount }) : startLive({ amount_minor: amount });
    await w.run(input);
    await w.settle();
    assert.equal(w.calls.provider.length, 1, token);
    const raw = w.calls.provider[0].raw;
    assert.ok(raw.includes(`"syn_amount":${token},`), `${token} in ${raw.slice(0, 120)}`);
    assert.ok(!raw.includes(`"syn_amount":"`), "never a quoted string");
    assert.ok(w.calls.rpc[1].init.body.includes(`"p_amount_minor":${amount},`), "the claim gets the integer token");
    assert.ok(w.calls.rpc[2].init.body.includes(`"p_amount_minor":${amount},`), "the finish gets the claim's integer token");
  }
});

test("an amount the claim does not echo exactly is never sent", async () => {
  const w = world({ rpc: { card_attempt_context: contextOk(), card_attempt_claim: { ...freshClaim(), amount_minor: 1235 } },
    provider: { commit: providerReply() } });
  await w.run(startTest({ amount_minor: 1234 }));
  assert.deepEqual(w.calls.provider, []);
});
