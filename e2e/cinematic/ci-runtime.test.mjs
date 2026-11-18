import test from 'node:test';
import assert from 'node:assert/strict';
import { localStatus, assertHeightVideoEvidence, assertPublicEvidenceFilename, HEIGHT_VIDEO_FILE, acceptanceRunArgs, PUBLISHER_PROBE_TITLE, CLEAR_TRACE_TITLE, WELCOME_GRANT_IDENTITIES, projectMigrationGrantReceipt, assertPublicEvidenceJson, evidenceSanitizeDiagnostic, caseCollectionSummary, caseResultEvidence, probeDiagnosticScalars, budgetChildProcessStates, waitUntil } from './ci-runtime.mjs';
import { readFileSync } from 'node:fs';
import { liveBudgetTransportError, retainLiveBudgetFailure, observeLiveBudgetTransport } from './live-budget.mjs';
import { EventEmitter } from 'node:events';
import { createServer } from 'node:http';
const key = role => `test.${Buffer.from(JSON.stringify({ role })).toString('base64url')}.test`;

test('the short publisher reproduction runs once and never excludes an original case', () => {
  const probe = acceptanceRunArgs('probe'), full = acceptanceRunArgs('full');
  assert.deepEqual(probe, ['--no-install', 'playwright', 'test', '--config', 'cinematic/playwright.config.ts', '--grep', `(?:^|\\s)${PUBLISHER_PROBE_TITLE}$`, '--reporter=json']);
  assert.equal(full.at(-3), '--grep-invert');
  const trace = acceptanceRunArgs('trace');
  assert.equal(trace.at(-3), '--grep'); assert.equal(trace.at(-2), `(?:^|\\s)${CLEAR_TRACE_TITLE}$`);
  for (const mode of [undefined, null, '', 'retry', 'skip']) assert.throws(() => acceptanceRunArgs(mode));
  const source = readFileSync(new URL('./dashboard.spec.ts', import.meta.url), 'utf8');
  const titles = [...source.matchAll(/^test\('([^']+)'/gm)].map(match => match[1]);
  const pattern = new RegExp(probe.at(-2));
  assert.equal(pattern.test(`dashboard.spec.ts ${PUBLISHER_PROBE_TITLE}`), true);
  assert.equal(pattern.test(`project suite dashboard.spec.ts ${PUBLISHER_PROBE_TITLE}`), true);
  assert.equal(pattern.test(`dashboard.spec.ts ${PUBLISHER_PROBE_TITLE} extra`), false);
  assert.deepEqual(titles.filter(title => pattern.test(title)), [PUBLISHER_PROBE_TITLE]);
  assert.deepEqual(titles.filter(title => new RegExp(trace.at(-2)).test(title)), [CLEAR_TRACE_TITLE]);
  assert.deepEqual(titles.filter(title => !new RegExp(full.at(-2)).test(title)), [
    'real owner Dashboard → Storage → publisher → save → live menu; publication and appearance',
    'real owner Dashboard continuation → scene/welcome → replacement/clear and retained originals',
    'independent banner → actual Edge → save/reload → replace/clear preserves other media',
    'independent responsive banner settings → actual owner save/reload → device independence and restoration',
    'welcome image and MP4 → actual Edge → owner save/reload → public welcome',
  ]);
});
test('only the local gateway and anon role enter application builds', () => {
  assert.equal(localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: key('anon') }).url, 'http://127.0.0.1:54321');
  for (const url of ['https://test.supabase.co', 'http://localhost:54321', 'http://127.0.0.1:54321.evil.test', 'http://127.0.0.1:54321/path']) {
    assert.throws(() => localStatus({ API_URL: url, ANON_KEY: key('anon') }));
  }
  for (const role of ['service_role', 'authenticated', undefined]) {
    assert.throws(() => localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: key(role) }));
  }
  assert.throws(() => localStatus({ API_URL: 'http://127.0.0.1:54321', ANON_KEY: 'malformed' }));
});

