import assert from 'node:assert/strict';
import { createHash, createHmac, randomUUID, webcrypto } from 'node:crypto';
import { createHandler as submissionHandler } from '../../supabase/functions/web-order-submit/handler.mjs';
import { createHandler as dispatchHandler } from '../../supabase/functions/pos-order-alert-dispatch/handler.mjs';
import { createHandler as statusHandler } from '../../supabase/functions/pos-order-alert-status/handler.mjs';
import { createHandler as cronHandler, DISPATCH_URL } from '../../services/pos-alert-cron/lib/handler.mjs';


const API = 'http://127.0.0.1:3000';
const database = process.env.BIZBOT_SYNTHETIC_DATABASE;
const SOURCE_BASE = 'https://oqmevrndtivqxgyvcmwy.supabase.co';
const JWT_SECRET = 'synthetic-platform353-local-only-jwt-secret-never-production-000000';
const STATUS_SECRET = 'c'.repeat(64);
const WORKER = 'b'.repeat(64);
const CRON = 'a'.repeat(64);
const id = (label) => {
  const s = createHash('md5').update(`platform353-local-acceptance-${label}`).digest('hex');
  return `${s.slice(0, 8)}-${s.slice(8, 12)}-${s.slice(12, 16)}-${s.slice(16, 20)}-${s.slice(20)}`;
};
function jwt(role) {
  const enc = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
  const unsigned = `${enc({ alg: 'HS256', typ: 'JWT' })}.${enc({ role, sub: id('transport-user'), exp: Math.floor(Date.now() / 1000) + 3600 })}`;
  return `${unsigned}.${createHmac('sha256', JWT_SECRET).update(unsigned).digest('base64url')}`;
}
const report = { status: 'BLOCKED', evidenceKind: 'local_real_handlers_http_rpc_database_with_synthetic_transport',
  startedUtc: new Date().toISOString(), checks: [], productionConnections: 0, physicalPrints: 0, actualFcmSends: 0 };
const passed = (name, facts = {}) => report.checks.push({ name, result: 'PASS', ...facts });


