// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E constants (execution packet section 5; API_CONTRACT
// sections 4.55.4 and 4.55.5). The 001D claim stamps start_deadline_at = INSERT time + 120 s, up to
// one RPC deadline before its answer reaches the adapter, so the claim's tail, the commit budget and
// one finish call (2 x rpcMs + commitBudgetMs = 110 s) stay below it and below the 150 s request idle
// timeout.
// The commit continues after the start answer only for the worker's REMAINING lifetime (the
// platform wall clock counts from the worker's start and may be far below 150 s / 400 s): that
// continuation is an optimization, never a guarantee; a cut-off commit is recovered by status.
// test/static_guard.test.mjs pins these values and their relations.

export const TIMING = Object.freeze({
  requestMs: 5_000, // reading the POS request body
  rpcMs: 5_000, // each PostgREST call, headers and body
  startWindowMs: 3_000, // how long start waits for an early commit reply before answering 'sent'
  commitBudgetMs: 100_000, // the provider commit call
  lookupMs: 6_000, // one provider status lookup
  releaseMs: 6_000, // one provider release request
});

// Worst-case answer times for 001C's dedicated transport timeout (body read excluded):
//   start 2 x rpc + window = 13 s; status 3 x rpc + lookup = 21 s;
//   release 4 x rpc + release = 26 s; free_order 2 x rpc = 10 s.
export const AUTO_POLL_CAP = 90; // automatic (source='auto') lookups per attempt for a cashier
export const POLL_MIN_INTERVAL_MS = 3_000; // between provider lookups (and releases) of one attempt, database clock

export const LIMITS = Object.freeze({
  requestBytes: 16 * 1024,
  rpcAnswerBytes: 64 * 1024,
  providerReplyBytes: 256 * 1024,
});

export const ROLES = Object.freeze(["cashier", "manager", "restaurant_owner", "org_owner"]);
export const MANAGER_ROLES = Object.freeze(["manager", "restaurant_owner", "org_owner"]);
export const KEY_FORMATS = Object.freeze(["alpha16-l20-v1", "alpha16-l24-v1", "alpha16-l32-v1"]);
export const KEY_LENGTH = Object.freeze({ "alpha16-l20-v1": 20, "alpha16-l24-v1": 24, "alpha16-l32-v1": 32 });

export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export const UUID_V4 = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export const REFERENCE = /^[a-z0-9_-]{1,64}$/;
