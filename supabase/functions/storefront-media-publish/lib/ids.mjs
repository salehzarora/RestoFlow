// STOREFRONT-PUBLISH-001: deterministic per-step idempotency keys.
//
// The Dashboard sends ONE request_id per logical publish and reuses it across
// ladder rungs and retries. The stage and finalize RPCs are idempotent per
// (actor, client_request_id), so the function derives their keys from that one
// id: a retry after an unknown outcome (a killed or timed-out request) replays
// the SAME stage and finalize instead of creating new work.

const hex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');

/** A v5-shaped UUID from sha256("storefront-media-publish:<purpose>:<requestId>"). */
export async function derivedRequestId(requestId, purpose) {
  const data = new TextEncoder().encode(`storefront-media-publish:${purpose}:${requestId}`);
  const b = new Uint8Array(await crypto.subtle.digest('SHA-256', data)).slice(0, 16);
  b[6] = (b[6] & 0x0f) | 0x50; // version 5 (name-based, here with SHA-256)
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  const h = hex(b);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
