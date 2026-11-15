// Passive observation of this test page's existing publisher POST.
// No application or transport hook; no Response.json replacement; no acceptance override.
import { createHash } from 'node:crypto';
import type { Page, Request, Response, CDPSession } from '@playwright/test';

type Slot = 'hero' | 'background' | 'item' | 'product';
type Terminal = 'pending' | 'finished' | 'failed';
type StreamState = 'pending' | 'enabled' | 'finished-before-enable' | 'missing-resource' | 'command-failed';
type Parse = 'unread' | 'object' | 'non-object' | 'invalid-json' | 'invalid-utf8';
type Identity = { hash: string; bodyHash: string; slot: Slot; key: string };
type Pw = { identity: Identity; sequence: number; requestMs: number; terminal: Terminal; terminalMs: number | null; http: number | null; failureCode: string | null };
type Native = { ordinal: number; identity: Identity; sequence: number;
  frame: string; document: string; context: string | null; navigationEpoch: number; contextEpoch: number;
  requestMs: number; responseMs: number | null; terminalMs: number | null; terminal: Terminal; http: number | null;
  failureCode: string | null; canceled: boolean | null; corsFailure: boolean; blockedReason: string | null;
  stream: StreamState; ack: boolean; prefix: Buffer | null; chunks: Buffer[]; bytes: number;
  bufferedBytes: number; streamedBytes: number; observedDataLength: number; chunkCount: number;
  digest: string | null; canonicalDigest: string | null; parse: Parse; problems: string[]; pw: Pw | null };
export type PublisherObservationOptions = { apiOrigin: string; deadlineAt: number; expectedSlot?: Slot; now?: () => number };
export type PublisherNativeObservation = { snapshot(): Record<string, unknown>;
  firstError(boundary: 'publisher-body' | 'upload-assertion' | 'probe-assertion'): void;
  cleanup(boundary: 'upload-finally' | 'probe-finally'): void;
  assertComplete(response: Response, parsedBody: unknown): Promise<void>; stop(): Promise<void> };