test('only the exact bounded WebM evidence filename and header are admitted', () => {
  const header = Buffer.alloc(64); header.set(Buffer.from('1a45dfa3', 'hex')); header.write('webm', 16);
  assert.doesNotThrow(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, header));
  for (const name of ['other.webm', 'trace.zip', '../' + HEIGHT_VIDEO_FILE, HEIGHT_VIDEO_FILE.toUpperCase()]) assert.throws(() => assertHeightVideoEvidence(name, header));
  assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, Buffer.from('not a WebM')));
  assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, Buffer.alloc(8 * 1024 * 1024 + 1)));
  const invalid = Buffer.from(header); invalid[0] = 0; assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, invalid));
  const missingType = Buffer.from(header); missingType.fill(0, 16, 20); assert.throws(() => assertHeightVideoEvidence(HEIGHT_VIDEO_FILE, missingType));
});
test('actual public filename admission preserves existing receipts and denies the private background handoff', () => {
  for (const name of ['dashboard-publication-result.json','background-quality-publication.json','responsive-banner-case-result.json',
    'dashboard-result.json','source.json','existing-receipt.json','screenshot.png',HEIGHT_VIDEO_FILE]) assert.doesNotThrow(() => assertPublicEvidenceFilename(name));
  for (const name of ['traditional-background-handoff.json','TRADITIONAL-BACKGROUND-HANDOFF.JSON',
    '../traditional-background-handoff.json','nested/receipt.json','receipt.json.extra','trace.zip']) assert.throws(() => assertPublicEvidenceFilename(name));
});


const sourceIdentity = { testedCheckout: 'a'.repeat(40), testedTree: 'b'.repeat(40) };
const currentIdentity = { checkout: sourceIdentity.testedCheckout, tree: sourceIdentity.testedTree };
function roleAuditReceipt(value = false) {
  return { status: 'FAIL', phase: 'real-lifecycle-failed', tested_commit: sourceIdentity.testedCheckout,
    tested_tree: sourceIdentity.testedTree, expected_failure: { status: 'PASS', schemaRolledBack: true },
    untouched: { canRead: false, explanation: 'audit values survive unchanged' },
    welcome_video_release: { status: 'PASS', readiness: { content_v7: true },
      grants: WELCOME_GRANT_IDENTITIES.map(identity => ({ identity, owner: 'postgres', search_path: ['search_path=""'],
        definer: identity.startsWith('app.') || identity === 'storefront_menu_v12(text)',
        anon: identity === 'storefront_menu_v12(text)', authenticated: true, service_role: value, public_execute: false })) } };
}
const projection = value => projectMigrationGrantReceipt('migration-atomicity.json', JSON.stringify(value,null,2)+'\n', sourceIdentity, currentIdentity);

