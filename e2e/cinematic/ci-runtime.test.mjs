import test from 'node:test';
import assert from 'node:assert/strict';
import { localStatus, assertHeightVideoEvidence, HEIGHT_VIDEO_FILE, acceptanceRunArgs, PUBLISHER_PROBE_TITLE, CLEAR_TRACE_TITLE, WELCOME_GRANT_IDENTITIES, projectMigrationGrantReceipt, assertPublicEvidenceJson, evidenceSanitizeDiagnostic, caseCollectionSummary, probeDiagnosticScalars } from './ci-runtime.mjs';
import { readFileSync } from 'node:fs';
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
    'real owner Dashboard → Storage → publisher → save → live menu; replacement, clear and appearance',
    'independent banner → actual Edge → save/reload → replace/clear preserves other media',
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
