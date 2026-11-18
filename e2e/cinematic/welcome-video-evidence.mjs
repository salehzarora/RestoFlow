import { createHash } from 'node:crypto';
import { LOGICAL_ORIGIN } from './live-transport.mjs';

// A real browser response is mandatory. The fixture is independently pinned
// local source content; bytes fetched by the route adapter are never evidence.
export function welcomeVideoResponseEvidence({ url, status, contentRange, body }, source) {
  const u = new URL(url);
  const match = /^\/storage\/v1\/object\/public\/storefront-welcome-videos\/[0-9a-f]{32}\/([0-9a-f]{64})\.mp4$/.exec(u.pathname);
  if (!match || u.origin !== LOGICAL_ORIGIN || u.username || u.password || url !== u.href || u.search || u.hash || !Buffer.isBuffer(body) || !Buffer.isBuffer(source) || source.length < 1)
    throw new Error('welcome_video_browser_evidence_invalid');
  const hash = bytes => createHash('sha256').update(bytes).digest('hex');
  if (hash(source) !== match[1]) throw new Error('welcome_video_source_identity_mismatch');
  let first = 0, last = source.length - 1;
  if (status === 206) {
    const range = /^bytes (0|[1-9][0-9]*)-(0|[1-9][0-9]*)\/(0|[1-9][0-9]*)$/.exec(contentRange ?? '');
    if (!range || Number(range[3]) !== source.length) throw new Error('welcome_video_range_invalid');
    first = Number(range[1]); last = Number(range[2]);
    if (!Number.isSafeInteger(first) || !Number.isSafeInteger(last) || first > last || last >= source.length)
      throw new Error('welcome_video_range_invalid');
  } else if (status !== 200 || contentRange) throw new Error('welcome_video_status_invalid');
  const expected = source.subarray(first, last + 1);
  if (body.length !== expected.length || !body.equals(expected)) throw new Error('welcome_video_browser_bytes_mismatch');
  return { status, first, last, total: source.length, bytes: body.length, sha256: hash(body) };
}
export function welcomeVideoCoverage(receipts, total) {
  if (!Number.isInteger(total) || total < 1 || !Array.isArray(receipts) || receipts.length === 0) return false;
  let next = 0;
  for (const value of [...receipts].sort((a,b) => a.first - b.first)) {
    if (!value || value.total !== total || !Number.isInteger(value.first) || !Number.isInteger(value.last) || value.first < 0 || value.first > next || value.last < value.first || value.last >= total || value.bytes !== value.last-value.first+1 || !/^[0-9a-f]{64}$/.test(value.sha256 ?? '') || ![200,206].includes(value.status)) return false;
    next = Math.max(next, value.last + 1);
  }
  return next === total;
}
