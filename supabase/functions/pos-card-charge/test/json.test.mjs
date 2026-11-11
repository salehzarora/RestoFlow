// Strict JSON with number tokens kept as text, and the raw-number writer.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { blocked, settleAll, stray } from "./fixtures.mjs";
import { integerText, isObject, JsonError, JsonNumber, parseJson, stringifyJson } from "../lib/json.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

test("numbers stay exact token text; nothing is converted to a JavaScript Number", () => {
  const long = "9".repeat(30);
  const parsed = parseJson(`{"a":12.340,"b":-0.5e-7,"c":${long},"d":0}`);
  assert.ok(parsed.a instanceof JsonNumber);
  assert.equal(parsed.a.text, "12.340");
  assert.equal(parsed.b.text, "-0.5e-7");
  assert.equal(parsed.c.text, long);
  assert.equal(stringifyJson(parsed), `{"a":12.340,"b":-0.5e-7,"c":${long},"d":0}`);
  assert.equal(Object.getPrototypeOf(parsed), null);
});

test("strictness: duplicate keys at any depth, trailing data, lone surrogates, bad tokens and depth", () => {
  const bad = ['{"a":1,"a":1}', '{"a":{"b":1,"b":2}}', '{"a":1} x', '{"a":"\\ud800"}', '{"a":"\\udc00x"}', "{'a':1}",
    '{"a":01}', '{"a":1.}', '{"a":.5}', '{"a":+1}', '{"a":NaN}', '{"a":Infinity}', '{"a":undefined}', '{"a":"\u0001"}',
    "", "   ", '{"a":1,}', "[1,]", `${"[".repeat(40)}${"]".repeat(40)}`];
  for (const text of bad) assert.throws(() => parseJson(text), JsonError, text.slice(0, 30));
  assert.deepEqual(parseJson(' { "a" : [ true , false , null , "x" ] } ').a, [true, false, null, "x"]);
});

test("the writer emits JsonNumber raw and refuses JavaScript numbers, undefined members and broken text", () => {
  assert.equal(stringifyJson({ amount: new JsonNumber("12.34"), list: [new JsonNumber("1"), "x", null, true] }),
    '{"amount":12.34,"list":[1,"x",null,true]}');
  for (const bad of [{ a: 1 }, { a: 1.5 }, [2], { a: undefined }, { a: "\ud800" }, { a: () => 1 }, { a: 1n }]) {
    assert.throws(() => stringifyJson(bad), TypeError, String(Object.keys(bad)));
  }
  assert.throws(() => new JsonNumber("1e"));
  assert.throws(() => new JsonNumber(5));
});

test("integer tokens in closed ranges", () => {
  assert.equal(integerText(new JsonNumber("7"), 0, 10), "7");
  assert.equal(integerText(new JsonNumber("-999999"), -999999, 999999), "-999999");
  for (const bad of ["11", "-1", "1.0", "1e1", "-0"]) assert.equal(integerText(new JsonNumber(bad), 0, 10), null, bad);
  assert.equal(integerText(7, 0, 10), null);
  assert.equal(integerText("7", 0, 10), null);
  assert.ok(isObject(parseJson("{}")));
  assert.ok(!isObject(new JsonNumber("1")));
  assert.ok(!isObject([]));
});
