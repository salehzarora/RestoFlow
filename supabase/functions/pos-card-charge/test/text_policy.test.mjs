// The text policy (DECISION D-059 point 4): the JavaScript tables are the migration's class
// constants verbatim, the field table equals the SQL CASE exactly, and the validator returns the
// same result as app.card_safe_text_failure / card_text_canonical / card_text_absent for the
// text-policy vectors of supabase/tests/bizbot_zcredit_001d_field_rules_test.sql: the _fr_v groups
// (FR-1..FR-23, FR-30), the trim set (FR-24, FR-25), the review-fix-12 mask vectors (FR-236..FR-239),
// the review-fix-13 / 14 length bound and absence vectors (FR-241..FR-251, FR-247 as a 500 ms CPU bound),
// the review-fix-26 bound precedence (FR-285) and the C1-4 groups and code-space sweeps
// (FR-291..FR-320). Not ported: FR-26..FR-29 and FR-41 (single canonical / UUID cases covered by
// other vectors here) and every assertion that needs the database (the finish, events, audits).
// test/sql_vectors.mjs evaluates the vectors from the SQL text at run time, so no vector value is
// copied into this file, and a failing vector is named by group, number and field only - never
// printed. Item 35's residual vectors are recorded, not fixed.
import "./no_network.mjs";
import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { isDeepStrictEqual } from "node:util";
import { blocked, settleAll, stray } from "./fixtures.mjs";
import { PG_CLASSES, ZS_TRIM_CODE_POINTS } from "../lib/text_policy_tables.mjs";
import { canonicalText, FIELD_TABLE, pgClassToJs, RUNTIME_UNICODE_OK, safeTextFailure, textAbsent, UNICODE_15_NFKC,
  unicodeSelfCheck } from "../lib/text_policy.mjs";
import { assertionStatement, evaluate, evaluateInsert, evaluateIs, evaluateResultsEq, evaluateRows, expectedValues, statements,
  tableColumns, Unsupported } from "./sql_vectors.mjs";

test.after(async () => { await settleAll(); assert.deepEqual(blocked, []); assert.deepEqual(stray, []); });

const ROOT = new URL("../../../", import.meta.url);
const MIGRATION = new URL("migrations/20261023225657_bizbot_zcredit_001d_server_ledger.sql", ROOT);
const FIELD_RULES = new URL("tests/bizbot_zcredit_001d_field_rules_test.sql", ROOT);
const FUNCTION_SOURCE = new URL("../lib/text_policy.mjs", import.meta.url);
const read = async (url) => (await readFile(url, "utf8")).replace(/\r\n/g, "\n");
const squash = (text) => text.replace(/\s+/g, " ").trim();
const chr = (cp) => String.fromCodePoint(cp);
const hex = (cp) => `U+${cp.toString(16).toUpperCase().padStart(4, "0")}`;
/** app.card_safe_text_failure(app.card_text_canonical(v), field): NULL in, NULL out. */
const canonicalFailure = (value, field) => safeTextFailure(canonicalText(value), field);

const sqlText = read(FIELD_RULES);

test("the seven class constants and the trim set equal the migration's, byte for byte", async () => {
  const sql = await read(MIGRATION);
  const body = /create function app\.card_safe_text_failure\([\s\S]*?\n\$\$;/.exec(sql)[0];
  const constants = Object.fromEntries([...body.matchAll(/\n\s+(c_[a-z_]+) constant text := (U&)?'((?:[^']|'')*)';/g)]
    .map((match) => [match[1].slice(2), { unicode: Boolean(match[2]), text: match[3] }]));
  assert.deepEqual(Object.keys(PG_CLASSES), ["allowed_only", "control", "numeric_other", "not_digit", "mask_strip", "masked",
    "visible"]);
  for (const [name, text] of Object.entries(PG_CLASSES)) {
    assert.equal(constants[name].unicode, false, name);
    assert.equal(text, constants[name].text, `${name} differs from the migration`);
  }
  const trim = [...constants.trim.text.matchAll(/\\([0-9A-F]{4})/g)].map((match) => Number.parseInt(match[1], 16));
  assert.equal(constants.trim.unicode, true);
  assert.deepEqual([...ZS_TRIM_CODE_POINTS], trim);
  assert.equal(trim.length, 17);
});