try {
assert.match(database ?? '', /^platform353_e2e_[0-9a-f]{12}$/);
    const localFetch = async (url, init) => {
      const parsed = new URL(url);
      assert.equal(parsed.origin, API, 'all actual HTTP network traffic must be fixture loopback');
      assert.equal(parsed.username + parsed.password, '');
      return fetch(parsed, { ...init, redirect: 'error', signal: init?.signal ?? AbortSignal.timeout(10_000) });
    };
    let ready = false;
    for (let n = 0; n < 30; n++) {
      try { const r = await localFetch(API); if (r.status === 200) { ready = true; break; } } catch { /* Local startup only. */ }
      await new Promise((resolve) => setTimeout(resolve, 200));
    }
    assert.equal(ready, true, 'local PostgREST must be ready');
    const apiRpc = async (name, body, role = 'authenticated') => {
      assert.match(name, /^[a-z][a-z0-9_]+$/);
      const r = await localFetch(`${API}/rpc/${name}`, { method: 'POST', headers: {
        'Content-Type': 'application/json', Authorization: `Bearer ${jwt(role)}`,
      }, body: JSON.stringify(body) });
      const result = await r.json();
      assert.equal(r.status, 200, `RPC ${name} HTTP status; code=${result?.code ?? 'none'}`);
      return result;
    };
    const fixture = (p_action, p_request = null) => apiRpc('platform353_acceptance_fixture', { p_action, p_request }, 'service_role');
    assert.deepEqual(await fixture('identity'), { database, synthetic_only: true }, 'HTTP endpoint must be the newly cloned execution database');
    const deviceArgs = (n) => ({ p_pin_session_id: id(`pin-${n}`), p_device_id: id(`device-${n}`),
      p_device_session_token: `synthetic-platform353-local-token-${n}` });
    const register = (n) => apiRpc('pos_register_order_alert', { ...deviceArgs(n),
      p_installation_id: id(`installation-${n}`), p_fcm_token: `synthetic-platform353-local-fcm-token-${n}`,
      p_status_secret: STATUS_SECRET });
    const registrations = new Map();
    const registrationBindings = new Map();
    for (const n of [1, 2, 3]) {
      const r = await register(n); assert.equal(r.ok, true); registrations.set(n, r.registration_id); registrationBindings.set(n, r);
    }
    for (const label of ['a', 'b']) {
      const menu = await apiRpc('storefront_menu', { p_slug: `platform353-local-${label}` }, 'anon');
      assert.equal(menu.ok, true); assert.equal(menu.service.ordering_enabled, true);
    }
    passed('new_tenants_publish_order_and_pos_register_without_allowlists', { tenants: 2, initiallyRegisteredDevices: 3 });

    const captures = []; const tasks = []; const transportFailures = new Map();
    const env = { SUPABASE_URL: SOURCE_BASE, SUPABASE_SERVICE_ROLE_KEY: jwt('service_role'), WEB_ORDERS_ENABLED: 'true',
      POS_ORDER_ALERTS_ENABLED: 'true', POS_ORDER_ALERT_MODE: 'continuous', POS_ORDER_ALERT_INSTANT_WAKE_ENABLED: 'true',
      POS_ORDER_ALERT_WORKER_SECRET: WORKER, POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT: JSON.stringify({ type: 'service_account',
        project_id: 'synthetic-project', client_email: 'synthetic@synthetic-project.iam.gserviceaccount.com',
        private_key: ['-----BEGIN', 'PRIVATE KEY-----\nSYNTHETIC-NOT-A-KEY'].join(' '), token_uri: 'https://oauth2.googleapis.com/token' }) };
    let worker;
    const transport = async (url, init) => {
      if (url === DISPATCH_URL) return worker(new Request(url, init));
      if (url === 'https://fcm.googleapis.com/v1/projects/synthetic-project/messages:send') {
        const payload = JSON.parse(init.body).message;
        assert.deepEqual(Object.keys(payload.data).sort(), ['expires_at', 'kind', 'registration_id', 'request_id', 'version']);
        assert.equal(JSON.stringify(payload).includes('Stored item'), false);
        assert.equal(JSON.stringify(payload).includes('Synthetic Guest'), false);
        captures.push(payload);
        if (transportFailures.get(payload.token)) { transportFailures.set(payload.token, false); return Response.json({}, { status: 503 }); }
        return Response.json({ name: `projects/synthetic-project/messages/${captures.length}` });
      }
      const parsed = new URL(url);
      assert.equal(parsed.origin, SOURCE_BASE);
      assert.match(parsed.pathname, /^\/rest\/v1\/rpc\/[a-z_]+$/);
      assert.equal(parsed.search + parsed.hash, '');
      return localFetch(`${API}${parsed.pathname.replace('/rest/v1', '')}`, init);
    };
    worker = dispatchHandler({ getEnv: (name) => env[name], fetchImpl: transport, cryptoImpl: webcrypto,
      tokenProvider: async () => 'synthetic-local-oauth-access-token' });
    const submit = submissionHandler({ getEnv: (name) => env[name], fetchImpl: transport, cryptoImpl: webcrypto,
      waitUntil: (task) => tasks.push(task) });
    const nativeStatus = statusHandler({ getEnv: (name) => env[name], fetchImpl: transport, cryptoImpl: webcrypto });
    const cronEnv = { CRON_SECRET: CRON, POS_ALERT_CRON_ENABLED: 'true', POS_ALERT_DISPATCH_URL: DISPATCH_URL,
      POS_ORDER_ALERT_WORKER_SECRET: WORKER, POS_ORDER_ALERT_MODE: 'continuous', VERCEL: '1', VERCEL_ENV: 'production' };
    const cron = cronHandler({ getEnv: (name) => cronEnv[name], fetchImpl: transport });
    const tick = () => cron(new Request('https://synthetic-cron.invalid/api/dispatch', { headers: { Authorization: `Bearer ${CRON}` } }));
    const status = async (n) => {
      const r = await nativeStatus(new Request(`${SOURCE_BASE}/functions/v1/pos-order-alert-status`, { method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${STATUS_SECRET}` }, body: JSON.stringify({ installation_id: id(`installation-${n}`) }) }));
      return { status: r.status, body: await r.json() };
    };
    const requests = [];
    const newRequest = (label = 'a') => ({ action: 'submit', slug: `platform353-local-${label}`, request_id: randomUUID(),
      status_token: Buffer.alloc(32, requests.length + 30).toString('base64url'), order: { order_type: 'takeaway',
        customer: { name: 'Synthetic Guest', phone: `+1202555${String(requests.length + 1000).padStart(4, '0')}` }, notes: 'Stored customer note',
        items: [{ menu_item_id: id(`item-${label}`), quantity: 2, modifiers: [], notes: 'Stored item note' }] } });
    const submitOne = async (body) => {
      const r = await submit(new Request(`${SOURCE_BASE}/functions/v1/web-order-submit`, { method: 'POST',
        headers: { 'Content-Type': 'application/json', Origin: 'https://menu.bizbot.systems' }, body: JSON.stringify(body) }));
      const result = await r.json(); assert.equal(r.status, 200, `submission: ${result.error ?? 'ok'}`); assert.equal(result.ok, true);
      const internal = await fixture('lookup', body.request_id);
      assert.match(internal, /^[a-f0-9-]{36}$/); return { body, result, internal };
    };
    const first = await submitOne(newRequest()); requests.push(first);
    const firstReplay = await submitOne(first.body); assert.equal(firstReplay.result.replayed, true);
    const second = await submitOne(newRequest('b')); requests.push(second);
    await Promise.all([...tasks, tick()]);
    const firstMessages = captures.filter((p) => p.data.request_id === first.internal && p.data.kind === 'pending');
    assert.equal(firstMessages.length, 2); assert.deepEqual(new Set(firstMessages.map((m) => m.data.registration_id)), new Set([registrations.get(1), registrations.get(2)]));
    assert.equal(captures.filter((p) => p.data.request_id === second.internal && p.data.kind === 'pending').length, 1);
    assert.equal((await status(3)).body.requests[0].request_id, second.internal);
    for (const n of [1, 2]) {
      const inbox = await apiRpc('pos_web_order_inbox', deviceArgs(n));
      assert.equal(inbox.requests.length, 1); assert.equal(inbox.requests[0].request_id, first.internal);
    }
    assert.equal((await apiRpc('pos_accept_web_order', { ...deviceArgs(3), p_request_id: first.internal, p_decision_id: randomUUID() })).error, 'not_found');
    passed('real_submission_inbox_and_fcm_fanout_tenant_isolation', { pendingCaptures: 3, duplicateInstantCronCaptures: 0, replayed: true });

    const accepts = await Promise.all([1, 2].map(async (n) => ({ n, result: await apiRpc('pos_accept_web_order', {
      ...deviceArgs(n), p_request_id: first.internal, p_decision_id: randomUUID(),
    }) })));
    assert.equal(accepts.filter((r) => r.result.ok === true && r.result.replayed === false).length, 1);
    assert.equal(accepts.filter((r) => r.result.error === 'decision_conflict').length, 1);
    const winner = accepts.find((r) => r.result.replayed === false).n;
    const loser = winner === 1 ? 2 : 1;
    const loserClaim = await apiRpc('pos_claim_web_order_print', { ...deviceArgs(loser), p_request_id: first.internal });
    assert.equal(loserClaim.error, 'containment_blocked');
    assert.equal((await apiRpc('pos_claim_web_order_print', { ...deviceArgs(winner), p_request_id: first.internal })).state, 'claimed');
    const attempt = randomUUID();
    const begins = await Promise.all([1, 2].map(() => apiRpc('pos_begin_web_order_print', {
      ...deviceArgs(winner), p_request_id: first.internal, p_attempt_id: attempt,
    })));
    const kitchenCaptures = begins.filter((r) => r.send_authorized === true).map(() => ({ syntheticTransportCapture: true }));
    assert.equal(kitchenCaptures.length, 1);
    assert.equal((await apiRpc('pos_begin_web_order_print', { ...deviceArgs(loser), p_request_id: first.internal,
      p_attempt_id: randomUUID() })).send_authorized, false);
    const finish = await apiRpc('pos_finish_web_order_print', { ...deviceArgs(winner), p_request_id: first.internal,
      p_attempt_id: attempt, p_client_status: 'transport_accepted', p_error_code: null });
    assert.equal(finish.state, 'transport_accepted');
    const exact = await fixture('cardinality', first.internal);
    assert.deepEqual(exact, { decisions: 1, orders: 1, dispatches: 1, attempts: 1 });
    assert.equal((await apiRpc('pos_web_order_inbox', deviceArgs(loser))).requests.length, 0);
    assert.equal((await tick()).status, 200);
    assert.equal(captures.filter((p) => p.data.request_id === first.internal && p.data.kind === 'cancel').length, 2);
    assert.equal((await status(3)).body.requests[0].request_id, second.internal);
    passed('concurrent_accept_one_canonical_order_dispatch_and_irreversible_send', { ...exact, capturedKitchenTransmissions: kitchenCaptures.length, actualPaper: 'NOT_TESTED' });
    passed('accepted_terminal_cancellation_does_not_cancel_other_tenant_pending');

    await fixture('onboard_and_revoke');
    const fresh = await register(4); assert.equal(fresh.ok, true); registrations.set(4, fresh.registration_id);
    assert.equal((await register(2)).error, 'invalid_session');
    transportFailures.set('synthetic-platform353-local-fcm-token-4', true);
    const third = await submitOne(newRequest()); requests.push(third);
    await Promise.all(tasks);
    const thirdMessages = captures.filter((p) => p.data.request_id === third.internal && p.data.kind === 'pending');
    assert.deepEqual(new Set(thirdMessages.map((m) => m.data.registration_id)), new Set([registrations.get(1), registrations.get(4)]));
    assert.equal((await status(2)).status, 401);
    assert.equal((await apiRpc('pos_web_order_inbox', deviceArgs(4))).requests[0].request_id, third.internal);
    // Advance only a synthetic retry row's due time; the server still performs
    // the genuine lease/retry authorization and dispatcher uses its real sender.
    await fixture('retry_due', third.internal);
    assert.equal((await tick()).status, 200);
    assert.equal(captures.filter((p) => p.data.request_id === third.internal && p.token === 'synthetic-platform353-local-fcm-token-4').length, 2);
    passed('fresh_device_joins_without_schema_or_configuration_change_and_revoked_device_denied', { currentTenantAEligibleDevices: 2 });
    passed('real_database_retry_recovered_by_cron', { firstTransportResponse: 503, secondTransportResponse: 200, syntheticDueTimeAdvance: true });

    await fixture('offline');
    const acceptedOffline = await apiRpc('pos_accept_web_order', { ...deviceArgs(1), p_request_id: third.internal, p_decision_id: randomUUID() });
    assert.equal(acceptedOffline.ok, true);
    const offlineClaim = await apiRpc('pos_claim_web_order_print', { ...deviceArgs(1), p_request_id: third.internal });
    assert.equal(offlineClaim.error, 'readiness_required');
    assert.equal(await fixture('attempt_count', third.internal), 0);
    passed('offline_printer_preserves_accepted_order_without_send_or_automatic_retry');
    await fixture('expire', second.internal);
    assert.equal((await tick()).status, 200);
    assert.equal(captures.filter((p) => p.data.request_id === second.internal && p.data.kind === 'cancel').length, 1);
    passed('expired_request_reconciled_to_terminal_cancel', { syntheticExpiryAdvance: true });
    const beforeRefresh = (await status(1)).body;
    const refreshedResponse = await nativeStatus(new Request(`${SOURCE_BASE}/functions/v1/pos-order-alert-status/token/refresh`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${STATUS_SECRET}` },
      body: JSON.stringify({ installation_id: id('installation-1'), fcm_token: 'synthetic-platform353-refreshed-local-token-1',
        generation: registrationBindings.get(1).generation }),
    }));
    const refreshed = await refreshedResponse.json();
    assert.equal(refreshedResponse.status, 200);
    assert.equal(refreshed.registration_id, registrations.get(1));
    assert.equal(refreshed.authority_expires_at, beforeRefresh.authority_expires_at);
    assert.notEqual(refreshed.generation, registrationBindings.get(1).generation);
    passed('real_native_status_token_refresh_preserves_employee_authority_expiry');
    const renewedForeground = await register(1);
    assert.equal(renewedForeground.ok, true);
    assert.notEqual(renewedForeground.generation, refreshed.generation);
    const staleRefresh = await nativeStatus(new Request(`${SOURCE_BASE}/functions/v1/pos-order-alert-status/token/refresh`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${STATUS_SECRET}` },
      body: JSON.stringify({ installation_id: id('installation-1'), fcm_token: 'synthetic-stale-background-local-token-1', generation: refreshed.generation }),
    }));
    assert.equal(staleRefresh.status, 401);
    assert.equal((await status(1)).status, 200);
    passed('stale_native_token_refresh_cannot_replace_new_foreground_registration');
    env.POS_ORDER_ALERTS_ENABLED = 'false';
    const beforeOff = captures.length;
    const beforeOffQueue = await fixture('queue_snapshot');
    const offDirect = await worker(new Request(DISPATCH_URL, { method: 'POST', headers: {
      'Content-Type': 'application/json', Authorization: `Bearer ${WORKER}` }, body: '{}' }));
    assert.equal(offDirect.status, 503);
    // Cron intentionally normalizes a disabled/unavailable upstream to 502.
    assert.equal((await tick()).status, 502);
    assert.equal(captures.length, beforeOff);
    assert.deepEqual(await fixture('queue_snapshot'), beforeOffQueue);
    passed('global_emergency_off_denies_cron_without_claim_or_transport', { dispatcherStatus: 503, cronUpstreamFailureStatus: 502 });
    report.status = 'PASS'; report.database = database; report.localApi = API;
    report.totalSyntheticFcmTransportCalls = captures.length;
    report.limitations = ['Synthetic FCM transport and kitchen transport captures are not Android, audible or physical paper acceptance.',
      'POS Inbox and printing public RPCs are real; Flutter UI/native lifecycle are covered separately.',
      'Deployment and current production protections require separate read-only production verification.'];

} catch (error) { report.failure = { name: error.name, category: error.message }; } finally { report.finishedUtc = new Date().toISOString(); console.log(JSON.stringify(report)); }
