#!/usr/bin/env node
// GR-37 bounded migration apply (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001): the one approved route for
// applying the frozen 001D migration with finite lock and statement timeouts, outside the migration body.
// The installed Supabase CLI 2.107.0 ignores PGOPTIONS, so the three startup settings travel in the `options`
// parameter of a PASSWORDLESS --db-url; the password comes only from an owner-private PGPASSFILE; PGSSLMODE=require
// makes the CLI refuse a session without TLS. Nothing edits the SQL, writes the migration ledger by hand, passes
// --include-all, calls `migration repair` or retries the push, and the CLI's own advice to do any of that is never
// relayed: a refusal prints REFUSED <code> and pushes nothing, and every CLI failure ends in a STOP verdict.
// Inputs, from the environment only and never printed: BIZBOT_GR37_DB_URL (passwordless), BIZBOT_GR37_PASSFILE and
// BIZBOT_GR37_SUPABASE_CLI (the absolute path of the pinned supabase.exe).
// Usage: node tools/supabase/bounded-db-push.mjs --mode local|hosted [--project-ref <ref>] --workdir <dir> [--apply]
// Without --apply it stops after the dry run. Exit: 0 done; 2 refused, nothing pushed; 3 a CLI step failed;
// 4 the post-check does not match.
// One-time exact-gap mode (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001, DECISION D-066): adding
// `--exact-gap BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001` (plus BIZBOT_GR37_SSLROOTCERT, the owner-private
// CA) applies 001D into the one pinned history gap instead; see the section at the end of this file. Without that flag
// everything above and below runs exactly as before.
import { spawn, spawnSync } from 'node:child_process';
import { X509Certificate, createHash } from 'node:crypto';
import {
  closeSync, mkdtempSync, openSync, readFileSync, readSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync,
} from 'node:fs';
import { url as inspectorUrl } from 'node:inspector';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const CLI_VERSION = '2.107.0';
// The official supabase_2.107.0_windows_amd64.zip members (release asset SHA-256 2d909c0c...6afd). The front end runs
// the Go engine beside it, so both executables are pinned.
export const CLI_BINARIES = Object.freeze({
  'win32-x64': Object.freeze({
    'supabase.exe': 'bb59c6b769f6fa8817b0a7ee98cf791ad29d65268dd0c76df6ced6d22a8a2933',
    'supabase-go.exe': '4fb853b875b1e44c886e5e298b8b84be1399e23f1db629d2e8e6936c5e454125',
  }),
});
export const MIGRATION = '20261104141959_bizbot_zcredit_001d_server_ledger.sql';
export const MIGRATION_SHA256 = '468768f89029a0fb131869f754d5374127930b8bf05b48cd8de19d645546352e';
export const APPLICATION_NAME = 'bizbot_gr37_001d_v1';
// Fixed: no caller can add another PostgreSQL option.
export const STARTUP_OPTIONS = `-c lock_timeout=5s -c statement_timeout=60s -c application_name=${APPLICATION_NAME}`;
export const ENV_URL = 'BIZBOT_GR37_DB_URL';
export const ENV_PASSFILE = 'BIZBOT_GR37_PASSFILE';
export const ENV_CLI = 'BIZBOT_GR37_SUPABASE_CLI';
// The child sees only these inherited variables, plus the four the wrapper sets. PGPASSWORD, SUPABASE_DB_PASSWORD,
// PGOPTIONS, PGSERVICE*, PGAPPNAME, every SUPABASE_* and every *DEBUG* variable therefore never reach the CLI.
const INHERITED = ['SystemRoot', 'SYSTEMROOT', 'windir', 'ComSpec', 'PATHEXT', 'PATH', 'Path', 'TEMP', 'TMP',
  'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'HOMEDRIVE', 'HOMEPATH', 'HOME', 'USERNAME', 'LANG'];
const LOOPBACK = new Set(['127.0.0.1', 'localhost']);
const SELF = fileURLToPath(import.meta.url);

export class Refusal extends Error {
  constructor(code, message) { super(message); this.code = code; }
}
const refuse = (code, message) => { throw new Refusal(code, message); };
const sha256 = (bytes) => createHash('sha256').update(bytes).digest('hex');

function sha256File(file) {
  const hash = createHash('sha256');
  const buffer = Buffer.alloc(1 << 20);
  const fd = openSync(file, 'r');
  try {
    for (let n = readSync(fd, buffer, 0, buffer.length, null); n > 0; n = readSync(fd, buffer, 0, buffer.length, null)) {
      hash.update(buffer.subarray(0, n));
    }
  } finally { closeSync(fd); }
  return hash.digest('hex');
}

export function parseArgs(argv) {
  if (argv.some((a) => /^--(debug|log-level)\b/i.test(a))) refuse('debug_refused', 'debug output is not allowed');
  const out = { mode: null, projectRef: null, workdir: null, apply: false };
  const keys = { '--mode': 'mode', '--project-ref': 'projectRef', '--workdir': 'workdir' };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--apply') {
      if (out.apply) refuse('bad_arguments', 'repeated --apply');
      out.apply = true;
      continue;
    }
    const key = keys[argv[i]];
    if (!key) refuse('bad_arguments', 'unknown argument'); // never echoed: it could be a pasted secret
    if (out[key] !== null) refuse('bad_arguments', `repeated ${argv[i]}`);
    if (i + 1 >= argv.length || argv[i + 1].startsWith('--')) refuse('bad_arguments', `missing value after ${argv[i]}`);
    out[key] = argv[i + 1];
    i += 1;
  }
  if (!['local', 'hosted'].includes(out.mode)) refuse('bad_arguments', '--mode must be local or hosted');
  if (out.mode === 'hosted' && !/^[a-z]{20}$/.test(out.projectRef ?? '')) refuse('bad_arguments', 'hosted mode needs --project-ref (20 lowercase letters)');
  if (out.mode === 'local' && out.projectRef !== null) refuse('bad_arguments', '--project-ref is for hosted mode only');
  if (!out.workdir || !path.isAbsolute(out.workdir)) refuse('bad_arguments', '--workdir must be an absolute path');
  return out;
}

// The flags that start an inspector or load code before the wrapper runs. Configuration-only flags such as
// --inspect-port and --inspect-publish-uid start nothing (Node 24's test runner passes them with their defaults).
const DEBUG_FLAG = /^(?:-r|--require|--import|--loader|--experimental-loader|--inspect|--inspect-brk|--inspect-wait|--debug|--debug-brk)(?:=|$)/;

// The wrapper holds the password in memory: no debug variable, no NODE_OPTIONS, no inspector and no preloaded module.
export function refuseDebug(env, execArgv = process.execArgv, inspectorActive = () => Boolean(inspectorUrl())) {
  if (Object.keys(env).some((key) => /debug/i.test(key))) refuse('debug_refused', 'a debug environment variable is set');
  if (Object.keys(env).some((key) => key.toUpperCase() === 'NODE_OPTIONS' && String(env[key]).trim() !== '')) {
    refuse('debug_refused', 'NODE_OPTIONS is set');
  }
  if (execArgv.some((a) => DEBUG_FLAG.test(a)) || inspectorActive()) {
    refuse('debug_refused', 'an inspector or preload flag is set on this Node process');
  }
}