test("the field table equals the SQL CASE exactly (charset, min, max, free text), with boundary vectors per field", async () => {
  const sql = await read(MIGRATION);
  const body = /create function app\.card_safe_text_failure\([\s\S]*?\n\$\$;/.exec(sql)[0];
  const block = /\n {2}case p_field\n([\s\S]*?)\n {4}else\n {6}return 'charset';\n {2}end case;/.exec(body)[1];
  const table = {};
  for (const match of block.matchAll(/when ((?:'[a-z0-9_]+',?\s*)+)then\n((?:[ ]+v_[a-z]+ := [^;\n]+;)+)/g)) {
    const spec = { charset: null, min: 1, max: null, free: false };
    for (const [, name, value] of match[2].matchAll(/v_([a-z]+) := ([^;]+);/g)) {
      if (name === "charset") spec.charset = /^'([^']+)'$/.exec(value)[1];
      else if (name === "min" || name === "max") spec[name] = Number(value);
      else if (name === "free") spec.free = value === "true";
      else assert.fail(`unexpected assignment v_${name}`);
    }
    for (const [, field] of match[1].matchAll(/'([a-z0-9_]+)'/g)) table[field] = spec;
  }
  assert.equal(Object.keys(table).length, 21, "every field of the SQL table");
  assert.deepEqual(Object.keys(FIELD_TABLE).sort(), Object.keys(table).sort());
  assert.ok(Object.isFrozen(FIELD_TABLE) && Object.values(FIELD_TABLE).every((spec) => Object.isFrozen(spec)));
  // No live RegExp leaves the module: the exports are pinned, and every table entry is plain data (verification V1-3).
  assert.deepEqual(Object.keys(await import("../lib/text_policy.mjs")), ["FIELD_TABLE", "RUNTIME_UNICODE_OK", "UNICODE_15_NFKC",
    "canonicalText", "pgClassToJs", "safeTextFailure", "textAbsent", "trimSpaceSeparators", "unicodeSelfCheck"]);
  for (const spec of Object.values(FIELD_TABLE)) {
    assert.deepEqual(Object.keys(spec).sort(), ["charset", "flags", "free", "max", "min"]);
    assert.ok(Object.values(spec).every((value) => value === null || ["string", "number", "boolean"].includes(typeof value)));
  }
  for (const [field, spec] of Object.entries(table)) {
    const js = FIELD_TABLE[field];
    assert.equal(js.charset, spec.charset, `${field} charset`);
    assert.equal(js.flags, spec.charset === null ? null : "u", `${field} flags`);
    assert.equal(js.min, spec.min, `${field} min`);
    assert.equal(js.max, spec.max, `${field} max`);
    assert.equal(js.free, spec.free, `${field} free text`);
    // One unit of the field's own alphabet (never a mask or digit-run character).
    const unit = spec.charset === "^[0-9]+$" ? "4" : spec.free || /A-Z/.test(spec.charset) ? "A" : "a";
    if (spec.min > 1) assert.equal(safeTextFailure(unit.repeat(spec.min - 1), field), "length", `${field} min - 1`);
    assert.equal(safeTextFailure(unit.repeat(spec.min), field), null, `${field} min`);
    assert.equal(safeTextFailure(unit.repeat(spec.max), field), null, `${field} max`);
    assert.equal(safeTextFailure(unit.repeat(spec.max + 1), field), "length", `${field} max + 1`);
    assert.equal(safeTextFailure("\u3000", field), "length", `${field}: empty after the canonical trim (FR-29)`);
  }
  for (const field of ["no_such_field", "__proto__", "toString", "constructor"]) {
    assert.equal(safeTextFailure("abc", field), "charset", `${field}: an unknown field fails closed (FR-21)`);
  }
  assert.equal(safeTextFailure(null, "reason"), null, "NULL in, NULL out (FR-21)");
});

test("the escape conversion keeps every range endpoint inside, and its neighbours outside, each class", () => {
  for (const [name, text] of Object.entries(PG_CLASSES)) {
    const bracket = /\[\^?((?:\\u[0-9A-F]{4}|\\U[0-9A-F]{8}|-)+)\]/.exec(text);
    const points = [...bracket[1].matchAll(/(\\u[0-9A-F]{4}|\\U[0-9A-F]{8})(?:-(\\u[0-9A-F]{4}|\\U[0-9A-F]{8}))?/g)]
      .map((match) => [Number.parseInt(match[1].slice(2), 16), Number.parseInt((match[2] ?? match[1]).slice(2), 16)]);
    const inside = new RegExp(`^${pgClassToJs(`[${bracket[1]}]`)}$`, "u");
    for (const [low, high] of points) {
      for (const point of [low, high]) assert.ok(inside.test(chr(point)), `${name} ${point.toString(16)}`);
    }
    const covered = (point) => points.some(([low, high]) => point >= low && point <= high);
    for (const [low, high] of points) {
      for (const point of [low - 1, high + 1]) {
        if (point < 0 || point > 0x10ffff || covered(point) || (point >= 0xd800 && point <= 0xdfff)) continue;
        assert.ok(!inside.test(chr(point)), `${name} neighbour ${point.toString(16)}`);
      }
    }
  }
});