test('exact role-audit projection preserves both booleans and every failure/value while keeping original text otherwise unchanged', () => {
  for (const granted of [false,true]) {
    const receipt = roleAuditReceipt(granted), original = JSON.stringify(receipt,null,2)+'\n';
    assert.throws(() => assertPublicEvidenceJson(original), /Credential-shaped/);
    const result = projectMigrationGrantReceipt('migration-atomicity.json',original,sourceIdentity,currentIdentity);
    assert.equal(result.text,original.replace(/"service_role"(?=\s*:)/g,'"serviceRoleExecute"'));
    assertPublicEvidenceJson(result.text);
    const parsed = JSON.parse(result.text);
    assert.equal(parsed.status,'FAIL'); assert.deepEqual(parsed.untouched,receipt.untouched);
    assert.deepEqual(parsed.expected_failure,receipt.expected_failure);
    for (let index=0;index<11;index++) {
      const {service_role,...other}=receipt.welcome_video_release.grants[index];
      assert.deepEqual(parsed.welcome_video_release.grants[index],{...other,serviceRoleExecute:service_role});
    }
    assert.equal(result.manifest.renamedFields.length,11);
    assert.equal(result.manifest.producerStatus,'FAIL');
    assert.equal(result.manifest.sourceSha256.length,64); assert.notEqual(result.manifest.sourceSha256,result.manifest.projectedSha256);
    assert.deepEqual(result.manifest.renamedFields.map(row=>row.value),Array(11).fill(granted));
    assertPublicEvidenceJson(JSON.stringify(result.manifest));
  }
});
test('malformed, collision, duplicate, unknown identity/context and non-boolean role data are refused', () => {
  for (const value of ['secret-key',null,0,1,{},[]]) {
    const input=roleAuditReceipt();input.welcome_video_release.grants[0].service_role=value;
    assert.throws(()=>projection(input),/ROLE_AUDIT_PROJECTION_INVALID/);
  }
  for (const mutate of [
    value=>value.welcome_video_release.grants.pop(),
    value=>value.welcome_video_release.grants[1].identity=value.welcome_video_release.grants[0].identity,
    value=>value.welcome_video_release.grants[0].identity='storefront_menu_v13(text)',
    value=>value.welcome_video_release.grants[0].serviceRoleExecute=false,
    value=>value.unrelated={service_role:false},
  ]) { const input=roleAuditReceipt();mutate(input);assert.throws(()=>projection(input),/ROLE_AUDIT_PROJECTION_INVALID/); }
  const duplicate=JSON.stringify(roleAuditReceipt()).replace('"service_role":false','"service_role":"secret-key","service_role":false');
  assert.throws(()=>projectMigrationGrantReceipt('migration-atomicity.json',duplicate,sourceIdentity,currentIdentity),/ROLE_AUDIT_PROJECTION_INVALID/);
  assert.throws(()=>projectMigrationGrantReceipt('other.json',JSON.stringify(roleAuditReceipt()),sourceIdentity,currentIdentity),/ROLE_AUDIT_PROJECTION_INVALID/);
  assert.throws(()=>assertPublicEvidenceJson(JSON.stringify({unrelated:{service_role:false}})),/Credential-shaped/);
});
test('projection verifies source/current/receipt identities and preserves an earlier failed receipt without a new grant audit', () => {
  const text=JSON.stringify(roleAuditReceipt());
  assert.throws(()=>projectMigrationGrantReceipt('migration-atomicity.json',text,{...sourceIdentity,testedTree:'c'.repeat(40)},currentIdentity),/SOURCE_IDENTITY_MISMATCH/);
  const foreign=roleAuditReceipt();foreign.tested_commit='d'.repeat(40);assert.throws(()=>projection(foreign),/SOURCE_IDENTITY_MISMATCH/);
  assert.throws(()=>projectMigrationGrantReceipt('migration-atomicity.json',text,sourceIdentity,{...currentIdentity,tree:'e'.repeat(40)}),/SOURCE_IDENTITY_MISMATCH/);
  const early=JSON.stringify({status:'FAIL',phase:'before-welcome',rolledBack:false});
  assert.deepEqual(projectMigrationGrantReceipt('migration-atomicity.json',early,sourceIdentity,currentIdentity),{text:early,manifest:null});
});
test('unchanged generic credential guard still rejects real key-shaped fields, token strings and duplicate credential keys after projection', () => {
  for (const extra of [
    {password:'synthetic-secret'}, {access_token:'synthetic-secret'}, {refresh_token:'synthetic-secret'},
    {anonKey:'synthetic-secret'}, {ANON_KEY:'synthetic-secret'},
    {nested:{note:'eyJabcdefghijklm.abcdefghijk.abcdefghijk'}},
  ]) { const result=projection({...roleAuditReceipt(),...extra});assert.throws(()=>assertPublicEvidenceJson(result.text),/Credential-shaped/); }
  const raw=JSON.stringify({...roleAuditReceipt(),password:null}).replace('{','{"password":"do-not-drop-this-value",');
  const result=projectMigrationGrantReceipt('migration-atomicity.json',raw,sourceIdentity,currentIdentity);
  assert.ok(result.text.includes('"password":"do-not-drop-this-value"'));
  assert.throws(()=>assertPublicEvidenceJson(result.text),/Credential-shaped/);
});
test('sanitize diagnostics print only fixed known filenames and reason enums, never error text or rejected names', () => {
  assert.deepEqual(evidenceSanitizeDiagnostic('migration-atomicity.json',new Error('Credential-shaped data must not be published')),
    {file:'migration-atomicity.json',reason:'CREDENTIAL_PATTERN_REJECTED'});
  const unknown=evidenceSanitizeDiagnostic('../secret-value.json',new Error('secret-value'));
  assert.deepEqual(unknown,{file:null,reason:'EVIDENCE_SANITIZE_FAILED'});
  const syntax=evidenceSanitizeDiagnostic('source.json',new SyntaxError('secret-value'));
  assert.deepEqual(syntax,{file:'source.json',reason:'JSON_INVALID'});
  for (const name of ['dashboard-publication-result.json','background-quality-publication.json','responsive-banner-case-result.json']) {
    assert.deepEqual(evidenceSanitizeDiagnostic(name,new SyntaxError('secret-value')),{file:name,reason:'JSON_INVALID'});
    assert.equal(evidenceSanitizeDiagnostic(name+'.extra',new SyntaxError('secret-value')).file,null);
  }
  assert.equal(evidenceSanitizeDiagnostic('traditional-background-handoff.json',new SyntaxError('secret-value')).file,null);
  assert.ok(!JSON.stringify({unknown,syntax}).includes('secret-value'));
});
test('case collection and probe diagnostics retain only bounded fixed scalars even when no case was collected', () => {
  const summary=caseCollectionSummary('probe',{status:1,error:{name:'Error',code:'ENOENT',message:'secret-value'}},
    {errors:[{name:'SyntaxError',message:'secret-value',stack:'secret-value at /workspace/e2e/cinematic/dashboard.spec.ts:77:4'}]},false);
  assert.equal(summary.exitCode,1);assert.equal(summary.reportPresent,false);assert.equal(summary.globalErrorCount,1);
  assert.deepEqual(summary.spawnError,{name:'Error',code:'ENOENT'});
  assert.equal(summary.globalErrors[0].sourceFrame,'cinematic/dashboard.spec.ts:77:4');
  assert.equal(summary.globalErrors[0].messageSha256.length,64);assert.ok(!JSON.stringify(summary).includes('secret-value'));
  const probe=probeDiagnosticScalars({status:'FAIL',phase:'ui-upload-original-publisher-response',uiPublicationCalls:1,contentSaveCalls:0,
    failure:{matcher:'toBe',sourceLine:888,actual:'secret-value'},readErrorDetail:'no-data',body:'secret-value'});
  assert.deepEqual(probe,{status:'FAIL',phase:'ui-upload-original-publisher-response',uiPublicationCalls:1,contentSaveCalls:0,matcher:'toBe',sourceLine:888,readErrorDetail:'no-data'});
  const untrusted=probeDiagnosticScalars({status:'secret-value',phase:'secret-value',failure:{matcher:'secret-value',sourceLine:'secret-value'},uiPublicationCalls:'secret-value',readErrorDetail:'secret-value'});
  assert.ok(!JSON.stringify(untrusted).includes('secret-value'));
});

