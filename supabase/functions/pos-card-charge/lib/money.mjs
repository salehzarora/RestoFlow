// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E: the single decimal boundary (DECISION D-052 point 4,
// D-056 point 9, D-064). Internal amounts are integer minor units carried as canonical token text and
// computed with BigInt only: the outbound lexeme is built by integer division and modulo, and an
// inbound provider amount is accepted only as a raw JSON number token in the bounded inbound grammar,
// right-padded as text to the canonical two-decimal lexeme and converted by integer arithmetic. No
// JavaScript Number, float parse, rounding or locale formatting.
import { JsonNumber } from "./json.mjs";

/** Every amount and cap: 1 .. 99 999 999 999 minor units (the grammar's nine integer digits). */
export const MAX_MINOR = 99999999999n;
/** The canonical two-decimal lexeme: the outbound grammar and the finish rule of API_CONTRACT section 4.55.5. */
export const AMOUNT_LEXEME = /^(0|[1-9][0-9]{0,8})\.[0-9]{2}$/;
/** Inbound provider money (DECISION D-064): 1 to 9 integer digits, JSON's leading-zero rule, 0 to 2 fraction digits. */
export const INBOUND_MONEY_TOKEN = /^(0|[1-9][0-9]{0,8})(?:\.([0-9]{1,2}))?$/;

/** A canonical positive minor-unit token (JsonNumber) within the bound, as BigInt; else null. */
export function minorFromToken(value) {
  if (!(value instanceof JsonNumber) || !/^[1-9][0-9]{0,10}$/.test(value.text)) return null;
  const minor = BigInt(value.text);
  return minor <= MAX_MINOR ? minor : null;
}

/** The canonical two-decimal lexeme of an in-bound minor amount; throws outside the bound. */
export function lexemeFromMinor(minor) {
  if (typeof minor !== "bigint" || minor < 1n || minor > MAX_MINOR) throw new RangeError("amount outside the bound");
  const major = minor / 100n;
  const fraction = minor % 100n;
  const lexeme = `${major}.${fraction < 10n ? "0" : ""}${fraction}`;
  if (!AMOUNT_LEXEME.test(lexeme)) throw new RangeError("amount outside the grammar");
  return lexeme;
}

/** The outbound amount: the lexeme as an unquoted JSON number token. */
export function amountToken(minor) {
  return new JsonNumber(lexemeFromMinor(minor));
}

/** Canonical lexeme text -> minor units (BigInt) when it matches AMOUNT_LEXEME; else null. */
export function minorFromLexeme(text) {
  if (typeof text !== "string" || !AMOUNT_LEXEME.test(text)) return null;
  const [major, fraction] = text.split(".");
  return BigInt(major) * 100n + BigInt(fraction);
}

/**
 * Inbound provider money (DECISION D-064) -> its canonical two-decimal lexeme, or null. Only a raw JSON
 * number token (a JsonNumber) whose text matches INBOUND_MONEY_TOKEN is read - never a string or a
 * JavaScript number - and its fraction is right-padded with zeros (12 -> 12.00, 12.3 -> 12.30,
 * 0 -> 0.00). A sign, an exponent, a third fraction digit or a tenth integer digit gives null: the
 * text is never rounded or truncated.
 */
export function canonicalInboundMoney(value) {
  if (!(value instanceof JsonNumber)) return null;
  const match = INBOUND_MONEY_TOKEN.exec(value.text);
  if (match === null) return null;
  const lexeme = `${match[1]}.${(match[2] ?? "").padEnd(2, "0")}`;
  return AMOUNT_LEXEME.test(lexeme) ? lexeme : null;
}