test("the Unicode self-check: the module's own pairs, a failing normalize, and an older runtime refusing everything", async () => {
  assert.deepEqual(UNICODE_15_NFKC.map((pair) => [...pair]), [[0x1e030, 0x0430], [0x1e043, 0x0445], [0x1e061, 0x0445],
    [0x1e06d, 0x04b1]], "the Unicode 15.0 NFKC mappings of Cyrillic Extended-D");
  assert.ok(Object.isFrozen(UNICODE_15_NFKC) && UNICODE_15_NFKC.every((pair) => Object.isFrozen(pair)));
  for (const [from, to] of UNICODE_15_NFKC) assert.equal(chr(from).normalize("NFKC"), chr(to), hex(from));
  assert.equal(unicodeSelfCheck((value) => value.normalize("NFKC")), true);
  assert.equal(unicodeSelfCheck((value) => value), false, "a runtime without the mappings fails the check");
  assert.equal(unicodeSelfCheck((value) => (value.codePointAt(0) === 0x1e06d ? value : value.normalize("NFKC"))), false,
    "every pair is needed");
  assert.equal(RUNTIME_UNICODE_OK, true);
  // An older runtime, simulated in a child process: String.prototype.normalize leaves Cyrillic Extended-D unmapped.
  const script = [
    "const original = String.prototype.normalize;",
    "String.prototype.normalize = function (form) {",
    "  const value = String(this);",
    "  return [...value].some((c) => c.codePointAt(0) >= 0x1e030 && c.codePointAt(0) <= 0x1e08f) ? value : original.call(value, form);",
    "};",
    `const policy = await import(${JSON.stringify(new URL("../lib/text_policy.mjs", import.meta.url).href)});`,
    `const fixtures = await import(${JSON.stringify(new URL("./fixtures.mjs", import.meta.url).href)});`,
    "const w = fixtures.world();",
    "const out = await w.run(fixtures.startTest());",
    "console.log(JSON.stringify({ flag: policy.RUNTIME_UNICODE_OK, reason: policy.safeTextFailure('Customer request', 'reason'),",
    "  approval: policy.safeTextFailure('A1', 'approval_type'), none: policy.safeTextFailure(null, 'reason'),",
    "  status: out.status, body: out.body, rpc: w.calls.rpc.length, provider: w.calls.provider.length,",
    "  blocked: fixtures.blocked.length, stray: fixtures.stray.length }));",
  ].join("\n");
  const output = execFileSync(process.execPath, ["--input-type=module", "-e", script], { encoding: "utf8" });
  assert.deepEqual(JSON.parse(output), { flag: false, reason: "charset", approval: "charset", none: null, status: 503,
    body: { ok: false, error: "provider_unavailable" }, rpc: 0, provider: 0, blocked: 0, stray: 0 },
    "a failed self-check refuses every value: the configuration references fail, so start makes no call");
  const source = await read(FUNCTION_SOURCE);
  assert.match(source, /if \(!spec \|\| typeof value !== "string" \|\| !RUNTIME_UNICODE_OK\) return "charset";/,
    "the flag is checked before any rule");
});

/** The base tables of the vector file (as inserted there) plus _fr_c1cp / _fr_c1fam derived as it derives them. */
function vectorTables(sql) {
  const tables = {};
  for (const name of ["_fr_mask", "_fr_mask8", "_fr_c1cls", "_fr_c1famr", "_fr_c1w", "_fr_c1fill", "_fr_c1mark", "_fr_c1lm5",
    "_fr_c1sep"]) {
    const columns = tableColumns(sql, name);
    tables[name] = statements(sql, `insert into ${name} `).flatMap((statement) => evaluateInsert(statement, tables, {}, columns).rows);
    assert.ok(tables[name].length > 0, name);
  }
  tables._fr_c1cp = tables._fr_c1cls.flatMap(({ cls, lo, hi }) => Array.from({ length: hi - lo + 1 }, (_, k) => ({ cls, cp: lo + k })))
    .filter((row) => row.cp !== 0);
  const digits = tables._fr_c1cp.filter((row) => row.cls === "digit");
  const families = {};
  for (const range of tables._fr_c1famr) {
    for (const { cp } of digits) if (cp >= range.lo && cp <= range.hi) (families[range.fam] ??= []).push({ fam: range.fam, ord: range.ord, cp });
  }
  tables._fr_c1fam = Object.values(families).flatMap((members) => members.sort((a, b) => a.cp - b.cp)
    .map((member, index) => ({ ...member, n: index + 1 })));
  return tables;
}

/** pg_temp.fr_c1_d / fr_c1_mixed / fr_c1_w, ported from the definitions pinned in the C1 test. */
function vectorFunctions(tables) {
  const members = (fam) => tables._fr_c1fam.filter((row) => row.fam === fam).sort((a, b) => a.n - b.n);
  const familyOf = new Map(tables._fr_c1fam.map((row) => [row.ord, row.fam]));
  return {
    "pg_temp.fr_c1_d": (count, fam = "ascii", start = 2, separator = "") => {
      // string_agg over no row is NULL, and a NULL separator is NULL: neither occurs in the vectors, so refuse both.
      assert.ok(Number.isInteger(count) && count >= 1 && typeof separator === "string", "fr_c1_d arguments");
      const list = members(fam);
      assert.ok(list.length > 0, `family ${fam}`);
      return Array.from({ length: count }, (_, i) => chr(list[(start - 1 + i) % list.length].cp)).join(separator);
    },
    "pg_temp.fr_c1_mixed": (count, separator = "") => {
      assert.ok(Number.isInteger(count) && count >= 1 && typeof separator === "string", "fr_c1_mixed arguments");
      return Array.from({ length: count }, (_, k) => {
        const i = k + 1;
        const member = members(familyOf.get((i - 1) % 12 + 1)).find((row) => row.n === i % 9 + 1);
        return chr(member.cp);
      }).join(separator);
    },
    "pg_temp.fr_c1_w": (key) => tables._fr_c1w.find((row) => row.k === key)?.w ?? null,
  };
}