const BYTE_CAP = 64 * 1024, REQUEST_CAP = 8, CHUNK_CAP = 1024;
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/;
const slots = new Set(['hero', 'background', 'item', 'product']);
const endpoint = '/functions/v1/storefront-media-publish';
const sha = (value: string | Buffer) => createHash('sha256').update(value).digest('hex');
const networkCode = (value: unknown) => typeof value === 'string' && /^net::ERR_[A-Z_0-9]{1,64}$/.test(value) ? value : 'unclassified';
const blockedReasons = new Set(['other', 'csp', 'mixed-content', 'origin', 'inspector', 'subresource-filter', 'content-type', 'coep-frame-resource-needs-coep-header', 'coop-sandboxed-iframe-cannot-navigate-to-coop-page', 'corp-not-same-origin', 'corp-not-same-origin-after-defaulted-to-same-origin-by-coep', 'corp-not-same-site']);
function identity(text: string | null | undefined, expected?: Slot): Identity | null {
  // Read only the two permitted correlation fields; never retain/export the body.
  if (typeof text !== 'string' || Buffer.byteLength(text) > 4096) return null;
  try {
    const value = JSON.parse(text);
    if (!value || !UUID.test(value.request_id) || !slots.has(value.slot) || (expected && value.slot !== expected)) return null;
    const hash = sha(value.request_id), bodyHash = sha(text), slot = value.slot as Slot;
    return { hash, bodyHash, slot, key: `${hash}:${bodyHash}:${slot}` };
  } catch { return null; }
}
function fixedProtocolError(error: unknown): StreamState {
  // Message is examined transiently and is never included in returned evidence.
  const text = error instanceof Error ? error.message : '';
  if (text.includes('already finished loading')) return 'finished-before-enable';
  if (text.includes('provided ID') && (text.includes('not exist') || text.includes('not exists'))) return 'missing-resource';
  return 'command-failed';
}
function decoded(data: unknown): Buffer | null {
  if (typeof data !== 'string' || data.length > Math.ceil(BYTE_CAP / 3) * 4 ||
      !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(data)) return null;
  return Buffer.from(data, 'base64');
}
export function completeNativeBody(fact: { terminal: Terminal; stream: StreamState; problems: readonly string[];
  bytes: number; parse: Parse; paired: boolean }): boolean {
  // Diagnostic completeness only. This is NOT a publication/Edge acceptance gate.
  return fact.terminal === 'finished' && fact.stream === 'enabled' && fact.problems.length === 0 &&
    fact.bytes > 0 && fact.bytes <= BYTE_CAP && fact.parse === 'object' && fact.paired;
}
export async function observePublisherNative(page: Page, options: PublisherObservationOptions): Promise<PublisherNativeObservation> {
  const now = options.now ?? Date.now, began = now();
  if (options.apiOrigin !== 'http://127.0.0.1:54321' || !Number.isFinite(options.deadlineAt) ||
      options.deadlineAt <= began || options.deadlineAt - began > 120_000) throw new Error('Invalid bounded local publisher observation');
  let session: CDPSession | null = null, stopped = false, stoppedAt: number | null = null, deadlineExceeded = false, unavailable = false;
  let navigationEpoch = 0, contextEpoch = 0, contextOrdinal = 0, requestOverflow = 0, invalidIdentity = 0;
  let first: { boundary: string; ms: number } | null = null, cleanup: { boundary: string; ms: number } | null = null;
  const events: { event: string; ms: number }[] = [], records: Native[] = [];
  const natives = new Map<string, Native>(), nativeKeys = new Map<string, Native[]>(), pwKeys = new Map<string, Pw[]>();
  const requests = new WeakMap<Request, Pw>(), frames = new Map<string, string>(), documents = new Map<string, string>();
  const contexts = new Map<number, { label: string; frame: string }>();
  const listeners: { emitter: { off(event: string, listener: (...args: any[]) => void): unknown }; name: string; fn: (...args: any[]) => void }[] = [];
  const changes = new Set<() => void>();
  const notify = () => { for (const resolve of [...changes]) resolve(); };
  const stamp = () => Math.max(0, now() - began);
  const event = (name: string) => { if (events.length < 64) events.push({ event: name, ms: stamp() }); };
  const opaque = (map: Map<string, string>, raw: unknown, prefix: string): string => {
    if (typeof raw !== 'string' || !raw || map.size >= 32 && !map.has(raw)) return `${prefix}-unknown`;
    if (!map.has(raw)) map.set(raw, `${prefix}${map.size + 1}`); return map.get(raw)!;
  };
  const issue = (r: Native, code: string) => { if (!r.problems.includes(code) && r.problems.length < 12) r.problems.push(code); };
  const wipe = (r: Native) => { r.prefix?.fill(0); r.prefix = null; for (const b of r.chunks) b.fill(0); r.chunks.length = 0; };
  const active = () => { if (stopped) return false; if (now() > options.deadlineAt) { deadlineExceeded = true; return false; } return true; };
  const finalise = (r: Native) => {
    if (!r.ack || r.terminal === 'pending' || r.digest !== null) return;
    if (r.bytes !== r.observedDataLength) issue(r, 'byte-event-gap');
    if (!r.problems.length) {
      const body = Buffer.concat([...(r.prefix ? [r.prefix] : []), ...r.chunks]);
      r.digest = sha(body);
      try {
        const text = new TextDecoder('utf-8', { fatal: true }).decode(body);
        try { const parsed = JSON.parse(text); r.parse = parsed !== null && typeof parsed === 'object' && !Array.isArray(parsed) ? 'object' : 'non-object'; r.canonicalDigest = sha(JSON.stringify(parsed)); }
        catch { r.parse = 'invalid-json'; }
      } catch { r.parse = 'invalid-utf8'; }
      body.fill(0);
    }
    wipe(r); notify();
  };
  const pair = (key: string) => {
    const ns = nativeKeys.get(key) ?? [], ps = pwKeys.get(key) ?? [];
    for (let i = 0; i < Math.min(ns.length, ps.length); i++) ns[i].pw = ps[i]; notify();
  };
  const matches = (url: string, method: string) => {
    try { const u = new URL(url); return method === 'POST' && u.origin === options.apiOrigin && u.pathname === endpoint && !u.search && !u.hash; }
    catch { return false; }
  };
  const listen = (emitter: any, name: string, fn: (...args: any[]) => void) => {
    emitter.on(name, fn); listeners.push({ emitter, name, fn });
  };
  const bound = async <T>(operation: Promise<T>): Promise<T> => {
    const remaining = options.deadlineAt - now();
    if (remaining <= 0) { deadlineExceeded = true; throw new Error('Observation deadline'); }
    let timer: ReturnType<typeof setTimeout> | undefined;
    try { return await Promise.race([operation, new Promise<never>((_, reject) => { timer = setTimeout(() => { deadlineExceeded = true; reject(new Error('Observation deadline')); }, remaining); })]); }
    finally { if (timer) clearTimeout(timer); }
  };
  const onPwRequest = (request: Request) => {
    if (!active() || !matches(request.url(), request.method())) return;
    const id = identity(request.postData(), options.expectedSlot); if (!id) { invalidIdentity++; return; }
    const values = pwKeys.get(id.key) ?? [];
    if ([...pwKeys.values()].reduce((n, xs) => n + xs.length, 0) >= REQUEST_CAP) { requestOverflow++; return; }
    const value: Pw = { identity: id, sequence: values.length + 1, requestMs: stamp(), terminal: 'pending', terminalMs: null, http: null, failureCode: null };
    values.push(value); pwKeys.set(id.key, values); requests.set(request, value); pair(id.key);
  };
  const onPwResponse = (response: Response) => { const r = requests.get(response.request()); if (r && active()) { r.http = response.status(); notify(); } };
  const onPwTerminal = (request: Request, terminal: Terminal) => { const r = requests.get(request); if (r && active()) { r.terminal = terminal; r.terminalMs = stamp(); if (terminal === 'failed') r.failureCode = networkCode(request.failure()?.errorText); notify(); } };
  listen(page, 'request', onPwRequest); listen(page, 'response', onPwResponse);
  listen(page, 'requestfinished', (r: Request) => onPwTerminal(r, 'finished'));
  listen(page, 'requestfailed', (r: Request) => onPwTerminal(r, 'failed'));
  listen(page, 'framenavigated', frame => { if (frame === page.mainFrame()) { navigationEpoch++; event('main-frame-navigation'); } });
  listen(page, 'close', () => event('page-close')); listen(page, 'crash', () => event('page-crash'));
  listen(page, 'framedetached', frame => event(frame === page.mainFrame() ? 'main-frame-detached' : 'child-frame-detached'));
  listen(page.context(), 'close', () => event('browser-context-close'));
  try {
    const opening = page.context().newCDPSession(page);
    void opening.then(value => { if (stopped || now() > options.deadlineAt) return value.detach(); }).catch(() => {});
    session = await bound(opening);
    listen(session, 'close', () => { if (!stopped) event('unexpected-session-close'); });
    listen(session, 'Runtime.executionContextCreated', e => {
      const aux = e.context?.auxData;
      if (!active() || aux?.isDefault !== true || typeof e.context.id !== 'number' || contexts.size >= 32) return;
      const frame = opaque(frames, aux.frameId, 'f'); contexts.set(e.context.id, { frame, label: `x${++contextOrdinal}` });
      event('default-context-created');
    });
    listen(session, 'Runtime.executionContextDestroyed', e => { if (contexts.delete(e.executionContextId)) { contextEpoch++; event('default-context-destroyed'); } });
    listen(session, 'Runtime.executionContextsCleared', () => { contexts.clear(); contextEpoch++; event('contexts-cleared'); });
    listen(session, 'Network.requestWillBeSent', e => {
      if (!active() || !matches(e.request?.url, e.request?.method)) return;
      const id = identity(e.request?.postData, options.expectedSlot); if (!id) { invalidIdentity++; return; }
      if (records.length >= REQUEST_CAP) { requestOverflow++; return; }
      if (natives.has(e.requestId)) { issue(natives.get(e.requestId)!, 'request-id-reused-or-redirected'); return; }
      const group = nativeKeys.get(id.key) ?? [], frame = opaque(frames, e.frameId, 'f');
      const r: Native = { ordinal: records.length + 1, identity: id, sequence: group.length + 1,
        frame, document: opaque(documents, e.loaderId, 'd'), context: [...contexts.values()].find(x => x.frame === frame)?.label ?? null,
        navigationEpoch, contextEpoch, requestMs: stamp(), responseMs: null, terminalMs: null, terminal: 'pending', http: null,
        failureCode: null, canceled: null, corsFailure: false, blockedReason: null,
        stream: 'pending', ack: false, prefix: null, chunks: [], bytes: 0, bufferedBytes: 0, streamedBytes: 0, observedDataLength: 0,
        chunkCount: 0, digest: null, canonicalDigest: null, parse: 'unread', problems: [], pw: null };
      if (group.some(x => x.terminal === 'pending')) { issue(r, 'overlapping-identity'); for (const old of group) if (old.terminal === 'pending') issue(old, 'overlapping-identity'); }
      group.push(r); nativeKeys.set(id.key, group); records.push(r); natives.set(e.requestId, r); pair(id.key);
      // This reads THIS browser request only. Never Fetch.enable, route, replay, body override or fetch.
      void session!.send('Network.streamResourceContent', { requestId: e.requestId }).then(result => {
        if (!active()) return;
        const bytes = decoded(result.bufferedData); r.ack = true;
        if (!bytes) { issue(r, 'invalid-buffered-data'); r.stream = 'command-failed'; }
        else if (r.bytes + bytes.length > BYTE_CAP) { issue(r, 'byte-cap'); bytes.fill(0); r.stream = 'enabled'; }
        else { r.stream = 'enabled'; r.prefix = bytes; r.bufferedBytes = bytes.length; r.bytes += bytes.length; }
        finalise(r);
      }).catch(error => { if (!stopped) { r.ack = true; r.stream = fixedProtocolError(error); issue(r, 'stream-command-failed'); wipe(r); notify(); } });
    });
    listen(session, 'Network.responseReceived', e => { const r = natives.get(e.requestId); if (!r || !active()) return;
      r.responseMs = stamp(); r.http = Number.isInteger(e.response?.status) ? e.response.status : null; });
    listen(session, 'Network.dataReceived', e => {
      const r = natives.get(e.requestId); if (!r || !active()) return;
      if (!Number.isSafeInteger(e.dataLength) || e.dataLength < 0) { issue(r, 'invalid-data-length'); return; }
      r.observedDataLength += e.dataLength;
      if (e.data === undefined) return; // Prefix returned by the command covers pre-enable data.
      const bytes = decoded(e.data); r.chunkCount++;
      if (!bytes) issue(r, 'invalid-chunk');
      else if (r.bytes + bytes.length > BYTE_CAP || r.chunkCount > CHUNK_CAP) { issue(r, 'byte-or-chunk-cap'); bytes.fill(0); wipe(r); }
      else if (!r.problems.length) { r.bytes += bytes.length; r.streamedBytes += bytes.length; r.chunks.push(bytes); }
      else bytes.fill(0);
    });
    for (const [name, terminal] of [['Network.loadingFinished', 'finished'], ['Network.loadingFailed', 'failed']] as const) {
      listen(session, name, e => { const r = natives.get(e.requestId); if (!r || !active()) return;
        r.terminal = terminal; r.terminalMs = stamp();
        if (terminal === 'failed') {
          r.failureCode = networkCode(e.errorText); r.canceled = typeof e.canceled === 'boolean' ? e.canceled : null;
          r.corsFailure = Boolean(e.corsErrorStatus); r.blockedReason = e.blockedReason == null ? null : blockedReasons.has(e.blockedReason) ? e.blockedReason : 'unclassified';
        }
        finalise(r); });
    }
    await bound(session.send('Network.enable'));
    await bound(session.send('Runtime.enable')); // Context lifecycle only; no Runtime.evaluate or session access.
  } catch { unavailable = true; event('observer-unavailable'); }
  return {
    async assertComplete(response, parsedBody) {
      // Called ONLY after the caller's original response.json succeeded. Never recover or replace its error.
      const pw = requests.get(response.request());
      if (unavailable || !pw) throw new Error('Native publisher observation unavailable or uncorrelated');
      let actualCanonical: string;
      try { actualCanonical = sha(JSON.stringify(parsedBody)); }
      catch { throw new Error('Native publisher JSON comparison unavailable'); }
      while (true) {
        if (stopped || !active()) throw new Error('Native publisher observation ended before completeness');
        const r = records.find(value => value.pw === pw);
        if (requestOverflow) throw new Error('Native publisher observation request cap');
        if (r?.terminal === 'failed' || pw.terminal === 'failed') throw new Error('Native publisher request failed; incomplete');
        if (r?.problems.length || r && r.stream !== 'pending' && r.stream !== 'enabled') throw new Error('Native publisher body capture incomplete');
        if (r && r.terminal === 'finished' && r.ack && pw.terminal === 'finished') {
          if (!completeNativeBody({ terminal: r.terminal, stream: r.stream, problems: r.problems,
              bytes: r.bytes, parse: r.parse, paired: true }) || r.canonicalDigest !== actualCanonical ||
              r.http !== response.status() || pw.http !== response.status()) throw new Error('Native publisher body evidence mismatch or incomplete');
          return;
        }
        let wake: (() => void) | undefined;
        const changed = new Promise<void>(resolve => { wake = resolve; changes.add(resolve); });
        try { await bound(changed); } finally { if (wake) changes.delete(wake); }
      }
    },
    firstError(boundary) { first ??= { boundary, ms: stamp() }; },
    cleanup(boundary) { cleanup ??= { boundary, ms: stamp() }; },
    snapshot() {
      const expired = deadlineExceeded || (stoppedAt ?? now()) > options.deadlineAt;
      return { scope: 'passive-existing-native-publisher-post', identityScope: 'opaque-labels-local-to-this-upload-observer-not-global-browser-identities', acceptance: 'UNCHANGED_NOT_DECIDED_BY_OBSERVER',
        caps: { requestBytes: BYTE_CAP, requests: REQUEST_CAP, chunksPerRequest: CHUNK_CAP },
        page: 'p1', browserContext: 'bc1', session: 's1', stoppedAtMs: stoppedAt === null ? null : Math.max(0, stoppedAt - began), unavailable, deadlineExceeded: expired, requestOverflow, invalidIdentity,
        firstError: first, cleanup, events: events.slice(),
        requests: records.map(r => {
          const problems = [...r.problems, ...(expired ? ['observation-deadline'] : [])];
          const fact = { terminal: r.terminal, stream: r.stream, problems, bytes: r.bytes, parse: r.parse, paired: r.pw !== null };
          return { ordinal: r.ordinal, identityHash: r.identity.hash, postDataHash: r.identity.bodyHash, slot: r.identity.slot, identitySequence: r.sequence,
            page: 'p1', session: 's1', frame: r.frame, document: r.document, executionContext: r.context,
            navigationEpoch: r.navigationEpoch, contextEpoch: r.contextEpoch, requestMs: r.requestMs, responseMs: r.responseMs,
            terminalMs: r.terminalMs, terminal: r.terminal, http: r.http, stream: r.stream,
            failureCode: r.failureCode, canceled: r.canceled, corsFailure: r.corsFailure, blockedReason: r.blockedReason,
            bufferedBytes: r.bufferedBytes, streamedBytes: r.streamedBytes, bytes: r.bytes, observedDataLength: r.observedDataLength,
            chunks: r.chunkCount, digest: r.digest, parse: r.parse, problems,
            nativeBodyComplete: completeNativeBody(fact),
            playwright: r.pw ? { sequence: r.pw.sequence, requestMs: r.pw.requestMs, terminal: r.pw.terminal, terminalMs: r.pw.terminalMs, http: r.pw.http, failureCode: r.pw.failureCode } : null };
        }) };
    },
    async stop() {
      if (stopped) return; stoppedAt = now(); stopped = true; notify();
      for (const { emitter, name, fn } of listeners) emitter.off(name, fn); listeners.length = 0;
      for (const r of records) { if (!r.ack) issue(r, 'observer-stopped-before-ack'); wipe(r); }
      natives.clear(); nativeKeys.clear(); pwKeys.clear(); contexts.clear(); frames.clear(); documents.clear();
      // A dedicated observer detach is not a page/network shutdown. Never disable Playwright's own session.
      if (session) {
        const detached = session.detach().catch(() => { /* No raw error or replacement of first failure. */ });
        const remaining = Math.max(0, Math.min(500, options.deadlineAt - now()));
        let timer: ReturnType<typeof setTimeout> | undefined;
        try { await Promise.race([detached, new Promise<void>(done => { timer = setTimeout(done, remaining); })]); }
        finally { if (timer) clearTimeout(timer); }
      }
    },
  };
}
