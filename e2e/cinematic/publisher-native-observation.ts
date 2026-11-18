// Passive observation of this test page's existing publisher POST.
// The short probe and the first failing base-banner upload explicitly opt into
// bounded client-call observations using the same existing session. Never
// replace Response.json, a native body, or an acceptance outcome.
import { createHash } from 'node:crypto';
import type { Page, Request, Response, CDPSession } from '@playwright/test';

type Slot = 'hero' | 'background' | 'item' | 'product';
type Terminal = 'pending' | 'finished' | 'failed';
type StreamState = 'pending' | 'enabled' | 'finished-before-enable' | 'missing-resource' | 'command-failed';
type Parse = 'unread' | 'object' | 'non-object' | 'invalid-json' | 'invalid-utf8';
type WelcomeKind = 'welcome_video_v1';
type Identity = { hash: string; bodyHash: string; key: string } &
  ({ slot: Slot; kind?: never } | { kind: WelcomeKind; slot?: never });
type Pw = { identity: Identity; sequence: number; requestMs: number; terminal: Terminal; terminalMs: number | null; http: number | null; failureCode: string | null };
type Native = { ordinal: number; identity: Identity; sequence: number;
  frame: string; document: string; context: string | null; navigationEpoch: number; contextEpoch: number;
  requestMs: number; responseMs: number | null; terminalMs: number | null; terminal: Terminal; http: number | null;
  failureCode: string | null; canceled: boolean | null; corsFailure: boolean; blockedReason: string | null;
  stream: StreamState; ack: boolean; prefix: Buffer | null; chunks: Buffer[]; bytes: number;
  bufferedBytes: number; streamedBytes: number; observedDataLength: number; chunkCount: number;
  digest: string | null; canonicalDigest: string | null; parse: Parse; problems: string[]; pw: Pw | null };