test("every _fr_v vector gives the same rule token (FR-1..FR-30: the literal rows, A7, A15 / A16)", async (t) => {
  const sql = await sqlText;
  const tables = vectorTables(sql);
  const vectors = statements(sql, "insert into _fr_v (").flatMap((statement) => evaluateInsert(statement, tables).rows);
  assert.equal(vectors.length, 520);
  assert.equal(new Set(vectors.map((v) => v.grp)).size, 16, "FR-30: all 16 groups");
  assert.equal(vectors.filter((v) => v.grp === "A15").length, 39 * 5 + 17, "FR-19");
  assert.equal(tables._fr_mask.length, 39);
  for (const [index, v] of vectors.entries()) {
    const label = `${v.grp} #${index + 1} ${v.field}`;
    assert.equal(safeTextFailure(v.val, v.field), v.want, label);
    const canonical = canonicalText(v.val);
    assert.ok(canonical === null || canonicalText(canonical) === canonical, `FR-22 idempotent: ${label}`);
    if (v.want === null) assert.ok(canonical !== null && safeTextFailure(canonical, v.field) === null, `FR-23: ${label}`);
  }
  t.diagnostic(`_fr_v vectors evaluated: ${vectors.length}`);
});

test("every C1-4 vector group gives the same rule token, raw and canonical (FR-296..FR-317, FR-319)", async (t) => {
  const sql = await sqlText;
  const flat = squash(sql);
  // The derivations and helpers this file ports, pinned to their SQL text.
  for (const definition of [
    "create temp table _fr_c1cp as select c.cls, g.cp from _fr_c1cls c cross join lateral generate_series(c.lo, c.hi) g(cp) where g.cp <> 0;",
    "create temp table _fr_c1fam as select r.fam, r.ord, (row_number() over (partition by r.fam order by c.cp))::integer as n, c.cp from _fr_c1famr r join _fr_c1cp c on c.cls = 'digit' and c.cp between r.lo and r.hi;",
    "create function pg_temp.fr_c1_d(p_n integer, p_fam text default 'ascii', p_start integer default 2, p_sep text default '') returns text language sql stable as $$ select string_agg(chr(f.cp), p_sep order by g.i) from generate_series(0, p_n - 1) g(i) join _fr_c1fam f on f.fam = p_fam and f.n = (p_start - 1 + g.i) % (select count(*) from _fr_c1fam x where x.fam = p_fam) + 1 $$;",
    "create function pg_temp.fr_c1_mixed(p_n integer, p_sep text default '') returns text language sql stable as $$ select string_agg(chr(f.cp), p_sep order by g.i) from generate_series(1, p_n) g(i) join (select distinct x.fam, x.ord from _fr_c1fam x) o on o.ord = (g.i - 1) % 12 + 1 join _fr_c1fam f on f.fam = o.fam and f.n = g.i % 9 + 1 $$;",
    "create function pg_temp.fr_c1_w(p_k text) returns text language sql stable as $$ select w from _fr_c1w where k = p_k $$;",
    "create function pg_temp.fr_c1_dl(p_v text) returns integer language sql stable as $$ select count(*)::integer from regexp_split_to_table(p_v, '') c where pg_temp.fr_c1_is('digit', ascii(c)) $$;",
    "and (app.card_safe_text_failure(v.val, v.field) is distinct from v.want or (v.canon_too and app.card_safe_text_failure(app.card_text_canonical(v.val), v.field) is distinct from v.want))",
    "canon_too boolean not null default true",
  ]) assert.ok(flat.includes(definition), `pinned SQL text: ${definition.slice(0, 60)}`);
  const tables = vectorTables(sql);
  const functions = vectorFunctions(tables);
  const digitLike = new Set(tables._fr_c1cp.filter((row) => row.cls === "digit").map((row) => row.cp));
  const dl = (value) => [...value].filter((c) => digitLike.has(c.codePointAt(0))).length;
  const vectors = statements(sql, "insert into _fr_c1v (")
    .flatMap((statement) => evaluateInsert(statement, tables, functions).rows)
    .map((row, index) => ({ canon_too: true, ...row, k: index + 1 }));
  // FR-319: the groups, their sizes and the digit-like counts they were built with.
  const groups = [];
  for (const v of vectors) {
    let group = groups.find((g) => g.grp === v.grp);
    if (!group) groups.push(group = { grp: v.grp, count: 0, min: Infinity, max: -Infinity });
    group.count++;
    group.min = Math.min(group.min, dl(v.val));
    group.max = Math.max(group.max, dl(v.val));
  }
  assert.deepEqual(groups.map((g) => [g.grp, g.count, g.min, g.max]), expectedValues(sql, "FR-319"));
  // FR-296..FR-316 (pg_temp.fr_c1_bad): the raw token, and the canonical one unless canon_too is false.
  for (const v of vectors.filter((x) => !["NUMRAW", "POST"].includes(x.grp))) {
    const label = `${v.grp} #${v.k} ${v.label} [${v.field}]`;
    assert.equal(safeTextFailure(v.val, v.field), v.want, label);
    if (v.canon_too) assert.equal(canonicalFailure(v.val, v.field), v.want, `canonical: ${label}`);
  }
  // FR-299 (NUMRAW) and FR-317 (POST): their exact expected rows.
  assert.deepEqual(vectors.filter((v) => v.grp === "NUMRAW").map((v) => [v.label, v.field, safeTextFailure(v.val, v.field),
    canonicalFailure(v.val, v.field)]), expectedValues(sql, "FR-299"));
  assert.deepEqual(vectors.filter((v) => v.grp === "POST").map((v) => [v.label, v.field, [...v.val].length,
    [...canonicalText(v.val)].length, safeTextFailure(v.val, v.field), canonicalFailure(v.val, v.field)]), expectedValues(sql, "FR-317"));
  // FR-318 (vectors): the canonical form is idempotent.
  for (const v of vectors) {
    const canonical = canonicalText(v.val);
    assert.ok(canonical === null || canonicalText(canonical) === canonical, `FR-318 #${v.k}`);
  }
  t.diagnostic(`C1 vectors evaluated: ${vectors.length} in ${groups.length} groups`);
});