test('reported duration metadata preserves outcomes/errors and rejects missing, secret-shaped or out-of-range durations', () => {
  const clean = value => String(value ?? '').replaceAll('secret-value', '[REDACTED]');
  for (const duration of [0, 64_362, 1_200_048.5, 3_600_000]) {
    assert.deepEqual(caseResultEvidence({ status: 'timedOut', error: { message: 'original error' }, duration, extra: 'secret-value' }, clean),
      { status: 'timedOut', error: 'original error', startTime: null, durationMs: duration });
    assert.equal(caseCollectionSummary('full', { status: 1 }, { stats: { duration } }, true).durationMs, duration);
  }
  for (const duration of [undefined, null, false, -1, NaN, Infinity, 3_600_001, 'secret-value', { valueOf() { throw new Error('secret-value'); } }]) {
    const result = caseResultEvidence({ status: 'failed', error: { message: 'secret-value' }, duration }, clean);
    assert.deepEqual(result, { status: 'failed', error: '[REDACTED]', startTime: null, durationMs: null });
    assert.equal(caseCollectionSummary('full', { status: 1 }, { stats: { duration } }, true).durationMs, null);
    assert.ok(!JSON.stringify(result).includes('secret-value'));
  }
  assert.equal(caseCollectionSummary('full', { status: 1 }, {}, true).durationMs, null);
});

