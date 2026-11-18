import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { chromium } from '@playwright/test';

// A loopback browser regression, not Edge/upload/tenant acceptance. Preserve the
// application's no-store policy and require the original Playwright body read.
const empty = JSON.stringify({ ok: true, status: 'published', padding: '' });
const body = Buffer.from(JSON.stringify({
  ok: true,
  status: 'published',
  padding: 'x'.repeat(715 - Buffer.byteLength(empty)),
}));
const expected = JSON.parse(body.toString('utf8'));
assert.equal(body.length, 715);
assert.equal(body.subarray(0, 6).toString('utf8'), '{"ok":');

function deferred() {
  let resolve;
  const promise = new Promise(done => { resolve = done; });
  return { promise, resolve };
}

async function bounded(promise, label) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${label} did not complete within 5000ms`)), 5000);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function fixture(t, variant) {
  let browser, context, response, request, primaryError;
  let posts = 0, browserPosts = 0, releases = 0;
  let nodeFinished = false, nodePrematureClose = false, nodeBytes = 0, finRequested = false;
  const originalStarted = deferred(), nodeClosed = deferred(), terminal = deferred();
  const server = createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/') {
      res.writeHead(200, { 'content-type': 'text/html' }).end('<!doctype html><title>Publisher stream regression</title>');
      return;
    }
    if (req.method !== 'POST' || req.url !== '/publisher') {
      res.writeHead(404).end();
      return;
    }
    posts++;
    req.resume();
    req.once('end', () => {
      response = res;
      const socket = res.socket;
      res.once('finish', () => {
        nodeFinished = true;
        if (variant === 'truncated') {
          // Send an actual FIN after the valid 715-byte JSON prefix, while the
          // header promises 716. Do not wait for a keep-alive expiry or retry.
          finRequested = true;
          socket.end();
        }
      });
      res.once('close', () => {
        nodePrematureClose = !res.writableFinished;
        nodeClosed.resolve();
      });
      res.writeHead(200, {
        'content-type': 'application/json',
        'cache-control': 'no-store',
        'content-length': variant === 'truncated' ? '716' : '715',
      });
      res.write(body.subarray(0, 6));
      nodeBytes = 6;
    });
  });
  try {
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    const origin = `http://127.0.0.1:${server.address().port}`;
    const endpoint = `${origin}/publisher`;
    browser = await chromium.launch();
    context = await browser.newContext();
    const page = await context.newPage();
    const exact = r => r.method() === 'POST' && r.url() === endpoint;
    page.on('request', r => {
      if (exact(r)) { request = r; browserPosts++; }
    });
    page.on('requestfinished', r => {
      if (r === request) terminal.resolve({ status: 'finished' });
    });
    page.on('requestfailed', r => {
      if (r === request) terminal.resolve({ status: 'failed', error: r.failure()?.errorText });
    });
    await context.exposeBinding('releasePublisherTail', async (source, boundary) => {
      assert.equal(source.page, page);
      assert.equal(source.frame, page.mainFrame());
      assert.equal(++releases, 1);
      assert.deepEqual(boundary, {
        firstChunkBytes: 6,
        nextReadIssued: true,
        abortedBeforeRelease: variant === 'abort',
      });
      assert.ok(response);
      await bounded(originalStarted.promise, 'original response reader start');
      if (variant !== 'abort') {
        nodeBytes += 709;
        response.end(body.subarray(6));
      }
      return true;
    });
    await page.goto(origin);
    const headers = page.waitForResponse(r => exact(r.request()), { timeout: 5000 });
    const app = page.evaluate(async abort => {
      const controller = new AbortController();
      const arrays = [];
      let eof = false, errorName = null, releaseAcknowledged = false, releaseResult = null;
      const response = await fetch('/publisher', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: '{}',
        signal: controller.signal,
      });
      const reader = response.body.getReader();
      try {
        const first = await reader.read();
        if (first.done || first.value.byteLength !== 6) throw new Error('FIRST_CHUNK_NOT_SIX');
        arrays.push(first.value);
        // Attach the rejection handler immediately: a real abort can reject
        // this pending read before the binding acknowledgment arrives.
        let pending = reader.read().then(value => ({ ok: true, value }), error => ({ ok: false, error }));
        if (abort) controller.abort();
        releaseResult = window.releasePublisherTail({
          firstChunkBytes: first.value.byteLength,
          nextReadIssued: true,
          abortedBeforeRelease: controller.signal.aborted,
        }).then(value => ({ ok: true, value }), () => ({ ok: false }));
        // Continue consuming immediately. Waiting for the binding ACK here can
        // buffer the tail before the next read and conceal the reentrant EOF bug.
        while (true) {
          const next = await pending;
          if (!next.ok) throw next.error;
          if (next.value.done) { eof = true; break; }
          arrays.push(next.value.value);
          pending = reader.read().then(value => ({ ok: true, value }), error => ({ ok: false, error }));
        }
      } catch (error) {
        errorName = error.name;
      } finally {
        reader.releaseLock();
      }
      const released = releaseResult == null ? null : await releaseResult;
      releaseAcknowledged = released?.ok === true && released.value === true;
      const bytes = new Uint8Array(arrays.reduce((size, part) => size + part.byteLength, 0));
      let offset = 0;
      for (const part of arrays) { bytes.set(part, offset); offset += part.byteLength; }
      let parsed = null;
      try { parsed = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)); } catch {}
      return { eof, errorName, rawBytes: bytes.byteLength, parsed, releaseAcknowledged };
    }, variant === 'abort').then(value => ({ ok: true, value }), error => ({ ok: false, error }));
    const original = await headers;
    assert.equal(original.request(), request);
    assert.equal(original.status(), 200);
    assert.equal(original.headers()['cache-control'], 'no-store');
    assert.equal(original.headers()['content-length'], variant === 'truncated' ? '716' : '715');
    // This is the original browser response, with no clone or replacement GET.
    const originalBody = original.json().then(value => ({ ok: true, value }), error => ({ ok: false, error }));
    originalStarted.resolve();
    const [appResult, bodyResult, requestResult] = await bounded(
      Promise.all([app, originalBody, terminal.promise, nodeClosed.promise]),
      'publisher response, request terminal and server close',
    );
    assert.equal(posts, 1);
    assert.equal(browserPosts, 1);
    assert.equal(releases, 1);
    assert.equal(appResult.ok, true);
    assert.equal(appResult.value.releaseAcknowledged, true);
    t.diagnostic(JSON.stringify({
      variant, chromium: browser.version(),
      app: { eof: appResult.value.eof, bytes: appResult.value.rawBytes,
        parsedMatches: JSON.stringify(appResult.value.parsed) === JSON.stringify(expected),
        error: appResult.value.errorName },
      originalBodyReadable: bodyResult.ok,
      originalBodyUnavailable: !bodyResult.ok && /No data found for resource|No resource with given identifier/i.test(bodyResult.error?.message ?? ''),
      request: requestResult, node: { finish: nodeFinished, prematureClose: nodePrematureClose, bytes: nodeBytes, finRequested },
    }));
    if (variant === 'complete') {
      assert.deepEqual(appResult.value, {
        eof: true, errorName: null, rawBytes: 715, parsed: expected, releaseAcknowledged: true,
      });
      assert.equal(bodyResult.ok, true, bodyResult.error?.message);
      assert.deepEqual(bodyResult.value, expected);
      assert.deepEqual(requestResult, { status: 'finished' });
      assert.equal(nodeFinished, true);
      assert.equal(nodePrematureClose, false);
      assert.equal(nodeBytes, 715);
    } else {
      assert.equal(bodyResult.ok, false, 'An incomplete or aborted original body must remain a failure');
      assert.equal(requestResult.status, 'failed');
      assert.equal(appResult.value.eof, false);
      assert.notEqual(appResult.value.errorName, null);
      if (variant === 'truncated') {
        assert.equal(nodeBytes, 715);
        assert.equal(nodeFinished, true);
        assert.equal(finRequested, true);
      } else {
        assert.equal(nodeBytes, 6, 'Abort must precede the tail write');
        assert.equal(nodeFinished, false);
        assert.equal(nodePrematureClose, true);
        assert.equal(appResult.value.rawBytes, 6);
        assert.equal(appResult.value.errorName, 'AbortError');
      }
    }
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    const cleanupErrors = [];
    for (const [label, cleanup] of [
      ['context', async () => { await context?.close(); }],
      ['browser', async () => { await browser?.close(); }],
      ['server', async () => {
        server.closeAllConnections();
        if (server.listening) await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
      }],
    ]) {
      try { await cleanup(); } catch (error) { cleanupErrors.push(error); t.diagnostic(`${label} cleanup failed`); }
    }
    if (!primaryError && cleanupErrors.length) throw new AggregateError(cleanupErrors, 'Fixture cleanup failed');
  }
}

test('no-store 6+709-byte streaming JSON completes in app and original browser response', { timeout: 30000 },
  t => fixture(t, 'complete'));
test('valid 715-byte JSON with declared length716 and FIN still fails closed', { timeout: 30000 },
  t => fixture(t, 'truncated'));
test('explicit abort after the first6 bytes cannot become a completed publication', { timeout: 30000 },
  t => fixture(t, 'abort'));
