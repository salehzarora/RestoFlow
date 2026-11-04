#!/usr/bin/env node
// GR-37 bounded migration apply (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D-MIGRATION-REORDER-001): the one approved route for
// applying the frozen 001D migration with finite lock and statement timeouts, outside the migration body.
// The installed Supabase CLI 2.107.0 ignores PGOPTIONS, so the three startup settings travel in the `options`
// parameter of a PASSWORDLESS --db-url; the password comes only from an owner-private PGPASSFILE; PGSSLMODE=require
// makes the CLI refuse a session without TLS. Nothing edits the SQL, writes the migration ledger by hand, passes
// --include-all, calls `migration repair` or retries the push.
// Inputs, from the environment only and never printed: BIZBOT_GR37_DB_URL (passwordless), BIZBOT_GR37_PASSFILE and
// BIZBOT_GR37_SUPABASE_CLI (the absolute path of the pinned supabase.exe).
// Usage: node tools/supabase/bounded-db-push.mjs --mode local|hosted [--project-ref <ref>] --workdir <dir> [--apply]
// Without --apply it stops after the dry run. Exit: 0 done; 2 refused, nothing pushed; 3 a CLI step failed;
// 4 the post-check does not match.
import { spawn, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { closeSync, openSync, readFileSync, readSync, readdirSync, realpathSync, statSync } from 'node:fs';
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

export function refuseDebug(env) {
  if (Object.keys(env).some((key) => /debug/i.test(key))) refuse('debug_refused', 'a debug environment variable is set');
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

// .pgpass syntax: host:port:database:user:password, with \: and \\ escapes.
export function parsePassfile(text) {
  const entries = [];
  for (const line of text.split(/\r?\n/)) {
    if (line === '' || line.startsWith('#')) continue;
    const fields = [];
    let current = '';
    let escaped = false;
    for (const ch of line) {
      if (escaped) { current += ch; escaped = false; } else if (ch === '\\') escaped = true;
      else if (ch === ':' && fields.length < 4) { fields.push(current); current = ''; } else current += ch;
    }
    fields.push(current);
    entries.push(fields.length === 5 && !escaped ? fields : null);
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
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
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

export function verifyPassfile(raw, target, workdir, { repoRoot = path.resolve(path.dirname(SELF), '..', '..') } = {}) {
  if (typeof raw !== 'string' || raw === '') refuse('passfile_missing', `${ENV_PASSFILE} is not set`);
  if (!path.isAbsolute(raw)) refuse('passfile_missing', 'the passfile path must be absolute');
  let real;
  let st;
  try { real = realpathSync(raw); st = statSync(real); } catch { refuse('passfile_missing', 'the passfile does not exist'); }
  if (!st.isFile()) refuse('passfile_missing', 'the passfile is not a regular file');
  let workReal;
  try { workReal = realpathSync(workdir); } catch { refuse('bad_arguments', 'the workdir does not exist'); }
  const where = passfileLocationProblem(real, { repoRoot: realpathSync(repoRoot), workdir: workReal });
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

// The CLI's verdict lines, not the SQL it echoes: on failure the error lines (a statement text can run to dozens of
// lines and push the error out of a plain tail), on success the apply lines.
export function summarize(text, failed, n = 8) {
  const all = text.replace(/\r/g, '').split('\n').filter((l) => l.trim() && !/new version of supabase cli|recommend updating/i.test(l));
  const signal = failed
    ? (l) => /^\s*(ERROR|FATAL)\b/.test(l)
      || /SQLSTATE|^\s*At statement|canceling statement|failed to connect|authentication failed|refused TLS|connection refused/i.test(l)
    : (l) => /Applying migration|Finished|up to date/i.test(l);
  const picked = all.filter(signal).slice(0, n);
  return (picked.length ? picked : all.slice(-n)).map((l) => `    ${l.trim().slice(0, 220)}`).join('\n');
}

export async function main(argv = process.argv.slice(2), env = process.env, print = (l) => process.stdout.write(`${l}\n`)) {
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
      say(`RESULT: PUSH_FAILED (STOP: preserve the evidence; forward-fix only; no retry, no repair)`);
      return 3;
    }
    if (!after || after.length !== 0) {
      say('RESULT: POSTCHECK_MISMATCH');
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

if (process.argv[1] && path.resolve(process.argv[1]) === SELF) {
  main().then((code) => { process.exitCode = code; });
}
