// A small, closed evaluator for the literal SQL that supabase/tests/bizbot_zcredit_001d_field_rules_test.sql
// builds its text-policy vectors with, so this suite applies the SAME vectors (DECISION D-059 point 4)
// with no database and without copying a vector value into JavaScript. It covers exactly what that
// file uses: string and U&'...' literals, integers, null / true / false, ||, casts to text, jsonb and
// integer, a few functions, alias.column references, a one-comparison CASE, VALUES lists,
// unnest(array[...]) and SELECT [DISTINCT] ... FROM ... [CROSS JOIN [LATERAL] ...] [ORDER BY ...]
// [UNION ALL ...], plus pgTAP is() / results_eq() statements. Anything else - and the constructs whose
// PostgreSQL meaning differs from JavaScript's that this file could meet (a CASE on NULL or mixed
// types, a non-text format argument, || or ::text over a non-scalar, a NULL jsonb key) - throws
// Unsupported, so no vector is skipped and none of those is evaluated silently wrong.

export class Unsupported extends Error {}

const fail = (what) => { throw new Unsupported(what); };

/** PostgreSQL U&'...' escapes: \XXXX, \+XXXXXX and \\ (the default escape character). */
function unescapeUnicode(text) {
  return text.replace(/\\(\\|\+[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4})/g, (_, escape) => (escape === "\\" ? "\\"
    : String.fromCodePoint(Number.parseInt(escape.replace("+", ""), 16))));
}