test('case start times retain only exact valid canonical UTC timestamps from the actual report', () => {
  const clean = value => String(value ?? '');
  for (const startTime of ['2026-11-17T15:08:23.552Z', '2024-02-29T00:00:00.000Z', '1970-01-01T00:00:00.000Z']) {
    assert.deepEqual(caseResultEvidence({ status: 'timedOut', error: { message: 'original error' }, startTime, duration: 1_200_048.5 }, clean),
      { status: 'timedOut', error: 'original error', startTime, durationMs: 1_200_048.5 });
  }
  for (const startTime of [undefined, null, 0, new Date(0), 'secret-value', '2026-11-17', '2026-11-17T15:08:23Z',
    '2026-11-17T15:08:23.552+00:00', '2026-11-17T15:08:23.552z', '2026-11-17T15:08:23.552Z secret-value',
    ' 2026-11-17T15:08:23.552Z', '2026-02-30T00:00:00.000Z', '2026-13-01T00:00:00.000Z', '2026-11-17T24:00:00.000Z',
    { toString() { throw new Error('secret-value'); } }]) {
    const result = caseResultEvidence({ status: 'failed', error: { message: 'original error' }, startTime }, clean);
    assert.deepEqual(result, { status: 'failed', error: 'original error', startTime: null, durationMs: null });
    assert.ok(!JSON.stringify(result).includes('secret-value'));
  }
});


test('live-budget transport evidence admits fixed cause/name enums without messages, URLs, headers or bodies', () => {
  const error = new TypeError('secret-value', {cause:Object.assign(new Error('secret-value'), {code:'ECONNRESET',url:'https://secret-value/',headers:{authorization:'secret-value'},body:'secret-value'})});
  assert.deepEqual(liveBudgetTransportError(error),{name:'TypeError',causeName:'Error',causeCode:'ECONNRESET'});
  assert.deepEqual(liveBudgetTransportError({name:'TypeError',cause:{name:'SocketError',code:'UND_ERR_SOCKET'}}),{name:'TypeError',causeName:'SocketError',causeCode:'UND_ERR_SOCKET'});
  const unknown=liveBudgetTransportError({name:'secret-value',cause:{name:'secret-value',code:'secret-value',message:'secret-value'}});
  assert.deepEqual(unknown,{name:'unclassified',causeName:'unclassified',causeCode:'unclassified'});
  assert.ok(!JSON.stringify(unknown).includes('secret-value'));
});
test('a live fetch or body failure retains a partial FAIL receipt then rethrows exactly the same original error', () => {
  for (const phase of ['fetch','body-read']) {
    const original=new TypeError('secret-value',{cause:Object.assign(new Error('secret-value'),{code:'UND_ERR_SOCKET'})});
    let retained=null,calls=0;
    assert.throws(()=>retainLiveBudgetFailure(original,{phase,route:'/ar/s/maps-burger/menu',mapped:[{canonicalRoute:'/s/maps-burger/cart',actualRoute:'/s/cinematic-secret-value/cart',status:200}],status:phase==='body-read'?200:null},value=>{retained=value;calls++;}),error=>error===original);
    assert.equal(calls,1);assert.equal(retained.status,'FAIL');assert.equal(retained.complete,false);assert.deepEqual(retained.rows,[]);
    assert.deepEqual(retained.problems,['transport-error']);assert.equal(retained.phase,phase);assert.equal(retained.failedRoute,'/ar/s/maps-burger/menu');
    assert.deepEqual(retained.mapped,[{canonicalRoute:'/s/maps-burger/cart',status:200}]);
    assert.equal(retained.httpStatus,phase==='body-read'?200:null);assert.ok(!JSON.stringify(retained).includes('secret-value'));
    assert.throws(()=>retainLiveBudgetFailure(original,{phase,route:'https://secret-value/',mapped:[],status:null},()=>{throw new Error('evidence-write-failed');}),error=>error===original);
  }
});
test('non200 assertions remain failures and retain the actual bounded HTTP number without measuring incomplete output', () => {
  const original=Object.assign(new Error('actual live route must render'),{name:'AssertionError'});let retained;
  assert.throws(()=>retainLiveBudgetFailure(original,{phase:'http-status',route:'/he/s/maps-burger/review',mapped:[],status:503},value=>{retained=value;}),error=>error===original);
  assert.equal(retained.status,'FAIL');assert.equal(retained.httpStatus,503);assert.equal(retained.complete,false);assert.deepEqual(retained.rows,[]);
  assert.deepEqual(retained.problems,['http-status-error']);assert.equal(retained.transportError.name,'AssertionError');
  let privateInput;
  assert.throws(()=>retainLiveBudgetFailure(original,{phase:'secret-value',route:'https://secret-value/',mapped:[{canonicalRoute:'/s/secret-value/menu',status:'secret-value'}],status:'secret-value'},value=>{privateInput=value;}),error=>error===original);
  assert.equal(privateInput.failedRoute,null);assert.equal(privateInput.httpStatus,null);assert.equal(privateInput.phase,'unclassified');assert.ok(!JSON.stringify(privateInput).includes('secret-value'));
});
test('budget child snapshots observe only the two existing processes without calling kill or changing their state', () => {
  let calls=0;
  const dashboard={exitCode:null,signalCode:null,killed:false,pid:1234,stdout:'secret-value',args:['secret-value'],kill:()=>{calls++;}};
  const storefront={exitCode:1,signalCode:'SIGTERM',killed:true,env:{password:'secret-value'}};
  const states=budgetChildProcessStates(dashboard,storefront);
  assert.deepEqual(states,[{label:'dashboard',exitCode:null,signal:null,killed:false},{label:'storefront',exitCode:1,signal:'SIGTERM',killed:true}]);
  assert.equal(calls,0);assert.equal(dashboard.killed,false);assert.equal(storefront.exitCode,1);assert.ok(!JSON.stringify(states).includes('secret-value'));
  assert.deepEqual(budgetChildProcessStates(null,undefined),[]);
  const untrusted=budgetChildProcessStates({exitCode:'secret-value',signalCode:'secret-value',killed:'secret-value'},null);
  assert.deepEqual(untrusted,[{label:'dashboard',exitCode:null,signal:'OTHER',killed:false}]);
});

