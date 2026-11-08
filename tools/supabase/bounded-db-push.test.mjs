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
  selectPassfileEntry, summarize, urlShape, verifyCli, verifyPassfile,
} from './bounded-db-push.mjs';
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001: the one-time exact-gap mode (tests at the end of this file;
// still no database, Docker, network or real CLI - the flow runs against an injected fake runner).
import { X509Certificate } from 'node:crypto';
import { chmodSync, existsSync, readFileSync, statSync } from 'node:fs';
import {
  ACCEPTED_HOSTED_CA_SHA256, ENV_SSLROOTCERT, EXACT_GAP, EXACT_GAP_FLAG, EXACT_GAP_MODE, READONLY_STARTUP_OPTIONS, Refusal,
  buildExactGapChildEnv, buildReadOnlyDbUrl, caCertificateProblem, checkExactGapMigrations, connectedLocally, evaluateExactGapPost,
  evaluateExactGapPre, exactGapDryRunArgs, exactGapMain, exactGapNormalDryRunArgs, exactGapPushArgs, exactGapStateSql, migrationListArgs,
  parseExactGapArgs, parseMigrationList, parseStateRows, readOnlyUrlShape, stateQueryArgs, verifyCa,
} from './bounded-db-push.mjs';
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-CORRECTIONS-001: the one-entry passfile (CR-EG-01).
import { selectExactGapPassfileEntry, verifyExactGapPassfile } from './bounded-db-push.mjs';
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-REPIN-001: the state fingerprint (runtime and #382 surface).
import { stateFingerprint } from './bounded-db-push.mjs';
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-HOSTED-PRE-COMPAT-001 (D-067): the two accepted pre-001D body forms.
import { recreatedBodyForm } from './bounded-db-push.mjs';

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
  const tree = spawnSync('git', ['-C', REPO, 'rev-parse', '--is-inside-work-tree'], { encoding: 'utf8' });
  if (tree.status !== 0 || tree.stdout.trim() !== 'true') return t.skip('not a Git work tree');
  const r = spawnSync('git', ['-C', REPO, 'show', `HEAD:supabase/migrations/${MIGRATION}`], { maxBuffer: 1 << 26 });
  assert.equal(r.status, 0, `the pinned ${MIGRATION} is not committed at HEAD`);
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

test('any DEBUG variable, NODE_OPTIONS, inspector or preload flag refuses; configuration-only flags do not', () => {
  const off = () => false;
  for (const key of ['SUPABASE_DEBUG', 'SUPABASE_INTERNAL_DEBUG', 'SUPABASE_SSL_DEBUG', 'SUPABASE_TELEMETRY_DEBUG', 'DEBUG', 'debug']) {
    assert.throws(() => refuseDebug({ PATH: 'x', [key]: '' }, [], off), refusal('debug_refused'), key);
  }
  for (const value of ['--inspect', '--require ./x.cjs', ' --max-old-space-size=4096']) {
    assert.throws(() => refuseDebug({ PATH: 'x', NODE_OPTIONS: value }, [], off), refusal('debug_refused'), value);
  }
  assert.throws(() => refuseDebug({ PATH: 'x', node_options: '--inspect' }, [], off), refusal('debug_refused'));
  for (const flag of ['--inspect', '--inspect=0', '--inspect-brk', '--inspect-brk=9229', '--inspect-wait', '--debug', '-r',
    '--require', '--require=x', '--import=x', '--loader=x', '--experimental-loader=x']) {
    assert.throws(() => refuseDebug({ PATH: 'x' }, ['--no-warnings', flag], off), refusal('debug_refused'), flag);
  }
  // Node 24's test runner passes these defaults to every test process; they start no inspector and load no code.
  assert.doesNotThrow(() => refuseDebug({ PATH: 'x' },
    ['--inspect-port=127.0.0.1:9229', '--inspect-publish-uid=stderr,http', '--test-isolation=process'], off));
  assert.throws(() => refuseDebug({ PATH: 'x' }, [], () => true), refusal('debug_refused'), 'an active inspector');
  assert.doesNotThrow(() => refuseDebug({ PATH: 'x', PGSSLMODE: 'require', NODE_OPTIONS: '' }, ['--no-warnings'], off));
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

test('passfile: read as the CLI reads it (pgpassfile v1.0.0); exact single entry, no wildcard, nothing ambiguous', () => {
  const t = { host: '127.0.0.1', port: '56622', database: 'postgres', user: 'postgres' };
  assert.equal(selectPassfileEntry(parsePassfile(`# comment\n\n127.0.0.1:56622:postgres:postgres:${CANARY}\n`), t), CANARY);
  assert.equal(selectPassfileEntry(parsePassfile('127.0.0.1:56622:postgres:postgres:a\\:b\\:c\\\\d\r\n'), t), 'a:b:c\\d');
  assert.equal(selectPassfileEntry(parsePassfile('127.0.0.1:56622:postgres:postgres:a\\\\\\:b\n'), t), 'a\\:b');
  assert.equal(selectPassfileEntry(parsePassfile('h\\:x:1:d:u:p\nother:1:d:u:q\n'), { host: 'h:x', port: '1', database: 'd', user: 'u' }), 'p');
  assert.equal(selectPassfileEntry(parsePassfile('127.0.0.1:56623:postgres:postgres:x\n127.0.0.1:56622:postgres:postgres:y\n'), t), 'y');
  assert.equal(selectPassfileEntry(parsePassfile('127.0.0.1:56622:postgres:postgres:p w\n'), t), 'p w');
  for (const [text, code] of [
    ['127.0.0.1:56622:postgres\n', 'passfile_malformed'],
    ['127.0.0.1:56622:postgres:postgres:x\\\n', 'passfile_malformed'],
    // Readers disagree on these (the CLI would ignore the line, trim it or read another escape), so none is guessed.
    ['127.0.0.1:56622:postgres:postgres:a:b\n', 'passfile_malformed'],
    [' 127.0.0.1:56622:postgres:postgres:p1\n127.0.0.1:56622:postgres:postgres:p2\n', 'passfile_malformed'],
    ['127.0.0.1:56622:postgres:postgres:p1  \n', 'passfile_malformed'],
    ['127.0.0.1:56622:postgres:postgres:pa\\ss\n', 'passfile_malformed'],
    ['127.0.0.1:56622:postgres:postgres:p\t1\n', 'passfile_malformed'],
    ['\ufeff127.0.0.1:56622:postgres:postgres:p\n', 'passfile_malformed'],
    ['  # an indented comment\n127.0.0.1:56622:postgres:postgres:p\n', 'passfile_malformed'],
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
  // A child folder whose name starts with two dots is still inside.
  assert.ok(passfileLocationProblem(path.join(root, '..private', 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.join(workdir, '..x', 'pgpass'), { repoRoot: repo, workdir }));
  assert.ok(passfileLocationProblem(path.join(repo, '..pgpass'), { repoRoot: repo, workdir }));
  assert.equal(passfileLocationProblem(path.resolve(path.sep, 'private', 'gr37', 'pgpass'), { repoRoot: repo, workdir }), null);
  assert.equal(passfileLocationProblem(path.resolve(path.sep, '..private', 'gr37', 'pgpass'), { repoRoot: repo, workdir }), null);
});

test('passfile location: a device-path spelling of a file inside the repository is still inside (Windows)',
  { skip: process.platform !== 'win32' && 'Windows path spellings' }, () => {
    const repo = mkdtempSync(path.join(scratch, 'repo-'));
    const work = mkdtempSync(path.join(scratch, 'work-'));
    const file = path.join(repo, 'pgpass');
    writeFileSync(file, `127.0.0.1:56622:postgres:postgres:${CANARY}\n`);
    const target = { host: '127.0.0.1', port: '56622', database: 'postgres', user: 'postgres' };
    // The location gate runs before the ACL gate, so a spelling that escaped it would fail later, on permissions.
    for (const raw of [file, `\\\\?\\${file}`]) {
      assert.throws(() => verifyPassfile(raw, target, work, { repoRoot: repo }),
        (e) => e.code === 'passfile_location' && !e.message.includes(CANARY), raw);
    }
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
  // A line the CLI flags as an error is kept even when it happens to contain an advice phrase.
  const advicePhrase = summarize('Applying migration x...\nERROR: relation "app.db reset_marker" does not exist (SQLSTATE 42P01)\nAt statement: 7\n', true);
  assert.match(advicePhrase, /db reset_marker/);
  assert.match(advicePhrase, /At statement: 7/);
});

test('CLI output summary: a ledger mismatch keeps the error and never relays the CLI\'s repair or include-all advice', () => {
  const advice = /migration repair|db pull|db reset|--include-all|--debug|try repairing|update local migrations|make sure your local git repo/i;
  // The pinned CLI's text when the remote history holds a version the local folder lacks (rehearsal D).
  const remoteAhead = [
    'Using workdir <redacted>', 'DRY RUN: migrations will *not* be pushed to the database.', 'Connecting to local database...',
    'Remote migration versions not found in local migrations directory.', '',
    'Make sure your local git repo is up-to-date. If the error persists, try repairing the migration history table:',
    'supabase migration repair --status reverted 20261104131256', '', 'And update local migrations to match remote database:',
    'supabase db pull',
  ].join('\n');
  const a = summarize(remoteAhead, true);
  assert.match(a, /Remote migration versions not found in local migrations directory/);
  assert.ok(!advice.test(a), a);
  // ... and when a pending local version sorts before the remote's latest.
  const outOfOrder = [
    'Connecting to remote database...', 'Found local migration files to be inserted before the last migration on remote database.', '',
    'Rerun the command with --include-all flag to apply these migrations:', `supabase/migrations/${MIGRATION}`,
  ].join('\n');
  const b = summarize(outOfOrder, true);
  assert.match(b, /inserted before the last migration on remote database/);
  assert.ok(!advice.test(b) && !/rerun the command/i.test(b), b);
  // Advice lines are dropped even when no line is recognised as an error.
  assert.equal(summarize('something unexpected\nsupabase migration repair --status applied 1\nsupabase db pull\n', true), '    something unexpected');
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

// =====================================================================================================================
// One-time exact-gap mode (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001, DECISION D-066).
// =====================================================================================================================
const EG = EXACT_GAP;
const MIGRATIONS = 'supabase/migrations';
const inGitTree = () => {
  const r = spawnSync('git', ['-C', REPO, 'rev-parse', '--is-inside-work-tree'], { encoding: 'utf8' });
  return r.status === 0 && r.stdout.trim() === 'true';
};
const gitBlob = (file) => {
  const r = spawnSync('git', ['-C', REPO, 'cat-file', 'blob', `HEAD:${MIGRATIONS}/${file}`], { maxBuffer: 1 << 28 });
  assert.equal(r.status, 0, `HEAD:${MIGRATIONS}/${file} is not committed`);
  return r.stdout;
};
const gitMigrationNames = () => {
  const r = spawnSync('git', ['-C', REPO, 'ls-tree', '--name-only', `HEAD:${MIGRATIONS}`], { encoding: 'utf8', maxBuffer: 1 << 26 });
  assert.equal(r.status, 0);
  return r.stdout.split('\n').filter((n) => n.endsWith('.sql')).sort();
};

// A top-level statement splitter (quotes, identifiers, dollar quotes, line and nested block comments) used only to
// re-derive the pins from the committed bytes.
function splitSql(sql) {
  const out = [];
  let i = 0;
  let start = 0;
  while (i < sql.length) {
    const c = sql[i];
    if (c === '-' && sql[i + 1] === '-') { const e = sql.indexOf('\n', i); i = e < 0 ? sql.length : e + 1; continue; }
    if (c === '/' && sql[i + 1] === '*') {
      let depth = 1;
      i += 2;
      while (i < sql.length && depth > 0) {
        if (sql[i] === '/' && sql[i + 1] === '*') { depth += 1; i += 2; } else if (sql[i] === '*' && sql[i + 1] === '/') { depth -= 1; i += 2; } else i += 1;
      }
      continue;
    }
    if (c === "'" || c === '"') {
      i += 1;
      while (i < sql.length) { if (sql[i] === c && sql[i + 1] === c) { i += 2; continue; } if (sql[i] === c) { i += 1; break; } i += 1; }
      continue;
    }
    if (c === '$') {
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(sql.slice(i, i + 80));
      if (m) { const e = sql.indexOf(m[0], i + m[0].length); i = e < 0 ? sql.length : e + m[0].length; continue; }
    }
    if (c === ';') { out.push(sql.slice(start, i + 1)); start = i + 1; }
    i += 1;
  }
  if (sql.slice(start).trim()) out.push(sql.slice(start));
  return out;
}
const lead = (s) => {
  let t = s;
  for (;;) {
    const before = t;
    t = t.replace(/^\s+/, '').replace(/^--[^\n]*\n?/, '').replace(/^\/\*[\s\S]*?\*\//, '');
    if (t === before) return t;
  }
};
const createdFunctionNames = (sql) => splitSql(sql).map(lead)
  .map((s) => /^create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(/i.exec(s))
  .filter(Boolean).map((m) => `${m[1]}.${m[2]}`);
function createdFunctions(sql) {
  const out = [];
  for (const stmt of splitSql(sql).map(lead)) {
    const head = /^create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(/i.exec(stmt);
    if (!head) continue;
    const asAt = stmt.search(/\bas\s+\$([A-Za-z_][A-Za-z0-9_]*)?\$/i);
    const tag = /\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(stmt.slice(asAt));
    const start = asAt + tag.index + tag[0].length;
    const end = stmt.indexOf(tag[0], start);
    const attrs = `${stmt.slice(0, asAt)} ${stmt.slice(end + tag[0].length)}`.replace(/--[^\n]*/g, ' ').replace(/\s+/g, ' ').toLowerCase();
    const set = /\bset\s+search_path\s*(?:=|to)\s*('[^']*'|"[^"]*"|[a-z_, ]+?)(?=\s+(?:language|security|stable|immutable|volatile|as|returns|cost|rows|parallel|strict|called|leakproof|not|set)\b|\s*;|$)/.exec(attrs);
    const value = set ? set[1].trim() : null;
    out.push([`${head[1]}.${head[2]}`, sha(Buffer.from(stmt.slice(start, end), 'utf8')), /\bsecurity\s+definer\b/.test(attrs),
      value === null ? '' : `search_path=${value === "''" ? '""' : value.replace(/^'(.*)'$/, '$1')}`,
      /\bimmutable\b/.test(attrs) ? 'i' : /\bstable\b/.test(attrs) ? 's' : 'v', (/\blanguage\s+([a-z]+)/.exec(attrs) || [])[1]]);
  }
  return out;
}
function grantSets(sql) {
  const sets = new Map();
  for (const raw of splitSql(sql)) {
    const s = lead(raw).replace(/--[^\n]*\n/g, ' ').replace(/\s+/g, ' ').trim();
    const m = /^(grant|revoke)\s+(.+?)\s+on\s+function\s+(.+?)\s+(to|from)\s+(.+?);?$/i.exec(s);
    if (!m) continue;
    for (const name of m[3].match(/(?:app|public)\.[a-z_0-9]+(?=\()/g) || []) {
      sets.set(name, [...(sets.get(name) || []), `${m[1].toLowerCase()} ${m[2].toLowerCase()} ${m[4].toLowerCase()} ${m[5].split(',').map((r) => r.trim().toLowerCase()).join(',')}`]);
    }
  }
  return sets;
}

test('exact-gap: the pinned constants are the authorization\'s values and cannot be changed', () => {
  assert.equal(EXACT_GAP_MODE, 'BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001');
  assert.equal(EXACT_GAP_FLAG, '--exact-gap');
  assert.equal(ENV_SSLROOTCERT, 'BIZBOT_GR37_SSLROOTCERT');
  assert.equal(READONLY_STARTUP_OPTIONS, `-c default_transaction_read_only=on ${STARTUP_OPTIONS}`);
  assert.equal(ACCEPTED_HOSTED_CA_SHA256, '80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA');
  assert.equal(EG.missingVersion, '20261104141959');
  assert.equal(EG.missingFile, '20261104141959_bizbot_zcredit_001d_server_ledger.sql');
  assert.equal(EG.missingSha256, '468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e');
  // POST-386-REPIN-001 (current main 28c41911, D-068): 189 local migrations; hosted holds 188, the only difference 20261104141959
  // (REPIN-001 pinned 0fe8ef80's 188 / 187).
  assert.equal(EG.localCount, 189);
  assert.equal(EG.remoteCountBefore, 188);
  assert.deepEqual(EG.localTail.map(([n]) => n.slice(0, 14)), ['20261104131256', '20261104141959', '20261105025413', '20261105025604', '20261105141815', '20261108085442']);
  assert.deepEqual(EG.remoteTail, ['20261104131256', '20261105025413', '20261105025604', '20261105141815', '20261108085442']);
  assert.deepEqual(EG.laterHosted, ['20261105025413', '20261105025604', '20261105141815', '20261108085442']);
  assert.deepEqual(EG.localTail.map(([n]) => n.slice(0, 14)).filter((v) => !EG.remoteTail.includes(v)), [EG.missingVersion], 'the symmetric difference of the tails');
  assert.deepEqual(EG.remoteTail.filter((v) => !EG.localTail.some(([n]) => n.startsWith(v))), []);
  assert.equal(EG.localTail.find(([n]) => n.startsWith('20261105141815'))[0], '20261105141815_bizbot_storefront_background_clarity_001_api.sql');
  assert.equal(EG.localTail.find(([n]) => n.startsWith('20261108085442'))[0], '20261108085442_bizbot_pos_long_shift_alerts_001.sql');
  assert.deepEqual(Object.fromEntries(Object.entries(EG.storedStatements).map(([v, [, h]]) => [v, h])), {
    20261104131256: 'a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b',
    20261105025413: 'a901a709970b4629b22357743831aab687c2882fe066776dd7913b82c29c77d5',
    20261105025604: '7bfac52a707b20fdf9b67a466d84290a7565fe574850ce1e992c093d5f19b520',
    20261105141815: 'e5cf4b2840837facc5699cecb154689a7439383ac4d6650f13746d5e68bd8504',
    20261108085442: '7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865',
  });
  for (const [n, h] of EG.localTail) if (n !== MIGRATION) assert.equal(EG.storedStatements[n.slice(0, 14)][1], h, n);
  for (const [v, [name]] of Object.entries(EG.storedStatements)) assert.equal(`${v}_${name}.sql`, EG.localTail.find(([n]) => n.startsWith(v))[0], v);
  assert.deepEqual({ ...EG.runtime }, { serverVersionNum: '170006', timeZone: 'UTC' });
  assert.equal(EG.functions.length, 62);
  assert.equal(new Set(EG.functions.map((f) => f[0])).size, 62);
  const groups = {};
  for (const f of EG.functions) groups[f[6]] = (groups[f[6]] || 0) + 1;
  assert.deepEqual(groups, { none: 39, authenticated: 4, service_role: 12, recreated: 7 });
  assert.deepEqual(Object.keys(EG.recreated).sort(), EG.functions.filter((f) => f[6] === 'recreated').map((f) => f[0]).sort());
  assert.deepEqual(Object.keys(EG.recreatedBefore).sort(), Object.keys(EG.recreated).sort());
  assert.equal(EG.missingName, EG.missingFile.slice(15, -4));
  assert.equal(EG.configSha256, '447beeba30b17a739beede822807a9f0b19590e9e31abd4605b0ffc06a9a6bd7');
  assert.deepEqual([...EG.allowedDotenv], ['.env.example']);
  assert.deepEqual({ ...EG.missingRow }, { n: 125, all: '49b5e0fc873a7d13cbeee14040868ad4162b5f0f5204c65eb6259b6da5147309' });
  for (const value of [EG, EG.functions, EG.functions[0], EG.localTail, EG.localTail[0], EG.storedStatements, EG.recreated, EG.recreated['app.sync_push'], EG.policy, EG.tables,
    EG.recreatedBefore, EG.missingRow, EG.allowedDotenv, EG.policy.roles, EG.access, EG.access.functions, EG.access.functions.none,
    EG.access.functions.none[0], EG.access.recreated, EG.access.recreated['app.sync_push'], EG.access.table, EG.access.table[0], EG.access.sequence,
    EG.access.columns, EG.runtime, EG.remoteTail, EG.laterHosted, EG.surfaceFunctions, EG.surfaceTables, EG.surface382, EG.surface382.functions,
    EG.surface382.functions[0], EG.surface382.access, EG.surface382.access.anon_service_role, EG.surface382.access.anon_service_role[0],
    EG.surface382.relation, EG.surface382.relation.access, EG.surface382.relation.columns, EG.surface382.policies, EG.surface382.policies[0],
    EG.surface382.policies[0].roles, EG.surface386, EG.surface386.functions, EG.surface386.functions[0], EG.surface386.access,
    EG.surface386.access.service_role, EG.surface386.access.service_role[0], EG.surface386.inheritedAccess,
    EG.surface386.inheritedAccess['app.pos_order_alert_authority'], EG.surface386.relations, EG.surface386.relations[0],
    EG.surface386.relations[0].policies, EG.surface386.relations[0].access, EG.surface386.relations[0].columns, EG.surface386.triggers,
    EG.surface386.triggers[0]]) {
    assert.ok(Object.isFrozen(value));
  }
  assert.throws(() => { EG.localCount = 1; }, TypeError);
  assert.throws(() => { EG.functions.push(['x']); }, TypeError);
  assert.throws(() => { EG.runtime.serverVersionNum = '160004'; }, TypeError);
  assert.throws(() => { EG.surface382.policies[1].using = 'true'; }, TypeError);
  assert.throws(() => { EG.surface386.triggers[0][1] = 'x'; }, TypeError);
});

test('exact-gap: the 001D manifest pins equal the committed migration bytes', (t) => {
  if (!inGitTree()) return t.skip('not a Git work tree');
  const bytes = gitBlob(MIGRATION);
  assert.ok(sha(bytes) === MIGRATION_SHA256);
  const sql = bytes.toString('utf8');
  assert.deepEqual(createdFunctions(sql), EG.functions.map((f) => f.slice(0, 6)));
  const earlier = new Set(gitMigrationNames().filter((n) => n < MIGRATION).flatMap((n) => createdFunctionNames(gitBlob(n).toString('utf8'))));
  const sets = grantSets(sql);
  const groupOf = (name) => {
    if (earlier.has(name)) return 'recreated';
    return {
      'revoke all from public,anon,authenticated,service_role': 'none',
      'revoke all from public,anon,authenticated,service_role;grant execute to authenticated': 'authenticated',
      'revoke all from public,anon,authenticated,service_role;grant execute to service_role': 'service_role',
    }[(sets.get(name) || []).join(';')] ?? 'unexpected';
  };
  assert.deepEqual(EG.functions.map((f) => groupOf(f[0])), EG.functions.map((f) => f[6]));
  for (const [name, rule] of Object.entries(EG.recreated)) {
    const steps = sets.get(name) || [];
    const derived = {};
    for (const s of steps) {
      const [verb, , dir, roles] = s.split(' '); // "<grant|revoke> <privilege> <to|from> <role,role>"
      for (const role of roles.split(',')) derived[role] = verb === 'grant' && dir === 'to';
    }
    assert.deepEqual(derived, rule, name);
  }
  const objects = splitSql(sql).map(lead);
  const tables = objects.map((s) => /^create\s+table\s+([a-z_]+\.[a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => m[1]);
  const indexes = objects.map((s) => /^create\s+(?:unique\s+)?index\s+([a-z_0-9]+)\s+on\s+app\.([a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => `${m[1]}@${m[2]}`);
  const triggers = objects.map((s) => /^create\s+(?:or\s+replace\s+)?trigger\s+([a-z_0-9]+)[\s\S]*?\son\s+app\.([a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => `${m[1]}@${m[2]}`);
  assert.deepEqual(tables, [...EG.tables]);
  assert.deepEqual(indexes, [...EG.indexes]);
  assert.deepEqual(triggers, [...EG.triggers]);
  assert.ok(sql.includes(EG.sequence.split('.')[1]), 'the identity sequence is named in the migration');
  // The policy: the lockdown loop's one format string, applied to exactly the pinned tables; no other policy statement.
  const loop = /foreach\s+t\s+in\s+array\s+array\[([^\]]+)\]\s+loop([\s\S]*?)end\s+loop;/i.exec(sql);
  assert.ok(loop, 'the lockdown loop');
  assert.deepEqual(loop[1].split(',').map((s) => `app.${s.trim().replace(/^'|'$/g, '')}`), [...EG.tables]);
  const policies = [...loop[2].matchAll(/create policy ([a-z_]+) on app\.%I (as (?:permissive|restrictive) )?for (all|select|insert|update|delete) to ([a-z_]+) using\(([^)]*)\) with check\(([^)]*)\)/gi)];
  assert.equal(policies.length, 1);
  const [, name, as, cmd, role, using, check] = policies[0];
  assert.deepEqual({ ...EG.policy, roles: [...EG.policy.roles] }, {
    name, cmd: { all: '*', select: 'r', insert: 'a', update: 'w', delete: 'd' }[cmd.toLowerCase()],
    permissive: !/restrictive/i.test(as ?? ''), roles: [role], using, check,
  });
  assert.equal((sql.match(/create\s+policy/gi) || []).length, 1, 'no other policy statement');
  // The 001D history row's pinned statement count is the file's number of top-level statements.
  assert.equal(objects.filter((s) => s.trim()).length, EG.missingRow.n);
});

test('exact-gap: the re-created functions\' pre-001D pins are their latest definitions in the other 188 files', (t) => {
  if (!inGitTree()) return t.skip('not a Git work tree');
  const names = gitMigrationNames().slice(0, EG.localCount);
  const latest = new Map();
  for (const n of names.filter((x) => x !== MIGRATION)) {
    for (const [name, src] of createdFunctions(gitBlob(n).toString('utf8'))) if (name in EG.recreatedBefore) latest.set(name, src);
  }
  assert.deepEqual(Object.fromEntries([...latest].sort()), Object.fromEntries(Object.entries(EG.recreatedBefore).sort()));
  // The files after 001D (#380's two, #382's one and #386's one) define none of 001D's functions, so the out-of-order apply
  // overrides no newer body.
  assert.deepEqual(names.filter((x) => x > MIGRATION).map((n) => n.slice(0, 14)), EG.laterHosted);
  const touched = new Set(EG.functions.map((f) => f[0]));
  for (const n of names.filter((x) => x > MIGRATION)) {
    assert.deepEqual(createdFunctionNames(gitBlob(n).toString('utf8')).filter((f) => touched.has(f)), [], n);
  }
});

test('exact-gap: the local-set pins equal the 189 oldest committed migrations; the surfaces their files', (t) => {
  if (!inGitTree()) return t.skip('not a Git work tree');
  const names = gitMigrationNames().slice(0, EG.localCount);
  assert.equal(names.length, EG.localCount);
  assert.equal(sha(Buffer.from(names.join('\n'), 'utf8')), EG.localNamesSha256);
  assert.equal(sha(Buffer.from(names.map((n) => `${n} ${sha(gitBlob(n))}`).join('\n'), 'utf8')), EG.localBytesSha256);
  assert.deepEqual(names.slice(-EG.localTail.length), EG.localTail.map(([n]) => n));
  for (const [n, h] of EG.localTail) assert.ok(sha(gitBlob(n)) === h, n);
  // The #379 / #380 / #382 surfaces: the four earlier later-hosted files (#386's surface has its own pins, surface386).
  const surface = names.filter((n) => EG.remoteTail.includes(n.slice(0, 14)) && n.slice(0, 14) !== EG.surface386.version).map((n) => gitBlob(n).toString('utf8'));
  assert.deepEqual([...new Set(surface.flatMap(createdFunctionNames))].sort(), [...EG.surfaceFunctions]);
  const tables = [...new Set(surface.flatMap((s) => splitSql(s).map(lead).map((x) => /^create\s+table\s+([a-z_]+\.[a-z_0-9]+)/i.exec(x)).filter(Boolean).map((m) => m[1])))].sort();
  assert.deepEqual(tables, [...EG.surfaceTables]);
  // The workdir's other CLI inputs: main's config.toml bytes; the dotenv files main ships are only .env.example.
  const config = spawnSync('git', ['-C', REPO, 'cat-file', 'blob', 'HEAD:supabase/config.toml'], { maxBuffer: 1 << 24 });
  assert.equal(config.status, 0);
  assert.equal(sha(config.stdout), EG.configSha256);
  for (const tree of ['HEAD', 'HEAD:supabase']) {
    const r = spawnSync('git', ['-C', REPO, 'ls-tree', '--name-only', tree], { encoding: 'utf8' });
    assert.equal(r.status, 0);
    assert.deepEqual(r.stdout.split('\n').filter((n) => /^\.env(?:\.|$)/i.test(n)).filter((n) => !EG.allowedDotenv.includes(n)), [], tree);
  }
});

test('exact-gap arguments: one flag with its one Work ID; a caller\'s --include-all or repair is refused by name', () => {
  const wd = path.resolve(scratch);
  const ok = ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE];
  assert.deepEqual(parseExactGapArgs(ok), { mode: 'local', projectRef: null, workdir: wd, apply: false, exactGap: EXACT_GAP_MODE });
  assert.deepEqual(parseExactGapArgs([EXACT_GAP_FLAG, EXACT_GAP_MODE, '--mode', 'hosted', '--project-ref', REF, '--workdir', wd, '--apply']),
    { mode: 'hosted', projectRef: REF, workdir: wd, apply: true, exactGap: EXACT_GAP_MODE });
  for (const extra of [['--include-all'], ['--include_all'], ['include-all'], ['--include-all=true'], ['--INCLUDE-ALL'], ['-include-all']]) {
    assert.throws(() => parseExactGapArgs([...ok, ...extra]), refusal('include_all_refused'), extra.join(' '));
  }
  for (const extra of [['repair'], ['--repair'], ['migration', 'repair'], ['migration-repair'], ['--repair=applied']]) {
    assert.throws(() => parseExactGapArgs([...ok, ...extra]), refusal('repair_refused'), extra.join(' '));
  }
  for (const value of ['OTHER-WORK-ID', CANARY, EXACT_GAP_MODE.toLowerCase(), ` ${EXACT_GAP_MODE}`, '--apply']) {
    assert.throws(() => parseExactGapArgs(['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, value]),
      (e) => e.code === 'exact_gap_mode_unknown' && !e.message.includes(CANARY), value);
  }
  assert.throws(() => parseExactGapArgs(['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG]), refusal('exact_gap_mode_unknown'));
  assert.throws(() => parseExactGapArgs([...ok, EXACT_GAP_FLAG, EXACT_GAP_MODE]), refusal('bad_arguments'));
  assert.throws(() => parseExactGapArgs(['--mode', 'local', '--workdir', wd, `${EXACT_GAP_FLAG}=${EXACT_GAP_MODE}`]), refusal('bad_arguments'));
  assert.throws(() => parseExactGapArgs([...ok, '--target', 'x']), refusal('bad_arguments'));
  assert.throws(() => parseExactGapArgs([...ok, '--debug']), refusal('debug_refused'));
  assert.throws(() => parseExactGapArgs([...ok, '--log-level', 'debug']), refusal('debug_refused'));
  // The default parser never learned the flag: it stays an unknown argument there.
  assert.throws(() => parseArgs(ok), refusal('bad_arguments'));
});

test('exact-gap commands: --include-all only in its two db push commands; read-only URLs; verify-full child environment', () => {
  const target = parseTargetUrl(LOCAL, { mode: 'local' });
  const ro = buildReadOnlyDbUrl(target);
  const rw = buildDbUrl(target);
  assert.equal(ro, 'postgresql://postgres@127.0.0.1:56622/postgres?options=-c%20default_transaction_read_only%3Don%20-c%20lock_timeout%3D5s%20-c%20statement_timeout%3D60s%20-c%20application_name%3Dbizbot_gr37_001d_v1');
  assert.equal(new URL(ro).password, '');
  assert.deepEqual([...new URL(ro).searchParams.keys()], ['options']);
  assert.equal(readOnlyUrlShape('hosted'), `postgresql://<user>@<direct-host>:5432/<database>?options=${encodeURIComponent(READONLY_STARTUP_OPTIONS)}`);
  assert.deepEqual(exactGapDryRunArgs(ro, 'W'), ['db', 'push', '--include-all', '--dry-run', '--db-url', ro, '--workdir', 'W', '--agent', 'no']);
  assert.deepEqual(exactGapPushArgs(rw, 'W'), ['db', 'push', '--include-all', '--db-url', rw, '--workdir', 'W', '--yes', '--agent', 'no']);
  assert.deepEqual(exactGapNormalDryRunArgs(ro, 'W'), [...dryRunArgs(ro, 'W'), '--agent', 'no']);
  assert.deepEqual(migrationListArgs(ro, 'W'), ['migration', 'list', '--db-url', ro, '--workdir', 'W', '--agent', 'no']);
  assert.deepEqual(stateQueryArgs(ro, 'F', 'W'), ['db', 'query', '--db-url', ro, '--file', 'F', '--output', 'json', '--workdir', 'W', '--agent', 'no']);
  for (const args of [exactGapDryRunArgs(ro, 'W'), exactGapPushArgs(rw, 'W')]) assert.equal(args.filter((a) => a === '--include-all').length, 1);
  for (const args of [dryRunArgs(rw, 'W'), pushArgs(rw, 'W'), exactGapNormalDryRunArgs(ro, 'W'), migrationListArgs(ro, 'W'), stateQueryArgs(ro, 'F', 'W')]) {
    assert.ok(!args.some((a) => /include-all/.test(a)), args.join(' '));
  }
  for (const args of [exactGapDryRunArgs(ro, 'W'), exactGapPushArgs(rw, 'W'), exactGapNormalDryRunArgs(ro, 'W'), migrationListArgs(ro, 'W'), stateQueryArgs(ro, 'F', 'W')]) {
    assert.ok(!args.some((a) => /repair|debug|log-level/.test(a)) && !args.some((a) => /:\/\/[^@]*:[^@]*@/.test(a)), args.join(' '));
  }
  // The default route's two commands are unchanged (no --agent flag was added there).
  assert.deepEqual(dryRunArgs(rw, 'W'), ['db', 'push', '--dry-run', '--db-url', rw, '--workdir', 'W']);
  assert.deepEqual(pushArgs(rw, 'W'), ['db', 'push', '--db-url', rw, '--workdir', 'W', '--yes']);
  assert.ok(connectedLocally('Using workdir W\nConnecting to local database...\n') && !connectedLocally('Connecting to remote database...\n'));
  const parent = {
    Path: 'P', SystemRoot: 'S', PGSSLROOTCERT: 'parent-ca', PGSSLMODE: 'disable', PGPASSWORD: CANARY, SUPABASE_DB_PASSWORD: CANARY,
    SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED: 'true', PGSERVICE: 'other', PGSERVICEFILE: 'other',
  };
  assert.deepEqual(buildExactGapChildEnv(parent, 'PASSFILE', 'CA'), {
    Path: 'P', SystemRoot: 'S', PGPASSFILE: 'PASSFILE', PGSSLMODE: 'verify-full', SUPABASE_TELEMETRY_DISABLED: '1', DO_NOT_TRACK: '1', PGSSLROOTCERT: 'CA',
    SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED: 'false',
  });
  assert.equal(buildChildEnv(parent, 'PASSFILE').PGSSLMODE, 'require', 'the default route keeps PGSSLMODE=require');
  assert.ok(!('PGSSLROOTCERT' in buildChildEnv(parent, 'PASSFILE')), 'the default route never passes a CA');
  assert.ok(!('SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED' in buildChildEnv(parent, 'PASSFILE')), 'the default route child is unchanged');
});

const SYNTHETIC_CONFIG = 'project_id = "synthetic"\n[db]\nport = 54322\n';
// extra: workdir-relative path -> content (null leaves a default file out).
function exactGapFolder(pins, files, extra = {}) {
  const wd = mkdtempSync(path.join(scratch, 'eg-wd-'));
  mkdirSync(path.join(wd, 'supabase', 'migrations'), { recursive: true });
  for (const [name, content] of Object.entries(files)) writeFileSync(path.join(wd, 'supabase', 'migrations', name), content);
  for (const [rel, content] of Object.entries({ 'supabase/config.toml': SYNTHETIC_CONFIG, ...extra })) {
    if (content === null) continue;
    mkdirSync(path.dirname(path.join(wd, rel)), { recursive: true });
    writeFileSync(path.join(wd, rel), content);
  }
  return wd;
}
function syntheticFolderPins(files) {
  const names = Object.keys(files).sort();
  return {
    localCount: names.length,
    localTail: EG.localTail.map(([n]) => [n, sha(Buffer.from(files[n]))]),
    localNamesSha256: sha(Buffer.from(names.join('\n'), 'utf8')),
    localBytesSha256: sha(Buffer.from(names.map((n) => `${n} ${sha(Buffer.from(files[n]))}`).join('\n'), 'utf8')),
    configSha256: sha(Buffer.from(SYNTHETIC_CONFIG)),
    allowedDotenv: ['.env.example'],
  };
}

test('exact-gap local folder: exactly the pinned set (names and bytes), ending with the pinned tail', () => {
  const files = {
    '20260101000000_prefix_a.sql': 'select 1;\n', '20260101000001_prefix_b.sql': 'select 2;\n',
    ...Object.fromEntries(EG.localTail.map(([n], i) => [n, `select ${10 + i};\n`])),
  };
  const pins = syntheticFolderPins(files);
  const okFacts = checkExactGapMigrations(exactGapFolder(pins, files), pins);
  assert.equal(okFacts.files, 2 + EG.localTail.length);
  assert.deepEqual(okFacts.versions.slice(-EG.localTail.length), EG.localTail.map(([n]) => n.slice(0, 14)));
  const without = (name) => Object.fromEntries(Object.entries(files).filter(([n]) => n !== name));
  const cases = [
    [without('20260101000000_prefix_a.sql'), 'local_count'],
    [{ ...files, '20260101000002_prefix_c.sql': 'x' }, 'local_count'],
    [{ ...without('20260101000000_prefix_a.sql'), '20261106000000_later.sql': 'x' }, 'local_tail'],
    [without(MIGRATION), 'local_count'],
    [{ ...without(MIGRATION), '20260101000002_prefix_c.sql': 'x' }, 'local_tail'],
    [{ ...files, [MIGRATION]: files[MIGRATION].replace(/\n/g, '\r\n') }, 'migration_hash'],
    [{ ...without('20260101000000_prefix_a.sql'), '20260101000000_prefix_renamed.sql': 'select 1;\n' }, 'local_names'],
    [{ ...files, '20260101000000_prefix_a.sql': 'select 1; -- changed\n' }, 'local_bytes'],
    [{ ...without('20260101000001_prefix_b.sql'), '20260101000000_prefix_twin.sql': 'x' }, 'migration_version_reused'],
    [{ ...files, 'README.sql': 'x' }, 'migration_name'],
  ];
  for (const [set, code] of cases) assert.throws(() => checkExactGapMigrations(exactGapFolder(pins, set), pins), refusal(code), code);
  assert.throws(() => checkExactGapMigrations(path.join(scratch, 'absent-eg'), pins), refusal('migration_missing'));
  // The workdir's other CLI inputs: main's config.toml, no dotenv file the CLI would load, not linked to a project.
  const gate = (extra) => checkExactGapMigrations(exactGapFolder(pins, files, extra), pins);
  assert.throws(() => gate({ 'supabase/config.toml': null }), refusal('local_config'), 'no config.toml');
  assert.throws(() => gate({ 'supabase/config.toml': SYNTHETIC_CONFIG.replace(/\n/g, '\r\n') }), refusal('local_config'), 'a CRLF config.toml');
  assert.throws(() => gate({ 'supabase/config.toml': SYNTHETIC_CONFIG.replace('54322', '56422') }), refusal('local_config'), 'another port');
  for (const f of ['.env', '.env.local', '.ENV', '.env.production', 'supabase/.env', 'supabase/.env.local', 'supabase/.Env.example.local']) {
    assert.throws(() => gate({ [f]: 'PGSERVICE=other\n' }), refusal('local_dotenv'), f);
  }
  for (const f of ['supabase/.temp/project-ref', 'supabase/.temp/pooler-url']) assert.throws(() => gate({ [f]: REF }), refusal('local_linked'), f);
  // Allowed: main's own .env.example files, the CLI's version-check cache, a pg-delta CA bundle left by an earlier run
  // (the mode turns pg-delta off) and files that only resemble a dotenv name.
  assert.equal(gate({
    '.env.example': 'X=1\n', 'supabase/.env.example': 'X=1\n', 'supabase/.temp/cli-latest': 'v2.107.0',
    'supabase/.temp/pgdelta/pgdelta-target-ca.crt': 'x', 'env.example': 'x', 'supabase/functions/.env': 'x',
  }).files, 2 + EG.localTail.length);
});

// Public test certificates only (throwaway EC P-256 keys, discarded): a self-signed CA, a self-signed non-CA leaf and
// a CA issued by the first one. Valid 2026-11-05 .. 2036-11-02.
const TEST_CA = `-----BEGIN CERTIFICATE-----
MIIBsTCCAVegAwIBAgIUeWpK2xQTdfH+RSNHB4wG+kUC1vcwCgYIKoZIzj0EAwIw
JjEkMCIGA1UEAwwbR1IzNyBleGFjdC1nYXAgdW5pdC10ZXN0IENBMB4XDTI2MTEw
NTA5MTk1M1oXDTM2MTEwMjA5MTk1M1owJjEkMCIGA1UEAwwbR1IzNyBleGFjdC1n
YXAgdW5pdC10ZXN0IENBMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE3oaruXP6
uZKwQL6CI+/dQYqZkj6SMACsUoYUEp6lJPn1xwhRwkTw/nXEw6SAjopj8Zz9X/v4
1J/VGZWEE+UmXKNjMGEwHQYDVR0OBBYEFFUudGtqcaBx9cDJeobLo20efXzyMB8G
A1UdIwQYMBaAFFUudGtqcaBx9cDJeobLo20efXzyMA8GA1UdEwEB/wQFMAMBAf8w
DgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMCA0gAMEUCIQDSBy9OkLyP3W4AJgKF
zxfrQa674HK/9//WqTAJw/YDbgIgBi80RfKkDTNU96g+ZclyDflJDQlIrachDcLn
gAiIKBA=
-----END CERTIFICATE-----
`;
const TEST_LEAF = `-----BEGIN CERTIFICATE-----
MIIBozCCAUigAwIBAgIUIvW90RlJCczH7TNgiUXSmoBXCN4wCgYIKoZIzj0EAwIw
KDEmMCQGA1UEAwwdR1IzNyBleGFjdC1nYXAgdW5pdC10ZXN0IGxlYWYwHhcNMjYx
MTA1MDkxOTUzWhcNMzYxMTAyMDkxOTUzWjAoMSYwJAYDVQQDDB1HUjM3IGV4YWN0
LWdhcCB1bml0LXRlc3QgbGVhZjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABBIt
+FrWM90jKzrZu5LK7nm0WAtcDWdoZ+EehLm8B2ReqwDms17aE3pMzTyQFLLt+RA9
venJJQYEMsxdd9c7w/CjUDBOMB0GA1UdDgQWBBSPoDVHgt9eMEdiAksJ5sWQEoJR
ZDAfBgNVHSMEGDAWgBSPoDVHgt9eMEdiAksJ5sWQEoJRZDAMBgNVHRMBAf8EAjAA
MAoGCCqGSM49BAMCA0kAMEYCIQDvOBpzXxngFcpBF8iIThaL+I3Xn0Afy39wwtXZ
/hmOigIhAMfY3O7yH4ZQjCo1dH14HZ5et173ABnKDwzfDZJG3oEE
-----END CERTIFICATE-----
`;
const TEST_SUB_CA = `-----BEGIN CERTIFICATE-----
MIIBtDCCAVugAwIBAgIUBlxX0LGoVxRtjwu9gbWjJWWkVtgwCgYIKoZIzj0EAwIw
JjEkMCIGA1UEAwwbR1IzNyBleGFjdC1nYXAgdW5pdC10ZXN0IENBMB4XDTI2MTEw
NTA5MTk1M1oXDTM2MTEwMjA5MTk1M1owKjEoMCYGA1UEAwwfR1IzNyBleGFjdC1n
YXAgdW5pdC10ZXN0IHN1YiBDQTBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABD6u
COlkz+zOqXjs75BNRyHPaApsYQYD+NsO4WJUPOjS3Zpd0HHf6sWPPaLEXs2AQr15
Oc83YcmlGFKV98+Lo7qjYzBhMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQD
AgEGMB0GA1UdDgQWBBRjB70Y+uUyRwEAUVY5T+fAV0mbbjAfBgNVHSMEGDAWgBRV
LnRranGgcfXAyXqGy6NtHn188jAKBggqhkjOPQQDAgNHADBEAiBcwDFTAhV3uWuY
GXFVlwgy9OM9nbBo+/ioLBlxkxkRXQIge16gCo7QyjmxUTw3bXpQZX8KCR1VKycT
rziR+/EQInU=
-----END CERTIFICATE-----
`;
const IN_VALIDITY = Date.parse(new X509Certificate(TEST_CA).validFrom) + 86_400_000;
// Owner-only, the way an owner prepares the real file: the current user alone (Windows ACL) or mode 0600.
function ownerOnly(file) {
  if (process.platform === 'win32') {
    const who = spawnSync(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'whoami.exe'), [], { encoding: 'utf8' }).stdout.trim();
    const r = spawnSync(path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'icacls.exe'), [file, '/inheritance:r', '/grant:r', `${who}:(R,W)`], { encoding: 'utf8' });
    assert.equal(r.status, 0, 'icacls could not restrict the test file');
  } else {
    chmodSync(file, 0o600);
  }
}
// A synthetic repository two levels down, so the rule's "project store" (the repository's parent) is a scratch folder
// wherever this checkout lives (a repository mounted at /repo would make the store "/").
function syntheticRepo() {
  const repo = path.join(mkdtempSync(path.join(scratch, 'eg-store-')), 'repo');
  mkdirSync(repo);
  return repo;
}

test('exact-gap CA certificate: one self-signed CA in its validity; hosted mode needs the pinned fingerprint', () => {
  assert.equal(caCertificateProblem(TEST_CA, 'local', IN_VALIDITY), null);
  assert.deepEqual(caCertificateProblem(TEST_CA, 'hosted', IN_VALIDITY)?.[0], 'ca_not_accepted');
  assert.notEqual(new X509Certificate(TEST_CA).fingerprint256, ACCEPTED_HOSTED_CA_SHA256);
  const keyMarker = ['-----BEGIN', 'PRIVATE', 'KEY-----'].join(' ');
  for (const [pem, label] of [
    [TEST_LEAF, 'a non-CA certificate'], [TEST_SUB_CA, 'a CA issued by another CA'], [TEST_CA + TEST_CA, 'two certificates'],
    ['', 'empty'], ['not a certificate', 'garbage'], [`${TEST_CA}${keyMarker}\nAAAA\n`, 'a private key beside it'],
    [TEST_CA.replace('MIIBsTCC', 'MIIBsTCD'), 'a damaged certificate'],
  ]) assert.equal(caCertificateProblem(pem, 'local', IN_VALIDITY)?.[0], 'ca_invalid', label);
  const cert = new X509Certificate(TEST_CA);
  assert.equal(caCertificateProblem(TEST_CA, 'local', Date.parse(cert.validFrom) - 1000)?.[0], 'ca_invalid', 'not yet valid');
  assert.equal(caCertificateProblem(TEST_CA, 'local', Date.parse(cert.validTo) + 1000)?.[0], 'ca_invalid', 'expired');
});

test('exact-gap CA file: absolute, present, outside the store and the workdir, owner-only; the path is never echoed', () => {
  const work = mkdtempSync(path.join(scratch, 'eg-ca-work-'));
  const dir = mkdtempSync(path.join(scratch, 'eg-ca-'));
  const REPO_X = syntheticRepo();
  assert.throws(() => verifyCa(undefined, 'local', work), refusal('ca_missing'));
  assert.throws(() => verifyCa('', 'local', work), refusal('ca_missing'));
  assert.throws(() => verifyCa('relative-ca.pem', 'local', work), refusal('ca_missing'));
  assert.throws(() => verifyCa(path.join(dir, 'absent.pem'), 'local', work), refusal('ca_missing'));
  assert.throws(() => verifyCa(WRAPPER, 'local', work), refusal('ca_location'));
  const inWork = path.join(work, 'ca.pem');
  writeFileSync(inWork, TEST_CA);
  assert.throws(() => verifyCa(inWork, 'local', work, { repoRoot: REPO_X, now: IN_VALIDITY }), refusal('ca_location'));
  const file = path.join(dir, `ca-${CANARY}.pem`);
  writeFileSync(file, TEST_CA);
  // A freshly written file inherits the folder's ACL (Windows); elsewhere it is set to 0644 explicitly (a umask of 077
  // would already make it 0600): not owner-only.
  if (process.platform !== 'win32') chmodSync(file, 0o644);
  assert.throws(() => verifyCa(file, 'local', work, { repoRoot: REPO_X, now: IN_VALIDITY }),
    (e) => e.code === 'ca_permissions' && !e.message.includes(CANARY) && !e.message.includes(dir));
  ownerOnly(file);
  assert.deepEqual(verifyCa(file, 'local', work, { repoRoot: REPO_X, now: IN_VALIDITY }), { path: realpathSync.native(file) });
  assert.throws(() => verifyCa(file, 'hosted', work, { repoRoot: REPO_X, now: IN_VALIDITY }), refusal('ca_not_accepted'));
  writeFileSync(file, TEST_LEAF);
  assert.throws(() => verifyCa(file, 'local', work, { repoRoot: REPO_X, now: IN_VALIDITY }), refusal('ca_invalid'));
});

test('exact-gap state SQL: one read-only statement over pinned names only', () => {
  const sql = exactGapStateSql();
  const bare = sql.replace(/--[^\n]*/g, ' ').replace(/'(?:[^']|'')*'/g, "''");
  assert.equal((bare.match(/;/g) || []).length, 1, 'exactly one statement');
  assert.ok(/^\s*with\s+led\s+as\s*\(/i.test(bare) && /as state;\s*$/.test(bare));
  assert.ok(!/\b(insert|update|delete|merge|create|alter|drop|grant|revoke|truncate|copy|call|do|vacuum|analyze|lock|set|reset|begin|commit|rollback|execute|prepare|listen|notify|refresh|cluster|reindex|comment|security|returning)\b/i.test(bare), 'no write, DDL, transaction or session command');
  for (const name of [...EG.functions.map((f) => f[0]), ...EG.tables, EG.sequence, ...EG.indexes, ...EG.triggers, ...EG.surfaceFunctions, ...EG.surfaceTables,
    ...EG.surface382.functions.map((f) => f[0]), EG.surface382.relation.name, ...EG.surface382.policies.map((p) => p.name),
    ...EG.surface386.functions.map((f) => f[0]), ...EG.surface386.relations.map((r) => r.name), ...EG.surface386.triggers.map((t) => t[0])]) {
    assert.ok(sql.includes(`'${name}'`), name);
  }
  assert.ok(sql.includes('supabase_migrations.schema_migrations') && sql.includes('statements[1]'));
  assert.throws(() => exactGapStateSql({ ...EG, tables: ["app.x'; select 1; --"] }), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql({ ...EG, indexes: ['x@y; drop'] }), refusal('internal_pin'));
  // REPIN-001: the #382 names are pinned constants of the same shapes; its policies must be on storage.objects.
  const s382 = (change) => ({ ...EG, surface382: { ...EG.surface382, ...change } });
  assert.throws(() => exactGapStateSql(s382({ policies: [{ ...EG.surface382.policies[0], name: "x'; drop" }] })), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql(s382({ policies: [{ ...EG.surface382.policies[0], table: 'storage.buckets' }] })), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql(s382({ relation: { ...EG.surface382.relation, name: 'app.x; drop' } })), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql(s382({ functions: [['public.x(', 'a', 'b', true, '', 's', 'sql', 'none']] })), refusal('internal_pin'));
  // D-068: the #386 names are pinned constants of the same shapes; a trigger is name@schema.table.
  const s386 = (change) => ({ ...EG, surface386: { ...EG.surface386, ...change } });
  assert.throws(() => exactGapStateSql(s386({ functions: [['app.x; drop', 'a', 'b', true, '', 'v', 'plpgsql', 'none', 'd']] })), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql(s386({ relations: [{ ...EG.surface386.relations[0], name: "app.x'; drop" }] })), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql(s386({ triggers: [['x@y; drop', 'd']] })), refusal('internal_pin'));
  assert.throws(() => exactGapStateSql(s386({ triggers: [['end_shift_alert_on_shift@shifts', 'd']] })), refusal('internal_pin'), 'an unqualified table');
  // The runtime is read outside the session block (so the state fingerprint covers it).
  assert.ok(sql.includes("'runtime', json_build_object('server_version_num', current_setting('server_version_num'), 'time_zone', current_setting('TimeZone')),"));
});

test('exact-gap answers: the query JSON and the migration list are read strictly', () => {
  const state = { ledger: [], functions: [] };
  // `--agent no` (the pinned form): an array of rows; the CLI's agent mode: an envelope. Both carry exactly one row.
  assert.deepEqual(parseStateRows(`${JSON.stringify([{ state: JSON.stringify(state) }], null, 2)}\n`), state);
  assert.deepEqual(parseStateRows(JSON.stringify({ boundary: 'b', rows: [{ state: JSON.stringify(state) }], warning: 'w' })), state);
  for (const bad of [
    `Connecting...\n${JSON.stringify([{ state: JSON.stringify(state) }])}\n`, JSON.stringify([]), JSON.stringify([{ state: '{}' }, { state: '{}' }]),
    JSON.stringify({ rows: [{ state: JSON.stringify(state) }, { state: '{}' }] }), JSON.stringify({ rows: [{ state: state }] }),
    JSON.stringify({ rows: [] }), JSON.stringify({ rows: [{ state: '{"functions":[]}' }] }), 'not json', '', JSON.stringify({ rows: [{ state: 'nope' }] }),
  ]) assert.equal(parseStateRows(bad), null, bad);
  const listing = ['Using workdir W', '', '   Local          | Remote         | Time (UTC)          ', '  ----------------|----------------|---------------------',
    '   20261104131256 | 20261104131256 | 2026-11-04 13:12:56 ', `   ${EG.missingVersion} |                | 2026-11-04 14:19:59 `,
    '                  | 20261199000000 | 2026-11-99 00:00:00 '].join('\r\n');
  assert.deepEqual(parseMigrationList(listing), [
    { local: '20261104131256', remote: '20261104131256' }, { local: EG.missingVersion, remote: null }, { local: null, remote: '20261199000000' },
  ]);
  assert.equal(parseMigrationList('Remote database is up to date.\n'), null);
});

// Synthetic, internally consistent facts: 183 prefix versions plus the pinned tail.
const EG_LOCAL = (() => {
  const names = [...Array.from({ length: 183 }, (_, i) => `20260101${String(i).padStart(6, '0')}_prefix_${i}.sql`), ...EG.localTail.map(([n]) => n)];
  return { files: names.length, names, versions: names.map((n) => n.slice(0, 14)) };
})();
const PRE_PRIVILEGES = { anon: false, authenticated: true, service_role: false, public: false };
// D-067 (HOSTED-PRE-COMPAT-001): the line-ending facts the state query gives for a canonical LF body (raw SHA-256 =
// LF-normalized SHA-256, no CR); `lf` is the body's line-break count.
const lfFacts = (src, lf) => ({ src, src_lf: src, cr: 0, lf, crlf: 0, lone_cr: false });
// REPIN-001: #382's surface as the state query answers it on the pinned shape (16 storage.objects policies, as on the
// local reference; that digest is never pinned, only compared PRE to POST).
function egSurface382() {
  const S = EG.surface382;
  return {
    functions: S.functions.map(([name, args, src, secdef, config, volatility, language, group, def]) => ({
      name, args, kind: 'f', ...lfFacts(src, 40), secdef, config, volatility, language, owner: 'postgres', def, access: S.access[group].map((e) => [...e]),
    })),
    relations: [{
      name: S.relation.name, kind: S.relation.kind, rls: S.relation.rls, force_rls: S.relation.force_rls, owner: 'postgres',
      access: S.relation.access.map((e) => [...e]), columns: [], definition: S.relation.definition,
    }],
    policies: S.policies.map((p) => ({ ...p, roles: [...p.roles] })),
    objectPolicies: { count: 16, sha256: 'c'.repeat(64) },
  };
}
// D-068 (POST-386-REPIN-001): #386's surface as the state query answers it on the pinned shape.
function egSurface386() {
  const S = EG.surface386;
  const accessOf = (name, group) => (group === 'inherited' ? S.inheritedAccess[name] : S.access[group]).map((e) => [...e]);
  return {
    functions: S.functions.map(([name, args, src, secdef, config, volatility, language, group, def]) => ({
      name, args, kind: 'f', ...lfFacts(src, 30), secdef, config, volatility, language, owner: 'postgres', def, access: accessOf(name, group),
    })),
    relations: S.relations.map((r) => ({
      name: r.name, kind: r.kind, rls: r.rls, force_rls: r.force_rls, owner: 'postgres',
      policies: r.policies.map((p) => ({ name: p.name, cmd: p.cmd, permissive: p.permissive, roles: [...p.roles], using: p.using, check: p.check })),
      access: r.access.map((e) => [...e]), columns: [], definition: r.definition,
    })),
    triggers: S.triggers.map(([name, def]) => ({ name, enabled: 'O', def })),
  };
}
function egPreState() {
  return {
    session: { user: 'postgres', read_only: 'on', lock_timeout: '5s', statement_timeout: '1min', application_name: APPLICATION_NAME, server_version_num: '170006', ssl: true },
    runtime: { server_version_num: '170006', time_zone: 'UTC' },
    ledger: EG_LOCAL.names.filter((n) => n !== MIGRATION).map((n) => {
      const v = n.slice(0, 14);
      const stored = EG.storedStatements[v];
      return { version: v, name: n.slice(15, -4), n: stored ? 1 : 3, first: stored ? stored[1] : `first-${v}`, all: `all-${v}` };
    }),
    functions: EG.functions.filter((f) => f[6] === 'recreated').map(([name, , secdef, config, volatility, language]) => ({
      name, args: 'x', kind: 'f', ...lfFacts(EG.recreatedBefore[name], EG.legacyCrlfBefore[name]?.lineBreaks ?? 22), secdef, config, volatility, language, owner: 'postgres',
      ...(name === 'app.audit_category' ? { anon: false, authenticated: false, service_role: false, public: false } : PRE_PRIVILEGES),
      access: EG.access.recreated[name].map((e) => [...e]),
    })),
    relations: [], indexes: [], triggers: [], cardRelations: 0, cardFunctions: 0,
    surfaceFunctions: EG.surfaceFunctions.length, surfaceRelations: EG.surfaceTables.length, surface382: egSurface382(), surface386: egSurface386(),
    otherFunctions: { count: 577, sha256: 'f'.repeat(64) }, otherRelations: { count: 97, sha256: 'e'.repeat(64) },
    defaultAcl: { count: 27, sha256: 'd'.repeat(64) },
  };
}
const GROUPS = {
  none: { anon: false, authenticated: false, service_role: false, public: false },
  authenticated: { anon: false, authenticated: true, service_role: false, public: false },
  service_role: { anon: false, authenticated: false, service_role: true, public: false },
};
function egPostState(original = egPreState()) {
  const pre = JSON.parse(JSON.stringify(original)); // never share a row object with the PRE state
  const ledger = [...pre.ledger, { version: EG.missingVersion, name: EG.missingName, n: EG.missingRow.n, first: 'p', all: EG.missingRow.all }]
    .sort((a, b) => a.version.localeCompare(b.version));
  const functions = EG.functions.map(([name, src, secdef, config, volatility, language, group]) => {
    let privileges = GROUPS[group];
    let access = group === 'recreated' ? EG.access.recreated[name] : EG.access.functions[group];
    if (group === 'recreated') {
      const old = pre.functions.find((f) => f.name === name);
      privileges = { anon: old.anon, authenticated: old.authenticated, service_role: old.service_role, public: old.public };
      access = old.access ?? access; // 001D keeps a re-created function's ACL (CREATE OR REPLACE)
    }
    return { name, args: 'x', kind: 'f', ...lfFacts(src, 60), secdef, config, volatility, language, owner: 'postgres', ...privileges, access: access.map((e) => [...e]) };
  });
  const closed = { owner: 'postgres', anon: false, authenticated: false, service_role: false, public: false };
  const exact = (entries) => ({ access: entries.map((e) => [...e]), columns: [] });
  const relations = [
    ...EG.tables.map((name) => ({ name, kind: 'r', rls: true, force_rls: true, ...closed, policies: [{ ...EG.policy, roles: [...EG.policy.roles] }], ...exact(EG.access.table) })),
    { name: EG.sequence, kind: 'S', rls: false, force_rls: false, ...closed, policies: [], ...exact(EG.access.sequence) },
  ].sort((a, b) => a.name.localeCompare(b.name));
  return { ...pre, ledger, functions, relations, indexes: [...EG.indexes], triggers: EG.triggers.map((t) => `${t}:O`), cardRelations: 6, cardFunctions: 52 };
}
const listText = (rows) => ['   Local          | Remote         | Time (UTC)          ', '  ----------------|----------------|---------------------',
  ...rows.map(([l, r]) => `   ${l ?? '              '} | ${r ?? '              '} | 2026-11-05 00:00:00 `)].join('\n');
const UP_TO_DATE = { code: 0, out: 'Connecting to remote database...\nRemote database is up to date.\n' };
const LIST_OK = { code: 0, out: listText(EG_LOCAL.versions.map((v) => [v, v])) };
const codes = (problems) => problems.map((p) => p[0]);

test('exact-gap PRE gates: the hosted shape passes; every other shape is named', () => {
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), []);
  const variant = (change) => { const s = egPreState(); change(s); return codes(evaluateExactGapPre(s, EG_LOCAL)); };
  const has = (got, ...want) => { for (const w of want) assert.ok(got.includes(w), `${w} not in ${got.join(',')}`); };
  has(variant((s) => { s.ledger = egPostState().ledger; }), 'no_gap', 'remote_count');
  has(variant((s) => { s.ledger = s.ledger.filter((r) => r.version !== EG_LOCAL.versions[5]); }), 'gap_mismatch', 'remote_count');
  has(variant((s) => { s.ledger = egPostState().ledger.filter((r) => r.version !== EG_LOCAL.versions[5]); }), 'gap_mismatch');
  has(variant((s) => { s.ledger.splice(0, 0, { version: '20250101000000', name: 'stray', n: 1, first: 'x', all: 'y' }); }), 'remote_only', 'remote_count');
  has(variant((s) => { s.ledger.push({ version: '20261109000000', name: 'later', n: 1, first: 'x', all: 'y' }); }), 'remote_only', 'remote_tail', 'remote_count');
  // D-068: #386's version is the fourth later-hosted migration and the remote tail's newest.
  has(variant((s) => { s.ledger = s.ledger.filter((r) => r.version !== '20261108085442'); }), 'later_missing', 'remote_tail', 'gap_mismatch', 'remote_count');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261108085442').first = '0'.repeat(64); }), 'stored_statement');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261108085442').n = 78; }), 'stored_statement');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261108085442').name = 'bizbot_pos_long_shift_alerts_001b'; }), 'stored_name');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261108085442').name = null; }), 'stored_name');
  has(variant((s) => { s.ledger = s.ledger.filter((r) => r.version !== '20261108085442'); s.ledger.push({ version: '20261108085443', name: 'other', n: 1, first: 'x', all: 'y' }); }),
    'remote_only', 'remote_tail', 'later_missing', 'gap_mismatch');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105025413').first = '0'.repeat(64); }), 'stored_statement');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105025604').n = 4; }), 'stored_statement');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261104131256').name = 'renamed'; }), 'stored_name');
  has(variant((s) => { s.ledger = s.ledger.filter((r) => r.version !== '20261105025413'); }), 'later_missing', 'remote_tail', 'gap_mismatch');
  // REPIN-001: #382's version is the third later-hosted migration and the remote tail's newest.
  has(variant((s) => { s.ledger = s.ledger.filter((r) => r.version !== '20261105141815'); }), 'later_missing', 'remote_tail', 'gap_mismatch', 'remote_count');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105141815').first = '0'.repeat(64); }), 'stored_statement');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105141815').n = 230; }), 'stored_statement');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105141815').name = 'bizbot_storefront_background_clarity'; }), 'stored_name');
  // The review's SET-382-02: a pinned row with a NULL name is refused (only an unpinned earlier row may carry none).
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105141815').name = null; }), 'stored_name');
  has(variant((s) => { s.ledger.find((r) => r.version === '20261105025604').name = null; }), 'stored_name');
  has(variant((s) => { s.ledger = s.ledger.filter((r) => r.version !== '20261105141815'); s.ledger.push({ version: '20261105141816', name: 'other', n: 1, first: 'x', all: 'y' }); }),
    'remote_only', 'remote_tail', 'later_missing', 'gap_mismatch');
  has(variant((s) => { s.ledger[3].name = 'another_name'; }), 'remote_name');
  assert.deepEqual(variant((s) => { s.ledger[3].name = null; }), [], 'a NULL name on an earlier row is allowed and reported');
  has(variant((s) => { s.relations = [{ name: EG.tables[0] }]; }), 'partial_001d');
  has(variant((s) => { s.functions.push({ ...s.functions[0], name: 'app.card_text_canonical' }); }), 'partial_001d');
  has(variant((s) => { s.indexes = [EG.indexes[0]]; }), 'partial_001d');
  has(variant((s) => { s.triggers = [`${EG.triggers[0]}:O`]; }), 'partial_001d');
  has(variant((s) => { s.cardRelations = 1; }), 'partial_001d');
  has(variant((s) => { s.cardFunctions = 1; }), 'partial_001d');
  has(variant((s) => { s.functions = s.functions.filter((f) => f.name !== 'app.sync_push'); }), 'recreated_missing');
  has(variant((s) => { s.functions.push({ ...s.functions[0] }); }), 'recreated_missing');
  has(variant((s) => { s.surfaceFunctions -= 1; }), 'surfaces_missing');
  has(variant((s) => { s.surfaceRelations = 0; }), 'surfaces_missing');
  has(variant((s) => { s.session.read_only = 'off'; }), 'session_not_read_only');
  has(variant((s) => { s.session.ssl = false; }), 'session_not_tls');
  has(variant((s) => { s.session.lock_timeout = '0'; }), 'session_settings');
  has(variant((s) => { s.session.statement_timeout = '0'; }), 'session_settings');
  has(variant((s) => { s.session.application_name = 'psql'; }), 'session_settings');
  has(variant((s) => { delete s.session; }), 'session_not_read_only', 'session_not_tls', 'session_settings');
  has(variant((s) => { s.ledger.push({ ...s.ledger[0] }); }), 'remote_duplicate');
  // The seven re-created functions must be in their pinned pre-001D form: body, owner and the EXECUTE bits the file sets.
  const fn = (s, name) => s.functions.find((f) => f.name === name);
  has(variant((s) => { fn(s, 'app.sync_push').src = '0'.repeat(64); }), 'recreated_drift');
  has(variant((s) => { fn(s, 'app.audit_category').src = EG.functions.find((f) => f[0] === 'app.audit_category')[1]; }), 'recreated_drift');
  has(variant((s) => { fn(s, 'app.owner_audit_events').owner = 'supabase_admin'; }), 'recreated_drift');
  has(variant((s) => { fn(s, 'app.sync_push').anon = true; }), 'recreated_access');
  has(variant((s) => { fn(s, 'app.pin_session_capabilities').authenticated = false; }), 'recreated_access');
  has(variant((s) => { fn(s, 'app.pos_order_snapshots').public = true; }), 'recreated_access');
  has(variant((s) => { fn(s, 'app.audit_safe_detail').anon = true; }), 'recreated_access');
  has(variant((s) => { fn(s, 'app.audit_category').public = true; }), 'recreated_access');
  // A bit the file does not set is the hosted state 001D keeps (POST then requires it unchanged).
  assert.deepEqual(variant((s) => { fn(s, 'app.sync_push').service_role = true; }), []);
  assert.deepEqual(variant((s) => { fn(s, 'app.audit_action_has_detail').authenticated = false; }), []);
  assert.deepEqual(codes(evaluateExactGapPre(null, EG_LOCAL)), ['state_unreadable']);
});

