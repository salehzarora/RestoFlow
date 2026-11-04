// GR-37 wrapper unit tests (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001). No database, Docker, network or
// Supabase CLI: the pure checks, plus main() refusals that stop before any CLI process.
// Run: node --test tools/supabase/bounded-db-push.test.mjs
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { after, test } from 'node:test';
import {
  APPLICATION_NAME, CLI_BINARIES, ENV_CLI, ENV_PASSFILE, ENV_URL, MIGRATION, MIGRATION_SHA256, STARTUP_OPTIONS,
  aclPrincipals, aclProblem, buildChildEnv, buildDbUrl, checkMigrations, dryRunArgs, main, parseArgs, parsePassfile,
  parsePending, parseTargetUrl, passfileLocationProblem, posixModeProblem, pushArgs, redact, refuseDebug,
  selectPassfileEntry, summarize, urlShape, verifyCli,
} from './bounded-db-push.mjs';

const SELF = fileURLToPath(import.meta.url);
const WRAPPER = path.join(path.dirname(SELF), 'bounded-db-push.mjs');
const REPO = path.resolve(path.dirname(SELF), '..', '..');
const CANARY = 'synthetic-secret-never-log-5d1c39a7';
const REF = 'abcdefghijklmnopqrst';
const scratch = mkdtempSync(path.join(realpathSync(tmpdir()), 'bizbot-gr37-test-'));
after(() => rmSync(scratch, { recursive: true, force: true }));
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const refusal = (code) => (error) => error?.code === code;
const LOCAL = 'postgresql://postgres@127.0.0.1:56622/postgres';
const HOSTED = `postgresql://postgres@db.${REF}.supabase.co:5432/postgres`;

test('the pinned constants are the approved ones', () => {
  assert.equal(MIGRATION, '20261104141959_bizbot_zcredit_001d_server_ledger.sql');
  assert.equal(MIGRATION_SHA256, '468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e');
  assert.equal(APPLICATION_NAME, 'bizbot_gr37_001d_v1');
  assert.equal(STARTUP_OPTIONS, '-c lock_timeout=5s -c statement_timeout=60s -c application_name=bizbot_gr37_001d_v1');
  assert.deepEqual(Object.keys(CLI_BINARIES), ['win32-x64']);
  assert.deepEqual(Object.keys(CLI_BINARIES['win32-x64']).sort(), ['supabase-go.exe', 'supabase.exe']);
});

test('the committed 001D migration has the pinned bytes', (t) => {
  const r = spawnSync('git', ['-C', REPO, 'show', `HEAD:supabase/migrations/${MIGRATION}`], { maxBuffer: 1 << 26 });
  if (r.status !== 0) return t.skip('the migration is not committed at HEAD in this checkout');
  assert.equal(sha(r.stdout), MIGRATION_SHA256);
});

test('arguments: only --mode, --project-ref, --workdir and --apply; debug flags refused', () => {
  const wd = path.resolve(scratch);
  assert.deepEqual(parseArgs(['--mode', 'local', '--workdir', wd]), { mode: 'local', projectRef: null, workdir: wd, apply: false });
  assert.deepEqual(parseArgs(['--mode', 'hosted', '--project-ref', REF, '--workdir', wd, '--apply']),
    { mode: 'hosted', projectRef: REF, workdir: wd, apply: true });
  for (const bad of [
    ['--mode', 'local', '--workdir', wd, '--include-all'],
    ['--mode', 'local', '--workdir', wd, 'repair'],
    ['--mode', 'local'],
    ['--mode', 'local', '--workdir', 'relative/dir'],
    ['--mode', 'other', '--workdir', wd],
    ['--mode', 'hosted', '--workdir', wd],
    ['--mode', 'hosted', '--project-ref', 'ABCDEFGHIJKLMNOPQRST', '--workdir', wd],
    ['--mode', 'hosted', '--project-ref', 'abc', '--workdir', wd],
    ['--mode', 'local', '--project-ref', REF, '--workdir', wd],
    ['--mode', 'local', '--mode', 'local', '--workdir', wd],
    ['--mode', 'local', '--workdir', wd, '--apply', '--apply'],
    ['--mode', '--workdir', wd],
  ]) assert.throws(() => parseArgs(bad), refusal('bad_arguments'), bad.join(' '));
  for (const bad of [['--debug'], ['--mode', 'local', '--workdir', wd, '--debug'], ['--log-level', 'debug'], ['--debug=true']]) {
    assert.throws(() => parseArgs(bad), refusal('debug_refused'), bad.join(' '));
  }
  assert.throws(() => parseArgs(['--mode', 'local', '--workdir', wd, CANARY]), (e) => e.code === 'bad_arguments' && !e.message.includes(CANARY));
});

