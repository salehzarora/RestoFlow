// Static guards of the function source and its configuration (execution packet section 11):
// the environment allowlist, the service-role key confined to the ledger module, no logging, no
// remote import, hard-coded URL or other network channel, the closed RPC set with no payment
// writer, float-free money, the pinned timing constants, no vendor profile shipped (gate W1), the
// config.toml block and the CI step, synthetic test hosts only, and no secret in any answer.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { readdir, readFile } from "node:fs/promises";
import { adapterRead, ANON, blocked, contextAttempt, contextOk, envelope, freeInput, freshClaim, JWT, providerReply,
  releaseInput, SERVICE, settleAll, startTest, statusInput, stray, TOKEN, world } from "./fixtures.mjs";
import { AUTO_POLL_CAP, LIMITS, POLL_MIN_INTERVAL_MS, TIMING } from "../lib/constants.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const FUNCTION_DIR = new URL("../", import.meta.url);
const REPO = new URL("../../../../", import.meta.url);
const read = async (url) => (await readFile(url, "utf8")).replace(/\r\n/g, "\n");

async function files(dir, prefix = "") {
  const out = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const name = `${prefix}${entry.name}`;
    if (entry.isDirectory()) out.push(...await files(new URL(`${entry.name}/`, dir), `${name}/`));
    else out.push(name);
  }
  return out;
}