// postgresql://<user>@<host>:<port>/<database> and nothing else: no password, no query, no fragment.
export function parseTargetUrl(raw, { mode, projectRef }) {
  if (typeof raw !== 'string' || raw === '') refuse('url_missing', `${ENV_URL} is not set`);
  if (/^[a-z][a-z0-9+.-]*:\/\/[^@/?#]*:[^@/?#]*@/i.test(raw)) refuse('url_password', 'the database URL must carry no password');
  const m = /^(?:postgres|postgresql):\/\/([A-Za-z0-9._-]+)@([A-Za-z0-9.-]+):([0-9]{1,5})\/([A-Za-z0-9_-]+)$/.exec(raw);
  if (!m) refuse('url_invalid', 'the database URL must be postgresql://<user>@<host>:<port>/<database> with no other part');
  const [, user, hostRaw, port, database] = m;
  const host = hostRaw.toLowerCase();
  if (/(^|\.)pooler\.supabase\.com$/.test(host) || port === '6543') refuse('pooler_refused', 'pooler hosts are refused; use the direct database host');
  if (mode === 'local' && !LOOPBACK.has(host)) refuse('url_not_loopback', 'local mode accepts a loopback host only');
  if (mode === 'hosted' && (host !== `db.${projectRef}.supabase.co` || port !== '5432' || user !== 'postgres' || database !== 'postgres')) {
    refuse('url_not_direct_host', 'hosted mode accepts only postgres@db.<project-ref>.supabase.co:5432/postgres');
  }
  return { user, host, port, database };
}

export const buildDbUrl = ({ user, host, port, database }) =>
  `postgresql://${user}@${host}:${port}/${database}?options=${encodeURIComponent(STARTUP_OPTIONS)}`;

// The shape that may be printed: every private value replaced.
export const urlShape = (mode) =>
  `postgresql://<user>@${mode === 'hosted' ? '<direct-host>:5432' : '<loopback>:<port>'}/<database>?options=${encodeURIComponent(STARTUP_OPTIONS)}`;

export function buildChildEnv(parent, passfile) {
  const env = {};
  // Windows keys are case-insensitive: copy each inherited key once, under the parent's own spelling.
  const allowed = new Set(INHERITED.map((key) => key.toUpperCase()));
  for (const key of Object.keys(parent)) if (allowed.has(key.toUpperCase()) && typeof parent[key] === 'string') env[key] = parent[key];
  env.PGPASSFILE = passfile;
  env.PGSSLMODE = 'require';
  env.SUPABASE_TELEMETRY_DISABLED = '1';
  env.DO_NOT_TRACK = '1';
  return env;
}

// .pgpass entries as the CLI's own reader (jackc/pgpassfile v1.0.0) reads them: '#' comments, the \\ and \: escapes,
// exactly five ':'-separated fields. A line that this reader, libpq and the CLI could read differently is malformed
// (null) rather than guessed: surrounding whitespace, a character outside printable ASCII, any other backslash, or a
// field count other than five.
export function parsePassfile(text) {
  const entries = [];
  for (const raw of text.split('\n')) {
    const line = raw.endsWith('\r') ? raw.slice(0, -1) : raw;
    if (line === '' || line.startsWith('#')) continue;
    if (line !== line.trim() || /[^\x20-\x7e]/.test(line) || /\\(?!:)/.test(line.replace(/\\\\/g, ''))) {
      entries.push(null);
      continue;
    }
    const fields = line.replace(/\\\\/g, '\u0000').replace(/\\:/g, '\u0001').split(':')
      .map((f) => f.replace(/\u0000/g, '\\').replace(/\u0001/g, ':'));
    entries.push(fields.length === 5 ? fields : null);
  }
  return entries;
}

export function selectPassfileEntry(entries, { host, port, database, user }) {
  if (entries.some((e) => e === null)) refuse('passfile_malformed', 'the passfile has a malformed line');
  if (entries.some((e) => e.slice(0, 4).includes('*'))) refuse('passfile_wildcard', 'the passfile may not use wildcards');
  const hits = entries.filter((e) => e[0] === host && e[1] === port && e[2] === database && e[3] === user);
  if (hits.length !== 1 || hits[0][4] === '') refuse('passfile_entry', 'the passfile must hold exactly one entry for the exact target');
  return hits[0][4];
}

const within = (child, parent) => {
  const rel = path.relative(parent, child);
  return rel === '' || (rel !== '..' && !rel.startsWith(`..${path.sep}`) && !path.isAbsolute(rel)); // '..x' is inside
};

// Refused anywhere inside the repository, its parent folder (the store, or the worktrees folder and its store), the
// workdir, or any folder named worktrees or evidence.
export function passfileLocationProblem(file, { repoRoot, workdir }) {
  const parent = path.dirname(repoRoot);
  const roots = [repoRoot, parent, workdir];
  if (path.basename(parent).toLowerCase() === 'worktrees') roots.push(path.dirname(parent));
  if (roots.some((root) => within(file, root))) return 'inside the repository, the project store or the workdir';
  if (file.split(/[\\/]+/).some((part) => ['worktrees', 'evidence'].includes(part.toLowerCase()))) return 'inside a worktrees or evidence folder';
  return null;
}

export function aclPrincipals(icaclsOutput, file) {
  const found = [];
  icaclsOutput.replace(/\r/g, '').split('\n').filter((l) => l.trim()).forEach((line, index) => {
    if (/^Successfully processed|^Failed processing/i.test(line.trim())) return;
    const text = (index === 0 && line.startsWith(file) ? line.slice(file.length) : line).trim();
    const at = text.indexOf(':(');
    if (at > 0) found.push(text.slice(0, at).trim().toLowerCase());
  });
  return found;
}

export function aclProblem(principals, current) {
  return principals.length === 1 && principals[0] === current.toLowerCase() ? null : 'the ACL must grant the current user only';
}

export const posixModeProblem = (st, uid) =>
  ((st.mode & 0o777) === 0o600 && st.uid === uid ? null : 'the passfile must be mode 0600 and owned by the current user');

function systemTool(name) {
  return path.join(process.env.SystemRoot || process.env.SYSTEMROOT || 'C:\\Windows', 'System32', name);
}

// Paths are compared in their canonical long form: the native realpath resolves 8.3 short names and device-path
// spellings that the JavaScript realpath keeps.
const canonical = (p) => realpathSync.native(p);

export function verifyPassfile(raw, target, workdir, { repoRoot = path.resolve(path.dirname(SELF), '..', '..') } = {}) {
  if (typeof raw !== 'string' || raw === '') refuse('passfile_missing', `${ENV_PASSFILE} is not set`);
  if (!path.isAbsolute(raw)) refuse('passfile_missing', 'the passfile path must be absolute');
  let real;
  let st;
  try { real = canonical(raw); st = statSync(real); } catch { refuse('passfile_missing', 'the passfile does not exist'); }
  if (!st.isFile()) refuse('passfile_missing', 'the passfile is not a regular file');
  let workReal;
  try { workReal = canonical(workdir); } catch { refuse('bad_arguments', 'the workdir does not exist'); }
  const where = passfileLocationProblem(real, { repoRoot: canonical(repoRoot), workdir: workReal });
  if (where) refuse('passfile_location', `the passfile is ${where}`);
  if (process.platform === 'win32') {
    const who = spawnSync(systemTool('whoami.exe'), [], { encoding: 'utf8', shell: false, windowsHide: true });
    const acl = spawnSync(systemTool('icacls.exe'), [real], { encoding: 'utf8', shell: false, windowsHide: true });
    if (who.status !== 0 || acl.status !== 0) refuse('passfile_permissions', 'the passfile ACL could not be read');
    const problem = aclProblem(aclPrincipals(acl.stdout, real), who.stdout.trim());
    if (problem) refuse('passfile_permissions', problem);
  } else {
    const problem = posixModeProblem(st, process.getuid());
    if (problem) refuse('passfile_permissions', problem);
  }
  const password = selectPassfileEntry(parsePassfile(readFileSync(real, 'utf8')), target);
  return { path: real, secret: password };
}

export function checkMigrations(workdir, { name = MIGRATION, digest = MIGRATION_SHA256 } = {}) {
  const dir = path.join(workdir, 'supabase', 'migrations');
  let files;
  try { files = readdirSync(dir); } catch { refuse('migration_missing', 'the workdir has no supabase/migrations folder'); }
  const sql = files.filter((f) => f.toLowerCase().endsWith('.sql')).sort();
  if (sql.some((f) => !/^[0-9]{14}_[a-z0-9_]+\.sql$/.test(f))) refuse('migration_name', 'a migration file does not follow <14 digits>_<name>.sql');
  if (!sql.includes(name)) refuse('migration_missing', 'the 001D migration file is missing');
  if (sql[sql.length - 1] !== name) refuse('migration_not_newest', 'the 001D migration is not the newest local migration');
  if (sql.filter((f) => f.startsWith(`${name.slice(0, 14)}_`)).length !== 1) refuse('migration_version_reused', 'another file uses the 001D version');
  if (sha256(readFileSync(path.join(dir, name))) !== digest) refuse('migration_hash', 'the 001D migration bytes differ from the reviewed SHA-256 (a CRLF copy fails here)');
  return { files: sql.length };
}

export function verifyCli(cliPath, { pins = CLI_BINARIES, platform = `${process.platform}-${process.arch}` } = {}) {
  const pinned = pins[platform];
  if (!pinned) refuse('cli_platform', `no pinned Supabase CLI binaries for ${platform}`);
  if (typeof cliPath !== 'string' || !path.isAbsolute(cliPath)) refuse('cli_missing', `${ENV_CLI} must be an absolute path`);
  if (path.basename(cliPath).toLowerCase() !== 'supabase.exe') refuse('cli_missing', `${ENV_CLI} must name supabase.exe`);
  for (const [file, digest] of Object.entries(pinned)) {
    let actual;
    try { actual = sha256File(path.join(path.dirname(cliPath), file)); } catch { refuse('cli_missing', `${file} is missing`); }
    if (actual !== digest) refuse('cli_hash', `${file} does not match its pinned SHA-256`);
  }
  return cliPath;
}

// The dry run's pending list; null when the output is not understood.
export function parsePending(text) {
  const lines = text.replace(/\r/g, '').split('\n');
  const start = lines.findIndex((l) => l.includes('Would push these migrations'));
  if (start < 0) return /database is up to date/i.test(text) ? [] : null;
  const names = [];
  for (const line of lines.slice(start + 1)) {
    const hit = line.match(/\b[0-9]{14}_[A-Za-z0-9_]+\.sql\b/g);
    if (hit) names.push(...hit);
  }
  return names;
}

// Shapes first (a URL is masked whole before any secret inside it is replaced), then every known secret value. Only
// the wrapper's own placeholder-only URL shape is printed with maskUrls off.
export function redact(text, secrets, { maskUrls = true } = {}) {
  let out = String(text);
  if (maskUrls) out = out.replace(/postgres(?:ql)?:\/\/[^\s'"]+/gi, '<db-url>');
  out = out
    .replace(/password\s*=\s*[^\s&'"]+/gi, 'password=<redacted>')
    .replace(/\bsbp_[A-Za-z0-9]{8,}/g, '<token>')
    .replace(/\bsb_(?:secret|publishable)_[A-Za-z0-9_-]{8,}/g, '<key>')
    .replace(/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}(?:\.[A-Za-z0-9_-]+)?/g, '<jwt>');
  for (const s of [...new Set(secrets.filter((v) => typeof v === 'string' && v.length > 0))].sort((a, b) => b.length - a.length)) {
    out = out.split(s).join('<redacted>');
  }
  return out;
}

// The only two database commands the wrapper ever runs.
export const dryRunArgs = (dbUrl, workdir) => ['db', 'push', '--dry-run', '--db-url', dbUrl, '--workdir', workdir];
export const pushArgs = (dbUrl, workdir) => ['db', 'push', '--db-url', dbUrl, '--workdir', workdir, '--yes'];

function runCli(cli, args, env) {
  return new Promise((resolve) => {
    const child = spawn(cli, args, { env, shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const chunks = [];
    child.stdout.on('data', (c) => chunks.push(c));
    child.stderr.on('data', (c) => chunks.push(c));
    child.on('error', () => resolve({ code: -1, out: '' }));
    child.on('close', (code) => resolve({ code, out: Buffer.concat(chunks).toString('utf8') }));
  });
}

// The CLI's advice that the failure rule forbids (repair the history, pull or reset, include out-of-order files, rerun
// with debug output) is never relayed.
const CLI_ADVICE = /migration repair|db pull|db reset|--include-all|--debug|try repairing|update local migrations|make sure your local git repo|rerun the command/i;

// The CLI's verdict lines, not the SQL it echoes: on failure the error lines (a statement text can run to dozens of
// lines and push the error out of a plain tail), on success the apply lines.
export function summarize(text, failed, n = 8) {
  const signal = failed
    ? (l) => /^\s*(ERROR|FATAL)\b/.test(l)
      || /SQLSTATE|^\s*At statement|canceling statement|failed to connect|authentication failed|refused TLS|connection refused/i.test(l)
      || /migration versions not found|inserted before the last migration/i.test(l)
    : (l) => /Applying migration|Finished|up to date/i.test(l);
  // A line the CLI flags as an error is always kept; the other lines that carry its advice are dropped.
  const all = text.replace(/\r/g, '').split('\n')
    .filter((l) => l.trim() && !/new version of supabase cli|recommend updating/i.test(l) && (signal(l) || !CLI_ADVICE.test(l)));
  const picked = all.filter(signal).slice(0, n);
  return (picked.length ? picked : all.slice(-n)).map((l) => `    ${l.trim().slice(0, 220)}`).join('\n');
}

export async function main(argv = process.argv.slice(2), env = process.env, print = (l) => process.stdout.write(`${l}\n`)) {
  // The one-time exact-gap mode (the section at the end of this file) is reached only through its own flag.
  if (Array.isArray(argv) && argv.includes(EXACT_GAP_FLAG)) return exactGapMain(argv, env, print);
  const secrets = [env[ENV_URL], env[ENV_PASSFILE]];
  const say = (line) => print(redact(line, secrets));
  try {
    const args = parseArgs(argv);
    refuseDebug(env);
    const target = parseTargetUrl(env[ENV_URL], args);
    if (args.mode === 'hosted') secrets.push(target.host, args.projectRef);
    const passfile = verifyPassfile(env[ENV_PASSFILE], target, args.workdir);
    secrets.push(passfile.secret, passfile.path, passfile.path.replace(/\\/g, '/'));
    const local = checkMigrations(args.workdir);
    const cli = verifyCli(env[ENV_CLI]);
    secrets.push(cli, path.dirname(cli), args.workdir, args.workdir.replace(/\\/g, '/'));
    const childEnv = buildChildEnv(env, passfile.path);
    const dbUrl = buildDbUrl(target);
    secrets.push(dbUrl);
    print(redact(`gr37: ${args.mode} mode; URL shape ${urlShape(args.mode)}; PGSSLMODE=require; password only from the owner-only passfile`, secrets, { maskUrls: false }));
    const version = await runCli(cli, ['--version'], childEnv);
    if (version.code !== 0 || version.out.replace(/\r/g, '').split('\n')[0].trim() !== CLI_VERSION) refuse('cli_version', `the CLI does not report ${CLI_VERSION}`);
    say(`gr37: Supabase CLI ${CLI_VERSION}; supabase.exe and supabase-go.exe match their pinned SHA-256`);
    say(`gr37: ${MIGRATION} matches its reviewed SHA-256 and is the newest of ${local.files} local migrations`);
    const dry = await runCli(cli, dryRunArgs(dbUrl, args.workdir), childEnv);
    if (dry.code !== 0) {
      say(`gr37: dry run failed (exit ${dry.code}); nothing was pushed\n${summarize(dry.out, true)}`);
      say('RESULT: DRY_RUN_FAILED (STOP: preserve the evidence; no retry, no repair, no --include-all)');
      return 3;
    }
    const pending = parsePending(dry.out);
    if (!pending || pending.length !== 1 || pending[0] !== MIGRATION) {
      refuse('pending_mismatch', `the dry run must list exactly ${MIGRATION}; it lists ${pending ? pending.length : 'an unreadable answer'}`);
    }
    say(`gr37: dry run lists exactly ${MIGRATION}`);
    if (!args.apply) {
      say('RESULT: CHECKED (no --apply: nothing was pushed)');
      return 0;
    }
    checkMigrations(args.workdir); // unchanged since the dry run
    const started = Date.now();
    const push = await runCli(cli, pushArgs(dbUrl, args.workdir), childEnv);
    const elapsed = Date.now() - started;
    say(`gr37: push (one attempt) exit ${push.code} after ${elapsed} ms\n${summarize(push.out, push.code !== 0)}`);
    const post = await runCli(cli, dryRunArgs(dbUrl, args.workdir), childEnv);
    const after = post.code === 0 ? parsePending(post.out) : null;
    say(`gr37: post-check dry run exit ${post.code}; pending ${after ? JSON.stringify(after) : 'unreadable'}`);
    if (push.code !== 0) {
      say('RESULT: PUSH_FAILED (STOP: preserve the evidence; forward-fix only; no retry, no repair, no --include-all)');
      return 3;
    }
    if (!after || after.length !== 0) {
      say('RESULT: POSTCHECK_MISMATCH (STOP: preserve the evidence; read the ledger read-only; no retry, no repair, no --include-all)');
      return 4;
    }
    say('RESULT: APPLIED');
    return 0;
  } catch (error) {
    if (error instanceof Refusal) {
      say(`REFUSED ${error.code}: ${error.message}`);
    } else {
      say('REFUSED internal_error: an unexpected error stopped the wrapper before any push');
    }
    return 2;
  }
}

// =====================================================================================================================
// One-time exact-gap mode: BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001 (DECISION D-066), re-pinned to main
// 0fe8ef80 by its REPIN-001 and, after #386, to main 28c41911 by POST-386-REPIN-001 (DECISION D-068).
// Hosted received #379's 20261104131256, then #380's 20261105025413 and 20261105025604, #382's 20261105141815 and
// #386's 20261108085442 through the official Supabase migration operation before 001D, so the frozen 20261104141959 now sorts before the hosted
// latest. The default route above refuses that (001D is not the newest local file, and the CLI's normal dry run asks for
// --include-all). This mode admits exactly that one gap and nothing else:
// - every value it checks is pinned below; the caller only selects the mode, with
//   `--exact-gap BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001`, and a caller's --include-all or repair is
//   refused;
// - the local folder must be exactly the pinned 189-file main set (names and bytes), ending with the pinned tail; the
//   workdir's other CLI inputs are pinned too: supabase/config.toml has main's bytes, no dotenv file other than
//   .env.example sits in the workdir or its supabase/ folder, and the workdir is not linked to a project;
// - a read-only session (default_transaction_read_only=on) must find exactly the pinned hosted shape: the PostgreSQL
//   runtime the access pins were derived on (server_version_num 170006) with TimeZone UTC, 188 versions, the one gap
//   20261104141959, no remote-only version, the five versions hosted received through the official operation each
//   holding its single stored statement with its pinned SHA-256, no 001D object, the seven functions 001D re-creates
//   still in their pinned pre-001D form (body, owner, the EXECUTE bits the file sets and their exact access: every
//   grantee, privilege, grant option and grantor), the #379 / #380 / #382 surfaces present, and #382's own surface (its
//   relation, functions and Storage policies) exactly as pinned from the sequential reference (each function's whole
//   definition, the relation's catalog line, the policies' expressions, owners and exact access), and (D-068) #386's own
//   surface (its 28 functions, four relations and twelve triggers) exactly as pinned from the sequential reference;
// - the CLI's --include-all is added internally, to a read-only dry run that must list exactly 001D (cross-checked
//   against the read-only version sets), and then to the one push, which runs only after the state is re-read unchanged
//   (its PostgreSQL runtime and TimeZone checked again) and the local folder is checked again;
// - POST, read-only: the ledger equals the local set (189 versions) with every earlier row unchanged and the 001D row as
//   pinned; a normal dry run (no --include-all) reports the database up to date; `migration list` shows no divergence
//   and the CLI gives no repair advice; the 001D manifest (derived from the migration bytes) matches, with the exact
//   access (every grantee, privilege, grant option and grantor) of every 001D function, table, column and the sequence
//   as pinned from the sequential reference; #382's surface, every policy on storage.objects and #386's surface are
//   identical to PRE;
//   and the catalog digests of every other function of the app and public schemas (identity, body, security definer,
//   config, volatility, language, owner, ACL), of every other relation there (kind, RLS, owner, ACL, columns,
//   constraints, policies, triggers, indexes) and of every default privilege are unchanged. Nothing else is compared:
//   not view definitions or options, other function attributes, other object classes, other schemas or table rows.
// Every session verifies the server certificate: PGSSLMODE=verify-full with the owner-private CA named by
// BIZBOT_GR37_SSLROOTCERT (hosted mode accepts only the pinned CA). The CLI's experimental pg-delta post-push step, which
// main's config.toml enables, is turned off for these child processes, so the push opens no further session. The password
// still comes only from the passfile, which here must hold exactly one active entry in total (the exact target), the URLs
// stay passwordless with the fixed startup settings, and there is one push attempt and no retry.
// D-067 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-HOSTED-PRE-COMPAT-001), after the read-only hosted check of
// 2026-11-06: six of the seven re-created functions are on hosted in an exact legacy CRLF form of their reviewed LF body
// (the pinned CLI recorded two October migrations from a CRLF checkout), and hosted's default privileges are not the local
// reference's. Therefore:
// - the state answer also gives each selected function's LF-normalized body SHA-256 (each CRLF pair replaced by one LF,
//   nothing else), its CR, LF and CRLF-pair counts and whether a lone CR exists; all of it is in the state fingerprint,
//   and the raw body SHA-256 stays;
// - PRE accepts a re-created function only in its exact canonical LF form or, for the six named in legacyCrlfBefore
//   only, in its exact reviewed legacy CRLF form (raw SHA-256, normalized SHA-256 and the three counts all pinned);
//   normalization alone never accepts a body, and any CR in any other selected function is refused;
// - POST accepts only the canonical LF form (the raw and the normalized SHA-256 both the POST pin, no CR);
// - the Default ACL digest the first PRE reads is this run's baseline: never compared with a local reference, it must be
//   read again, unchanged, by the second PRE (which both routes now run after their dry run) and by POST.
// =====================================================================================================================
export const EXACT_GAP_MODE = 'BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001';
export const EXACT_GAP_FLAG = '--exact-gap';
export const ENV_SSLROOTCERT = 'BIZBOT_GR37_SSLROOTCERT';
// The CA accepted for the hosted direct host: the owner-provided Supabase Root 2021 CA validated at the dark-apply resume
// of 2026-11-05 (its SHA-256 fingerprint). Local mode takes a disposable self-signed test CA instead, never this pin.
export const ACCEPTED_HOSTED_CA_SHA256 = '80:70:25:AD:50:D4:ED:21:9D:2C:9C:7D:29:9C:00:4F:82:4E:B0:0C:F7:F6:5A:FE:F6:07:D0:7B:72:E6:CA:FA';
// The read-only sessions: the same three fixed settings plus default_transaction_read_only=on.
export const READONLY_STARTUP_OPTIONS = `-c default_transaction_read_only=on ${STARTUP_OPTIONS}`;

const deepFreeze = (value) => {
  if (value && typeof value === 'object' && !Object.isFrozen(value)) {
    Object.values(value).forEach(deepFreeze);
    Object.freeze(value);
  }
  return value;
};

// Generated from the base main commit 28c41911 (189 migrations) by POST-386-REPIN-001's p3_gen_pins.mjs (REPIN-001's
// rp_gen_pins.mjs adapted; before it 0fe8ef80's 188 and ad8c3caf's 187); the unit tests re-derive the 001D, #382 and #386
// parts from the committed migration bytes.
// functions: [schema.name, SHA-256 of the dollar-quoted body (= prosrc), security definer, proconfig, volatility,
// language, EXECUTE group]; the groups are the file's own GRANT / REVOKE sets.
export const EXACT_GAP = deepFreeze({
  mode: EXACT_GAP_MODE,
  missingVersion: '20261104141959',
  missingFile: MIGRATION,
  missingSha256: MIGRATION_SHA256,
  missingName: 'bizbot_zcredit_001d_server_ledger',
  localCount: 189,
  remoteCountBefore: 188,
  localNamesSha256: '756219a502df025420b5a129887b9802b1cc410a0254b4e10a69634c45c5b78d',
  localBytesSha256: '0fae2d5a0a5a53e5cba1215c07fdf52faaca6940755cea1429056943d41f8358',
  // main's supabase/config.toml (the pinned CLI reads it during the push); the only dotenv files main itself ships.
  configSha256: '447beeba30b17a739beede822807a9f0b19590e9e31abd4605b0ffc06a9a6bd7',
  allowedDotenv: ['.env.example'],
  // REPIN-001: the PostgreSQL runtime the access pins below were derived on (17.6: a table owner also holds MAINTAIN),
  // and the session time zone hosted reports. PRE and the re-read before the push require both exactly; the pins are
  // never regenerated silently against another version.
  runtime: { serverVersionNum: '170006', timeZone: 'UTC' },
  // The 001D history row the pinned CLI records (its statement split of the pinned bytes): observed identically on the
  // sequential and the gap database of the local proof.
  missingRow: { n: 125, all: '49b5e0fc873a7d13cbeee14040868ad4162b5f0f5204c65eb6259b6da5147309' },
  localTail: [
    ['20261104131256_bizbot_storefront_cinematic_001b_appearance.sql', 'a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b'],
    [MIGRATION, MIGRATION_SHA256],
    ['20261105025413_bizbot_storefront_visual_parity_product_media.sql', 'a901a709970b4629b22357743831aab687c2882fe066776dd7913b82c29c77d5'],
    ['20261105025604_bizbot_storefront_visual_parity_scene.sql', '7bfac52a707b20fdf9b67a466d84290a7565fe574850ce1e992c093d5f19b520'],
    ['20261105141815_bizbot_storefront_background_clarity_001_api.sql', 'e5cf4b2840837facc5699cecb154689a7439383ac4d6650f13746d5e68bd8504'],
    ['20261108085442_bizbot_pos_long_shift_alerts_001.sql', '7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865'],
  ],
  remoteTail: ['20261104131256', '20261105025413', '20261105025604', '20261105141815', '20261108085442'],
  laterHosted: ['20261105025413', '20261105025604', '20261105141815', '20261108085442'],
  // version -> [stored name, SHA-256 of the ONE stored statement]: the official operation stores the whole file once.
  storedStatements: {
    '20261104131256': ['bizbot_storefront_cinematic_001b_appearance', 'a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b'],
    '20261105025413': ['bizbot_storefront_visual_parity_product_media', 'a901a709970b4629b22357743831aab687c2882fe066776dd7913b82c29c77d5'],
    '20261105025604': ['bizbot_storefront_visual_parity_scene', '7bfac52a707b20fdf9b67a466d84290a7565fe574850ce1e992c093d5f19b520'],
    '20261105141815': ['bizbot_storefront_background_clarity_001_api', 'e5cf4b2840837facc5699cecb154689a7439383ac4d6650f13746d5e68bd8504'],
    '20261108085442': ['bizbot_pos_long_shift_alerts_001', '7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865'],
  },
  owner: 'postgres',
  tables: ['app.card_payments_pilot_revisions', 'app.payment_terminals', 'app.card_provider_attempts', 'app.card_provider_private_events',
    'app.card_attempt_identity_tombstones'],
  sequence: 'app.card_payments_pilot_revisions_revision_seq',
  policy: { name: 'deny_client', cmd: '*', permissive: true, roles: ['authenticated'], using: 'false', check: 'false' },
  indexes: ['payment_terminals_one_current_per_device@payment_terminals', 'payment_terminals_one_admitting_per_org@payment_terminals',
    'payment_terminals_credential_ref_idx@payment_terminals', 'card_attempts_one_claim_per_order@card_provider_attempts',
    'card_attempts_order_idx@card_provider_attempts', 'card_attempts_shift_idx@card_provider_attempts',
    'card_attempts_branch_identity_idx@card_provider_attempts', 'card_attempts_retention_idx@card_provider_attempts',
    'card_events_one_test_recording_refusal@card_provider_private_events', 'card_events_one_field_drop@card_provider_private_events',
    'card_events_attempt_idx@card_provider_private_events', 'card_events_retention_idx@card_provider_private_events'],
  triggers: ['card_pilot_revisions_append_only@card_payments_pilot_revisions', 'card_pilot_revisions_no_truncate@card_payments_pilot_revisions',
    'card_tombstones_append_only@card_attempt_identity_tombstones', 'card_tombstones_no_truncate@card_attempt_identity_tombstones',
    'card_attempts_no_truncate@card_provider_attempts', 'card_events_no_truncate@card_provider_private_events',
    'payment_terminals_no_truncate@payment_terminals', 'payment_terminals_guard@payment_terminals',
    'card_attempts_insert_guard@card_provider_attempts', 'card_attempts_guard@card_provider_attempts',
    'card_events_guard@card_provider_private_events'],
  functions: [
    ['app.card_text_canonical', '90e07b766820403aa1f1b17a1a83a67155946adbeeef119791173504feec1a98', false, 'search_path=""', 'i', 'plpgsql', 'none'],
    ['app.card_text_absent', '40264bd537e2c366da1ad6bfa699fac73a825b2a72d0f17322a9f36e5c996286', false, 'search_path=""', 'i', 'sql', 'none'],
    ['app.card_safe_text_failure', '4ee6fa07d948441c91f1dc7a13d782fae7e275eb1e479ed1fe8b2b332fad9a4f', false, 'search_path=""', 'i', 'plpgsql', 'none'],
    ['app.card_safe_text_ok', '86dfc2c0500416e44083f4cc69a7b024040df9aa288c2e5450fe5da6cf952823', false, 'search_path=""', 'i', 'sql', 'none'],
    ['app.card_identity_digest', '4feb984c12dd6a63e2019c328109b7b0253d2a630681c95d6d77f316e85aa049', false, 'search_path=""', 'i', 'sql', 'none'],
    ['app.card_provider_key', 'ce5531e971ec1d329fd2127bf43da6b2d61c09023e38f2fd81ca5b46f8cc085a', false, 'search_path=""', 'i', 'sql', 'none'],
    ['app.card_event_detail_ok', '9afbcc7fd9e6aeeebd93db27a0348e4eecb5e1caccf225b4e165e63c7e1a6e95', false, 'search_path=""', 'i', 'sql', 'none'],
    ['app.card_identity_lock', 'cc949e1f9b32060abdaf25bff801d5d032f967b29bc170d79c4dc20422b5c84c', false, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_terminal_lock', '95eb4e3cb34f0d06b3ca84039b21f17dc21b3677a6615d6abb07c7137ee1f5b9', false, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_pilot_revision_current', '871fa0d0303026c924255024c9ad3c0a99ed71c73f286c6945065cd305abe435', true, 'search_path=""', 's', 'sql', 'none'],
    ['app.card_attested_approver_ok', '99218b370864c7d2b6dd9d2ace01da75cbc2fa8dd308207e753941a1dbf02ccd', true, 'search_path=""', 's', 'sql', 'none'],
    ['app.card_caller_binding_denial', '6019a5ba4b5f83c5afe0f7817fd85b921bec0fbe0d1098da61600990c7c90daa', true, 'search_path=""', 's', 'sql', 'none'],
    ['app.card_attempt_proof', '4ad8dad555b945981153a1ffb20d1b381bcaebebbd1a8a3b880da121802037da', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_attempt_payment_id', '73975ea6b5bd5e2ce28fb2c92ab6bb1834eee23e64395d511baf81b4568f79b6', true, 'search_path=""', 's', 'sql', 'none'],
    ['app.card_attempt_derive', 'c8d7c1d18e9d1f292d7606ef323abb282112c36c0e084e67fcb973313be99c0b', true, 'search_path=""', 's', 'plpgsql', 'none'],
    ['app.card_attempt_envelope', '88f3a92f3dbdf8b98f1cf611639f5c4cc22ef89648968eaf0b03c59b2dc7387a', true, 'search_path=""', 's', 'plpgsql', 'none'],
    ['app.card_order_claim_active', 'e09ebb63d0d8279dfaa54e0baf4bd950704212041db18a420e649a89b13ded64', true, 'search_path=""', 's', 'sql', 'none'],
    ['app.card_shift_close_blocked', '627ebe28cdf53b27efc2331d0666107ffee07e8fbe3085b41b791c1ad606bc42', true, 'search_path=""', 's', 'sql', 'none'],
    ['app.card_active_manager_denial', 'e49643cb648eb162f0ed720225d1603e865e4c82c2d6adc3c58532d3de9df8e3', true, 'search_path=""', 's', 'plpgsql', 'none'],
    ['app.card_dispatch_certain_deny', 'f993441a02c6918ab28d6565528165957b0d177c2d1de05e16c72345ebbc0f01', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_private_event_write', '56ae8322af85b7bb7d166ef6a7fd20326c3a9f64050e699e2e8a77c1fe43fc56', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_audit_write', '37961316667f2547e4e3a10d6179948378bf4da45796aea81d1dde9b6a85b497', true, 'search_path=""', 'v', 'sql', 'none'],
    ['app.card_denial_evidence', '5cdba2de2bec2d47a23897b182b79202dd5f1b5db18370b5bb35966cb6cb725e', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_attempt_resolve', 'ebea366880282d901495fa02bab43670380e92c264c3353460687b38fb173bbf', true, 'search_path=""', 's', 'plpgsql', 'none'],
    ['app.card_proof_denial_evidence', '0f698e850354dd9a0f5ed5d153ef43b1ab766d9f20812e15810e3f4ffd18cda2', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_config_mismatch', '672aafbd819e2e581727f8056e6ad15ddc37e1ffd91c878cdf5ef2c5a13875a5', false, 'search_path=""', 'i', 'plpgsql', 'none'],
    ['app.card_append_only_guard', '126852c47795514c8691f4c542eeea9898934701aadf64fb70f9ef0ef2359552', false, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.payment_terminals_guard', '5c8d87f055ed89f21bf72d18eaae61b9efd3c7f735f876fb2fbb0e3ea651a044', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_attempts_insert_guard', 'ea30131d7799845a2e7d64cb5c925277e51592125e7bd780df044286062970c7', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_attempts_guard', '2cfb8f39addb040fafa320e96d4c0c98814efe6116024c23c56ecc130bae905c', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_events_guard', '72c84ab6faef16dff3819af7a92024619fc96f94c99dffa410299ba06051a273', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_terminal_posture', 'b2363a9113c537798e8a40a080a41b5d129a12ea915bf1afff095fb0da6f8589', true, 'search_path=""', 's', 'plpgsql', 'none'],
    ['app.card_attempt_context', 'a6168f89f73105f470efc62efe364534727ec8a4443fd4806373c915044481f5', true, 'search_path=""', 'v', 'plpgsql', 'authenticated'],
    ['public.card_attempt_context', '9ea5f2a9e9a9c19a0b0659adbf5a724ab40c2d0e95f6ade9fbdaa7113f47a00f', false, 'search_path=""', 'v', 'sql', 'authenticated'],
    ['app.owner_card_attempts', '2293c008f330b6c0980199ef1979b8d2c1e654b4bc5988ccca5a603970bdb0de', true, 'search_path=""', 's', 'plpgsql', 'authenticated'],
    ['public.owner_card_attempts', '0d5c1ce4a26018899d4a0397ca9a80d7cac1bd31b0b542057e47758c9c840434', false, 'search_path=""', 's', 'sql', 'authenticated'],
    ['app.card_attempt_claim', '2d7751b50bf664e20ae2e2ef2df88626ed3a6e5f45285272474c7d9ac4767ff4', true, 'search_path=""', 'v', 'plpgsql', 'service_role'],
    ['public.card_attempt_claim', 'c22206e6f14f31aaa3ae47bbf1eb8c1458f78611c1dd1f564cc4acfe832d1cf1', false, 'search_path=""', 'v', 'sql', 'service_role'],
    ['app.card_attempt_adapter_read', '61ee79f9912e5dad79aede491934a7618286a8ade413b17af6156d5fcd4f0165', true, 'search_path=""', 'v', 'plpgsql', 'service_role'],
    ['public.card_attempt_adapter_read', 'eead8e7fb7471dac59b14582b3c29194d4b34a715c159f21c35a9cdf0ba8a835', false, 'search_path=""', 'v', 'sql', 'service_role'],
    ['app.card_attempt_finish', '2eb0a7e0dc33d2673b12a069bf99f9f6ceb5115853ad303f52854f3cfe5d4e32', true, 'search_path=""', 'v', 'plpgsql', 'service_role'],
    ['public.card_attempt_finish', 'c5580a39a2478b31deb4c10ca081ddfafebcbb75091aa851141ba00e61635c7e', false, 'search_path=""', 'v', 'sql', 'service_role'],
    ['app.card_attempt_mark_release_requested', '8285ba32580669643aa226bc50fdcbe763a6c88427af38c830c958b0eedab289', true, 'search_path=""', 'v', 'plpgsql', 'service_role'],
    ['public.card_attempt_mark_release_requested', 'fdd7c8f30fc400ab0d5775e5acb5bc67547d6c6be26b4c5e5203acb2fd887ea5', false, 'search_path=""', 'v', 'sql', 'service_role'],
    ['app.card_attempt_mark_recording_result', '8ec3a72b1faf1c2ae16d3c5d94c7ef05e8e953a034611076b4d2bc1f932d5ff5', true, 'search_path=""', 'v', 'plpgsql', 'service_role'],
    ['public.card_attempt_mark_recording_result', '455d8a7e69f23ceaa93bbdd49eb84895abd405028b28cda348ca57113e74b7ea', false, 'search_path=""', 'v', 'sql', 'service_role'],
    ['app.card_attempt_free_order', 'db5a825e64e74ec82a7ef2c39ff2ed3eda1730b17a5ab28f91cb0b21bd9ab7a8', true, 'search_path=""', 'v', 'plpgsql', 'service_role'],
    ['public.card_attempt_free_order', '1587a292cc6c823b155433fc95b775c12023f1f0a5a6cec54696041256b4bebf', false, 'search_path=""', 'v', 'sql', 'service_role'],
    ['app.card_claim_guard', '72596cc8de73505edaa1f323243ae4f59df1fb7e0f6a5210a1581f44fdba5ed2', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_recording_resume_guard', '2b796081b3ccde796877f9a4ba7037bad17ec43eaf989b8ac03f5aa7cab88dd5', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.set_card_payments_pilot', '1549dc56f11190bd96658e3dd2168c236e543c83719618ee87ce90249cdef658', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.set_payment_terminal', '631c221ffa24c8f0f9c6362d4c25567d022a4430f54de93637316ddc155488e7', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_attempt_resolve_orphan', 'fcefff673f83d436bfd2df2f0c73e9b2636b6d9ef042c69d92677745e0a04822', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.card_attempt_set_incident_hold', '3895f4a0756c74cf44e4cb3e2c3e981cfb71510d7498e00b4822e9c292e18210', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.purge_expired_test_card_attempts', '65f281919c637c168e0da1c9d041391d23c6373ebf7e45de866bde179a84ca71', true, 'search_path=""', 'v', 'plpgsql', 'none'],
    ['app.sync_push', 'cad1ebdc14c1f387590cc089e034a3235d855b49395654aa12bbed4850e2e2a4', true, 'search_path=""', 'v', 'plpgsql', 'recreated'],
    ['app.pin_session_capabilities', '7704e5fe3dc54faad06ff02850e1fa14d5339403b7ec7f53f9eb30c1eee3afef', true, 'search_path=""', 's', 'plpgsql', 'recreated'],
    ['app.pos_order_snapshots', 'a1d30d4ea128657c5e17a85bf6b8c62dd4f2425168595e0069a2aab4a56bbbde', true, 'search_path=""', 's', 'plpgsql', 'recreated'],
    ['app.audit_action_has_detail', '26052aa649502121486fc16b51d328ccc9cf2a6c7d0bb2b94c9545643af90b91', false, 'search_path=""', 'i', 'sql', 'recreated'],
    ['app.audit_safe_detail', '1b1cb0a53d5b1385a76fd4a6ba8f5b8b810d8e7df360116aad290cf7b3aca51f', false, 'search_path=""', 'i', 'plpgsql', 'recreated'],
    ['app.owner_audit_events', 'f3703e2245b993e95587bd7b0d0bc3b9a5dfe29cce6e8cee4cc7fdfd27258530', true, 'search_path=""', 's', 'plpgsql', 'recreated'],
    ['app.audit_category', 'c828cde607b247d4a7f8737006fcb6e33691750f173806d279da3490c29cc1a6', false, 'search_path=""', 'i', 'sql', 'recreated'],
  ],
  // The seven functions 001D re-creates, before it: the SHA-256 of their pre-001D body (the latest earlier migration's
  // definition), which PRE requires, so a drifted or partly pre-applied body refuses instead of being silently replaced.
  recreatedBefore: {
    'app.sync_push': '3567342245d0b61c509688c5706345b78015152e9f9f8c7843b5b7f6b70da9c5',
    'app.pin_session_capabilities': '7f0ba8c1ac58206eb6763363bda3ddd3ea81f75c89dfb622bf4259b6f813be1e',
    'app.pos_order_snapshots': 'ce10e252ead728320ae798ce62c61db85d3b088e0b6b6669273dda7b37d7d15b',
    'app.audit_action_has_detail': '9e3e215f8eb465058a6202e77d1789270e271eb7af4107bfe639f975040345f2',
    'app.audit_safe_detail': 'b571d902b1ea167848589e8a522233c1d41084599f0757b7707b07f6d2aa6c95',
    'app.owner_audit_events': '960474ccbc4e11af695d2ce642a6d06c0090f52d7fb103066e1e56bb9e650e21',
    'app.audit_category': '49e905af85b8363c355bb7a0262b5901bf1af5b63ff5a4893c3b6a08bc1b17b4',
  },
  // D-067 (HOSTED-PRE-COMPAT-001): the one other pre-001D form PRE accepts, for exactly these six of the seven: the exact
  // legacy CRLF form hosted holds (the reviewed LF body with every LF written as CRLF). canonical = recreatedBefore;
  // crlf = the SHA-256 of the raw CRLF body; lineBreaks = its CR, LF and CRLF-pair count alike. app.audit_category is
  // accepted in canonical LF only, and POST never accepts this form.
  legacyCrlfBefore: {
    'app.sync_push': {
      canonical: '3567342245d0b61c509688c5706345b78015152e9f9f8c7843b5b7f6b70da9c5',
      crlf: 'd5114f69ba235571eddba9b98e51d37c89cdd0ae0671cb51073cbfde1ae3d0c1', lineBreaks: 910,
    },
    'app.pin_session_capabilities': {
      canonical: '7f0ba8c1ac58206eb6763363bda3ddd3ea81f75c89dfb622bf4259b6f813be1e',
      crlf: 'acde331884996f4e570b14c29f72e3dca996c2cb5227434586c6176f43ff3693', lineBreaks: 120,
    },
    'app.pos_order_snapshots': {
      canonical: 'ce10e252ead728320ae798ce62c61db85d3b088e0b6b6669273dda7b37d7d15b',
      crlf: '3caa845700d7806c10d7f2057f04bc3398527f2f350d4844a48a3c7498d70d1b', lineBreaks: 281,
    },
    'app.audit_action_has_detail': {
      canonical: '9e3e215f8eb465058a6202e77d1789270e271eb7af4107bfe639f975040345f2',
      crlf: '5129aea0b695aa7bae4f894b21a05ef70d516244fb222f5c87d27b0f692582f8', lineBreaks: 49,
    },
    'app.audit_safe_detail': {
      canonical: 'b571d902b1ea167848589e8a522233c1d41084599f0757b7707b07f6d2aa6c95',
      crlf: '500a1888b885fa580d8f1c46f8832dc707dada7c1a1817dcec56654d93a151d1', lineBreaks: 130,
    },
    'app.owner_audit_events': {
      canonical: '960474ccbc4e11af695d2ce642a6d06c0090f52d7fb103066e1e56bb9e650e21',
      crlf: '86175d5422dd57c6974ff9bf509548c085e3c281df4773e8537d7cfe80397012', lineBreaks: 204,
    },
  },
  // The seven functions 001D re-creates keep their earlier ACL (CREATE OR REPLACE); the file sets only these bits. PRE
  // requires them to hold already (so the file's re-statement is a no-op) and POST requires all four bits unchanged.
  // Their exact entries are pinned in access.recreated below.
  recreated: {
    'app.sync_push': { anon: false, public: false, authenticated: true },
    'app.pin_session_capabilities': { anon: false, public: false, authenticated: true },
    'app.pos_order_snapshots': { anon: false, public: false, authenticated: true },
    'app.owner_audit_events': { anon: false, public: false, authenticated: true },
    'app.audit_action_has_detail': { anon: false, public: false },
    'app.audit_safe_detail': { anon: false, public: false },
    'app.audit_category': { public: false },
  },
  // CR-EG-02 (CORRECTIONS-001): the EXACT access of every selected object, as the state query normalizes it: the stored
  // ACL (a NULL ACL resolved to its documented default) exploded into [grantee, privilege, grantable, grantor] entries
  // (grantee PUBLIC for 0), sorted in byte order. Observed on the sequential reference database A of the local proof
  // (PostgreSQL 17, so a table owner also holds MAINTAIN): every function of an EXECUTE group, every table and the
  // sequence carry exactly these entries, and no column of the five tables carries a column grant. The seven re-created
  // functions carry their own entries, identical on A just before and just after 001D: PRE requires them before 001D,
  // POST after it. Any extra, missing or changed grantee, privilege, grant option or grantor is refused.
  access: {
    functions: {
      none: [['postgres', 'EXECUTE', false, 'postgres']],
      authenticated: [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      service_role: [['postgres', 'EXECUTE', false, 'postgres'], ['service_role', 'EXECUTE', false, 'postgres']],
    },
    recreated: {
      'app.sync_push': [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      'app.pin_session_capabilities': [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      'app.pos_order_snapshots': [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      'app.audit_action_has_detail': [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      'app.audit_safe_detail': [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      'app.owner_audit_events': [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      'app.audit_category': [['postgres', 'EXECUTE', false, 'postgres']],
    },
    table: [['postgres', 'DELETE', false, 'postgres'], ['postgres', 'INSERT', false, 'postgres'], ['postgres', 'MAINTAIN', false, 'postgres'],
      ['postgres', 'REFERENCES', false, 'postgres'], ['postgres', 'SELECT', false, 'postgres'], ['postgres', 'TRIGGER', false, 'postgres'],
      ['postgres', 'TRUNCATE', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres']],
    sequence: [['postgres', 'SELECT', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres'], ['postgres', 'USAGE', false, 'postgres']],
    // [column, grantee, privilege, grantable, grantor] per column grant: none on any of the five tables.
    columns: [],
  },
  // The #379 / #380 / #382 surfaces: every function and table the four later-hosted files create (present before and
  // unchanged after the apply).
  surfaceFunctions: ['app.can_access_storefront_background_object_v1', 'app.finalize_storefront_background_variant_v1',
    'app.finalize_storefront_media', 'app.finalize_storefront_product_media_v1', 'app.get_restaurant_storefront_content_v2',
    'app.get_restaurant_storefront_content_v3', 'app.get_storefront_background_source_v1', 'app.get_storefront_product_original_v1',
    'app.get_storefront_product_source_v1', 'app.list_storefront_content_media_v2', 'app.list_storefront_media',
    'app.register_storefront_product_derivative_v1', 'app.select_storefront_product_derivative_v1', 'app.set_restaurant_storefront_content_v1',
    'app.set_restaurant_storefront_profile', 'app.stage_storefront_background_variant_v1', 'app.stage_storefront_media',
    'app.stage_storefront_product_media_v1', 'app.storefront_background_authorize_v1', 'app.storefront_background_context_v1',
    'app.storefront_background_prefix_v1', 'app.storefront_background_result_v1', 'app.storefront_content_document_shape_v1',
    'app.storefront_content_media_in_use_v1', 'app.storefront_content_media_url_v1', 'app.storefront_content_read_v2',
    'app.storefront_content_repoint_media_v1', 'app.storefront_product_authorize_v1', 'app.storefront_product_candidate_snapshot_v1',
    'app.storefront_product_current_v1', 'app.storefront_product_images_v1', 'public.finalize_storefront_background_variant_v1',
    'public.finalize_storefront_product_media_v1', 'public.get_restaurant_storefront_content_v2', 'public.get_restaurant_storefront_content_v3',
    'public.get_storefront_background_source_v1', 'public.get_storefront_product_original_v1', 'public.get_storefront_product_source_v1',
    'public.list_storefront_content_media_v2', 'public.register_storefront_product_derivative_v1', 'public.select_storefront_product_derivative_v1',
    'public.stage_storefront_background_variant_v1', 'public.stage_storefront_product_media_v1', 'public.storefront_menu_v5',
    'public.storefront_menu_v6', 'public.storefront_menu_v7'],
  surfaceTables: ['app.storefront_background_variants', 'app.storefront_product_derivatives', 'app.storefront_product_selections'],
  // REPIN-001: #382's own surface (20261105141815_bizbot_storefront_background_clarity_001_api.sql), exactly as observed
  // on the current-main sequential reference database A (PostgreSQL 17.6), the same definitions the file's bytes give.
  // functions: [schema.name, identity arguments, SHA-256 of the dollar-quoted body (= prosrc), security definer,
  // proconfig, volatility, language, EXECUTE group, SHA-256 of pg_get_functiondef: the whole definition, with the
  // result type, every argument, strictness, cost, rows and parallel safety as well]; access: the exact entries of each
  // group (the file revokes all from public, anon, authenticated and service_role, then grants EXECUTE to
  // authenticated, or to anon and service_role). relation: its kind, RLS, owner, exact access, column grants and the
  // SHA-256 of its catalog line (the line the other-relation digest uses: kind, RLS, owner, ACL, columns, constraints,
  // policies, triggers, indexes; not its persistence, replica identity, storage options, rules or publication
  // membership). policies: its two Storage policies on storage.objects, with their command, roles and expressions as
  // PostgreSQL 17.6 renders them. PRE requires all of it before the apply; POST requires it, and every policy on
  // storage.objects, identical to PRE.
  surface382: {
    version: '20261105141815',
    functions: [
      ['app.can_access_storefront_background_object_v1', 'p_name text, p_insert boolean', 'bb8e99e4671177ab0cffc8417b5c9715d90cc05cb11c3f737636933dc7248160', true, 'search_path=""', 's', 'sql', 'authenticated',
        '9f61cf707de7f8e2404302727bf0da114374b134bc195e852542b4c5e7af669b'],
      ['app.finalize_storefront_background_variant_v1', 'p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_variant_id uuid', 'ac5d0d426220c5ab8c945d54f65943c3e2b2eaf33a5242563d9103ec95e27028', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        '6e5ec7b9123d2db9000aa0c7ec0ea66f0405bef1e13b07a2a7af6b18daa4a39a'],
      ['app.get_storefront_background_source_v1', 'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_base_media_id uuid', '0262f5cf0a650ecc79f1c00706b348b90fbcd36ef231c0601c592053251dbde3', true, 'search_path=""', 's', 'plpgsql', 'authenticated',
        '7d1112cba9710374b6219cd2c0d6000b7912906ad993f7144ee4f769d1d0ff86'],
      ['app.stage_storefront_background_variant_v1', 'p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_base_media_id uuid, p_source_snapshot jsonb, p_expected_base_hash text, p_content_hash text, p_width integer, p_height integer, p_bytes integer', 'bb6c1b82a313dbccde1258498b23148ccb7b95b7b6f76669d85689c38ed37b83', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        'e5ff2f2a0d3348888ad6ad27a4431ceac0d9d8489dfe034e83ecf1722aab287f'],
      ['app.storefront_background_authorize_v1', 'p_o uuid, p_r uuid', '614e53a8d98ec8bd35e221a48dd4ce59d5f6da046dd7b9850358bf3015fb79d8', false, 'search_path=""', 's', 'plpgsql', 'none',
        'ca11407818b09215b307eabf1a8abbef3dd57a00ecf76c92a22d0297affde886'],
      ['app.storefront_background_context_v1', 'p_o uuid, p_r uuid, p_b uuid, p_base uuid', '598d7181f936dfe2ecc08187476b023331acc83a1321f05bf570dd664a2f2b61', false, 'search_path=""', 's', 'sql', 'none',
        'eb0466313ba9893b12943291f9f74865b446e2a91d0cf0ddbba002bf500a7798'],
      ['app.storefront_background_prefix_v1', 'p_restaurant uuid', 'd0479b2a0f7f75444b06cee704e48664d52b6e10ab66e63a45395f204018b223', false, 'search_path=""', 'i', 'sql', 'none',
        '3b79de98ccbf6cf70e7f2c9f71e23a53df668f574b90f15b9cdfc3837b9e9fd6'],
      ['app.storefront_background_result_v1', 'v app.storefront_background_variants', '0e07803e486f7a414a72c38a6014c8fe2d2e963717b0cc6c32c356b754d85999', false, 'search_path=""', 's', 'sql', 'none',
        'd09333d10e10068bdcf15b03c6d88ceb0cb17e3e959fe5faf2ade5313d7de7b6'],
      ['public.finalize_storefront_background_variant_v1', 'p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_variant_id uuid', 'e6683312b958e4ec6d5f644657aa80cde32d5c900885f2953fb750416a5b8ffb', false, 'search_path=""', 'v', 'sql', 'authenticated',
        'f0358b1aa8cb1192c2bb049d294fea72d5420e401ee847c4edb7869577cab431'],
      ['public.get_storefront_background_source_v1', 'p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_base_media_id uuid', '6acdc5cb7a0fd956c8f6a5653d376c3c9b7845bed910ab7d1c30a4e06fecd042', false, 'search_path=""', 's', 'sql', 'authenticated',
        '6adf3b2ae9dbeaaca610f72268ba3bbe88f3c52d4066bbb83b9d549d7b682788'],
      ['public.stage_storefront_background_variant_v1', 'p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_base_media_id uuid, p_source_snapshot jsonb, p_expected_base_hash text, p_content_hash text, p_width integer, p_height integer, p_bytes integer', '6b929c7ca5bcc5b96ed41069666e12fb0c864bae929416a940ee25bdb1f76b94', false, 'search_path=""', 'v', 'sql', 'authenticated',
        'ecd8898ddea90c224c3be4b108b5ff14da85bed9dccddbda7a09d79fa78e143e'],
      ['public.storefront_menu_v7', 'p_slug text', '090aa1ace5afe57dd58050833a5d201170b57e6fd321aa4883b3c3570f2112fe', true, 'search_path=""', 's', 'plpgsql', 'anon_service_role',
        '93a3eaee504451467c92051c7ca368e2f5f200dd17544e6b97d63ad2ae872504'],
    ],
    access: {
      none: [['postgres', 'EXECUTE', false, 'postgres']],
      authenticated: [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      anon_service_role: [['anon', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres'], ['service_role', 'EXECUTE', false, 'postgres']],
    },
    relation: {
      name: 'app.storefront_background_variants', kind: 'r', rls: true, force_rls: false,
      access: [['postgres', 'DELETE', false, 'postgres'], ['postgres', 'INSERT', false, 'postgres'], ['postgres', 'MAINTAIN', false, 'postgres'],
        ['postgres', 'REFERENCES', false, 'postgres'], ['postgres', 'SELECT', false, 'postgres'], ['postgres', 'TRIGGER', false, 'postgres'],
        ['postgres', 'TRUNCATE', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres']],
      columns: [],
      definition: 'd37cc990030e183fe29a4b5822faf3915b5ffcf399f40eb415a5c9829719100b',
    },
    policies: [
      { table: 'storage.objects', name: 'storefront_background_registered_insert_v1', cmd: 'a', permissive: true, roles: ['authenticated'], using: null,
        check: "((bucket_id = 'storefront-media'::text) AND app.can_access_storefront_background_object_v1(name, true))" },
      { table: 'storage.objects', name: 'storefront_background_registered_select_v1', cmd: 'r', permissive: true, roles: ['authenticated'],
        using: "((bucket_id = 'storefront-media'::text) AND app.can_access_storefront_background_object_v1(name, false))", check: null },
    ],
  },
  // D-068 (POST-386-REPIN-001): #386's own surface (20261108085442_bizbot_pos_long_shift_alerts_001.sql), exactly as observed on
  // the current-main sequential reference database A (PostgreSQL 17.6), the same definitions the file's bytes give. functions: as
  // surface382 ([schema.name, identity arguments, SHA-256 of the dollar-quoted body (= prosrc), security definer, proconfig,
  // volatility, language, EXECUTE group, SHA-256 of pg_get_functiondef]); the groups are the file's own GRANT / REVOKE sets
  // ('none': the owner only; 'inherited': the one CREATE OR REPLACE the file neither grants nor revokes keeps its earlier access,
  // pinned per function in inheritedAccess). The five *_core functions are the file's renames of the earlier functions: a rename
  // keeps the body, and the file revokes them from every client role; four bodies are the latest static definitions in the
  // earlier files, and app.pos_register_order_alert_core's also carries the in-database patches of 20261027011255 and
  // 20261027142721. relations: the three tables the file creates and the one it alters (kind, RLS, forced RLS, owner, policies,
  // exact access, column grants and the SHA-256 of the catalog line the other-relation digest uses). triggers: [name@schema.table,
  // SHA-256 of pg_get_triggerdef], each required enabled. PRE requires all of it; POST requires it, byte for byte, identical to PRE.
  surface386: {
    version: '20261108085442',
    functions: [
      ['app.approve_pos_shift_alert_end', 'p_shift_id uuid, p_policy_revision uuid, p_approved_until timestamp with time zone', 'b8c6351593c9430f3fba27280b8395f71c374807cb42cf6fd36c2ef01b1e24df', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        'bb9a5a887032cc8128f6f0a1f6263ee515940a3ae9f64210b851f02b4801f40b'],
      ['app.end_pos_shift_alert_bindings', '', '36a2c9343895045c9e750f184ecef09306961e37f23b9b3dcb3229dc50b59e73', true, 'search_path=""', 'v', 'plpgsql', 'none',
        '058b4ca03ce335764857e3695f87fea733689fbdcd99eabadab4be24e188e20b'],
      ['app.pos_claim_order_alert_deliveries', 'p_limit integer', '31374c4731041a09792068cb9ec63619c9d72594d688e68e0834c0db892bfa92', true, 'search_path=""', 'v', 'plpgsql', 'service_role',
        '318b3272e5fc7ec1a6893c901aaa012695b676918fa08b61482b83028bf08e1e'],
      ['app.pos_claim_order_alert_deliveries_core', 'p_limit integer', '064444341ea9f6e4d9aad0451a0911a539c77b3191a4aa85d9d7d42a07aefa29', true, 'search_path=""', 'v', 'plpgsql', 'none',
        '8c98b99c87bcee2e6c47f96d3938d6893ca32e182367239234d3bc0c9a535afa'],
      ['app.pos_disable_order_alert', 'p_installation_id uuid, p_status_secret_hash text', 'f6f9acc79bf2c894790b528452a6abd3e17d2563a5a62016b47ed1ef1f0d1927', true, 'search_path=""', 'v', 'plpgsql', 'service_role',
        '6f537c08c64efbd34639b1c9d874f58a00a82618dfe3dd99088bc489732e016a'],
      ['app.pos_disable_order_alert_core', 'p_installation_id uuid, p_status_secret_hash text', '5bdb2d754351a0390893967e7fbd58a58e98c4317e551c669f71eb32d1fe7f76', true, 'search_path=""', 'v', 'plpgsql', 'none',
        'e7eb08d17f2a916bf6414331b562292b6a08288e8f5048edde882e74e494ecbe'],
      ['app.pos_order_alert_authority', 'p_registration app.pos_order_alert_registrations', '698fa45e86ba7a8bdc7cccf9cf23bbccd5b2feefac4e6aab9ff0123fd996a2fa', true, 'search_path=""', 's', 'sql', 'inherited',
        '462c38c566a63a51cbf532c07f26987e2320d02553f0b724f320ab13488aeb0f'],
      ['app.pos_order_alert_status', 'p_installation_id uuid, p_status_secret_hash text', 'baad78917b21a37437720ece786b8178ae2dac1283b39389a0aba2ecacebd980', true, 'search_path=""', 's', 'sql', 'service_role',
        'aa916efb43b4e8dab3076818ba2591543dd0523ca8d22619db187c34691ac283'],
      ['app.pos_order_alert_status_core', 'p_installation_id uuid, p_status_secret_hash text', '678b3ebb7eacd88c231b7c4fc9f0976b8b96b83830978272a5980de04b36806d', true, 'search_path=""', 's', 'plpgsql', 'none',
        '29f43dfe3219fc4699bca6c03f0993b22e4bd046e5f763ca4ea8796ffa0bd217'],
      ['app.pos_preview_shift_order_alert', 'p_installation_id uuid, p_device_id uuid, p_pin_session_id uuid, p_device_session_token text, p_consent_id uuid, p_revoke_hash text', '17a85888dc0fece1151333394a0afee011482764c245ca1ff44751de3b01a461', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        'fb806f6d636478ea4f57c82f6d706ea16b13649fda6c2d098a7b41fa157865b4'],
      ['app.pos_refresh_order_alert_token', 'p_installation_id uuid, p_status_secret_hash text, p_fcm_token text, p_expected_generation uuid', 'e0e105ed4fa378779782749d3bf62429b4119dd233ecfc467ae03ab0f0e2caf9', true, 'search_path=""', 'v', 'plpgsql', 'service_role',
        'a331fb8748206baebb567bebf37973035793c15bfe333bbf08097014423862d6'],
      ['app.pos_refresh_order_alert_token_core', 'p_installation_id uuid, p_status_secret_hash text, p_fcm_token text, p_expected_generation uuid', '3a125cd7df3c4826af45f533a2284ac81f9438e56566e150b87e37b2ff76183d', true, 'search_path=""', 'v', 'plpgsql', 'none',
        'a8f0c0ddf615f88b5711b6eeeac5a761790d62dd26e4cf9888380a438aa31167'],
      ['app.pos_refresh_shift_order_alert_token', 'p_installation_id uuid, p_consent_id uuid, p_status_secret_hash text, p_fcm_token text, p_expected_generation uuid', 'a4b02051390d1364b7eee0163b40faaabda6610a442e61dac020690581390465', true, 'search_path=""', 'v', 'plpgsql', 'service_role',
        '165d24c573cc6a82f8753f7127acf8c7a6be4dc3aa8bbf30c997c0fd55016946'],
      ['app.pos_register_order_alert', 'p_installation_id uuid, p_fcm_token text, p_status_secret text, p_device_id uuid, p_pin_session_id uuid, p_device_session_token text', '9875377b9777bf89249b18620683238580f0abf099de47a6b5ae1fb6324735b6', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        '72578d436ca210e5486e23548394d761f0588d376dc1b6bca0fa4262fa568eaa'],
      ['app.pos_register_order_alert_core', 'p_installation_id uuid, p_fcm_token text, p_status_secret text, p_device_id uuid, p_pin_session_id uuid, p_device_session_token text', 'bb4be534418b864bb183aafb190ff35ecabdd8bc23454e1d0c1ebcd2c87b39a1', true, 'search_path=""', 'v', 'plpgsql', 'none',
        '08d663e94bd6bf11e4d1d733c4370bd2568feb5929f5f9044812a3894be8067a'],
      ['app.pos_register_shift_order_alert', 'p_installation_id uuid, p_device_id uuid, p_pin_session_id uuid, p_device_session_token text, p_consent_id uuid, p_shift_id uuid, p_policy_revision uuid, p_expected_deadline timestamp with time zone, p_status_secret text, p_fcm_token text, p_consent jsonb', '2cb6dd95bb22c24cb605c9934fb3ae068c90e5c8a4735b25f01d9a2fefff3a7e', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        '8fc7f8a8942520f2db20ec3c17f17527d7616f6fa0a05c8b11bdb7e81a7f96d4'],
      ['app.pos_revoke_shift_order_alert', 'p_installation_id uuid, p_consent_id uuid, p_revoke_hash text', 'a9796d4a732163aa48daebf8a4d64faf5301431992a297379c089a1c8d6d77d3', true, 'search_path=""', 'v', 'plpgsql', 'service_role',
        'b6eb5763e13f69f405c60bb1602ccbb5e157e5b06fab2f99667fc1958a0de3e8'],
      ['app.pos_shift_alert_human', 'p_pin uuid, p_device uuid, p_token text', '49d1924bd5340ed36b998af1a345830be60726ed75d127584e527e60e7eab186', true, 'search_path=""', 'v', 'plpgsql', 'none',
        'e52ea8a4aeba7312c711489ff1424d54584a28723bb09bff705d167fbe202709'],
      ['app.pos_shift_alert_owner', 'p_branch uuid', '8376a538982f8d6b7bd2510a8c67c4c04762328913174b190a8cd510cc2282ed', true, 'search_path=""', 'v', 'plpgsql', 'none',
        'e2ab961f2fc7fd4eb832fc882d8d3cdf67b3066704d28cadeafdef4291cf725a'],
      ['app.pos_shift_order_alert_status', 'p_installation_id uuid, p_consent_id uuid, p_status_secret_hash text', '900d6342877eecafc8ac5650a4db6731eb84f27103e39eb134ad6e26afe8bd82', true, 'search_path=""', 's', 'plpgsql', 'service_role',
        'c20db322a21e8d3a9329ab9ca25444c20ece574b3b97bbc4a2ec20ab92e9afee'],
      ['app.set_pos_shift_alert_policy', 'p_branch_id uuid, p_expected_revision uuid, p_enabled jsonb, p_cap_minutes integer', 'ce6fb91c4942b3d9d8d7670b03192a04cc45d8fabef3b72e49cf7420c921586a', true, 'search_path=""', 'v', 'plpgsql', 'authenticated',
        '59ee769e015f1a2c3dd9daf184dba7b584f6cfd615d12f57716880adfabe06cf'],
      ['public.approve_pos_shift_alert_end', 'p_shift_id uuid, p_policy_revision uuid, p_approved_until timestamp with time zone', '3ed5bc800174dd227ffc4d3c6f684e31e6fff6a17e2199115b5f3ef0180e64e2', false, 'search_path=""', 'v', 'sql', 'authenticated',
        '6e7f8e5cab22b107142cf0acfc963fb9e77a80ba86500cfad43a17de485cc982'],
      ['public.pos_preview_shift_order_alert', 'p_installation_id uuid, p_device_id uuid, p_pin_session_id uuid, p_device_session_token text, p_consent_id uuid, p_revoke_hash text', '5970b27fbd733497cc9827ec671efbc9392ff9c0e8aee910d232e0138407182f', false, 'search_path=""', 'v', 'sql', 'authenticated',
        'e00e7f1e645dfcd49be4054c5564303fabb93688d9eefccfa6f9d737f833bb47'],
      ['public.pos_refresh_shift_order_alert_token', 'p_installation_id uuid, p_consent_id uuid, p_status_secret_hash text, p_fcm_token text, p_expected_generation uuid', '14ed4dee7d7306160eb8dc0a0627407e0053ff3ef999aa7ef2a3c46935ee9463', false, 'search_path=""', 'v', 'sql', 'service_role',
        '9ca2f750b06e60bc894559872044dd2378f34c1f633780f0c4abb7d3c5d68f51'],
      ['public.pos_register_shift_order_alert', 'p_installation_id uuid, p_device_id uuid, p_pin_session_id uuid, p_device_session_token text, p_consent_id uuid, p_shift_id uuid, p_policy_revision uuid, p_expected_deadline timestamp with time zone, p_status_secret text, p_fcm_token text, p_consent jsonb', '58b9d6a9b80304b3c53fa12b7f46175880d0c8e65bf3ff6adb8fa2cab6e3e1f8', false, 'search_path=""', 'v', 'sql', 'authenticated',
        'b74372d2341655475f9bfb96ccf6aaf8711e36485e941168e00c5891c4ac49d1'],
      ['public.pos_revoke_shift_order_alert', 'p_installation_id uuid, p_consent_id uuid, p_revoke_hash text', 'f5e4f52e64e9fcfec13041ed0c810392f52d1334df5f98b457e37848147882b0', false, 'search_path=""', 'v', 'sql', 'service_role',
        '1a396bb7dd0f33d86c199832205ee2ce8c195b15150eac2a9de28b7b8147245d'],
      ['public.pos_shift_order_alert_status', 'p_installation_id uuid, p_consent_id uuid, p_status_secret_hash text', '6f65af600b8994cad4af5dc84e8b44b9e426edd4ba21ddcd78d3ae44a314ee61', false, 'search_path=""', 's', 'sql', 'service_role',
        'da670530522e54e94fd2b66d28dfabe17b0b472e26c0b01d8b0edf9f15f549ab'],
      ['public.set_pos_shift_alert_policy', 'p_branch_id uuid, p_expected_revision uuid, p_enabled jsonb, p_cap_minutes integer', 'd237a56e236a50bc059d57ff221221bfc422900d0b394744c34775c20aba7d71', false, 'search_path=""', 'v', 'sql', 'authenticated',
        'eb50774e3fb29d747ec122809f303744b3e52e91cf739aa9c73ae20b0e037a13'],
    ],
    access: {
      none: [['postgres', 'EXECUTE', false, 'postgres']],
      authenticated: [['authenticated', 'EXECUTE', false, 'postgres'], ['postgres', 'EXECUTE', false, 'postgres']],
      service_role: [['postgres', 'EXECUTE', false, 'postgres'], ['service_role', 'EXECUTE', false, 'postgres']],
    },
    inheritedAccess: {
      'app.pos_order_alert_authority': [['postgres', 'EXECUTE', false, 'postgres']],
    },
    relations: [
      { name: 'app.pos_order_alert_registrations', kind: 'r', rls: true, force_rls: true, policies: [{ name: 'deny_client', cmd: '*', permissive: true, roles: ['authenticated'], using: 'false', check: 'false' }],
        access: [['postgres', 'DELETE', false, 'postgres'], ['postgres', 'INSERT', false, 'postgres'], ['postgres', 'MAINTAIN', false, 'postgres'], ['postgres', 'REFERENCES', false, 'postgres'], ['postgres', 'SELECT', false, 'postgres'], ['postgres', 'TRIGGER', false, 'postgres'], ['postgres', 'TRUNCATE', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres']],
        columns: [], definition: 'e31be14384c9740c458449709ae92199dfe094c841e246905a57540909eaf8a2' },
      { name: 'app.pos_shift_alert_approvals', kind: 'r', rls: true, force_rls: true, policies: [],
        access: [['postgres', 'DELETE', false, 'postgres'], ['postgres', 'INSERT', false, 'postgres'], ['postgres', 'MAINTAIN', false, 'postgres'], ['postgres', 'REFERENCES', false, 'postgres'], ['postgres', 'SELECT', false, 'postgres'], ['postgres', 'TRIGGER', false, 'postgres'], ['postgres', 'TRUNCATE', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres']],
        columns: [], definition: 'aecdeeceb1b182cd7475595a40b5d0ec7a81d9953d674ae1276c4d719d1fb626' },
      { name: 'app.pos_shift_alert_consents', kind: 'r', rls: true, force_rls: true, policies: [],
        access: [['postgres', 'DELETE', false, 'postgres'], ['postgres', 'INSERT', false, 'postgres'], ['postgres', 'MAINTAIN', false, 'postgres'], ['postgres', 'REFERENCES', false, 'postgres'], ['postgres', 'SELECT', false, 'postgres'], ['postgres', 'TRIGGER', false, 'postgres'], ['postgres', 'TRUNCATE', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres']],
        columns: [], definition: '520545f61fae81c90ff363645f2a1a96cfe682543d9864933c926fefd8e962ed' },
      { name: 'app.pos_shift_alert_policies', kind: 'r', rls: true, force_rls: true, policies: [],
        access: [['postgres', 'DELETE', false, 'postgres'], ['postgres', 'INSERT', false, 'postgres'], ['postgres', 'MAINTAIN', false, 'postgres'], ['postgres', 'REFERENCES', false, 'postgres'], ['postgres', 'SELECT', false, 'postgres'], ['postgres', 'TRIGGER', false, 'postgres'], ['postgres', 'TRUNCATE', false, 'postgres'], ['postgres', 'UPDATE', false, 'postgres']],
        columns: [], definition: 'd02586267603b2c1678e28e23c92c1afd7bd518abda6b18e1d2b2e0eefa5ec29' },
    ],
    triggers: [
      ['end_shift_alert_on_branch@public.branches', '66ce7c745e9c8cd01b5ef02ccff07793710d31b859585241b5978b0ae9940b89'],
      ['end_shift_alert_on_device@public.devices', '1638aab312343dbf9b3f46c8cfacee64be066c334a36f801b7e9cf4a0b0c764b'],
      ['end_shift_alert_on_employee@public.employee_profiles', '819704d446a514c74b5ee54b9c2ab765a28a66d4b7db1a048cd60140e9a31308'],
      ['end_shift_alert_on_online_policy@app.online_order_settings', '3c6ef5dfb14adb67a55e41aa3d8b3f32748b15057e452ca97514531e3eb436d2'],
      ['end_shift_alert_on_organization@public.organizations', '809f82465e51cee0e7125ffc1e56efbec20f3a35cfa0fe7433de28cbf355ac55'],
      ['end_shift_alert_on_pairing@public.device_pairings', 'dd586cc3b84dcdc6f5a4e556b7956f0ee94d021b19c7182caf3218571127e63d'],
      ['end_shift_alert_on_person@public.app_users', '7b1ef516c7e6941a8ceb85862cdb3242a63d160256012d39682e680549c1ea8e'],
      ['end_shift_alert_on_pin@public.pin_sessions', '7b5f473aad9ccf268d0bcaa05f6121b729bf598e32f72113c024c5fddf2215fc'],
      ['end_shift_alert_on_restaurant@public.restaurants', 'a201e9d873af50da863c84280330cdd327552f7c79640c0bce0d6b74a880cfe9'],
      ['end_shift_alert_on_role@public.memberships', '29552a5b195e618d74ae5c39a18442811916696692144349c635a8df434073ba'],
      ['end_shift_alert_on_session@public.device_sessions', '8cc5134ca51cff54f5f8006e63538ce7cd9afe170101fa5107a0a502a596ef2f'],
      ['end_shift_alert_on_shift@public.shifts', 'a8af540470790c0e2d693314e8561c3b64b704eb5e4f4d3aced1761accbc0e45'],
    ],
  },
});

export const buildReadOnlyDbUrl = ({ user, host, port, database }) =>
  `postgresql://${user}@${host}:${port}/${database}?options=${encodeURIComponent(READONLY_STARTUP_OPTIONS)}`;

export const readOnlyUrlShape = (mode) =>
  `postgresql://<user>@${mode === 'hosted' ? '<direct-host>:5432' : '<loopback>:<port>'}/<database>?options=${encodeURIComponent(READONLY_STARTUP_OPTIONS)}`;

// The default allowlist, then verify-full with the owner-private CA (the default route's child keeps PGSSLMODE=require).
// The pinned CLI's experimental pg-delta step (enabled by main's config.toml) runs after a real push: it writes the CLI's
// own CA bundle into the workdir, starts an edge-runtime container for a catalog export and opens a further session. It
// is turned off here, for this mode's children only (proven locally: the push then opens exactly one read-write session
// and writes no pg-delta file).
export function buildExactGapChildEnv(parent, passfile, ca) {
  return { ...buildChildEnv(parent, passfile), PGSSLMODE: 'verify-full', PGSSLROOTCERT: ca, SUPABASE_EXPERIMENTAL_PGDELTA_ENABLED: 'false' };
}

// The only CLI commands this mode runs; --include-all appears in exactly the two db push commands. `--agent no` pins the
// CLI's output format (2.107.0 wraps `db query` answers in an envelope when it detects an agent environment); the POST
// normal dry run is the default route's dryRunArgs plus that flag (dryRunArgs itself is unchanged).
const NOT_AN_AGENT = ['--agent', 'no'];
export const exactGapNormalDryRunArgs = (dbUrl, workdir) => [...dryRunArgs(dbUrl, workdir), ...NOT_AN_AGENT];
export const exactGapDryRunArgs = (dbUrl, workdir) => ['db', 'push', '--include-all', '--dry-run', '--db-url', dbUrl, '--workdir', workdir, ...NOT_AN_AGENT];
export const exactGapPushArgs = (dbUrl, workdir) => ['db', 'push', '--include-all', '--db-url', dbUrl, '--workdir', workdir, '--yes', ...NOT_AN_AGENT];
export const migrationListArgs = (dbUrl, workdir) => ['migration', 'list', '--db-url', dbUrl, '--workdir', workdir, ...NOT_AN_AGENT];
export const stateQueryArgs = (dbUrl, file, workdir) => ['db', 'query', '--db-url', dbUrl, '--file', file, '--output', 'json', '--workdir', workdir, ...NOT_AN_AGENT];
// The pinned CLI treats a URL whose host and port equal the workdir's own local stack as "the local database" and then
// ignores PGSSLMODE (no TLS). Hosted never matches; a local rehearsal must use a workdir whose config.toml names another
// port. Either way this mode refuses to go on when the CLI says it connected locally.
export const connectedLocally = (text) => /Connecting to local database/i.test(String(text ?? ''));

const INCLUDE_ALL_TOKEN = /^-{0,2}include[-_]?all(?:=|$)/i;
const REPAIR_TOKEN = /^-{0,2}(?:migration[-_]?)?repair(?:=|$)/i;

// The mode flag and its one value, then the default argument rules for everything else. A caller's own
// --include-all or repair request is refused by name; the value after the flag is never echoed.
export function parseExactGapArgs(argv) {
  if (!Array.isArray(argv)) refuse('bad_arguments', 'no arguments');
  if (argv.some((a) => /^--(debug|log-level)\b/i.test(a))) refuse('debug_refused', 'debug output is not allowed');
  if (argv.some((a) => INCLUDE_ALL_TOKEN.test(a))) {
    refuse('include_all_refused', 'a caller may not request --include-all: the exact-gap mode adds it itself, to its read-only dry run and, after every gate, to its one push');
  }
  if (argv.some((a) => REPAIR_TOKEN.test(a))) refuse('repair_refused', 'migration repair is never run');
  const at = argv.indexOf(EXACT_GAP_FLAG);
  if (at < 0 || argv.lastIndexOf(EXACT_GAP_FLAG) !== at) refuse('bad_arguments', `exactly one ${EXACT_GAP_FLAG} is required`);
  if (argv[at + 1] !== EXACT_GAP_MODE) refuse('exact_gap_mode_unknown', `${EXACT_GAP_FLAG} accepts only its one Work ID`);
  return { ...parseArgs([...argv.slice(0, at), ...argv.slice(at + 2)]), exactGap: EXACT_GAP_MODE };
}

// The whole local folder: exactly the pinned 189-file main set (names and bytes), ending with the pinned tail.
export function checkExactGapMigrations(workdir, pins = EXACT_GAP) {
  const dir = path.join(workdir, 'supabase', 'migrations');
  let files;
  try { files = readdirSync(dir); } catch { refuse('migration_missing', 'the workdir has no supabase/migrations folder'); }
  const names = files.filter((f) => f.toLowerCase().endsWith('.sql')).sort();
  if (names.some((f) => !/^[0-9]{14}_[a-z0-9_]+\.sql$/.test(f))) refuse('migration_name', 'a migration file does not follow <14 digits>_<name>.sql');
  const versions = names.map((f) => f.slice(0, 14));
  if (new Set(versions).size !== versions.length) refuse('migration_version_reused', 'two local migration files share a version');
  if (names.length !== pins.localCount) refuse('local_count', `the workdir must hold exactly ${pins.localCount} migrations; it holds ${names.length}`);
  const tail = names.slice(-pins.localTail.length);
  if (tail.join('\n') !== pins.localTail.map(([n]) => n).join('\n')) {
    refuse('local_tail', `the newest local migrations must be ${pins.localTail.map(([n]) => n.slice(0, 14)).join(', ')}`);
  }
  const digests = new Map(names.map((n) => [n, sha256(readFileSync(path.join(dir, n)))]));
  for (const [n, digest] of pins.localTail) {
    if (digests.get(n) !== digest) refuse('migration_hash', `${n} differs from its reviewed SHA-256 (a CRLF copy fails here)`);
  }
  if (sha256(Buffer.from(names.join('\n'), 'utf8')) !== pins.localNamesSha256) refuse('local_names', 'the local migration names are not the pinned main set');
  if (sha256(Buffer.from(names.map((n) => `${n} ${digests.get(n)}`).join('\n'), 'utf8')) !== pins.localBytesSha256) {
    refuse('local_bytes', 'a local migration\'s bytes differ from the pinned main set (a CRLF checkout fails here)');
  }
  // The workdir's other inputs to the pinned CLI: main's config.toml; no dotenv file it would load (one can carry
  // PGSERVICE*, which outranks PGSSLMODE); no linked project.
  let config;
  try { config = readFileSync(path.join(workdir, 'supabase', 'config.toml')); } catch { refuse('local_config', 'the workdir has no supabase/config.toml'); }
  if (sha256(config) !== pins.configSha256) refuse('local_config', 'supabase/config.toml differs from main\'s (a CRLF checkout fails here)');
  for (const folder of [workdir, path.join(workdir, 'supabase')]) {
    let entries = [];
    try { entries = readdirSync(folder); } catch { entries = []; }
    if (entries.some((f) => /^\.env(?:\.|$)/i.test(f) && !pins.allowedDotenv.includes(f))) {
      refuse('local_dotenv', 'a dotenv file the CLI would load sits in the workdir or its supabase/ folder (only .env.example is allowed)');
    }
  }
  const present = (p) => { try { statSync(p); return true; } catch { return false; } };
  if (['project-ref', 'pooler-url'].some((f) => present(path.join(workdir, 'supabase', '.temp', f)))) {
    refuse('local_linked', 'the workdir is linked to a project (supabase/.temp holds a project reference)');
  }
  return { files: names.length, names, versions };
}

function ownerOnlyProblem(real, st) {
  if (process.platform === 'win32') {
    const who = spawnSync(systemTool('whoami.exe'), [], { encoding: 'utf8', shell: false, windowsHide: true });
    const acl = spawnSync(systemTool('icacls.exe'), [real], { encoding: 'utf8', shell: false, windowsHide: true });
    if (who.status !== 0 || acl.status !== 0) return 'the ACL could not be read';
    return aclProblem(aclPrincipals(acl.stdout, real), who.stdout.trim());
  }
  return (st.mode & 0o777) === 0o600 && st.uid === process.getuid() ? null : 'the file must be mode 0600 and owned by the current user';
}

// Exactly one PEM certificate, no private key, a self-signed CA certificate inside its validity period; hosted mode
// also requires the pinned fingerprint. [code, message] or null.
export function caCertificateProblem(pem, mode, now = Date.now()) {
  const text = String(pem);
  if (/-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(text)) return ['ca_invalid', 'the CA file must not hold a private key'];
  const blocks = text.match(/-----BEGIN CERTIFICATE-----[\s\S]+?-----END CERTIFICATE-----/g) || [];
  if (blocks.length !== 1) return ['ca_invalid', 'the CA file must hold exactly one PEM certificate'];
  let cert;
  try { cert = new X509Certificate(blocks[0]); } catch { return ['ca_invalid', 'the CA certificate cannot be parsed']; }
  if (!cert.ca) return ['ca_invalid', 'the certificate is not a CA certificate'];
  let selfSigned = false;
  try { selfSigned = cert.subject === cert.issuer && cert.verify(cert.publicKey); } catch { selfSigned = false; }
  if (!selfSigned) return ['ca_invalid', 'the CA certificate is not self-signed'];
  if (!(now >= Date.parse(cert.validFrom) && now <= Date.parse(cert.validTo))) return ['ca_invalid', 'the CA certificate is outside its validity period'];
  if (mode === 'hosted' && cert.fingerprint256 !== ACCEPTED_HOSTED_CA_SHA256) {
    return ['ca_not_accepted', 'the CA is not the accepted CA for the hosted direct host'];
  }
  return null;
}

// CR-EG-01 (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-EXACT-GAP-APPLY-001-CORRECTIONS-001): this mode's passfile holds exactly
// ONE active entry in total, and that entry is the exact target (host, port, database, user) with a non-empty password.
// Comments and empty lines are ignored; a malformed or wildcard line is refused, as on the default route, whose own rule
// (one exact entry for the endpoint) is unchanged. Neither the passfile's path nor any of its content is ever printed.
export function selectExactGapPassfileEntry(entries, target) {
  if (entries.some((e) => e === null)) refuse('passfile_malformed', 'the passfile has a malformed line');
  if (entries.some((e) => e.slice(0, 4).includes('*'))) refuse('passfile_wildcard', 'the passfile may not use wildcards');
  if (entries.length !== 1) refuse('passfile_entry_count', 'the passfile must hold exactly one active entry in total: the exact target');
  return selectPassfileEntry(entries, target);
}

// The default route's passfile checks (location, owner-only permissions, format, the exact target entry) run first, so a
// file with no exact entry or two of them refuses there (passfile_entry); then a second read of the same file must pass
// the one-entry rule and select the same password (passfile_changed otherwise). (read: a test seam.)
export function verifyExactGapPassfile(raw, target, workdir, { read = (file) => readFileSync(file, 'utf8'), ...options } = {}) {
  const checked = verifyPassfile(raw, target, workdir, options);
  let text;
  try { text = read(checked.path); } catch { refuse('passfile_missing', 'the passfile could not be read'); }
  if (selectExactGapPassfileEntry(parsePassfile(text), target) !== checked.secret) {
    refuse('passfile_changed', 'the passfile changed while it was checked');
  }
  return checked;
}

// The owner-private CA file: absolute, a regular non-empty file, outside the repository, the store and the workdir,
// owner-only, and an acceptable certificate. Its path is never printed.
export function verifyCa(raw, mode, workdir, { repoRoot = path.resolve(path.dirname(SELF), '..', '..'), now = Date.now() } = {}) {
  if (typeof raw !== 'string' || raw === '') refuse('ca_missing', `${ENV_SSLROOTCERT} is not set`);
  if (!path.isAbsolute(raw)) refuse('ca_missing', 'the CA path must be absolute');
  let real;
  let st;
  try { real = canonical(raw); st = statSync(real); } catch { refuse('ca_missing', 'the CA file does not exist'); }
  if (!st.isFile() || st.size === 0) refuse('ca_missing', 'the CA file is not a non-empty regular file');
  let workReal;
  try { workReal = canonical(workdir); } catch { refuse('bad_arguments', 'the workdir does not exist'); }
  const where = passfileLocationProblem(real, { repoRoot: canonical(repoRoot), workdir: workReal });
  if (where) refuse('ca_location', `the CA file is ${where}`);
  const permission = ownerOnlyProblem(real, st);
  if (permission) refuse('ca_permissions', permission);
  const problem = caCertificateProblem(readFileSync(real, 'utf8'), mode, now);
  if (problem) refuse(problem[0], problem[1]);
  return { path: real };
}

const SAFE_QUALIFIED = /^[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;
const SAFE_AT = /^[a-z_][a-z0-9_]*@[a-z_][a-z0-9_]*$/;
// D-068: a trigger on a schema-qualified table (#386's triggers sit on public and app tables).
const SAFE_AT_QUALIFIED = /^[a-z_][a-z0-9_]*@[a-z_][a-z0-9_]*\.[a-z_][a-z0-9_]*$/;
const textArray = (items, shape) => {
  if (!items.length || items.some((s) => !shape.test(s))) throw new Refusal('internal_pin', 'a pinned name has an unexpected shape');
  return `array[${items.map((s) => `'${s}'`).join(', ')}]::text[]`;
};
const sqlDigest = (expr) => `encode(sha256(convert_to(coalesce(${expr}, ''), 'UTF8')), 'hex')`;
const relationPrivilege = (role) => `case when c.relkind = 'S' then has_sequence_privilege('${role}', c.oid, 'USAGE,SELECT,UPDATE')
      else has_table_privilege('${role}', c.oid, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
        or has_any_column_privilege('${role}', c.oid, 'SELECT,INSERT,UPDATE,REFERENCES') end`;
// CR-EG-02: the exact access of one ACL value (pass a NULL-resolved ACL): its entries as [grantee, privilege, grantable,
// grantor] (grantee 0 is PUBLIC; role names, never OIDs), sorted in byte order, so the same catalog always gives the
// same answer (and the same state fingerprint).
const aclEntries = (acl) => `(select coalesce(json_agg(json_build_array(x.grantee, x.privilege, x.grantable, x.grantor)
      order by x.grantee collate "C", x.privilege collate "C", x.grantable, x.grantor collate "C"), '[]'::json)
    from (select case when a.grantee = 0 then 'PUBLIC' else pg_catalog.pg_get_userbyid(a.grantee)::text end as grantee,
        a.privilege_type::text as privilege, a.is_grantable as grantable, pg_catalog.pg_get_userbyid(a.grantor)::text as grantor
      from pg_catalog.aclexplode(${acl}) a) x)`;
// Every column grant of one relation, as [column, grantee, privilege, grantable, grantor], sorted the same way.
const columnEntries = (relation) => `(select coalesce(json_agg(json_build_array(x.col, x.grantee, x.privilege, x.grantable, x.grantor)
      order by x.col collate "C", x.grantee collate "C", x.privilege collate "C", x.grantable, x.grantor collate "C"), '[]'::json)
    from (select att.attname::text as col, case when a.grantee = 0 then 'PUBLIC' else pg_catalog.pg_get_userbyid(a.grantee)::text end as grantee,
        a.privilege_type::text as privilege, a.is_grantable as grantable, pg_catalog.pg_get_userbyid(a.grantor)::text as grantor
      from pg_catalog.pg_attribute att cross join lateral pg_catalog.aclexplode(att.attacl) a
      where att.attrelid = ${relation} and att.attnum > 0 and not att.attisdropped) x)`;
// One relation's whole catalog line (kind, RLS, owner, ACL, columns, constraints, policies, triggers, indexes) over the
// rel CTE's row r: the other-relation digest's line, and (REPIN-001) the #382 relation's definition digest.
// The policies segment is the pol CTE's JSON list as text (names, commands, permissive flags, roles by name, expressions):
// one unambiguous serialization, the rendering PRE compares by value (D-068 review: a role OID is instance-local, and a
// joined role list could collide).
const relationLine = `r.name || '|' || r.kind || '|' || r.rls::text || '|' || r.force_rls::text || '|' || r.owner || '|' || r.acl
    || '|' || coalesce((select string_agg(a.attname || ':' || pg_catalog.format_type(a.atttypid, a.atttypmod) || ':'
        || a.attnotnull::text || ':' || coalesce(a.attacl::text, '') || ':' || coalesce(pg_catalog.pg_get_expr(d.adbin, d.adrelid), ''),
        ',' order by a.attnum)
      from pg_catalog.pg_attribute a left join pg_catalog.pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
      where a.attrelid = r.oid and a.attnum > 0 and not a.attisdropped), '')
    || '|' || coalesce((select string_agg(co.conname || ':' || co.contype::text || ':' || pg_catalog.pg_get_constraintdef(co.oid),
        ',' order by co.conname)
      from pg_catalog.pg_constraint co where co.conrelid = r.oid), '')
    || '|' || coalesce((select pol.policies::text from pol where pol.polrelid = r.oid), '')
    || '|' || coalesce((select string_agg(t.tgname || ':' || t.tgenabled::text || ':' || pg_catalog.pg_get_triggerdef(t.oid),
        ',' order by t.tgname)
      from pg_catalog.pg_trigger t where t.tgrelid = r.oid and not t.tgisinternal), '')
    || '|' || coalesce((select string_agg(pg_catalog.pg_get_indexdef(i.indexrelid), ',' order by pg_catalog.pg_get_indexdef(i.indexrelid))
      from pg_catalog.pg_index i where i.indrelid = r.oid), '')`;
const SAFE_NAME = /^[a-z_][a-z0-9_]*$/;
// The NULL-resolved ACL of the rel CTE's row r (a sequence's default differs from a table's).
const relationAcl = "coalesce(r.relacl, pg_catalog.acldefault(case when r.kind = 'S' then 's'::\"char\" else 'r'::\"char\" end, r.relowner))";

// ONE read-only statement: catalog facts and digests only, never a table row. Every name in it is a pinned constant.
export function exactGapStateSql(pins = EXACT_GAP) {
  const fns = textArray(pins.functions.map((f) => f[0]), SAFE_QUALIFIED);
  const rels = textArray([...pins.tables, pins.sequence], SAFE_QUALIFIED);
  const idx = textArray(pins.indexes, SAFE_AT);
  const trg = textArray(pins.triggers, SAFE_AT);
  const surfFns = textArray(pins.surfaceFunctions, SAFE_QUALIFIED);
  const surfRels = textArray(pins.surfaceTables, SAFE_QUALIFIED);
  // REPIN-001: #382's own surface, by name only (an extra overload of a pinned name is part of the answer).
  const s382Fns = textArray([...new Set(pins.surface382.functions.map((f) => f[0]))], SAFE_QUALIFIED);
  const s382Rels = textArray([pins.surface382.relation.name], SAFE_QUALIFIED);
  const s382Pols = textArray(pins.surface382.policies.map((p) => p.name), SAFE_NAME);
  if (pins.surface382.policies.some((p) => p.table !== 'storage.objects')) throw new Refusal('internal_pin', 'a pinned #382 policy is not on storage.objects');
  // D-068 (POST-386-REPIN-001): #386's own surface, by name only (an extra overload or a duplicate under a pinned name is part of the answer).
  const s386Fns = textArray([...new Set(pins.surface386.functions.map((f) => f[0]))], SAFE_QUALIFIED);
  const s386Rels = textArray(pins.surface386.relations.map((r) => r.name), SAFE_QUALIFIED);
  const s386Trgs = textArray(pins.surface386.triggers.map((t) => t[0]), SAFE_AT_QUALIFIED);
  const lines = "string_agg(line, E'\\n' order by line)";
  return `-- GR-37 exact-gap state (${EXACT_GAP_MODE}): read-only catalog facts and digests, never row data
with led as (
  select version, name, coalesce(array_length(statements, 1), 0) as n,
    case when coalesce(array_length(statements, 1), 0) >= 1
      then encode(sha256(convert_to(statements[1], 'UTF8')), 'hex') end as first_sha,
    ${sqlDigest('statements::text')} as all_sha
  from supabase_migrations.schema_migrations
), fn as (
  select n.nspname || '.' || p.proname as name, p.prokind::text as kind,
    pg_catalog.pg_get_function_identity_arguments(p.oid) as args,
    ${sqlDigest('p.prosrc')} as src,
    ${sqlDigest("replace(b.body, E'\\r\\n', E'\\n')")} as src_lf,
    length(b.body) - length(replace(b.body, E'\\r', '')) as cr,
    length(b.body) - length(replace(b.body, E'\\n', '')) as lf,
    (length(b.body) - length(replace(b.body, E'\\r\\n', ''))) / 2 as crlf,
    (length(b.body) - length(replace(b.body, E'\\r', ''))) > (length(b.body) - length(replace(b.body, E'\\r\\n', ''))) / 2 as lone_cr,
    p.prosecdef as secdef, coalesce(array_to_string(p.proconfig, ','), '') as config,
    p.provolatile::text as volatility, l.lanname::text as language,
    pg_catalog.pg_get_userbyid(p.proowner)::text as owner, coalesce(p.proacl::text, '') as acl,
    has_function_privilege('anon', p.oid, 'EXECUTE') as anon,
    has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated,
    has_function_privilege('service_role', p.oid, 'EXECUTE') as service_role,
    exists (select 1 from pg_catalog.aclexplode(coalesce(p.proacl, pg_catalog.acldefault('f', p.proowner))) a
      where a.grantee = 0 and a.privilege_type = 'EXECUTE') as public,
    p.proacl as proacl, p.proowner as proowner, p.oid as oid
  from pg_catalog.pg_proc p
  cross join lateral (select coalesce(p.prosrc, '') as body) b
  join pg_catalog.pg_namespace n on n.oid = p.pronamespace
  join pg_catalog.pg_language l on l.oid = p.prolang
  where n.nspname in ('app', 'public')
), rel as (
  select n.nspname || '.' || c.relname as name, c.oid, c.relkind::text as kind,
    c.relrowsecurity as rls, c.relforcerowsecurity as force_rls,
    pg_catalog.pg_get_userbyid(c.relowner)::text as owner, coalesce(c.relacl::text, '') as acl,
    ${relationPrivilege('anon')} as anon,
    ${relationPrivilege('authenticated')} as authenticated,
    ${relationPrivilege('service_role')} as service_role,
    exists (select 1 from pg_catalog.aclexplode(coalesce(c.relacl,
        pg_catalog.acldefault(case when c.relkind = 'S' then 's'::"char" else 'r'::"char" end, c.relowner))) a
      where a.grantee = 0) as public,
    c.relacl as relacl, c.relowner as relowner
  from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('app', 'public') and c.relkind in ('r', 'p', 'v', 'm', 'f', 'S')
), pol as (
  select p.polrelid,
    json_agg(json_build_object('name', p.polname, 'cmd', p.polcmd::text, 'permissive', p.polpermissive,
      'roles', (select coalesce(json_agg(coalesce(r.rolname::text, 'public') order by coalesce(r.rolname::text, 'public')), '[]'::json)
        from unnest(p.polroles) u(o) left join pg_catalog.pg_roles r on r.oid = u.o),
      'using', pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'check', pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid))
      order by p.polname) as policies
  from pg_catalog.pg_policy p group by p.polrelid
), other_rel as (
  select ${relationLine} as line
  from rel r where not (r.name = any (${rels}))
), other_fn as (
  select name || '(' || args || ')|' || kind || '|' || src || '|' || secdef::text || '|' || config || '|' || volatility
    || '|' || language || '|' || owner || '|' || acl as line
  from fn where not (name = any (${fns}))
), dacl as (
  select pg_catalog.pg_get_userbyid(d.defaclrole)::text || '|' || coalesce(n.nspname::text, '') || '|' || d.defaclobjtype::text
    || '|' || coalesce(d.defaclacl::text, '') as line
  from pg_catalog.pg_default_acl d left join pg_catalog.pg_namespace n on n.oid = d.defaclnamespace
)
select json_build_object(
  'session', json_build_object('user', current_user, 'read_only', current_setting('transaction_read_only'),
    'lock_timeout', current_setting('lock_timeout'), 'statement_timeout', current_setting('statement_timeout'),
    'application_name', current_setting('application_name'), 'server_version_num', current_setting('server_version_num'),
    'ssl', (select s.ssl from pg_catalog.pg_stat_ssl s where s.pid = pg_catalog.pg_backend_pid())),
  'runtime', json_build_object('server_version_num', current_setting('server_version_num'), 'time_zone', current_setting('TimeZone')),
  'ledger', (select coalesce(json_agg(json_build_object('version', version, 'name', name, 'n', n, 'first', first_sha,
    'all', all_sha) order by version), '[]'::json) from led),
  'functions', (select coalesce(json_agg(json_build_object('name', name, 'args', args, 'kind', kind, 'src', src,
    'src_lf', src_lf, 'cr', cr, 'lf', lf, 'crlf', crlf, 'lone_cr', lone_cr,
    'secdef', secdef, 'config', config, 'volatility', volatility, 'language', language, 'owner', owner, 'anon', anon,
    'authenticated', authenticated, 'service_role', service_role, 'public', public,
    'access', ${aclEntries("coalesce(proacl, pg_catalog.acldefault('f', proowner))")}) order by name, args), '[]'::json)
    from fn where name = any (${fns})),
  'relations', (select coalesce(json_agg(json_build_object('name', r.name, 'kind', r.kind, 'rls', r.rls,
    'force_rls', r.force_rls, 'owner', r.owner, 'anon', r.anon, 'authenticated', r.authenticated,
    'service_role', r.service_role, 'public', r.public,
    'policies', coalesce((select pol.policies from pol where pol.polrelid = r.oid), '[]'::json),
    'access', ${aclEntries("coalesce(r.relacl, pg_catalog.acldefault(case when r.kind = 'S' then 's'::\"char\" else 'r'::\"char\" end, r.relowner))")},
    'columns', ${columnEntries('r.oid')}) order by r.name), '[]'::json)
    from rel r where r.name = any (${rels})),
  'indexes', (select coalesce(json_agg(ci.relname || '@' || ct.relname order by ci.relname), '[]'::json)
    from pg_catalog.pg_index i join pg_catalog.pg_class ci on ci.oid = i.indexrelid
    join pg_catalog.pg_class ct on ct.oid = i.indrelid join pg_catalog.pg_namespace n on n.oid = ct.relnamespace
    where n.nspname = 'app' and (ci.relname || '@' || ct.relname) = any (${idx})),
  'triggers', (select coalesce(json_agg(t.tgname || '@' || c.relname || ':' || t.tgenabled::text order by t.tgname), '[]'::json)
    from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where not t.tgisinternal and n.nspname = 'app' and (t.tgname || '@' || c.relname) = any (${trg})),
  'cardRelations', (select count(*) from rel where name ~ '^(app|public)\\.(card_|payment_terminal)'),
  'cardFunctions', (select count(*) from fn where name ~ '^(app|public)\\.(card_|owner_card_attempts$|payment_terminal)'),
  'surfaceFunctions', (select count(distinct name) from fn where name = any (${surfFns})),
  'surfaceRelations', (select count(*) from rel where name = any (${surfRels})),
  'surface382', json_build_object(
    'functions', (select coalesce(json_agg(json_build_object('name', name, 'args', args, 'kind', kind, 'src', src,
      'src_lf', src_lf, 'cr', cr, 'lf', lf, 'crlf', crlf, 'lone_cr', lone_cr,
      'secdef', secdef, 'config', config, 'volatility', volatility, 'language', language, 'owner', owner,
      'def', ${sqlDigest('pg_catalog.pg_get_functiondef(oid)')},
      'access', ${aclEntries("coalesce(proacl, pg_catalog.acldefault('f', proowner))")}) order by name, args), '[]'::json)
      from fn where name = any (${s382Fns})),
    'relations', (select coalesce(json_agg(json_build_object('name', r.name, 'kind', r.kind, 'rls', r.rls,
      'force_rls', r.force_rls, 'owner', r.owner, 'access', ${aclEntries(relationAcl)},
      'columns', ${columnEntries('r.oid')}, 'definition', ${sqlDigest(relationLine)}) order by r.name), '[]'::json)
      from rel r where r.name = any (${s382Rels})),
    'policies', (select coalesce(json_agg(json_build_object('table', n.nspname || '.' || c.relname, 'name', p.polname,
      'cmd', p.polcmd::text, 'permissive', p.polpermissive,
      'roles', (select coalesce(json_agg(coalesce(r.rolname::text, 'public') order by coalesce(r.rolname::text, 'public')), '[]'::json)
        from unnest(p.polroles) u(o) left join pg_catalog.pg_roles r on r.oid = u.o),
      'using', pg_catalog.pg_get_expr(p.polqual, p.polrelid), 'check', pg_catalog.pg_get_expr(p.polwithcheck, p.polrelid))
      order by p.polname), '[]'::json)
      from pg_catalog.pg_policy p join pg_catalog.pg_class c on c.oid = p.polrelid
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'storage' and c.relname = 'objects' and p.polname = any (${s382Pols})),
    'objectPolicies', (select json_build_object('count', json_array_length(pol.policies), 'sha256', ${sqlDigest('pol.policies::text')})
      from pol join pg_catalog.pg_class c on c.oid = pol.polrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'storage' and c.relname = 'objects')),
  'surface386', json_build_object(
    'functions', (select coalesce(json_agg(json_build_object('name', name, 'args', args, 'kind', kind, 'src', src,
      'src_lf', src_lf, 'cr', cr, 'lf', lf, 'crlf', crlf, 'lone_cr', lone_cr,
      'secdef', secdef, 'config', config, 'volatility', volatility, 'language', language, 'owner', owner,
      'def', ${sqlDigest('pg_catalog.pg_get_functiondef(oid)')},
      'access', ${aclEntries("coalesce(proacl, pg_catalog.acldefault('f', proowner))")}) order by name, args), '[]'::json)
      from fn where name = any (${s386Fns})),
    'relations', (select coalesce(json_agg(json_build_object('name', r.name, 'kind', r.kind, 'rls', r.rls,
      'force_rls', r.force_rls, 'owner', r.owner,
      'policies', coalesce((select pol.policies from pol where pol.polrelid = r.oid), '[]'::json),
      'access', ${aclEntries(relationAcl)}, 'columns', ${columnEntries('r.oid')}, 'definition', ${sqlDigest(relationLine)}) order by r.name), '[]'::json)
      from rel r where r.name = any (${s386Rels})),
    'triggers', (select coalesce(json_agg(json_build_object('name', t.tgname || '@' || n.nspname || '.' || c.relname, 'enabled', t.tgenabled::text,
      'def', ${sqlDigest('pg_catalog.pg_get_triggerdef(t.oid)')}) order by t.tgname, n.nspname, c.relname), '[]'::json)
      from pg_catalog.pg_trigger t join pg_catalog.pg_class c on c.oid = t.tgrelid join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where not t.tgisinternal and n.nspname in ('app', 'public') and (t.tgname || '@' || n.nspname || '.' || c.relname) = any (${s386Trgs}))),
  'otherFunctions', (select json_build_object('count', count(*), 'sha256', ${sqlDigest(lines)}) from other_fn),
  'otherRelations', (select json_build_object('count', count(*), 'sha256', ${sqlDigest(lines)}) from other_rel),
  'defaultAcl', (select json_build_object('count', count(*), 'sha256', ${sqlDigest(lines)}) from dacl)
)::text as state;
`;
}

// The pinned CLI's `db query --output json` answer on stdout: with `--agent no` an array of rows, [{"state": "<json
// text>"}]; in its agent mode an envelope {boundary, rows, warning}. Exactly one row with a string state either way.
export function parseStateRows(stdout) {
  try {
    const outer = JSON.parse(String(stdout).trim());
    const rows = Array.isArray(outer) ? outer : (outer && Array.isArray(outer.rows) ? outer.rows : null);
    if (!rows || rows.length !== 1 || !rows[0] || typeof rows[0].state !== 'string') return null;
    const state = JSON.parse(rows[0].state);
    return state && typeof state === 'object' && Array.isArray(state.ledger) ? state : null;
  } catch {
    return null;
  }
}

// `migration list`: the Local | Remote | Time table; null when the header is missing.
export function parseMigrationList(text) {
  const lines = String(text).replace(/\r/g, '').split('\n');
  const head = lines.findIndex((l) => /^\s*Local\s*\|\s*Remote\s*\|\s*Time/.test(l));
  if (head < 0) return null;
  const rows = [];
  for (const line of lines.slice(head + 1)) {
    const m = /^\s*([0-9]{14})?\s*\|\s*([0-9]{14})?\s*\|/.exec(line);
    if (m && (m[1] || m[2])) rows.push({ local: m[1] ?? null, remote: m[2] ?? null });
  }
  return rows;
}

const GROUP_PRIVILEGES = deepFreeze({
  none: { anon: false, authenticated: false, service_role: false, public: false },
  authenticated: { anon: false, authenticated: true, service_role: false, public: false },
  service_role: { anon: false, authenticated: false, service_role: true, public: false },
});

// CR-EG-02: exact access, compared as a set of entries (order-independent; a malformed answer never matches), and a
// short account of a difference: role names and privileges only (catalog names, never a secret).
const accessKeys = (entries) => (Array.isArray(entries) && entries.every((e) => Array.isArray(e)) ? entries.map((e) => JSON.stringify(e)).sort() : null);
const sameAccess = (got, want) => {
  const g = accessKeys(got);
  return g !== null && JSON.stringify(g) === JSON.stringify(accessKeys(want));
};
const accessDiff = (got, want) => {
  const g = accessKeys(got);
  if (g === null) return 'the access answer is missing or malformed';
  const w = accessKeys(want);
  const show = (keys) => (keys.length ? `${keys.slice(0, 3).map((k) => JSON.parse(k).join(' ')).join('; ')}${keys.length > 3 ? `; and ${keys.length - 3} more` : ''}` : 'none');
  return `unexpected: ${show(g.filter((k) => !w.includes(k)))}; missing: ${show(w.filter((k) => !g.includes(k)))}`;
};

const sessionProblems = (state, label) => {
  const s = state.session || {};
  const out = [];
  if (s.read_only !== 'on') out.push(['session_not_read_only', `the ${label} session is not read-only`]);
  if (s.ssl !== true) out.push(['session_not_tls', `the ${label} session is not encrypted`]);
  if (s.application_name !== APPLICATION_NAME || s.lock_timeout !== '5s' || s.statement_timeout !== '1min') {
    out.push(['session_settings', `the ${label} session does not carry the fixed startup settings`]);
  }
  return out;
};

// REPIN-001: the PostgreSQL runtime the access pins were derived on, and the session time zone; [code, message] each.
const runtimeProblems = (state, pins, label) => {
  const r = (state && state.runtime) || {};
  const out = [];
  if (r.server_version_num !== pins.runtime.serverVersionNum) {
    out.push(['runtime_version', `the ${label} server reports server_version_num ${String(r.server_version_num).slice(0, 12)}; the access pins are PostgreSQL ${pins.runtime.serverVersionNum} values and are never regenerated silently`]);
  }
  if (r.time_zone !== pins.runtime.timeZone) {
    out.push(['runtime_timezone', `the ${label} session reports TimeZone ${String(r.time_zone).slice(0, 40)}; it must be ${pins.runtime.timeZone}`]);
  }
  return out;
};

// REPIN-001: #382's own surface, exactly as pinned from the current-main sequential reference; [code, message] each.
const samePolicy = (got, want) => Boolean(got) && got.table === want.table && got.name === want.name && got.cmd === want.cmd
  && got.permissive === want.permissive && JSON.stringify(got.roles) === JSON.stringify(want.roles) && got.using === want.using
  && got.check === want.check;
const surface382Problems = (state, pins) => {
  const s = state.surface382;
  const p = pins.surface382;
  if (!s || typeof s !== 'object' || !Array.isArray(s.functions) || !Array.isArray(s.relations) || !Array.isArray(s.policies)) {
    return [['surface382_unreadable', 'the #382 surface answer is missing or malformed']];
  }
  const out = [];
  if (s.functions.length !== p.functions.length) {
    out.push(['surface382_function', `#382 must have exactly ${p.functions.length} functions under its pinned names; found ${s.functions.length}`]);
  }
  for (const [name, args, src, secdef, config, volatility, language, group, def] of p.functions) {
    const found = s.functions.filter((f) => f && f.name === name);
    if (found.length !== 1) { out.push(['surface382_function', `${name}: ${found.length} definitions`]); continue; }
    const f = found[0];
    if (f.args !== args || f.kind !== 'f' || f.src !== src || f.secdef !== secdef || f.config !== config || f.volatility !== volatility
      || f.language !== language || f.def !== def || f.owner !== pins.owner) {
      out.push(['surface382_function', `${name}: the identity, definition or owner differs from the pinned sequential reference`]);
    }
    if (!sameAccess(f.access, p.access[group])) {
      out.push(['surface382_access', `${name}: the exact access differs from the pinned sequential reference (${accessDiff(f.access, p.access[group])})`]);
    }
  }
  const want = p.relation;
  const rows = s.relations.filter((r) => r && r.name === want.name);
  if (s.relations.length !== 1 || rows.length !== 1) {
    out.push(['surface382_relation', `${want.name} must exist exactly once; found ${rows.length}`]);
  } else {
    const r = rows[0];
    if (r.kind !== want.kind || r.rls !== want.rls || r.force_rls !== want.force_rls || r.owner !== pins.owner || r.definition !== want.definition) {
      out.push(['surface382_relation', `${want.name}: the definition, RLS or owner differs from the pinned sequential reference`]);
    }
    if (!sameAccess(r.access, want.access)) {
      out.push(['surface382_access', `${want.name}: the exact access differs from the pinned sequential reference (${accessDiff(r.access, want.access)})`]);
    }
    if (!sameAccess(r.columns, want.columns)) {
      out.push(['surface382_access', `${want.name}: a column grant differs from the pinned sequential reference (${accessDiff(r.columns, want.columns)})`]);
    }
  }
  if (s.policies.length !== p.policies.length || !p.policies.every((w) => samePolicy(s.policies.find((g) => g && g.name === w.name), w))) {
    out.push(['surface382_policy', `the #382 Storage policies on storage.objects differ from the pinned sequential reference (${s.policies.length} found under the ${p.policies.length} pinned names)`]);
  }
  return out;
};

// D-068 (POST-386-REPIN-001): #386's own surface, exactly as pinned from the current-main sequential reference; [code, message]
// each. Functions: exactly one per pinned name, with the pinned identity, body, attributes, whole definition, owner and exact
// access (the group's entries, or the per-function entries of the inherited one). Relations: exactly the pinned ones, each
// with the pinned kind, RLS, forced RLS, owner, policies, exact access, column grants and catalog-line digest. Triggers:
// exactly the pinned ones, each enabled with the pinned definition digest.
const samePolicyList = (got, want) => Array.isArray(got) && got.length === want.length
  && want.every((w) => got.filter((g) => g && g.name === w.name).length === 1 && samePolicy({ table: w.table, ...got.find((g) => g.name === w.name) }, w));
const surface386Problems = (state, pins) => {
  const s = state.surface386;
  const p = pins.surface386;
  if (!s || typeof s !== 'object' || !Array.isArray(s.functions) || !Array.isArray(s.relations) || !Array.isArray(s.triggers)) {
    return [['surface386_unreadable', 'the #386 surface answer is missing or malformed']];
  }
  const out = [];
  if (s.functions.length !== p.functions.length) {
    out.push(['surface386_function', `#386 must have exactly ${p.functions.length} functions under its pinned names; found ${s.functions.length}`]);
  }
  for (const [name, args, src, secdef, config, volatility, language, group, def] of p.functions) {
    const found = s.functions.filter((f) => f && f.name === name);
    if (found.length !== 1) { out.push(['surface386_function', `${name}: ${found.length} definitions`]); continue; }
    const f = found[0];
    if (f.args !== args || f.kind !== 'f' || f.src !== src || f.secdef !== secdef || f.config !== config || f.volatility !== volatility
      || f.language !== language || f.def !== def || f.owner !== pins.owner) {
      out.push(['surface386_function', `${name}: the identity, definition or owner differs from the pinned sequential reference`]);
    }
    const want = group === 'inherited' ? p.inheritedAccess[name] : p.access[group];
    if (!sameAccess(f.access, want)) {
      out.push(['surface386_access', `${name}: the exact access differs from the pinned sequential reference (${accessDiff(f.access, want)})`]);
    }
  }
  if (s.relations.length !== p.relations.length) {
    out.push(['surface386_relation', `#386 must have exactly ${p.relations.length} relations under its pinned names; found ${s.relations.length}`]);
  }
  for (const want of p.relations) {
    const rows = s.relations.filter((r) => r && r.name === want.name);
    if (rows.length !== 1) { out.push(['surface386_relation', `${want.name} must exist exactly once; found ${rows.length}`]); continue; }
    const r = rows[0];
    if (r.kind !== want.kind || r.rls !== want.rls || r.force_rls !== want.force_rls || r.owner !== pins.owner || r.definition !== want.definition
      || !samePolicyList(r.policies, want.policies.map((x) => ({ table: want.name, ...x })))) {
      out.push(['surface386_relation', `${want.name}: the definition, RLS, policies or owner differs from the pinned sequential reference`]);
    }
    if (!sameAccess(r.access, want.access)) {
      out.push(['surface386_access', `${want.name}: the exact access differs from the pinned sequential reference (${accessDiff(r.access, want.access)})`]);
    }
    if (!sameAccess(r.columns, want.columns)) {
      out.push(['surface386_access', `${want.name}: a column grant differs from the pinned sequential reference (${accessDiff(r.columns, want.columns)})`]);
    }
  }
  if (s.triggers.length !== p.triggers.length) {
    out.push(['surface386_trigger', `#386 must have exactly ${p.triggers.length} triggers under its pinned names; found ${s.triggers.length}`]);
  }
  for (const [name, def] of p.triggers) {
    const rows = s.triggers.filter((t) => t && t.name === name);
    if (rows.length !== 1) { out.push(['surface386_trigger', `${name}: ${rows.length} triggers`]); continue; }
    if (rows[0].enabled !== 'O' || rows[0].def !== def) {
      out.push(['surface386_trigger', `${name}: disabled, or its definition differs from the pinned sequential reference`]);
    }
  }
  return out;
};
const surface386Functions = (state) => (state && state.surface386 && typeof state.surface386 === 'object'
  && Array.isArray(state.surface386.functions) ? state.surface386.functions : []);

// D-067 (HOSTED-PRE-COMPAT-001): one selected function's line-ending facts as the state query reports them; null when one
// is missing or malformed (the function is then refused, never guessed).
const eolFacts = (f) => (f && typeof f === 'object' && typeof f.src === 'string' && typeof f.src_lf === 'string'
  && [f.cr, f.lf, f.crlf].every((n) => Number.isInteger(n) && n >= 0) && typeof f.lone_cr === 'boolean'
  ? { src: f.src, srcLf: f.src_lf, cr: f.cr, lf: f.lf, crlf: f.crlf, loneCr: f.lone_cr } : null);

// D-067: the pre-001D form of one of the seven re-created functions. It passes only in its exact canonical LF form or,
// for the six named in legacyCrlfBefore only, in its exact reviewed legacy CRLF form (raw SHA-256, LF-normalized
// SHA-256, and CR = LF = CRLF pairs = the pinned line-break count, with no lone CR). Anything else is one refusal that
// names its rule; the caller adds the function's name, and no body text is ever part of it. Exported for the unit tests.
export function recreatedBodyForm(f, name, pins = EXACT_GAP) {
  const canonical = pins.recreatedBefore[name];
  const map = pins.legacyCrlfBefore || {};
  const legacy = Object.hasOwn(map, name) ? map[name] : null;
  if (typeof canonical !== 'string' || (legacy && legacy.canonical !== canonical)) {
    throw new Refusal('internal_pin', 'a re-created function\'s canonical and legacy CRLF pins disagree');
  }
  const e = eolFacts(f);
  if (!e) return { ok: false, code: 'recreated_eol', rule: 'its line-ending facts are missing or malformed' };
  if (e.src === canonical && e.srcLf === canonical && e.cr === 0 && !e.loneCr) return { ok: true, form: 'canonical LF' };
  if (legacy && e.src === legacy.crlf && e.srcLf === canonical && e.cr === legacy.lineBreaks && e.lf === legacy.lineBreaks
    && e.crlf === legacy.lineBreaks && !e.loneCr) {
    return { ok: true, form: 'legacy CRLF' };
  }
  if (e.loneCr) return { ok: false, code: 'recreated_eol', rule: 'a lone carriage return (a CR not followed by an LF)' };
  if (e.cr === 0) return { ok: false, code: 'recreated_drift', rule: 'its body is not the canonical LF pin' };
  if (!legacy) return { ok: false, code: 'recreated_eol', rule: 'carriage returns in a body accepted only in its canonical LF form' };
  if (e.cr !== e.crlf || e.lf !== e.crlf) return { ok: false, code: 'recreated_eol', rule: 'mixed line endings (CRLF beside LF-only line breaks)' };
  if (e.srcLf !== canonical) return { ok: false, code: 'recreated_drift', rule: 'its LF-normalized body is not the canonical pin' };
  if (e.cr !== legacy.lineBreaks) return { ok: false, code: 'recreated_eol', rule: 'its line-break count is not the reviewed legacy CRLF form\'s' };
  return { ok: false, code: 'recreated_eol', rule: 'its raw bytes are not the exact reviewed legacy CRLF form (the same normalized body in an unpinned raw form)' };
}

// D-067: every other selected function (a 001D function found before the apply, every #382 function and every POST
// function) is accepted in canonical LF only, with no CR at all. The rule it breaks, or null.
const lfOnlyRule = (f) => {
  const e = eolFacts(f);
  if (!e) return 'its line-ending facts are missing or malformed';
  if (e.loneCr) return 'a lone carriage return (a CR not followed by an LF)';
  if (e.cr !== 0) return 'carriage returns in a body accepted only in its canonical LF form';
  return null;
};
const selectedName = (f, fallback) => (f && typeof f.name === 'string' && SAFE_QUALIFIED.test(f.name) ? f.name : fallback);
const surface382Functions = (state) => (state && state.surface382 && typeof state.surface382 === 'object'
  && Array.isArray(state.surface382.functions) ? state.surface382.functions : []);

// D-067: the Default ACL digest ({count, sha256} over every pg_default_acl row) as the state query reports it. The first
// PRE's value is this run's baseline; it is never compared with a local reference.
const defaultAclShape = (d) => Boolean(d) && typeof d === 'object' && Number.isInteger(d.count) && d.count >= 0
  && typeof d.sha256 === 'string' && /^[0-9a-f]{64}$/.test(d.sha256);

// PRE gates on the read-only state: [code, message] for each failure (none means every gate passed).
export function evaluateExactGapPre(state, local, pins = EXACT_GAP) {
  if (!state || !Array.isArray(state.ledger)) return [['state_unreadable', 'the read-only state could not be read']];
  const problems = sessionProblems(state, 'PRE');
  problems.push(...runtimeProblems(state, pins, 'PRE'));
  const add = (code, message) => problems.push([code, message]);
  const remote = state.ledger.map((r) => r.version);
  const remoteSet = new Set(remote);
  const localSet = new Set(local.versions);
  if (remoteSet.size !== remote.length) add('remote_duplicate', 'the remote ledger repeats a version');
  if (remote.length !== pins.remoteCountBefore) add('remote_count', `the remote ledger must hold ${pins.remoteCountBefore} versions; it holds ${remote.length}`);
  const tail = remote.slice(-pins.remoteTail.length);
  if (tail.join(',') !== pins.remoteTail.join(',')) add('remote_tail', `the newest remote versions must be ${pins.remoteTail.join(', ')}; they are ${tail.join(', ')}`);
  const remoteOnly = remote.filter((v) => !localSet.has(v));
  const localOnly = local.versions.filter((v) => !remoteSet.has(v));
  if (remoteOnly.length) add('remote_only', `the remote ledger holds ${remoteOnly.length} version(s) the local folder lacks: ${remoteOnly.slice(0, 5).join(', ')}`);
  if (localOnly.length === 0) add('no_gap', `no local version is missing remotely (${pins.missingVersion} is already recorded)`);
  else if (localOnly.length !== 1 || localOnly[0] !== pins.missingVersion) {
    add('gap_mismatch', `the one missing version must be ${pins.missingVersion}; missing: ${localOnly.slice(0, 5).join(', ')}${localOnly.length > 5 ? ', ...' : ''}`);
  }
  for (const v of pins.laterHosted) if (!remoteSet.has(v)) add('later_missing', `the later hosted migration ${v} is not recorded`);
  const byVersion = new Map(state.ledger.map((r) => [r.version, r]));
  for (const [v, [name, digest]] of Object.entries(pins.storedStatements)) {
    const row = byVersion.get(v);
    if (!row) continue; // reported above
    if (row.name !== name) add('stored_name', `${v} is recorded under another name than ${name}`);
    if (row.n !== 1 || row.first !== digest) add('stored_statement', `${v} does not hold the one reviewed statement (SHA-256 ${digest})`);
  }
  const localNames = new Map(local.names.map((f) => [f.slice(0, 14), f.slice(15, -4)]));
  const renamed = state.ledger.filter((r) => localNames.has(r.version) && r.name !== null && r.name !== localNames.get(r.version));
  if (renamed.length) add('remote_name', `${renamed.length} remote version(s) carry another name than the local file: ${renamed.slice(0, 5).map((r) => r.version).join(', ')}`);
  const created = new Set(pins.functions.filter((f) => f[6] !== 'recreated').map((f) => f[0]));
  const partial = [
    ...state.functions.filter((f) => created.has(f.name)).map((f) => f.name),
    ...state.relations.map((r) => r.name), ...state.indexes, ...state.triggers,
  ];
  if (partial.length || state.cardRelations !== 0 || state.cardFunctions !== 0) {
    add('partial_001d', `001D objects already exist (${partial.length} pinned; card-named relations ${state.cardRelations}, functions ${state.cardFunctions}): migration repair is invalid and nothing is applied`);
  }
  for (const name of pins.functions.filter((f) => f[6] === 'recreated').map((f) => f[0])) {
    const found = state.functions.filter((f) => f.name === name);
    if (found.length !== 1) { add('recreated_missing', `${name} must exist exactly once before 001D re-creates it; found ${found.length}`); continue; }
    const f = found[0];
    // D-067: the body in its exact canonical LF form or, for six functions only, its exact reviewed legacy CRLF form.
    const form = recreatedBodyForm(f, name, pins);
    if (!form.ok) {
      const accepted = Object.hasOwn(pins.legacyCrlfBefore || {}, name) ? 'its canonical LF form or its exact reviewed legacy CRLF form' : 'its canonical LF form';
      add(form.code, `${name}: ${form.rule}; only ${accepted} is accepted, and a drifted or partly pre-applied body is never replaced silently`);
    }
    if (f.owner !== pins.owner) {
      add('recreated_drift', `${name}: its owner is not the pinned owner: a drifted or partly pre-applied function is never replaced silently`);
    }
    for (const [role, bit] of Object.entries(pins.recreated[name])) {
      if (f[role] !== bit) add('recreated_access', `${name}: EXECUTE for ${role} is ${f[role]} before 001D; the file sets ${bit}, so the hosted access differs from the pinned shape`);
    }
    // CR-EG-02: the exact pre-001D access (every grantee, privilege, grant option and grantor) of the sequential reference.
    if (!sameAccess(f.access, pins.access.recreated[name])) {
      add('recreated_access', `${name}: the exact access before 001D differs from the pinned sequential reference (${accessDiff(f.access, pins.access.recreated[name])})`);
    }
  }
  if (state.surfaceFunctions !== pins.surfaceFunctions.length || state.surfaceRelations !== pins.surfaceTables.length) {
    add('surfaces_missing', `the #379 / #380 / #382 surfaces are incomplete: ${state.surfaceFunctions} of ${pins.surfaceFunctions.length} functions, ${state.surfaceRelations} of ${pins.surfaceTables.length} tables`);
  }
  problems.push(...surface382Problems(state, pins));
  problems.push(...surface386Problems(state, pins));
  // D-067: a CR in any other selected function is refused (only six re-created functions have a legacy CRLF form); D-068 adds
  // #386's functions to the selected ones.
  const recreatedNames = new Set(pins.functions.filter((f) => f[6] === 'recreated').map((f) => f[0]));
  for (const f of [...state.functions.filter((x) => !(x && recreatedNames.has(x.name))), ...surface382Functions(state), ...surface386Functions(state)]) {
    const rule = lfOnlyRule(f);
    if (rule) add('selected_function_eol', `${selectedName(f, 'a selected function')}: ${rule}`);
  }
  // D-067: the Default ACL digest is this run's baseline (the second PRE and POST must read it again unchanged).
  if (!defaultAclShape(state.defaultAcl)) add('default_acl_unreadable', 'the Default ACL digest (row count and SHA-256) is missing or malformed');
  return problems;
}

const sameJson = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// POST checks on the read-only state, the normal dry run and the migration list.
export function evaluateExactGapPost({ pre, post, normal, list, local }, pins = EXACT_GAP) {
  if (!post || !Array.isArray(post.ledger)) return [['post_unreadable', 'the read-only POST state could not be read']];
  const problems = sessionProblems(post, 'POST');
  const add = (code, message) => problems.push([code, message]);
  const remote = post.ledger.map((r) => r.version);
  const remoteSet = new Set(remote);
  const localSet = new Set(local.versions);
  if (remote.length !== pins.localCount) add('post_count', `the remote ledger must hold ${pins.localCount} versions after the apply; it holds ${remote.length}`);
  const missing = local.versions.filter((v) => !remoteSet.has(v));
  const extra = remote.filter((v) => !localSet.has(v));
  if (missing.length || extra.length) add('post_versions', `local and remote versions differ: ${missing.length} missing remotely, ${extra.length} remote-only`);
  const rows = post.ledger.filter((r) => r.version === pins.missingVersion);
  if (rows.length !== 1 || rows[0].name !== pins.missingName || rows[0].n !== pins.missingRow.n || rows[0].all !== pins.missingRow.all) {
    add('post_001d_row', `${pins.missingVersion} must be recorded exactly once, as ${pins.missingName}, with the pinned ${pins.missingRow.n} statements`);
  }
  const before = new Map(pre.ledger.map((r) => [r.version, r]));
  const changed = post.ledger.filter((r) => before.has(r.version) && !sameJson(r, before.get(r.version)));
  if (changed.length) add('post_ledger_changed', `${changed.length} earlier ledger row(s) changed: ${changed.slice(0, 5).map((r) => r.version).join(', ')}`);
  const pending = normal && normal.code === 0 ? parsePending(normal.out) : null;
  if (!pending || pending.length !== 0) {
    add('post_normal_dry_run', `a normal dry run (no --include-all) must report the database up to date; exit ${normal ? normal.code : 'none'}, pending ${pending ? pending.length : 'unreadable'}`);
  }
  const listed = list && list.code === 0 ? parseMigrationList(list.out) : null;
  const divergent = listed ? listed.filter((r) => !r.local || r.local !== r.remote) : [];
  if (!listed || listed.length !== pins.localCount || divergent.length) {
    add('post_migration_list', `migration list must show ${pins.localCount} rows with equal local and remote versions; exit ${list ? list.code : 'none'}, rows ${listed ? listed.length : 'unreadable'}, divergent ${divergent.length}`);
  }
  if ([normal?.out, list?.out].some((o) => CLI_ADVICE.test(String(o ?? '')))) add('post_cli_advice', 'the CLI still suggests a repair, pull, reset or --include-all');
  for (const [name, src, secdef, config, volatility, language, group] of pins.functions) {
    const found = post.functions.filter((f) => f.name === name);
    if (found.length !== 1) { add('post_function', `${name}: ${found.length} definitions`); continue; }
    const f = found[0];
    if (f.kind !== 'f' || f.src !== src || f.secdef !== secdef || f.config !== config || f.volatility !== volatility || f.language !== language) {
      add('post_function', `${name}: the definition differs from the reviewed migration`);
    }
    // D-067: POST accepts only the canonical LF form: the raw (above) and the LF-normalized SHA-256 both the POST pin, no
    // CR and no lone CR. The legacy CRLF alternative of PRE is never consulted here.
    const eol = lfOnlyRule(f) ?? (f.src_lf !== src ? 'its LF-normalized body is not the POST pin' : null);
    if (eol) add('post_function_eol', `${name}: ${eol}; POST accepts only the canonical LF form`);
    if (f.owner !== pins.owner) add('post_owner', `${name}: owner ${f.owner}`);
    let want = GROUP_PRIVILEGES[group];
    if (group === 'recreated') {
      // PRE already required the bits the file sets, so all four must be unchanged.
      const old = pre.functions.find((p) => p.name === name) || {};
      want = { anon: old.anon, authenticated: old.authenticated, service_role: old.service_role, public: old.public };
    }
    for (const role of ['anon', 'authenticated', 'service_role', 'public']) {
      if (f[role] !== want[role]) add('post_privilege', `${name}: EXECUTE for ${role} is ${f[role]}, expected ${want[role]}`);
    }
    // CR-EG-02: the exact access of the sequential reference; the four bits above stay as readable diagnostics.
    const exact = group === 'recreated' ? pins.access.recreated[name] : pins.access.functions[group];
    if (!sameAccess(f.access, exact)) add('post_function_access', `${name}: the exact access differs from the pinned sequential reference (${accessDiff(f.access, exact)})`);
  }
  const relation = (name) => post.relations.find((r) => r.name === name);
  for (const name of pins.tables) {
    const r = relation(name);
    if (!r) { add('post_table', `${name} is missing`); continue; }
    const clientAccess = r.anon || r.authenticated || r.service_role || r.public;
    if (r.kind !== 'r' || !r.rls || !r.force_rls || r.owner !== pins.owner || clientAccess || !sameJson(r.policies, [pins.policy])) {
      add('post_table', `${name}: RLS, owner, client privileges or policies differ from the manifest`);
    }
    if (!sameAccess(r.access, pins.access.table)) add('post_table_access', `${name}: the exact table access differs from the pinned sequential reference (${accessDiff(r.access, pins.access.table)})`);
    if (!sameAccess(r.columns, pins.access.columns)) add('post_column_access', `${name}: a column grant differs from the pinned sequential reference (${accessDiff(r.columns, pins.access.columns)})`);
  }
  const seq = relation(pins.sequence);
  if (!seq || seq.kind !== 'S' || seq.anon || seq.authenticated || seq.service_role || seq.public) add('post_sequence', `${pins.sequence} is missing or reachable by a client role`);
  if (seq && !sameAccess(seq.access, pins.access.sequence)) {
    add('post_sequence_access', `${pins.sequence}: the exact sequence access differs from the pinned sequential reference (${accessDiff(seq.access, pins.access.sequence)})`);
  }
  if (seq && !sameAccess(seq.columns, pins.access.columns)) {
    add('post_sequence_access', `${pins.sequence}: a column grant differs from the pinned sequential reference (${accessDiff(seq.columns, pins.access.columns)})`);
  }
  const indexes = new Set(post.indexes);
  for (const name of pins.indexes) if (!indexes.has(name)) add('post_index', `${name} is missing`);
  const triggers = new Set(post.triggers);
  for (const name of pins.triggers) if (!triggers.has(`${name}:O`)) add('post_trigger', `${name} is missing or not enabled`);
  if (post.surfaceFunctions !== pre.surfaceFunctions || post.surfaceRelations !== pre.surfaceRelations) add('post_surfaces', 'the #379 / #380 / #382 surfaces changed');
  // REPIN-001: #382's whole surface (its relation, functions, Storage policies and their exact access) and the digest of
  // every policy on storage.objects are identical to PRE (which required the pins): nothing added, removed or changed.
  if (!post.surface382 || typeof post.surface382 !== 'object' || !sameJson(post.surface382, pre.surface382)) {
    add('post_surface382', '#382\'s surface (its relation, functions, Storage policies or any policy on storage.objects) is not identical to PRE');
  }
  // D-067: every #382 function stays canonical LF at POST as well.
  for (const f of surface382Functions(post)) {
    const rule = lfOnlyRule(f);
    if (rule) add('post_function_eol', `${selectedName(f, 'a #382 function')}: ${rule}; POST accepts only the canonical LF form`);
  }
  // D-068 (POST-386-REPIN-001): #386's whole surface (its functions, relations and triggers, with their exact access) is identical
  // to PRE (which required the pins): nothing added, removed or changed; and every #386 function stays canonical LF.
  if (!post.surface386 || typeof post.surface386 !== 'object' || !sameJson(post.surface386, pre.surface386)) {
    add('post_surface386', '#386\'s surface (its functions, relations, triggers or their exact access) is not identical to PRE');
  }
  for (const f of surface386Functions(post)) {
    const rule = lfOnlyRule(f);
    if (rule) add('post_function_eol', `${selectedName(f, 'a #386 function')}: ${rule}; POST accepts only the canonical LF form`);
  }
  // D-067: defaultAcl is compared with this run's own baseline, the first PRE's value (never a local reference).
  for (const key of ['otherFunctions', 'otherRelations', 'defaultAcl']) {
    if (!sameJson(post[key], pre[key])) add('post_unchanged', `${key} changed during the apply`);
  }
  return problems;
}

// Everything but the session block: the ledger, the manifest, the access, the digests and (REPIN-001) the PostgreSQL
// runtime, the TimeZone and #382's surface. Exported for the unit tests.
export const stateFingerprint = (state) => sha256(Buffer.from(JSON.stringify({ ...state, session: undefined }), 'utf8'));

// One CLI child with stdout kept apart (the query's JSON answer) as well as the merged text.
function runCliCapture(cli, args, env) {
  return new Promise((resolve) => {
    const child = spawn(cli, args, { env, shell: false, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    const all = [];
    const out = [];
    child.stdout.on('data', (c) => { all.push(c); out.push(c); });
    child.stderr.on('data', (c) => all.push(c));
    child.on('error', () => resolve({ code: -1, out: '', stdout: '' }));
    child.on('close', (code) => resolve({ code, out: Buffer.concat(all).toString('utf8'), stdout: Buffer.concat(out).toString('utf8') }));
  });
}

async function readExactGapState(run, cli, roUrl, workdir, env) {
  const dir = mkdtempSync(path.join(os.tmpdir(), 'bizbot-gr37-eg-'));
  try {
    const file = path.join(dir, 'state.sql');
    writeFileSync(file, exactGapStateSql(), { encoding: 'utf8', mode: 0o600 });
    const r = await run(cli, stateQueryArgs(roUrl, file, workdir), env);
    if (connectedLocally(r.out)) return { ok: false, local: true, code: r.code, out: '' };
    if (r.code !== 0) return { ok: false, code: r.code, out: r.out };
    const state = parseStateRows(r.stdout);
    return state ? { ok: true, state } : { ok: false, code: r.code, out: 'the query answer was not understood' };
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

export async function exactGapMain(argv, env, print, deps = {}) {
  const d = { run: runCliCapture, verifyCli, verifyPassfile: verifyExactGapPassfile, verifyCa, checkLocal: checkExactGapMigrations, ...deps };
  const pins = EXACT_GAP;
  const secrets = [env[ENV_URL], env[ENV_PASSFILE], env[ENV_SSLROOTCERT]];
  const say = (line) => print(redact(line, secrets));
  let pushed = false;
  try {
    const args = parseExactGapArgs(argv);
    refuseDebug(env);
    const target = parseTargetUrl(env[ENV_URL], args);
    if (args.mode === 'hosted') secrets.push(target.host, args.projectRef);
    const passfile = d.verifyPassfile(env[ENV_PASSFILE], target, args.workdir);
    secrets.push(passfile.secret, passfile.path, passfile.path.replace(/\\/g, '/'));
    const ca = d.verifyCa(env[ENV_SSLROOTCERT], args.mode, args.workdir);
    secrets.push(ca.path, ca.path.replace(/\\/g, '/'));
    const local = d.checkLocal(args.workdir);
    const cli = d.verifyCli(env[ENV_CLI]);
    secrets.push(cli, path.dirname(cli), args.workdir, args.workdir.replace(/\\/g, '/'));
    const childEnv = buildExactGapChildEnv(env, passfile.path, ca.path);
    const rwUrl = buildDbUrl(target);
    const roUrl = buildReadOnlyDbUrl(target);
    secrets.push(rwUrl, roUrl);
    print(redact(`gr37 exact-gap: mode ${EXACT_GAP_MODE}; ${args.mode} mode; read-only sessions ${readOnlyUrlShape(args.mode)}; the push ${urlShape(args.mode)}; PGSSLMODE=verify-full with ${args.mode === 'hosted' ? 'the accepted CA (pinned SHA-256 fingerprint)' : 'a disposable local test CA'}; password only from the owner-only passfile`, secrets, { maskUrls: false }));
    const version = await d.run(cli, ['--version'], childEnv);
    if (version.code !== 0 || version.out.replace(/\r/g, '').split('\n')[0].trim() !== CLI_VERSION) refuse('cli_version', `the CLI does not report ${CLI_VERSION}`);
    say(`gr37 exact-gap: Supabase CLI ${CLI_VERSION}; supabase.exe and supabase-go.exe match their pinned SHA-256`);
    say(`gr37 exact-gap: local folder = the pinned main set: ${local.files} migrations (names and bytes), ending ${pins.localTail.map(([n]) => n.slice(0, 14)).join(', ')}; ${pins.missingFile} has its reviewed SHA-256`);
    const read = async (label) => {
      const r = await readExactGapState(d.run, cli, roUrl, args.workdir, childEnv);
      if (r.local && !pushed) refuse('cli_local_database', 'the CLI connected to its local stack, which skips TLS; nothing was pushed');
      if (r.local) return { ok: false, code: r.code, out: '' };
      if (!r.ok) say(`gr37 exact-gap: the ${label} read-only state could not be read (exit ${r.code})\n${summarize(redact(r.out, secrets), true)}`);
      return r;
    };
    const first = await read('PRE');
    if (!first.ok) { say('RESULT: PRE_READ_FAILED (STOP: preserve the evidence; nothing was pushed; no retry)'); return 3; }
    const preProblems = evaluateExactGapPre(first.state, local);
    if (preProblems.length) {
      for (const [code, message] of preProblems) say(`gr37 exact-gap: PRE gate ${code}: ${message}`);
      refuse(preProblems[0][0], `${preProblems.length} PRE gate(s) failed; nothing was pushed`);
    }
    const s = first.state;
    say(`gr37 exact-gap: PRE (read-only session over TLS, PostgreSQL server_version_num ${s.runtime.server_version_num} and TimeZone ${s.runtime.time_zone}, as pinned): remote ledger ${s.ledger.length} versions ending ${pins.remoteTail.join(', ')}; the only gap is ${pins.missingVersion}; ${Object.keys(pins.storedStatements).join(', ')} each hold their one reviewed statement; ${s.ledger.filter((r) => r.name === null).length} earlier row(s) carry no name; no 001D object; the seven re-created functions in their pinned pre-001D form (body in its canonical LF or exact reviewed legacy CRLF form, owner and exact access); #379 / #380 / #382 surfaces present (${s.surfaceFunctions} functions, ${s.surfaceRelations} tables); #382's own surface as pinned (${pins.surface382.functions.length} functions, its relation and ${pins.surface382.policies.length} Storage policies: definition, owner and exact access); #386's own surface as pinned (${pins.surface386.functions.length} functions, ${pins.surface386.relations.length} relations and ${pins.surface386.triggers.length} triggers: definition, owner and exact access)`);
    // D-067: the form each re-created function was accepted in, and this run's Default ACL baseline (digests only).
    const forms = pins.functions.filter((f) => f[6] === 'recreated')
      .map(([name]) => `${name} ${recreatedBodyForm(s.functions.find((f) => f.name === name), name, pins).form}`);
    say(`gr37 exact-gap: PRE line endings (D-067): ${forms.join('; ')}; every other selected function canonical LF. Default ACL baseline for this run (never compared with a local reference): ${s.defaultAcl.count} rows, SHA-256 ${s.defaultAcl.sha256}. First PRE state fingerprint ${stateFingerprint(s)}`);
    const dry = await d.run(cli, exactGapDryRunArgs(roUrl, args.workdir), childEnv);
    if (connectedLocally(dry.out)) refuse('cli_local_database', 'the CLI connected to its local stack, which skips TLS; nothing was pushed');
    if (dry.code !== 0) {
      say(`gr37 exact-gap: the --include-all dry run failed (exit ${dry.code}); nothing was pushed\n${summarize(redact(dry.out, secrets), true)}`);
      say('RESULT: DRY_RUN_FAILED (STOP: preserve the evidence; no retry, no repair)');
      return 3;
    }
    const pending = parsePending(dry.out);
    if (!pending || pending.length !== 1 || pending[0] !== pins.missingFile) {
      refuse('pending_mismatch', `the --include-all dry run must list exactly ${pins.missingFile}; it lists ${pending ? pending.length : 'an unreadable answer'}`);
    }
    say(`gr37 exact-gap: the read-only --include-all dry run lists exactly ${pins.missingFile}, the read-only set difference`);
    // D-067: the second PRE, on both routes, after the dry run. The check route proves PRE 2 equality itself; on the apply
    // route it is the re-read immediately before the push.
    const label = args.apply ? 're-check' : 'second PRE';
    const when = args.apply ? 'at the re-read immediately before the push' : 'at the second PRE read, after the dry run';
    const second = await read(label);
    if (!second.ok) { say('RESULT: PRE_READ_FAILED (STOP: preserve the evidence; nothing was pushed; no retry)'); return 3; }
    // D-067, its review's F1: the second read's own session must be read-only, encrypted and carry the fixed startup
    // settings, as the first one's (the fingerprint leaves the session block out).
    const session = sessionProblems(second.state, label);
    if (session.length) refuse(session[0][0], `${session[0][1]} (${when}); nothing was pushed`);
    // REPIN-001: the PostgreSQL runtime and TimeZone are checked again, explicitly; the fingerprint covers them too.
    const drift = runtimeProblems(second.state, pins, label);
    if (drift.length) refuse(drift[0][0], `${drift[0][1]} (${when}); nothing was pushed`);
    // D-067: the Default ACL must be this run's baseline, exactly (the fingerprint covers it too).
    if (!defaultAclShape(second.state.defaultAcl) || !sameJson(second.state.defaultAcl, s.defaultAcl)) {
      refuse('default_acl_changed', `the Default ACL differs from this run's baseline, read by the first PRE (${when}); nothing was pushed`);
    }
    if (stateFingerprint(second.state) !== stateFingerprint(first.state)) {
      refuse('state_changed', args.apply ? 'the database changed between the PRE read and the push; nothing was pushed'
        : 'the database changed between the first and the second PRE read; nothing was pushed');
    }
    const equal = `the Default ACL equals this run's baseline; state fingerprint ${stateFingerprint(second.state)} equals the first PRE's`;
    if (!args.apply) {
      say(`gr37 exact-gap: second PRE (read-only, after the dry run): PostgreSQL runtime and TimeZone as pinned; ${equal}`);
      say('RESULT: CHECKED_EXACT_GAP (no --apply: nothing was pushed)');
      return 0;
    }
    // The last gate before the push: the local folder (migrations, config.toml, no dotenv, not linked) is re-checked.
    d.checkLocal(args.workdir);
    say(`gr37 exact-gap: re-read immediately before the push: PostgreSQL runtime and TimeZone as pinned; database unchanged; local folder unchanged; ${equal}`);
    const started = Date.now();
    pushed = true;
    const push = await d.run(cli, exactGapPushArgs(rwUrl, args.workdir), childEnv);
    say(`gr37 exact-gap: push --include-all (one attempt) exit ${push.code} after ${Date.now() - started} ms\n${summarize(redact(push.out, secrets), push.code !== 0)}`);
    const post = await read('POST');
    const normal = await d.run(cli, exactGapNormalDryRunArgs(roUrl, args.workdir), childEnv);
    const list = await d.run(cli, migrationListArgs(roUrl, args.workdir), childEnv);
    if (push.code !== 0) {
      if (post.ok) {
        const p = post.state;
        say(`gr37 exact-gap: after the failed push (read-only): remote ledger ${p.ledger.length} versions; ${pins.missingVersion} recorded ${p.ledger.some((r) => r.version === pins.missingVersion)}; 001D relations ${p.relations.length}, card-named functions ${p.cardFunctions}`);
      }
      say('RESULT: PUSH_FAILED (STOP: preserve the evidence; forward-fix only; no retry, no repair)');
      return 3;
    }
    const postProblems = post.ok ? evaluateExactGapPost({ pre: first.state, post: post.state, normal, list, local }) : [['post_unreadable', 'the read-only POST state could not be read']];
    if (postProblems.length) {
      for (const [code, message] of postProblems) say(`gr37 exact-gap: POST check ${code}: ${message}`);
      say('RESULT: POSTCHECK_MISMATCH (STOP: preserve the evidence; read the ledger read-only; no retry, no repair)');
      return 4;
    }
    say(`gr37 exact-gap: POST (read-only): remote ledger ${post.state.ledger.length} versions = the local set; ${pins.missingVersion} recorded once, as pinned (${pins.missingRow.n} statements); every earlier row unchanged; a normal dry run (no --include-all) reports the database up to date; migration list ${pins.localCount} rows, none divergent; 001D manifest: ${pins.functions.length} functions, ${pins.tables.length} tables (RLS forced, ${pins.policy.name} only), the sequence, ${pins.indexes.length} indexes and ${pins.triggers.length} triggers match, each function, table, column and the sequence with its exact pinned access; #382's surface, every storage.objects policy and #386's surface identical to PRE; every POST function in its canonical LF form; the catalog digests of every other app / public function and relation unchanged, and the Default ACL equal to this run's baseline`);
    say('RESULT: APPLIED_EXACT_GAP');
    return 0;
  } catch (error) {
    if (pushed) {
      say('gr37 exact-gap: an unexpected error stopped the post-check after the push');
      say('RESULT: POSTCHECK_MISMATCH (STOP: preserve the evidence; read the ledger read-only; no retry, no repair)');
      return 4;
    }
    if (error instanceof Refusal) {
      say(`REFUSED ${error.code}: ${error.message}`);
    } else {
      say('REFUSED internal_error: an unexpected error stopped the wrapper before any push');
    }
    return 2;
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === SELF) {
  main().then((code) => { process.exitCode = code; });
}