test('any DEBUG variable refuses, whatever its value', () => {
  for (const key of ['SUPABASE_DEBUG', 'SUPABASE_INTERNAL_DEBUG', 'SUPABASE_SSL_DEBUG', 'SUPABASE_TELEMETRY_DEBUG', 'DEBUG', 'debug']) {
    assert.throws(() => refuseDebug({ PATH: 'x', [key]: '' }), refusal('debug_refused'), key);
  }
  assert.doesNotThrow(() => refuseDebug({ PATH: 'x', PGSSLMODE: 'require' }));
});

test('URL: passwordless, explicit port, no query, no pooler; local loopback; hosted exact direct host', () => {
  assert.deepEqual(parseTargetUrl(LOCAL, { mode: 'local' }), { user: 'postgres', host: '127.0.0.1', port: '56622', database: 'postgres' });
  assert.equal(parseTargetUrl('postgres://postgres@LOCALHOST:5432/postgres', { mode: 'local' }).host, 'localhost');
  assert.deepEqual(parseTargetUrl(HOSTED, { mode: 'hosted', projectRef: REF }), { user: 'postgres', host: `db.${REF}.supabase.co`, port: '5432', database: 'postgres' });
  assert.equal(parseTargetUrl(HOSTED.replace(`db.${REF}.supabase.co`, `DB.${REF.toUpperCase()}.SUPABASE.CO`), { mode: 'hosted', projectRef: REF }).host, `db.${REF}.supabase.co`);
  const cases = [
    [undefined, 'local', 'url_missing'],
    ['', 'local', 'url_missing'],
    [`postgresql://postgres:${CANARY}@127.0.0.1:5432/postgres`, 'local', 'url_password'],
    ['postgresql://postgres:@127.0.0.1:5432/postgres', 'local', 'url_password'],
    [`postgresql://postgres:${CANARY}@db.${REF}.supabase.co:5432/postgres`, 'hosted', 'url_password'],
    [`${LOCAL}?sslmode=disable`, 'local', 'url_invalid'],
    [`${LOCAL}?options=-c%20lock_timeout%3D0`, 'local', 'url_invalid'],
    [`${LOCAL}#x`, 'local', 'url_invalid'],
    ['postgresql://postgres@127.0.0.1/postgres', 'local', 'url_invalid'],
    ['postgresql://127.0.0.1:5432/postgres', 'local', 'url_invalid'],
    ['https://postgres@127.0.0.1:5432/postgres', 'local', 'url_invalid'],
    [` ${LOCAL}`, 'local', 'url_invalid'],
    ['postgresql://postgres@127.0.0.1:5432/postgres/extra', 'local', 'url_invalid'],
    [`postgresql://postgres.${REF}@aws-0-eu-west-1.pooler.supabase.com:5432/postgres`, 'hosted', 'pooler_refused'],
    [`postgresql://postgres@db.${REF}.supabase.co:6543/postgres`, 'hosted', 'pooler_refused'],
    ['postgresql://postgres@127.0.0.1:6543/postgres', 'local', 'pooler_refused'],
    ['postgresql://postgres@10.1.2.3:5432/postgres', 'local', 'url_not_loopback'],
    [HOSTED, 'local', 'url_not_loopback'],
    [`postgresql://postgres@db.zyxwvutsrqponmlkjihg.supabase.co:5432/postgres`, 'hosted', 'url_not_direct_host'],
    [`postgresql://postgres@db.${REF}.supabase.co:5433/postgres`, 'hosted', 'url_not_direct_host'],
    [`postgresql://postgres.${REF}@db.${REF}.supabase.co:5432/postgres`, 'hosted', 'url_not_direct_host'],
    [`postgresql://postgres@db.${REF}.supabase.co:5432/other`, 'hosted', 'url_not_direct_host'],
    [LOCAL, 'hosted', 'url_not_direct_host'],
  ];
  for (const [raw, mode, code] of cases) {
    assert.throws(() => parseTargetUrl(raw, { mode, projectRef: REF }), (e) => e.code === code && !e.message.includes(CANARY), `${raw} -> ${code}`);
  }
});

