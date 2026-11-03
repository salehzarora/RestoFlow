// Test-only Auth evidence. Reduce transient request/response data to primitives
// and fixed enums before retaining it. Never serialize credentials, tokens,
// messages, headers, URLs, paths or whole request/response objects.
const grantTypes = new Set(['password', 'refresh_token', 'pkce', 'id_token']);
const mimeTypes = new Set(['application/json', 'text/plain', 'text/html']);
const authCodes = new Set(['invalid_credentials', 'email_not_confirmed',
  'email_provider_disabled', 'user_banned', 'over_request_rate_limit',
  'over_email_send_rate_limit', 'captcha_failed', 'bad_json', 'validation_failed',
  'request_timeout', 'unexpected_failure', 'no_authorization', 'bad_jwt']);
const oauthCodes = new Set(['invalid_grant', 'invalid_request', 'unauthorized_client',
  'unsupported_grant_type', 'server_error', 'temporarily_unavailable']);
const fixed = (value, allowed) => value === undefined || value === null || value === ''
  ? 'missing' : typeof value === 'string' && allowed.has(value) ? value : 'unclassified';
const object = value => value !== null && typeof value === 'object' && !Array.isArray(value) ? value : {};

function grantType(url) {
  try {
    const values = new URL(url).searchParams.getAll('grant_type');
    return values.length === 0 ? 'missing' : values.length === 1 ? fixed(values[0], grantTypes) : 'unclassified';
  } catch { return 'unclassified'; }
}

export function isPasswordGrantRequest(url, method, apiOrigin) {
  try {
    const u = new URL(url);
    return method === 'POST' && u.origin === apiOrigin && !u.username && !u.password
      && u.pathname === '/auth/v1/token' && grantType(url) === 'password';
  } catch { return false; }
}

export function authRequestEvidence(url, postData, expected) {
  let body = {};
  try { body = object(JSON.parse(postData)); } catch { /* No raw parse error retained. */ }
  return {
    grantType: grantType(url),
    submittedEmailMatchesFixture: typeof body.email === 'string'
      && typeof expected?.email === 'string' && expected.email.length > 0 && body.email === expected.email,
    submittedPasswordMatchesFixture: typeof body.password === 'string'
      && typeof expected?.password === 'string' && expected.password.length > 0 && body.password === expected.password,
  };
}

export function authResponseEvidence(result, durationMs) {
  const data = object(result?.data);
  const mime = typeof result?.contentType === 'string' ? result.contentType.split(';')[0].trim().toLowerCase() : '';
  return {
    httpStatus: Number.isInteger(result?.status) && result.status >= 100 && result.status <= 599 ? result.status : null,
    contentType: fixed(mime, mimeTypes),
    errorCode: fixed(data.error_code ?? data.code, authCodes),
    oauthError: fixed(data.error, oauthCodes),
    durationMs: Number.isFinite(durationMs) && durationMs >= 0 && durationMs <= 120_000 ? Math.round(durationMs) : null,
  };
}