test("the C1-4 class tables and code-space sweeps (FR-291..FR-295, FR-298, FR-300, FR-302..FR-305, FR-310, FR-311, FR-318, FR-320)", async (t) => {
  const sql = await sqlText;
  const tables = vectorTables(sql);
  const functions = vectorFunctions(tables);
  const cls = (name) => tables._fr_c1cp.filter((row) => row.cls === name).map((row) => row.cp);
  const digitLike = new Set(cls("digit"));
  const dl = (value) => [...value].filter((c) => digitLike.has(c.codePointAt(0))).length;
  const masks = new Set(tables._fr_mask.map((row) => row.cp));
  const d = functions["pg_temp.fr_c1_d"];
  // FR-291 / FR-292: the class table and the digit families.
  const summary = {};
  for (const { cls: name, lo, hi } of tables._fr_c1cls) {
    summary[name] ??= [name, 0, 0];
    summary[name][1]++;
    summary[name][2] += hi - lo + 1;
  }
  assert.deepEqual(Object.values(summary).sort((a, b) => (a[0] < b[0] ? -1 : 1)), expectedValues(sql, "FR-291"));
  const families = [...new Map(tables._fr_c1fam.map((row) => [row.fam, row.ord])).entries()].sort((a, b) => a[1] - b[1])
    .map(([fam]) => [fam, tables._fr_c1fam.filter((row) => row.fam === fam).length]);
  assert.deepEqual(families, expectedValues(sql, "FR-292"));
  // FR-293 / FR-294: every refused control, alone and inside a visible reason.
  for (const cp of [...cls("di_refused"), ...cls("ctrl_other")]) {
    assert.equal(safeTextFailure(chr(cp), "reason"), "control_character", `alone ${hex(cp)}`);
    assert.equal(safeTextFailure(`Ab ${chr(cp)} cd`, "reason"), "control_character", `inside ${hex(cp)}`);
  }
  // FR-295 and the sweep columns of FR-296 / FR-298 / FR-300 / FR-302 / FR-310: the whole code space.
  const expected = Object.fromEntries([...sql.matchAll(/\(j ->> '([a-z_]+)'\)::integer <> (\d+)/g)].map((m) => [m[1], Number(m[2])]));
  const totals = /'\{"swept": (\d+), "control_verdicts": (\d+), "control_class": (\d+), "control_mismatch": (\d+)\}'::jsonb/.exec(sql)
    .slice(1).map(Number);
  const marks = /s\.cp in \(([0-9, ]+)\) and s\.f is not null/.exec(sql)[1].split(",").map(Number);
  const control = new Set([...cls("di_refused"), ...cls("ctrl_other")]);
  const sets = { numeric: new Set(cls("numeric")), canon_numeric: new Set(cls("canon_numeric")), digit: digitLike, lm: new Set(cls("lm")) };
  const sweep = { swept: 0, control_verdicts: 0, control_class: 0, control_mismatch: 0, numeric_class: 0, numeric_not_charset: 0,
    canon_numeric_class: 0, canon_numeric_not_charset: 0, digit_class: 0, digit_not_null: 0, lm_class: 0, lm_not_null: 0,
    marks_not_null: 0 };
  for (let cp = 1; cp <= 0x10ffff; cp++) {
    if (cp >= 0xd800 && cp <= 0xdfff) continue;
    const f = safeTextFailure(`ab${chr(cp)}cd`, "reason");
    sweep.swept++;
    if (f === "control_character") sweep.control_verdicts++;
    if (control.has(cp)) sweep.control_class++;
    if ((f === "control_character") !== control.has(cp)) sweep.control_mismatch++;
    if (sets.numeric.has(cp)) { sweep.numeric_class++; if (f !== "charset") sweep.numeric_not_charset++; }
    if (sets.canon_numeric.has(cp)) { sweep.canon_numeric_class++; if (f !== "charset") sweep.canon_numeric_not_charset++; }
    if (sets.digit.has(cp)) { sweep.digit_class++; if (f !== null) sweep.digit_not_null++; }
    if (sets.lm.has(cp)) { sweep.lm_class++; if (f !== null) sweep.lm_not_null++; }
    if (marks.includes(cp) && f !== null) sweep.marks_not_null++;
  }
  assert.deepEqual([sweep.swept, sweep.control_verdicts, sweep.control_class, sweep.control_mismatch], totals, "FR-295");
  for (const [name, value] of Object.entries(expected)) assert.equal(sweep[name], value, `sweep ${name}`);
  assert.equal(sweep.marks_not_null, 0, "FR-296 sweep");
  // FR-298: every Numeric code point alone, inside a reason and after REF- as a provider_reference.
  for (const cp of sets.numeric) {
    assert.equal(safeTextFailure(chr(cp), "reason"), "charset", `alone ${hex(cp)}`);
    assert.equal(safeTextFailure(`Ab ${chr(cp)} cd`, "reason"), "charset", `inside ${hex(cp)}`);
    assert.equal(safeTextFailure(`REF-${chr(cp)}`, "provider_reference"), "charset", `REF- ${hex(cp)}`);
  }
  // FR-300: the NFKC-only Numeric producers.
  for (const cp of sets.canon_numeric) {
    assert.ok(!sets.numeric.has(cp), hex(cp));
    assert.equal(safeTextFailure(`Ab ${chr(cp)} cd`, "reason"), "charset", hex(cp));
  }
  // FR-302 / FR-303 / FR-320: the 808 digit-like code points.
  for (const cp of digitLike) {
    const c = chr(cp);
    assert.equal(safeTextFailure(c.repeat(12), "reason"), "digit_run", `x12 ${hex(cp)}`);
    assert.equal(canonicalFailure(c.repeat(12), "reason"), "digit_run", `x12 canonical ${hex(cp)}`);
    assert.equal(safeTextFailure(c.repeat(11), "reason"), null, `x11 ${hex(cp)}`);
    assert.equal(canonicalFailure(c.repeat(11), "reason"), null, `x11 canonical ${hex(cp)}`);
    assert.equal(dl(c.normalize("NFKC")), 1, `FR-303 ${hex(cp)}`);
    const four = c.repeat(4);
    assert.equal(safeTextFailure(`${four}*${four}`, "reason"), "masked_pattern", `4*4 ${hex(cp)}`);
    assert.equal(canonicalFailure(`${four}*${four}`, "reason"), "masked_pattern", `4*4 canonical ${hex(cp)}`);
    assert.equal(safeTextFailure(`***${four}`, "reason"), "masked_pattern", `***4 ${hex(cp)}`);
    assert.equal(safeTextFailure(`${four}###`, "reason"), "masked_pattern", `4### ${hex(cp)}`);
    assert.equal(safeTextFailure(`${c.repeat(3)}*${four}`, "reason"), null, `3*4 ${hex(cp)}`);
    assert.equal(safeTextFailure(`**${four}`, "reason"), null, `**4 ${hex(cp)}`);
  }
  // FR-304 / FR-305: the NFKC-only digit producers.
  const producers = {};
  for (const cp of cls("canon_digit")) {
    const key = `${dl(chr(cp))}/${dl(chr(cp).normalize("NFKC"))}`;
    producers[key] = (producers[key] ?? 0) + 1;
    const per = dl(chr(cp).normalize("NFKC"));
    const copies = Math.trunc(12 / per);
    assert.equal(safeTextFailure(chr(cp).repeat(12), "reason"), "digit_run", `x12 ${hex(cp)}`);
    assert.equal(safeTextFailure(chr(cp).repeat(copies), "reason"), "digit_run", `xmin ${hex(cp)}`);
    assert.equal(safeTextFailure(chr(cp).repeat(copies - 1), "reason"), null, `xmin-1 ${hex(cp)}`);
  }
  assert.deepEqual(Object.entries(producers).map(([key, count]) => [...key.split("/").map(Number), count]).sort(),
    expectedValues(sql, "FR-304"));
  // FR-310 / FR-311: every Lm code point as a mask separator.
  const lmMasks = [];
  for (const cp of sets.lm) {
    const l = chr(cp);
    const canonicalMask = [...l.normalize("NFKC")].some((c) => masks.has(c));
    if (canonicalMask) lmMasks.push([hex(cp)]);
    assert.equal(safeTextFailure(`${d(4)}${l}*${l}${d(4, "ascii", 6)}`, "reason"), "masked_pattern", `masked ${hex(cp)}`);
    assert.equal(safeTextFailure(`${d(4)}${l}${d(4, "ascii", 6)}`, "reason"), canonicalMask ? "masked_pattern" : null, `plain ${hex(cp)}`);
  }
  assert.deepEqual(lmMasks, expectedValues(sql, "FR-311"));
  // FR-318 (code points): the canonical form is idempotent over the class table.
  for (const { cp } of tables._fr_c1cp) {
    const canonical = canonicalText(chr(cp));
    assert.ok(canonical === null || canonicalText(canonical) === canonical, `FR-318 ${hex(cp)}`);
  }
  t.diagnostic(`code points swept: ${sweep.swept}`);
});