test('the URL the CLI receives: passwordless, exactly the three fixed startup settings', () => {
  const url = buildDbUrl(parseTargetUrl(LOCAL, { mode: 'local' }));
  assert.equal(url, 'postgresql://postgres@127.0.0.1:56622/postgres?options=-c%20lock_timeout%3D5s%20-c%20statement_timeout%3D60s%20-c%20application_name%3Dbizbot_gr37_001d_v1');
  const parsed = new URL(url);
  assert.equal(parsed.password, '');
  assert.deepEqual([...parsed.searchParams.keys()], ['options']);
  assert.equal(parsed.searchParams.get('options'), STARTUP_OPTIONS);
  assert.ok(!urlShape('hosted').includes(REF) && urlShape('hosted').includes('<direct-host>'));
  assert.equal(urlShape('local'), 'postgresql://<user>@<loopback>:<port>/<database>?options=-c%20lock_timeout%3D5s%20-c%20statement_timeout%3D60s%20-c%20application_name%3Dbizbot_gr37_001d_v1');
});

test('the two CLI commands: no --include-all, repair, debug or password; push has --yes', () => {
  const url = buildDbUrl(parseTargetUrl(LOCAL, { mode: 'local' }));
  assert.deepEqual(dryRunArgs(url, 'W'), ['db', 'push', '--dry-run', '--db-url', url, '--workdir', 'W']);
  assert.deepEqual(pushArgs(url, 'W'), ['db', 'push', '--db-url', url, '--workdir', 'W', '--yes']);
  for (const args of [dryRunArgs(url, 'W'), pushArgs(url, 'W')]) {
    assert.ok(!args.some((a) => /include-all|repair|debug|log-level/.test(a)));
    assert.ok(!args.some((a) => /:\/\/[^@]*:[^@]*@/.test(a)), 'no password userinfo');
  }
});

test('child environment: an allowlist plus PGPASSFILE, PGSSLMODE=require and telemetry off', () => {
  const parent = {
    Path: 'P', SystemRoot: 'S', USERPROFILE: 'U', APPDATA: 'A', TEMP: 'T',
    PGPASSWORD: CANARY, SUPABASE_DB_PASSWORD: CANARY, PGOPTIONS: '-c lock_timeout=0', PGSERVICE: 'x', PGSERVICEFILE: 'y',
    PGAPPNAME: 'z', PGPASSFILE: 'other', PGSSLMODE: 'disable', PGHOST: 'h', PGUSER: 'u', SUPABASE_ACCESS_TOKEN: CANARY,
    SUPABASE_DEBUG: '1', [ENV_URL]: LOCAL, [ENV_PASSFILE]: 'f', [ENV_CLI]: 'c', NODE_OPTIONS: '--inspect',
  };
  const env = buildChildEnv(parent, 'PASSFILE');
  assert.deepEqual(env, {
    Path: 'P', SystemRoot: 'S', USERPROFILE: 'U', APPDATA: 'A', TEMP: 'T',
    PGPASSFILE: 'PASSFILE', PGSSLMODE: 'require', SUPABASE_TELEMETRY_DISABLED: '1', DO_NOT_TRACK: '1',
  });
  assert.ok(!JSON.stringify(env).includes(CANARY));
});