export type PublisherObservationOptions = { apiOrigin: string; deadlineAt: number; now?: () => number; clientLifecycleProbe?: boolean } &
  ({ expectedSlot?: Slot; expectedKind?: never } | { expectedKind: WelcomeKind; expectedSlot?: never });
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
function identity(text: string | null | undefined, expected?: Slot, expectedKind?: WelcomeKind): Identity | null {
  // Read only the request UUID and exact slot/kind discriminator. Never retain
  // or export the request body or its private media/source fields.
  if (typeof text !== 'string' || Buffer.byteLength(text) > 4096) return null;
  try {
    const value = JSON.parse(text);
    if (!value || !UUID.test(value.request_id)) return null;
    const hash = sha(value.request_id), bodyHash = sha(text);
    if (expectedKind !== undefined) {
      if (value.kind !== expectedKind || Object.hasOwn(value, 'slot')) return null;
      return { hash, bodyHash, kind: expectedKind, key: `${hash}:${bodyHash}:${expectedKind}` };
    }
    if (Object.hasOwn(value, 'kind') || !slots.has(value.slot) || (expected && value.slot !== expected)) return null;
    const slot = value.slot as Slot;
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
// Self-contained, test-only installation in the exact Dashboard main realm.
// Function identities temporarily differ. Native this/arguments, returned
// Promises/Responses/streams/readers/results and errors never get substituted.
export function installPublisherClientLifecycle(config: { began: number; deadlineAt: number }) {
  const root = globalThis as any, key = '__cinematicPublisherLifecycleProbe';
  if (root.location?.origin !== 'http://127.0.0.1:57026' || root.window !== root.top || Object.hasOwn(root, key)
    || !root.crypto?.subtle || !Number.isFinite(config.began) || !Number.isFinite(config.deadlineAt)
    || config.deadlineAt <= Date.now() || config.deadlineAt <= config.began || config.deadlineAt - config.began > 120_000) return { status: 'UNAVAILABLE' };
  const fetchDescriptor = Object.getOwnPropertyDescriptor(root, 'fetch');
  const bodyGetter = Object.getOwnPropertyDescriptor(root.Response?.prototype ?? {}, 'body')?.get;
  if (!fetchDescriptor?.configurable || typeof fetchDescriptor.value !== 'function' || !bodyGetter) return { status: 'UNAVAILABLE' };
  const originalFetch = fetchDescriptor.value, nativeThen = Promise.prototype.then;
  const records: any[] = [], restores: (() => void)[] = [], removals: (() => void)[] = [];
  const streams = new WeakSet<object>(), readers = new WeakSet<object>();
  let stopped = false, overflow = 0, unsupported = 0, restorationSkipped = 0, eventCount = 0, readerCount = 0, pendingHashes = 0;
  let control: any;
  const stamp = () => Math.max(0, Math.min(120_000, Date.now() - config.began));
  const errorClass = (value: any) => ['Error', 'TypeError', 'AbortError', 'DOMException'].includes(value?.name) ? value.name : 'unclassified';
  const sites = () => {
    // Examine transiently; export only owned compiled-script coordinates.
    const text = (new Error().stack ?? '').slice(0, 8192), result: any[] = [];
    for (const line of text.split('\n', 32)) {
      const m = /http:\/\/127\.0\.0\.1:57026\/main\.dart\.js:(\d{1,8}):(\d{1,8})(?:\)|$)/.exec(line);
      if (m) { result.push({ kind: 'dashboard-main', line: Number(m[1]), column: Number(m[2]) }); if (result.length === 4) break; }
    }
    return result.length ? result : [{ kind: 'unclassified' }];
  };
  const event = (r: any, name: string, extra: any = {}) => {
    if (stopped) return;
    if (eventCount++ >= 128) { overflow++; return; }
    r.events.push({ event: name, ms: stamp(), ...extra });
  };
  const decorate = (target: any, name: string, descriptor: PropertyDescriptor) => {
    const previous = Object.getOwnPropertyDescriptor(target, name);
    if (previous && !previous.configurable || !previous && !Object.isExtensible(target)) { unsupported++; return false; }
    Object.defineProperty(target, name, { configurable: true, enumerable: previous?.enumerable ?? false, ...descriptor });
    restores.push(() => {
      const current = Object.getOwnPropertyDescriptor(target, name);
      if (current?.value !== descriptor.value || current?.get !== descriptor.get) { restorationSkipped++; return; }
      if (previous) Object.defineProperty(target, name, previous); else delete target[name];
    });
    return true;
  };
  const observePromise = (promise: any, success: (value: any) => void, failure: (error: any) => void) => {
    Reflect.apply(nativeThen, promise, [
      (value: any) => { try { success(value); } catch { unsupported++; } },
      (error: any) => { try { failure(error); } catch { unsupported++; } },
    ]);
  };
  const trackReader = (reader: any, r: any) => {
    if (readers.has(reader)) return;
    if (!(reader instanceof root.ReadableStreamDefaultReader) || Object.getPrototypeOf(reader) !== root.ReadableStreamDefaultReader.prototype
      || readerCount >= 8) { unsupported++; return; }
    readers.add(reader); const label = `reader${++readerCount}`;
    event(r, 'get-reader', { reader: label });
    for (const method of ['read', 'cancel']) {
      if (Object.hasOwn(reader, method)) { unsupported++; continue; }
      const native = root.ReadableStreamDefaultReader.prototype[method];
      decorate(reader, method, { writable: true, value: function(this: any, ...args: any[]) {
        if (this !== reader || stopped) return Reflect.apply(native, this, args);
        try { event(r, `${method}-call`, { reader: label, sites: sites() }); } catch { unsupported++; }
        let promise: any;
        try { promise = Reflect.apply(native, this, args); }
        catch (error) { try { event(r, `${method}-throw`, { reader: label, errorClass: errorClass(error) }); } catch {} throw error; }
        try { observePromise(promise, value => {
          if (method === 'cancel') { event(r, 'cancel-fulfilled', { reader: label }); return; }
          const done = Object.getOwnPropertyDescriptor(value, 'done'), chunk = Object.getOwnPropertyDescriptor(value, 'value');
          if (!done || !Object.hasOwn(done, 'value') || typeof done.value !== 'boolean'
            || chunk && !Object.hasOwn(chunk, 'value')) { unsupported++; return; }
          const bytes = chunk?.value;
          event(r, 'read-fulfilled', { reader: label, done: done.value,
            bytes: bytes instanceof Uint8Array ? bytes.byteLength : done.value && bytes === undefined ? 0 : null });
        }, error => event(r, `${method}-rejected`, { reader: label, errorClass: errorClass(error) })); } catch { unsupported++; }
        return promise;
      } });
    }
  };
  const trackResponse = (response: any, r: any) => {
    event(r, 'fetch-fulfilled');
    if (!(response instanceof root.Response) || Object.getPrototypeOf(response) !== root.Response.prototype
      || Object.hasOwn(response, 'body')) { unsupported++; return; }
    decorate(response, 'body', { get: function(this: any) {
      const stream = Reflect.apply(bodyGetter, this, []);
      if (this === response && stream && !stopped) {
        try {
          event(r, 'body-get');
          if (!streams.has(stream)) {
            streams.add(stream);
            if (Object.getPrototypeOf(stream) !== root.ReadableStream.prototype || Object.hasOwn(stream, 'getReader')) { unsupported++; return stream; }
            const native = root.ReadableStream.prototype.getReader;
            decorate(stream, 'getReader', { writable: true, value: function(this: any, ...args: any[]) {
              const reader = Reflect.apply(native, this, args);
              if (this === stream && !stopped) { try { trackReader(reader, r); } catch { unsupported++; } }
              return reader;
            } });
          }
        } catch { unsupported++; }
      }
      return stream;
    } });
  };
  const fetchWrapper = function(this: any, ...args: any[]) {
    const enteredMs = stamp();
    const promise = Reflect.apply(originalFetch, this, args);
    try {
      // The pinned Dart client supplies a string URL and plain RequestInit.
      // Unsupported accessors/Request streams are never read or cloned.
      if (args[0] !== 'http://127.0.0.1:54321/functions/v1/storefront-media-publish' || !args[1] || stopped) return promise;
      const method = Object.getOwnPropertyDescriptor(args[1], 'method'), body = Object.getOwnPropertyDescriptor(args[1], 'body');
      if (method?.value !== 'POST' || !body || !Object.hasOwn(body, 'value')) { unsupported++; return promise; }
      const value = body.value;
      if (typeof value === 'string' && value.length > 4096) { unsupported++; return promise; }
      const data = typeof value === 'string' ? new TextEncoder().encode(value) : value instanceof Uint8Array ? value : null;
      if (!data || data.byteLength > 4096) { unsupported++; return promise; }
      const parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(data));
      if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(parsed?.request_id) || parsed.slot !== 'hero' || Object.hasOwn(parsed, 'kind')) return promise;
      if (records.length >= 8) { overflow++; return promise; }
      const r: any = { ordinal: records.length + 1, identityHash: null, postDataHash: null, signalObserved: false, events: [] }; records.push(r);
      event(r, 'fetch-call', { ms: enteredMs });
      const hex = (bytes: ArrayBuffer) => [...new Uint8Array(bytes)].map(v => v.toString(16).padStart(2, '0')).join('');
      pendingHashes++;
      observePromise(Promise.all([root.crypto.subtle.digest('SHA-256', new TextEncoder().encode(parsed.request_id)), root.crypto.subtle.digest('SHA-256', data)]),
        values => { pendingHashes--; r.identityHash = hex(values[0]); r.postDataHash = hex(values[1]); }, () => { pendingHashes--; unsupported++; });
      const signalDescriptor = Object.getOwnPropertyDescriptor(args[1], 'signal'), signal = signalDescriptor?.value;
      if (signal instanceof root.AbortSignal) {
        r.signalObserved = true;
        if (signal.aborted) event(r, 'signal-already-aborted');
        const aborted = (e: Event) => { try { event(r, 'signal-abort', { signalAborted: signal.aborted === true, trusted: e.isTrusted === true, sites: sites() }); } catch { unsupported++; } };
        signal.addEventListener('abort', aborted, { once: true }); removals.push(() => signal.removeEventListener('abort', aborted));
      } else unsupported++;
      observePromise(promise, response => trackResponse(response, r), error => event(r, 'fetch-rejected', { errorClass: errorClass(error) }));
    } catch { unsupported++; }
    return promise;
  };
  const snapshot = () => ({ status: !records.length ? 'UNAVAILABLE' : unsupported || overflow || restorationSkipped || pendingHashes ? 'PARTIAL' : 'OBSERVED', observerEffect: 'Temporary function identities and extra passive Promise reactions; no native object/result substitution',
    stopped, overflow, unsupported, restorationSkipped, pendingHashes, records });
  const restore = () => {
    if (!stopped) {
      stopped = true; clearTimeout(timer);
      for (const remove of removals.splice(0)) { try { remove(); } catch { restorationSkipped++; } }
      for (const restore of restores.splice(0).reverse()) { try { restore(); } catch { restorationSkipped++; } }
      if (root[key] === control) delete root[key];
    }
    return snapshot();
  };
  const timer = setTimeout(restore, Math.max(0, config.deadlineAt - Date.now()));
  control = { snapshot, stop: restore };
  try {
    Object.defineProperty(root, key, { configurable: true, value: control });
    Object.defineProperty(root, 'fetch', { ...fetchDescriptor, value: fetchWrapper });
    restores.push(() => { if (root.fetch === fetchWrapper) Object.defineProperty(root, 'fetch', fetchDescriptor); else restorationSkipped++; });
  } catch { restore(); return { status: 'UNAVAILABLE' }; }
  return { status: 'INSTALLED' };
}
export function projectPublisherClientLifecycle(value: any): Record<string, any> {
  if (!value || !['OBSERVED', 'PARTIAL', 'UNAVAILABLE'].includes(value.status) || !Array.isArray(value.records) || value.records.length > REQUEST_CAP)
    return { status: 'UNAVAILABLE' };
  const count = (v: unknown) => Number.isSafeInteger(v) && (v as number) >= 0 && (v as number) <= 1_000_000 ? v : null;
  const names = new Set(['fetch-call', 'fetch-fulfilled', 'fetch-rejected', 'body-get', 'get-reader', 'read-call', 'read-throw',
    'read-fulfilled', 'read-rejected', 'cancel-call', 'cancel-throw', 'cancel-fulfilled', 'cancel-rejected', 'signal-abort', 'signal-already-aborted']);
  let eventCount = 0;
  const records = value.records.map((r: any, index: number) => ({ ordinal: index + 1,
    identityHash: typeof r?.identityHash === 'string' && /^[a-f0-9]{64}$/.test(r.identityHash) ? r.identityHash : null,
    postDataHash: typeof r?.postDataHash === 'string' && /^[a-f0-9]{64}$/.test(r.postDataHash) ? r.postDataHash : null,
    signalObserved: r?.signalObserved === true,
    events: (Array.isArray(r?.events) ? r.events : []).flatMap((e: any) => {
      if (eventCount >= 128 || !names.has(e?.event) || !Number.isFinite(e.ms) || e.ms < 0 || e.ms > 120_000) return [];
      eventCount++;
      return [{ event: e.event, ms: e.ms, ...(/^reader[1-8]$/.test(e.reader ?? '') ? { reader: e.reader } : {}),
        ...(typeof e.done === 'boolean' ? { done: e.done } : {}),
        ...(typeof e.signalAborted === 'boolean' ? { signalAborted: e.signalAborted } : {}),
        ...(typeof e.trusted === 'boolean' ? { trusted: e.trusted } : {}),
        ...(Object.hasOwn(e, 'bytes') ? { bytes: Number.isSafeInteger(e.bytes) && e.bytes >= 0 && e.bytes <= BYTE_CAP ? e.bytes : null } : {}),
        ...(Object.hasOwn(e, 'errorClass') ? { errorClass: ['Error', 'TypeError', 'AbortError', 'DOMException'].includes(e.errorClass) ? e.errorClass : 'unclassified' } : {}),
        ...(Array.isArray(e.sites) ? { sites: e.sites.slice(0, 4).map((s: any) => s?.kind === 'dashboard-main'
          && Number.isSafeInteger(s.line) && s.line > 0 && s.line <= 99_999_999 && Number.isSafeInteger(s.column) && s.column > 0 && s.column <= 99_999_999
          ? { kind: 'dashboard-main', line: s.line, column: s.column } : { kind: 'unclassified' }) } : {}) }];
    }) }));
  return { status: value.status, observerEffect: 'Temporary function identities and passive Promise reactions; original native objects/results retained',
    stopped: value.stopped === true, overflow: count(value.overflow), unsupported: count(value.unsupported),
    restorationSkipped: count(value.restorationSkipped), pendingHashes: count(value.pendingHashes), records };
}
export async function observePublisherNative(page: Page, options: PublisherObservationOptions): Promise<PublisherNativeObservation> {
  const now = options.now ?? Date.now, began = now();
  if (options.apiOrigin !== 'http://127.0.0.1:54321' || !Number.isFinite(options.deadlineAt) ||
      options.deadlineAt <= began || options.deadlineAt - began > 120_000 ||
      (options.expectedKind !== undefined && (options.expectedKind !== 'welcome_video_v1' || options.expectedSlot !== undefined))
      || options.clientLifecycleProbe !== undefined && typeof options.clientLifecycleProbe !== 'boolean'
      || options.clientLifecycleProbe === true && options.expectedSlot !== 'hero') throw new Error('Invalid bounded local publisher observation');
  let session: CDPSession | null = null, stopped = false, stoppedAt: number | null = null, deadlineExceeded = false, unavailable = false;
  let navigationEpoch = 0, contextEpoch = 0, contextOrdinal = 0, requestOverflow = 0, invalidIdentity = 0;
  let first: { boundary: string; ms: number } | null = null, cleanup: { boundary: string; ms: number } | null = null;
  const events: { event: string; ms: number }[] = [], records: Native[] = [];
  const natives = new Map<string, Native>(), nativeKeys = new Map<string, Native[]>(), pwKeys = new Map<string, Pw[]>();
  const requests = new WeakMap<Request, Pw>(), frames = new Map<string, string>(), documents = new Map<string, string>();
  const contexts = new Map<number, { label: string; frame: string }>();
  let clientContext: number | null = null, clientFacts: Record<string, any> = { status: 'UNAVAILABLE' };
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
    const id = identity(request.postData(), options.expectedSlot, options.expectedKind); if (!id) { invalidIdentity++; return; }
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
      const id = identity(e.request?.postData, options.expectedSlot, options.expectedKind); if (!id) { invalidIdentity++; return; }
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
    await bound(session.send('Runtime.enable')); // Lifecycle by default; explicit opt-in evaluates its bounded observer, never sessions.
    if (options.clientLifecycleProbe === true) {
      try {
        const tree = await bound(session.send('Page.getFrameTree'));
        const frame = frames.get(tree.frameTree?.frame?.id);
        clientContext = [...contexts].find(([, value]) => value.frame === frame)?.[0] ?? null;
        if (clientContext !== null) {
          const result = await bound(session.send('Runtime.evaluate', { contextId: clientContext, returnByValue: true,
            expression: `(${installPublisherClientLifecycle.toString()})(${JSON.stringify({ began, deadlineAt: options.deadlineAt })})` }));
          clientFacts = { status: result.result?.value?.status === 'INSTALLED' ? 'INSTALLED' : 'UNAVAILABLE' };
        }
      } catch { clientFacts = { status: 'UNAVAILABLE' }; }
    }
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
        ...(options.clientLifecycleProbe === true ? { clientLifecycle: { ...clientFacts,
          records: clientFacts.records?.map((r: any) => ({ ...r, nativeOrdinals: records.filter(n =>
            n.identity.hash === r.identityHash && n.identity.bodyHash === r.postDataHash).map(n => n.ordinal) })) } } : {}),
        requests: records.map(r => {
          const problems = [...r.problems, ...(expired ? ['observation-deadline'] : [])];
          const fact = { terminal: r.terminal, stream: r.stream, problems, bytes: r.bytes, parse: r.parse, paired: r.pw !== null };
          return { ordinal: r.ordinal, identityHash: r.identity.hash, postDataHash: r.identity.bodyHash,
            ...(r.identity.kind === undefined ? { slot: r.identity.slot } : { kind: r.identity.kind }), identitySequence: r.sequence,
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
      if (options.clientLifecycleProbe === true && session && clientContext !== null) {
        try {
          const operation = session.send('Runtime.evaluate', { contextId: clientContext, returnByValue: true,
            expression: 'globalThis.__cinematicPublisherLifecycleProbe?.stop()' });
          const result = await bound(operation);
          clientFacts = projectPublisherClientLifecycle(result.result?.value);
        } catch { clientFacts = { status: 'UNAVAILABLE', restoration: 'UNKNOWN_OR_CONTEXT_DESTROYED' }; }
      }
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