test('exact-gap POST checks: the applied shape passes; every divergence is named', () => {
  const pre = egPreState();
  const base = () => ({ pre, post: egPostState(pre), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL });
  assert.deepEqual(evaluateExactGapPost(base()), []);
  const variant = (change) => { const v = base(); change(v); return codes(evaluateExactGapPost(v)); };
  const has = (got, ...want) => { for (const w of want) assert.ok(got.includes(w), `${w} not in ${got.join(',')}`); };
  has(variant((v) => { v.post.ledger = v.post.ledger.filter((r) => r.version !== EG.missingVersion); }), 'post_count', 'post_versions', 'post_001d_row');
  has(variant((v) => { v.post.ledger.push({ version: '20261106000000', name: 'x', n: 1, first: 'x', all: 'y' }); }), 'post_versions', 'post_count');
  has(variant((v) => { v.post.ledger.find((r) => r.version === EG.missingVersion).name = 'other'; }), 'post_001d_row');
  has(variant((v) => { v.post.ledger.find((r) => r.version === '20261105025413').all = 'changed'; }), 'post_ledger_changed');
  has(variant((v) => {
    v.normal = { code: 1, out: 'Found local migration files to be inserted before the last migration on remote database.\n\nRerun the command with --include-all flag to apply these migrations:\n' };
  }), 'post_normal_dry_run', 'post_cli_advice');
  has(variant((v) => { v.normal = { code: 0, out: `Would push these migrations:\n \u2022 ${MIGRATION}\n` }; }), 'post_normal_dry_run');
  has(variant((v) => { v.list = { code: 0, out: listText(EG_LOCAL.versions.map((x) => [x, x === EG.missingVersion ? null : x])) }; }), 'post_migration_list');
  has(variant((v) => { v.list = { code: 1, out: 'failed to connect' }; }), 'post_migration_list');
  has(variant((v) => { v.list = { code: 0, out: `${LIST_OK.out}\nsupabase migration repair --status reverted 1\n` }; }), 'post_cli_advice');
  has(variant((v) => { v.post.functions[0].src = 'other'; }), 'post_function');
  has(variant((v) => { v.post.functions.splice(1, 1); }), 'post_function');
  has(variant((v) => { v.post.functions.push({ ...v.post.functions[2] }); }), 'post_function');
  has(variant((v) => { v.post.functions[3].owner = 'supabase_admin'; }), 'post_owner');
  has(variant((v) => { v.post.functions.find((f) => f.name === 'app.card_text_canonical').anon = true; }), 'post_privilege');
  has(variant((v) => { v.post.functions.find((f) => f.name === 'public.card_attempt_claim').authenticated = true; }), 'post_privilege');
  has(variant((v) => { v.post.functions.find((f) => f.name === 'app.audit_category').service_role = true; }), 'post_privilege');
  has(variant((v) => { v.post.functions.find((f) => f.name === 'app.sync_push').authenticated = false; }), 'post_privilege');
  has(variant((v) => { v.post.relations.find((r) => r.name === EG.tables[1]).force_rls = false; }), 'post_table');
  has(variant((v) => { v.post.relations.find((r) => r.name === EG.tables[2]).policies.push({ ...EG.policy, name: 'extra' }); }), 'post_table');
  has(variant((v) => { v.post.relations.find((r) => r.name === EG.tables[3]).authenticated = true; }), 'post_table');
  has(variant((v) => { v.post.relations = v.post.relations.filter((r) => r.name !== EG.tables[4]); }), 'post_table');
  has(variant((v) => { v.post.relations.find((r) => r.name === EG.sequence).anon = true; }), 'post_sequence');
  has(variant((v) => { v.post.indexes.pop(); }), 'post_index');
  has(variant((v) => { v.post.triggers[0] = v.post.triggers[0].replace(/:O$/, ':D'); }), 'post_trigger');
  has(variant((v) => { v.post.surfaceFunctions -= 1; }), 'post_surfaces');
  has(variant((v) => { v.post.otherFunctions = { count: 577, sha256: '0'.repeat(64) }; }), 'post_unchanged');
  has(variant((v) => { v.post.otherRelations = { count: 98, sha256: 'e'.repeat(64) }; }), 'post_unchanged');
  has(variant((v) => { v.post.defaultAcl = { count: 28, sha256: 'd'.repeat(64) }; }), 'post_unchanged');
  has(variant((v) => { v.post.session.read_only = 'off'; }), 'session_not_read_only');
  has(variant((v) => { v.post.session.ssl = false; }), 'session_not_tls');
  has(variant((v) => { v.post.session.statement_timeout = '0'; }), 'session_settings');
  // The 001D row as the pinned CLI records it: once, its name, the pinned statement count and digest.
  const row = (v) => v.post.ledger.find((r) => r.version === EG.missingVersion);
  has(variant((v) => { row(v).n = EG.missingRow.n - 1; }), 'post_001d_row');
  has(variant((v) => { row(v).all = '0'.repeat(64); }), 'post_001d_row');
  has(variant((v) => { v.post.ledger.push({ ...row(v) }); }), 'post_001d_row', 'post_count');
  // Every manifest attribute of a function.
  const f = (v, name) => v.post.functions.find((x) => x.name === name);
  has(variant((v) => { f(v, 'app.card_attempt_claim').kind = 'p'; }), 'post_function');
  has(variant((v) => { f(v, 'app.card_attempt_claim').secdef = false; }), 'post_function');
  has(variant((v) => { f(v, 'app.card_attempt_claim').config = ''; }), 'post_function');
  has(variant((v) => { f(v, 'app.card_attempt_claim').volatility = 's'; }), 'post_function');
  has(variant((v) => { f(v, 'app.card_attempt_claim').language = 'sql'; }), 'post_function');
  has(variant((v) => { f(v, 'app.sync_push').src = EG.recreatedBefore['app.sync_push']; }), 'post_function');
  // The re-created functions keep all four PRE bits, including those the file does not set.
  has(variant((v) => { f(v, 'app.sync_push').service_role = true; }), 'post_privilege');
  has(variant((v) => { f(v, 'app.audit_category').authenticated = true; }), 'post_privilege');
  has(variant((v) => { f(v, 'public.card_attempt_finish').service_role = false; }), 'post_privilege');
  // Every manifest attribute of a table and of the sequence.
  const t = (v, name) => v.post.relations.find((r) => r.name === name);
  has(variant((v) => { t(v, EG.tables[0]).rls = false; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).owner = 'supabase_admin'; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).kind = 'p'; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).anon = true; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).service_role = true; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).public = true; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).policies[0].permissive = false; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).policies[0].roles = ['anon']; }), 'post_table');
  has(variant((v) => { t(v, EG.tables[0]).policies = []; }), 'post_table');
  has(variant((v) => { v.post.relations = v.post.relations.filter((r) => r.name !== EG.sequence); }), 'post_sequence');
  has(variant((v) => { t(v, EG.sequence).kind = 'r'; }), 'post_sequence');
  for (const role of ['authenticated', 'service_role', 'public']) has(variant((v) => { t(v, EG.sequence)[role] = true; }), 'post_sequence');
  // The migration list must have every local version on both sides: a list one row short is divergent.
  has(variant((v) => { v.list = { code: 0, out: listText(EG_LOCAL.versions.filter((x) => x !== EG.missingVersion).map((x) => [x, x])) }; }), 'post_migration_list');
  has(variant((v) => { v.list = { code: 0, out: 'Remote database is up to date.\n' }; }), 'post_migration_list');
  has(variant((v) => { v.normal = null; }), 'post_normal_dry_run');
  has(variant((v) => { v.post.surfaceRelations -= 1; }), 'post_surfaces');
  assert.deepEqual(codes(evaluateExactGapPost({ ...base(), post: null })), ['post_unreadable']);
});