test('passfile: exact single entry, escapes, no wildcard, no malformed line', () => {
  const t = { host: '127.0.0.1', port: '56622', database: 'postgres', user: 'postgres' };
  assert.equal(selectPassfileEntry(parsePassfile(`# comment\n\n127.0.0.1:56622:postgres:postgres:${CANARY}\n`), t), CANARY);
  assert.equal(selectPassfileEntry(parsePassfile('127.0.0.1:56622:postgres:postgres:a\\:b:c\\\\d\r\n'), t), 'a:b:c\\d');
  assert.equal(selectPassfileEntry(parsePassfile('h\\:x:1:d:u:p\nother:1:d:u:q\n'), { host: 'h:x', port: '1', database: 'd', user: 'u' }), 'p');
  assert.equal(selectPassfileEntry(parsePassfile('127.0.0.1:56623:postgres:postgres:x\n127.0.0.1:56622:postgres:postgres:y\n'), t), 'y');
  for (const [text, code] of [
    ['127.0.0.1:56622:postgres\n', 'passfile_malformed'],
    ['127.0.0.1:56622:postgres:postgres:x\\\n', 'passfile_malformed'],
    ['*:56622:postgres:postgres:x\n', 'passfile_wildcard'],
    ['127.0.0.1:*:postgres:postgres:x\n', 'passfile_wildcard'],
    ['127.0.0.1:56622:postgres:postgres:x\n127.0.0.1:56622:postgres:postgres:y\n', 'passfile_entry'],
    ['localhost:56622:postgres:postgres:x\n', 'passfile_entry'],
    ['127.0.0.1:56622:postgres:postgres:\n', 'passfile_entry'],
    ['', 'passfile_entry'],
  ]) assert.throws(() => selectPassfileEntry(parsePassfile(text), t), (e) => e.code === code && !e.message.includes(CANARY), text);
});