const WHITESPACE = /\s+/y;
const COMMENT = /--[^\n]*/y;
const NUMBER = /[0-9]+/y;
const NAME = /[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?/y;

/** Tokens: { kind: "string" | "number" | "name" | "punct", value }; names are lower-cased. */
export function tokenize(source) {
  const tokens = [];
  const at = (regex, index) => { regex.lastIndex = index; return regex.exec(source); };
  let i = 0;
  while (i < source.length) {
    let match = at(WHITESPACE, i) ?? at(COMMENT, i);
    if (match) { i += match[0].length; continue; }
    const c = source[i];
    const unicode = (c === "U" || c === "u") && source[i + 1] === "&" && source[i + 2] === "'";
    if (c === "'" || unicode) {
      i += unicode ? 3 : 1;
      let text = "";
      for (;;) {
        if (i >= source.length) fail("an unterminated literal");
        if (source[i] === "'") {
          if (source[i + 1] === "'") { text += "'"; i += 2; continue; }
          i++;
          break;
        }
        text += source[i++];
      }
      tokens.push({ kind: "string", value: unicode ? unescapeUnicode(text) : text });
      continue;
    }
    if ((match = at(NUMBER, i))) { tokens.push({ kind: "number", value: Number(match[0]) }); i += match[0].length; continue; }
    if ((match = at(NAME, i))) { tokens.push({ kind: "name", value: match[0].toLowerCase() }); i += match[0].length; continue; }
    const two = source.slice(i, i + 2);
    if (two === "||" || two === "::") { tokens.push({ kind: "punct", value: two }); i += 2; continue; }
    if ("(),=[]".includes(c)) { tokens.push({ kind: "punct", value: c }); i++; continue; }
    fail(`the character ${JSON.stringify(c)}`);
  }
  return tokens;
}

const KEYWORDS = new Set(["select", "distinct", "from", "cross", "join", "lateral", "values", "union", "all", "order", "by",
  "where", "as", "case", "when", "then", "else", "end", "null", "true", "false", "array", "unnest", "insert", "into", "desc",
  "asc", "on", "group", "limit"]);

/** The SQL functions the vector file uses, evaluated as PostgreSQL does for these inputs. */
const BUILTINS = {
  repeat: (text, count) => (text === null ? null : text.repeat(count)),
  left: (text, count) => (text === null ? null : [...text].slice(0, count).join("")),
  chr: (code) => String.fromCodePoint(code),
  rtrim: (text, set) => {
    const points = [...text];
    const strip = new Set(set);
    while (points.length > 0 && strip.has(points[points.length - 1])) points.pop();
    return points.join("");
  },
  format: (pattern, ...args) => {
    if (/%[^s]/.test(pattern.replace(/%s/g, ""))) fail("a format directive");
    // PostgreSQL prints booleans as t / f and NULL as an empty string: only text and integers are taken here.
    if (!args.every((arg) => typeof arg === "string" || Number.isInteger(arg))) fail("a format argument that is not text");
    let index = 0;
    return pattern.replace(/%s/g, () => String(args[index++] ?? ""));
  },
  char_length: (text) => (text === null ? null : [...text].length),
  jsonb_build_object: (...pairs) => {
    if (pairs.length % 2 !== 0) fail("an odd jsonb_build_object argument list");
    const out = {};
    for (let i = 0; i < pairs.length; i += 2) {
      if (typeof pairs[i] !== "string") fail("a jsonb_build_object key that is not text");
      out[pairs[i]] = pairs[i + 1];
    }
    return out;
  },
  make_date: (year, month, day) => ({ year, month, day, hour: 0, minute: 0 }),
  make_timestamp: (year, month, day, hour, minute) => ({ year, month, day, hour, minute }),
  to_char: (value, pattern) => {
    const pad = (n, width = 2) => String(n).padStart(width, "0");
    const date = `${pad(value.year, 4)}-${pad(value.month)}-${pad(value.day)}`;
    if (pattern === "YYYY-MM-DD") return date;
    if (pattern === "YYYY-MM-DD HH24:MI") return `${date} ${pad(value.hour)}:${pad(value.minute)}`;
    return fail(`to_char ${pattern}`);
  },
};

class Parser {
  constructor(tokens, functions) {
    this.tokens = tokens;
    this.i = 0;
    this.functions = functions;
  }

  peek(offset = 0) { return this.tokens[this.i + offset]; }
  isName(value, offset = 0) { const t = this.peek(offset); return t?.kind === "name" && t.value === value; }
  isPunct(value, offset = 0) { const t = this.peek(offset); return t?.kind === "punct" && t.value === value; }
  name(value) { if (!this.isName(value)) fail(`${value} at token ${this.i}`); this.i++; }
  punct(value) { if (!this.isPunct(value)) fail(`${value} at token ${this.i}`); this.i++; }
  identifier() {
    const t = this.peek();
    if (t?.kind !== "name" || KEYWORDS.has(t.value) || t.value.includes(".")) fail(`an identifier at token ${this.i}`);
    this.i++;
    return t.value;
  }

  list(parse) {
    const out = [parse()];
    while (this.isPunct(",")) { this.i++; out.push(parse()); }
    return out;
  }

  expr() {
    let node = this.term();
    while (this.isPunct("||")) {
      this.i++;
      const left = node;
      const right = this.term();
      node = (env) => {
        const a = left(env);
        const b = right(env);
        if ([a, b].some((value) => value !== null && typeof value === "object")) fail("|| over a non-scalar value");
        return a === null || b === null ? null : `${a}${b}`;
      };
    }
    return node;
  }

  term() {
    let node = this.primary();
    while (this.isPunct("::")) {
      this.i++;
      const type = this.identifier();
      const inner = node;
      if (type === "text") {
        node = (env) => {
          const value = inner(env);
          if (value !== null && typeof value === "object") fail("a text cast of a non-scalar value");
          return value === null ? null : String(value);
        };
      } else if (type === "jsonb") {
        node = (env) => {
          const value = inner(env);
          if (typeof value !== "string") fail("a jsonb cast of a non-text value");
          return JSON.parse(value);
        };
      } else if (type === "integer" || type === "bigint") {
        node = (env) => {
          const value = inner(env);
          if (value !== null && !Number.isInteger(value)) fail(`a ${type} cast of a non-integer value`);
          return value;
        };
      } else {
        fail(`a cast to ${type}`);
      }
    }
    return node;
  }

  primary() {
    const t = this.peek();
    if (!t) fail("the end of the input");
    if (t.kind === "string" || t.kind === "number") { this.i++; return () => t.value; }
    if (this.isPunct("(")) {
      this.i++;
      const inner = this.expr();
      this.punct(")");
      return inner;
    }
    if (t.kind !== "name") fail(`${t.value} at token ${this.i}`);
    if (t.value === "null") { this.i++; return () => null; }
    if (t.value === "true" || t.value === "false") { this.i++; return () => t.value === "true"; }
    if (t.value === "case") return this.caseExpr();
    if (this.isPunct("(", 1)) {
      this.i += 2;
      const fn = Object.hasOwn(BUILTINS, t.value) ? BUILTINS[t.value]
        : Object.hasOwn(this.functions, t.value) ? this.functions[t.value] : fail(`the function ${t.value}`);
      const args = this.isPunct(")") ? [] : this.list(() => this.expr());
      this.punct(")");
      return (env) => fn(...args.map((arg) => arg(env)));
    }
    if (KEYWORDS.has(t.value)) fail(`the keyword ${t.value} at token ${this.i}`);
    this.i++;
    return (env) => column(env, t.value);
  }

  caseExpr() {
    this.name("case");
    this.name("when");
    const left = this.expr();
    this.punct("=");
    const right = this.expr();
    this.name("then");
    const then = this.expr();
    let otherwise = () => null;
    if (this.isName("else")) { this.i++; otherwise = this.expr(); }
    this.name("end");
    return (env) => {
      const a = left(env);
      const b = right(env);
      // PostgreSQL's three-valued and typed comparison differs from === for NULL and mixed types.
      if (a === null || b === null || typeof a !== typeof b) fail("a CASE comparison with NULL or mixed types");
      return a === b ? then(env) : otherwise(env);
    };
  }

  /** VALUES (...), (...): each row a list of expressions. */
  values() {
    this.name("values");
    return { kind: "values", rows: this.list(() => { this.punct("("); const row = this.list(() => this.expr()); this.punct(")"); return row; }) };
  }

  /** SELECT [DISTINCT] items FROM sources [UNION ALL SELECT ...] [ORDER BY ...]. */
  query() {
    const parts = [this.select()];
    while (this.isName("union")) { this.i++; this.name("all"); parts.push(this.select()); }
    if (this.isName("order")) {
      // ORDER BY only orders the rows; every vector is evaluated on its own.
      this.i++;
      this.name("by");
      while (this.i < this.tokens.length && !this.isPunct(")")) this.i++;
    }
    return { kind: "query", parts };
  }

  select() {
    this.name("select");
    let distinct = false;
    if (this.isName("distinct")) { this.i++; distinct = true; }
    const items = this.list(() => {
      const t = this.peek();
      const start = this.i;
      const expr = this.expr();
      // A bare column reference names its output column; any other expression needs AS.
      let name = this.i === start + 1 && t.kind === "name" && !KEYWORDS.has(t.value) ? t.value.split(".").pop() : null;
      if (this.isName("as")) { this.i++; name = this.identifier(); }
      return { expr, name };
    });
    this.name("from");
    const sources = [this.source()];
    while (this.isName("cross")) {
      this.i++;
      this.name("join");
      if (this.isName("lateral")) this.i++;
      sources.push(this.source());
    }
    if (this.isName("where") || this.isName("group") || this.isName("limit") || this.isName("on")) {
      fail("a WHERE, GROUP BY, LIMIT or ON clause");
    }
    return { distinct, items, sources };
  }

  source() {
    if (this.isName("unnest")) {
      this.i++;
      this.punct("(");
      this.name("array");
      this.punct("[");
      const items = this.list(() => this.expr());
      this.punct("]");
      this.punct(")");
      return { kind: "unnest", items, alias: this.identifier() };
    }
    if (this.isPunct("(")) {
      this.i++;
      const inner = this.isName("values") ? this.values() : this.query();
      this.punct(")");
      const alias = this.identifier();
      let columns = null;
      if (this.isPunct("(")) { this.i++; columns = this.list(() => this.identifier()); this.punct(")"); }
      return { kind: "derived", inner, alias, columns };
    }
    const table = this.peek();
    if (table?.kind !== "name" || KEYWORDS.has(table.value)) fail(`a table at token ${this.i}`);
    this.i++;
    const next = this.peek();
    const aliased = next?.kind === "name" && !KEYWORDS.has(next.value) && !next.value.includes(".");
    return { kind: "table", table: table.value, alias: aliased ? this.identifier() : table.value };
  }
}

/** alias.column, or a bare column name that exactly one source provides. */
function column(env, name) {
  if (name.includes(".")) {
    if (!Object.hasOwn(env, name)) fail(`the column ${name}`);
    return env[name];
  }
  const keys = Object.keys(env).filter((key) => key.endsWith(`.${name}`));
  if (keys.length !== 1) fail(`the column ${name}`);
  return env[keys[0]];
}

function rowsOf(node, env, tables) {
  if (node.kind === "values") return node.rows.map((row) => row.map((expr) => expr(env)));
  return runQuery(node, env, tables).map((row) => row.values);
}

function* sourceRows(source, env, tables) {
  if (source.kind === "table") {
    if (!Object.hasOwn(tables, source.table)) fail(`the table ${source.table}`);
    for (const row of tables[source.table]) {
      yield Object.fromEntries(Object.entries(row).map(([key, value]) => [`${source.alias}.${key}`, value]));
    }
  } else if (source.kind === "unnest") {
    for (const item of source.items) yield { [`${source.alias}.${source.alias}`]: item(env) };
  } else {
    const names = source.columns ?? (source.inner.kind === "query" ? source.inner.parts[0].items.map((item) => item.name) : null);
    if (!names || names.some((name) => name === null)) fail("an unnamed derived column");
    for (const row of rowsOf(source.inner, env, tables)) {
      if (row.length !== names.length) fail("a derived row of the wrong width");
      yield Object.fromEntries(row.map((value, index) => [`${source.alias}.${names[index]}`, value]));
    }
  }
}

function* product(sources, env, tables) {
  if (sources.length === 0) { yield env; return; }
  const [first, ...rest] = sources;
  for (const row of sourceRows(first, env, tables)) yield* product(rest, { ...env, ...row }, tables);
}

function runQuery(query, env, tables) {
  const out = [];
  for (const part of query.parts) {
    const seen = new Set();
    for (const scope of product(part.sources, env, tables)) {
      const values = part.items.map((item) => item.expr(scope));
      if (part.distinct) {
        const key = JSON.stringify(values);
        if (seen.has(key)) continue;
        seen.add(key);
      }
      out.push({ values });
    }
  }
  return out;
}

/** Evaluate one SQL expression (no column references). */
export function evaluate(source, functions = {}) {
  const parser = new Parser(tokenize(source), functions);
  const value = parser.expr()({});
  if (parser.i !== parser.tokens.length) fail("trailing tokens");
  return value;
}

/** Evaluate `values (...), (...)` or a SELECT query: an array of rows (arrays of values). */
export function evaluateRows(source, tables = {}, functions = {}) {
  const parser = new Parser(tokenize(source), functions);
  const node = parser.isName("values") ? parser.values() : parser.query();
  if (parser.i !== parser.tokens.length) fail("trailing tokens");
  return rowsOf(node, {}, tables);
}

/** `insert into <table> [(<columns>)] <values | query>`: { table, columns, rows } with rows as objects. */
export function evaluateInsert(statement, tables = {}, functions = {}, defaultColumns = null) {
  const parser = new Parser(tokenize(statement), functions);
  parser.name("insert");
  parser.name("into");
  const table = parser.identifier();
  let columns = defaultColumns;
  if (parser.isPunct("(")) { parser.i++; columns = parser.list(() => parser.identifier()); parser.punct(")"); }
  const node = parser.isName("values") ? parser.values() : parser.query();
  if (parser.i !== parser.tokens.length) fail("trailing tokens");
  if (!columns) fail("an insert without a column list");
  const rows = rowsOf(node, {}, tables);
  if (rows.some((row) => row.length !== columns.length)) fail("a row of the wrong width");
  return { table, columns, rows: rows.map((row) => Object.fromEntries(row.map((value, index) => [columns[index], value]))) };
}

/**
 * Every top-level statement of `sql` that starts with `prefix` at a line start, up to its
 * terminating semicolon (outside literals, comments and parentheses).
 */
export function statements(sql, prefix) {
  const out = [];
  let from = 0;
  for (;;) {
    const start = sql.indexOf(`\n${prefix}`, from);
    if (start < 0) return out;
    let depth = 0;
    let quoted = false;
    let end = -1;
    for (let i = start + 1; i < sql.length; i++) {
      const c = sql[i];
      if (quoted) {
        if (c === "'") { if (sql[i + 1] === "'") i++; else quoted = false; }
        continue;
      }
      if (c === "'") quoted = true;
      else if (c === "-" && sql[i + 1] === "-") { while (i < sql.length && sql[i] !== "\n") i++; }
      else if (c === "(") depth++;
      else if (c === ")") depth--;
      else if (c === ";" && depth === 0) { end = i; break; }
    }
    if (end < 0) fail("an unterminated statement");
    out.push(sql.slice(start + 1, end));
    from = end;
  }
}

/** The column names of `create temp table <name> (<column> <type> ..., ...)`. */
export function tableColumns(sql, name) {
  const match = new RegExp(`\\ncreate temp table ${name} \\(([^;]*?)\\);`).exec(sql);
  if (!match) fail(`the table definition of ${name}`);
  return match[1].split(/,(?![^(]*\))/).map((part) => part.trim().split(/\s+/)[0]).filter((word) => word !== "primary");
}

/** The pgTAP statement whose description starts with `label`: from its `select` to its description line. */
export function assertionStatement(sql, label) {
  const at = sql.indexOf(`'${label} `);
  if (at < 0) fail(`the assertion ${label}`);
  const start = sql.lastIndexOf("\nselect ", at);
  const end = sql.indexOf("\n", at);
  if (start < 0 || end < 0) fail(`the statement of ${label}`);
  return sql.slice(start + 1, end);
}

/** `select is(<actual>, <expected>, '<label>');` evaluated with `functions`: [actual, expected]. */
export function evaluateIs(statement, functions = {}) {
  const match = /^select (is\([\s\S]*\));$/.exec(statement.trim());
  if (!match) fail("an is() statement");
  return evaluate(match[1], { ...functions, is: (actual, expected) => [actual, expected] });
}

/** `select results_eq($$ <query> $$, $$ <values> $$, '<label>');` evaluated: [actual rows, expected rows]. */
export function evaluateResultsEq(statement, tables = {}, functions = {}) {
  const match = /^select results_eq\(\$\$([\s\S]*?)\$\$,\s*\$\$([\s\S]*?)\$\$,\s*'/.exec(statement.trim());
  if (!match) fail("a results_eq() statement");
  return [evaluateRows(match[1], tables, functions), evaluateRows(match[2], tables, functions)];
}

/** The expected `$$ values ... $$` block of the pgTAP assertion whose description starts with `label`. */
export function expectedValues(sql, label, tables = {}, functions = {}) {
  const at = sql.indexOf(`'${label} `);
  if (at < 0) fail(`the assertion ${label}`);
  const open = sql.lastIndexOf("$$ values", at);
  const close = open < 0 ? -1 : sql.indexOf("$$", open + 2);
  if (open < 0 || close < 0 || close > at) fail(`the expected values of ${label}`);
  return evaluateRows(sql.slice(open + 2, close), tables, functions);
}