// A fake pinned CLI: answers by command, records every call (arguments and child environment) and checks that each
// state query runs the pinned SQL from an owner-only temporary file.
function egFakeCli(scenario = {}) {
  const calls = [];
  const queryFiles = [];
  let pushed = false;
  let queries = 0;
  const pre = scenario.pre ?? egPreState();
  const run = async (cli, args, env) => {
    calls.push({ cli, args: [...args], env: { ...env } });
    const has = (a) => args.includes(a);
    if (args[0] === '--version') return scenario.version ?? { code: 0, out: '2.107.0\n', stdout: '2.107.0\n' };
    if (args[0] === 'db' && args[1] === 'query') {
      queries += 1;
      const file = args[args.indexOf('--file') + 1];
      queryFiles.push(file);
      assert.equal(readFileSync(file, 'utf8'), exactGapStateSql(), 'the query file holds the pinned state SQL');
      assert.ok(path.basename(path.dirname(file)).startsWith('bizbot-gr37-eg-'), file);
      if (process.platform !== 'win32') assert.equal(statSync(file).mode & 0o077, 0, 'the query file is owner-only');
      if (scenario.queryFailAt === queries) {
        return { code: 1, out: scenario.queryFailOut ?? 'failed to connect to `host=x`: tls: failed to verify certificate', stdout: '' };
      }
      let state = pushed ? (scenario.post ?? egPostState(pre)) : pre;
      if (!pushed && queries === 2 && scenario.changedBeforePush) state = scenario.changedBeforePush;
      const rows = [{ state: JSON.stringify(state) }];
      const stdout = scenario.envelope ? JSON.stringify({ boundary: 'b', rows, warning: 'w' }) : `${JSON.stringify(rows, null, 2)}\n`;
      const local = scenario.queryLocal || (pushed && scenario.queryLocalAfterPush);
      return { code: 0, out: `Connecting to ${local ? 'local' : 'remote'} database...\n${stdout}`, stdout };
    }
    if (args[0] === 'db' && args[1] === 'push' && has('--include-all') && has('--dry-run')) {
      return scenario.dry ?? { code: 0, out: `Connecting to remote database...\nWould push these migrations:\n • ${MIGRATION}\nFinished supabase db push.\n`, stdout: '' };
    }
    if (args[0] === 'db' && args[1] === 'push' && has('--include-all')) {
      pushed = true;
      return scenario.push ?? { code: 0, out: `Applying migration ${MIGRATION}...\nFinished supabase db push.\n`, stdout: '' };
    }
    if (args[0] === 'db' && args[1] === 'push' && has('--dry-run')) {
      if (scenario.normalThrows) throw new Error('synthetic failure after the push');
      return scenario.normal ?? UP_TO_DATE;
    }
    if (args[0] === 'migration' && args[1] === 'list') return scenario.list ?? LIST_OK;
    return { code: 99, out: 'unexpected command', stdout: '' };
  };
  return { run, calls, queryFiles };
}
// Platform-native fake paths (an absolute path on this platform, so path.dirname never yields ".").
const FAKE_ROOT = path.parse(scratch).root;
const EG_PASSFILE = path.join(FAKE_ROOT, 'private', 'gr37', 'pgpass');
const EG_CA = path.join(FAKE_ROOT, 'private', 'gr37', 'supabase-ca.pem');
const EG_CLI = path.join(FAKE_ROOT, 'pinned', 'supabase', 'supabase.exe');
// real: the dependencies left to exactGapMain's own defaults; deps: replacements; env: extra or removed (undefined)
// variables.
async function runExactGap({ argv, scenario = {}, url = LOCAL, mode = 'local', real = [], deps = {}, env: extraEnv = {} } = {}) {
  const wd = path.resolve(scratch);
  const fake = egFakeCli(scenario);
  const env = { Path: 'P', SystemRoot: 'S', [ENV_URL]: url, [ENV_PASSFILE]: EG_PASSFILE, [ENV_SSLROOTCERT]: EG_CA, [ENV_CLI]: EG_CLI, PGPASSWORD: CANARY, ...extraEnv };
  for (const key of Object.keys(env)) if (env[key] === undefined) delete env[key];
  const injected = {
    run: fake.run,
    verifyPassfile: () => ({ path: EG_PASSFILE, secret: CANARY }),
    verifyCa: () => ({ path: EG_CA }),
    checkLocal: () => EG_LOCAL,
    verifyCli: () => EG_CLI,
    ...deps,
  };
  for (const key of real) delete injected[key];
  const lines = [];
  const code = await exactGapMain(argv ?? ['--mode', mode, ...(mode === 'hosted' ? ['--project-ref', REF] : []), '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE, '--apply'],
    env, (l) => lines.push(l), injected);
  return { code, out: lines.join('\n'), calls: fake.calls, queryFiles: fake.queryFiles };
}
const kinds = (calls) => calls.map(({ args }) => {
  if (args[0] === '--version') return 'version';
  if (args[1] === 'query') return 'query';
  if (args[0] === 'migration') return 'list';
  if (args.includes('--include-all')) return args.includes('--dry-run') ? 'dry-include-all' : 'push-include-all';
  return args.includes('--dry-run') ? 'dry-normal' : 'other';
});
const noLeak = (out) => !out.includes(CANARY) && !out.includes('private') && !out.includes(path.join('pinned', 'supabase'))
  && !out.includes('pinned/supabase') && !out.includes('127.0.0.1') && !out.includes(REF) && !/postgres(?:ql)?:\/\/(?!<user>)/.test(out);

test('exact-gap flow: one apply; read-only, verify-full sessions everywhere but the push; POST verified; nothing leaks', async () => {
  for (const mode of ['local', 'hosted']) {
    const r = await runExactGap({ mode, url: mode === 'local' ? LOCAL : HOSTED });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /RESULT: APPLIED_EXACT_GAP$/);
    assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query', 'push-include-all', 'query', 'dry-normal', 'list']);
    const target = parseTargetUrl(mode === 'local' ? LOCAL : HOSTED, { mode, projectRef: REF });
    for (const call of r.calls) {
      assert.equal(call.cli, EG_CLI);
      if (call.args[0] !== '--version') assert.deepEqual(call.args.slice(-2), ['--agent', 'no'], call.args.join(' '));
      assert.equal(call.env.PGSSLMODE, 'verify-full');
      assert.equal(call.env.PGSSLROOTCERT, EG_CA);
      assert.equal(call.env.PGPASSFILE, EG_PASSFILE);
      assert.ok(!('PGPASSWORD' in call.env) && !JSON.stringify(call.env).includes(CANARY));
      const at = call.args.indexOf('--db-url');
      if (at < 0) continue;
      const kind = kinds([call])[0];
      assert.equal(call.args[at + 1], kind === 'push-include-all' ? buildDbUrl(target) : buildReadOnlyDbUrl(target), kind);
    }
    assert.ok(noLeak(r.out), r.out);
    // Three state queries, each from its own temporary folder, removed afterwards.
    assert.equal(r.queryFiles.length, 3);
    assert.equal(new Set(r.queryFiles.map((f) => path.dirname(f))).size, 3);
    for (const f of r.queryFiles) assert.ok(!existsSync(path.dirname(f)), f);
    assert.match(r.out, /re-read immediately before the push: PostgreSQL runtime and TimeZone as pinned; database unchanged; local folder unchanged/);
  }
});