test('passfile location: outside the repository, the store, worktrees, evidence and the workdir', () => {
  const root = path.resolve(path.sep, 'store');
  const repo = path.join(root, 'RestoFlow');
  const wtRepo = path.join(root, 'worktrees', 'some-task');
  const workdir = path.resolve(path.sep, 'work');
  assert.ok(passfileLocationProblem(path.join(repo, 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.join(root, 'evidence', 'x', 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.join(root, 'other', 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.join(root, 'other', 'pgpass'), { repoRoot: wtRepo, workdir }));
  assert.ok(passfileLocationProblem(path.join(workdir, 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.resolve(path.sep, 'x', 'Evidence', 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.resolve(path.sep, 'x', 'worktrees', 'pgpass'), { repoRoot: repo, workdir }));
  assert.equal(passfileLocationProblem(path.resolve(path.sep, 'private', 'gr37', 'pgpass'), { repoRoot: repo, workdir }), null);
});

test('passfile permissions: Windows ACL with the current user only; POSIX 0600 owned by the user', () => {
  const file = 'C:\\private\\gr37\\pgpass';
  const only = `${file} DESKTOP-ABC\\owner:(R,W)\r\n\r\nSuccessfully processed 1 files; Failed processing 0 files\r\n`;
  assert.deepEqual(aclPrincipals(only, file), ['desktop-abc\\owner']);
  assert.equal(aclProblem(aclPrincipals(only, file), 'desktop-abc\\owner'), null);
  const inherited = `${file} DESKTOP-ABC\\owner:(I)(F)\r\n                    BUILTIN\\Administrators:(I)(F)\r\n                    NT AUTHORITY\\SYSTEM:(I)(F)\r\n\r\nSuccessfully processed 1 files; Failed processing 0 files\r\n`;
  assert.equal(aclPrincipals(inherited, file).length, 3);
  assert.ok(aclProblem(aclPrincipals(inherited, file), 'desktop-abc\\owner'));
  assert.ok(aclProblem(aclPrincipals(only, file), 'desktop-abc\\someone-else'));
  assert.ok(aclProblem([], 'desktop-abc\\owner'));
  assert.equal(posixModeProblem({ mode: 0o100600, uid: 1000 }, 1000), null);
  assert.ok(posixModeProblem({ mode: 0o100644, uid: 1000 }, 1000));
  assert.ok(posixModeProblem({ mode: 0o100640, uid: 1000 }, 1000));
  assert.ok(posixModeProblem({ mode: 0o100600, uid: 0 }, 1000));
});

function migrationsDir(files) {
  const wd = mkdtempSync(path.join(scratch, 'wd-'));
  mkdirSync(path.join(wd, 'supabase', 'migrations'), { recursive: true });
  for (const [name, content] of Object.entries(files)) writeFileSync(path.join(wd, 'supabase', 'migrations', name), content);
  return wd;
}

test('migration gates: present, newest, unique version, exact raw bytes (a CRLF copy fails)', () => {
  const body = Buffer.from('create table t (id int);\nselect 1;\n');
  const pin = { digest: sha(body) };
  assert.deepEqual(checkMigrations(migrationsDir({ '20261102015942_main.sql': 'x', [MIGRATION]: body }), pin), { files: 2 });
  const fails = [
    [{ '20261102015942_main.sql': 'x' }, 'migration_missing'],
    [{ [MIGRATION]: body, '20261105000000_later.sql': 'x' }, 'migration_not_newest'],
    [{ [MIGRATION]: body, '20261104141959_a.sql': 'x' }, 'migration_version_reused'],
    [{ [MIGRATION]: Buffer.from(body.toString().replace(/\n/g, '\r\n')) }, 'migration_hash'],
    [{ [MIGRATION]: body, 'README.sql': 'x' }, 'migration_name'],
    [{ [MIGRATION]: body, '20261101000000_Upper.sql': 'x' }, 'migration_name'],
  ];
  for (const [files, code] of fails) assert.throws(() => checkMigrations(migrationsDir(files), pin), refusal(code), code);
  assert.throws(() => checkMigrations(path.join(scratch, 'absent')), refusal('migration_missing'));
});

test('CLI binaries: pinned platform, absolute supabase.exe, both executables hash-checked', () => {
  const dir = mkdtempSync(path.join(scratch, 'cli-'));
  writeFileSync(path.join(dir, 'supabase.exe'), 'front');
  writeFileSync(path.join(dir, 'supabase-go.exe'), 'engine');
  const pins = { 'test-x64': { 'supabase.exe': sha(Buffer.from('front')), 'supabase-go.exe': sha(Buffer.from('engine')) } };
  const cli = path.join(dir, 'supabase.exe');
  assert.equal(verifyCli(cli, { pins, platform: 'test-x64' }), cli);
  assert.throws(() => verifyCli(cli, { pins, platform: 'linux-x64' }), refusal('cli_platform'));
  assert.throws(() => verifyCli('supabase.exe', { pins, platform: 'test-x64' }), refusal('cli_missing'));
  assert.throws(() => verifyCli(path.join(dir, 'supabase-go.exe'), { pins, platform: 'test-x64' }), refusal('cli_missing'));
  assert.throws(() => verifyCli(cli, { pins: { 'test-x64': { ...pins['test-x64'], 'supabase-go.exe': sha(Buffer.from('other')) } }, platform: 'test-x64' }), refusal('cli_hash'));
  assert.throws(() => verifyCli(cli, { pins: { 'test-x64': { ...pins['test-x64'], 'extra.exe': 'x' } }, platform: 'test-x64' }), refusal('cli_missing'));
});

test('dry-run parsing: exactly the listed migrations, empty when up to date, null when unreadable', () => {
  assert.deepEqual(parsePending(`Using workdir W\nWould push these migrations:\n \u2022 ${MIGRATION}\n`), [MIGRATION]);
  assert.deepEqual(parsePending(`Would push these migrations:\n \u2022 ${MIGRATION}\n \u2022 20261105000000_x.sql\n`).length, 2);
  assert.deepEqual(parsePending('Remote database is up to date.\n'), []);
  assert.deepEqual(parsePending('Local database is up to date.\n'), []);
  assert.equal(parsePending('something else\n'), null);
});

test('redaction: URLs whole, passwords, tokens, keys, JWTs and every named secret', () => {
  const text = [
    `postgresql://postgres:${CANARY}@db.${REF}.supabase.co:5432/postgres?options=x`,
    // The access token is built from parts so the literal never trips tools/check_secrets.sh.
    `password=${CANARY}`, ['sbp', '0123456789abcdef0123'].join('_'), 'sb_secret_abcdefghijklmn', 'eyJhbGciOiJI.eyJzdWIiOiIx.c2lnbmF0dXJl',
    `C:\\private\\gr37\\pgpass and C:/private/gr37/pgpass and ${CANARY}`,
  ].join('\n');
  const out = redact(text, [CANARY, 'C:\\private\\gr37\\pgpass', 'C:/private/gr37/pgpass']);
  assert.ok(!out.includes(CANARY) && !out.includes('pgpass') && !out.includes(REF) && !out.includes('sbp_') && !out.includes('eyJ'));
  assert.ok(out.includes('<db-url>') && out.includes('<token>') && out.includes('<key>') && out.includes('<jwt>') && out.includes('<redacted>'));
});

test('CLI output summary: the error lines on failure (not the echoed SQL), the apply lines on success', () => {
  const failure = [
    `Applying migration ${MIGRATION}...`, 'ERROR: canceling statement due to lock timeout (SQLSTATE 55P03)', 'At statement: 43',
    'create table app.card_provider_attempts (', '  foreign key (organization_id, order_id) references public.orders (organization_id, id)',
    "  'permission_denied', 'revoked_device', 'provider_recording_refused', 'error_timeout')),",
    ')', 'Try rerunning the command with --debug to troubleshoot the error.', 'A new version of Supabase CLI is available: v3.0.0',
  ].join('\r\n');
  const s = summarize(failure, true);
  assert.match(s, /canceling statement due to lock timeout \(SQLSTATE 55P03\)/);
  assert.match(s, /At statement: 43/);
  assert.equal(s.split('\n').length, 2, s);
  assert.ok(!s.includes('references public.orders') && !s.includes('_refused') && !s.includes('new version') && !s.includes('--debug'));
  assert.match(summarize('failed to connect to `user=postgres database=postgres`: server refused TLS connection\n', true), /refused TLS/);
  assert.match(summarize('failed SASL auth (FATAL: password authentication failed for user "postgres" (SQLSTATE 28P01))\n', true), /28P01/);
  const ok = summarize(`Connecting to local database...\nApplying migration ${MIGRATION}...\nFinished supabase db push.\n`, false);
  assert.match(ok, /Applying migration/);
  assert.match(ok, /Finished supabase db push/);
  assert.equal(summarize('only noise\nmore noise\n', true), '    only noise\n    more noise');
});

test('the URL shape is printed unmasked and holds only placeholders; every other URL is masked whole', () => {
  assert.equal(redact(urlShape('hosted'), [], { maskUrls: false }), urlShape('hosted'));
  assert.equal(redact(urlShape('hosted'), []), '<db-url>');
  assert.equal(redact(`x ${HOSTED} y`, []), 'x <db-url> y');
});

test('main(): refusals stop before any CLI process and never print a secret', async () => {
  const wd = path.resolve(scratch);
  const run = async (argv, env) => {
    const lines = [];
    const code = await main(argv, env, (l) => lines.push(l));
    return { code, out: lines.join('\n') };
  };
  const base = ['--mode', 'local', '--workdir', wd];
  const cases = [
    [base, { [ENV_URL]: `postgresql://postgres:${CANARY}@127.0.0.1:56622/postgres` }, 'url_password'],
    [base, { [ENV_URL]: LOCAL, SUPABASE_DEBUG: '1' }, 'debug_refused'],
    [[...base, '--debug'], { [ENV_URL]: LOCAL }, 'debug_refused'],
    [base, {}, 'url_missing'],
    [base, { [ENV_URL]: LOCAL }, 'passfile_missing'],
    [base, { [ENV_URL]: LOCAL, [ENV_PASSFILE]: 'relative-pgpass' }, 'passfile_missing'],
    [base, { [ENV_URL]: LOCAL, [ENV_PASSFILE]: path.join(scratch, 'absent-pgpass') }, 'passfile_missing'],
    [base, { [ENV_URL]: LOCAL, [ENV_PASSFILE]: WRAPPER }, 'passfile_location'],
    [base, { [ENV_URL]: `postgresql://postgres@127.0.0.1:6543/postgres` }, 'pooler_refused'],
    [['--mode', 'hosted', '--project-ref', REF, '--workdir', wd], { [ENV_URL]: LOCAL }, 'url_not_direct_host'],
  ];
  for (const [argv, env, code] of cases) {
    const r = await run(argv, env);
    assert.equal(r.code, 2, code);
    assert.match(r.out, new RegExp(`^REFUSED ${code}:`), r.out);
    assert.ok(!r.out.includes(CANARY) && !r.out.includes('127.0.0.1:56622') && !r.out.includes(WRAPPER), r.out);
  }
});
