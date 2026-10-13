import { invalid } from './validation';

/** JSON.parse permits duplicate keys. Check decoded keys, depth and grammar first. */
export function parseOrderJson(source: string): unknown {
  let cursor = 0;
  const space = () => { while (cursor < source.length && /[\x20\t\r\n]/.test(source[cursor])) cursor++; };
  const string = (): string => {
    const start = cursor++;
    while (cursor < source.length) {
      const character = source[cursor++];
      if (character === '"') {
        try { return JSON.parse(source.slice(start, cursor)) as string; } catch { invalid(); }
      }
      if (character === '\\') cursor++;
    }
    return invalid();
  };
  const value = (depth: number): unknown => {
    if (depth > 16) invalid();
    space();
    const character = source[cursor];
    if (character === '"') return string();
    if (character === '{') {
      cursor++; space();
      const object: Record<string, unknown> = Object.create(null);
      const keys = new Set<string>();
      if (source[cursor] === '}') { cursor++; return object; }
      while (cursor < source.length) {
        if (source[cursor] !== '"') invalid();
        const key = string();
        if (keys.has(key)) invalid();
        keys.add(key); space();
        if (source[cursor++] !== ':') invalid();
        object[key] = value(depth + 1); space();
        const separator = source[cursor++];
        if (separator === '}') return object;
        if (separator !== ',') invalid();
        space();
      }
      return invalid();
    }
    if (character === '[') {
      cursor++; space();
      const array: unknown[] = [];
      if (source[cursor] === ']') { cursor++; return array; }
      while (cursor < source.length) {
        array.push(value(depth + 1)); space();
        const separator = source[cursor++];
        if (separator === ']') return array;
        if (separator !== ',') invalid();
      }
      return invalid();
    }
    if (source.startsWith('true', cursor)) { cursor += 4; return true; }
    if (source.startsWith('false', cursor)) { cursor += 5; return false; }
    if (source.startsWith('null', cursor)) { cursor += 4; return null; }
    const number = /-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?/y;
    number.lastIndex = cursor;
    const match = number.exec(source);
    if (!match) invalid();
    cursor = number.lastIndex;
    const result = Number(match[0]);
    if (!Number.isFinite(result)) invalid();
    return result;
  };
  const result = value(0); space();
  if (cursor !== source.length) invalid();
  return result;
}