async function sources() {
  const names = (await files(FUNCTION_DIR)).filter((name) => !name.startsWith("test/") && /\.(mjs|ts)$/.test(name));
  return Promise.all(names.map(async (name) => ({ name, text: await read(new URL(name, FUNCTION_DIR)) })));
}
// Source without full-line comments and block comments (prose may name things).
const code = (text) => text.split("\n").filter((line) => !/^\s*\/\//.test(line)).join("\n").replace(/\/\*[\s\S]*?\*\//g, "");

test("the function's files are exactly the reviewed set", async () => {
  assert.deepEqual((await sources()).map((source) => source.name).sort(), ["handler.mjs", "index.ts", "lib/caller.mjs",
    "lib/config.mjs", "lib/constants.mjs", "lib/envelope.mjs", "lib/http.mjs", "lib/json.mjs", "lib/ledger.mjs", "lib/money.mjs",
    "lib/provider/engine.mjs", "lib/provider/zcredit_profile.mjs", "lib/request.mjs", "lib/text_policy.mjs",
    "lib/text_policy_tables.mjs", "lib/time.mjs"]);
});

test("Deno is used only by index.ts: one env accessor, Deno.serve and EdgeRuntime.waitUntil; no vendor profile ships", async () => {
  for (const { name, text } of await sources()) {
    const body = code(text);
    const uses = [...body.matchAll(/\bDeno\b(?!:)|\bEdgeRuntime\b/g)].length;
    if (name !== "index.ts") assert.equal(uses, 0, `${name} uses the runtime directly`);
    assert.ok(!/process\.env|toObject\(|Deno\.env\.get\(['"]/.test(body), `${name} reads the environment directly`);
  }
  const index = code((await sources()).find((source) => source.name === "index.ts").text);
  assert.equal([...index.matchAll(/Deno\.env\.get\(/g)].length, 1);
  assert.match(index, /getEnv: \(name: string\) => Deno\.env\.get\(name\),/);
  assert.equal([...index.matchAll(/Deno\.serve\(/g)].length, 1);
  assert.match(index, /waitUntil: \(task: Promise<unknown>\) => EdgeRuntime\.waitUntil\(task\),/);
  assert.match(index, /providerProfile: null,/, "gate W1: no vendor wire profile is wired in");
  assert.ok(!/timing/.test(index), "production runs on the pinned constants");
});

test("exactly five environment names; the service-role key name lives in lib/ledger.mjs only", async () => {
  const names = new Set();
  for (const { name, text } of await sources()) {
    for (const match of code(text).matchAll(/["'`]([A-Z][A-Z0-9_]{5,})["'`]/g)) {
      if (/^(SUPABASE|POS_CARD|SB_)/.test(match[1])) names.add(`${match[1]}@${name}`);
    }
    for (const forbidden of ["SUPABASE_DB_URL", "SUPABASE_SECRET_KEYS", "SUPABASE_JWKS", "SUPABASE_PUBLISHABLE_KEYS", "service_role"]) {
      assert.ok(!code(text).includes(forbidden), `${name} names ${forbidden}`);
    }
  }
  assert.deepEqual([...names].sort(), ["POS_CARD_PAYMENTS_ENABLED@lib/config.mjs", "POS_CARD_PROVIDER_CONFIG@lib/config.mjs",
    "SUPABASE_ANON_KEY@lib/config.mjs", "SUPABASE_SERVICE_ROLE_KEY@lib/ledger.mjs", "SUPABASE_URL@lib/config.mjs"]);
  // The platform accessor reaches two wrappers only: the four-name allowlist and the ledger's opaque key source.
  const all = await sources();
  const body = (file) => code(all.find((source) => source.name === file).text);
  for (const { name, text } of all) {
    const uses = [...code(text).matchAll(/\bgetEnv\b/g)].length;
    if (!["index.ts", "handler.mjs", "lib/config.mjs", "lib/ledger.mjs"].includes(name)) assert.equal(uses, 0, `${name} sees getEnv`);
    if (name !== "lib/ledger.mjs") {
      assert.ok(!/\bSERVICE_KEY\b|\bSOURCES\.(?:get|set)\b/.test(code(text)), `${name} names the key source internals`);
    }
    if (!["handler.mjs", "lib/ledger.mjs"].includes(name)) assert.ok(!/serviceKeySource/.test(code(text)), `${name} opens a key source`);
  }
  const handler = body("handler.mjs");
  assert.equal([...handler.matchAll(/\bgetEnv\b/g)].length, 3, "the option, the allowlist and the key source");
  assert.match(handler, /const env = allowlistedEnv\(getEnv\);\n {2}const keySource = serviceKeySource\(getEnv\);/);
  const ledger = body("lib/ledger.mjs");
  assert.equal([...ledger.matchAll(/getEnv\(/g)].length, 1);
  assert.match(ledger, /SOURCES\.set\(source, \(\) => getEnv\(SERVICE_KEY\)\);/, "the source reads exactly one name");
  assert.match(ledger, /const SOURCES = new WeakMap\(\);/);
  assert.ok(!/export\s+(?:const|let|var)\s+(?:SERVICE_KEY|SOURCES)/.test(ledger), "the key name and the sources stay private");
  assert.ok(!all.some((source) => /LEDGER_ENV_NAMES/.test(source.text)));
  assert.equal([...body("lib/config.mjs").matchAll(/getEnv\(name\)/g)].length, 1, "the allowlist reads only a checked name");
});

test("the timing constants and byte caps are pinned and fit the start deadline and the 150 s platform limits", async () => {
  assert.deepEqual({ ...TIMING }, { requestMs: 5_000, rpcMs: 5_000, startWindowMs: 3_000, commitBudgetMs: 100_000,
    lookupMs: 6_000, releaseMs: 6_000 });
  assert.ok(Object.isFrozen(TIMING));
  assert.deepEqual({ ...LIMITS }, { requestBytes: 16_384, rpcAnswerBytes: 65_536, providerReplyBytes: 262_144 });
  assert.ok(Object.isFrozen(LIMITS));
  assert.equal(AUTO_POLL_CAP, 90);
  assert.equal(POLL_MIN_INTERVAL_MS, 3_000);
  // 001D stamps start_deadline_at at the claim's INSERT, up to one RPC deadline before its answer: the claim's
  // tail, the commit budget and one finish call end before it. The interval is read from the migration.
  const migration = await read(new URL("supabase/migrations/20261104141959_bizbot_zcredit_001d_server_ledger.sql", REPO));
  const deadline = /provider_query_key, provider_duplicate_key, retention_until, start_deadline_at\)[\s\S]*?clock_timestamp\(\) \+ interval '(\d+) seconds'\)\n\s+on conflict/.exec(migration);
  assert.ok(deadline, "the claim's start_deadline_at expression");
  const deadlineMs = BigInt(deadline[1]) * 1_000n;
  assert.equal(deadlineMs, 120_000n);
  assert.ok(BigInt(2 * TIMING.rpcMs + TIMING.commitBudgetMs) < deadlineMs);
  // The background commit (request body, proof, claim, commit, finish) fits the 150 s Free wall clock and
  // the 150 s request idle timeout - as an upper bound only; the worker may end sooner (a hosted gate).
  assert.ok(TIMING.requestMs + 2 * TIMING.rpcMs + TIMING.commitBudgetMs + TIMING.rpcMs < 150_000);
  // The answer times the POS transport timeout is sized against (body read excluded).
  assert.deepEqual([2 * TIMING.rpcMs + TIMING.startWindowMs, 3 * TIMING.rpcMs + TIMING.lookupMs,
    4 * TIMING.rpcMs + TIMING.releaseMs, 2 * TIMING.rpcMs], [13_000, 21_000, 26_000, 10_000]);
  // Automatic polling at the minimum interval spans more than twice the start deadline.
  assert.ok(BigInt(AUTO_POLL_CAP * POLL_MIN_INTERVAL_MS) >= 2n * deadlineMs);
});

test("no logging, no remote import, no hard-coded URL, no import outside the function directory", async () => {
  for (const { name, text } of await sources()) {
    const body = code(text);
    assert.ok(!/\bconsole\b/.test(body), `${name} logs`);
    assert.ok(!/\bWebSocket\b|\bEventSource\b|XMLHttpRequest|sendBeacon|Deno\.(?:connect|listen|run|Command)|\bnode:/.test(body),
      `${name} opens another network channel`);
    assert.ok(!/https?:\/\//.test(body), `${name} hard-codes a URL`);
    for (const match of body.matchAll(/\b(?:import|export)\b[^'"]*?\bfrom\s+['"]([^'"]+)['"]|\bimport\(\s*['"]([^'"]+)['"]\s*\)/g)) {
      const spec = match[1] ?? match[2];
      assert.ok(spec.startsWith("./") || spec.startsWith("../"), `${name} imports ${spec}`);
      const resolved = new URL(spec, new URL(name, FUNCTION_DIR));
      assert.ok(resolved.href.startsWith(FUNCTION_DIR.href), `${name} imports outside the function: ${spec}`);
    }
  }
});

test("fetch is used only through the bounded transport; the RPC set is exactly the seven card functions", async () => {
  const rpcs = new Set();
  for (const { name, text } of await sources()) {
    const body = code(text);
    const calls = [...body.matchAll(/\bfetch(?:Impl)?\s*\(/g)].length;
    assert.equal(calls, name === "lib/http.mjs" ? 1 : 0, `${name} calls fetch directly`);
    for (const match of body.matchAll(/["'`/](card_attempt_[a-z_]+|owner_card_attempts)["'`]/g)) rpcs.add(match[1]);
    assert.ok(!/sync_push|record_payment|payment\.create|close_shift|set_payment_terminal|set_card_payments_pilot|resolve_orphan|purge_expired/.test(body),
      `${name} names a payment writer or an operator RPC`);
    assert.ok(!/\/rest\/v1\/(?!rpc\/)/.test(body), `${name} reaches a table endpoint`);
  }
  assert.deepEqual([...rpcs].sort(), ["card_attempt_adapter_read", "card_attempt_claim", "card_attempt_context",
    "card_attempt_finish", "card_attempt_free_order", "card_attempt_mark_recording_result",
    "card_attempt_mark_release_requested"]);
  const caller = code((await sources()).find((source) => source.name === "lib/caller.mjs").text);
  assert.ok(!/card_attempt_(?!context)/.test(caller), "the caller-scoped client calls the context proof only");
});

test("money is float-free: no Number, parseFloat, parseInt, toFixed, Math, Intl or locale formatting", async () => {
  for (const { name, text } of await sources()) {
    if (name === "lib/time.mjs" || name === "index.ts") continue; // timestamps only; the runtime entry
    const body = code(text);
    for (const forbidden of [/\bNumber\s*[.(]/, /parseFloat/, /parseInt/, /toFixed/, /toPrecision/, /toLocaleString/, /\bIntl\b/,
      /\bMath\./, /Number\.isSafeInteger/, /\*\s*100(?!n)\b/, /\/\s*100(?!n)\b/, /%\s*100(?!n)\b/]) {
      assert.ok(!forbidden.test(body), `${name} matches ${forbidden}`);
    }
  }
  const money = code((await sources()).find((source) => source.name === "lib/money.mjs").text);
  assert.match(money, /minor \/ 100n/);
  assert.match(money, /minor % 100n/);
  const engine = code((await sources()).find((source) => source.name === "lib/provider/engine.mjs").text);
  assert.ok(!/JSON\.parse/.test(engine), "provider replies are parsed only by the raw-token reader");
  assert.ok(!/\breason\b|order_freed_note|confirmation_reference/.test(engine), "no provider value is routed into a free-text field");
});

test("config.toml registers pos-card-charge with verify_jwt = false and nothing else", async () => {
  const toml = await read(new URL("supabase/config.toml", REPO));
  const block = /\n\[functions\.pos-card-charge\]\n([\s\S]*?)(?=\n\[|\n*$)/.exec(toml);
  assert.ok(block, "the function block exists");
  assert.deepEqual(block[1].split("\n").map((line) => line.trim()).filter((line) => line && !line.startsWith("#")),
    ["enabled = true", "verify_jwt = false"]);
  assert.equal([...toml.matchAll(/\[functions\.pos-card-charge\]/g)].length, 1);
});

test("the validate job runs this suite as one explicit Node step", async () => {
  const ci = await read(new URL(".github/workflows/ci.yml", REPO));
  const validate = ci.slice(ci.indexOf("\n  validate:"), ci.indexOf("\n  db-tests:"));
  const steps = [...validate.matchAll(/node --test supabase\/functions\/pos-card-charge\/test\/\*\.test\.mjs/g)];
  assert.equal(steps.length, 1);
  assert.ok(!ci.slice(ci.indexOf("\n  db-tests:")).includes("pos-card-charge"));
});

test("the suite uses synthetic hosts only", async () => {
  const tests = (await files(FUNCTION_DIR)).filter((name) => name.startsWith("test/"));
  for (const name of tests) {
    const text = await read(new URL(name, FUNCTION_DIR));
    for (const match of text.matchAll(/https?:\/\/[^\s"'`)\]]+/g)) {
      let host;
      try { host = new URL(match[0].replace(/\$\{[^}]*\}.*$/, "")).hostname; } catch { host = match[0]; }
      assert.ok(host.endsWith(".test"), `${name} names ${host}`);
    }
  }
});

test("no answer ever carries a key, token, credential, PIN-pad identifier or provider reference", async () => {
  const secrets = [SERVICE, ANON, JWT, TOKEN, "SYNPASS", "SYNTERM", "SYNPAD", "abcdefghijklmnop", "ponmlkjihgfedcba", "SYN-REF-1",
    "APPR1", "VCH1", "pad-test", "cred-test", "SYNTHETIC"];
  const flows = [
    [startTest(), { card_attempt_context: contextOk(), card_attempt_claim: freshClaim(),
      card_attempt_finish: envelope("approved") }, { commit: providerReply() }],
    [startTest(), { card_attempt_context: contextOk(), card_attempt_claim: freshClaim(), card_attempt_finish: envelope("unknown") },
      { commit: () => { throw new Error("SYNTHETIC failure SYNPASS"); } }],
    [statusInput(), { card_attempt_context: contextOk({ attempt: contextAttempt("unknown") }),
      card_attempt_adapter_read: adapterRead("unknown"), card_attempt_finish: envelope("unknown") },
    { lookup: providerReply({ SynStatus: "S1" }) }],
    [releaseInput(), { card_attempt_context: contextOk({ attempt: contextAttempt("sent") }),
      card_attempt_adapter_read: adapterRead("sent"), card_attempt_mark_release_requested: envelope("sent"),
      card_attempt_finish: envelope("released") }, { release: { SynError: false, SynReturn: 0 } }],
    [freeInput(), { card_attempt_context: contextOk({ role: "manager" }), card_attempt_free_order: envelope("unknown") }, {}],
  ];
  for (const [input, rpc, provider] of flows) {
    const w = world({ rpc, provider });
    const out = await w.run(input);
    await w.settle();
    for (const secret of secrets) assert.ok(!out.text.includes(secret), `${input.action} answer leaks ${secret}`);
  }
});