test("the review-fix-12 mask vectors: 8 added masks x 3 shapes x 2 fields, and U+1F685 is no mask (FR-236..FR-239)", async () => {
  const sql = await sqlText;
  const tables = vectorTables(sql);
  const m8v = /\ncreate temp table _fr_m8v as\n(select [\s\S]*?);\n/.exec(sql)[1];
  const vectors = evaluateRows(m8v, tables);
  assert.equal(vectors.length, 48, "FR-236");
  const allMasks = new Set(tables._fr_mask.map((row) => row.cp));
  assert.ok(tables._fr_mask8.every((row) => allMasks.has(row.cp)), "FR-236: the 8 belong to the 39");
  for (const [index, [, field, shape, value]] of vectors.entries()) {
    assert.equal(safeTextFailure(value, field), "masked_pattern", `FR-237 #${index + 1} ${field} / ${shape}`);
  }
  const train = /'FR-238 [\s\S]*?\n(select is_empty\(\$\$ select format\('%s \/ %s got=%s'[\s\S]*?)\n {2}'FR-239 /.exec(sql)[1];
  const from = /\n\s+from (\(values \('reason'\), \('order_freed_note'\)\) f\(field\)\n\s+cross join \(values [\s\S]*?\) s\(shape, val\))\n\s+where /.exec(train)[1];
  const shapes = evaluateRows(`select f.field, s.shape, s.val from ${from}`, tables);
  assert.equal(shapes.length, 6);
  for (const [field, shape, value] of shapes) assert.equal(safeTextFailure(value, field), null, `FR-239 ${field} / ${shape}`);
});