function diagnosticBus() {
  const listeners = new Map();
  const channel = name => ({
    subscribe(fn) { if (!listeners.has(name)) listeners.set(name, new Set()); listeners.get(name).add(fn); },
    unsubscribe(fn) { listeners.get(name)?.delete(fn); },
  });
  return { channel, emit(name, value) { for (const fn of listeners.get(name) ?? []) fn(value); },
    count() { return [...listeners.values()].reduce((sum, value) => sum + value.size, 0); } };
}
test('socket evidence observes only existing local readiness/first measurement events and exports no paths, headers or bodies', () => {
  const bus = diagnosticBus(); let ms = 100, io = 0;
  const observation = observeLiveBudgetTransport({ channel: bus.channel, now: () => ms++ });
  const socket = Object.assign(new EventEmitter(), { remoteAddress: '127.0.0.1', remotePort: 3000,
    destroyed: false, readableEnded: false, writableEnded: false,
    write() { io++; }, end() { io++; }, destroy() { io++; }, connect() { io++; } });
  const request = () => ({ origin: 'http://127.0.0.1:3000', get path() { throw new Error('secret-value'); },
    get headers() { throw new Error('secret-value'); }, get body() { throw new Error('secret-value'); } });
  const startup = request(), first = request();
  bus.emit('undici:client:sendHeaders', { request: { origin: 'https://secret-value/' }, socket });
  bus.emit('undici:client:connected', { socket: { remoteAddress: '127.0.0.1', remotePort: 54321 } });
  assert.deepEqual(observation.snapshot().events, []);
  bus.emit('undici:client:connected', { socket });
  bus.emit('undici:client:sendHeaders', { request: startup, socket });
  observation.beginMeasure();
  // A delayed startup completion must not steal the first measurement identity.
  bus.emit('undici:request:trailers', { request: startup });
  bus.emit('undici:client:sendHeaders', { request: first, socket });
  bus.emit('undici:request:error', { request: first, error: Object.assign(new Error('secret-value'), { code: 'EPIPE', body: 'secret-value' }) });
  const beforeLaterRoute = observation.snapshot().events.length;
  bus.emit('undici:client:sendHeaders', { request: request(), socket });
  assert.equal(observation.snapshot().events.length, beforeLaterRoute);
  socket.destroyed = true; socket.emit('close', true);
  const result = observation.snapshot();
  const sends = result.events.filter(value => value.event === 'send');
  assert.equal(sends.length, 2); assert.equal(sends[1].request, 'r2');
  assert.equal(sends[1].requestPhase, 'measure'); assert.equal(sends[1].reusedFromStartup, true);
  assert.deepEqual(result.events.find(value => value.event === 'request-error').error,
    { name: 'Error', causeName: 'Error', causeCode: 'EPIPE' });
  assert.equal(result.events.at(-1).destroyed, true); assert.equal(result.events.at(-1).hadError, true);
  assert.ok(!JSON.stringify(result).includes('secret-value')); assert.equal(io, 0);
  observation.stop(); observation.stop(); assert.equal(bus.count(), 0); assert.equal(socket.listenerCount('close'), 0);
});

