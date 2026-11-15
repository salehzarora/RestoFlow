// Fixed-enum bootstrap evidence only. No requests, SQL, credentials, raw error
// text, response bodies or runtime configuration are serialized.
import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { isAuthenticatedReadiness } from './publisher-diagnostics.mjs';

const stages = new Set(['initial', 'a_signup', 'a_organization', 'b_signup', 'b_organization',
  'outsider_signup', 'authenticated_publisher_readiness', 'seed_catalogue', 'a_owner_list', 'b_owner_list',
  'private_original_upload', 'receipt_logo', 'fixture_hero_publish', 'post_publish_fixture_finalize', 'complete']);
const errorTypes = new Set(['Error', 'AssertionError', 'TypeError', 'SyntaxError', 'RangeError', 'AbortError', 'TimeoutError']);
const sqlStates = new Set(['23502', '23503', '23505', '23514', '42501', '42601', '42P01', '42883', '40001', '40P01', '55P03', '57014']);
const assertionStrings = new Set(['published', 'w960', 'true', 'false', 'invalid_request', 'missing', 'not_found', 'permission_denied']);
const integer = (value, maximum) => Number.isInteger(value) && value >= 0 && value <= maximum ? value : null;
const sqlState = value => typeof value === 'string' && sqlStates.has(value) ? value : null;
const assertionValue = value => typeof value === 'boolean' ? value : integer(value, 599)
  ?? (typeof value === 'string' && assertionStrings.has(value) ? value : null);

export function bootstrapFailureEvidence(error) {
  return { errorType: errorTypes.has(error?.name) ? error.name : 'unclassified',
    errorCode: error?.code === 'ERR_ASSERTION' ? 'ERR_ASSERTION' : 'unclassified', sqlState: sqlState(error?.code),
    actual: assertionValue(error?.actual), expected: assertionValue(error?.expected) };
}

export function bootstrapResponseEvidence(result, readiness = false) {
  const value = result?.data;
  const evidence = { httpStatus: integer(result?.status, 599), ok: typeof value?.ok === 'boolean' ? value.ok : null,
    sqlState: sqlState(value?.code) };
  if (readiness) {
    // Match booleans only: even actual field/reason strings remain private.
    const objectBody = value !== null && typeof value === 'object' && !Array.isArray(value);
    evidence.readiness = { matches: isAuthenticatedReadiness(result), http400: result?.status === 400,
      objectBody, exactKeys: objectBody && Object.keys(value).sort().join(',') === 'field,ok,reason,status',
      okFalse: value?.ok === false, invalidRequestStatus: value?.status === 'invalid_request',
      requestIdField: value?.field === 'request_id', missingReason: value?.reason === 'missing' };
  }
  return evidence;
}

export function createBootstrapDiagnostics(publicDir) {
  const receipt = { scope: 'ephemeral synthetic bootstrap', status: 'RUNNING', stage: 'initial', observation: null };
  const flush = () => writeFileSync(resolve(publicDir, 'bootstrap-stage.json'), `${JSON.stringify(receipt, null, 2)}\n`);
  flush();
  return {
    advance(stage) { assert.ok(stages.has(stage), 'Unknown bootstrap diagnostic stage'); receipt.stage = stage; receipt.observation = null; flush(); },
    response(result, readiness = false) { receipt.observation = bootstrapResponseEvidence(result, readiness); flush(); },
    process(result) {
      const match = /(?:\bSQLSTATE[ :]*\(?|\b(?:ERROR|FATAL|PANIC):\s*)([0-9A-Z]{5})\b/.exec(String(result?.stderr ?? ''));
      receipt.observation = { exitCode: integer(result?.status, 255), sqlState: sqlState(match?.[1]) }; flush();
    },
    fail(error) { receipt.status = 'FAIL'; receipt.failure = bootstrapFailureEvidence(error); flush(); },
    complete() { receipt.stage = 'complete'; receipt.status = 'PASS'; receipt.observation = null; flush(); },
  };
}