test('exact-gap flow: without --apply it reads and dry-runs with --include-all, and pushes nothing', async () => {
  const wd = path.resolve(scratch);
  for (const envelope of [false, true]) {
    const r = await runExactGap({ argv: ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE], scenario: { envelope } });
    assert.equal(r.code, 0, r.out);
    assert.match(r.out, /RESULT: CHECKED_EXACT_GAP \(no --apply: nothing was pushed\)$/);
    // D-067 (HOSTED-PRE-COMPAT-001): the check route also reads the state a second time, after its dry run.
    assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query']);
  }
});

test('exact-gap flow: refusals push nothing; failures are STOP verdicts; one push at most', async () => {
  const wd = path.resolve(scratch);
  const base = ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE, '--apply'];
  const pre = egPreState();
  const cases = [
    { name: 'a caller --include-all', argv: [...base, '--include-all'], code: 2, line: /^REFUSED include_all_refused:/m, kinds: [] },
    { name: 'a caller repair', argv: [...base, 'repair'], code: 2, line: /^REFUSED repair_refused:/m, kinds: [] },
    { name: 'another mode value', argv: ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, CANARY], code: 2, line: /^REFUSED exact_gap_mode_unknown:/m, kinds: [] },
    { name: 'the wrong CLI version', scenario: { version: { code: 0, out: '2.108.0\n', stdout: '' } }, code: 2, line: /^REFUSED cli_version:/m, kinds: ['version'] },
    { name: 'the CLI reads its local stack (no TLS)', scenario: { queryLocal: true }, code: 2, line: /^REFUSED cli_local_database:/m, kinds: ['version', 'query'] },
    {
      name: 'the dry run connects to the local stack',
      scenario: { dry: { code: 0, out: `Connecting to local database...\nWould push these migrations:\n • ${MIGRATION}\n`, stdout: '' } },
      code: 2, line: /^REFUSED cli_local_database:/m, kinds: ['version', 'query', 'dry-include-all'],
    },
    { name: 'the PRE read fails', scenario: { queryFailAt: 1 }, code: 3, line: /RESULT: PRE_READ_FAILED/, kinds: ['version', 'query'] },
    { name: 'no gap (001D recorded)', scenario: { pre: egPostState(pre) }, code: 2, line: /^REFUSED /m, kinds: ['version', 'query'] },
    { name: 'a partial 001D object', scenario: { pre: { ...pre, cardRelations: 1 } }, code: 2, line: /^REFUSED partial_001d:/m, kinds: ['version', 'query'] },
    {
      name: 'a changed #380 statement',
      scenario: { pre: { ...pre, ledger: pre.ledger.map((r) => (r.version === '20261105025604' ? { ...r, first: '1'.repeat(64) } : r)) } },
      code: 2, line: /^REFUSED stored_statement:/m, kinds: ['version', 'query'],
    },
    { name: 'the dry run fails', scenario: { dry: { code: 1, out: 'ERROR: something\n', stdout: '' } }, code: 3, line: /RESULT: DRY_RUN_FAILED/, kinds: ['version', 'query', 'dry-include-all'] },
    {
      name: 'the dry run lists two migrations',
      scenario: { dry: { code: 0, out: `Would push these migrations:\n \u2022 ${MIGRATION}\n \u2022 20261106000000_x.sql\n`, stdout: '' } },
      code: 2, line: /^REFUSED pending_mismatch:/m, kinds: ['version', 'query', 'dry-include-all'],
    },
    { name: 'the re-check read fails', scenario: { queryFailAt: 2 }, code: 3, line: /RESULT: PRE_READ_FAILED/, kinds: ['version', 'query', 'dry-include-all', 'query'] },
    {
      name: 'the state changes before the push',
      scenario: { changedBeforePush: { ...pre, otherFunctions: { count: 578, sha256: 'a'.repeat(64) } } },
      code: 2, line: /^REFUSED state_changed:/m, kinds: ['version', 'query', 'dry-include-all', 'query'],
    },
    {
      name: 'only a ledger row changes before the push',
      scenario: { changedBeforePush: { ...pre, ledger: pre.ledger.map((r, i) => (i === 7 ? { ...r, all: '0'.repeat(64) } : r)) } },
      code: 2, line: /^REFUSED state_changed:/m, kinds: ['version', 'query', 'dry-include-all', 'query'],
    },
    {
      // The last gate before the push: the local folder is checked again after the re-read.
      name: 'the local folder changes before the push',
      deps: { checkLocal: (() => { let n = 0; return () => { n += 1; return n === 1 ? EG_LOCAL : checkExactGapMigrations(path.join(scratch, 'absent-eg-recheck')); }; })() },
      code: 2, line: /^REFUSED migration_missing:/m, kinds: ['version', 'query', 'dry-include-all', 'query'],
    },
    {
      name: 'the dry run lists one other migration',
      scenario: { dry: { code: 0, out: 'Would push these migrations:\n • 20261106000000_x.sql\n', stdout: '' } },
      code: 2, line: /^REFUSED pending_mismatch:/m, kinds: ['version', 'query', 'dry-include-all'],
    },
    {
      name: 'the dry run answer is not understood',
      scenario: { dry: { code: 0, out: 'Connecting to remote database...\n', stdout: '' } },
      code: 2, line: /^REFUSED pending_mismatch:/m, kinds: ['version', 'query', 'dry-include-all'],
    },
    {
      name: 'a re-created function drifted',
      scenario: { pre: { ...pre, functions: pre.functions.map((f) => (f.name === 'app.sync_push' ? { ...f, src: '0'.repeat(64) } : f)) } },
      code: 2, line: /^REFUSED recreated_drift:/m, kinds: ['version', 'query'],
    },
    {
      name: 'an error after the push', scenario: { normalThrows: true },
      code: 4, line: /an unexpected error stopped the post-check after the push\nRESULT: POSTCHECK_MISMATCH/,
      kinds: ['version', 'query', 'dry-include-all', 'query', 'push-include-all', 'query', 'dry-normal'],
    },
    {
      name: 'the POST read connects to the local stack', scenario: { queryLocalAfterPush: true },
      code: 4, line: /POST check post_unreadable[\s\S]*RESULT: POSTCHECK_MISMATCH/,
      kinds: ['version', 'query', 'dry-include-all', 'query', 'push-include-all', 'query', 'dry-normal', 'list'],
    },
    {
      name: 'the push fails', scenario: { push: { code: 1, out: 'ERROR: canceling statement due to lock timeout (SQLSTATE 55P03)\nAt statement: 14\n', stdout: '' }, post: pre },
      code: 3, line: /RESULT: PUSH_FAILED/, kinds: ['version', 'query', 'dry-include-all', 'query', 'push-include-all', 'query', 'dry-normal', 'list'],
    },
    {
      name: 'the normal dry run is still divergent',
      scenario: { normal: { code: 1, out: 'Found local migration files to be inserted before the last migration on remote database.\n', stdout: '' } },
      code: 4, line: /RESULT: POSTCHECK_MISMATCH/, kinds: ['version', 'query', 'dry-include-all', 'query', 'push-include-all', 'query', 'dry-normal', 'list'],
    },
    {
      name: 'the POST read fails', scenario: { queryFailAt: 3 },
      code: 4, line: /RESULT: POSTCHECK_MISMATCH/, kinds: ['version', 'query', 'dry-include-all', 'query', 'push-include-all', 'query', 'dry-normal', 'list'],
    },
  ];
  for (const c of cases) {
    const r = await runExactGap({ argv: c.argv, scenario: c.scenario, deps: c.deps });
    assert.equal(r.code, c.code, `${c.name}: ${r.out}`);
    assert.match(r.out, c.line, c.name);
    assert.deepEqual(kinds(r.calls), c.kinds, c.name);
    assert.ok(kinds(r.calls).filter((k) => k === 'push-include-all').length <= 1, c.name);
    assert.ok(noLeak(r.out), `${c.name}: ${r.out}`);
    if (c.code !== 4) assert.ok(!/RESULT: (APPLIED|POSTCHECK)/.test(r.out), c.name);
    if (c.code === 4) assert.ok(!/^REFUSED /m.test(r.out), `${c.name}: never a refusal after the push`);
  }
});

test('exact-gap flow: CLI output that echoes a secret is redacted before it is cut, at every relayed failure', async () => {
  const wd = path.resolve(scratch);
  const echo = `ERROR: failed to connect to \`host=db.${REF}.supabase.co user=postgres\`: ${EG_PASSFILE} ${EG_CA} password=${CANARY} ${HOSTED} ${wd} ${EG_CLI}\n`;
  // Each secret straddles the 220-character cut: cutting first would keep its first characters.
  const cut = [EG_PASSFILE, EG_CA, wd, EG_CLI].map((s, i) => `ERROR: ${String(i).repeat(205)}${s}`).join('\n');
  for (const [site, scenario, line] of [
    ['the PRE read', (text) => ({ queryFailAt: 1, queryFailOut: text }), /RESULT: PRE_READ_FAILED/],
    ['the dry run', (text) => ({ dry: { code: 1, out: text, stdout: '' } }), /RESULT: DRY_RUN_FAILED/],
    ['the push', (text) => ({ push: { code: 1, out: text, stdout: '' }, post: egPreState() }), /RESULT: PUSH_FAILED/],
  ]) {
    for (const text of [echo, cut]) {
      const r = await runExactGap({ mode: 'hosted', url: HOSTED, scenario: scenario(text) });
      assert.match(r.out, line, `${site}: ${r.out}`);
      assert.ok(r.out.includes('<redact'), `${site}: the echoed line is relayed, redacted: ${r.out}`);
      assert.ok(noLeak(r.out), `${site}: ${r.out}`);
      for (const secret of [EG_PASSFILE, EG_CA, wd, EG_CLI]) assert.ok(!r.out.includes(secret.slice(0, 8)), `${site}: a cut prefix of a secret: ${r.out}`);
    }
  }
});

test('exact-gap wiring: by default the real passfile, CA, local-folder and CLI checks run, before any CLI process', async () => {
  const cliRefusal = CLI_BINARIES[`${process.platform}-${process.arch}`] ? 'cli_missing' : 'cli_platform';
  for (const [real, env, code] of [
    [['verifyPassfile'], {}, 'passfile_missing'],
    [['verifyCa'], { [ENV_SSLROOTCERT]: undefined }, 'ca_missing'],
    [['verifyCa'], { [ENV_SSLROOTCERT]: 'relative-ca.pem' }, 'ca_missing'],
    [['checkLocal'], {}, 'migration_missing'],
    [['verifyCli'], {}, cliRefusal],
  ]) {
    const r = await runExactGap({ real, env });
    assert.equal(r.code, 2, `${real}: ${r.out}`);
    assert.match(r.out, new RegExp(`^REFUSED ${code}:`, 'm'), `${real}: ${r.out}`);
    assert.equal(r.calls.length, 0, `${real}: no CLI process`);
    assert.ok(noLeak(r.out), r.out);
  }
  // The real CA check: a valid, owner-only CA that is not the accepted one is refused in hosted mode before any CLI
  // process; the same file is accepted in local mode, which then runs the whole flow with it.
  const work = mkdtempSync(path.join(scratch, 'eg-wire-work-'));
  const dir = mkdtempSync(path.join(scratch, 'eg-wire-'));
  const ca = path.join(dir, 'test-ca.pem');
  writeFileSync(ca, TEST_CA);
  ownerOnly(ca);
  const repoRoot = syntheticRepo();
  const realCa = (raw, mode, workdir) => verifyCa(raw, mode, workdir, { repoRoot, now: IN_VALIDITY });
  const argv = (mode) => ['--mode', mode, ...(mode === 'hosted' ? ['--project-ref', REF] : []), '--workdir', work, EXACT_GAP_FLAG, EXACT_GAP_MODE, '--apply'];
  let r = await runExactGap({ argv: argv('hosted'), url: HOSTED, deps: { verifyCa: realCa }, env: { [ENV_SSLROOTCERT]: ca } });
  assert.equal(r.code, 2, r.out);
  assert.match(r.out, /^REFUSED ca_not_accepted:/m);
  assert.equal(r.calls.length, 0);
  assert.ok(!r.out.includes(dir) && noLeak(r.out), r.out);
  r = await runExactGap({ argv: argv('local'), deps: { verifyCa: realCa }, env: { [ENV_SSLROOTCERT]: ca } });
  assert.equal(r.code, 0, r.out);
  assert.ok(r.calls.length > 0 && r.calls.every((call) => call.env.PGSSLROOTCERT === realpathSync.native(ca)));
  assert.ok(!r.out.includes(dir) && noLeak(r.out), r.out);
});

test('the wrapper as a process: both routes refuse before any CLI process when the database URL is missing', () => {
  const wd = path.resolve(scratch);
  const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => /^(SystemRoot|windir|PATH|TEMP|TMP|TMPDIR|HOME|USERPROFILE)$/i.test(k)));
  for (const argv of [['--mode', 'local', '--workdir', wd], ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE, '--apply']]) {
    const r = spawnSync(process.execPath, [WRAPPER, ...argv], { env, encoding: 'utf8', timeout: 60_000, windowsHide: true });
    assert.equal(r.status, 2, `${argv.join(' ')}: ${r.stdout}${r.stderr}`);
    assert.match(r.stdout, /^REFUSED url_missing:/);
    assert.equal(r.stderr, '');
  }
});

test('main() dispatch: only the exact flag reaches the exact-gap mode; the default route is unchanged without it', async () => {
  const wd = path.resolve(scratch);
  const run = async (argv, env) => {
    const lines = [];
    const code = await main(argv, env, (l) => lines.push(l));
    return { code, out: lines.join('\n') };
  };
  // Only the exact-gap parser names a caller's --include-all: the flag routed the call there.
  let r = await run(['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE, '--include-all'], { [ENV_URL]: LOCAL });
  assert.equal(r.code, 2);
  assert.match(r.out, /^REFUSED include_all_refused:/);
  // Without the plain flag the default route answers, exactly as before.
  r = await run(['--mode', 'local', '--workdir', wd, '--include-all'], { [ENV_URL]: LOCAL });
  assert.match(r.out, /^REFUSED bad_arguments: unknown argument$/);
  r = await run(['--mode', 'local', '--workdir', wd, `${EXACT_GAP_FLAG}=${EXACT_GAP_MODE}`], { [ENV_URL]: LOCAL });
  assert.match(r.out, /^REFUSED bad_arguments: unknown argument$/);
  r = await run(['--mode', 'local', '--workdir', wd], {});
  assert.match(r.out, /^REFUSED url_missing:/);
  // The exact-gap route uses the real passfile and CA checks before any CLI process.
  r = await run(['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE], { [ENV_URL]: LOCAL });
  assert.equal(r.code, 2);
  assert.match(r.out, /^REFUSED passfile_missing:/);
  r = await run(['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE], { [ENV_URL]: `postgresql://postgres:${CANARY}@127.0.0.1:56622/postgres` });
  assert.match(r.out, /^REFUSED url_password:/);
  assert.ok(!r.out.includes(CANARY));
  r = await run(['--mode', 'hosted', '--project-ref', REF, '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE], { [ENV_URL]: `postgresql://postgres@db.${REF}.supabase.co:6543/postgres` });
  assert.match(r.out, /^REFUSED pooler_refused:/);
});

// =====================================================================================================================
// CORRECTIONS-001 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-CORRECTIONS-001): CR-EG-01, exactly one active
// passfile entry; CR-EG-02, the exact access of every selected object.
// =====================================================================================================================
const PF_TARGET = { host: '127.0.0.1', port: '56622', database: 'postgres', user: 'postgres' };
const PF_EXACT = `127.0.0.1:56622:postgres:postgres:${CANARY}`;

test('exact-gap passfile (CR-EG-01): exactly one active entry in total, the exact target, with a password', () => {
  const pick = (text) => selectExactGapPassfileEntry(parsePassfile(text), PF_TARGET);
  assert.ok(pick(`${PF_EXACT}\n`) === CANARY, 'one exact entry');
  assert.ok(pick(`# owner-private\n\n${PF_EXACT}\r\n\n# end\n`) === CANARY, 'comments and empty lines are ignored');
  assert.ok(pick(PF_EXACT) === CANARY, 'no final newline');
  for (const [text, code, label] of [
    [`${PF_EXACT}\n127.0.0.2:56622:postgres:postgres:other\n`, 'passfile_entry_count', 'the exact entry plus another host'],
    [`${PF_EXACT}\n127.0.0.1:56623:postgres:postgres:other\n`, 'passfile_entry_count', 'the exact entry plus another port'],
    [`${PF_EXACT}\n127.0.0.1:56622:otherdb:postgres:other\n`, 'passfile_entry_count', 'the exact entry plus another database'],
    [`127.0.0.1:56622:postgres:someone_else:other\n${PF_EXACT}\n`, 'passfile_entry_count', 'another user, listed before the exact entry'],
    [`${PF_EXACT}\n${PF_EXACT}\n`, 'passfile_entry_count', 'two exact target entries'],
    [`${PF_EXACT}\n127.0.0.1:56622:postgres:postgres:other\n`, 'passfile_entry_count', 'two target entries with different passwords'],
    ['# only a comment\n\n# and another\n', 'passfile_entry_count', 'only comments: no active entry'],
    ['', 'passfile_entry_count', 'an empty file'],
    ['localhost:56622:postgres:postgres:x\n', 'passfile_entry', 'one entry, but not the exact target'],
    ['127.0.0.1:56622:postgres:postgres:\n', 'passfile_entry', 'the exact target with an empty password'],
    [`${PF_EXACT}\n127.0.0.1:56622:postgres\n`, 'passfile_malformed', 'a malformed line beside the exact entry'],
    [`${PF_EXACT}\n*:*:*:*:other\n`, 'passfile_wildcard', 'a wildcard line beside the exact entry'],
    [`  ${PF_EXACT}\n`, 'passfile_malformed', 'an indented entry'],
  ]) assert.throws(() => pick(text), (e) => e.code === code && !e.message.includes(CANARY) && !e.message.includes('127.0.0.1'), label);
  // The default route keeps its own rule: one exact entry for the endpoint, other entries allowed.
  assert.ok(selectPassfileEntry(parsePassfile(`${PF_EXACT}\n127.0.0.2:56622:postgres:postgres:other\n`), PF_TARGET) === CANARY);
});

test('exact-gap passfile file (CR-EG-01): the default checks, then the one-entry rule; no passfile path or content in output', () => {
  const work = mkdtempSync(path.join(scratch, 'eg-pf-work-'));
  const dir = mkdtempSync(path.join(scratch, `eg-pf-${CANARY}-`));
  const repoRoot = syntheticRepo();
  const file = path.join(dir, 'pgpass');
  const quiet = (code) => (e) => e.code === code && !e.message.includes(CANARY) && !e.message.includes(dir) && !e.message.includes('127.0.0');
  writeFileSync(file, `${PF_EXACT}\n127.0.0.2:56622:postgres:postgres:other\n`);
  ownerOnly(file);
  // The default route accepts this file (one exact entry for the endpoint); the exact-gap mode refuses it.
  assert.deepEqual(verifyPassfile(file, PF_TARGET, work, { repoRoot }), { path: realpathSync.native(file), secret: CANARY });
  assert.throws(() => verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot }), quiet('passfile_entry_count'));
  writeFileSync(file, `# owner-private\n\n${PF_EXACT}\n`);
  assert.deepEqual(verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot }), { path: realpathSync.native(file), secret: CANARY });
  writeFileSync(file, '# nothing active\n');
  assert.throws(() => verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot }), quiet('passfile_entry'));
  writeFileSync(file, `${PF_EXACT}\n${PF_EXACT}\n`);
  assert.throws(() => verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot }), quiet('passfile_entry'));
  // The default checks still run first: location and permissions.
  assert.throws(() => verifyExactGapPassfile(path.join(dir, 'absent'), PF_TARGET, work, { repoRoot }), quiet('passfile_missing'));
  const inWork = path.join(work, 'pgpass');
  writeFileSync(inWork, `${PF_EXACT}\n`);
  assert.throws(() => verifyExactGapPassfile(inWork, PF_TARGET, work, { repoRoot }), quiet('passfile_location'));
  // A file that changes between the two reads, or cannot be read again, is refused.
  writeFileSync(file, `${PF_EXACT}\n`);
  assert.throws(() => verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot, read: () => '127.0.0.1:56622:postgres:postgres:changed\n' }), quiet('passfile_changed'));
  assert.throws(() => verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot, read: () => `${PF_EXACT}\n127.0.0.2:1:d:u:x\n` }), quiet('passfile_entry_count'));
  assert.throws(() => verifyExactGapPassfile(file, PF_TARGET, work, { repoRoot, read: () => { throw new Error(CANARY); } }), quiet('passfile_missing'));
});

test('exact-gap wiring (CR-EG-01): by default the one-entry passfile check runs, before any CLI process', async (t) => {
  const work = mkdtempSync(path.join(scratch, 'eg-pfw-work-'));
  const dir = mkdtempSync(path.join(scratch, 'eg-pfw-'));
  if (passfileLocationProblem(realpathSync.native(dir), { repoRoot: realpathSync.native(REPO), workdir: realpathSync.native(work) })) {
    return t.skip('this checkout\'s project store holds the scratch folder');
  }
  const file = path.join(dir, 'pgpass');
  writeFileSync(file, `${PF_EXACT}\n127.0.0.2:56622:postgres:postgres:other\n`);
  ownerOnly(file);
  const argv = ['--mode', 'local', '--workdir', work, EXACT_GAP_FLAG, EXACT_GAP_MODE, '--apply'];
  const r = await runExactGap({ argv, real: ['verifyPassfile'], env: { [ENV_PASSFILE]: file } });
  assert.equal(r.code, 2, r.out);
  assert.match(r.out, /^REFUSED passfile_entry_count:/m);
  assert.equal(r.calls.length, 0, 'no CLI process');
  assert.ok(!r.out.includes(dir) && noLeak(r.out), r.out);
  // The same file with the extra entry removed passes the passfile check, and the run goes on to its one apply.
  writeFileSync(file, `${PF_EXACT}\n`);
  const ok = await runExactGap({ argv, real: ['verifyPassfile'], env: { [ENV_PASSFILE]: file } });
  assert.equal(ok.code, 0, ok.out);
  assert.ok(ok.calls.every((call) => call.env.PGPASSFILE === realpathSync.native(file)));
  assert.ok(!ok.out.includes(dir) && noLeak(ok.out), ok.out);
});