test("the length bound, the trim set and absence (FR-24, FR-25, FR-241..FR-251, FR-285)", async (t) => {
  const sql = await sqlText;
  const functions = {
    "app.card_safe_text_failure": (value, field) => safeTextFailure(value, field),
    "app.card_text_canonical": (value) => (value === null ? null : canonicalText(value)),
    "app.card_text_absent": (value) => textAbsent(value),
  };
  let checked = 0;
  // FR-241..FR-244, FR-248, FR-249: `select is(<actual>, <expected>, ...)` evaluated with the JavaScript policy.
  for (const label of ["FR-241", "FR-242", "FR-243", "FR-244", "FR-248", "FR-249"]) {
    const [actual, expected] = evaluateIs(assertionStatement(sql, label), functions);
    assert.ok(isDeepStrictEqual(actual, expected), label); // never print the long values
    checked++;
  }
  // FR-245 and FR-285: results_eq over a VALUES list (the rows carry labels and tokens, never the values).
  for (const label of ["FR-245", "FR-285"]) {
    const [actual, expected] = evaluateResultsEq(assertionStatement(sql, label), {}, functions);
    assert.ok(actual.length >= 6 && actual.length === expected.length, label);
    for (const [index, row] of actual.entries()) assert.deepEqual(row, expected[index], `${label} row ${index + 1}`);
    checked += actual.length;
  }
  // FR-246 / FR-247: a 64001-code-point mark run answers length from the linear bound, well under 500 ms of CPU.
  const timed = /\ncreate temp table _fr_timed as\nselect \* from pg_temp\.fr_timed\(([\s\S]*?), 'reason'\);\n/.exec(sql)[1];
  const value = evaluate(timed);
  const expected = JSON.parse(/'(\{[^']*\})'::jsonb,\n\s+'FR-246 /.exec(sql)[1]);
  // CPU time, not wall time: a loaded runner deschedules the process (verification V2-5). The bound-free path costs ~1.8 s.
  const cpu = process.cpuUsage();
  const failure = safeTextFailure(value, "reason");
  const used = process.cpuUsage(cpu);
  const elapsed = (used.user + used.system) / 1_000;
  assert.deepEqual({ failure, raw_code_points: [...value].length }, expected, "FR-246");
  assert.ok(elapsed < 500, `FR-247: ${Math.round(elapsed)} ms of CPU`);
  checked++;
  // FR-24 / FR-25: the trim set is exactly the 17 Zs (each predicate ported from its is_empty query, pinned here).
  const fr24 = assertionStatement(sql, "FR-24");
  assert.ok(fr24.includes(" z where app.card_text_canonical(z || z || 'ZC 1' || z) is distinct from 'ZC 1' $$"), "FR-24 predicate");
  const spaces = evaluateRows(`select z from ${/ from (unnest\(array\[[^\]]*\]\)) z where /.exec(fr24)[1]} z`);
  assert.equal(spaces.length, 17);
  for (const [z] of spaces) assert.equal(canonicalText(`${z}${z}ZC 1${z}`), "ZC 1", `FR-24 ${hex(z.codePointAt(0))}`);
  const fr25 = assertionStatement(sql, "FR-25");
  assert.ok(fr25.includes(" v where app.card_text_canonical(v) is distinct from v $$"), "FR-25 predicate");
  const kept = evaluateRows(`select v from ${/ from (unnest\(array\[[^\]]*\]\)) v where /.exec(fr25)[1]} v`);
  assert.equal(kept.length, 6);
  for (const [index, [v]] of kept.entries()) assert.ok(canonicalText(v) === v, `FR-25 #${index + 1}`);
  checked += spaces.length + kept.length;
  // FR-250 / FR-251: absence equals an empty canonical form over the 24 vectors of _fr_abs.
  const columns = tableColumns(sql, "_fr_abs");
  const rows = statements(sql, "insert into _fr_abs values").flatMap((statement) =>
    evaluateInsert(statement, {}, functions, columns).rows);
  const generated = /\ninsert into _fr_abs\nselect 2 \+ u\.o::integer, 'Zs U\+' \|\| upper\(lpad\(to_hex\(ascii\(u\.z\)\), 4, '0'\)\), u\.z, true\n\s+from (unnest\(array\[[^\]]*\]\)) with ordinality u\(z, o\);/.exec(sql);
  assert.ok(generated, "the Space_Separator rows of _fr_abs are pinned");
  for (const [index, [z]] of evaluateRows(`select z from ${generated[1]} z`).entries()) {
    rows.push({ n: 3 + index, label: `Zs ${hex(z.codePointAt(0))}`, v: z, want: true });
  }
  assert.equal(rows.length, 24, "FR-251");
  for (const row of rows) {
    assert.equal(textAbsent(row.v), row.want, `FR-250 ${row.label}`);
    assert.equal(row.v === null || canonicalText(row.v) === null, row.want, `FR-250 canonical ${row.label}`);
  }
  checked += rows.length;
  // JavaScript-only absence vectors: characters that are not Space_Separators - most of them removed by
  // String.prototype.trim - are never absent (V2-4).
  for (const code of [0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x85, 0x180e, 0x200b, 0xfeff, 0x2028, 0x2029]) {
    assert.equal(textAbsent(chr(code)), false, hex(code));
    assert.ok(canonicalText(chr(code)) !== null, hex(code));
  }
  t.diagnostic(`bound, trim and absence vectors evaluated: ${checked}; FR-246 in ${Math.round(elapsed)} ms of CPU`);
});

