// The configuration NAMES and the shape-validated POS_CARD_PROVIDER_CONFIG (API_CONTRACT section
// 4.55.9; DEPLOYMENT section 18.4): mode / scope / restaurant rules, references, the SQL
// projections that never carry a credential value or PIN-pad identifier, and the env allowlist.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { blocked, providerConfig, REST, settleAll, stray } from "./fixtures.mjs";
import { allowlistedEnv, masterFlagOn, providerConfiguration, sqlMaps } from "../lib/config.mjs";
import { stringifyJson } from "../lib/json.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const parse = (value) => providerConfiguration(allowlistedEnv((name) => (name === "POS_CARD_PROVIDER_CONFIG"
  ? (typeof value === "string" ? value : JSON.stringify(value)) : undefined)));

test("a valid configuration parses; SQL receives references, tokens and ids only", () => {
  const config = parse(providerConfig());
  assert.ok(config);
  assert.equal(config.baseUrl, "https://synthetic-provider.test/api");
  const maps = sqlMaps(config);
  assert.equal(Object.getPrototypeOf(maps.terminals), null);
  assert.equal(Object.getPrototypeOf(maps.credentials), null);
  assert.deepEqual(JSON.parse(stringifyJson(maps)), { environment: "test", terminals: { "pad-test": "cred-test", "pad-live": "cred-live" },
    credentials: { "cred-test": { mode: "test", scope: "development" },
      "cred-live": { mode: "live", scope: "merchant", restaurant_id: REST } } });
  assert.ok(!JSON.stringify(maps).includes("SYN"), "no secret or PIN-pad value");
  assert.deepEqual(sqlMaps(null), { environment: null, terminals: {}, credentials: {} });
  assert.equal(parse({ ...providerConfig(), base_url: "https://synthetic-provider.test/" }).baseUrl, "https://synthetic-provider.test");
});

test("every shape violation is a missing configuration (provider_unavailable upstream)", () => {
  const base = providerConfig();
  const live = base.credentials["cred-live"];
  const testRecord = base.credentials["cred-test"];
  const bad = [
    "", "{", "[]", "null", JSON.stringify("x"),
    { ...base, environment: "staging" }, { ...base, environment: "TEST" },
    { ...base, key_format: "alpha16-l16-v1" }, { ...base, key_format: null },
    { ...base, base_url: "http://synthetic-provider.test" }, { ...base, base_url: "https://user:pw@synthetic-provider.test" },
    { ...base, base_url: "https://synthetic-provider.test/api?x=1" }, { ...base, base_url: "https://synthetic-provider.test/#x" },
    { ...base, base_url: "https://synthetic-provider.test/a b" }, { ...base, base_url: "not a url" },
    { ...base, extra: true }, (() => { const v = { ...base }; delete v.terminals; return v; })(),
    { ...base, credentials: {} }, { ...base, terminals: {} },
    { ...base, credentials: { "Cred-Upper": testRecord } },
    { ...base, credentials: { [`c-${"0".repeat(12)}`]: testRecord } },
    { ...base, credentials: { "cred-test": { ...testRecord, restaurant_id: REST } } },
    { ...base, credentials: { "cred-test": { ...testRecord, scope: "merchant" } } },
    { ...base, credentials: { "cred-live": { ...live, scope: "development" } } },
    { ...base, credentials: { "cred-live": { ...live, restaurant_id: undefined } } },
    { ...base, credentials: { "cred-live": { ...live, restaurant_id: "not-a-uuid" } } },
    { ...base, credentials: { "cred-test": { ...testRecord, mode: "sandbox" } } },
    { ...base, credentials: { "cred-test": { ...testRecord, secret: {} } } },
    { ...base, credentials: { "cred-test": { ...testRecord, secret: { terminal: "" } } } },
    { ...base, credentials: { "cred-test": { ...testRecord, secret: { terminal: "has space" } } } },
    { ...base, credentials: { "cred-test": { ...testRecord, secret: { Terminal: "X" } } } },
    { ...base, credentials: { "cred-test": { ...testRecord, secret: { terminal: 5 } } } },
    { ...base, credentials: { "cred-test": { ...testRecord, extra: 1 } } },
    { ...base, terminals: { "pad-test": { credential_ref: "cred-test" } } },
    { ...base, terminals: { "pad-test": { credential_ref: "cred-test", pinpad_id: "" } } },
    { ...base, terminals: { "pad-test": { credential_ref: "cred-test", pinpad_id: "has space" } } },
    { ...base, terminals: { "pad-test": { credential_ref: "Cred", pinpad_id: "X" } } },
    { ...base, terminals: { "pad test": { credential_ref: "cred-test", pinpad_id: "X" } } },
    { ...base, terminals: Object.fromEntries(Array.from({ length: 33 }, (_, i) => [`pad-${i}`, { credential_ref: "cred-test", pinpad_id: "X" }])) },
    JSON.stringify(base).replace('"environment":"test"', '"environment":"test","environment":"test"'),
  ];
  for (const value of bad) assert.equal(parse(value), null, JSON.stringify(value).slice(0, 100));
});

test("the master flag is exactly the text 'true' and the accessor reads only allowlisted names", () => {
  const env = allowlistedEnv((name) => ({ POS_CARD_PAYMENTS_ENABLED: "true", OTHER: "x" })[name]);
  assert.ok(masterFlagOn(env));
  for (const value of ["TRUE", "True", "1", "yes", " true", "true ", "", undefined]) {
    assert.ok(!masterFlagOn(allowlistedEnv(() => value)), String(value));
  }
  assert.throws(() => env("OTHER"));
  assert.throws(() => env("SUPABASE_SERVICE_ROLE_KEY"), "the service key is readable only through the ledger's opaque key source");
  assert.throws(() => env("SUPABASE_DB_URL"));
  assert.equal(allowlistedEnv(() => 5)("SUPABASE_URL"), undefined, "non-string values are absent");
});

test("the configuration maps have no prototype: a reference spelled like an Object member is an own key or absent", () => {
  const config = parse(providerConfig());
  for (const map of [config.credentials, config.terminals]) {
    assert.equal(Object.getPrototypeOf(map), null);
    for (const name of ["constructor", "toString", "hasOwnProperty", "valueOf", "__proto__"]) assert.equal(map[name], undefined, name);
  }
  // __proto__ and constructor match the reference grammar: they stay ordinary own keys end to end.
  const text = JSON.stringify(providerConfig()).replaceAll('"cred-live"', '"__proto__"').replaceAll('"pad-live"', '"constructor"');
  const odd = parse(text);
  assert.ok(odd);
  assert.deepEqual(Object.keys(odd.credentials), ["cred-test", "__proto__"]);
  assert.deepEqual(Object.keys(odd.terminals), ["pad-test", "constructor"]);
  assert.equal(Object.getPrototypeOf(odd.credentials), null, "a __proto__ reference never becomes the map's prototype");
  assert.equal(odd.credentials.__proto__.mode, "live");
  assert.equal(odd.terminals.constructor.credentialRef, "__proto__");
  const maps = JSON.parse(stringifyJson(sqlMaps(odd)));
  assert.deepEqual(Object.keys(maps.credentials), ["cred-test", "__proto__"]);
  assert.equal(maps.terminals.constructor, "__proto__");
});
