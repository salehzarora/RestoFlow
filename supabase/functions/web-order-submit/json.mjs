import { RequestError } from "./errors.mjs";

export const MAX_BODY_BYTES = 32 * 1024;
const MAX_DEPTH = 32;

/** JSON.parse alone silently accepts duplicate keys. Compare decoded keys at every depth. */
export function parseStrictJson(source) {
  let cursor = 0;
  const fail = () => { throw new RequestError("invalid_json"); };
  const space = () => {
    while (cursor < source.length && /[\x20\t\r\n]/.test(source[cursor])) cursor++;
  };
  const string = () => {
    const start = cursor++;
    while (cursor < source.length) {
      const character = source[cursor++];
      if (character === '"') {
        try { return JSON.parse(source.slice(start, cursor)); } catch { fail(); }
      }
      if (character === "\\") cursor++;
    }
    fail();
  };
  const value = (depth) => {
    if (depth > MAX_DEPTH) fail();
    space();
    const character = source[cursor];
    if (character === '"') return string();
    if (character === "{") {
      cursor++;
      space();
      const object = Object.create(null);
      const keys = new Set();
      if (source[cursor] === "}") { cursor++; return object; }
      while (cursor < source.length) {
        if (source[cursor] !== '"') fail();
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
      fail();
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
      fail();
    }
    for (const [literal, result] of [["true", true], ["false", false], ["null", null]]) {
      if (source.startsWith(literal, cursor)) { cursor += literal.length; return result; }
    }
    const number = /-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/y;
    number.lastIndex = cursor;
    const match = number.exec(source);
    if (!match) fail();
    cursor = number.lastIndex;
    const result = Number(match[0]);
    if (!Number.isFinite(result)) fail();
    return result;
  };
  const result = value(0);
  space();
  if (cursor !== source.length) fail();
  return result;
}

/** Enforce the byte limit while streaming, regardless of the declared Content-Length. */
export async function readLimitedBody(message, maxBytes = MAX_BODY_BYTES) {
  const length = message.headers.get("content-length");
  if (length !== null && (!/^\d+$/.test(length) || Number(length) > maxBytes)) {
    throw new RequestError("payload_too_large", 413);
  }
  if (!message.body) return new Uint8Array();
  const reader = message.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        void reader.cancel().catch(() => {});
        throw new RequestError("payload_too_large", 413);
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

export async function readStrictJson(message) {
  const bytes = await readLimitedBody(message);
  let source;
  // A BOM is left intact and rejected by the JSON grammar; invalid UTF-8 is never replaced.
  try { source = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(bytes); }
  catch { throw new RequestError("invalid_json"); }
  return parseStrictJson(source);
}

export async function readRequestJson(request) {
  const type = request.headers.get("content-type") ?? "";
  if (!/^application\/json(?:\s*;\s*charset\s*=\s*(?:utf-8|"utf-8"))?\s*$/i.test(type)) {
    throw new RequestError("unsupported_media_type", 415);
  }
  const encoding = request.headers.get("content-encoding");
  if (encoding !== null && encoding.toLowerCase() !== "identity") {
    throw new RequestError("unsupported_media_type", 415);
  }
  return readStrictJson(request);
}
