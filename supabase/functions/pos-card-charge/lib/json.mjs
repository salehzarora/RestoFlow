// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: strict JSON with number tokens kept as text.
//
// Every JSON this function reads (the POS request, PostgREST answers, provider replies) is parsed
// here: duplicate keys at any depth, lone surrogates and trailing data are refused, and a number
// is never converted to a JavaScript Number — it stays a JsonNumber holding its exact token
// text, so no money value is ever rounded or reformatted (DECISION D-052 point 4). The writer
// emits a JsonNumber as that raw, unquoted token and refuses a JavaScript number outright.

const NUMBER_TOKEN = /^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$/;

/** A JSON number token, kept as its exact text. */
export class JsonNumber {
  #text;
  constructor(text) {
    if (typeof text !== "string" || !NUMBER_TOKEN.test(text)) throw new TypeError("not a JSON number token");
    this.#text = text;
    Object.freeze(this);
  }
  get text() { return this.#text; }
}

export class JsonError extends Error {}

const fail = () => { throw new JsonError("invalid_json"); };

/** Parse one JSON document. Objects have a null prototype; numbers are JsonNumber. */
export function parseJson(source, { maxDepth = 16 } = {}) {
  if (typeof source !== "string") fail();
  let cursor = 0;
  const space = () => {
    while (cursor < source.length && (source[cursor] === " " || source[cursor] === "\t"
      || source[cursor] === "\n" || source[cursor] === "\r")) cursor++;
  };
  const string = () => {
    const start = cursor++;
    while (cursor < source.length) {
      const character = source[cursor++];
      if (character === "\"") {
        let decoded;
        try { decoded = JSON.parse(source.slice(start, cursor)); } catch { fail(); }
        if (!decoded.isWellFormed()) fail();
        return decoded;
      }
      if (character === "\\") cursor++;
    }
    return fail();
  };
  const value = (depth) => {
    if (depth > maxDepth) fail();
    space();
    const character = source[cursor];
    if (character === "\"") return string();
    if (character === "{") {
      cursor++;
      space();
      const object = Object.create(null);
      const keys = new Set();
      if (source[cursor] === "}") { cursor++; return object; }
      while (cursor < source.length) {
        if (source[cursor] !== "\"") fail();
        const key = string();
        if (keys.has(key)) fail();
        keys.add(key);
        space();
        if (source[cursor++] !== ":") fail();
        object[key] = value(depth + 1);
        space();
        const separator = source[cursor++];
        if (separator === "}") return object;
        if (separator !== ",") fail();
        space();
      }
      return fail();
    }
    if (character === "[") {
      cursor++;
      space();
      const array = [];
      if (source[cursor] === "]") { cursor++; return array; }
      while (cursor < source.length) {
        array.push(value(depth + 1));
        space();
        const separator = source[cursor++];
        if (separator === "]") return array;
        if (separator !== ",") fail();
      }
      return fail();
    }
    for (const [literal, result] of [["true", true], ["false", false], ["null", null]]) {
      if (source.startsWith(literal, cursor)) { cursor += literal.length; return result; }
    }
    const number = /-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?/y;
    number.lastIndex = cursor;
    const match = number.exec(source);
    if (!match) fail();
    cursor = number.lastIndex;
    return new JsonNumber(match[0]);
  };
  const result = value(0);
  space();
  if (cursor !== source.length) fail();
  return result;
}

/** A plain JSON object (parsed or literal), never an array, null or a JsonNumber. */
export function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value) && !(value instanceof JsonNumber);
}

/** Serialize: JsonNumber raw, strings, booleans, null, arrays and plain objects only. */
export function stringifyJson(value) {
  if (value instanceof JsonNumber) return value.text;
  if (value === null) return "null";
  if (value === true) return "true";
  if (value === false) return "false";
  if (typeof value === "string") {
    if (!value.isWellFormed()) throw new TypeError("not well-formed text");
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) return `[${value.map(stringifyJson).join(",")}]`;
  if (isObject(value)) {
    return `{${Object.keys(value).map((key) => {
      if (value[key] === undefined) throw new TypeError("undefined member");
      return `${JSON.stringify(key)}:${stringifyJson(value[key])}`;
    }).join(",")}}`;
  }
  throw new TypeError("unsupported JSON value");
}

/** An integer token in a closed range, as its canonical text (no sign for 0, no exponent). */
export function integerText(value, min, max) {
  if (!(value instanceof JsonNumber) || !/^-?(?:0|[1-9][0-9]{0,15})$/.test(value.text)) return null;
  const parsed = BigInt(value.text);
  return parsed >= BigInt(min) && parsed <= BigInt(max) && value.text !== "-0" ? value.text : null;
}