test("the SQL evaluator and its ported helpers refuse what PostgreSQL would answer differently (final verification F2-3)", async () => {
  for (const source of ["jsonb_build_object('a', 1)::text", "'x' || jsonb_build_object('a', 1)", "jsonb_build_object(null, 1)",
    "jsonb_build_object(1, 2)", "'{\"a\": 1}'::jsonb::text", "format('%s', true)", "case when null = null then 'a' else 'b' end",
    "case when 1 = '1' then 'a' else 'b' end", "'a' || 1 :: numeric"]) {
    assert.throws(() => evaluate(source), Unsupported, source);
  }
  const functions = vectorFunctions(vectorTables(await sqlText));
  for (const helper of ["pg_temp.fr_c1_d", "pg_temp.fr_c1_mixed"]) {
    assert.throws(() => functions[helper](0), assert.AssertionError, `${helper} count 0`);
    const separatorAt = helper === "pg_temp.fr_c1_d" ? [4, "ascii", 2, null] : [4, null];
    assert.throws(() => functions[helper](...separatorAt), assert.AssertionError, `${helper} NULL separator`);
  }
});

test("canonical form and absence follow app.card_text_canonical / app.card_text_absent", () => {
  assert.equal(canonicalText("\u00a0ABC\u3000"), "ABC");
  assert.equal(canonicalText("\uff21\uff22"), "AB");
  assert.equal(canonicalText("\u2003"), null);
  assert.ok(textAbsent(""));
  assert.ok(textAbsent("\u00a0\u2000\u3000"));
  assert.ok(textAbsent(null));
  assert.ok(!textAbsent("\u200b"), "a format character is not a Space_Separator");
  const sample = "A\u030a\ufb01";
  assert.equal(canonicalText(canonicalText(sample)), canonicalText(sample), "idempotent");
});

test("known limitation (001D packet section 11 item 35): the residual vectors pass both layers", () => {
  // Masked groups joined by dash-like Lo letters or a sideways-I letter, a non-mask asterisk, and a
  // reason made only of modifier letters pass the SQL rule and this one; widening the classes is a
  // separate decision. The ASCII charsets of the provider reference fields refuse those letters. In a
  // structured field the SQL rule treats '-' and '_' as separators, so a truncated card number masked
  // with them passes it too; the provider engine drops a 4-8 digit group, a run of two or more '-' /
  // '_' and 4 digits (single separators between digits removed first) before any RPC (see
  // provider.test.mjs). A bare BIN + last four (at most 11 digits) and a "mask" of one separator stay
  // recorded residuals of both layers (a W1 review item).
  const digits = "1234";
  for (const joiner of ["\u3161", "\u1173", "\ua7f7", "\u2733"]) {
    const value = `${digits}${joiner}${joiner}${"5678"}`;
    assert.equal(safeTextFailure(value, "reason"), null, `U+${joiner.codePointAt(0).toString(16)}`);
    for (const field of ["provider_reference", "approval_number", "voucher_number", "deposit_id", "confirmation_reference"]) {
      assert.equal(safeTextFailure(value, field), "charset", `${field} refuses the residual form`);
    }
  }
  assert.equal(safeTextFailure("\u0640\u0640\u0640", "reason"), null);
  const hyphenMasked = `${"0".repeat(6)}${"-".repeat(3)}${"0".repeat(4)}`;
  const bare = `${"0".repeat(6)}${"0".repeat(4)}`;
  for (const field of ["provider_reference", "deposit_id", "card_brand_code", "pan_entry_mode", "payment_method_code"]) {
    assert.equal(safeTextFailure(hyphenMasked, field), null, `${field}: a hyphen-masked form passes the SQL rule`);
    assert.equal(safeTextFailure(hyphenMasked.replace(/-/g, "_"), field), field.includes("_code") || field === "pan_entry_mode"
      ? null : "charset", `${field}: an underscore-masked form`);
    assert.equal(safeTextFailure(bare, field), null, `${field}: a bare BIN + last four passes`);
  }
});