test('socket observations are bounded, cannot throw into a request, and do not replace the original budget failure', () => {
  const bus = diagnosticBus(), observation = observeLiveBudgetTransport({ channel: bus.channel, now: () => 0 });
  assert.doesNotThrow(() => bus.emit('undici:client:connected', { get socket() { throw new Error('secret-value'); } }));
  for (let i = 0; i < 100; i++) bus.emit('undici:request:error', {
    request: { origin: 'http://127.0.0.1:3000' }, error: { name: 'secret-value', code: 'secret-value' },
  });
  const snapshot = observation.snapshot();
  assert.equal(snapshot.unavailable, 1); assert.ok(snapshot.overflow > 0); assert.ok(snapshot.events.length <= 64);
  assert.ok(!JSON.stringify(snapshot).includes('secret-value'));
  const original = new TypeError('original-failure', { cause: Object.assign(new Error(), { code: 'EPIPE' }) }); let retained;
  assert.throws(() => retainLiveBudgetFailure(original,
    { phase: 'fetch', route: '/s/maps-burger/menu', mapped: [], status: null, socketObservation: snapshot },
    value => { retained = value; }), error => error === original);
  assert.equal(retained.status, 'FAIL'); assert.equal(retained.complete, false);
  assert.deepEqual(retained.socketObservation, snapshot); assert.equal(retained.transportError.causeCode, 'EPIPE');
  observation.stop(); assert.equal(bus.count(), 0);
});

test('actual Storefront readiness closes only its own connection before a single later fetch; other readiness stays unchanged', { timeout: 5000 }, async () => {
  const seen = [], closed = new Map();
  const server = createServer((request, response) => {
    seen.push({ path: request.url, connection: request.headers.connection, socket: request.socket });
    response.end(request.url === '/menu' ? 'actual measured response' : 'ready');
  });
  server.on('connection', socket => closed.set(socket, new Promise(resolve => socket.once('close', resolve))));
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const origin = `http://127.0.0.1:${server.address().port}`;
  // Keep the production selection rule and readiness function intact while
  // using a fresh synthetic port, not a developer's possible port3000 server.
  const localFetch = (logicalUrl, options) => fetch(origin + new URL(logicalUrl).pathname, options);
  try {
    await waitUntil('http://127.0.0.1:3000/', response => response.status === 200, undefined, localFetch);
    assert.equal(seen.length, 1); assert.equal(seen[0].connection, 'close');
    await closed.get(seen[0].socket);
    const response = await fetch(origin + '/menu', { redirect: 'error' });
    assert.equal(response.status, 200); assert.equal(await response.text(), 'actual measured response');
    assert.equal(seen.length, 2); assert.notEqual(seen[0].socket, seen[1].socket);
    assert.equal(seen[1].connection, 'keep-alive');
    await waitUntil('http://127.0.0.1:57026/', response => response.status === 200, undefined, localFetch);
    assert.equal(seen.length, 3); assert.equal(seen[2].connection, 'keep-alive');
    await waitUntil('http://127.0.0.1:3000/other', response => response.status === 200, undefined, localFetch);
    assert.equal(seen.length, 4); assert.equal(seen[3].connection, 'keep-alive');
  } finally {
    server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
  }
});

test('readiness still fails on an exited application before sending any request', async () => {
  let requests = 0;
  await assert.rejects(waitUntil('http://127.0.0.1:3000/', () => true, { exitCode: 1 }, () => { requests++; }),
    /Local application exited during startup/);
  assert.equal(requests, 0);
});