test('exact-gap access pins (CR-EG-02): exact entries per EXECUTE group, re-created function, table, sequence and column', () => {
  const A = EG.access;
  const all = [...Object.values(A.functions).flat(), ...Object.values(A.recreated).flat(), ...A.table, ...A.sequence];
  // [grantee, privilege, grantable, grantor]: the owner grants every entry, none with a grant option.
  for (const e of all) assert.ok(e.length === 4 && e[2] === false && e[3] === EG.owner, JSON.stringify(e));
  const grantees = (list) => list.map((e) => e[0]).sort();
  // The EXECUTE groups (each function's group is re-derived from the migration's own GRANT / REVOKE sets above): the
  // owner keeps EXECUTE, plus exactly the group's one client role.
  assert.deepEqual(Object.keys(A.functions).sort(), ['authenticated', 'none', 'service_role']);
  assert.deepEqual(grantees(A.functions.none), [EG.owner]);
  assert.deepEqual(grantees(A.functions.authenticated), ['authenticated', EG.owner]);
  assert.deepEqual(grantees(A.functions.service_role), [EG.owner, 'service_role']);
  for (const list of [...Object.values(A.functions), ...Object.values(A.recreated)]) for (const e of list) assert.equal(e[1], 'EXECUTE');
  // The re-created functions: the owner, and agreement with every bit the file sets.
  assert.deepEqual(Object.keys(A.recreated).sort(), Object.keys(EG.recreated).sort());
  for (const [name, list] of Object.entries(A.recreated)) {
    assert.ok(list.some((e) => e[0] === EG.owner), `${name}: the owner`);
    for (const [role, bit] of Object.entries(EG.recreated[name])) {
      assert.equal(list.some((e) => e[0] === (role === 'public' ? 'PUBLIC' : role)), bit, `${name}: ${role}`);
    }
  }
  // Tables and the sequence: the owner alone, with every privilege PostgreSQL 17 gives an owner; no column grant.
  assert.deepEqual(grantees(A.table), Array(8).fill(EG.owner));
  assert.deepEqual(A.table.map((e) => e[1]).sort(), ['DELETE', 'INSERT', 'MAINTAIN', 'REFERENCES', 'SELECT', 'TRIGGER', 'TRUNCATE', 'UPDATE']);
  assert.deepEqual(grantees(A.sequence), Array(3).fill(EG.owner));
  assert.deepEqual(A.sequence.map((e) => e[1]).sort(), ['SELECT', 'UPDATE', 'USAGE']);
  assert.deepEqual([...A.columns], []);
  assert.throws(() => { A.functions.none.push(['x']); }, TypeError);
  assert.throws(() => { A.table[0][0] = 'anon'; }, TypeError);
});

test('exact-gap state SQL (CR-EG-02): the full ACL of every selected object and column, normalized and sorted', () => {
  const sql = exactGapStateSql();
  const bare = sql.replace(/--[^\n]*/g, ' ').replace(/'(?:[^']|'')*'/g, "''");
  assert.equal((bare.match(/;/g) || []).length, 1, 'still exactly one statement');
  // REPIN-001: each expression appeared exactly twice, once for the 001D objects and once for #382's; D-068 adds #386's
  // functions and relations: three times.
  const count = (fragment) => sql.split(fragment).length - 1;
  assert.equal(count("pg_catalog.aclexplode(coalesce(proacl, pg_catalog.acldefault('f', proowner)))"), 3, 'functions: the stored ACL, NULL resolved');
  assert.equal(count("pg_catalog.aclexplode(coalesce(r.relacl, pg_catalog.acldefault(case when r.kind = 'S' then 's'::\"char\" else 'r'::\"char\" end, r.relowner)))"), 3,
    'relations: the stored ACL, NULL resolved');
  assert.ok(count('from pg_catalog.pg_attribute att cross join lateral pg_catalog.aclexplode(att.attacl) a') === 3
    && count('where att.attrelid = r.oid and att.attnum > 0 and not att.attisdropped') === 3, 'columns: every live column of the relation');
  // REPIN-001 and D-068: the 001D functions and relations, plus #382's functions and relation and #386's functions and
  // relations (each with its access; the relations also with their column grants).
  assert.equal((sql.match(/json_build_array\(x\.grantee, x\.privilege, x\.grantable, x\.grantor\)/g) || []).length, 6, 'function and relation entries');
  assert.equal((sql.match(/json_build_array\(x\.col, x\.grantee, x\.privilege, x\.grantable, x\.grantor\)/g) || []).length, 3, 'column entries');
  const grantee = "case when a.grantee = 0 then 'PUBLIC' else pg_catalog.pg_get_userbyid(a.grantee)::text end as grantee";
  const rest = 'a.privilege_type::text as privilege, a.is_grantable as grantable, pg_catalog.pg_get_userbyid(a.grantor)::text as grantor';
  assert.equal(sql.split(grantee).length - 1, 9, 'every entry names its grantee, PUBLIC for 0 (functions, relations, columns)');
  assert.equal(sql.split(rest).length - 1, 9, 'every entry carries its privilege, grant option and grantor');
  assert.equal((sql.match(/order by x\.grantee collate "C", x\.privilege collate "C", x\.grantable, x\.grantor collate "C"/g) || []).length, 6, 'a byte-order sort');
  assert.equal((sql.match(/order by x\.col collate "C", x\.grantee collate "C", x\.privilege collate "C", x\.grantable, x\.grantor collate "C"/g) || []).length, 3, 'a byte-order sort');
  assert.equal((sql.match(/'access', \(select/g) || []).length, 6, 'functions and relations carry their access');
  assert.equal((sql.match(/'columns', \(select/g) || []).length, 3, 'relations carry their column grants');
  assert.ok(sql.includes('p.proacl as proacl, p.proowner as proowner') && sql.includes('c.relacl as relacl, c.relowner as relowner'),
    'the stored ACLs and owners come straight from pg_proc and pg_class');
  // The delta review (CR-R-01): one-line changes to the query could hide a grantee from every check above. The whole
  // query is therefore pinned to the text the live proof ran (REPIN-001: the current-main run, whose run driver records
  // this query and its SHA-256); any change fails here and needs a new live proof before this pin moves. D-067
  // (HOSTED-PRE-COMPAT-001) moved it once, for the line-ending facts, with its own hosted-shape live proof; D-068
  // (POST-386-REPIN-001) moved it again, for the #386 surface block, with its own 189 / 188 live proof.
  assert.ok(sha(Buffer.from(sql, 'utf8')) === '4b6cd0fffd1a6c20a15570a8d1be41f07d41f853011b2a1211219c4002844195',
    'the state SQL is exactly the query the live proof ran');
  // REPIN-001 (the review's S382-01): #382's functions are also compared by their whole definition; D-068: so are #386's.
  assert.equal(sql.split("'def', encode(sha256(convert_to(coalesce(pg_catalog.pg_get_functiondef(oid), ''), 'UTF8')), 'hex'),").length - 1, 2);
  assert.ok(sql.includes('p.proacl as proacl, p.proowner as proowner, p.oid as oid'));
});

test('exact-gap PRE access (CR-EG-02): the seven re-created functions must carry exactly their pinned entries', () => {
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), []);
  const variant = (name, change) => {
    const s = egPreState();
    const f = s.functions.find((x) => x.name === name);
    f.access = change(f.access);
    return evaluateExactGapPre(s, EG_LOCAL);
  };
  // The named code only: the four known-role bits are unchanged in each of these.
  const only = (problems, code, label) => {
    assert.ok(problems.length > 0, label);
    assert.deepEqual([...new Set(codes(problems))], [code], `${label}: ${JSON.stringify(problems)}`);
  };
  const fifth = ['eg_fifth_role', 'EXECUTE', false, 'postgres'];
  only(variant('app.audit_category', (a) => [...a, fifth]), 'recreated_access', 'a fifth role on a function without a client grant');
  only(variant('app.sync_push', (a) => [...a, fifth]), 'recreated_access', 'a fifth role on an authenticated function');
  only(variant('app.pin_session_capabilities', (a) => a.filter((e) => e[0] !== 'postgres')), 'recreated_access', 'a removed expected grant');
  only(variant('app.pos_order_snapshots', (a) => a.map((e) => (e[0] === 'authenticated' ? [e[0], e[1], e[2], 'supabase_admin'] : e))), 'recreated_access', 'a changed grantor');
  only(variant('app.owner_audit_events', (a) => a.map((e) => (e[0] === 'authenticated' ? [e[0], e[1], true, e[3]] : e))), 'recreated_access', 'WITH GRANT OPTION');
  only(variant('app.audit_safe_detail', (a) => [...a, ['authenticated', 'TRUNCATE', false, 'postgres']]), 'recreated_access', 'another privilege for a known role');
  only(variant('app.audit_action_has_detail', () => undefined), 'recreated_access', 'no access answer');
  only(variant('app.audit_action_has_detail', () => 'postgres=X/postgres'), 'recreated_access', 'a malformed access answer');
  const message = variant('app.audit_category', (a) => [...a, fifth]).find((p) => /exact access/.test(p[1]))[1];
  assert.match(message, /unexpected: eg_fifth_role EXECUTE false postgres; missing: none/);
});

test('exact-gap POST access (CR-EG-02): every 001D function, table, column and the sequence carry exactly the pinned entries', () => {
  const pre = egPreState();
  const base = () => ({ pre, post: egPostState(pre), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL });
  assert.deepEqual(evaluateExactGapPost(base()), []);
  const variant = (change) => { const v = base(); change(v.post); return evaluateExactGapPost(v); };
  const only = (problems, code, label) => {
    assert.ok(problems.length > 0, label);
    assert.deepEqual([...new Set(codes(problems))], [code], `${label}: ${JSON.stringify(problems)}`);
  };
  const fn = (post, name) => post.functions.find((f) => f.name === name);
  const rel = (post, name) => post.relations.find((r) => r.name === name);
  const fifth = (privilege) => ['eg_fifth_role', privilege, false, 'postgres'];
  const secdefNone = EG.functions.find((f) => f[2] === true && f[6] === 'none')[0];
  const authFn = EG.functions.find((f) => f[6] === 'authenticated')[0];
  const serviceFn = EG.functions.find((f) => f[6] === 'service_role')[0];
  // An unexpected fifth role (the four known-role bits unchanged) on each kind of selected object.
  only(variant((p) => fn(p, secdefNone).access.push(fifth('EXECUTE'))), 'post_function_access', 'a SECURITY DEFINER function with no client grant');
  only(variant((p) => fn(p, authFn).access.push(fifth('EXECUTE'))), 'post_function_access', 'an authenticated function');
  only(variant((p) => fn(p, serviceFn).access.push(fifth('EXECUTE'))), 'post_function_access', 'a service_role function');
  only(variant((p) => fn(p, 'app.sync_push').access.push(fifth('EXECUTE'))), 'post_function_access', 'a re-created function');
  only(variant((p) => rel(p, EG.tables[0]).access.push(fifth('SELECT'))), 'post_table_access', 'a private table');
  only(variant((p) => rel(p, EG.tables[2]).columns.push(['provider_ref', 'eg_fifth_role', 'SELECT', false, 'postgres'])), 'post_column_access', 'one table column');
  only(variant((p) => rel(p, EG.sequence).access.push(fifth('USAGE'))), 'post_sequence_access', 'the revision sequence');
  // A removed expected grant, a changed grantor, WITH GRANT OPTION.
  only(variant((p) => { const f = fn(p, serviceFn); f.access = f.access.filter((e) => e[0] !== 'postgres'); }), 'post_function_access', 'a removed owner grant');
  only(variant((p) => { const f = fn(p, serviceFn); f.access = f.access.map((e) => (e[0] === 'service_role' ? [e[0], e[1], e[2], 'supabase_admin'] : e)); }), 'post_function_access', 'a changed grantor');
  only(variant((p) => { const f = fn(p, authFn); f.access = f.access.map((e) => (e[0] === 'authenticated' ? [e[0], e[1], true, e[3]] : e)); }), 'post_function_access', 'WITH GRANT OPTION');
  only(variant((p) => { const r = rel(p, EG.tables[1]); r.access = r.access.filter((e) => e[1] !== 'MAINTAIN'); }), 'post_table_access', 'a removed table privilege');
  only(variant((p) => { const r = rel(p, EG.tables[3]); r.access = r.access.map((e) => (e[1] === 'SELECT' ? [e[0], e[1], true, e[3]] : e)); }), 'post_table_access', 'a table grant option');
  only(variant((p) => { const r = rel(p, EG.sequence); r.access = r.access.map((e) => [e[0], e[1], e[2], 'supabase_admin']); }), 'post_sequence_access', 'a changed sequence grantor');
  only(variant((p) => { rel(p, EG.sequence).columns = [['last_value', 'eg_fifth_role', 'SELECT', false, 'postgres']]; }), 'post_sequence_access', 'a sequence column grant');
  // A missing or malformed answer never matches.
  only(variant((p) => { delete fn(p, 'app.card_text_canonical').access; }), 'post_function_access', 'no function access answer');
  only(variant((p) => { rel(p, EG.tables[4]).columns = null; }), 'post_column_access', 'no column answer');
  only(variant((p) => { rel(p, EG.tables[4]).access = 'postgres=arwdDxtm/postgres'; }), 'post_table_access', 'a malformed table answer');
  // The known-role bits stay as diagnostics: a client grant is named by both checks.
  const both = variant((p) => { const f = fn(p, 'app.card_text_canonical'); f.anon = true; f.access.push(['anon', 'EXECUTE', false, 'postgres']); });
  assert.deepEqual([...new Set(codes(both))].sort(), ['post_function_access', 'post_privilege']);
});

test('exact-gap flow (CR-EG-02): an access change refuses before the push; a POST access difference is a STOP after it', async () => {
  const pre = egPreState();
  const withAudit = (state, change) => ({ ...state, functions: state.functions.map((f) => (f.name === 'app.audit_category' ? change(f) : f)) });
  // Between the first and the second PRE read: the state fingerprint covers the exact access.
  for (const [label, change] of [
    ['a fifth role', (f) => ({ ...f, access: [...f.access, ['eg_fifth_role', 'EXECUTE', false, 'postgres']] })],
    ['a changed grantor', (f) => ({ ...f, access: f.access.map((e) => [e[0], e[1], e[2], 'supabase_admin']) })],
    ['WITH GRANT OPTION', (f) => ({ ...f, access: f.access.map((e) => [e[0], e[1], true, e[3]]) })],
  ]) {
    const r = await runExactGap({ scenario: { changedBeforePush: withAudit(pre, change) } });
    assert.equal(r.code, 2, `${label}: ${r.out}`);
    assert.match(r.out, /^REFUSED state_changed:/m, label);
    assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query'], label);
    assert.ok(noLeak(r.out), r.out);
  }
  // At the first read the PRE gate itself refuses, before the dry run.
  const first = await runExactGap({ scenario: { pre: withAudit(pre, (f) => ({ ...f, access: [...f.access, ['eg_fifth_role', 'EXECUTE', false, 'postgres']] })) } });
  assert.equal(first.code, 2, first.out);
  assert.match(first.out, /^gr37 exact-gap: PRE gate recreated_access: app\.audit_category: the exact access before 001D differs/m);
  assert.match(first.out, /^REFUSED recreated_access:/m);
  assert.deepEqual(kinds(first.calls), ['version', 'query']);
  // After the push: a fifth role on a 001D table is a POSTCHECK_MISMATCH (exit 4), never a refusal.
  const post = egPostState(pre);
  post.relations.find((x) => x.name === EG.tables[0]).access.push(['eg_fifth_role', 'SELECT', false, 'postgres']);
  const after = await runExactGap({ scenario: { post } });
  assert.equal(after.code, 4, after.out);
  assert.match(after.out, /POST check post_table_access: app\.card_payments_pilot_revisions: the exact table access differs[\s\S]*RESULT: POSTCHECK_MISMATCH/);
  assert.ok(!/^REFUSED /m.test(after.out) && noLeak(after.out), after.out);
});

// =====================================================================================================================
// REPIN-001 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-REPIN-001): the PostgreSQL 17.6 runtime gate and
// #382's surface proof.
// =====================================================================================================================
const onlyCode = (problems, code, label) => {
  assert.ok(problems.length > 0, label);
  assert.deepEqual([...new Set(codes(problems))], [code], `${label}: ${JSON.stringify(problems)}`);
};
const FIFTH = (privilege = 'EXECUTE') => ['eg_fifth_role', privilege, false, 'postgres'];

test('exact-gap runtime (REPIN-001): PRE refuses any server but PostgreSQL 17.6 (170006) and any TimeZone but UTC', () => {
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), []);
  const variant = (change) => { const s = egPreState(); change(s); return evaluateExactGapPre(s, EG_LOCAL); };
  for (const [value, label] of [
    ['160004', 'PostgreSQL 16'], ['160010', 'a later PostgreSQL 16'], ['170004', 'PostgreSQL 17 with an earlier minor'],
    ['170007', 'PostgreSQL 17 with a later minor'], ['180000', 'PostgreSQL 18'], [170006, 'the right number, not as the setting text'], ['', 'empty'],
  ]) onlyCode(variant((s) => { s.runtime.server_version_num = value; }), 'runtime_version', label);
  for (const [value, label] of [
    ['Asia/Jerusalem', 'a local zone'], ['Etc/UTC', 'another name for UTC'], ['utc', 'lower case'], ['GMT', 'GMT'], ['UTC ', 'a trailing space'], [null, 'no value'],
  ]) onlyCode(variant((s) => { s.runtime.time_zone = value; }), 'runtime_timezone', label);
  assert.deepEqual([...new Set(codes(variant((s) => { delete s.runtime; })))].sort(), ['runtime_timezone', 'runtime_version']);
  // The session block's own server_version_num is display only: the gate reads the runtime block.
  assert.deepEqual(variant((s) => { s.session.server_version_num = '160004'; }), []);
  const message = variant((s) => { s.runtime.server_version_num = '160004'; })[0][1];
  assert.match(message, /server_version_num 160004; the access pins are PostgreSQL 170006 values and are never regenerated silently/);
  assert.match(variant((s) => { s.runtime.time_zone = 'Asia/Jerusalem'; })[0][1], /TimeZone Asia\/Jerusalem; it must be UTC/);
});

test('exact-gap runtime (REPIN-001): the state fingerprint covers the runtime and #382\'s surface, not the session block', () => {
  const base = egPreState();
  const fp = stateFingerprint(base);
  const changed = (change) => { const s = JSON.parse(JSON.stringify(base)); change(s); return stateFingerprint(s); };
  assert.equal(changed((s) => { s.session.server_version_num = '160004'; s.session.ssl = false; }), fp, 'the session block is not part of it');
  for (const [label, change] of [
    ['server_version_num', (s) => { s.runtime.server_version_num = '170007'; }],
    ['TimeZone', (s) => { s.runtime.time_zone = 'Asia/Jerusalem'; }],
    ['a #382 function access', (s) => { s.surface382.functions[0].access.push(FIFTH()); }],
    ['the #382 relation definition', (s) => { s.surface382.relations[0].definition = '0'.repeat(64); }],
    ['a #382 Storage policy', (s) => { s.surface382.policies[1].using = 'true'; }],
    ['another storage.objects policy', (s) => { s.surface382.objectPolicies.count += 1; }],
  ]) assert.notEqual(changed(change), fp, label);
});

test('exact-gap flow (REPIN-001): a runtime change between the PRE read and the re-read refuses before the push', async () => {
  const pre = egPreState();
  for (const [label, runtime, code] of [
    ['PostgreSQL 16 at the re-read', { server_version_num: '160004', time_zone: 'UTC' }, 'runtime_version'],
    ['another PostgreSQL 17 at the re-read', { server_version_num: '170007', time_zone: 'UTC' }, 'runtime_version'],
    ['a non-UTC TimeZone at the re-read', { server_version_num: '170006', time_zone: 'Asia/Jerusalem' }, 'runtime_timezone'],
  ]) {
    const r = await runExactGap({ scenario: { changedBeforePush: { ...pre, runtime } } });
    assert.equal(r.code, 2, `${label}: ${r.out}`);
    assert.match(r.out, new RegExp(`^REFUSED ${code}: the re-check [^\\n]*\\(at the re-read immediately before the push\\); nothing was pushed$`, 'm'), label);
    assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query'], label);
    assert.ok(noLeak(r.out), r.out);
  }
  // At the first read the PRE gate refuses, before the dry run.
  for (const [runtime, code] of [[{ server_version_num: '160004', time_zone: 'UTC' }, 'runtime_version'], [{ server_version_num: '170006', time_zone: 'Asia/Jerusalem' }, 'runtime_timezone']]) {
    const first = await runExactGap({ scenario: { pre: { ...pre, runtime } } });
    assert.equal(first.code, 2, first.out);
    assert.match(first.out, new RegExp(`^gr37 exact-gap: PRE gate ${code}:`, 'm'));
    assert.match(first.out, new RegExp(`^REFUSED ${code}:`, 'm'));
    assert.deepEqual(kinds(first.calls), ['version', 'query']);
  }
  // The pinned runtime is printed in the PRE line of a passing run.
  const ok = await runExactGap({ argv: ['--mode', 'local', '--workdir', path.resolve(scratch), EXACT_GAP_FLAG, EXACT_GAP_MODE] });
  assert.equal(ok.code, 0, ok.out);
  assert.match(ok.out, /PostgreSQL server_version_num 170006 and TimeZone UTC, as pinned/);
});

// The parameter list of each CREATE FUNCTION statement as pg_get_function_identity_arguments prints these plain
// "name type" parameters: one space inside a parameter, ", " between them.
function createdFunctionArgs(sql) {
  const out = [];
  for (const stmt of splitSql(sql).map(lead)) {
    const head = /^create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(/i.exec(stmt);
    if (!head) continue;
    let depth = 0;
    let close = -1;
    for (let i = head[0].length - 1; i < stmt.length && close < 0; i += 1) {
      if (stmt[i] === '(') depth += 1;
      if (stmt[i] === ')') { depth -= 1; if (depth === 0) close = i; }
    }
    const params = stmt.slice(head[0].length, close).split(',').map((p) => p.replace(/\s+/g, ' ').trim()).filter(Boolean);
    out.push([`${head[1]}.${head[2]}`, params.join(', ')]);
  }
  return out;
}
const byteOrder = (a, b) => (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0);

test('exact-gap #382 surface pins (REPIN-001): they equal the committed #382 migration bytes', (t) => {
  if (!inGitTree()) return t.skip('not a Git work tree');
  const S = EG.surface382;
  const file = EG.localTail.find(([n]) => n.startsWith(S.version))[0];
  const bytes = gitBlob(file);
  assert.ok(sha(bytes) === EG.storedStatements[S.version][1], 'the stored-statement pin is the file');
  const sql = bytes.toString('utf8');
  // Every function the file creates (none re-created): name, body, security definer, config, volatility, language and
  // the identity arguments.
  assert.deepEqual(createdFunctions(sql).sort(byteOrder), S.functions.map(([name, , src, secdef, config, volatility, language]) => [name, src, secdef, config, volatility, language]));
  assert.deepEqual(createdFunctionArgs(sql).sort(byteOrder), S.functions.map(([name, args]) => [name, args]));
  assert.ok(!/create\s+or\s+replace/i.test(sql), '#382 replaces no earlier object');
  // Each function's EXECUTE group is the file's own REVOKE / GRANT set; each group's exact entries are the owner plus
  // exactly the granted roles, EXECUTE, without grant option, granted by the owner.
  const sets = grantSets(sql);
  const GROUP = {
    'revoke all from public,anon,authenticated,service_role': 'none',
    'revoke all from public,anon,authenticated,service_role;grant execute to authenticated': 'authenticated',
    'revoke all from public,anon,authenticated,service_role;grant execute to anon,service_role': 'anon_service_role',
  };
  assert.deepEqual(S.functions.map(([name]) => GROUP[(sets.get(name) || []).join(';')] ?? 'unexpected'), S.functions.map((f) => f[7]));
  assert.deepEqual(Object.keys(S.access).sort(), ['anon_service_role', 'authenticated', 'none']);
  const roles = { none: [], authenticated: ['authenticated'], anon_service_role: ['anon', 'service_role'] };
  for (const [group, entries] of Object.entries(S.access)) {
    assert.deepEqual(entries.map((e) => e[0]).sort(), [...roles[group], EG.owner].sort(), group);
    for (const e of entries) assert.deepEqual(e.slice(1), ['EXECUTE', false, EG.owner], group);
  }
  // The one relation: created here, RLS enabled (not forced), every privilege revoked from the client roles and PUBLIC,
  // no grant: the owner's PostgreSQL 17 privileges only, no column grant; its one index.
  const stmts = splitSql(sql).map(lead).map((s) => s.replace(/\s+/g, ' ').trim());
  assert.deepEqual(stmts.map((s) => /^create table ([a-z_]+\.[a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => m[1]), [S.relation.name]);
  assert.ok(stmts.includes(`alter table ${S.relation.name} enable row level security;`) && !/force row level security/i.test(sql));
  assert.deepEqual([S.relation.kind, S.relation.rls, S.relation.force_rls], ['r', true, false]);
  assert.ok(stmts.includes(`revoke all on ${S.relation.name} from public,anon,authenticated,service_role;`));
  assert.ok(!stmts.some((s) => /^grant /i.test(s) && s.includes(S.relation.name)), 'no grant on the relation');
  assert.deepEqual(S.relation.access, EG.access.table, 'the owner\'s privileges only');
  assert.deepEqual([...S.relation.columns], []);
  assert.deepEqual(stmts.map((s) => /^create (?:unique )?index ([a-z_0-9]+) on ([a-z_]+\.[a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => `${m[1]}@${m[2]}`),
    [`storefront_background_object_v1@${S.relation.name}`]);
  // The two Storage policies: name, table, command, role and expression (compared without PostgreSQL's added
  // parentheses, spacing, case and ::text casts).
  const norm = (e) => String(e).toLowerCase().replace(/::text/g, '').replace(/[\s()]/g, '');
  const created = stmts.map((s) => /^create policy ([a-z_0-9]+) on ([a-z_]+\.[a-z_]+) for (select|insert|update|delete|all) to ([a-z_]+) (using|with check) ?\((.*)\);$/i.exec(s))
    .filter(Boolean).map((m) => ({ name: m[1], table: m[2], cmd: { select: 'r', insert: 'a', update: 'w', delete: 'd', all: '*' }[m[3]], roles: [m[4]], [m[5] === 'using' ? 'using' : 'check']: m[6] }));
  assert.equal(created.length, 2);
  assert.equal((sql.match(/create\s+policy/gi) || []).length, 2, 'no other policy statement');
  for (const want of S.policies) {
    const got = created.find((c) => c.name === want.name);
    assert.ok(got, want.name);
    assert.deepEqual([got.table, got.cmd, got.roles, want.permissive], [want.table, want.cmd, [...want.roles], true], want.name);
    assert.equal(norm(got.using ?? null), norm(want.using), `${want.name} using`);
    assert.equal(norm(got.check ?? null), norm(want.check), `${want.name} check`);
  }
  // #382's functions and relation are part of the #379 / #380 / #382 surfaces.
  for (const [name] of S.functions) assert.ok(EG.surfaceFunctions.includes(name), name);
  assert.ok(EG.surfaceTables.includes(S.relation.name));
});

test('exact-gap #382 surface pins (REPIN-001): the catalog renderings are the live proof\'s, and each is one distinct digest', () => {
  const S = EG.surface382;
  // The whole-definition digests (pg_get_functiondef) and the relation's catalog-line digest are PostgreSQL 17.6
  // renderings, which the migration bytes cannot give. They are the values the current-main sequential reference and
  // the hosted-shape gap database both showed (the run's pin check). This digest over every catalog-rendered pin (the
  // identity arguments, the definition digests, the relation's line and the two policy expressions) fails on any change
  // of one of them, so a pin can only move together with a new live proof.
  for (const f of S.functions) assert.ok(f.length === 9 && /^[0-9a-f]{64}$/.test(f[8]), f[0]);
  assert.equal(new Set(S.functions.map((f) => f[8])).size, S.functions.length);
  assert.ok(/^[0-9a-f]{64}$/.test(S.relation.definition));
  const rendered = JSON.stringify({
    args: S.functions.map((f) => [f[0], f[1]]), def: S.functions.map((f) => [f[0], f[8]]), relation: S.relation.definition,
    policies: S.policies.map((p) => [p.name, p.using, p.check]),
  });
  assert.ok(sha(Buffer.from(rendered, 'utf8')) === '3d7cf87c1ff40d78034ac2e23714d21b954234e47a49a813193035abb392ff44', 'the catalog-rendered #382 pins are the live proof\'s');
});

test('exact-gap PRE #382 surface (REPIN-001): its functions, relation and Storage policies must be exactly as pinned', () => {
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), []);
  const variant = (change) => { const s = egPreState(); change(s.surface382, s); return evaluateExactGapPre(s, EG_LOCAL); };
  const fn = (x, name) => x.functions.find((f) => f.name === name);
  // Functions: presence, identity and definition.
  onlyCode(variant((x) => { x.functions = x.functions.filter((f) => f.name !== 'public.storefront_menu_v7'); }), 'surface382_function', 'storefront_menu_v7 missing');
  onlyCode(variant((x) => { x.functions.push({ ...fn(x, 'app.storefront_background_prefix_v1'), args: 'p_restaurant text' }); }), 'surface382_function', 'an extra overload');
  onlyCode(variant((x) => { x.functions.push({ ...fn(x, 'public.storefront_menu_v7'), name: 'public.storefront_menu_v8' }); }), 'surface382_function', 'a row under an unpinned name (a malformed answer)');
  for (const [label, change] of [
    ['another identity', (f) => { f.args = 'p_organization_id uuid'; }], ['another body', (f) => { f.src = '0'.repeat(64); }],
    ['another whole definition (another result type, strictness, cost or rows)', (f) => { f.def = '0'.repeat(64); }], ['no definition answer', (f) => { delete f.def; }],
    ['no longer SECURITY DEFINER', (f) => { f.secdef = false; }], ['another config', (f) => { f.config = ''; }],
    ['another volatility', (f) => { f.volatility = 'v'; }], ['another language', (f) => { f.language = 'sql'; }],
    ['a procedure', (f) => { f.kind = 'p'; }], ['another owner', (f) => { f.owner = 'supabase_admin'; }],
  ]) onlyCode(variant((x) => change(fn(x, 'app.get_storefront_background_source_v1'))), 'surface382_function', label);
  // Functions: exact access.
  onlyCode(variant((x) => { fn(x, 'public.storefront_menu_v7').access.push(FIFTH()); }), 'surface382_access', 'a fifth role on storefront_menu_v7');
  onlyCode(variant((x) => { fn(x, 'app.storefront_background_prefix_v1').access.push(['authenticated', 'EXECUTE', false, 'postgres']); }), 'surface382_access', 'a client grant on a function without one');
  onlyCode(variant((x) => { const f = fn(x, 'public.get_storefront_background_source_v1'); f.access = f.access.filter((e) => e[0] !== 'authenticated'); }), 'surface382_access', 'a removed grant');
  onlyCode(variant((x) => { const f = fn(x, 'public.storefront_menu_v7'); f.access = f.access.map((e) => (e[0] === 'anon' ? [e[0], e[1], e[2], 'supabase_admin'] : e)); }), 'surface382_access', 'a changed grantor');
  onlyCode(variant((x) => { const f = fn(x, 'app.can_access_storefront_background_object_v1'); f.access = f.access.map((e) => (e[0] === 'authenticated' ? [e[0], e[1], true, e[3]] : e)); }), 'surface382_access', 'WITH GRANT OPTION');
  onlyCode(variant((x) => { fn(x, 'public.storefront_menu_v7').access = 'postgres=X/postgres'; }), 'surface382_access', 'a malformed access answer');
  // The relation.
  onlyCode(variant((x) => { x.relations = []; }), 'surface382_relation', 'the relation missing');
  onlyCode(variant((x) => { x.relations.push({ ...x.relations[0] }); }), 'surface382_relation', 'the relation twice');
  for (const [label, change] of [
    ['another definition (a column, constraint, index or trigger)', (r) => { r.definition = '0'.repeat(64); }], ['RLS forced', (r) => { r.force_rls = true; }],
    ['RLS off', (r) => { r.rls = false; }], ['another owner', (r) => { r.owner = 'supabase_admin'; }], ['another kind', (r) => { r.kind = 'p'; }],
  ]) onlyCode(variant((x) => change(x.relations[0])), 'surface382_relation', label);
  onlyCode(variant((x) => { x.relations[0].access.push(FIFTH('SELECT')); }), 'surface382_access', 'a fifth role on the relation');
  onlyCode(variant((x) => { x.relations[0].access = x.relations[0].access.filter((e) => e[1] !== 'MAINTAIN'); }), 'surface382_access', 'a removed owner privilege');
  onlyCode(variant((x) => { x.relations[0].columns.push(['object_key', 'anon', 'SELECT', false, 'postgres']); }), 'surface382_access', 'a column grant');
  // The two Storage policies.
  for (const [label, change] of [
    ['a policy missing', (x) => { x.policies = x.policies.slice(1); }], ['a duplicate policy', (x) => { x.policies.push({ ...x.policies[0] }); }],
    ['another role', (x) => { x.policies[0].roles = ['anon']; }], ['another command', (x) => { x.policies[0].cmd = '*'; }],
    ['restrictive', (x) => { x.policies[0].permissive = false; }], ['another table', (x) => { x.policies[0].table = 'storage.buckets'; }],
    ['another check', (x) => { x.policies[0].check = x.policies[0].check.replace('true', 'false'); }], ['no check', (x) => { x.policies[0].check = null; }],
    ['another using', (x) => { x.policies[1].using = x.policies[1].using.replace('false', 'true'); }], ['a using added', (x) => { x.policies[0].using = 'true'; }],
  ]) onlyCode(variant(change), 'surface382_policy', label);
  // A missing or malformed answer.
  onlyCode(variant((x, s) => { delete s.surface382; }), 'surface382_unreadable', 'no answer');
  onlyCode(variant((x, s) => { s.surface382 = { functions: [] }; }), 'surface382_unreadable', 'a partial answer');
  // The digest of every storage.objects policy is never pinned (hosted may hold other Storage policies): POST compares
  // it with PRE.
  assert.deepEqual(variant((x) => { x.objectPolicies = { count: 99, sha256: '1'.repeat(64) }; }), []);
  assert.deepEqual(variant((x) => { x.objectPolicies = null; }), []);
  // The #382 presence count is part of the #379 / #380 / #382 surfaces.
  assert.ok(codes(variant((x, s) => { s.surfaceRelations -= 1; })).includes('surfaces_missing'));
  assert.match(variant((x, s) => { s.surfaceFunctions -= 1; }).find((p) => p[0] === 'surfaces_missing')[1], /#379 \/ #380 \/ #382 surfaces are incomplete: 45 of 46 functions/);
});

test('exact-gap POST #382 surface (REPIN-001): identical to PRE, including every storage.objects policy', () => {
  const pre = egPreState();
  const base = () => ({ pre, post: egPostState(pre), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL });
  assert.deepEqual(evaluateExactGapPost(base()), []);
  const variant = (change) => { const v = base(); change(v.post.surface382, v.post); return evaluateExactGapPost(v); };
  for (const [label, change] of [
    ['a fifth role on a #382 function', (x) => { x.functions[0].access.push(FIFTH()); }],
    ['a #382 function removed', (x) => { x.functions.pop(); }],
    ['a #382 overload added', (x) => { x.functions.push({ ...x.functions[0], args: 'x' }); }],
    ['a #382 body changed', (x) => { x.functions[3].src = '0'.repeat(64); }],
    ['a #382 whole definition changed (another result type)', (x) => { x.functions[5].def = '0'.repeat(64); }],
    ['the #382 relation changed', (x) => { x.relations[0].definition = 'f'.repeat(64); }],
    ['a #382 relation grant', (x) => { x.relations[0].access.push(FIFTH('SELECT')); }],
    ['a #382 column grant', (x) => { x.relations[0].columns.push(['width', 'anon', 'SELECT', false, 'postgres']); }],
    ['a #382 policy changed', (x) => { x.policies[1].using = 'true'; }],
    ['a #382 policy removed', (x) => { x.policies.pop(); }],
    ['another storage.objects policy added', (x) => { x.objectPolicies = { count: 17, sha256: '1'.repeat(64) }; }],
    ['another storage.objects policy changed', (x) => { x.objectPolicies.sha256 = '2'.repeat(64); }],
    ['no answer', (x, p) => { delete p.surface382; }],
    ['a malformed answer', (x, p) => { p.surface382 = 'x'; }],
  ]) onlyCode(variant(change), 'post_surface382', label);
  assert.ok(codes(variant((x, p) => { p.surfaceRelations -= 1; })).includes('post_surfaces'));
});

test('exact-gap flow (REPIN-001): a #382 surface change refuses before the push; a POST #382 difference is a STOP after it', async () => {
  const pre = egPreState();
  const with382 = (state, change) => { const s = JSON.parse(JSON.stringify(state)); change(s.surface382); return s; };
  // Between the first and the second PRE read: the state fingerprint covers the whole #382 surface.
  for (const [label, change] of [
    ['a fifth role on storefront_menu_v7', (x) => { x.functions.find((f) => f.name === 'public.storefront_menu_v7').access.push(FIFTH()); }],
    ['a changed #382 Storage policy', (x) => { x.policies[1].using = 'true'; }],
    ['another storage.objects policy', (x) => { x.objectPolicies = { count: 17, sha256: '1'.repeat(64) }; }],
  ]) {
    const r = await runExactGap({ scenario: { changedBeforePush: with382(pre, change) } });
    assert.equal(r.code, 2, `${label}: ${r.out}`);
    assert.match(r.out, /^REFUSED state_changed:/m, label);
    assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query'], label);
    assert.ok(noLeak(r.out), r.out);
  }
  // At the first read the PRE gate refuses, before the dry run.
  const first = await runExactGap({ scenario: { pre: with382(pre, (x) => { x.relations[0].definition = '0'.repeat(64); }) } });
  assert.equal(first.code, 2, first.out);
  assert.match(first.out, /^gr37 exact-gap: PRE gate surface382_relation: app\.storefront_background_variants: the definition/m);
  assert.match(first.out, /^REFUSED surface382_relation:/m);
  assert.deepEqual(kinds(first.calls), ['version', 'query']);
  // After the push: a #382 difference is a POSTCHECK_MISMATCH (exit 4), never a refusal.
  const post = egPostState(pre);
  post.surface382.policies[0].roles = ['anon'];
  const after = await runExactGap({ scenario: { post } });
  assert.equal(after.code, 4, after.out);
  assert.match(after.out, /POST check post_surface382: #382's surface[\s\S]*RESULT: POSTCHECK_MISMATCH/);
  assert.ok(!/^REFUSED /m.test(after.out) && noLeak(after.out), after.out);
  // A passing run names #382's surface in its PRE and POST lines.
  const ok = await runExactGap({});
  assert.equal(ok.code, 0, ok.out);
  assert.match(ok.out, /#379 \/ #380 \/ #382 surfaces present \(46 functions, 3 tables\); #382's own surface as pinned \(12 functions, its relation and 2 Storage policies/);
  assert.match(ok.out, /#382's surface, every storage\.objects policy and #386's surface identical to PRE/);
});

// =====================================================================================================================
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-HOSTED-PRE-COMPAT-001 (DECISION D-067): the exact legacy CRLF PRE forms of
// six re-created functions, POST canonical LF only, and the Default ACL as a per-run baseline (PRE 1 = PRE 2 = POST).
// =====================================================================================================================
const SIX = ['app.sync_push', 'app.pin_session_capabilities', 'app.pos_order_snapshots', 'app.audit_action_has_detail', 'app.audit_safe_detail',
  'app.owner_audit_events'];
// The authorization's values, typed here independently of the wrapper's map.
const AUTHORIZED_CRLF = {
  'app.sync_push': ['3567342245d0b61c509688c5706345b78015152e9f9f8c7843b5b7f6b70da9c5', 'd5114f69ba235571eddba9b98e51d37c89cdd0ae0671cb51073cbfde1ae3d0c1', 910],
  'app.pin_session_capabilities': ['7f0ba8c1ac58206eb6763363bda3ddd3ea81f75c89dfb622bf4259b6f813be1e', 'acde331884996f4e570b14c29f72e3dca996c2cb5227434586c6176f43ff3693', 120],
  'app.pos_order_snapshots': ['ce10e252ead728320ae798ce62c61db85d3b088e0b6b6669273dda7b37d7d15b', '3caa845700d7806c10d7f2057f04bc3398527f2f350d4844a48a3c7498d70d1b', 281],
  'app.audit_action_has_detail': ['9e3e215f8eb465058a6202e77d1789270e271eb7af4107bfe639f975040345f2', '5129aea0b695aa7bae4f894b21a05ef70d516244fb222f5c87d27b0f692582f8', 49],
  'app.audit_safe_detail': ['b571d902b1ea167848589e8a522233c1d41084599f0757b7707b07f6d2aa6c95', '500a1888b885fa580d8f1c46f8832dc707dada7c1a1817dcec56654d93a151d1', 130],
  'app.owner_audit_events': ['960474ccbc4e11af695d2ce642a6d06c0090f52d7fb103066e1e56bb9e650e21', '86175d5422dd57c6974ff9bf509548c085e3c281df4773e8537d7cfe80397012', 204],
};
const AUDIT_CATEGORY_LF = '49e905af85b8363c355bb7a0262b5901bf1af5b63ff5a4893c3b6a08bc1b17b4';
// The state query's line-ending facts, computed in JavaScript the way the SQL computes them: the raw SHA-256, the SHA-256
// with each CRLF pair replaced by one LF (nothing else), the CR, LF and CRLF-pair counts, and whether a lone CR exists.
const factsOf = (body) => {
  const cr = body.split('\r').length - 1;
  const crlf = body.split('\r\n').length - 1;
  return { src: sha(Buffer.from(body, 'utf8')), src_lf: sha(Buffer.from(body.split('\r\n').join('\n'), 'utf8')), cr, lf: body.split('\n').length - 1, crlf, lone_cr: cr > crlf };
};
const crlfFacts = (name) => {
  const L = EG.legacyCrlfBefore[name];
  return { src: L.crlf, src_lf: L.canonical, cr: L.lineBreaks, lf: L.lineBreaks, crlf: L.lineBreaks, lone_cr: false };
};
const canonicalFacts = (name) => lfFacts(EG.recreatedBefore[name], EG.legacyCrlfBefore[name]?.lineBreaks ?? 22);
const setFacts = (state, name, facts) => { Object.assign(state.functions.find((f) => f.name === name), facts); return state; };
// The hosted shape the check of 2026-11-06 found: the six in their legacy CRLF form, app.audit_category canonical LF,
// and a Default ACL that is not the local reference's (a synthetic digest, never hosted's value).
const HOSTED_LIKE_ACL = { count: 31, sha256: sha('synthetic hosted-like default ACL baseline') };
function egHostedShapePre() {
  const s = egPreState();
  for (const name of SIX) setFacts(s, name, crlfFacts(name));
  s.defaultAcl = { ...HOSTED_LIKE_ACL };
  return s;
}
const HEX64 = /[0-9a-f]{64}/;
// The body text of each CREATE FUNCTION statement (the dollar-quoted text that becomes prosrc).
function createdBodies(sql) {
  const out = [];
  for (const stmt of splitSql(sql).map(lead)) {
    const head = /^create\s+(?:or\s+replace\s+)?function\s+([a-z_][a-z0-9_]*)\.([a-z_][a-z0-9_]*)\s*\(/i.exec(stmt);
    if (!head) continue;
    const asAt = stmt.search(/\bas\s+\$([A-Za-z_][A-Za-z0-9_]*)?\$/i);
    const tag = /\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(stmt.slice(asAt));
    const start = asAt + tag.index + tag[0].length;
    out.push([`${head[1]}.${head[2]}`, stmt.slice(start, stmt.indexOf(tag[0], start))]);
  }
  return out;
}

test('exact-gap legacy CRLF pins (D-067): exactly the six named functions, the authorization\'s values, frozen', () => {
  const L = EG.legacyCrlfBefore;
  assert.deepEqual(Object.keys(L).sort(), [...SIX].sort());
  for (const name of SIX) {
    assert.deepEqual([L[name].canonical, L[name].crlf, L[name].lineBreaks], AUTHORIZED_CRLF[name], name);
    assert.equal(L[name].canonical, EG.recreatedBefore[name], `${name}: the canonical pin is the unchanged recreatedBefore pin`);
    assert.notEqual(L[name].crlf, L[name].canonical, name);
    assert.equal(EG.functions.find((f) => f[0] === name)[6], 'recreated', name);
    assert.ok(Object.isFrozen(L[name]), name);
  }
  // app.audit_category is canonical LF only; its canonical pin is unchanged.
  assert.ok(!Object.hasOwn(L, 'app.audit_category'));
  assert.equal(EG.recreatedBefore['app.audit_category'], AUDIT_CATEGORY_LF);
  assert.deepEqual(Object.keys(EG.recreatedBefore).filter((n) => !Object.hasOwn(L, n)), ['app.audit_category']);
  assert.ok(Object.isFrozen(L));
  assert.throws(() => { L['app.audit_category'] = { canonical: AUDIT_CATEGORY_LF, crlf: '0'.repeat(64), lineBreaks: 22 }; }, TypeError);
  assert.throws(() => { L['app.sync_push'].lineBreaks = 1; }, TypeError);
  // A map whose canonical value disagrees with recreatedBefore is an internal pin error, never a silent acceptance.
  const bad = { ...EG, legacyCrlfBefore: { ...L, 'app.sync_push': { ...L['app.sync_push'], canonical: '0'.repeat(64) } } };
  assert.throws(() => recreatedBodyForm(crlfFacts('app.sync_push'), 'app.sync_push', bad), refusal('internal_pin'));
  assert.throws(() => evaluateExactGapPre(egHostedShapePre(), EG_LOCAL, bad), refusal('internal_pin'));
});

test('exact-gap legacy CRLF pins (D-067): each is the committed LF body written with CRLF line breaks', (t) => {
  if (!inGitTree()) return t.skip('not a Git work tree');
  const latest = new Map();
  for (const n of gitMigrationNames().slice(0, EG.localCount).filter((x) => x !== MIGRATION)) {
    for (const [name, body] of createdBodies(gitBlob(n).toString('utf8'))) if (name in EG.recreatedBefore) latest.set(name, body);
  }
  assert.equal(latest.size, 7);
  for (const [name, body] of latest) {
    assert.ok(!body.includes('\r'), `${name}: the committed body is LF`);
    assert.ok(sha(Buffer.from(body, 'utf8')) === EG.recreatedBefore[name], `${name}: the canonical pin`);
    const crlf = body.split('\n').join('\r\n');
    if (name === 'app.audit_category') {
      // Its CRLF form exists as bytes, but no pin accepts it.
      assert.deepEqual(recreatedBodyForm(factsOf(crlf), name), { ok: false, code: 'recreated_eol', rule: 'carriage returns in a body accepted only in its canonical LF form' });
      continue;
    }
    const L = EG.legacyCrlfBefore[name];
    assert.ok(sha(Buffer.from(crlf, 'utf8')) === L.crlf, `${name}: the legacy CRLF pin is the committed body with CRLF line breaks`);
    assert.equal(body.split('\n').length - 1, L.lineBreaks, `${name}: the line-break count`);
    // The JavaScript mirror of the state query gives exactly the pinned facts for both forms.
    assert.deepEqual(factsOf(body), canonicalFacts(name), `${name}: canonical facts`);
    assert.deepEqual(factsOf(crlf), crlfFacts(name), `${name}: legacy CRLF facts`);
    assert.deepEqual(recreatedBodyForm(factsOf(body), name), { ok: true, form: 'canonical LF' }, name);
    assert.deepEqual(recreatedBodyForm(factsOf(crlf), name), { ok: true, form: 'legacy CRLF' }, name);
    // One changed line ending, in each direction, made from the real bytes: never accepted.
    const at = crlf.indexOf('\r\n', Math.floor(crlf.length / 2));
    const lfAt = body.indexOf('\n', Math.floor(body.length / 2));
    for (const [label, bytes, code, rule] of [
      ['one CRLF written as LF (one removed CR: mixed endings)', `${crlf.slice(0, at)}${crlf.slice(at + 1)}`, 'recreated_eol', /mixed line endings/],
      ['one LF written as CRLF in the LF body (one inserted CR: mixed endings)', `${body.slice(0, lfAt)}\r${body.slice(lfAt)}`, 'recreated_eol', /mixed line endings/],
      ['one CRLF missing its LF (one removed LF: a lone CR)', `${crlf.slice(0, at + 1)}${crlf.slice(at + 2)}`, 'recreated_eol', /lone carriage return/],
      ['one extra CR before a CRLF (a lone CR)', `${crlf.slice(0, at)}\r${crlf.slice(at)}`, 'recreated_eol', /lone carriage return/],
      ['one extra LF in the CRLF body (mixed endings)', `${crlf.slice(0, at)}\n${crlf.slice(at)}`, 'recreated_eol', /mixed line endings/],
      ['one extra LF in the LF body (a content change)', `${body.slice(0, lfAt)}\n${body.slice(lfAt)}`, 'recreated_drift', /not the canonical LF pin/],
      ['one removed LF in the LF body (a content change)', `${body.slice(0, lfAt)}${body.slice(lfAt + 1)}`, 'recreated_drift', /not the canonical LF pin/],
      ['every line ending CR alone (the old Mac form)', body.split('\n').join('\r'), 'recreated_eol', /lone carriage return/],
    ]) {
      const form = recreatedBodyForm(factsOf(bytes), name);
      assert.equal(form.ok, false, `${name}: ${label}`);
      assert.equal(form.code, code, `${name}: ${label}`);
      assert.match(form.rule, rule, `${name}: ${label}`);
    }
  }
});

test('exact-gap PRE line endings (D-067): canonical LF for all seven and the exact legacy CRLF form for the six pass', () => {
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), [], 'all seven canonical LF');
  for (const name of SIX) {
    assert.deepEqual(evaluateExactGapPre(setFacts(egPreState(), name, crlfFacts(name)), EG_LOCAL), [], `${name} alone in its legacy CRLF form`);
    assert.deepEqual(recreatedBodyForm(crlfFacts(name), name), { ok: true, form: 'legacy CRLF' }, name);
    assert.deepEqual(recreatedBodyForm(canonicalFacts(name), name), { ok: true, form: 'canonical LF' }, name);
  }
  assert.deepEqual(recreatedBodyForm(canonicalFacts('app.audit_category'), 'app.audit_category'), { ok: true, form: 'canonical LF' });
  // The hosted shape: the six legacy CRLF, app.audit_category canonical LF, a Default ACL that is not the local reference's.
  assert.deepEqual(evaluateExactGapPre(egHostedShapePre(), EG_LOCAL), []);
  // The legacy form changes nothing else: owner and exact access stay required.
  const hosted = (change) => { const s = egHostedShapePre(); change(s.functions.find((f) => f.name === 'app.sync_push')); return evaluateExactGapPre(s, EG_LOCAL); };
  onlyCode(hosted((f) => { f.owner = 'supabase_admin'; }), 'recreated_drift', 'another owner beside the legacy CRLF form');
  onlyCode(hosted((f) => { f.access.push(FIFTH()); }), 'recreated_access', 'a fifth role beside the legacy CRLF form');
  onlyCode(hosted((f) => { f.anon = true; }), 'recreated_access', 'an anon grant beside the legacy CRLF form');
});

test('exact-gap PRE line endings (D-067): every other form is refused, naming the function and the rule only', () => {
  const pre = (name, facts) => evaluateExactGapPre(setFacts(egHostedShapePre(), name, facts), EG_LOCAL);
  const one = (problems, code, rule, name, label) => {
    onlyCode(problems, code, label);
    assert.equal(problems.length, 1, `${label}: ${JSON.stringify(problems)}`);
    const message = problems[0][1];
    assert.ok(message.startsWith(`${name}: `), `${label}: ${message}`);
    assert.match(message, rule, label);
    assert.ok(!HEX64.test(message), `${label}: no digest or body text in the refusal: ${message}`);
  };
  for (const name of SIX) {
    const L = EG.legacyCrlfBefore[name];
    const n = L.lineBreaks;
    const c = crlfFacts(name);
    // Each field of the accepted CRLF facts, perturbed alone (the facts are otherwise exactly the reviewed form).
    one(pre(name, { ...c, src: '1'.repeat(64) }), 'recreated_eol', /unpinned raw form/, name, `${name}: another raw hash with the same normalized hash`);
    one(pre(name, { ...c, src_lf: '2'.repeat(64) }), 'recreated_drift', /LF-normalized body is not the canonical pin/, name, `${name}: the CRLF raw pin with another normalized body`);
    one(pre(name, { ...c, cr: n - 1 }), 'recreated_eol', /mixed line endings/, name, `${name}: one CR fewer`);
    one(pre(name, { ...c, cr: n + 1, lone_cr: true }), 'recreated_eol', /lone carriage return/, name, `${name}: one inserted lone CR`);
    one(pre(name, { ...c, lf: n + 1 }), 'recreated_eol', /mixed line endings/, name, `${name}: one inserted LF`);
    one(pre(name, { ...c, crlf: n - 1 }), 'recreated_eol', /mixed line endings/, name, `${name}: one CRLF pair fewer`);
    one(pre(name, { ...c, lone_cr: true }), 'recreated_eol', /lone carriage return/, name, `${name}: a lone CR flag`);
    one(pre(name, { ...c, cr: n + 1, lf: n + 1, crlf: n + 1 }), 'recreated_eol', /line-break count/, name, `${name}: another line-break count`);
    // Mixed endings as the SQL reports them for consistent bytes: one CRLF of the legacy form written as LF.
    one(pre(name, { src: '3'.repeat(64), src_lf: L.canonical, cr: n - 1, lf: n, crlf: n - 1, lone_cr: false }), 'recreated_eol', /mixed line endings/, name, `${name}: mixed endings`);
    // Generic normalization is never acceptance: a CRLF body whose normalized form is not the reviewed source.
    one(pre(name, { src: '4'.repeat(64), src_lf: '5'.repeat(64), cr: n, lf: n, crlf: n, lone_cr: false }), 'recreated_drift', /LF-normalized body is not the canonical pin/, name, `${name}: a CRLF body of other content`);
    // Each field of the canonical LF facts, perturbed alone.
    const l = canonicalFacts(name);
    one(pre(name, { ...l, src: '6'.repeat(64) }), 'recreated_drift', /not the canonical LF pin/, name, `${name}: canonical normalized hash, another raw hash`);
    one(pre(name, { ...l, src_lf: '7'.repeat(64) }), 'recreated_drift', /not the canonical LF pin/, name, `${name}: canonical raw hash, another normalized hash`);
    one(pre(name, { ...l, cr: 3, crlf: 3 }), 'recreated_eol', /mixed line endings/, name, `${name}: canonical hashes with CRs`);
    one(pre(name, { ...l, lone_cr: true }), 'recreated_eol', /lone carriage return/, name, `${name}: canonical hashes with a lone CR flag`);
  }
  // app.audit_category: canonical LF only.
  const A = 'app.audit_category';
  const a = canonicalFacts(A);
  for (const [label, facts, code, rule] of [
    ['its CRLF form', { src: '8'.repeat(64), src_lf: AUDIT_CATEGORY_LF, cr: 22, lf: 22, crlf: 22, lone_cr: false }, 'recreated_eol', /accepted only in its canonical LF form/],
    ['one CRLF', { src: '9'.repeat(64), src_lf: AUDIT_CATEGORY_LF, cr: 1, lf: 22, crlf: 1, lone_cr: false }, 'recreated_eol', /accepted only in its canonical LF form/],
    ['a lone CR', { ...a, src: 'a'.repeat(64), src_lf: 'b'.repeat(64), cr: 1, lone_cr: true }, 'recreated_eol', /lone carriage return/],
    ['another raw hash', { ...a, src: 'c'.repeat(64) }, 'recreated_drift', /not the canonical LF pin/],
    ['canonical hashes with CRs', { ...a, cr: 2, crlf: 2 }, 'recreated_eol', /accepted only in its canonical LF form/],
  ]) one(pre(A, facts), code, rule, A, `${A}: ${label}`);
  // Missing or malformed facts are never guessed.
  for (const [label, change] of [
    ['no normalized hash', (f) => { delete f.src_lf; }], ['no CR count', (f) => { delete f.cr; }], ['a text count', (f) => { f.lf = '910'; }],
    ['a negative count', (f) => { f.crlf = -1; }], ['a fractional count', (f) => { f.cr = 0.5; }], ['no lone-CR flag', (f) => { delete f.lone_cr; }],
    ['a text flag', (f) => { f.lone_cr = 'false'; }], ['no raw hash', (f) => { delete f.src; }],
  ]) {
    const s = egHostedShapePre();
    change(s.functions.find((f) => f.name === 'app.sync_push'));
    one(evaluateExactGapPre(s, EG_LOCAL), 'recreated_eol', /line-ending facts are missing or malformed/, 'app.sync_push', label);
  }
  // A CR in any other selected function: a #382 function (its body pin fails too) or a 001D function found before 001D.
  const s382 = egHostedShapePre();
  Object.assign(s382.surface382.functions.find((f) => f.name === 'public.storefront_menu_v7'), { src: 'd'.repeat(64), cr: 5, crlf: 5 });
  const p382 = evaluateExactGapPre(s382, EG_LOCAL);
  assert.deepEqual([...new Set(codes(p382))].sort(), ['selected_function_eol', 'surface382_function']);
  assert.match(p382.find((p) => p[0] === 'selected_function_eol')[1], /^public\.storefront_menu_v7: carriage returns in a body accepted only in its canonical LF form$/);
  const lone382 = egHostedShapePre();
  Object.assign(lone382.surface382.functions[0], { cr: 1, lone_cr: true });
  assert.ok(codes(evaluateExactGapPre(lone382, EG_LOCAL)).includes('selected_function_eol'));
  const created = egHostedShapePre();
  created.functions.push({ ...created.functions.find((f) => f.name === 'app.audit_category'), name: 'app.card_text_canonical', cr: 2, crlf: 2 });
  assert.deepEqual([...new Set(codes(evaluateExactGapPre(created, EG_LOCAL)))].sort(), ['partial_001d', 'selected_function_eol']);
  const noFacts = egHostedShapePre();
  delete noFacts.surface382.functions[2].lone_cr;
  onlyCode(evaluateExactGapPre(noFacts, EG_LOCAL), 'selected_function_eol', 'a #382 function without its line-ending facts');
});

test('exact-gap POST line endings (D-067): only the canonical LF form; never the legacy CRLF alternative', () => {
  const pre = egHostedShapePre();
  const base = () => ({ pre, post: egPostState(pre), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL });
  assert.deepEqual(evaluateExactGapPost(base()), [], 'the six legacy CRLF PRE bodies are re-created in canonical LF');
  const variant = (change) => { const v = base(); change(v.post); return evaluateExactGapPost(v); };
  const fnOf = (post, name) => post.functions.find((f) => f.name === name);
  const pin = (name) => EG.functions.find((f) => f[0] === name)[1];
  // A re-created function still in its PRE legacy CRLF form (001D did not replace it).
  assert.deepEqual([...new Set(codes(variant((p) => Object.assign(fnOf(p, 'app.sync_push'), crlfFacts('app.sync_push')))))].sort(), ['post_function', 'post_function_eol']);
  // The POST body itself in a CRLF form: the legacy alternative of PRE is never accepted at POST.
  for (const name of [...SIX, 'app.audit_category', 'app.card_attempt_claim', 'public.card_attempt_claim']) {
    const got = variant((p) => Object.assign(fnOf(p, name), { src: 'e'.repeat(64), src_lf: pin(name), cr: 7, lf: 7, crlf: 7, lone_cr: false }));
    assert.deepEqual([...new Set(codes(got))].sort(), ['post_function', 'post_function_eol'], name);
    assert.match(got.find((x) => x[0] === 'post_function_eol')[1], new RegExp(`^${name.replace('.', '\\.')}: carriage returns[^]*POST accepts only the canonical LF form$`));
  }
  // The raw pin with any other fact is still refused (inconsistent answers never pass).
  onlyCode(variant((p) => Object.assign(fnOf(p, 'app.sync_push'), { src_lf: 'f'.repeat(64) })), 'post_function_eol', 'the raw pin with another normalized hash');
  onlyCode(variant((p) => Object.assign(fnOf(p, 'app.sync_push'), { cr: 1, crlf: 1 })), 'post_function_eol', 'the raw pin with a CR count');
  onlyCode(variant((p) => Object.assign(fnOf(p, 'app.card_text_canonical'), { lone_cr: true })), 'post_function_eol', 'the raw pin with a lone CR flag');
  onlyCode(variant((p) => { delete fnOf(p, 'public.owner_card_attempts').crlf; }), 'post_function_eol', 'no CRLF count');
  // A #382 function at POST: canonical LF as well (here PRE and POST hold the same CR, so only the line-ending check sees it).
  const pre382 = egHostedShapePre();
  Object.assign(pre382.surface382.functions[4], { cr: 3, crlf: 3 });
  const p382 = evaluateExactGapPost({ pre: pre382, post: egPostState(pre382), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL });
  onlyCode(p382, 'post_function_eol', 'a #382 function with CRs at POST');
});

test('exact-gap state SQL (D-067): every selected function\'s raw and LF-normalized digests and its line-ending counts', () => {
  const sql = exactGapStateSql();
  const count = (fragment) => sql.split(fragment).length - 1;
  // The raw body digest is unchanged; the normalized one replaces each CRLF pair by one LF and nothing else.
  assert.equal(count("encode(sha256(convert_to(coalesce(p.prosrc, ''), 'UTF8')), 'hex') as src,"), 1);
  assert.equal(count("encode(sha256(convert_to(coalesce(replace(b.body, E'\\r\\n', E'\\n'), ''), 'UTF8')), 'hex') as src_lf,"), 1);
  assert.equal(count("length(b.body) - length(replace(b.body, E'\\r', '')) as cr,"), 1);
  assert.equal(count("length(b.body) - length(replace(b.body, E'\\n', '')) as lf,"), 1);
  assert.equal(count("(length(b.body) - length(replace(b.body, E'\\r\\n', ''))) / 2 as crlf,"), 1);
  assert.equal(count("(length(b.body) - length(replace(b.body, E'\\r', ''))) > (length(b.body) - length(replace(b.body, E'\\r\\n', ''))) / 2 as lone_cr,"), 1);
  assert.equal(count("cross join lateral (select coalesce(p.prosrc, '') as body) b"), 1);
  // Every selected-function list carries all five facts beside the raw digest: the 001D manifest's names, #382's and (D-068)
  // #386's.
  assert.equal(count("'src', src,\n    'src_lf', src_lf, 'cr', cr, 'lf', lf, 'crlf', crlf, 'lone_cr', lone_cr,"), 1);
  assert.equal(count("'src', src,\n      'src_lf', src_lf, 'cr', cr, 'lf', lf, 'crlf', crlf, 'lone_cr', lone_cr,"), 2);
  // The other-function digest line is unchanged (its body digest is the raw one).
  assert.equal(count("select name || '(' || args || ')|' || kind || '|' || src || '|' || secdef::text"), 1);
  // The Default ACL digest: every pg_default_acl row, sorted (a count and a SHA-256), outside the session block.
  assert.ok(sql.includes("'defaultAcl', (select json_build_object('count', count(*), 'sha256', encode(sha256(convert_to(coalesce(string_agg(line, E'\\n' order by line), ''), 'UTF8')), 'hex')) from dacl)"));
});

test('exact-gap state fingerprint (D-067): it covers every line-ending fact and the Default ACL baseline', () => {
  const base = egHostedShapePre();
  const fp = stateFingerprint(base);
  const changed = (change) => { const s = JSON.parse(JSON.stringify(base)); change(s); return stateFingerprint(s); };
  for (const key of ['src', 'src_lf', 'cr', 'lf', 'crlf', 'lone_cr']) {
    assert.notEqual(changed((s) => { const f = s.functions.find((x) => x.name === 'app.owner_audit_events'); f[key] = key === 'lone_cr' ? true : typeof f[key] === 'number' ? f[key] + 1 : '0'.repeat(64); }), fp, `re-created ${key}`);
    assert.notEqual(changed((s) => { const f = s.surface382.functions[1]; f[key] = key === 'lone_cr' ? true : typeof f[key] === 'number' ? f[key] + 1 : '0'.repeat(64); }), fp, `#382 ${key}`);
    assert.notEqual(changed((s) => { const f = s.surface386.functions[2]; f[key] = key === 'lone_cr' ? true : typeof f[key] === 'number' ? f[key] + 1 : '0'.repeat(64); }), fp, `#386 ${key}`);
  }
  // D-068: the #386 surface is inside the fingerprint as well (a relation's definition, a trigger's definition, an access entry).
  assert.notEqual(changed((s) => { s.surface386.relations[0].definition = '0'.repeat(64); }), fp, '#386 relation');
  assert.notEqual(changed((s) => { s.surface386.triggers[0].def = '0'.repeat(64); }), fp, '#386 trigger');
  assert.notEqual(changed((s) => { s.surface386.functions[0].access.push(FIFTH()); }), fp, '#386 access');
  // Both accepted forms of the same function are two different states (so a switch between the reads refuses).
  assert.notEqual(changed((s) => Object.assign(s.functions.find((x) => x.name === 'app.sync_push'), canonicalFacts('app.sync_push'))), fp);
  assert.notEqual(changed((s) => { s.defaultAcl.count += 1; }), fp, 'the Default ACL row count');
  assert.notEqual(changed((s) => { s.defaultAcl.sha256 = '0'.repeat(64); }), fp, 'the Default ACL digest');
});

test('exact-gap Default ACL (D-067): any well-formed first-PRE value is this run\'s baseline; a malformed one is refused', () => {
  for (const acl of [HOSTED_LIKE_ACL, { count: 27, sha256: 'd'.repeat(64) }, { count: 0, sha256: sha('') }, { count: 400, sha256: sha('another') }]) {
    const s = egHostedShapePre();
    s.defaultAcl = { ...acl };
    assert.deepEqual(evaluateExactGapPre(s, EG_LOCAL), [], JSON.stringify(acl));
  }
  for (const [label, acl] of [
    ['missing', undefined], ['null', null], ['a text', 'x'], ['a negative count', { count: -1, sha256: 'd'.repeat(64) }],
    ['a text count', { count: '24', sha256: 'd'.repeat(64) }], ['a short digest', { count: 24, sha256: 'd'.repeat(63) }],
    ['an upper-case digest', { count: 24, sha256: 'D'.repeat(64) }], ['no digest', { count: 24 }],
  ]) {
    const s = egHostedShapePre();
    if (acl === undefined) delete s.defaultAcl; else s.defaultAcl = acl;
    onlyCode(evaluateExactGapPre(s, EG_LOCAL), 'default_acl_unreadable', label);
  }
});

test('exact-gap flow (D-067): both routes read the state twice; PRE 2 must equal PRE 1, the Default ACL included', async () => {
  const wd = path.resolve(scratch);
  const check = ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE];
  const pre = egHostedShapePre();
  // The hosted shape passes check mode: the forms and this run's baseline are printed (digests only), then PRE 2.
  const ok = await runExactGap({ argv: check, scenario: { pre } });
  assert.equal(ok.code, 0, ok.out);
  assert.deepEqual(kinds(ok.calls), ['version', 'query', 'dry-include-all', 'query']);
  const forms = `${SIX.map((n) => `${n} legacy CRLF`).join('; ')}; app.audit_category canonical LF`;
  assert.ok(ok.out.includes(`PRE line endings (D-067): ${forms}; every other selected function canonical LF.`), ok.out);
  assert.ok(ok.out.includes(`Default ACL baseline for this run (never compared with a local reference): 31 rows, SHA-256 ${HOSTED_LIKE_ACL.sha256}.`), ok.out);
  const fp = stateFingerprint(pre);
  assert.ok(ok.out.includes(`First PRE state fingerprint ${fp}`), ok.out);
  assert.match(ok.out, new RegExp(`second PRE \\(read-only, after the dry run\\): PostgreSQL runtime and TimeZone as pinned; the Default ACL equals this run's baseline; state fingerprint ${fp} equals the first PRE's\\nRESULT: CHECKED_EXACT_GAP \\(no --apply: nothing was pushed\\)$`));
  assert.ok(noLeak(ok.out), ok.out);
  // All-LF passes too, and is reported as such.
  const lf = await runExactGap({ argv: check });
  assert.equal(lf.code, 0, lf.out);
  assert.ok(lf.out.includes(`PRE line endings (D-067): ${[...SIX, 'app.audit_category'].map((n) => `${n} canonical LF`).join('; ')};`), lf.out);
  // Between the first and the second PRE read, on both routes: another Default ACL, a malformed one, or one body switching
  // between its two accepted forms. Nothing is pushed.
  for (const route of ['check', 'apply']) {
    const argv = route === 'check' ? check : undefined;
    for (const [label, second, code] of [
      ['another Default ACL row', { ...pre, defaultAcl: { count: 32, sha256: HOSTED_LIKE_ACL.sha256 } }, 'default_acl_changed'],
      ['another Default ACL digest', { ...pre, defaultAcl: { count: 31, sha256: sha('another default ACL') } }, 'default_acl_changed'],
      ['the Default ACL missing', { ...pre, defaultAcl: undefined }, 'default_acl_changed'],
      ['app.sync_push switched to canonical LF', setFacts(JSON.parse(JSON.stringify(pre)), 'app.sync_push', canonicalFacts('app.sync_push')), 'state_changed'],
      ['a #382 function\'s LF count', (() => { const s = JSON.parse(JSON.stringify(pre)); s.surface382.functions[0].lf += 1; return s; })(), 'state_changed'],
    ]) {
      const r = await runExactGap({ argv, scenario: { pre, changedBeforePush: second } });
      assert.equal(r.code, 2, `${route} / ${label}: ${r.out}`);
      assert.match(r.out, new RegExp(`^REFUSED ${code}:`, 'm'), `${route} / ${label}`);
      assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query'], `${route} / ${label}`);
      assert.ok(!/RESULT: (CHECKED|APPLIED)/.test(r.out) && noLeak(r.out), r.out);
    }
  }
  const late = await runExactGap({ argv: check, scenario: { pre, changedBeforePush: { ...pre, defaultAcl: { count: 30, sha256: HOSTED_LIKE_ACL.sha256 } } } });
  assert.match(late.out, /^REFUSED default_acl_changed: the Default ACL differs from this run's baseline, read by the first PRE \(at the second PRE read, after the dry run\); nothing was pushed$/m);
  const lateApply = await runExactGap({ scenario: { pre, changedBeforePush: { ...pre, defaultAcl: { count: 30, sha256: HOSTED_LIKE_ACL.sha256 } } } });
  assert.match(lateApply.out, /^REFUSED default_acl_changed: the Default ACL differs from this run's baseline, read by the first PRE \(at the re-read immediately before the push\); nothing was pushed$/m);
  // The check route's second read can fail (a STOP, nothing pushed), and its runtime is checked again.
  const failed = await runExactGap({ argv: check, scenario: { pre, queryFailAt: 2 } });
  assert.equal(failed.code, 3, failed.out);
  assert.match(failed.out, /the second PRE read-only state could not be read[\s\S]*RESULT: PRE_READ_FAILED/);
  const tz = await runExactGap({ argv: check, scenario: { pre, changedBeforePush: { ...pre, runtime: { server_version_num: '170006', time_zone: 'Asia/Jerusalem' } } } });
  assert.match(tz.out, /^REFUSED runtime_timezone: the second PRE session reports TimeZone Asia\/Jerusalem; it must be UTC \(at the second PRE read, after the dry run\); nothing was pushed$/m);
});

test('exact-gap flow (D-067): the hosted-like Default ACL applies end to end; POST keeps the baseline and the exact access', async () => {
  const pre = egHostedShapePre();
  // A hosted-like baseline, the six legacy CRLF bodies and the exact final manifest: APPLIED.
  const ok = await runExactGap({ scenario: { pre } });
  assert.equal(ok.code, 0, ok.out);
  assert.match(ok.out, /every POST function in its canonical LF form; the catalog digests of every other app \/ public function and relation unchanged, and the Default ACL equal to this run's baseline\nRESULT: APPLIED_EXACT_GAP$/);
  assert.match(ok.out, /re-read immediately before the push: PostgreSQL runtime and TimeZone as pinned; database unchanged; local folder unchanged; the Default ACL equals this run's baseline/);
  const after = async (change, label) => {
    const post = egPostState(pre);
    change(post);
    const r = await runExactGap({ scenario: { pre, post } });
    assert.equal(r.code, 4, `${label}: ${r.out}`);
    assert.ok(/RESULT: POSTCHECK_MISMATCH/.test(r.out) && !/^REFUSED /m.test(r.out) && noLeak(r.out), `${label}: ${r.out}`);
    return [...new Set([...r.out.matchAll(/^gr37 exact-gap: POST check ([a-z_0-9]+):/gm)].map((m) => m[1]))].sort();
  };
  // Another Default ACL between PRE 2 and POST: a POST mismatch, against this run's own baseline.
  assert.deepEqual(await after((p) => { p.defaultAcl = { count: 32, sha256: HOSTED_LIKE_ACL.sha256 }; }, 'a Default ACL row added during the apply'), ['post_unchanged']);
  assert.deepEqual(await after((p) => { p.defaultAcl = { count: 27, sha256: 'd'.repeat(64) }; }, 'the local reference\'s Default ACL at POST'), ['post_unchanged']);
  // An extra grant that a default privilege gives a new object (the Default ACL itself unchanged): POST names the object.
  const fn = (p, name) => p.functions.find((f) => f.name === name);
  const rel = (p, name) => p.relations.find((r) => r.name === name);
  assert.deepEqual(await after((p) => { const f = fn(p, 'public.card_attempt_claim'); f.authenticated = true; f.access.push(['authenticated', 'EXECUTE', false, 'postgres']); }, 'authenticated on a service-only public function'),
    ['post_function_access', 'post_privilege']);
  assert.deepEqual(await after((p) => { fn(p, 'app.card_attempt_resolve').access.push(FIFTH()); }, 'a fifth role on an app function'), ['post_function_access']);
  assert.deepEqual(await after((p) => { rel(p, EG.tables[1]).access.push(['service_role', 'SELECT', false, 'postgres']); }, 'service_role on a private table'), ['post_table_access']);
  assert.deepEqual(await after((p) => { rel(p, EG.tables[2]).columns.push(['attempt_id', 'service_role', 'SELECT', false, 'postgres']); }, 'a column grant'), ['post_column_access']);
  assert.deepEqual(await after((p) => { rel(p, EG.sequence).access.push(['authenticated', 'USAGE', false, 'postgres']); }, 'authenticated on the revision sequence'), ['post_sequence_access']);
});

test('exact-gap flow (D-067, review F1): the second PRE\'s own session must be read-only, encrypted and carry the fixed settings', async () => {
  const wd = path.resolve(scratch);
  const check = ['--mode', 'local', '--workdir', wd, EXACT_GAP_FLAG, EXACT_GAP_MODE];
  const pre = egHostedShapePre();
  // The session block is outside the state fingerprint, so only this check sees a second read in another session.
  for (const [route, argv, label, when] of [
    ['check', check, 'second PRE', 'at the second PRE read, after the dry run'],
    ['apply', undefined, 're-check', 'at the re-read immediately before the push'],
  ]) {
    for (const [change, code, what] of [
      [{ read_only: 'off' }, 'session_not_read_only', 'is not read-only'],
      [{ ssl: false }, 'session_not_tls', 'is not encrypted'],
      [{ ssl: null }, 'session_not_tls', 'is not encrypted'],
      [{ application_name: 'psql' }, 'session_settings', 'does not carry the fixed startup settings'],
      [{ lock_timeout: '0' }, 'session_settings', 'does not carry the fixed startup settings'],
      [{ statement_timeout: '0' }, 'session_settings', 'does not carry the fixed startup settings'],
    ]) {
      const second = { ...pre, session: { ...pre.session, ...change } };
      assert.equal(stateFingerprint(second), stateFingerprint(pre), 'the session block is outside the fingerprint');
      const r = await runExactGap({ argv, scenario: { pre, changedBeforePush: second } });
      assert.equal(r.code, 2, `${route} / ${JSON.stringify(change)}: ${r.out}`);
      assert.match(r.out, new RegExp(`^REFUSED ${code}: the ${label} session ${what} \\(${when}\\); nothing was pushed$`, 'm'), `${route} / ${JSON.stringify(change)}`);
      assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query'], `${route} / ${JSON.stringify(change)}`);
      assert.ok(!/RESULT: (CHECKED|APPLIED)/.test(r.out) && noLeak(r.out), r.out);
    }
    const missing = await runExactGap({ argv, scenario: { pre, changedBeforePush: { ...pre, session: undefined } } });
    assert.equal(missing.code, 2, `${route} / no session block: ${missing.out}`);
    assert.match(missing.out, /^REFUSED session_not_read_only:/m);
  }
});

// =====================================================================================================================
// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-POST-386-REPIN-001 (DECISION D-068): the exact-gap mode re-pinned to main
// 28c41911 (189 local migrations, 188 hosted versions, the one gap 20261104141959) and #386's named surface as a PRE gate
// and a POST identity.
// =====================================================================================================================
const CORE_RENAMES = [
  ['app.pos_register_order_alert', 'app.pos_register_order_alert_core'], ['app.pos_order_alert_status', 'app.pos_order_alert_status_core'],
  ['app.pos_disable_order_alert', 'app.pos_disable_order_alert_core'], ['app.pos_refresh_order_alert_token', 'app.pos_refresh_order_alert_token_core'],
  ['app.pos_claim_order_alert_deliveries', 'app.pos_claim_order_alert_deliveries_core'],
];
// The two files that patch app.pos_register_order_alert's body in place (they read its definition, edit the text and execute
// it), so the renamed core body is not the latest static definition of the name.
const PATCH_FILES = ['20261027011255_bizbot_pos_alert_observation_conflict_reference_001.sql', '20261027142721_bizbot_pos_alert_observation_validated_pin_001.sql'];

test('exact-gap 189 / 188 (D-068): the exact positive case and the four count pins', () => {
  assert.equal(EG_LOCAL.files, 189);
  assert.equal(egPreState().ledger.length, 188);
  assert.equal(egPostState().ledger.length, 189);
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), []);
  const pre = egPreState();
  assert.deepEqual(evaluateExactGapPost({ pre, post: egPostState(pre), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL }), []);
  // A wrong hosted count on either side of 188 (a version too few, a version too many) is named with its count.
  const fewer = egPreState();
  fewer.ledger = fewer.ledger.filter((r) => r.version !== EG_LOCAL.versions[7]);
  assert.ok(codes(evaluateExactGapPre(fewer, EG_LOCAL)).includes('remote_count'));
  assert.match(evaluateExactGapPre(fewer, EG_LOCAL).find((p) => p[0] === 'remote_count')[1], /must hold 188 versions; it holds 187/);
  const more = egPreState();
  more.ledger.push({ version: '20260101999999', name: 'extra', n: 1, first: 'x', all: 'y' });
  assert.match(evaluateExactGapPre(more, EG_LOCAL).find((p) => p[0] === 'remote_count')[1], /must hold 188 versions; it holds 189/);
  // A wrong local count is the local folder's own gate (checkExactGapMigrations), named with the pinned 189.
  const files = { ...Object.fromEntries(Array.from({ length: 183 }, (_, i) => [`20260101${String(i).padStart(6, '0')}_prefix_${i}.sql`, `select ${i};\n`])),
    ...Object.fromEntries(EG.localTail.map(([n], i) => [n, `select ${1000 + i};\n`])) };
  const pins = syntheticFolderPins(files);
  assert.equal(pins.localCount, 189);
  assert.equal(checkExactGapMigrations(exactGapFolder(pins, files), pins).files, 189);
  const without = (name) => Object.fromEntries(Object.entries(files).filter(([n]) => n !== name));
  for (const [set, label] of [[without('20260101000005_prefix_5.sql'), '188 files'], [{ ...files, '20260101999999_prefix_x.sql': 'x' }, '190 files']]) {
    assert.throws(() => checkExactGapMigrations(exactGapFolder(pins, set), pins), (e) => e?.code === 'local_count' && /exactly 189 migrations/.test(e.message), label);
  }
  // A local folder without #386's file, or with a file after it, fails the tail gate before any contact.
  assert.throws(() => checkExactGapMigrations(exactGapFolder(pins, { ...without('20261108085442_bizbot_pos_long_shift_alerts_001.sql'), '20260101999999_prefix_x.sql': 'x' }), pins), refusal('local_tail'));
  assert.throws(() => checkExactGapMigrations(exactGapFolder(pins, { ...without('20260101000005_prefix_5.sql'), '20261109000000_after_386.sql': 'x' }), pins), refusal('local_tail'));
});

test('exact-gap #386 surface pins (D-068): they equal the committed #386 migration bytes', (t) => {
  if (!inGitTree()) return t.skip('not a Git work tree');
  const S = EG.surface386;
  const file = EG.localTail.find(([n]) => n.startsWith(S.version))[0];
  assert.equal(file, '20261108085442_bizbot_pos_long_shift_alerts_001.sql');
  const bytes = gitBlob(file);
  assert.ok(sha(bytes) === EG.storedStatements[S.version][1], 'the stored-statement pin is the file');
  assert.ok(sha(bytes) === EG.localTail.find(([n]) => n === file)[1]);
  const sql = bytes.toString('utf8');
  const pinned = new Map(S.functions.map((f) => [f[0], f]));
  assert.equal(pinned.size, S.functions.length, 'one pin per name');
  // The 23 functions the file creates or replaces: body, security definer, config, volatility and language from the bytes.
  const created = createdFunctions(sql);
  assert.equal(created.length, 23);
  for (const [name, src, secdef, config, volatility, language] of created) {
    const p = pinned.get(name);
    assert.ok(p, name);
    assert.deepEqual(p.slice(2, 7), [src, secdef, config, volatility, language], name);
  }
  // Their identity arguments, as pg_get_function_identity_arguments prints them: timestamptz spelled out, defaults left out.
  const identity = (params) => params.replace(/\btimestamptz\b/g, 'timestamp with time zone').replace(/\s+default\s+[^,]+/gi, '');
  for (const [name, params] of createdFunctionArgs(sql)) assert.equal(pinned.get(name)[1], identity(params), name);
  // The one CREATE OR REPLACE keeps the earlier access (the file neither grants nor revokes it): the inherited group.
  const replaced = splitSql(sql).map(lead).filter((s) => /^create\s+or\s+replace\s+function/i.test(s)).map((s) => /function\s+([a-z_]+\.[a-z_0-9]+)/i.exec(s)[1]);
  assert.deepEqual(replaced, ['app.pos_order_alert_authority']);
  assert.deepEqual(S.functions.filter((f) => f[7] === 'inherited').map((f) => f[0]), replaced);
  assert.deepEqual(Object.keys(S.inheritedAccess), replaced);
  assert.deepEqual(S.inheritedAccess['app.pos_order_alert_authority'], EG.access.functions.none, 'its earlier access: the owner only');
  // The five renames: new names, the same arguments, and each revoked from every client role.
  const renames = splitSql(sql).map((s) => /^\s*alter\s+function\s+app\.([a-z_0-9]+)\s*\(([^)]*)\)\s+rename\s+to\s+([a-z_0-9]+)\s*;/i.exec(s.replace(/--[^\n]*\n/g, '\n')))
    .filter(Boolean).map((m) => ({ oldName: `app.${m[1]}`, newName: `app.${m[3]}`, args: m[2].replace(/\s+/g, '') }));
  assert.deepEqual(renames.map((r) => [r.oldName, r.newName]), CORE_RENAMES);
  assert.equal(created.length + renames.length, S.functions.length);
  const sets = grantSets(sql);
  const GROUP = {
    'revoke all from public,anon,authenticated,service_role': 'none',
    'revoke all from public,anon,authenticated,service_role;grant execute to authenticated': 'authenticated',
    'revoke all from public,anon,authenticated,service_role;grant execute to service_role': 'service_role',
  };
  for (const [name, , , , , , , group] of S.functions) {
    if (group === 'inherited') { assert.ok(!sets.has(name), `${name} is neither granted nor revoked`); continue; }
    assert.equal(GROUP[(sets.get(name) || []).join(';')] ?? 'unexpected', group, name);
  }
  for (const r of renames) assert.equal(pinned.get(r.newName)[7], 'none', r.newName);
  // Each group's exact entries are the owner plus exactly the granted role, EXECUTE, without grant option, granted by the owner.
  assert.deepEqual(Object.keys(S.access).sort(), ['authenticated', 'none', 'service_role']);
  const roles = { none: [], authenticated: ['authenticated'], service_role: ['service_role'] };
  for (const [group, entries] of Object.entries(S.access)) {
    assert.deepEqual(entries.map((e) => e[0]).sort(), [...roles[group], EG.owner].sort(), group);
    for (const e of entries) assert.deepEqual(e.slice(1), ['EXECUTE', false, EG.owner], group);
  }
  // The renamed functions keep the earlier body (a rename keeps prosrc). Four bodies are the latest static definitions of
  // the original names in the earlier files; app.pos_register_order_alert's was patched in place by two later files, so its
  // pin is the live proof's value, which must differ from the last static definition, and both patch files must name it.
  const earlier = gitMigrationNames().filter((n) => n < file);
  const latest = new Map();
  for (const n of earlier) for (const [name, src] of createdFunctions(gitBlob(n).toString('utf8'))) if (renames.some((r) => r.oldName === name)) latest.set(name, src);
  for (const r of renames) {
    const pin = pinned.get(r.newName);
    assert.ok(latest.has(r.oldName), r.oldName);
    if (r.oldName === 'app.pos_register_order_alert') {
      assert.notEqual(pin[2], latest.get(r.oldName), 'patched in place after its last static definition');
      for (const n of PATCH_FILES) {
        assert.ok(earlier.includes(n), n);
        const patch = gitBlob(n).toString('utf8');
        assert.ok(/'app\.pos_register_order_alert\(uuid,text,text,uuid,uuid,text\)'::regprocedure/.test(patch) && /pg_get_functiondef/.test(patch) && /\bexecute\b/i.test(patch), n);
      }
    } else {
      assert.equal(pin[2], latest.get(r.oldName), r.newName);
    }
  }
  // The relations: the three tables the file creates, locked down in its DO block (row level security enabled and forced,
  // every privilege revoked from PUBLIC and the client roles, no policy), and the one table it alters; the pins.
  const stmts = splitSql(sql).map(lead).map((s) => s.replace(/\s+/g, ' ').trim());
  const tables = stmts.map((s) => /^create table ([a-z_]+\.[a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => m[1]).sort();
  assert.deepEqual(tables, ['app.pos_shift_alert_approvals', 'app.pos_shift_alert_consents', 'app.pos_shift_alert_policies']);
  const altered = stmts.map((s) => /^alter table ([a-z_]+\.[a-z_0-9]+) add column/i.exec(s)).filter(Boolean).map((m) => m[1]);
  assert.deepEqual(altered, ['app.pos_order_alert_registrations']);
  assert.deepEqual(S.relations.map((r) => r.name), [...tables, ...altered].sort());
  const loop = /foreach\s+t\s+in\s+array\s+array\[([^\]]+)\]\s+loop([\s\S]*?)end\s+loop;/i.exec(sql);
  assert.ok(loop, 'the lockdown loop');
  assert.deepEqual(loop[1].split(',').map((s) => `app.${s.trim().replace(/^'|'$/g, '')}`).sort(), tables);
  assert.ok(/enable row level security/.test(loop[2]) && /force row level security/.test(loop[2]) && /revoke all on app\.%I from public,anon,authenticated,service_role/.test(loop[2]));
  assert.equal((sql.match(/create\s+policy/gi) || []).length, 0, 'no policy statement');
  assert.ok(!stmts.some((s) => /^grant /i.test(s) && /on (table )?app\./i.test(s) && !/on function/i.test(s)), 'no table grant');
  const denyClient = { name: EG.policy.name, cmd: EG.policy.cmd, permissive: EG.policy.permissive, roles: [...EG.policy.roles], using: EG.policy.using, check: EG.policy.check };
  for (const r of S.relations) {
    assert.deepEqual([r.kind, r.rls, r.force_rls], ['r', true, true], r.name);
    assert.deepEqual(r.access, EG.access.table, `${r.name}: the owner's PostgreSQL 17 privileges only`);
    assert.deepEqual([...r.columns], [], r.name);
    assert.ok(/^[0-9a-f]{64}$/.test(r.definition), r.name);
    // The three new tables have no policy; the altered one keeps its earlier deny_client policy (the project's standard one).
    assert.deepEqual(r.policies.map((p) => ({ ...p, roles: [...p.roles] })), tables.includes(r.name) ? [] : [denyClient], r.name);
  }
  // The indexes (twelve, on the consents table and the altered registrations table) and the triggers (twelve, each an
  // AFTER UPDATE trigger on another table that executes the file's trigger function).
  const indexes = stmts.map((s) => /^create (?:unique )?index ([a-z_0-9]+) on ([a-z_]+\.[a-z_0-9]+)/i.exec(s)).filter(Boolean).map((m) => [m[1], m[2]]);
  assert.equal(indexes.length, 12);
  assert.deepEqual([...new Set(indexes.map((i) => i[1]))].sort(), ['app.pos_order_alert_registrations', 'app.pos_shift_alert_consents']);
  const triggers = stmts.map((s) => /^create trigger ([a-z_0-9]+) after update on ([a-z_]+\.[a-z_0-9]+) for each row when .* execute function app\.end_pos_shift_alert_bindings\(\);$/i.exec(s))
    .filter(Boolean).map((m) => `${m[1]}@${m[2]}`).sort();
  assert.equal(triggers.length, 12);
  assert.deepEqual(S.triggers.map((x) => x[0]), triggers);
  for (const [, def] of S.triggers) assert.ok(/^[0-9a-f]{64}$/.test(def));
  assert.equal((sql.match(/create\s+(?:or\s+replace\s+)?trigger/gi) || []).length, 12, 'no other trigger statement');
  // #386's objects are not part of the #379 / #380 / #382 surfaces (they have their own pins) and not of the 001D manifest.
  for (const [name] of S.functions) assert.ok(!EG.surfaceFunctions.includes(name) && !EG.functions.some((f) => f[0] === name), name);
  for (const r of S.relations) assert.ok(!EG.surfaceTables.includes(r.name) && !EG.tables.includes(r.name), r.name);
});

test('exact-gap #386 surface pins (D-068): the catalog renderings are the live proof\'s, and each is one distinct digest', () => {
  const S = EG.surface386;
  // The whole-definition digests (pg_get_functiondef), the relations' catalog-line digests and the triggers' definition
  // digests are PostgreSQL 17.6 renderings, which the migration bytes cannot give. They are the values the current-main
  // sequential reference and the hosted-shape gap database both showed (the run's pin check). This digest over every
  // catalog-rendered pin fails on any change of one of them, so a pin can only move together with a new live proof.
  for (const f of S.functions) assert.ok(f.length === 9 && /^[0-9a-f]{64}$/.test(f[8]), f[0]);
  assert.equal(new Set(S.functions.map((f) => f[8])).size, S.functions.length);
  assert.equal(new Set(S.functions.map((f) => f[2])).size, S.functions.length, 'every body is distinct');
  assert.equal(new Set(S.relations.map((r) => r.definition)).size, S.relations.length);
  assert.equal(new Set(S.triggers.map((t) => t[1])).size, S.triggers.length);
  assert.equal(S.functions.length, 28);
  assert.equal(S.relations.length, 4);
  assert.equal(S.triggers.length, 12);
  const rendered = JSON.stringify({
    args: S.functions.map((f) => [f[0], f[1]]), def: S.functions.map((f) => [f[0], f[8]]),
    relations: S.relations.map((r) => [r.name, r.definition, r.policies]), triggers: S.triggers.map((t) => [t[0], t[1]]),
  });
  assert.ok(sha(Buffer.from(rendered, 'utf8')) === 'df9e27e5f883424c4ad05a8059179336657e985f5a8711ee338f14b7a95b9435', 'the catalog-rendered #386 pins are the live proof\'s');
});

test('exact-gap PRE #386 surface (D-068): its functions, relations and triggers must be exactly as pinned', () => {
  assert.deepEqual(evaluateExactGapPre(egPreState(), EG_LOCAL), []);
  const variant = (change) => { const s = egPreState(); change(s.surface386, s); return evaluateExactGapPre(s, EG_LOCAL); };
  const fn = (x, name) => x.functions.find((f) => f.name === name);
  // Functions: presence, identity and definition.
  onlyCode(variant((x) => { x.functions = x.functions.filter((f) => f.name !== 'app.pos_register_order_alert_core'); }), 'surface386_function', 'a renamed core function missing');
  onlyCode(variant((x) => { x.functions = x.functions.filter((f) => f.name !== 'public.set_pos_shift_alert_policy'); }), 'surface386_function', 'a public wrapper missing');
  onlyCode(variant((x) => { x.functions.push({ ...fn(x, 'app.pos_shift_alert_owner'), args: 'p_branch text' }); }), 'surface386_function', 'an extra overload');
  onlyCode(variant((x) => { x.functions.push({ ...fn(x, 'app.pos_shift_alert_owner'), name: 'app.pos_shift_alert_owner_v2' }); }), 'surface386_function', 'a row under an unpinned name (a malformed answer)');
  for (const [label, change] of [
    ['another identity', (f) => { f.args = 'p_pin uuid'; }], ['another body', (f) => { f.src = '0'.repeat(64); }],
    ['another whole definition (another result type, strictness, cost or rows)', (f) => { f.def = '0'.repeat(64); }], ['no definition answer', (f) => { delete f.def; }],
    ['no longer SECURITY DEFINER', (f) => { f.secdef = false; }], ['another config', (f) => { f.config = ''; }],
    ['another volatility', (f) => { f.volatility = 's'; }], ['another language', (f) => { f.language = 'sql'; }],
    ['a procedure', (f) => { f.kind = 'p'; }], ['another owner', (f) => { f.owner = 'supabase_admin'; }],
  ]) onlyCode(variant((x) => change(fn(x, 'app.pos_shift_alert_human'))), 'surface386_function', label);
  // The renamed core function's body is pinned too (the preserved earlier body).
  onlyCode(variant((x) => { fn(x, 'app.pos_register_order_alert_core').src = EG.surface386.functions.find((f) => f[0] === 'app.pos_register_order_alert')[2]; }), 'surface386_function', 'the core body replaced by the wrapper body');
  // Functions: exact access.
  onlyCode(variant((x) => { fn(x, 'public.set_pos_shift_alert_policy').access.push(FIFTH()); }), 'surface386_access', 'a fifth role on a public wrapper');
  onlyCode(variant((x) => { fn(x, 'app.pos_register_order_alert_core').access.push(['authenticated', 'EXECUTE', false, 'postgres']); }), 'surface386_access', 'a client grant on a renamed core function');
  onlyCode(variant((x) => { fn(x, 'app.pos_order_alert_authority').access.push(['service_role', 'EXECUTE', false, 'postgres']); }), 'surface386_access', 'a grant on the inherited-access function');
  onlyCode(variant((x) => { const f = fn(x, 'public.pos_shift_order_alert_status'); f.access = f.access.filter((e) => e[0] !== 'service_role'); }), 'surface386_access', 'a removed grant');
  onlyCode(variant((x) => { const f = fn(x, 'app.set_pos_shift_alert_policy'); f.access = f.access.map((e) => (e[0] === 'authenticated' ? [e[0], e[1], e[2], 'supabase_admin'] : e)); }), 'surface386_access', 'a changed grantor');
  onlyCode(variant((x) => { const f = fn(x, 'app.pos_revoke_shift_order_alert'); f.access = f.access.map((e) => (e[0] === 'service_role' ? [e[0], e[1], true, e[3]] : e)); }), 'surface386_access', 'WITH GRANT OPTION');
  onlyCode(variant((x) => { fn(x, 'app.pos_shift_alert_owner').access = 'postgres=X/postgres'; }), 'surface386_access', 'a malformed access answer');
  // The relations.
  const rel = (x, name) => x.relations.find((r) => r.name === name);
  onlyCode(variant((x) => { x.relations = x.relations.filter((r) => r.name !== 'app.pos_shift_alert_consents'); }), 'surface386_relation', 'a table missing');
  onlyCode(variant((x) => { x.relations.push({ ...rel(x, 'app.pos_shift_alert_policies') }); }), 'surface386_relation', 'a table twice');
  for (const [label, change] of [
    ['another definition (a column, constraint, index or trigger)', (r) => { r.definition = '0'.repeat(64); }], ['RLS not forced', (r) => { r.force_rls = false; }],
    ['RLS off', (r) => { r.rls = false; }], ['another owner', (r) => { r.owner = 'supabase_admin'; }], ['another kind', (r) => { r.kind = 'p'; }],
    ['a policy added', (r) => { r.policies.push({ name: 'open', cmd: 'r', permissive: true, roles: ['authenticated'], using: 'true', check: null }); }],
  ]) onlyCode(variant((x) => change(rel(x, 'app.pos_shift_alert_policies'))), 'surface386_relation', label);
  for (const [label, change] of [
    ['the deny_client policy removed', (r) => { r.policies = []; }], ['the deny_client policy opened', (r) => { r.policies[0].using = 'true'; }],
    ['the deny_client policy for another role', (r) => { r.policies[0].roles = ['anon']; }], ['the deny_client policy restrictive', (r) => { r.policies[0].permissive = false; }],
    ['the deny_client policy for one command', (r) => { r.policies[0].cmd = 'r'; }], ['a duplicate policy', (r) => { r.policies.push({ ...r.policies[0] }); }],
  ]) onlyCode(variant((x) => change(rel(x, 'app.pos_order_alert_registrations'))), 'surface386_relation', label);
  onlyCode(variant((x) => { rel(x, 'app.pos_shift_alert_consents').access.push(FIFTH('SELECT')); }), 'surface386_access', 'a fifth role on a table');
  onlyCode(variant((x) => { const r = rel(x, 'app.pos_shift_alert_approvals'); r.access = r.access.filter((e) => e[1] !== 'MAINTAIN'); }), 'surface386_access', 'a removed owner privilege');
  onlyCode(variant((x) => { rel(x, 'app.pos_order_alert_registrations').columns.push(['duty_consent_id', 'anon', 'SELECT', false, 'postgres']); }), 'surface386_access', 'a column grant');
  // The triggers.
  onlyCode(variant((x) => { x.triggers = x.triggers.filter((t) => t.name !== 'end_shift_alert_on_shift@public.shifts'); }), 'surface386_trigger', 'a trigger missing');
  onlyCode(variant((x) => { x.triggers.push({ ...x.triggers[0] }); }), 'surface386_trigger', 'a trigger twice');
  onlyCode(variant((x) => { x.triggers[3].enabled = 'D'; }), 'surface386_trigger', 'a trigger disabled');
  onlyCode(variant((x) => { x.triggers[3].enabled = 'A'; }), 'surface386_trigger', 'a trigger set to ALWAYS');
  onlyCode(variant((x) => { x.triggers[5].def = '0'.repeat(64); }), 'surface386_trigger', 'another trigger definition (its WHEN clause or function)');
  // An answer row under an unpinned name is a malformed answer (the state query selects pinned names only): the counts refuse it.
  onlyCode(variant((x) => { x.relations.push({ ...rel(x, 'app.pos_shift_alert_policies'), name: 'app.pos_shift_alert_other' }); }), 'surface386_relation', 'a relation under an unpinned name');
  onlyCode(variant((x) => { x.triggers.push({ ...x.triggers[0], name: 'end_shift_alert_on_other@public.shifts' }); }), 'surface386_trigger', 'a trigger under an unpinned name');
  // The inherited-access function is compared with its own pinned entries, never with a group's: under a pins variant whose inherited
  // entries differ from every group, only a matching answer passes.
  const inheritedEntries = [['postgres', 'EXECUTE', false, 'postgres'], ['service_role', 'EXECUTE', false, 'postgres']];
  const inheritedPins = { ...EG, surface386: { ...EG.surface386, inheritedAccess: { 'app.pos_order_alert_authority': inheritedEntries } } };
  const withInherited = (change) => {
    const s = egPreState();
    const f = s.surface386.functions.find((g) => g.name === 'app.pos_order_alert_authority');
    f.access = inheritedEntries.map((e) => [...e]);
    if (change) change(f);
    return evaluateExactGapPre(s, EG_LOCAL, inheritedPins);
  };
  assert.deepEqual(withInherited(), [], 'the inherited entries are read from inheritedAccess');
  onlyCode(withInherited((f) => { f.access = EG.surface386.access.none.map((e) => [...e]); }), 'surface386_access', 'an answer equal to the none group is refused when the inherited entries differ');
  // A missing or malformed answer.
  onlyCode(variant((x, s) => { delete s.surface386; }), 'surface386_unreadable', 'no answer');
  onlyCode(variant((x, s) => { s.surface386 = { functions: [], relations: [] }; }), 'surface386_unreadable', 'a partial answer');
  // D-067: a CR in a #386 function is refused as in every other selected function.
  const crlf = variant((x) => { Object.assign(fn(x, 'public.set_pos_shift_alert_policy'), { cr: 3, crlf: 3, lone_cr: false }); });
  assert.deepEqual(codes(crlf), ['selected_function_eol']);
  assert.match(crlf[0][1], /^public\.set_pos_shift_alert_policy: carriage returns in a body accepted only in its canonical LF form$/);
});

test('exact-gap POST #386 surface (D-068): identical to PRE', () => {
  const pre = egPreState();
  const base = () => ({ pre, post: egPostState(pre), normal: UP_TO_DATE, list: LIST_OK, local: EG_LOCAL });
  assert.deepEqual(evaluateExactGapPost(base()), []);
  const variant = (change) => { const v = base(); change(v.post.surface386, v.post); return evaluateExactGapPost(v); };
  for (const [label, change] of [
    ['a fifth role on a #386 function', (x) => { x.functions[0].access.push(FIFTH()); }],
    ['a #386 function removed', (x) => { x.functions.pop(); }],
    ['a #386 overload added', (x) => { x.functions.push({ ...x.functions[0], args: 'x' }); }],
    ['a #386 body changed', (x) => { x.functions[3].src = '0'.repeat(64); }],
    ['a #386 whole definition changed (another result type)', (x) => { x.functions[5].def = '0'.repeat(64); }],
    ['a #386 relation changed', (x) => { x.relations[0].definition = 'f'.repeat(64); }],
    ['a #386 relation grant', (x) => { x.relations[0].access.push(FIFTH('SELECT')); }],
    ['a #386 column grant', (x) => { x.relations[0].columns.push(['duty_consent_id', 'anon', 'SELECT', false, 'postgres']); }],
    ['a #386 policy added', (x) => { x.relations[1].policies.push({ name: 'open', cmd: 'r', permissive: true, roles: ['anon'], using: 'true', check: null }); }],
    ['a #386 trigger disabled', (x) => { x.triggers[0].enabled = 'D'; }],
    ['a #386 trigger changed', (x) => { x.triggers[1].def = '0'.repeat(64); }],
    ['a #386 trigger removed', (x) => { x.triggers.pop(); }],
    ['no answer', (x, p) => { delete p.surface386; }],
    ['a malformed answer', (x, p) => { p.surface386 = 'x'; }],
  ]) onlyCode(variant(change), 'post_surface386', label);
  // D-067: a #386 function in CRLF at POST is named by the line-ending rule as well as by the identity.
  const eol = variant((x) => { Object.assign(x.functions[2], { cr: 2, crlf: 2 }); });
  assert.deepEqual(codes(eol).sort(), ['post_function_eol', 'post_surface386']);
});

test('exact-gap flow (D-068): a #386 surface change refuses before the push; a POST #386 difference is a STOP after it', async () => {
  const pre = egPreState();
  const with386 = (state, change) => { const s = JSON.parse(JSON.stringify(state)); change(s.surface386); return s; };
  // Between the first and the second PRE read: the state fingerprint covers the whole #386 surface.
  for (const [label, change] of [
    ['a fifth role on a #386 function', (x) => { x.functions.find((f) => f.name === 'public.set_pos_shift_alert_policy').access.push(FIFTH()); }],
    ['a #386 relation changed', (x) => { x.relations[2].definition = '0'.repeat(64); }],
    ['a #386 trigger disabled', (x) => { x.triggers[4].enabled = 'D'; }],
  ]) {
    const r = await runExactGap({ scenario: { changedBeforePush: with386(pre, change) } });
    assert.equal(r.code, 2, `${label}: ${r.out}`);
    assert.match(r.out, /^REFUSED state_changed:/m, label);
    assert.deepEqual(kinds(r.calls), ['version', 'query', 'dry-include-all', 'query'], label);
    assert.ok(noLeak(r.out), r.out);
  }
  // At the first read the PRE gate refuses, before the dry run.
  const first = await runExactGap({ scenario: { pre: with386(pre, (x) => { x.triggers[0].enabled = 'D'; }) } });
  assert.equal(first.code, 2, first.out);
  // The pinned triggers are ordered by name: the first is end_shift_alert_on_branch on public.branches.
  assert.match(first.out, /^gr37 exact-gap: PRE gate surface386_trigger: end_shift_alert_on_branch@public\.branches: disabled/m);
  assert.match(first.out, /^REFUSED surface386_trigger:/m);
  assert.deepEqual(kinds(first.calls), ['version', 'query']);
  // After the push: a #386 difference is a POSTCHECK_MISMATCH (exit 4), never a refusal.
  const post = egPostState(pre);
  post.surface386.functions[0].access.push(FIFTH());
  const after = await runExactGap({ scenario: { post } });
  assert.equal(after.code, 4, after.out);
  assert.match(after.out, /POST check post_surface386: #386's surface[\s\S]*RESULT: POSTCHECK_MISMATCH/);
  assert.ok(!/^REFUSED /m.test(after.out) && noLeak(after.out), after.out);
  // A passing run names #386's surface in its PRE and POST lines, and the five stored statements.
  const ok = await runExactGap({});
  assert.equal(ok.code, 0, ok.out);
  assert.match(ok.out, /remote ledger 188 versions ending 20261104131256, 20261105025413, 20261105025604, 20261105141815, 20261108085442; the only gap is 20261104141959; 20261104131256, 20261105025413, 20261105025604, 20261105141815, 20261108085442 each hold their one reviewed statement/);
  assert.match(ok.out, /#386's own surface as pinned \(28 functions, 4 relations and 12 triggers: definition, owner and exact access\)/);
  assert.match(ok.out, /local folder = the pinned main set: 189 migrations \(names and bytes\), ending 20261104131256, 20261104141959, 20261105025413, 20261105025604, 20261105141815, 20261108085442/);
  assert.match(ok.out, /POST \(read-only\): remote ledger 189 versions = the local set[\s\S]*migration list 189 rows, none divergent/);
  assert.match(ok.out, /#382's surface, every storage\.objects policy and #386's surface identical to PRE/);
});
