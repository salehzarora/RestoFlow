// BIZBOT-PAYMENTS-ZCREDIT-PILOT-001D: real independent PostgreSQL connections (the T-023 concurrency lane).
// pgTAP runs in one transaction and cannot show a lock wait; this runner proves the API_CONTRACT §4.55.3
// admission serialization with two to four live psql sessions (plus one observer): a claim and a push of one
// identity in both winning orders, rollback / retry, the advisory-lock sets, the terminal lock against the
// operator binding setter, the TEST purge barrier, concurrent claims (one identity; one order), the M9
// unique-index mapping, concurrent D-054 Resumes, Resume / claim / finish versus shift.close, a forced deadlock
// on the recording leg and a lock-order stress on an ordinary and a printer-only branch; and (C15–C22) a start
// against a retirement / rotation and an activation / retirement against a start, cash and hand-recorded card
// pushes against a retirement, concurrent pilot revisions, a session holding only the identity lock, the purge
// against a push / claim holding the terminal lock, a forced outbound-key collision with a purged identity,
// order.edit against a claim and the recording leg, and the credential-reference lock; and (C23–C25, with a
// TEST purge and an order.edit session added to the C13 stress rounds) a purge against a card_attempt_finish
// of an expired TEST attempt in both orders, the claim guard's membership FOR SHARE read against a concurrent
// role grant in both interleavings, and the recording-result freshness race of review fix 20; and (C26–C32,
// correction C1) the inactive-device shutdown (a claim against revoke_device_management in both orders, the
// drain / retirement of the revoked till's binding serialized on its terminal lock, retirement only after the
// operator resolution, a replacement till blocked until then), the bounded purge batch (a device outside the
// locked set, incident holds set and cleared against a purge, the pre-ledger TEST refusal against a purge, a
// forced failure rolling the whole batch back, each in both orders) and the support-authority transitions (a
// support session activated by another session between two context calls, a membership revoked between the
// context proof and the service-only write); and (C33, the C1 delta review) a batch's cut-off fixed before its
// terminal locks (a TEST attempt expiring while the batch waits on a held terminal lock survives that batch); and
// (C34–C39, correction C2: the authorization cutoff of D-060 point 2) a support session activated by another
// session against the original caller's binding — committed during the operation's lock wait (refused, nothing
// written) or after its final check (it stands; the next call is refused) — for the claim (terminal lock, orders
// row, replay), both marks, free_order and adapter_read, and app.sync_push's start-of-request guard; and (C40, the
// C2 self-review) the check right after the write-time proof of both marks, free_order and adapter_read (an
// activation committed while the proof waits never lets the resolver answer attempt_not_found); and (C41, the C2
// review) the claim's checks after its identity lock and after its shift / drawer locks, and change 7 refusing a
// support push while another session holds the terminal lock (no wait).
// Disposable LOCAL clone only: the migrated schema of the named container's `postgres` database is dumped
// (schema only, never a row) into a fresh zc001d_race_<creation epoch seconds>_<12 hex> database of the same
// container (dump /tmp/zc001d-race-<epoch>-<hex>.dump); the synthetic fixture and every write below go to that
// clone, which is dropped at the end, on SIGINT / SIGTERM too (then the exit code is 130 / 143). Before it
// starts, the run sweeps clones and dumps of that naming whose creation epoch is older than 6 hours (left by a
// killed run); a name without an epoch is never touched.
// productionContacted:false and providerRequests:0 in the evidence JSON are constants by construction, not
// measurements: this file has no backend URL, credential, HTTP client or provider transport, and every command
// it runs is `docker exec` into the allowlisted local container.
// Usage: node supabase/tests/support/run_bizbot_zcredit_001d_concurrency.mjs --container <name> [--fixture <path>]
//   <name>   supabase_db_BIZBOTZCREDIT001D (this task's disposable local stack, published on port 56422), or
//            supabase_db_RestoFlow only when GITHUB_ACTIONS=true, CI=true and GITHUB_RUN_ID is non-empty, and
//            only while that container publishes port 54322. Anything else is refused.
//   --fixture <path>  use that file's full text as the fixture instead of the default source: the prefix of
//            ../bizbot_zcredit_001d_claim_identity_test.sql from `begin;` up to the line
//            `-- ZC001D FIXTURE END:` (pg_temp.* is rewritten to the committed schema zc001d_fixture).
// Development only: ZC001D_SCENARIOS=C1,C3 runs a subset (the setup always runs).
// Pre-fix evidence only: ZC001D_SOURCE_DB=zc001d_prefix dumps the schema of the local container's pre-fix clone
//            database zc001d_prefix instead of `postgres` (allowlist postgres | zc001d_prefix, default postgres;
//            zc001d_prefix only with the local container). It is only read, like `postgres`.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';

const LOCAL_CONTAINER = 'supabase_db_BIZBOTZCREDIT001D';
const LOCAL_DB_PORT = '56422';
const CI_CONTAINER = 'supabase_db_RestoFlow';
const CI_DB_PORT = '54322';
const STALE_AFTER_SECONDS = 6 * 60 * 60;
const RACE_DATABASE = /^zc001d_race_([0-9]{10})_[0-9a-f]{12}$/;
const RACE_DUMP_FILE = /^zc001d-race-([0-9]{10})-[0-9a-f]{12}\.dump$/;
const FIXTURE_MARKER = '-- ZC001D FIXTURE END:';
const F = 'zc001d_fixture';
const STRESS_ROUNDS = 12;
const STRESS_SEED = 0x2c001d;

// ---------------------------------------------------------------------------------------------------------
// Arguments and the target allowlist (refused before any process starts).
// ---------------------------------------------------------------------------------------------------------
const argv = process.argv.slice(2);
let container = null;
let fixturePath = null;
for (let i = 0; i < argv.length; i += 2) {
  const [flag, value] = [argv[i], argv[i + 1]];
  assert.ok(typeof value === 'string' && value.length > 0 && !value.startsWith('--'),
    `usage: --container <name> [--fixture <path>] (missing value after ${flag})`);
  if (flag === '--container' && container === null) container = value;
  else if (flag === '--fixture' && fixturePath === null) fixturePath = value;
  else assert.fail(`usage: --container <name> [--fixture <path>] (unexpected ${flag})`);
}
assert.ok(container !== null, 'usage: --container <name> [--fixture <path>]');
const ciRun = process.env.GITHUB_ACTIONS === 'true' && process.env.CI === 'true';
const ciRunId = (process.env.GITHUB_RUN_ID ?? '').trim();
assert.ok(container === LOCAL_CONTAINER || (ciRun && container === CI_CONTAINER),
  `refused: only ${LOCAL_CONTAINER} (this task's disposable local stack) or, inside GitHub Actions CI, ${CI_CONTAINER}`);
assert.ok(container !== CI_CONTAINER || ciRunId !== '', `refused: ${CI_CONTAINER} also requires a non-empty GITHUB_RUN_ID`);
const expectedDbPort = container === LOCAL_CONTAINER ? LOCAL_DB_PORT : CI_DB_PORT;
const dockerHost = process.env.DOCKER_HOST ?? '';
assert.ok(dockerHost === '' || /^(unix|npipe):\/\//.test(dockerHost), 'refused: DOCKER_HOST names a non-local Docker daemon');
const only = (process.env.ZC001D_SCENARIOS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const wants = (key) => only.length === 0 || only.includes(key);
// The database whose migrated schema is cloned: `postgres` (default) or, for the pre-fix evidence run only, the
// local container's pre-fix candidate clone zc001d_prefix. Anything else is refused before any process starts.
const SOURCE_DATABASES = ['postgres', 'zc001d_prefix'];
const sourceDatabase = (process.env.ZC001D_SOURCE_DB ?? '').trim() || 'postgres';
assert.ok(SOURCE_DATABASES.includes(sourceDatabase),
  `refused: ZC001D_SOURCE_DB must be one of ${SOURCE_DATABASES.join(' | ')} (default postgres)`);
assert.ok(sourceDatabase === 'postgres' || container === LOCAL_CONTAINER,
  `refused: ZC001D_SOURCE_DB=${sourceDatabase} exists only in ${LOCAL_CONTAINER}`);
let interrupted = null; // the signal name once SIGINT / SIGTERM arrived (no scenario starts after it)

// The clone and dump names carry their creation epoch (seconds), so a later run's sweep can tell their age.
const createdEpoch = Math.floor(Date.now() / 1000);
const nonceHex = randomBytes(6).toString('hex');
const database = `zc001d_race_${createdEpoch}_${nonceHex}`;
const dumpFile = `zc001d-race-${createdEpoch}-${nonceHex}.dump`;
const dumpPath = `/tmp/${dumpFile}`;
assert.match(database, RACE_DATABASE);
assert.match(dumpFile, RACE_DUMP_FILE);

// ---------------------------------------------------------------------------------------------------------
// Process helpers: every command is `docker exec` into the allowlisted container (no host database client).
// ---------------------------------------------------------------------------------------------------------
const lit = (v) => `'${String(v).replaceAll("'", "''")}'`;
const jlit = (value) => `${lit(JSON.stringify(value))}::jsonb`;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const handled = (promise) => { promise.catch(() => {}); return promise; };
const md5Hex = (text) => createHash('md5').update(text).digest('hex');
const md5Uuid = (text) => {
  const h = md5Hex(text);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
};
// The fixture's zc_id(label) / zc_lop(label), computed locally to compare returned identifiers.
const nodeId = (label) => md5Uuid(`bizbot-zcredit-001d-synthetic-${label}`);
const nodeLop = (label) => {
  const h = md5Hex(`bizbot-zcredit-001d-lop-${label}`);
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
};
const TRANSPORT_SUB = nodeId('transport-principal');

function docker(args, { input = '', timeoutMs = 120_000 } = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn('docker', args, { shell: false, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    let stdout = '';
    let stderr = '';
    const timer = setTimeout(() => { p.kill(); reject(new Error(`timeout: docker ${args.slice(0, 4).join(' ')}`)); }, timeoutMs);
    p.stdout.setEncoding('utf8').on('data', (x) => { stdout += x; });
    p.stderr.setEncoding('utf8').on('data', (x) => { stderr += x; });
    p.on('error', (e) => { clearTimeout(timer); reject(e); });
    p.on('close', (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(stdout.trim());
      else reject(new Error(`docker ${args.slice(0, 4).join(' ')} exited ${code}: ${stderr.trim()}`));
    });
    p.stdin.on('error', () => {});
    p.stdin.end(input);
  });
}
const psqlArgs = (db) => ['exec', '-i', container, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1'];

// One long-lived psql connection to the race database. Statements are sent with an \echo marker (the
// platform-353 / POS-inbox precedent); application_name and the backend pid identify it in pg_stat_activity.
const sessions = new Set();
let ops = null;
class Session {
  constructor(name, init = '') {
    assert.match(name, /^zc_[a-z0-9_]{1,50}$/);
    this.name = name;
    this.sequence = 0;
    this.pending = null;
    this.stderr = '';
    this.exited = false;
    this.pid = null;
    this.child = spawn('docker', psqlArgs(database), { shell: false, stdio: ['pipe', 'pipe', 'pipe'], windowsHide: true });
    this.child.stderr.setEncoding('utf8').on('data', (x) => { this.stderr += x; });
    createInterface({ input: this.child.stdout }).on('line', (line) => {
      if (!this.pending) return;
      if (line === this.pending.marker) {
        const { resolve, rows, timer } = this.pending;
        clearTimeout(timer);
        this.pending = null;
        resolve(rows);
      } else if (line.trim() !== '') this.pending.rows.push(line);
    });
    this.child.on('error', (e) => this.fail(e));
    this.child.stdin.on('error', (e) => this.fail(e));
    this.exit = new Promise((resolve) => this.child.on('close', () => {
      this.exited = true;
      sessions.delete(this);
      this.fail(new Error(`${this.name}: psql exited: ${this.stderr.trim() || 'no stderr'}`));
      resolve();
    }));
    sessions.add(this);
    this.ready = handled(this.query(`set application_name = ${lit(name)}; set statement_timeout = '60s';
set request.jwt.claim.sub = ${lit(TRANSPORT_SUB)}; ${init}
select pg_backend_pid();`).then((rows) => {
      assert.equal(rows.length, 1);
      this.pid = Number(rows[0]);
      assert.ok(Number.isInteger(this.pid) && this.pid > 0);
      return this;
    }));
  }

  fail(error) {
    if (!this.pending) return;
    const { reject, timer } = this.pending;
    clearTimeout(timer);
    this.pending = null;
    reject(error);
  }

  query(text, timeoutMs = 60_000) {
    assert.equal(this.pending, null, `${this.name}: one statement at a time`);
    if (this.exited) return handled(Promise.reject(new Error(`${this.name}: exited: ${this.stderr.trim()}`)));
    return handled(new Promise((resolve, reject) => {
      const marker = `__zc001d_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error(`${this.name}: statement timed out`)), timeoutMs);
      this.pending = { marker, rows: [], timer, resolve, reject };
      // Every statement is terminated, so psql never leaves it in its buffer behind the \echo marker.
      this.child.stdin.write(`${/;\s*$/.test(text) ? text : `${text};`}\n\\echo ${marker}\n`);
    }));
  }

  one(text, timeoutMs) {
    return handled(this.query(text, timeoutMs).then((rows) => {
      assert.equal(rows.length, 1, `${this.name}: expected one row, got ${rows.length}: ${rows.join(' | ')}`);
      return rows[0];
    }));
  }

  json(text, timeoutMs) { return handled(this.one(text, timeoutMs).then((row) => JSON.parse(row))); }

  async close() {
    if (this.exited) return;
    if (this.pending && this.pid && ops && ops !== this && !ops.exited && !ops.pending) {
      // A statement still waits (a failed scenario): end only this race-database backend.
      await ops.query(`select pg_terminate_backend(a.pid) from pg_stat_activity a where a.pid = ${this.pid}
        and a.datname = ${lit(database)} and a.application_name = ${lit(this.name)};`).catch(() => {});
    }
    if (!this.child.stdin.writableEnded) this.child.stdin.end('rollback;\n\\q\n');
    const killer = setTimeout(() => this.child.kill(), 10_000);
    await this.exit;
    clearTimeout(killer);
  }
}

// ---------------------------------------------------------------------------------------------------------
// SQL vocabulary over the committed fixture schema (staff / device numbering of the shared fixture).
// ---------------------------------------------------------------------------------------------------------
const id = (label) => `${F}.zc_id(${lit(label)})`;
const lop = (label) => `${F}.zc_lop(${lit(label)})`;
const ORG = `${F}.zc_org()`;
const OWNER = `${F}.zc_owner()`;
const dev = (d) => id(`device-${d}`);
const ord = (label) => id(`order-${label}`);
const APPROVED = { error_flag: false, provider_return_code: 0, approval_type: 'approved',
  provider_status_code: 'ok1', provider_return_class: 'approved' };
const LOOKUP_APPROVED = { ...APPROVED, provider_amount: '12.34', provider_currency: 'ILS' };
const DECLINED = { approval_type: 'declined', provider_return_class: 'declined' };
const claimLive = (n, label, orderLabel, amount = 1234, rev = 1) =>
  `${F}.zc_claim(${n}, ${lop(label)}, 'live', ${amount}, ${ord(orderLabel)}, ${rev})`;
const claimTest = (n, label, amount = 1234) => `${F}.zc_claim(${n}, ${lop(label)}, 'test', ${amount})`;
const finish = (claim, source, outcome, fields = {}, poll = null) =>
  `${F}.zc_finish(${jlit(claim)}, ${lit(source)}, ${lit(outcome)}, ${jlit(fields)}${poll ? `, ${lit(poll)}` : ''})`;
const payOp = (label, orderLabel, tender = 'card', amount = 1234, extra = null) =>
  `${F}.zc_pay_op(${lop(label)}, ${ord(orderLabel)}, ${lit(tender)}, ${amount}${extra ? `, ${jlit(extra)}` : ''})`;
const closeOp = (label, shiftId) => `jsonb_build_object('local_operation_id', ${lop(label)},
  'operation_type', 'shift.close', 'target_entity', 'shift', 'target_id', ${lit(shiftId)}::uuid,
  'client_created_at', '2026-10-24T00:00:00Z', 'payload', jsonb_build_object('shift_id', ${lit(shiftId)}::uuid,
  'counted_amount_minor', 0, 'reason', 'ZC001D synthetic close'))`;
const voidOp = (label, orderLabel) => `jsonb_build_object('local_operation_id', ${lop(label)},
  'operation_type', 'order.void', 'target_entity', 'order', 'target_id', ${ord(orderLabel)},
  'client_created_at', '2026-10-24T00:00:00Z', 'payload', jsonb_build_object('order_id', ${ord(orderLabel)},
  'reason', 'ZC001D synthetic void'))`;
const push = (n, op) => `${F}.zc_push(${n}, jsonb_build_array(${op}))`;
const freeOrder = (label) => `public.card_attempt_free_order(${id('pin-2')}, ${dev(1)}, 'zc-token-1', ${lop(label)},
  'ZC001D synthetic free', 'provider_report', ${lit(`zc-report-${label}`)}, ${F}.zc_caller())`;
const markRefused = (label, token) => `public.card_attempt_mark_recording_result(${id('pin-1')}, ${dev(1)},
  'zc-token-1', ${lop(label)}, ${lit(token)}, ${F}.zc_caller())`;
const setTerminal = (d, mode, lifecycle, reason) => `app.set_payment_terminal(${dev(d)}, ${lit(mode)},
  ${lit(`zc-term-${mode}-${d}`)}, ${lit(`zc-cred-${mode}-${d}`)}, ${lit(lifecycle)}, ${lit(reason)},
  'ZC001D synthetic binding', 'zc001d-op/ref-2', ${OWNER})`;
// Role framing: the adapter's service client, the POS (authenticated), and uncommitted variants.
const svc = (expr) => `set role service_role; select (${expr})::text; reset role;`;
const pos = (expr) => `set role authenticated; select (${expr})::text; reset role;`;
const svcTx = (expr) => `begin; set local role service_role; select (${expr})::text;`;
const posTx = (expr) => `begin; set local role authenticated; select (${expr})::text;`;
// The §4.55.3 advisory keys, computed by the database exactly as the bodies compute them.
const terminalKeySql = (d) => `hashtextextended('card-terminal/v1:' || ${ORG}::text || ':' || ${dev(d)}::text, 0)::text`;
const identityKeySql = (d, label) =>
  `hashtextextended('card-identity/v1:' || ${ORG}::text || ':' || ${dev(d)}::text || ':' || ${lop(label)}, 0)::text`;
const PURGE_KEY_SQL = `hashtextextended('card-purge/v1', 0)::text`;

const pick = (o, keys) => Object.fromEntries(keys.map((k) => [k, o?.[k] ?? null]));
const lockSet = (locks) => locks.map((l) => `${l.key}/${l.mode}/${l.granted ? 'granted' : 'waiting'}`).sort();
const count = async (text) => Number(await ops.one(text));
const keyValues = (map) => ops.json(`select jsonb_build_object(${Object.entries(map)
  .map(([k, e]) => `${lit(k)}, ${e}`).join(', ')})::text`);
const advisoryLocks = (session) => ops.json(`select coalesce(jsonb_agg(jsonb_build_object(
  'key', ((l.classid::bigint << 32) | l.objid::bigint)::text, 'mode', l.mode, 'granted', l.granted,
  'objsubid', l.objsubid)), '[]'::jsonb)::text from pg_locks l where l.pid = ${session.pid} and l.locktype = 'advisory'`);
const attempt = (d, label) => ops.json(`select coalesce((select to_jsonb(a) - 'provider_status_digest'
  - 'provider_duplicate_digest' from app.card_provider_attempts a where a.organization_id = ${ORG}
  and a.device_id = ${dev(d)} and a.local_operation_id = ${lop(label)}), 'null'::jsonb)::text`);
const derived = (d, label) => ops.json(`select coalesce((select app.card_attempt_derive(a)
  from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(d)}
  and a.local_operation_id = ${lop(label)}), 'null'::jsonb)::text`);
const syncRow = (d, label) => ops.json(`select coalesce((select jsonb_build_object('status', so.status,
  'rejection_reason', so.rejection_reason, 'last_error_class', so.last_error_class, 'last_error_code',
  so.last_error_code, 'retry_count', so.retry_count) from public.sync_operations so where so.organization_id = ${ORG}
  and so.device_id = ${dev(d)} and so.local_operation_id = ${lop(label)}), 'null'::jsonb)::text`);
const paymentsUnder = (d, label) => count(`select count(*) from public.payments p
  where p.device_id = ${dev(d)} and p.local_operation_id = ${lop(label)}`);
const orderPayments = (label) => count(`select count(*) from public.payments p where p.order_id = ${ord(label)}
  and p.status = 'completed' and p.deleted_at is null`);
const shiftStatus = (shiftId) => ops.one(`select s.status from public.shifts s where s.id = ${lit(shiftId)}::uuid`);
const closeBlocked = (shiftId) => ops.one(`select app.card_shift_close_blocked(${ORG}, ${lit(shiftId)}::uuid)::text`);
const makeOrders = (...labels) => ops.query(`select count(*) from (select ${F}.zc_order(l)
  from unnest(array[${labels.map(lit).join(', ')}]::text[]) l) x;`);
const deadlocks = () => count('select deadlocks from pg_stat_database where datname = current_database()');

// Test-only shift rotation in the race database (no guard exists on shifts): close the device's open shift
// and drawer directly and open a fresh pair, so a scenario's attempts are the only ones frozen to its shift.
async function rotateShift(label) {
  return ops.one(`begin;
update public.cash_drawer_sessions c set status = 'closed', closed_at = clock_timestamp()
 where c.organization_id = ${ORG} and c.device_id = ${dev(1)} and c.status in ('opened', 'active', 'counting');
update public.shifts s set status = 'closed', closed_at = clock_timestamp()
 where s.organization_id = ${ORG} and s.device_id = ${dev(1)} and s.status in ('opening', 'open', 'closing');
insert into public.shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id,
                           resolved_membership_id, local_operation_id, status)
values (${id(`shift-1-${label}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(1)}, ${id('employee-1')},
        ${id('membership-1')}, ${lit(`zc001d-shift-1-${label}`)}, 'open');
insert into public.cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id,
                                         opened_by_employee_profile_id, opening_float_minor, local_operation_id)
values (${id(`drawer-1-${label}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(1)}, ${id(`shift-1-${label}`)},
        ${id('employee-1')}, 0, ${lit(`zc001d-drawer-1-${label}`)});
commit;
select ${id(`shift-1-${label}`)}::text;`);
}

// Proves that `waiter` is blocked on a lock held by `blocker`: pg_stat_activity (by pid and application_name)
// reports wait_event_type 'Lock' and pg_blocking_pids names the blocker, while the statement is unfinished.
async function provenWait(waiter, pending, blocker, events) {
  let settled = false;
  let outcome = null; // how the statement settled, for the failure message only
  pending.then((value) => { settled = true; outcome = `answered ${String(JSON.stringify(value)).slice(0, 160)}`; },
    (error) => { settled = true; outcome = `raised ${String(error?.message ?? error).slice(0, 160)}`; });
  const deadline = Date.now() + 15_000;
  let seen = null;
  while (Date.now() < deadline) {
    seen = await ops.json(`select coalesce((select jsonb_build_object('wait_event_type', a.wait_event_type,
      'wait_event', a.wait_event, 'blockers', to_jsonb(pg_blocking_pids(a.pid))) from pg_stat_activity a
      where a.pid = ${waiter.pid} and a.application_name = ${lit(waiter.name)} and a.datname = ${lit(database)}),
      '{}'::jsonb)::text`);
    if (seen.wait_event_type === 'Lock' && Array.isArray(seen.blockers) && seen.blockers.includes(blocker.pid)) {
      assert.ok(events.includes(seen.wait_event), `${waiter.name} waits on ${seen.wait_event}; expected ${events.join(' | ')}`);
      return { waiter: waiter.name, blocker: blocker.name, wait_event_type: seen.wait_event_type, wait_event: seen.wait_event };
    }
    assert.equal(settled, false,
      `${waiter.name} finished before a lock wait on ${blocker.name} was observed (${JSON.stringify(seen)}; it ${outcome})`);
    await sleep(15);
  }
  return assert.fail(`${waiter.name} was never observed waiting on ${blocker.name} (${JSON.stringify(seen)})`);
}

// Resolves `promise` or fails if it does not settle in `ms` (a statement that must NOT wait).
async function within(promise, ms, message) {
  let timer;
  const timeout = new Promise((_, reject) => { timer = setTimeout(() => reject(new Error(message)), ms); });
  try { return await Promise.race([promise, timeout]); } finally { clearTimeout(timer); }
}

// ---------------------------------------------------------------------------------------------------------
// Scenario bookkeeping.
// ---------------------------------------------------------------------------------------------------------
const results = [];
class Scenario {
  constructor(key) { this.key = key; this.assertions = 0; this.detail = {}; this.opened = []; }
  eq(actual, expected, message) { this.assertions += 1; assert.deepStrictEqual(actual, expected, `CC-${this.key}: ${message}`); }
  ok(value, message) { this.assertions += 1; assert.ok(value, `CC-${this.key}: ${message}`); }
  async open(label, init = '') {
    const s = new Session(`zc_${this.key.toLowerCase()}_${label}`, init);
    this.opened.push(s);
    return s.ready;
  }
}
async function scenario(key, title, body) {
  if (!wants(key) || interrupted !== null) return;
  if (ops.exited) ops = await new Session(`zc_ops_${results.length}`).ready; // a failed scenario killed it
  const sc = new Scenario(key);
  const started = Date.now();
  try {
    await body(sc);
    results.push({ name: `CC-${key} ${title}`, pass: true, detail: { assertions: sc.assertions, ms: Date.now() - started, ...sc.detail } });
  } catch (error) {
    results.push({ name: `CC-${key} ${title}`, pass: false,
      detail: { assertions: sc.assertions, error: String(error?.message ?? error), ...sc.detail } });
  } finally {
    for (const s of sc.opened) await s.close();
  }
  const last = results[results.length - 1];
  process.stderr.write(`[zc001d] ${last.pass ? 'PASS' : 'FAIL'} ${last.name}${last.pass ? '' : ` -- ${last.detail.error}`}\n`);
}

const SYNC_RESULT_KEYS = ['error', 'idempotency_replay', 'local_operation_id', 'ok', 'operation_type', 'status'];

// ---------------------------------------------------------------------------------------------------------
// C5 (TEST phase, runs first): the purge barrier against a claim of the purged identity.
// ---------------------------------------------------------------------------------------------------------
async function c5PurgeBarrier(sc) {
  const t1 = await ops.json(svc(claimTest(8, 'c5-t1')));
  sc.eq([t1.ok, t1.claim_created, t1.state, t1.mode, t1.classification], [true, true, 'sent', 'test', 'test_sent'],
    'TEST claim of identity T on d2 committed');
  const aged = await ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
with u as (update app.card_provider_attempts a set retention_until = clock_timestamp() - interval '1 second'
            where a.id = ${lit(t1.attempt_row_id)}::uuid returning 1) select count(*) from u;
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
  sc.eq(aged, ['1'], 'race database only: T aged past its retention (frozen-fact trigger bypassed for that UPDATE)');
  const k = await keyValues({ t1: terminalKeySql(1), t2: terminalKeySql(2), purge: PURGE_KEY_SQL });
  await makeOrders('c5');
  const A = await sc.open('purger');
  const B = await sc.open('same_identity');
  const C = await sc.open('barrier_probe');
  const D = await sc.open('purged_push');
  const purged = await A.json(`begin; select app.purge_expired_test_card_attempts('ZC001D synthetic purge',
    'zc001d-op/ref-3', ${OWNER})::text;`);
  sc.eq([purged.ok, purged.attempts_purged], [true, 1], 'A: the TEST purge deletes T and keeps its tombstone (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([{ key: k.t2, mode: 'ExclusiveLock', granted: true },
    { key: k.purge, mode: 'ExclusiveLock', granted: true }]), 'A holds the d2 terminal lock and the EXCLUSIVE purge barrier');
  const sameP = B.json(svc(claimTest(8, 'c5-t1')));
  sc.detail.purged_identity_claim_wait = await provenWait(B, sameP, A, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([{ key: k.t2, mode: 'ExclusiveLock', granted: false }]),
    'B (claim of the purged identity) waits on the d2 terminal lock the purge holds');
  const probeP = C.json(svc(claimTest(1, 'c5-t2')));
  sc.detail.barrier_probe_wait = await provenWait(C, probeP, A, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(C)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: true },
    { key: k.purge, mode: 'ShareLock', granted: false }]),
  'C (a claim on another device) holds its own terminal lock and waits for the SHARED purge barrier');
  const eventsBefore = await count(`select count(*) from app.card_provider_private_events e
    where e.action = 'test.card_recording_refused'`);
  const pushedP = D.json(pos(push(8, payOp('c5-t1', 'c5'))));
  sc.detail.purged_identity_push_wait = await provenWait(D, pushedP, A, ['advisory']);
  await A.query('commit;');
  const same = await sameP;
  const probe = await probeP;
  const pushed = (await pushedP).results[0];
  sc.eq(pick(pushed, ['ok', 'error', 'status', 'idempotency_replay']),
    { ok: false, error: 'test_attempt_not_recordable', status: 'rejected', idempotency_replay: false },
    'D (payment.create of the purged identity): refused pre-ledger once the tombstone committed');
  sc.eq(await count(`select count(*) from app.card_provider_private_events e where e.action = 'test.card_recording_refused'`),
    eventsBefore, 'D: a tombstoned identity writes no private event');
  sc.eq(await syncRow(2, 'c5-t1'), null, 'D: no sync_operations row');
  sc.eq(pick(same, ['ok', 'error', 'detail']), { ok: false, error: 'conflict', detail: 'identity_in_use' },
    'B: conflict / identity_in_use (it read the committed tombstone)');
  sc.eq(Object.keys(same).sort(), ['detail', 'error', 'ok', 'server_ts'], 'B: typed refusal, no attempt fact');
  sc.eq(pick(probe, ['ok', 'error']), { ok: false, error: 'card_payments_disabled' },
    'C: proceeds after the barrier is released (card_payments_disabled: d1 has no binding)');
  sc.eq(await count(`select count(*) from app.card_attempt_identity_tombstones t where t.organization_id = ${ORG}
    and t.device_id = ${dev(2)} and t.local_operation_id = ${lop('c5-t1')}`), 1, 'one tombstone keeps T');
  sc.eq(await count(`select count(*) from app.card_provider_attempts a
    where a.local_operation_id in (${lop('c5-t1')}, ${lop('c5-t2')})`), 0, 'no attempt row for T or the probe');
  sc.eq(await count(`select count(*) from app.card_provider_private_events e
    where e.action = 'operator.card_test_attempts_purged'`), 1, 'one purge operator event');
  sc.detail.answers = { purged_identity_claim: same.detail, barrier_probe: probe.error };
}

// ---------------------------------------------------------------------------------------------------------
// C14 (TEST phase): concurrent pushes of a TEST identity are refused before the ledger step, with at most
//      one private test.card_recording_refused per attempt (checked under the identity lock).
// ---------------------------------------------------------------------------------------------------------
async function c14TestPushes(sc) {
  await makeOrders('c14');
  const t = await ops.json(svc(claimTest(8, 'c14-t')));
  sc.eq([t.ok, t.claim_created, t.mode], [true, true, 'test'], 'TEST claim of identity T on d2 committed');
  const k = await keyValues({ t2: terminalKeySql(2), identity: identityKeySql(2, 'c14-t') });
  const A = await sc.open('first_push');
  const B = await sc.open('second_push');
  const first = (await A.json(posTx(push(8, payOp('c14-t', 'c14'))))).results[0];
  sc.eq(pick(first, ['ok', 'error', 'status', 'idempotency_replay', 'local_operation_id', 'operation_type', 'order_id']),
    { ok: false, error: 'test_attempt_not_recordable', status: 'rejected', idempotency_replay: false,
      local_operation_id: nodeLop('c14-t'), operation_type: 'payment.create', order_id: nodeId('order-c14') },
    'A: pre-ledger TEST refusal (uncommitted)');
  sc.eq(Object.keys(first).sort(), ['error', 'idempotency_replay', 'local_operation_id', 'ok', 'operation_type', 'order_id',
    'server_ts', 'status'], 'A: exactly the contract shape');
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([{ key: k.t2, mode: 'ExclusiveLock', granted: true },
    { key: k.identity, mode: 'ExclusiveLock', granted: true }]), 'A holds the d2 terminal lock and the identity lock of T');
  const secondP = B.json(pos(push(8, payOp('c14-t', 'c14'))));
  sc.detail.second_push_wait = await provenWait(B, secondP, A, ['advisory']);
  await A.query('commit;');
  const second = (await secondP).results[0];
  sc.eq(pick(second, ['ok', 'error', 'status', 'idempotency_replay']),
    { ok: false, error: 'test_attempt_not_recordable', status: 'rejected', idempotency_replay: false }, 'B: the same refusal');
  sc.eq(await count(`select count(*) from app.card_provider_private_events e where e.action = 'test.card_recording_refused'
    and e.attempt_row_id = ${lit(t.attempt_row_id)}::uuid`), 1, 'exactly one private refusal event for the attempt');
  sc.eq(await syncRow(2, 'c14-t'), null, 'no sync_operations row');
  sc.eq(await count(`select count(*) from public.audit_events e where e.new_values ->> 'local_operation_id' = ${lop('c14-t')}`), 0,
    'no tenant audit row');
  sc.eq(await paymentsUnder(2, 'c14-t'), 0, 'no payment');
  // Resolve the attempt so the TEST binding can be retired at the end of the TEST phase.
  sc.eq((await ops.json(svc(finish(t, 'commit', 'declined', DECLINED)))).state, 'declined', 'cleanup: the TEST attempt is declined');
}

// ---------------------------------------------------------------------------------------------------------
// C4: the terminal admission lock against the operator binding setter (drain, activation, retirement,
//     rotation), both orders.
// ---------------------------------------------------------------------------------------------------------
const setTerminalRefs = (term, cred, lifecycle, reason) => `app.set_payment_terminal(${dev(1)}, 'live', ${lit(term)},
  ${lit(cred)}, ${lit(lifecycle)}, ${lit(reason)}, 'ZC001D synthetic binding', 'zc001d-op/ref-2', ${OWNER})`;
const bindingRows = () => ops.one(`select string_agg(t.terminal_ref || ':' || t.lifecycle, ',' order by t.created_at, t.id)
  from app.payment_terminals t where t.device_id = ${dev(1)}`);

async function c4TerminalVsOperator(sc) {
  await makeOrders('c4a', 'c4b', 'c4c');
  const k = await keyValues({ t1: terminalKeySql(1) });
  const A = await sc.open('claim');
  const B = await sc.open('operator');
  // (1) a drain commits first: the claim serialized after it sees the committed mapping.
  const drained = await B.json(`begin; select ${setTerminal(1, 'live', 'draining', 'incident')}::text;`);
  sc.eq(pick(drained, ['ok', 'prior_lifecycle', 'new_lifecycle']), { ok: true, prior_lifecycle: 'enabled', new_lifecycle: 'draining' },
    '(1) B: drain of the d1 binding (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: true }]),
    '(1) the setter holds exactly the d1 terminal lock (never the purge barrier)');
  const lateP = A.json(svc(claimLive(1, 'c4-x0', 'c4c')));
  sc.detail.claim_waits_for_drain = await provenWait(A, lateP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: false }]),
    '(1) A (claim) waits on the d1 terminal lock held by the drain');
  await B.query('commit;');
  sc.eq(pick(await lateP, ['ok', 'error']), { ok: false, error: 'card_payments_disabled' }, '(1) A: card_payments_disabled after the drain committed');
  sc.eq(await attempt(1, 'c4-x0'), null, '(1) no attempt row for the refused start');
  // (2) an activation commits first: the claim serialized after it is admitted.
  const activated = await B.json(`begin; select ${setTerminal(1, 'live', 'enabled', 'live_activation')}::text;`);
  sc.eq(pick(activated, ['ok', 'prior_lifecycle', 'new_lifecycle']), { ok: true, prior_lifecycle: 'draining', new_lifecycle: 'enabled' },
    '(2) B: LIVE activation (uncommitted; no unresolved attempt, no backlog)');
  const admittedP = A.json(svc(claimLive(1, 'c4-x1', 'c4a')));
  sc.detail.claim_waits_for_activation = await provenWait(A, admittedP, B, ['advisory']);
  await B.query('commit;');
  const admitted = await admittedP;
  sc.eq(pick(admitted, ['ok', 'claim_created', 'state']), { ok: true, claim_created: true, state: 'sent' },
    '(2) A: admitted once the activation committed');
  // (3) a claim commits first: the drain waits; activation and retirement see the committed attempt; a
  //     credential rotation (the atomic replacement) needs no gate and leaves the attempts' frozen references.
  const claimed = await A.json(svcTx(claimLive(1, 'c4-x2', 'c4b')));
  sc.eq([claimed.ok, claimed.claim_created, claimed.state], [true, true, 'sent'], '(3) A: fresh LIVE claim (uncommitted)');
  const drainP = B.json(`begin; select ${setTerminal(1, 'live', 'draining', 'incident')}::text;`);
  sc.detail.drain_waits_for_claim = await provenWait(B, drainP, A, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: false }]),
    '(3) B (drain) waits on the d1 terminal lock held by the claim');
  await A.query('commit;');
  sc.eq(pick(await drainP, ['ok', 'prior_lifecycle', 'new_lifecycle']), { ok: true, prior_lifecycle: 'enabled', new_lifecycle: 'draining' },
    '(3) B: the drain succeeds once the claim committed');
  const activation = await B.json(`select ${setTerminal(1, 'live', 'enabled', 'live_activation')}::text;`);
  sc.eq(pick(activation, ['ok', 'error', 'detail']), { ok: false, error: 'precondition_failed', detail: 'attempt_unresolved' },
    '(3) B (same transaction): LIVE activation sees the committed attempt and is refused');
  const retirement = await B.json(`select ${setTerminal(1, 'live', 'retired', 'end_of_pilot')}::text;`);
  sc.eq(pick(retirement, ['ok', 'error', 'detail']), { ok: false, error: 'precondition_failed', detail: 'attempt_unresolved' },
    '(3) B (same transaction): retirement sees the committed attempt and is refused');
  const rotated = await B.json(`select ${setTerminalRefs('zc-term-live-1r', 'zc-cred-live-1r', 'configured', 'rotation')}::text;`);
  sc.eq(pick(rotated, ['ok', 'replaced', 'prior_lifecycle', 'new_lifecycle']),
    { ok: true, replaced: true, prior_lifecycle: 'draining', new_lifecycle: 'configured' },
    '(3) B (same transaction): the rotation replaces the draining row');
  await B.query('commit;');
  sc.eq(await bindingRows(), 'zc-term-live-1:retired,zc-term-live-1r:configured', '(3) old row retired, new row configured');
  sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.device_id = ${dev(1)}
    and a.local_operation_id in (${lop('c4-x1')}, ${lop('c4-x2')}) and a.terminal_ref = 'zc-term-live-1'
    and a.credential_ref = 'zc-cred-live-1'`), 2, '(3) the unresolved attempts keep their frozen references');
  sc.eq(pick(await A.json(svc(claimLive(1, 'c4-x3', 'c4c'))), ['ok', 'error']), { ok: false, error: 'card_payments_disabled' },
    '(3) a start after the rotation sees a configured (not enabled) binding');
  // Restore the original binding for the following scenarios: resolve the attempts, then activate,
  // drain and rotate back, and activate the original references again.
  for (const c of [admitted, claimed]) {
    sc.eq((await ops.json(svc(finish(c, 'commit', 'declined', DECLINED)))).state, 'declined', 'cleanup: attempt declined');
  }
  for (const [term, cred, lifecycle, reason] of [['zc-term-live-1r', 'zc-cred-live-1r', 'enabled', 'live_activation'],
    ['zc-term-live-1r', 'zc-cred-live-1r', 'draining', 'rotation'], ['zc-term-live-1', 'zc-cred-live-1', 'configured', 'rotation'],
    ['zc-term-live-1', 'zc-cred-live-1', 'enabled', 'live_activation']]) {
    const step = await ops.json(`select ${setTerminalRefs(term, cred, lifecycle, reason)}::text`);
    sc.eq([step.ok, step.new_lifecycle], [true, lifecycle], `cleanup: ${term} -> ${lifecycle}`);
  }
  sc.eq(await bindingRows(), 'zc-term-live-1:retired,zc-term-live-1r:retired,zc-term-live-1:enabled',
    'cleanup: the original references are enabled again on a new row');
}

// ---------------------------------------------------------------------------------------------------------
// C3: the advisory-lock set of an uncommitted claim.
// ---------------------------------------------------------------------------------------------------------
async function c3ClaimLocks(sc) {
  await makeOrders('c3');
  const k = await keyValues({ terminal: terminalKeySql(1), identity: identityKeySql(1, 'c3-x'), purge: PURGE_KEY_SQL });
  const A = await sc.open('claim');
  const claimed = await A.json(svcTx(claimLive(1, 'c3-x', 'c3')));
  sc.eq([claimed.ok, claimed.claim_created], [true, true], 'A: fresh LIVE claim (uncommitted)');
  const held = await advisoryLocks(A);
  sc.eq(lockSet(held), lockSet([{ key: k.terminal, mode: 'ExclusiveLock', granted: true },
    { key: k.identity, mode: 'ExclusiveLock', granted: true }, { key: k.purge, mode: 'ShareLock', granted: true }]),
  'pg_locks: exactly the terminal and full-identity advisory locks (exclusive) and the purge barrier (shared)');
  sc.eq(held.map((l) => l.objsubid), [1, 1, 1], 'each is a single 64-bit advisory key');
  sc.detail.locks = held.map((l) => ({ key: l.key, mode: l.mode, granted: l.granted,
    kind: l.key === k.terminal ? 'card-terminal/v1' : l.key === k.identity ? 'card-identity/v1' : 'card-purge/v1' }));
  await A.query('commit;');
  sc.eq(await advisoryLocks(A), [], 'transaction-scoped: all three released at commit');
}

// ---------------------------------------------------------------------------------------------------------
// C1: one identity, a claim and a push, both winning orders.
// ---------------------------------------------------------------------------------------------------------
async function c1IdentityBothOrders(sc) {
  await makeOrders('c1', 'c1r-cash', 'c1r-claim');
  const k = await keyValues({ t1: terminalKeySql(1), y: identityKeySql(1, 'c1-y') });
  const A = await sc.open('claim');
  const B = await sc.open('push');
  // (1) the claim first.
  const claimed = await A.json(svcTx(claimLive(1, 'c1-x', 'c1')));
  sc.eq([claimed.ok, claimed.claim_created, claimed.state], [true, true, 'sent'], 'A: fresh LIVE claim of X (uncommitted)');
  const legP = B.json(pos(push(1, payOp('c1-x', 'c1'))));
  sc.detail.push_waits_for_claim = await provenWait(B, legP, A, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: false }]),
    'B (payment.create of X) waits on the d1 terminal lock held by the claim');
  await A.query('commit;');
  const leg = (await legP).results[0];
  sc.eq(pick(leg, ['ok', 'error', 'detail', 'status', 'idempotency_replay', 'order_id']),
    { ok: false, error: 'provider_recording_refused', detail: 'attempt_not_approved', status: 'rejected',
      idempotency_replay: false, order_id: nodeId('order-c1') }, 'B: the committed claim wins (identity-first gate)');
  sc.eq(Object.keys(leg).sort(), [...SYNC_RESULT_KEYS, 'detail', 'order_id', 'server_ts'].sort(), 'B: no attempt fact in the refusal');
  sc.eq(pick(await syncRow(1, 'c1-x'), ['status', 'rejection_reason']), { status: 'rejected', rejection_reason: 'provider_recording_refused' },
    'the push is memoized rejected');
  sc.eq(await paymentsUnder(1, 'c1-x'), 0, 'no payment under X');
  sc.eq(pick(await attempt(1, 'c1-x'), ['state', 'mode']), { state: 'sent', mode: 'live' }, 'the attempt is unchanged');
  // (2) the push first.
  const cash = (await B.json(posTx(push(1, payOp('c1-y', 'c1r-cash', 'cash', 2000))))).results[0];
  sc.eq([cash.ok, cash.status], [true, 'applied'], 'B: cash payment.create of Y applied (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: true },
    { key: k.y, mode: 'ExclusiveLock', granted: true }]),
  'B (app.sync_push) holds the d1 terminal lock and the full-identity lock of Y (never the purge barrier)');
  const claimP = A.json(svc(claimLive(1, 'c1-y', 'c1r-claim')));
  sc.detail.claim_waits_for_push = await provenWait(A, claimP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([{ key: k.t1, mode: 'ExclusiveLock', granted: false }]),
    'A (claim of Y) waits on the d1 terminal lock held by the push');
  await B.query('commit;');
  const lost = await claimP;
  sc.eq(pick(lost, ['ok', 'error', 'detail']), { ok: false, error: 'conflict', detail: 'identity_in_use' },
    'A: conflict / identity_in_use (the committed push owns Y)');
  sc.eq(Object.keys(lost).sort(), ['detail', 'error', 'ok', 'server_ts'], 'A: typed refusal, no attempt fact');
  sc.eq(await attempt(1, 'c1-y'), null, 'no attempt row for Y');
  sc.eq(await paymentsUnder(1, 'c1-y'), 1, 'exactly the one cash payment under Y');
}

// ---------------------------------------------------------------------------------------------------------
// C2: the first transaction rolls back; the second gets its ordinary outcome; the loser's retry the same answer.
// ---------------------------------------------------------------------------------------------------------
async function c2RollbackRetry(sc) {
  await makeOrders('c2a', 'c2b-cash', 'c2b-claim');
  const A = await sc.open('claim');
  const B = await sc.open('push');
  // (1) a claim rolls back while the push of its identity waits.
  const claimed = await A.json(svcTx(claimLive(1, 'c2-x', 'c2a')));
  sc.eq([claimed.ok, claimed.claim_created], [true, true], 'A: fresh LIVE claim of X (uncommitted)');
  const legP = B.json(pos(push(1, payOp('c2-x', 'c2a'))));
  sc.detail.push_waits_for_claim = await provenWait(B, legP, A, ['advisory']);
  await A.query('rollback;');
  const leg = (await legP).results[0];
  sc.eq(pick(leg, ['ok', 'error', 'status']), { ok: false, error: 'card_terminal_required', status: 'rejected' },
    'B: the ordinary outcome of a hand-recorded card on a LIVE terminal till (no attempt exists)');
  const retry = await A.json(svc(claimLive(1, 'c2-x', 'c2a')));
  sc.eq(pick(retry, ['ok', 'error', 'detail']), { ok: false, error: 'conflict', detail: 'identity_in_use' },
    "A's retry: identity_in_use (the push committed a sync row)");
  sc.eq(await attempt(1, 'c2-x'), null, 'no attempt row for X');
  sc.eq(await paymentsUnder(1, 'c2-x'), 0, 'no payment under X');
  // (2) a push rolls back while the claim of its identity waits.
  const cash = (await B.json(posTx(push(1, payOp('c2-y', 'c2b-cash', 'cash', 2000))))).results[0];
  sc.eq([cash.ok, cash.status], [true, 'applied'], 'B: cash payment.create of Y applied (uncommitted)');
  const claimP = A.json(svc(claimLive(1, 'c2-y', 'c2b-claim')));
  sc.detail.claim_waits_for_push = await provenWait(A, claimP, B, ['advisory']);
  await B.query('rollback;');
  const won = await claimP;
  sc.eq(pick(won, ['ok', 'claim_created', 'replayed', 'state']), { ok: true, claim_created: true, replayed: false, state: 'sent' },
    'A: the ordinary outcome, a fresh claim of Y');
  const again = (await B.json(pos(push(1, payOp('c2-y', 'c2b-cash', 'cash', 2000))))).results[0];
  sc.eq(pick(again, ['ok', 'error', 'detail', 'status']),
    { ok: false, error: 'provider_recording_refused', detail: 'attempt_not_approved', status: 'rejected' },
    "B's retry: the same answer as a push after a committed claim");
  sc.eq(await paymentsUnder(1, 'c2-y'), 0, 'no payment under Y');
  sc.eq(await orderPayments('c2b-cash'), 0, 'the rolled-back cash payment left nothing');
}

// ---------------------------------------------------------------------------------------------------------
// C6 / C7: concurrent claims of one identity, and of two identities for one order.
// ---------------------------------------------------------------------------------------------------------
async function c6SameIdentity(sc) {
  await makeOrders('c6', 'c6b', 'c6c');
  const A = await sc.open('first');
  const B = await sc.open('second');
  const first = await A.json(svcTx(claimLive(1, 'c6-x', 'c6')));
  sc.eq([first.ok, first.claim_created, first.replayed], [true, true, false], 'A: fresh claim (uncommitted)');
  const secondP = B.json(svc(claimLive(1, 'c6-x', 'c6')));
  sc.detail.same_identity_wait = await provenWait(B, secondP, A, ['advisory']);
  await A.query('commit;');
  const second = await secondP;
  sc.eq(pick(second, ['ok', 'claim_created', 'replayed', 'state', 'attempt_id', 'attempt_row_id']),
    { ok: true, claim_created: false, replayed: true, state: 'sent', attempt_id: nodeLop('c6-x'), attempt_row_id: first.attempt_row_id },
    "B: the replay of A's committed row (claimed after A, no second commit call)");
  sc.eq(['provider_query_key', 'provider_duplicate_key', 'provider_key_format_version'].filter((x) => x in second), [],
    'B: no outbound key (only the inserting request receives them)');
  sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.local_operation_id = ${lop('c6-x')}`), 1, 'one row');
  // A concurrent loser whose frozen fields differ answers conflict.
  const third = await A.json(svcTx(claimLive(1, 'c6-y', 'c6b')));
  sc.eq([third.ok, third.claim_created], [true, true], 'A: fresh claim of Y for order c6b (uncommitted)');
  const otherP = B.json(svc(claimLive(1, 'c6-y', 'c6c')));
  sc.detail.different_fields_wait = await provenWait(B, otherP, A, ['advisory']);
  await A.query('commit;');
  sc.eq(pick(await otherP, ['ok', 'error', 'attempt_id', 'attempt_state']),
    { ok: false, error: 'conflict', attempt_id: nodeLop('c6-y'), attempt_state: 'sent' }, 'B: same identity, another order → conflict');
  sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.local_operation_id = ${lop('c6-y')}
    and a.order_id = ${ord('c6b')}`), 1, "one row, still A's order");
}

async function c7OneOrder(sc) {
  await makeOrders('c7');
  const A = await sc.open('first');
  const B = await sc.open('second');
  const first = await A.json(svcTx(claimLive(1, 'c7-x', 'c7')));
  sc.eq([first.ok, first.claim_created], [true, true], 'A: fresh claim of X for the order (uncommitted)');
  const secondP = B.json(svc(claimLive(1, 'c7-y', 'c7')));
  sc.detail.second_identity_wait = await provenWait(B, secondP, A, ['advisory']);
  await A.query('commit;');
  const second = await secondP;
  sc.eq(pick(second, ['ok', 'error']), { ok: false, error: 'payment_in_progress' }, 'B: payment_in_progress (one claim per order)');
  sc.eq(Object.keys(second).sort(), ['error', 'ok', 'server_ts'], 'B: no attempt fact');
  sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.order_id = ${ord('c7')}`), 1, 'one attempt row for the order');
  sc.eq(await attempt(1, 'c7-y'), null, 'no row for Y');
}

// ---------------------------------------------------------------------------------------------------------
// C8 (M9): a colliding outbound key committed by another connection while the claim waits on the unique index.
// ---------------------------------------------------------------------------------------------------------
async function c8PlantedKey(sc) {
  await makeOrders('c8');
  const defs = await ops.json(`select jsonb_object_agg(c.conname, pg_get_constraintdef(c.oid))::text from pg_constraint c
    where c.conrelid = 'app.card_provider_attempts'::regclass and c.conname in ('card_attempts_keys', 'card_attempts_digests')`);
  sc.eq(Object.keys(defs).sort(), ['card_attempts_digests', 'card_attempts_keys'], 'both CHECK definitions captured');
  await ops.query('alter table app.card_provider_attempts drop constraint card_attempts_keys, drop constraint card_attempts_digests;');
  let A = null;
  try {
    const zKey = await ops.one(`select app.card_provider_key(app.card_identity_digest('card-status-key/v1', ${ORG}, ${dev(1)},
      ${lop('c8-z')}), 'alpha16-l32-v1')`);
    sc.ok(/^[a-p]{32}$/.test(zKey), "Z's would-be query key computed by the claim's own formatter");
    A = await sc.open('planter');
    const B = await sc.open('claim');
    const planted = await A.one(`begin;
insert into app.card_provider_attempts (organization_id, restaurant_id, branch_id, device_id, local_operation_id,
    initiated_by_employee_profile_id, initiated_by_membership_id, mode, state, amount_minor, currency_code,
    terminal_ref, credential_ref, provider_status_digest, provider_duplicate_digest, provider_key_format_version,
    provider_query_key, provider_duplicate_key, retention_until, start_deadline_at)
select ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(1)}, ${lop('c8-w')}, ${id('employee-1')}, ${id('membership-1')},
       'test', 'sent', 1234, 'ILS', 'zc-term-live-1', 'zc-cred-live-1', w.sd, w.dd, 'alpha16-l32-v1', ${lit(zKey)},
       app.card_provider_key(w.dd, 'alpha16-l32-v1'), clock_timestamp() - interval '1 second',
       clock_timestamp() + interval '120 seconds'
  from (select app.card_identity_digest('card-status-key/v1', ${ORG}, ${dev(1)}, ${lop('c8-w')}) sd,
               app.card_identity_digest('card-duplicate-key/v1', ${ORG}, ${dev(1)}, ${lop('c8-w')}) dd) w
returning id::text;`);
    const claimP = B.json(svc(claimLive(1, 'c8-z', 'c8')));
    sc.detail.claim_waits_on_unique_index = await provenWait(B, claimP, A, ['transactionid']);
    await A.query('commit;');
    const refused = await claimP;
    sc.eq(pick(refused, ['ok', 'error', 'detail']), { ok: false, error: 'conflict', detail: 'identity_in_use' },
      'B: the unique violation on the query key is mapped to conflict / identity_in_use');
    sc.eq(Object.keys(refused).sort(), ['detail', 'error', 'ok', 'server_ts'], 'B: typed, no SQLSTATE, no attempt fact');
    sc.ok(!/duplicate key|unique/i.test(B.stderr), 'B: no raw unique-violation surfaced');
    sc.eq(await attempt(1, 'c8-z'), null, 'no row for Z');
    sc.eq(await B.one('select 1;'), '1', "B's connection continues (the violation was contained)");
    // The insert guard re-stamps a TEST row's retention to created_at + 90 days, so the planted row is not
    // purgeable: remove it with the frozen-fact trigger bypassed for this one DELETE (race database only).
    sc.eq(await ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
with d as (delete from app.card_provider_attempts a where a.id = ${lit(planted)}::uuid returning 1) select count(*) from d;
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`), ['1'], 'cleanup (race database only): the planted row deleted with the guard trigger bypassed');
  } finally {
    // Whatever happened above: end the planter's transaction, remove the planted row, restore both CHECKs.
    if (A && !A.exited && !A.pending) await A.query('rollback;').catch(() => {});
    await ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
delete from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(1)}
  and a.local_operation_id = ${lop('c8-w')};
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
    await ops.query(`alter table app.card_provider_attempts add constraint card_attempts_keys ${defs.card_attempts_keys},
      add constraint card_attempts_digests ${defs.card_attempts_digests};`);
  }
  sc.eq(await count(`select count(*) from pg_constraint c where c.conrelid = 'app.card_provider_attempts'::regclass
    and c.conname in ('card_attempts_keys', 'card_attempts_digests') and c.convalidated`), 2, 'cleanup: both CHECKs restored, validated');
}

// ---------------------------------------------------------------------------------------------------------
// C9: concurrent D-054 Resumes of one rejected recording leg; then a Resume against the recording-result
//     report, against a Resume of another attempt frozen to the same shift, and against shift.close.
// ---------------------------------------------------------------------------------------------------------
async function refusedApprovedLeg(sc, label, orderLabel) {
  const claimed = await ops.json(svc(claimLive(1, label, orderLabel)));
  sc.eq([claimed.ok, claimed.claim_created], [true, true], `${label}: claimed`);
  const approved = await ops.json(svc(finish(claimed, 'commit', 'approved', APPROVED)));
  sc.eq(approved.state, 'approved', `${label}: approved`);
  const kitchen = (await ops.json(pos(push(4, payOp(label, orderLabel))))).results[0];
  sc.eq(pick(kitchen, ['ok', 'error', 'status']), { ok: false, error: 'permission_denied', status: 'rejected' },
    `${label}: the leg pushed under a kitchen PIN session is memoized permission_denied`);
  const marked = await ops.json(svc(markRefused(label, 'permission_denied')));
  sc.eq(pick(marked, ['refusal_code', 'classification', 'recoverable', 'resume_count']),
    { refusal_code: 'permission_denied', classification: 'approved_unrecorded', recoverable: true, resume_count: 0 },
    `${label}: the refusal is reported; recoverable`);
  return claimed;
}

async function c9ConcurrentResumes(sc) {
  await makeOrders('c9', 'c9b', 'c9r', 'c9c-1', 'c9c-2');
  await refusedApprovedLeg(sc, 'c9-x', 'c9');
  const A = await sc.open('manager');
  const B = await sc.open('owner');
  const resume = payOp('c9-x', 'c9', 'card', 1234, { recording_resume: 0 });
  const first = (await A.json(posTx(push(2, resume)))).results[0];
  sc.eq(pick(first, ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    'A (manager): the Resume reopens and records the same row (uncommitted)');
  const secondP = B.json(pos(push(9, resume)));
  sc.detail.second_resume_wait = await provenWait(B, secondP, A, ['advisory']);
  await A.query('commit;');
  const second = (await secondP).results[0];
  sc.eq(pick(second, ['status', 'idempotency_replay', 'payment_id']), { status: 'applied', idempotency_replay: true, payment_id: first.payment_id },
    'B (owner, same recording_resume 0): answered by the recorded replay');
  sc.eq('resume_denied' in second, false, 'B: no second reopen');
  sc.eq(await paymentsUnder(1, 'c9-x'), 1, 'exactly one dispatch recorded');
  sc.eq(pick(await attempt(1, 'c9-x'), ['recording_resume_count']), { recording_resume_count: 1 }, 'the Resume count moved once');
  sc.eq(await ops.one(`select jsonb_array_length(a.recording_resume_history)::text || '/' ||
    jsonb_array_length(a.recording_refusal_history)::text from app.card_provider_attempts a
    where a.organization_id = ${ORG} and a.device_id = ${dev(1)} and a.local_operation_id = ${lop('c9-x')}`), '1/1',
  'one authorized-dispatch entry, one prior refusal entry');
  sc.eq(await count(`select count(*) from public.audit_events e where e.action = 'card_attempt.recording_resume_requested'
    and e.new_values ->> 'local_operation_id' = ${lop('c9-x')} and e.new_values ->> 'outcome' = 'dispatched'`), 1,
  'one dispatched Resume audit');
  sc.eq((await derived(1, 'c9-x')).classification, 'recorded', 'the attempt is recorded (strict join)');
  // Recording-result versus Resume: serial on the identity's sync row; the late report sees the recording.
  await refusedApprovedLeg(sc, 'c9r-x', 'c9r');
  const reported = pick(await attempt(1, 'c9r-x'), ['refusal_code', 'recording_refused_at']);
  const reports = () => count(`select count(*) from public.audit_events e where e.action = 'card_attempt.recording_refused'
    and e.device_id = ${dev(1)}`);
  const reportsBefore = await reports();
  const D = await sc.open('adapter');
  const resumedR = (await A.json(posTx(push(2, payOp('c9r-x', 'c9r', 'card', 1234, { recording_resume: 0 }))))).results[0];
  sc.eq(pick(resumedR, ['ok', 'status']), { ok: true, status: 'applied' }, 'A: a Resume records (uncommitted)');
  const reportP = D.json(svc(markRefused('c9r-x', 'permission_denied')));
  sc.detail.recording_result_waits_for_resume = await provenWait(D, reportP, A, ['transactionid', 'tuple']);
  await A.query('commit;');
  const report = await reportP;
  sc.eq(pick(report, ['ok', 'state', 'classification', 'recorded', 'payment_id']),
    { ok: true, state: 'approved', classification: 'recorded', recorded: true, payment_id: resumedR.payment_id },
    'D (mark_recording_result): answers the recorded envelope after the Resume committed, no write');
  sc.eq(await reports() - reportsBefore, 0, 'no recording_refused audit for the late report');
  const afterResume = pick(await attempt(1, 'c9r-x'), ['refusal_code', 'recording_refused_at', 'recording_resume_count']);
  sc.eq({ ...afterResume, reported_at_present: typeof reported.recording_refused_at === 'string' },
    { refusal_code: 'permission_denied', recording_refused_at: reported.recording_refused_at, recording_resume_count: 1,
      reported_at_present: true },
  'review fix 6: the authorized Resume keeps the reported refusal_code / recording_refused_at unchanged (the guard no '
    + 'longer clears them) and moves only the Resume count');
  // Two Resumes for different attempts frozen to one shift: serial, both record, no cycle.
  await refusedApprovedLeg(sc, 'c9c-x', 'c9c-1');
  await refusedApprovedLeg(sc, 'c9c-y', 'c9c-2');
  const firstX = (await A.json(posTx(push(2, payOp('c9c-x', 'c9c-1', 'card', 1234, { recording_resume: 0 }))))).results[0];
  sc.eq(pick(firstX, ['ok', 'status']), { ok: true, status: 'applied' }, 'A: Resume of X records (uncommitted)');
  const secondYP = B.json(pos(push(9, payOp('c9c-y', 'c9c-2', 'card', 1234, { recording_resume: 0 }))));
  sc.detail.other_attempt_resume_wait = await provenWait(B, secondYP, A, ['advisory']);
  await A.query('commit;');
  const secondY = (await secondYP).results[0];
  sc.eq(pick(secondY, ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    "B: Resume of Y records after A's commit");
  sc.eq([await paymentsUnder(1, 'c9c-x'), await paymentsUnder(1, 'c9c-y')], [1, 1], 'one payment each');
  // Resume versus shift.close: serial on the shift row; the close then sees the recorded attempt.
  const shift = await rotateShift('s9b');
  await refusedApprovedLeg(sc, 'c9b-x', 'c9b');
  sc.eq(await closeBlocked(shift), 'true', 'the approved, unrecorded attempt blocks its frozen shift');
  const C = await sc.open('closer');
  const resumed = (await A.json(posTx(push(2, payOp('c9b-x', 'c9b', 'card', 1234, { recording_resume: 0 }))))).results[0];
  sc.eq(pick(resumed, ['ok', 'status']), { ok: true, status: 'applied' }, 'A: the Resume records (uncommitted)');
  const closeP = C.json(pos(push(3, closeOp('c9b-close', shift))));
  sc.detail.close_waits_for_resume = await provenWait(C, closeP, A, ['transactionid', 'tuple']);
  await A.query('commit;');
  const closed = (await closeP).results[0];
  sc.eq(pick(closed, ['ok', 'status']), { ok: true, status: 'applied' }, 'C: the close proceeds after the recording committed');
  sc.eq(await shiftStatus(shift), 'closed', 'the shift is closed');
  sc.eq(await paymentsUnder(1, 'c9b-x'), 1, 'one payment under the identity');
  await rotateShift('after-c9');
}

// ---------------------------------------------------------------------------------------------------------
// C10: claim versus shift.close, both orders.
// ---------------------------------------------------------------------------------------------------------
async function c10ClaimVsClose(sc) {
  const s1 = await rotateShift('s10a');
  await makeOrders('c10a', 'c10b');
  const A = await sc.open('claim');
  const B = await sc.open('close');
  const claimed = await A.json(svcTx(claimLive(1, 'c10-x', 'c10a')));
  sc.eq([claimed.ok, claimed.claim_created], [true, true], 'A: fresh claim frozen to the shift (uncommitted)');
  const closeP = B.json(pos(push(3, closeOp('c10-close-a', s1))));
  sc.detail.close_waits_for_claim = await provenWait(B, closeP, A, ['transactionid', 'tuple']);
  await A.query('commit;');
  const refused = (await closeP).results[0];
  sc.eq(pick(refused, ['ok', 'error', 'status', 'shift_id']), { ok: false, error: 'card_payment_in_progress', status: 'rejected', shift_id: s1 },
    'B (manager of another till): card_payment_in_progress once the claim committed');
  sc.eq(Object.keys(refused).sort(), [...SYNC_RESULT_KEYS, 'server_ts', 'shift_id'].sort(), 'no attempt fact in the close refusal');
  sc.eq(await shiftStatus(s1), 'open', 'the shift stays open');
  const s2 = await rotateShift('s10b');
  const closed = (await B.json(posTx(push(3, closeOp('c10-close-b', s2))))).results[0];
  sc.eq(pick(closed, ['ok', 'status']), { ok: true, status: 'applied' }, 'B: the close of an unblocked shift (uncommitted)');
  const claimP = A.json(svc(claimLive(1, 'c10-y', 'c10b')));
  sc.detail.claim_waits_for_close = await provenWait(A, claimP, B, ['transactionid', 'tuple']);
  await B.query('commit;');
  const late = await claimP;
  sc.eq(pick(late, ['ok', 'error', 'detail']), { ok: false, error: 'precondition_failed', detail: 'no_open_shift' },
    'A: no_open_shift once the close committed');
  sc.eq(await attempt(1, 'c10-y'), null, 'no attempt row');
  sc.eq(await shiftStatus(s2), 'closed', 'the shift is closed');
  await rotateShift('after-c10');
}

// ---------------------------------------------------------------------------------------------------------
// C11: a provider finish and a close are not lock-serialized; the close decides on the committed state.
// ---------------------------------------------------------------------------------------------------------
async function freedAttempt(sc, label, orderLabel) {
  const claimed = await ops.json(svc(claimLive(1, label, orderLabel)));
  sc.eq([claimed.ok, claimed.claim_created], [true, true], `${label}: claimed`);
  sc.eq((await ops.json(svc(finish(claimed, 'commit', 'unknown')))).state, 'unknown', `${label}: commit reply unknown`);
  sc.eq((await ops.json(svc(finish(claimed, 'lookup', 'pending', {}, 'operator')))).state, 'unknown', `${label}: a lookup was attempted`);
  const freed = await ops.json(svc(freeOrder(label)));
  sc.eq(pick(freed, ['ok', 'state', 'classification']), { ok: true, state: 'unknown', classification: 'freed' },
    `${label}: freed by the manager's evidence-bound free`);
  return claimed;
}

async function c11FinishVsClose(sc) {
  await makeOrders('c11a', 'c11b', 'c11c', 'c11d');
  const A = await sc.open('finish');
  const B = await sc.open('close');
  // (a) the finish commits first and leaves the attempt blocking: the close is refused.
  const sa = await rotateShift('s11a');
  const xa = await freedAttempt(sc, 'c11a-x', 'c11a');
  sc.eq(await closeBlocked(sa), 'false', '(a) a freed unknown attempt without an anomaly does not block');
  const approvedA = await A.json(svc(finish(xa, 'lookup', 'approved', LOOKUP_APPROVED, 'operator')));
  sc.eq(pick(approvedA, ['state', 'classification']), { state: 'approved', classification: 'orphan_approved' },
    '(a) the approval found after the free is committed (orphan_approved)');
  const refused = (await B.json(pos(push(3, closeOp('c11a-close', sa))))).results[0];
  sc.eq(pick(refused, ['ok', 'error']), { ok: false, error: 'card_payment_in_progress' }, '(a) the close is refused');
  sc.eq(await shiftStatus(sa), 'open', '(a) the shift stays open');
  // (b) the close reads before the finish commits: it does not wait, the shift closes and stays closed.
  const sb = await rotateShift('s11b');
  const xb = await freedAttempt(sc, 'c11b-x', 'c11b');
  const approvedB = await A.json(svcTx(finish(xb, 'lookup', 'approved', LOOKUP_APPROVED, 'operator')));
  sc.eq(approvedB.state, 'approved', '(b) A: the approving lookup is written (uncommitted)');
  const closed = (await within(B.json(pos(push(3, closeOp('c11b-close', sb)))), 10_000,
    '(b) the close waited for the uncommitted finish')).results[0];
  sc.eq(pick(closed, ['ok', 'status']), { ok: true, status: 'applied' }, '(b) B: the close commits without waiting for the finish');
  sc.eq(await shiftStatus(sb), 'closed', '(b) the shift is closed while the finish is still open');
  await A.query('commit;');
  sc.eq(pick(await derived(1, 'c11b-x'), ['classification', 'reason']), { classification: 'orphan_approved', reason: 'order_freed' },
    '(b) the later approval is a reconciliation incident (orphan_approved / order_freed)');
  sc.eq(await shiftStatus(sb), 'closed', '(b) nothing re-blocks the closed shift');
  // (c) a declining finish is uncommitted: the close reads the committed sent attempt and is refused,
  //     then a close after the commit succeeds.
  const sc3 = await rotateShift('s11c');
  const xc = await ops.json(svc(claimLive(1, 'c11c-x', 'c11c')));
  sc.eq([xc.ok, xc.claim_created], [true, true], '(c) claimed');
  const declining = await A.json(svcTx(finish(xc, 'commit', 'declined', DECLINED)));
  sc.eq(declining.state, 'declined', '(c) A: the decline is written (uncommitted)');
  const early = (await within(B.json(pos(push(3, closeOp('c11c-close-1', sc3)))), 10_000,
    '(c) the close waited for the uncommitted finish')).results[0];
  sc.eq(pick(early, ['ok', 'error']), { ok: false, error: 'card_payment_in_progress' },
    '(c) B: refused on the committed sent state, without waiting');
  await A.query('commit;');
  const later = (await B.json(pos(push(3, closeOp('c11c-close-2', sc3))))).results[0];
  sc.eq(pick(later, ['ok', 'status']), { ok: true, status: 'applied' }, '(c) a close after the committed decline succeeds');
  sc.eq(await shiftStatus(sc3), 'closed', '(c) the shift is closed');
  // (d) the close reads before an anomaly finish commits: the shift closes; the anomaly is an incident only.
  const sd = await rotateShift('s11d');
  const xd = await freedAttempt(sc, 'c11d-x', 'c11d');
  const anomalous = await A.json(svcTx(finish(xd, 'lookup', 'anomaly', { anomaly_code: 'amount_mismatch' }, 'operator')));
  sc.eq(pick(anomalous, ['state', 'classification', 'anomaly_code']), { state: 'unknown', classification: 'provider_anomaly', anomaly_code: 'amount_mismatch' },
    '(d) A: an anomaly is written on the freed attempt (uncommitted)');
  const closedD = (await within(B.json(pos(push(3, closeOp('c11d-close', sd)))), 10_000,
    '(d) the close waited for the uncommitted finish')).results[0];
  sc.eq(pick(closedD, ['ok', 'status']), { ok: true, status: 'applied' }, '(d) B: the close commits without waiting for the finish');
  await A.query('commit;');
  sc.eq(pick(await derived(1, 'c11d-x'), ['classification', 'blocks_close']), { classification: 'provider_anomaly', blocks_close: true },
    '(d) the later anomaly would block an open shift (charge may exist)');
  sc.eq(await shiftStatus(sd), 'closed', '(d) nothing re-blocks the closed shift (reconciliation incident)');
  sc.detail.interleavings = { a: 'finish committed first -> close refused', b: 'approval after the read -> closed, orphan_approved',
    c: 'decline uncommitted -> close refused, then closes', d: 'anomaly after the read -> closed, provider_anomaly' };
  await rotateShift('after-c11');
}

// ---------------------------------------------------------------------------------------------------------
// C12: a forced deadlock inside the recording leg's dispatch is a transient failure; a resend records once.
// ---------------------------------------------------------------------------------------------------------
async function c12ForcedDeadlock(sc) {
  await rotateShift('s12');
  await makeOrders('c12');
  const claimed = await ops.json(svc(claimLive(1, 'c12-x', 'c12')));
  sc.eq((await ops.json(svc(finish(claimed, 'commit', 'approved', APPROVED)))).state, 'approved', 'the attempt is approved');
  // The leg's backend detects the cycle (2 s); the row-locking connection would wait 60 s, so the card side
  // is the deadlock victim deterministically.
  const X = await sc.open('locker', "set deadlock_timeout = '60s';");
  const L = await sc.open('leg', "set deadlock_timeout = '2s';");
  sc.eq(await L.one('show deadlock_timeout;'), '2s', 'the leg session detects deadlocks first');
  const before = await deadlocks();
  const held = await X.one(`begin; select a.id::text from app.card_provider_attempts a where a.organization_id = ${ORG}
    and a.device_id = ${dev(1)} and a.local_operation_id = ${lop('c12-x')} for update;`);
  sc.eq(held, claimed.attempt_row_id, 'X holds the attempt row');
  const legP = L.json(pos(push(1, payOp('c12-x', 'c12'))));
  sc.detail.leg_waits_for_attempt_row = await provenWait(L, legP, X, ['transactionid', 'tuple']);
  const xP = X.one(`select o.id::text from public.orders o where o.id = ${ord('c12')} for update;`);
  const leg = (await legP).results[0];
  sc.eq(await xP, nodeId('order-c12'), 'X obtains the order row once the leg subtransaction rolled back');
  await X.query('rollback;');
  sc.eq(pick(leg, ['ok', 'error', 'retryable', 'status', 'idempotency_replay']),
    { ok: false, error: 'transient_failure', retryable: true, status: 'pending', idempotency_replay: false },
    'L: the deadlock inside the card-sensitive dispatch answers transient_failure');
  sc.eq(pick(await syncRow(1, 'c12-x'), ['status', 'last_error_class', 'last_error_code']),
    { status: 'pending', last_error_class: 'transient', last_error_code: '40P01' }, 'the row returns to pending (40P01, transient)');
  sc.eq(await paymentsUnder(1, 'c12-x'), 0, 'no payment');
  sc.eq(await count(`select count(*) from public.audit_events e where e.action = 'sync.operation_rejected'
    and e.new_values ->> 'local_operation_id' = ${lop('c12-x')}`), 0, 'no rejection audit');
  await L.query('select pg_stat_force_next_flush();');
  await L.query('select 1;');
  let after = before;
  for (let i = 0; i < 100 && after === before; i += 1) { await sleep(30); after = await deadlocks(); }
  sc.eq(after - before, 1, 'pg_stat_database counts exactly one deadlock');
  const resend = (await L.json(pos(push(1, payOp('c12-x', 'c12'))))).results[0];
  sc.eq(pick(resend, ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    'the resend of the same identity is dispatched once and records');
  sc.eq(await paymentsUnder(1, 'c12-x'), 1, 'exactly one payment');
  sc.eq(pick(await syncRow(1, 'c12-x'), ['status', 'retry_count']), { status: 'applied', retry_count: 1 }, 'the same row, adopted once');
  sc.eq((await derived(1, 'c12-x')).classification, 'recorded', 'the attempt is recorded (strict join)');
  const replay = (await L.json(pos(push(1, payOp('c12-x', 'c12'))))).results[0];
  sc.eq(pick(replay, ['status', 'idempotency_replay', 'payment_id']), { status: 'applied', idempotency_replay: true, payment_id: resend.payment_id },
    'a further resend replays the stored result');
  sc.eq(await paymentsUnder(1, 'c12-x'), 1, 'still exactly one payment');
  sc.detail.deadlocks_counted = after - before;
}

// ---------------------------------------------------------------------------------------------------------
// C13: lock-order stress from five sessions on an ordinary and a printer-only branch: P claims, finishes and
//      pushes the recording leg; Q pushes two cash payments; R pushes a refused close, a lookup and every third
//      round a void; and (TEST_BRIEF_3 §C item 2; SECURITY:325 "a concurrent TEST purge"; TESTING_STRATEGY:173
//      "the lock order against app.edit_order") G runs the TEST purge, which deletes the one prepared TEST
//      attempt of d2 aged before the round, and E pushes an order.edit of the round's card order (quantity
//      2 -> 3; started 25 ms later in even rounds). Same round count and seed; the outcome tally is in the
//      evidence.
// ---------------------------------------------------------------------------------------------------------
function lcg(seed) {
  let s = seed >>> 0;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
}

// The TEST attempts the stress purges (one per round and mode), claimed and declined on d2 in the TEST phase.
const C13_MODES = ['kds', 'printer_only'];
const c13TestLabel = (mode, r) => `c13-${mode}-t${r}`;
async function c13Prepare() {
  for (const mode of C13_MODES) {
    for (let r = 1; r <= STRESS_ROUNDS; r += 1) {
      const label = c13TestLabel(mode, r);
      const t = await ops.json(svc(claimTest(8, label)));
      assert.equal(t.claim_created, true, `C13 preparation: TEST claim ${label}: ${JSON.stringify(t)}`);
      const fin = await ops.json(svc(finish(t, 'commit', 'declined', DECLINED)));
      assert.equal(fin.state, 'declined', `C13 preparation: ${label} declined: ${JSON.stringify(fin)}`);
    }
  }
}
// Race database only: one TEST attempt of device d becomes purgeable (its retention moved into the past with
// the frozen-fact trigger bypassed for that one UPDATE). The stress calls it between rounds, while no stress
// session runs a statement.
const ageTestIdentity = (d, label) => ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
with u as (update app.card_provider_attempts a set retention_until = clock_timestamp() - interval '1 second'
            where a.organization_id = ${ORG} and a.device_id = ${dev(d)} and a.local_operation_id = ${lop(label)}
              and a.mode = 'test' returning 1) select count(*) from u;
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
// [ledger rows, tombstones] of one identity of device d.
const identityRows = (d, label) => ops.json(`select jsonb_build_array(
  (select count(*) from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(d)}
      and a.local_operation_id = ${lop(label)}),
  (select count(*) from app.card_attempt_identity_tombstones t where t.organization_id = ${ORG}
      and t.device_id = ${dev(d)} and t.local_operation_id = ${lop(label)}))::text`);
// order.edit of the order's seeded line item-<order label>, quantity 2 -> 3: 1234 -> 1851 (tax off on the
// pilot branch).
const editQuantityOp = (label, orderLabel) => `jsonb_build_object('local_operation_id', ${lop(label)},
  'operation_type', 'order.edit', 'target_entity', 'order', 'target_id', ${ord(orderLabel)},
  'client_created_at', '2026-10-24T00:00:00Z', 'payload', jsonb_build_object('order_id', ${ord(orderLabel)},
    'expected', jsonb_build_object('subtotal_minor', 1851, 'tax_total_minor', 0, 'grand_total_minor', 1851),
    'changes', jsonb_build_array(jsonb_build_object('op', 'set_quantity', 'order_item_id', ${id(`item-${orderLabel}`)},
      'quantity', 3))))`;
const orderEditState = (label) => ops.json(`select jsonb_build_object('revision', o.revision, 'status', o.status,
  'grand_total_minor', o.grand_total_minor, 'edit_count', o.edit_count,
  'order_edits', (select count(*) from public.order_edits e where e.order_id = o.id))::text
  from public.orders o where o.id = ${ord(label)}`);

async function stress(sc, mode) {
  if (mode === 'printer_only') {
    sc.eq(await ops.one(`update public.branches b set kitchen_workflow_mode = 'printer_only' where b.id = ${F}.zc_branch()
      returning b.kitchen_workflow_mode;`), 'printer_only', 'race database only: the pilot branch is printer-only');
  }
  sc.eq(await ops.one(`update public.branches b set order_edit_enabled = true where b.id = ${F}.zc_branch()
    returning b.order_edit_enabled::text`), 'true', `${mode}: race database only: order editing ON for the order.edit session`);
  const shift = await rotateShift(`s13-${mode}`);
  const labels = [`c13-${mode}-blocker`];
  for (let r = 1; r <= STRESS_ROUNDS; r += 1) labels.push(`c13-${mode}-r${r}`, `c13-${mode}-r${r}-cash`);
  await makeOrders(...labels);
  // One editable line per round card order (2 x 617 = 1234, the order total) for the order.edit session.
  await ops.query(`insert into public.menu_categories (id, organization_id, restaurant_id, name)
values (${id('menu-category-c13')}, ${ORG}, ${F}.zc_rest(), 'ZC001D stress category') on conflict (id) do nothing;
insert into public.menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code)
values (${id('menu-item-c13')}, ${ORG}, ${F}.zc_rest(), ${id('menu-category-c13')}, 'ZC001D stress item', 617, 'ILS')
on conflict (id) do nothing;
insert into public.order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity,
                                menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor)
select ${F}.zc_id('item-c13-' || ${lit(mode)} || '-r' || r), ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(),
       ${F}.zc_id('order-c13-' || ${lit(mode)} || '-r' || r), ${id('menu-item-c13')}, 2, 'ZC001D stress item', 617, 1234
  from generate_series(1, ${STRESS_ROUNDS}) r;`);
  const blocker = await ops.json(svc(claimLive(1, `c13-${mode}-blocker`, `c13-${mode}-blocker`)));
  sc.eq([blocker.ok, blocker.claim_created], [true, true], `${mode}: a standing attempt keeps the shift blocked`);
  const startedAt = await ops.one('select clock_timestamp()::text');
  const P = await sc.open(`${mode}_p`);
  const Q = await sc.open(`${mode}_q`);
  const R = await sc.open(`${mode}_r`);
  const G = await sc.open(`${mode}_g`);
  const E = await sc.open(`${mode}_e`);
  const S = await sc.open(`${mode}_sampler`);
  const before = await deadlocks();
  const random = lcg(STRESS_SEED + (mode === 'kds' ? 0 : 1));
  const tally = {};
  const bump = (k) => { tally[k] = (tally[k] ?? 0) + 1; };
  const outcome = (x) => (x.ok ? x.status : `${x.status}:${x.error}${x.detail ? `/${x.detail}` : ''}`);
  let samples = 0;
  let lockWaitSamples = 0;
  for (let r = 1; r <= STRESS_ROUNDS; r += 1) {
    const card = `c13-${mode}-r${r}`;
    const testLabel = c13TestLabel(mode, r);
    sc.eq(await ageTestIdentity(2, testLabel), ['1'],
      `${mode} r${r}: race database only: the prepared TEST attempt ${testLabel} of d2 aged past its retention (between rounds)`);
    const jitter = () => sleep(Math.floor(random() * 20));
    const delays = [0, 1, 2, 3, 4].map(() => Math.floor(random() * 20));
    // Evidence only (not asserted): how often one of the five sessions was observed in a lock wait.
    let sampling = true;
    const sampler = handled((async () => {
      while (sampling) {
        const waiting = Number(await S.one(`select count(*) from pg_stat_activity a where a.datname = current_database()
          and a.pid in (${P.pid}, ${Q.pid}, ${R.pid}, ${G.pid}, ${E.pid}) and a.wait_event_type = 'Lock'`));
        samples += 1;
        if (waiting > 0) lockWaitSamples += 1;
      }
    })());
    const [p, q, rr, g, e] = await Promise.all([
      (async () => {
        await sleep(delays[0]);
        const claim = await P.json(svc(claimLive(1, `c13-${mode}-x${r}`, card)));
        bump(`P.claim:${claim.ok ? 'created' : `${claim.error}${claim.detail ? `/${claim.detail}` : ''}`}`);
        if (!(claim.ok && claim.claim_created)) return { claim };
        await jitter();
        const fin = await P.json(svc(finish(claim, 'commit', 'approved', APPROVED)));
        await jitter();
        const leg = (await P.json(pos(push(1, payOp(`c13-${mode}-x${r}`, card))))).results[0];
        bump(`P.leg:${outcome(leg)}`);
        return { claim, fin, leg };
      })(),
      (async () => {
        await sleep(delays[1]);
        const contend = (await Q.json(pos(push(2, payOp(`c13-${mode}-y${r}`, card, 'cash', 2000))))).results[0];
        bump(`Q.cash_same_order:${outcome(contend)}`);
        await jitter();
        const other = (await Q.json(pos(push(2, payOp(`c13-${mode}-z${r}`, `${card}-cash`, 'cash', 2000))))).results[0];
        bump(`Q.cash_other_order:${outcome(other)}`);
        return { contend, other };
      })(),
      (async () => {
        await sleep(delays[2]);
        const close = (await R.json(pos(push(3, closeOp(`c13-${mode}-close${r}`, shift))))).results[0];
        bump(`R.close:${outcome(close)}`);
        await jitter();
        const look = await R.json(svc(finish(blocker, 'lookup', 'pending', {}, 'auto')));
        let voided = null;
        if (r % 3 === 0) {
          await jitter();
          voided = (await R.json(pos(push(3, voidOp(`c13-${mode}-v${r}`, card))))).results[0];
          bump(`R.void:${outcome(voided)}`);
        }
        return { close, look, voided };
      })(),
      (async () => {
        await sleep(delays[3]);
        const purged = await G.json(`select ${PURGE_CALL}::text`);
        bump(`G.purge:${purged.ok ? `purged_${purged.attempts_purged}` : purged.error}`);
        return { purged };
      })(),
      (async () => {
        // Odd rounds race the edit against the claim; even rounds start it 25 ms later, so it mostly meets the
        // finish / recording leg or the cash payment of the same order (keeping the card path exercised).
        await sleep(delays[4] + (r % 2 === 0 ? 25 : 0));
        const edit = (await E.json(pos(push(1, editQuantityOp(`c13-${mode}-e${r}`, card))))).results[0];
        bump(`E.edit:${outcome(edit)}`);
        return { edit };
      })(),
    ]).finally(() => { sampling = false; });
    await sampler;
    const pushed = [p.leg, q.contend, q.other, rr.close, rr.voided, e.edit].filter(Boolean);
    sc.eq(pushed.filter((x) => !['applied', 'rejected'].includes(x.status) || x.error === 'transient_failure'
      || x.sqlstate === '40P01').map(outcome), [], `${mode} r${r}: every push is applied or terminally rejected`);
    sc.eq(pick(rr.close, ['ok', 'error']), { ok: false, error: 'card_payment_in_progress' }, `${mode} r${r}: the close is refused`);
    sc.ok(rr.look.ok === true && ['sent', 'unknown'].includes(rr.look.state), `${mode} r${r}: the blocker lookup is written`);
    if (p.leg) sc.eq(p.leg.status, 'applied', `${mode} r${r}: an approved leg records`);
    const status = await ops.one(`select o.status from public.orders o where o.id = ${ord(card)}`);
    sc.eq(await orderPayments(card), status === 'voided' ? 0 : 1, `${mode} r${r}: exactly one payment unless voided (${status})`);
    sc.eq(await orderPayments(`${card}-cash`), 1, `${mode} r${r}: the other order took its one cash payment`);
    if (mode === 'printer_only' && status !== 'voided') sc.eq(status, 'completed', `${mode} r${r}: a paid printer-only order auto-completes`);
    if (mode === 'kds' && status !== 'voided') sc.eq(status, 'submitted', `${mode} r${r}: a paid KDS order is not auto-completed`);
    // The concurrent TEST purge (G) and order.edit (E) of this round.
    sc.eq({ ...g.purged, cutoff: typeof g.purged.cutoff }, { ok: true, attempts_purged: 1, events_purged: 0,
      attempts_deferred: 0, events_deferred: 0, devices_locked: 1, cutoff: 'string' },
    `${mode} r${r}: the concurrent TEST purge deletes exactly the one attempt aged for this round (C1-3: a one-device `
      + 'batch result, nothing deferred)');
    sc.eq(await identityRows(2, testLabel), [0, 1], `${mode} r${r}: ${testLabel} has no ledger row and one tombstone`);
    const edited = e.edit.ok === true;
    sc.eq(pick(await orderEditState(card), ['grand_total_minor', 'edit_count', 'order_edits']),
      edited ? { grand_total_minor: 1851, edit_count: 1, order_edits: 1 } : { grand_total_minor: 1234, edit_count: 0, order_edits: 0 },
      `${mode} r${r}: the order carries the edit exactly when it was applied (${outcome(e.edit)})`);
    if (edited) {
      sc.eq(await attempt(1, `c13-${mode}-x${r}`), null,
        `${mode} r${r}: an applied edit came before any claim: no card attempt for the order (its expected_revision 1 is stale)`);
    }
  }
  for (const s of [P, Q, R, G, E]) { await s.query('select pg_stat_force_next_flush();'); await s.query('select 1;'); }
  await sleep(300);
  sc.eq(await deadlocks() - before, 0, `${mode}: pg_stat_database counts no deadlock`);
  sc.eq(await count(`select count(*) from public.sync_operations so where so.created_at >= ${lit(startedAt)}::timestamptz
    and (so.last_error_code in ('40P01', '40001') or so.last_error_class = 'transient' or so.status not in ('applied', 'rejected'))`),
  0, `${mode}: no deadlock, serialization or transient ledger row`);
  sc.eq(await count(`select count(*) from (select p.device_id, p.local_operation_id from public.payments p
    group by 1, 2 having count(*) > 1) d`), 0, `${mode}: no payment identity is duplicated`);
  sc.eq(await count(`select count(*) from (select p.order_id from public.payments p where p.status = 'completed'
    and p.deleted_at is null group by 1 having count(*) > 1) d`), 0, `${mode}: no order has two completed payments`);
  sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.created_at >= ${lit(startedAt)}::timestamptz
    and a.state = 'approved' and app.card_attempt_payment_id(a) is null`), 0, `${mode}: every approved attempt is recorded`);
  sc.eq(await shiftStatus(shift), 'open', `${mode}: the shift stayed open (every close refused)`);
  sc.eq(await ops.json(`select jsonb_build_array(
    (select count(*) from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(2)}
        and a.local_operation_id in (select ${F}.zc_lop('c13-' || ${lit(mode)} || '-t' || r) from generate_series(1, ${STRESS_ROUNDS}) r)),
    (select count(*) from app.card_attempt_identity_tombstones t where t.organization_id = ${ORG} and t.device_id = ${dev(2)}
        and t.local_operation_id in (select ${F}.zc_lop('c13-' || ${lit(mode)} || '-t' || r) from generate_series(1, ${STRESS_ROUNDS}) r)))::text`),
  [0, STRESS_ROUNDS], `${mode}: the ${STRESS_ROUNDS} prepared TEST attempts were purged, one per round, each into the tombstone set`);
  sc.detail[mode] = { rounds: STRESS_ROUNDS, seed: STRESS_SEED + (mode === 'kds' ? 0 : 1), outcomes: tally,
    lock_wait_samples: `${lockWaitSamples}/${samples}` };
}

// =========================================================================================================
// Review-fix pass (TEST_BRIEF_2 §C lane CC): C15–C22, numbered after C14.
// =========================================================================================================
// Shared vocabulary of the added scenarios.
const ORIGINAL_LIVE = ['zc-term-live-1', 'zc-cred-live-1'];
const PILOT_BRANCH_ID = '2847c0be-3e31-45a5-957c-508729f1971e'; // the fixture's zc_branch() (D-051 point 1 constant)
const terminalCall = (d, mode, [term, cred], lifecycle, reason) => `app.set_payment_terminal(${dev(d)}, ${lit(mode)},
  ${lit(term)}, ${lit(cred)}, ${lit(lifecycle)}, ${lit(reason)}, 'ZC001D synthetic binding', 'zc001d-op/ref-2', ${OWNER})`;
const liveCall = (refs, lifecycle, reason) => terminalCall(1, 'live', refs, lifecycle, reason);
// The full app.set_payment_terminal success envelope of one lifecycle change (it carries no server_ts).
const changed = (mode, prior, next, extra = {}) => ({ ok: true, changed: true, binding_mode: mode,
  prior_lifecycle: prior, new_lifecycle: next, ...extra });
const PURGE_CALL = `app.purge_expired_test_card_attempts('ZC001D synthetic purge', 'zc001d-op/ref-3', ${OWNER})`;
const credKeySql = (ref) => `hashtextextended('card-credential-ref/v1:' || ${lit(ref)}, 0)::text`;
const PILOT_KEY_SQL = `hashtextextended('card-pilot-revision/v1:' || ${ORG}::text || ':' || ${F}.zc_branch()::text, 0)::text`;
const held = (key) => ({ key, mode: 'ExclusiveLock', granted: true });
const waiting = (key) => ({ key, mode: 'ExclusiveLock', granted: false });
const sharedHeld = (key) => ({ key, mode: 'ShareLock', granted: true });
const sharedWaiting = (key) => ({ key, mode: 'ShareLock', granted: false });
// A full envelope with server_ts replaced by its JSON type (the value is a clock reading, never asserted).
const tsShape = (x) => (x && typeof x === 'object' && 'server_ts' in x ? { ...x, server_ts: typeof x.server_ts } : x);
const currentBinding = (d) => ops.one(`select coalesce((select t.terminal_ref || '/' || t.credential_ref || '/' || t.mode
  || '/' || t.lifecycle from app.payment_terminals t where t.organization_id = ${ORG} and t.device_id = ${dev(d)}
  and t.deleted_at is null and t.lifecycle <> 'retired'), 'none')`);
const operatorEvents = (d) => count(`select count(*) from app.card_provider_private_events e
  where e.action = 'operator.payment_terminal_updated' and e.device_id = ${dev(d)}`);
const cardAudits = (d) => count(`select count(*) from public.audit_events e where e.action like 'card_attempt.%'
  and e.device_id = ${dev(d)}`);
const paymentMethods = (d, label) => ops.one(`select coalesce(string_agg(p.method || ':' || p.status || ':' || p.amount_minor,
  ',' order by p.id), 'none') from public.payments p where p.device_id = ${dev(d)} and p.local_operation_id = ${lop(label)}`);
// Runs `expr` inside a PL/pgSQL block and answers its text, or 'SQLSTATE:<code>' when it raises: the error is
// caught (its subtransaction rolled back), so psql's ON_ERROR_STOP never ends the session.
const caught = (expr) => `do $zc$ begin perform set_config('zc001d.caught', (${expr})::text, false);
exception when others then perform set_config('zc001d.caught', 'SQLSTATE:' || sqlstate, false); end $zc$;
select current_setting('zc001d.caught');`;
const terminalLabel = ([term, cred], mode, lifecycle) => `${term}/${cred}/${mode}/${lifecycle}`;

// ---------------------------------------------------------------------------------------------------------
// C15 (SECURITY:325 terminal admission; the C4 legs in the remaining orders): a LIVE start against an
//      uncommitted retirement and an uncommitted rotation (each ends card_payments_disabled), and a LIVE
//      activation and a retirement against an uncommitted start (each sees the unresolved attempt and is
//      refused attempt_unresolved). Runs right after C4, while d1 has no unresolved attempt.
// ---------------------------------------------------------------------------------------------------------
async function c15TerminalAdmissionLegs(sc) {
  await makeOrders('c15a', 'c15b', 'c15c1', 'c15c2');
  const ROTATED = ['zc-term-live-1x', 'zc-cred-live-1x'];
  const k = await keyValues({ t1: terminalKeySql(1), purge: PURGE_KEY_SQL, rot: credKeySql(ROTATED[1]),
    c1: identityKeySql(1, 'c15-c1'), c2: identityKeySql(1, 'c15-c2') });
  const A = await sc.open('start');
  const B = await sc.open('operator');
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'enabled'), 'start: the original LIVE binding of d1 is enabled');
  const audits0 = await cardAudits(1);

  // (a) the retirement first: B drains and retires the enabled binding in one uncommitted transaction.
  sc.eq(await B.json(`begin; select ${liveCall(ORIGINAL_LIVE, 'draining', 'end_of_pilot')}::text;`),
    changed('live', 'enabled', 'draining'), '(a) B: drain of the enabled binding (uncommitted)');
  sc.eq(await B.json(`select ${liveCall(ORIGINAL_LIVE, 'retired', 'end_of_pilot')}::text;`),
    changed('live', 'draining', 'retired'), '(a) B: retirement in the same transaction (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([held(k.t1)]), '(a) B holds exactly the d1 terminal lock');
  const aP = A.json(svc(claimLive(1, 'c15-a', 'c15a')));
  sc.detail.a_start_waits_for_retirement = await provenWait(A, aP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([waiting(k.t1)]),
    '(a) A (LIVE start) waits on the d1 terminal lock and holds no other advisory lock');
  await B.query('commit;');
  sc.eq(tsShape(await aP), { ok: false, error: 'card_payments_disabled', server_ts: 'string' },
    '(a) A: exactly {ok:false, error:card_payments_disabled} once the retirement committed');
  sc.eq(await attempt(1, 'c15-a'), null, '(a) no attempt row for the refused start');
  sc.eq(await cardAudits(1) - audits0, 0, '(a) no card_attempt.* tenant audit for the refused start');
  sc.eq(await currentBinding(1), 'none', '(a) d1 has no current binding after the retirement');
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'configured', 'live_activation')}::text`),
    changed('live', null, 'configured'), 'restore (a): the original references configured on a new row');
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'enabled', 'live_activation')}::text`),
    changed('live', 'configured', 'enabled'), 'restore (a): enabled');

  // (b) the rotation first: B drains and replaces the draining row (credential rotation) uncommitted.
  sc.eq(await B.json(`begin; select ${liveCall(ORIGINAL_LIVE, 'draining', 'rotation')}::text;`),
    changed('live', 'enabled', 'draining'), '(b) B: drain of the enabled binding (uncommitted)');
  sc.eq(await B.json(`select ${liveCall(ROTATED, 'configured', 'rotation')}::text;`),
    changed('live', 'draining', 'configured', { replaced: true }),
    '(b) B: the rotation (atomic replacement of the draining row) in the same transaction (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([held(k.t1), held(k.rot)]),
    '(b) B holds the d1 terminal lock and the credential-reference lock its new row took (review fix 11)');
  const bP = A.json(svc(claimLive(1, 'c15-b', 'c15b')));
  sc.detail.b_start_waits_for_rotation = await provenWait(A, bP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([waiting(k.t1)]), '(b) A (LIVE start) waits on the d1 terminal lock');
  await B.query('commit;');
  sc.eq(tsShape(await bP), { ok: false, error: 'card_payments_disabled', server_ts: 'string' },
    '(b) A: exactly {ok:false, error:card_payments_disabled} once the rotation committed (a configured row admits no start)');
  sc.eq(await attempt(1, 'c15-b'), null, '(b) no attempt row for the refused start');
  sc.eq(await cardAudits(1) - audits0, 0, '(b) no card_attempt.* tenant audit for the refused start');
  sc.eq(await currentBinding(1), terminalLabel(ROTATED, 'live', 'configured'), '(b) the rotated row is the current binding');
  for (const [refs, lifecycle, reason, prior, extra] of [[ROTATED, 'enabled', 'live_activation', 'configured', {}],
    [ROTATED, 'draining', 'rotation', 'enabled', {}], [ORIGINAL_LIVE, 'configured', 'rotation', 'draining', { replaced: true }],
    [ORIGINAL_LIVE, 'enabled', 'live_activation', 'configured', {}]]) {
    sc.eq(await ops.json(`select ${liveCall(refs, lifecycle, reason)}::text`), changed('live', prior, lifecycle, extra),
      `restore (b): ${refs[0]} -> ${lifecycle}`);
  }

  // (c) the start first: A's uncommitted transaction claims and then drains (so B's call below is a real
  //     lifecycle transition); B's LIVE activation (c1), separately B's retirement (c2), waits on the
  //     terminal lock and, after A commits, sees the unresolved attempt.
  for (const [leg, label, order, lifecycle, reason] of [['c1', 'c15-c1', 'c15c1', 'enabled', 'live_activation'],
    ['c2', 'c15-c2', 'c15c2', 'retired', 'end_of_pilot']]) {
    const what = lifecycle === 'enabled' ? 'LIVE activation' : 'retirement';
    const events0 = await operatorEvents(1);
    const started = await A.json(svcTx(claimLive(1, label, order)));
    sc.eq(pick(started, ['ok', 'claim_created', 'replayed', 'state', 'mode']),
      { ok: true, claim_created: true, replayed: false, state: 'sent', mode: 'live' }, `(${leg}) A: fresh LIVE start (uncommitted)`);
    sc.eq(await A.json(`reset role; select ${liveCall(ORIGINAL_LIVE, 'draining', 'incident')}::text;`),
      changed('live', 'enabled', 'draining'), `(${leg}) A (same transaction): drains the binding`);
    sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), sharedHeld(k.purge), held(k[leg])]),
      `(${leg}) A holds the d1 terminal lock, the shared purge barrier and the identity lock`);
    const bP2 = B.json(`select ${liveCall(ORIGINAL_LIVE, lifecycle, reason)}::text`);
    sc.detail[`${leg}_${lifecycle}_waits_for_start`] = await provenWait(B, bP2, A, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(B)), lockSet([waiting(k.t1)]), `(${leg}) B (${what}) waits on the d1 terminal lock`);
    await A.query('commit;');
    sc.eq(await bP2, { ok: false, error: 'precondition_failed', detail: 'attempt_unresolved' },
      `(${leg}) B: the ${what} sees the committed unresolved attempt and is refused attempt_unresolved`);
    sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'draining'), `(${leg}) the binding stays draining`);
    sc.eq(await operatorEvents(1) - events0, 1, `(${leg}) one operator event (A's drain), none for the refused ${what}`);
    sc.eq(pick(await attempt(1, label), ['state', 'mode', 'terminal_ref', 'credential_ref']),
      { state: 'sent', mode: 'live', terminal_ref: ORIGINAL_LIVE[0], credential_ref: ORIGINAL_LIVE[1] },
      `(${leg}) the committed attempt is sent with its frozen references`);
    sc.eq((await ops.json(svc(finish(started, 'commit', 'declined', DECLINED)))).state, 'declined', `cleanup (${leg}): attempt declined`);
    sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'enabled', 'live_activation')}::text`),
      changed('live', 'draining', 'enabled'), `cleanup (${leg}): the binding enabled again`);
  }
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'enabled'), 'end: the original LIVE binding of d1 is enabled');
}

// ---------------------------------------------------------------------------------------------------------
// C16 (SECURITY:325; API §4.55.9 card_terminal_required): a hand-recorded card and a cash payment.create
//      against a retirement, both orders. The card push is refused while the LIVE binding is enabled,
//      draining or configured and admitted once the retirement committed; cash is admitted in both orders.
// ---------------------------------------------------------------------------------------------------------
async function c16PushesVsRetirement(sc) {
  await makeOrders('c16-en', 'c16-dr', 'c16-cf', 'c16-r-card', 'c16-r-cash', 'c16-p-card', 'c16-p-cash');
  const k = await keyValues({ t1: terminalKeySql(1), pcard: identityKeySql(1, 'c16-p-card-x'),
    pcash: identityKeySql(1, 'c16-p-cash-y') });
  const A = await sc.open('card');
  const C = await sc.open('cash');
  const B = await sc.open('operator');
  const refusal = (label, orderLabel) => ({ ok: false, error: 'card_terminal_required', status: 'rejected',
    idempotency_replay: false, local_operation_id: nodeLop(label), operation_type: 'payment.create',
    order_id: nodeId(`order-${orderLabel}`), server_ts: 'string' });
  const refusedCard = async (label, orderLabel, state) => {
    const r = (await ops.json(pos(push(1, payOp(label, orderLabel))))).results[0];
    sc.eq(tsShape(r), refusal(label, orderLabel), `${state}: a hand-recorded card push is refused card_terminal_required`);
    sc.eq([await paymentsUnder(1, label), pick(await syncRow(1, label), ['status', 'rejection_reason'])],
      [0, { status: 'rejected', rejection_reason: 'card_terminal_required' }], `${state}: no payment, the push memoized rejected`);
  };
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'enabled'), 'start: the original LIVE binding of d1 is enabled');
  await refusedCard('c16-en-x', 'c16-en', 'enabled');
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'draining', 'end_of_pilot')}::text`),
    changed('live', 'enabled', 'draining'), 'the binding drained (committed)');
  await refusedCard('c16-dr-x', 'c16-dr', 'draining');

  // (1) the retirement first: a card push and a cash push both wait on the terminal lock, then are admitted.
  sc.eq(await B.json(`begin; select ${liveCall(ORIGINAL_LIVE, 'retired', 'end_of_pilot')}::text;`),
    changed('live', 'draining', 'retired'), '(1) B: retirement (uncommitted)');
  const cardP = A.json(pos(push(1, payOp('c16-r-card-x', 'c16-r-card'))));
  sc.detail.card_push_waits_for_retirement = await provenWait(A, cardP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([waiting(k.t1)]), '(1) A (card push) waits on the d1 terminal lock');
  const cashP = C.json(pos(push(1, payOp('c16-r-cash-y', 'c16-r-cash', 'cash', 2000))));
  sc.detail.cash_push_waits_for_retirement = await provenWait(C, cashP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(C)), lockSet([waiting(k.t1)]), '(1) C (cash push) waits on the d1 terminal lock');
  await B.query('commit;');
  const card = (await cardP).results[0];
  const cash = (await cashP).results[0];
  sc.eq(pick(card, ['ok', 'status', 'idempotency_replay', 'local_operation_id', 'operation_type']),
    { ok: true, status: 'applied', idempotency_replay: false, local_operation_id: nodeLop('c16-r-card-x'),
      operation_type: 'payment.create' }, '(1) A: the hand-recorded card is admitted once the retirement committed');
  sc.eq(pick(cash, ['ok', 'status', 'idempotency_replay', 'local_operation_id', 'operation_type']),
    { ok: true, status: 'applied', idempotency_replay: false, local_operation_id: nodeLop('c16-r-cash-y'),
      operation_type: 'payment.create' }, '(1) C: the cash payment is admitted');
  sc.eq([await paymentMethods(1, 'c16-r-card-x'), await paymentMethods(1, 'c16-r-cash-y')],
    ['card:completed:1234', 'cash:completed:1234'], '(1) exactly one card and one cash payment');
  sc.eq(await currentBinding(1), 'none', '(1) d1 has no current binding');

  // (2) the push first, under a configured binding: the card push (refused) and, separately, the cash push
  //     (applied) hold the terminal lock uncommitted; the retirement waits and then succeeds.
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'configured', 'live_activation')}::text`),
    changed('live', null, 'configured'), 'the original references configured again (committed)');
  await refusedCard('c16-cf-x', 'c16-cf', 'configured');
  for (const [leg, S, label, orderLabel, tender, key] of [['card', A, 'c16-p-card-x', 'c16-p-card', 'card', k.pcard],
    ['cash', C, 'c16-p-cash-y', 'c16-p-cash', 'cash', k.pcash]]) {
    if (leg === 'cash') {
      sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'configured', 'live_activation')}::text`),
        changed('live', null, 'configured'), '(2 cash) the original references configured again (committed)');
    }
    const first = (await S.json(posTx(push(1, payOp(label, orderLabel, tender, tender === 'cash' ? 2000 : 1234))))).results[0];
    if (tender === 'card') {
      sc.eq(tsShape(first), refusal(label, orderLabel), '(2 card) A: card_terminal_required under the configured binding (uncommitted)');
    } else {
      sc.eq(pick(first, ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
        '(2 cash) C: the cash payment applied (uncommitted)');
    }
    sc.eq(lockSet(await advisoryLocks(S)), lockSet([held(k.t1), held(key)]),
      `(2 ${leg}) the push holds the d1 terminal lock and its identity lock`);
    const retireP = B.json(`select ${liveCall(ORIGINAL_LIVE, 'retired', 'end_of_pilot')}::text`);
    sc.detail[`retirement_waits_for_${leg}_push`] = await provenWait(B, retireP, S, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(B)), lockSet([waiting(k.t1)]), `(2 ${leg}) B (retirement) waits on the d1 terminal lock`);
    await S.query('commit;');
    sc.eq(await retireP, changed('live', 'configured', 'retired'),
      `(2 ${leg}) B: the retirement succeeds once the push committed (no payment.create backlog)`);
    sc.eq(await paymentMethods(1, label), tender === 'card' ? 'none' : 'cash:completed:1234',
      `(2 ${leg}) ${tender === 'card' ? 'no payment for the refused card push' : 'exactly one cash payment'}`);
  }
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'configured', 'live_activation')}::text`),
    changed('live', null, 'configured'), 'restore: the original references configured');
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'enabled', 'live_activation')}::text`),
    changed('live', 'configured', 'enabled'), 'restore: enabled (no unresolved LIVE attempt, no backlog)');
}

// ---------------------------------------------------------------------------------------------------------
// C17 (SECURITY:325): two concurrent app.set_card_payments_pilot calls serialize on the pilot-revision
//      advisory key and commit in revision order; the later decision holds the higher revision.
// ---------------------------------------------------------------------------------------------------------
async function c17PilotRevisions(sc) {
  const k = await keyValues({ pilot: PILOT_KEY_SQL });
  const before = await ops.json(`select jsonb_build_object('n', count(*), 'max', max(r.revision))::text
    from app.card_payments_pilot_revisions r`);
  const events0 = await count(`select count(*) from app.card_provider_private_events e
    where e.action = 'operator.card_payments_pilot_updated'`);
  const A = await sc.open('first');
  const B = await sc.open('second');
  const pilotCall = (enabled, reason) => `app.set_card_payments_pilot(${enabled}, 'live', null, 100000, 1000000,
    ${lit(reason)}, 'zc001d-op/ref-1', ${OWNER})`;
  const decision = (r) => ({ ...r, window_until: typeof r.window_until });
  const first = await A.json(`begin; select ${pilotCall(false, 'ZC001D concurrent revision A')}::text;`);
  sc.eq(decision(first), { ok: true, revision: before.max + 1, enabled: false, mode: 'live', window_until: 'string',
    max_test_amount_minor: 100000, max_live_amount_minor: 1000000 }, 'A: a disabling revision (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.pilot)]), 'A holds exactly the pilot-revision advisory lock');
  const secondP = B.json(`select ${pilotCall(true, 'ZC001D concurrent revision B')}::text`);
  sc.detail.second_revision_wait = await provenWait(B, secondP, A, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([waiting(k.pilot)]), 'B waits on the pilot-revision advisory lock');
  await A.query('commit;');
  const second = await secondP;
  sc.eq(decision(second), { ok: true, revision: before.max + 2, enabled: true, mode: 'live', window_until: 'string',
    max_test_amount_minor: 100000, max_live_amount_minor: 1000000 }, 'B: the enabling revision, recorded after A (no error)');
  sc.eq(await ops.json(`select coalesce(jsonb_agg(jsonb_build_array(r.revision, r.enabled, r.reason) order by r.revision),
    '[]'::jsonb)::text from app.card_payments_pilot_revisions r where r.revision > ${Number(before.max)}`),
  [[before.max + 1, false, 'ZC001D concurrent revision A'], [before.max + 2, true, 'ZC001D concurrent revision B']],
  'exactly two new revisions, in commit order, no duplicate');
  sc.eq(await ops.json(`select jsonb_build_array(c.revision, c.enabled, c.reason)::text
    from app.card_pilot_revision_current() c`), [before.max + 2, true, 'ZC001D concurrent revision B'],
  'the later decision (B, enabled) holds the higher revision and is current');
  sc.eq(await ops.json(`select coalesce(jsonb_agg(e.reason order by e.created_at, e.id), '[]'::jsonb)::text
    from app.card_provider_private_events e where e.action = 'operator.card_payments_pilot_updated'`)
    .then((r) => r.slice(events0)), ['ZC001D concurrent revision A', 'ZC001D concurrent revision B'],
  'exactly two operator events, in revision order');
}

// ---------------------------------------------------------------------------------------------------------
// C18 (SECURITY:325 "a session holding only app.card_identity_lock for the identity blocks the other's claim
//      and push after their terminal lock"): an owner session holds only the full-identity lock; a claim and
//      a push of that identity each take the d1 terminal lock and wait on the identity key, then complete with
//      their ordinary outcome after the holder commits or rolls back (the holder wrote nothing).
// ---------------------------------------------------------------------------------------------------------
async function c18IdentityLockAlone(sc) {
  await makeOrders('c18a', 'c18b', 'c18c', 'c18d');
  const k = await keyValues({ t1: terminalKeySql(1), purge: PURGE_KEY_SQL, a: identityKeySql(1, 'c18-a'),
    b: identityKeySql(1, 'c18-b'), c: identityKeySql(1, 'c18-c'), d: identityKeySql(1, 'c18-d') });
  const H = await sc.open('holder');
  const A = await sc.open('claim');
  const B = await sc.open('push');
  for (const { leg, S, end, kind } of [{ leg: 'a', S: A, end: 'commit', kind: 'claim' },
    { leg: 'b', S: A, end: 'rollback', kind: 'claim' }, { leg: 'c', S: B, end: 'commit', kind: 'cash' },
    { leg: 'd', S: B, end: 'rollback', kind: 'card' }]) {
    const label = `c18-${leg}`;
    const order = `c18${leg}`;
    await H.query(`begin; select app.card_identity_lock(${ORG}, ${dev(1)}, ${lop(label)});`);
    sc.eq(lockSet(await advisoryLocks(H)), lockSet([held(k[leg])]),
      `(${leg}) H (owner session) holds only the full-identity lock of ${label} (uncommitted)`);
    const p = S.json(kind === 'claim' ? svc(claimLive(1, label, order))
      : pos(push(1, payOp(label, order, kind, kind === 'cash' ? 2000 : 1234))));
    sc.detail[`${leg}_${kind}_waits_on_identity_lock`] = await provenWait(S, p, H, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(S)), lockSet(kind === 'claim' ? [held(k.t1), sharedHeld(k.purge), waiting(k[leg])]
      : [held(k.t1), waiting(k[leg])]),
    kind === 'claim' ? `(${leg}) the claim holds the d1 terminal lock and the shared purge barrier and waits on the identity key`
      : `(${leg}) the ${kind} push holds the d1 terminal lock and waits on the identity key`);
    await H.query(`${end};`);
    sc.eq(await advisoryLocks(H), [], `(${leg}) the holder's ${end} released the identity lock`);
    const r = await p;
    if (kind === 'claim') {
      sc.eq(pick(r, ['ok', 'claim_created', 'replayed', 'state', 'mode', 'local_operation_id']),
        { ok: true, claim_created: true, replayed: false, state: 'sent', mode: 'live', local_operation_id: nodeLop(label) },
        `(${leg}) after the holder's ${end}: the ordinary fresh claim`);
      sc.eq(pick(await attempt(1, label), ['state', 'order_id']), { state: 'sent', order_id: nodeId(`order-${order}`) },
        `(${leg}) exactly the one sent attempt row`);
    } else if (kind === 'cash') {
      sc.eq(pick(r.results[0], ['ok', 'status', 'idempotency_replay', 'local_operation_id', 'operation_type']),
        { ok: true, status: 'applied', idempotency_replay: false, local_operation_id: nodeLop(label), operation_type: 'payment.create' },
        `(${leg}) after the holder's ${end}: the cash push is applied`);
      sc.eq(await paymentMethods(1, label), 'cash:completed:1234', `(${leg}) exactly one cash payment`);
    } else {
      sc.eq(tsShape(r.results[0]), { ok: false, error: 'card_terminal_required', status: 'rejected', idempotency_replay: false,
        local_operation_id: nodeLop(label), operation_type: 'payment.create', order_id: nodeId(`order-${order}`), server_ts: 'string' },
      `(${leg}) after the holder's ${end}: the hand-recorded card push is refused card_terminal_required (enabled LIVE binding)`);
      sc.eq(await paymentsUnder(1, label), 0, `(${leg}) no payment`);
    }
  }
}

// ---------------------------------------------------------------------------------------------------------
// C19 (TEST phase; SECURITY:325 purge, two transactions): the purge of an expired TEST attempt against a
//      push and, separately, a claim of its identity holding the d2 terminal lock uncommitted: the purge waits
//      on that key, then deletes the attempt into the tombstone set (identity, digests, outbound keys); after
//      it a push of the identity is still refused test_attempt_not_recordable with no row and a claim of it is
//      identity_in_use. The purge-first order of the same pair is C5.
// ---------------------------------------------------------------------------------------------------------
const ageRetention = (rowId) => ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
with u as (update app.card_provider_attempts a set retention_until = clock_timestamp() - interval '1 second'
            where a.id = ${lit(rowId)}::uuid returning 1) select count(*) from u;
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
const tombstone = (d, label) => ops.json(`select coalesce((select jsonb_build_object('device_id', t.device_id,
  'local_operation_id', t.local_operation_id, 'provider_key_format_version', t.provider_key_format_version,
  'provider_query_key', t.provider_query_key, 'provider_duplicate_key', t.provider_duplicate_key,
  'digests_of_identity', t.provider_status_digest = app.card_identity_digest('card-status-key/v1', t.organization_id,
    t.device_id, t.local_operation_id) and t.provider_duplicate_digest = app.card_identity_digest('card-duplicate-key/v1',
    t.organization_id, t.device_id, t.local_operation_id))
  from app.card_attempt_identity_tombstones t where t.organization_id = ${ORG} and t.device_id = ${dev(d)}
   and t.local_operation_id = ${lop(label)}), 'null'::jsonb)::text`);
const recordingRefusals = (rowId) => count(`select count(*) from app.card_provider_private_events e
  where e.action = 'test.card_recording_refused' and e.attempt_row_id = ${lit(rowId)}::uuid`);

async function c19PurgeAfterHolders(sc) {
  await makeOrders('c19');
  const k = await keyValues({ t2: terminalKeySql(2), purge: PURGE_KEY_SQL, push: identityKeySql(2, 'c19-push'),
    claim: identityKeySql(2, 'c19-claim') });
  const P = await sc.open('push');
  const Q = await sc.open('claim');
  const G = await sc.open('purger');
  for (const leg of ['push', 'claim']) {
    const label = `c19-${leg}`;
    const t = await ops.json(svc(claimTest(8, label)));
    sc.eq([t.ok, t.claim_created, t.state, t.mode], [true, true, 'sent', 'test'], `(${leg}) TEST claim of ${label} on d2 committed`);
    sc.eq(await ageRetention(t.attempt_row_id), ['1'],
      `(${leg}) race database only: the attempt aged past its retention (frozen-fact trigger bypassed for that UPDATE)`);
    let holder;
    if (leg === 'push') {
      const pushed = (await P.json(posTx(push(8, payOp(label, 'c19'))))).results[0];
      sc.eq(tsShape(pushed), { ok: false, error: 'test_attempt_not_recordable', status: 'rejected', idempotency_replay: false,
        local_operation_id: nodeLop(label), operation_type: 'payment.create', order_id: nodeId('order-c19'), server_ts: 'string' },
      '(push) P: the pre-ledger TEST refusal (uncommitted)');
      sc.eq(lockSet(await advisoryLocks(P)), lockSet([held(k.t2), held(k.push)]),
        '(push) P holds the d2 terminal lock and the identity lock (never the purge barrier)');
      holder = P;
    } else {
      const replay = await Q.json(svcTx(claimTest(8, label)));
      sc.eq(pick(replay, ['ok', 'claim_created', 'replayed', 'state', 'mode', 'attempt_row_id']),
        { ok: true, claim_created: false, replayed: true, state: 'sent', mode: 'test', attempt_row_id: t.attempt_row_id },
        '(claim) Q: the claim of the expired identity replays its row (uncommitted)');
      sc.eq(lockSet(await advisoryLocks(Q)), lockSet([held(k.t2), sharedHeld(k.purge), held(k.claim)]),
        '(claim) Q holds the d2 terminal lock, the shared purge barrier and the identity lock');
      holder = Q;
    }
    const purgeP = G.json(`select ${PURGE_CALL}::text`);
    sc.detail[`purge_waits_for_${leg}`] = await provenWait(G, purgeP, holder, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(G)), lockSet([waiting(k.t2)]),
      `(${leg}) G (purge) waits on the d2 terminal lock before it takes the purge barrier`);
    await holder.query('commit;');
    const purged = await purgeP;
    sc.eq({ ...purged, cutoff: typeof purged.cutoff }, { ok: true, attempts_purged: 1, events_purged: 0,
      attempts_deferred: 0, events_deferred: 0, devices_locked: 1, cutoff: 'string' },
    `(${leg}) G: the purge deletes exactly the expired attempt once the ${leg} committed (C1-3: a one-device batch result, `
      + 'nothing deferred)');
    sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.id = ${lit(t.attempt_row_id)}::uuid`), 0,
      `(${leg}) the attempt row is gone`);
    sc.eq(await tombstone(2, label), { device_id: nodeId('device-2'), local_operation_id: nodeLop(label),
      provider_key_format_version: t.provider_key_format_version, provider_query_key: t.provider_query_key,
      provider_duplicate_key: t.provider_duplicate_key, digests_of_identity: true },
    `(${leg}) the tombstone keeps the identity, its digests and the outbound keys the claim returned`);
    const refusals = await recordingRefusals(t.attempt_row_id);
    sc.eq(refusals, leg === 'push' ? 1 : 0, `(${leg}) ${leg === 'push' ? "one test.card_recording_refused (P's)" : 'no private refusal event'}`);
    const again = (await ops.json(pos(push(8, payOp(label, 'c19'))))).results[0];
    sc.eq(pick(again, ['ok', 'error', 'status', 'idempotency_replay']),
      { ok: false, error: 'test_attempt_not_recordable', status: 'rejected', idempotency_replay: false },
      `(${leg}) after the purge: a push of the purged identity is still refused test_attempt_not_recordable`);
    sc.eq([await syncRow(2, label), await recordingRefusals(t.attempt_row_id)], [null, refusals],
      `(${leg}) after the purge: no sync_operations row and no further private event`);
    sc.eq(tsShape(await ops.json(svc(claimTest(8, label)))),
      { ok: false, error: 'conflict', detail: 'identity_in_use', server_ts: 'string' },
      `(${leg}) after the purge: a claim of the purged identity is identity_in_use`);
  }
  sc.detail.purge_first_order = 'CC-C5';
}

// ---------------------------------------------------------------------------------------------------------
// C20 (SECURITY:325 purge): a d1 claim whose outbound key is forced equal to a purged d2 TEST attempt's,
//      both orders against the purge: it serializes on the purge barrier and is refused identity_in_use either
//      way, from the ledger row before the purge and from the tombstone after it; no ledger row. The two TEST
//      attempts are claimed (and declined) in the TEST phase by c20Prepare; race database only, the key CHECKs
//      of the ledger and the tombstone set are dropped (as C8 does) and restored, validated.
// ---------------------------------------------------------------------------------------------------------
async function c20Prepare() {
  for (const label of ['c20-t1', 'c20-t2']) {
    const t = await ops.json(svc(claimTest(8, label)));
    assert.equal(t.claim_created, true, `C20 preparation: TEST claim ${label}: ${JSON.stringify(t)}`);
    const fin = await ops.json(svc(finish(t, 'commit', 'declined', DECLINED)));
    assert.equal(fin.state, 'declined', `C20 preparation: ${label} declined: ${JSON.stringify(fin)}`);
  }
}

async function c20ForcedKeyVsPurge(sc) {
  await makeOrders('c20a', 'c20b');
  sc.eq(await ops.json(`select coalesce(jsonb_object_agg(a.local_operation_id, a.mode || '/' || a.state), '{}'::jsonb)::text
    from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(2)}
     and a.local_operation_id in (${lop('c20-t1')}, ${lop('c20-t2')})`),
  { [nodeLop('c20-t1')]: 'test/declined', [nodeLop('c20-t2')]: 'test/declined' }, 'the TEST-phase attempts T1 / T2 of d2 exist (declined)');
  const wouldBe = (label) => `app.card_provider_key(app.card_identity_digest('card-status-key/v1', ${ORG}, ${dev(1)},
    ${lop(label)}), 'alpha16-l32-v1')`;
  const z = await keyValues({ z1: wouldBe('c20-z1'), z2: wouldBe('c20-z2') });
  const k = await keyValues({ t1: terminalKeySql(1), t2: terminalKeySql(2), purge: PURGE_KEY_SQL, z2: identityKeySql(1, 'c20-z2') });
  const defs = await ops.json(`select jsonb_build_object(
    'card_attempts_keys', (select pg_get_constraintdef(c.oid) from pg_constraint c
                            where c.conrelid = 'app.card_provider_attempts'::regclass and c.conname = 'card_attempts_keys'),
    'card_tombstones_keys', (select pg_get_constraintdef(c.oid) from pg_constraint c
                              where c.conrelid = 'app.card_attempt_identity_tombstones'::regclass and c.conname = 'card_tombstones_keys'))::text`);
  sc.ok(typeof defs.card_attempts_keys === 'string' && typeof defs.card_tombstones_keys === 'string', 'both key CHECK definitions captured');
  await ops.query(`alter table app.card_provider_attempts drop constraint card_attempts_keys;
alter table app.card_attempt_identity_tombstones drop constraint card_tombstones_keys;`);
  let A = null;
  let G = null;
  try {
    A = await sc.open('claim');
    G = await sc.open('purger');
    const force = (label, key) => ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
with u as (update app.card_provider_attempts a set provider_query_key = ${lit(key)},
                  retention_until = clock_timestamp() - interval '1 second'
            where a.organization_id = ${ORG} and a.device_id = ${dev(2)} and a.local_operation_id = ${lop(label)}
            returning 1) select count(*) from u;
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
    const identityInUse = { ok: false, error: 'conflict', detail: 'identity_in_use', server_ts: 'string' };
    // (1) the purge first: it holds the d2 terminal lock and the exclusive barrier; the claim waits on the barrier.
    sc.eq(await force('c20-t1', z.z1), ['1'],
      "(1) race database only: T1 (d2) carries the d1 claim Z1's would-be outbound query key and is expired");
    const purged1 = await G.json(`begin; select ${PURGE_CALL}::text;`);
    sc.eq({ ...purged1, cutoff: typeof purged1.cutoff }, { ok: true, attempts_purged: 1, events_purged: 0,
      attempts_deferred: 0, events_deferred: 0, devices_locked: 1, cutoff: 'string' },
    '(1) G: the purge deletes T1 into the tombstone set (uncommitted; C1-3: a one-device batch result, nothing deferred)');
    sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), held(k.purge)]),
      '(1) G holds the d2 terminal lock and the exclusive purge barrier');
    const z1P = A.json(svc(claimLive(1, 'c20-z1', 'c20a')));
    sc.detail.claim_waits_on_purge_barrier = await provenWait(A, z1P, G, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), sharedWaiting(k.purge)]),
      '(1) A (d1 claim of Z1) holds its own terminal lock and waits on the shared purge barrier');
    await G.query('commit;');
    sc.eq(tsShape(await z1P), identityInUse, '(1) A: identity_in_use from the tombstone once the purge committed');
    sc.eq(await attempt(1, 'c20-z1'), null, '(1) no ledger row for Z1');
    sc.eq((await tombstone(2, 'c20-t1'))?.provider_query_key, z.z1, "(1) the tombstone keeps T1's outbound key (= Z1's)");
    // (2) the claim first: it holds the shared barrier across its identity check; the purge waits on it.
    sc.eq(await force('c20-t2', z.z2), ['1'],
      "(2) race database only: T2 (d2) carries the d1 claim Z2's would-be outbound query key and is expired");
    sc.eq(tsShape(await A.json(svcTx(claimLive(1, 'c20-z2', 'c20b')))), identityInUse,
      '(2) A: identity_in_use from the ledger row before the purge (uncommitted)');
    sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), sharedHeld(k.purge), held(k.z2)]),
      '(2) A holds its terminal lock, the shared purge barrier and the identity lock of Z2');
    const purge2P = G.json(`select ${PURGE_CALL}::text`);
    sc.detail.purge_waits_on_claim_barrier = await provenWait(G, purge2P, A, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), waiting(k.purge)]),
      '(2) G (purge) holds the d2 terminal lock and waits for the exclusive purge barrier');
    await A.query('commit;');
    const purged2 = await purge2P;
    sc.eq({ ...purged2, cutoff: typeof purged2.cutoff }, { ok: true, attempts_purged: 1, events_purged: 0,
      attempts_deferred: 0, events_deferred: 0, devices_locked: 1, cutoff: 'string' },
    '(2) G: the purge deletes T2 once the claim committed (C1-3: a one-device batch result, nothing deferred)');
    sc.eq(tsShape(await A.json(svc(claimLive(1, 'c20-z2', 'c20b')))), identityInUse,
      '(2) a retry of Z2: identity_in_use from the tombstone after the purge');
    sc.eq(await attempt(1, 'c20-z2'), null, '(2) no ledger row for Z2');
    sc.eq((await tombstone(2, 'c20-t2'))?.provider_query_key, z.z2, "(2) the tombstone keeps T2's outbound key (= Z2's)");
  } finally {
    // Whatever happened above: end both sessions, remove the forced rows / tombstones, restore both CHECKs.
    for (const s of [A, G]) if (s) await s.close();
    await ops.query(`begin;
alter table app.card_attempt_identity_tombstones disable trigger card_tombstones_append_only;
delete from app.card_attempt_identity_tombstones t where t.organization_id = ${ORG} and t.device_id = ${dev(2)}
  and t.local_operation_id in (${lop('c20-t1')}, ${lop('c20-t2')});
alter table app.card_attempt_identity_tombstones enable trigger card_tombstones_append_only;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
delete from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(2)}
  and a.local_operation_id in (${lop('c20-t1')}, ${lop('c20-t2')});
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
    await ops.query(`alter table app.card_provider_attempts add constraint card_attempts_keys ${defs.card_attempts_keys};
alter table app.card_attempt_identity_tombstones add constraint card_tombstones_keys ${defs.card_tombstones_keys};`);
  }
  sc.eq(await count(`select count(*) from pg_constraint c where c.convalidated and ((c.conrelid = 'app.card_provider_attempts'::regclass
    and c.conname = 'card_attempts_keys') or (c.conrelid = 'app.card_attempt_identity_tombstones'::regclass
    and c.conname = 'card_tombstones_keys'))`), 2,
  'cleanup (race database only): the forced tombstones removed, both key CHECKs restored and validated');
}

// ---------------------------------------------------------------------------------------------------------
// C21 (TESTING_STRATEGY:173 "the lock order against app.edit_order deadlock-free"): an order.edit against a
//      claim and against the recording leg of the same order, both orders. Each pair serializes on the orders
//      row (the guard's FOR UPDATE, app.edit_order's first lock), never on an advisory key: no 40P01, every
//      outcome decided by the first commit.
// ---------------------------------------------------------------------------------------------------------
async function c21EditOrderLockOrder(sc) {
  sc.eq(await ops.one(`update public.branches b set order_edit_enabled = true, kitchen_workflow_mode = 'kds'
    where b.id = ${F}.zc_branch() returning b.order_edit_enabled::text || '/' || b.kitchen_workflow_mode`), 'true/kds',
  'race database only: order editing ON and the KDS channel on the pilot branch');
  const orders = ['c21a', 'c21b', 'c21c', 'c21d', 'c21e'];
  await makeOrders(...orders);
  await ops.query(`insert into public.menu_categories (id, organization_id, restaurant_id, name)
values (${id('menu-category-c21')}, ${ORG}, ${F}.zc_rest(), 'ZC001D edit category');
insert into public.menu_items (id, organization_id, restaurant_id, menu_category_id, name, base_price_minor, currency_code)
values (${id('menu-item-c21')}, ${ORG}, ${F}.zc_rest(), ${id('menu-category-c21')}, 'ZC001D edit item', 617, 'ILS');
insert into public.order_items (id, organization_id, restaurant_id, branch_id, order_id, menu_item_id, quantity,
                                menu_item_name_snapshot, unit_price_minor_snapshot, line_total_minor)
select ${F}.zc_id('item-' || l), ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${F}.zc_id('order-' || l),
       ${id('menu-item-c21')}, 2, 'ZC001D edit item', 617, 1234
  from unnest(array[${orders.map(lit).join(', ')}]::text[]) l;`);
  const k = await keyValues({ t1: terminalKeySql(1), purge: PURGE_KEY_SQL, x2: identityKeySql(1, 'c21-x2'),
    x4: identityKeySql(1, 'c21-x4'), x5: identityKeySql(1, 'c21-x5') });
  const orderState = (label) => ops.json(`select jsonb_build_object('revision', o.revision, 'status', o.status,
    'grand_total_minor', o.grand_total_minor, 'edit_count', o.edit_count,
    'order_edits', (select count(*) from public.order_edits e where e.order_id = o.id))::text
    from public.orders o where o.id = ${ord(label)}`);
  // One line, quantity 2 -> 3: 1234 -> 1851 (tax off on the pilot branch).
  const editOp = (label, orderLabel) => `jsonb_build_object('local_operation_id', ${lop(label)},
    'operation_type', 'order.edit', 'target_entity', 'order', 'target_id', ${ord(orderLabel)},
    'client_created_at', '2026-10-24T00:00:00Z', 'payload', jsonb_build_object('order_id', ${ord(orderLabel)},
      'expected', jsonb_build_object('subtotal_minor', 1851, 'tax_total_minor', 0, 'grand_total_minor', 1851),
      'changes', jsonb_build_array(jsonb_build_object('op', 'set_quantity', 'order_item_id', ${id(`item-${orderLabel}`)},
        'quantity', 3))))`;
  const guardRefusal = (label, orderLabel) => ({ ok: false, error: 'payment_in_progress', detail: 'card_attempt_active',
    status: 'rejected', idempotency_replay: false, local_operation_id: nodeLop(label), operation_type: 'order.edit',
    order_id: nodeId(`order-${orderLabel}`), server_ts: 'string' });
  const approvedAttempt = async (label, orderLabel) => {
    const c = await ops.json(svc(claimLive(1, label, orderLabel)));
    sc.eq([c.ok, c.claim_created], [true, true], `${label}: claimed`);
    sc.eq((await ops.json(svc(finish(c, 'commit', 'approved', APPROVED)))).state, 'approved', `${label}: approved`);
  };
  const rejectedAudits = (label) => count(`select count(*) from public.audit_events e where e.action = 'sync.operation_rejected'
    and e.new_values ->> 'local_operation_id' = ${lop(label)}`);
  const deadlocks0 = await deadlocks();
  const startedAt = await ops.one('select clock_timestamp()::text');
  const A = await sc.open('card');
  const B = await sc.open('edit');
  const E = await sc.open('edit_lock_set');

  // (1) the claim first: the edit waits on the orders row and is refused by the guard.
  const x1 = await A.json(svcTx(claimLive(1, 'c21-x1', 'c21a')));
  sc.eq(pick(x1, ['ok', 'claim_created', 'state']), { ok: true, claim_created: true, state: 'sent' },
    '(1) A: fresh LIVE claim of order c21a (uncommitted; it holds the orders row FOR UPDATE)');
  const e1P = B.json(pos(push(1, editOp('c21-e1', 'c21a'))));
  sc.detail.edit_waits_for_claim = await provenWait(B, e1P, A, ['transactionid', 'tuple']);
  sc.eq(await advisoryLocks(B), [], '(1) B (order.edit) waits on the orders row and holds no advisory lock');
  await A.query('commit;');
  sc.eq(tsShape((await e1P).results[0]), guardRefusal('c21-e1', 'c21a'),
    '(1) B: the guard refuses the edit payment_in_progress / card_attempt_active once the claim committed');
  sc.eq(await orderState('c21a'), { revision: 1, status: 'submitted', grand_total_minor: 1234, edit_count: 0, order_edits: 0 },
    '(1) no business write: the order unchanged, no order_edits row');
  sc.eq([pick(await syncRow(1, 'c21-e1'), ['status', 'rejection_reason']), await rejectedAudits('c21-e1')],
    [{ status: 'rejected', rejection_reason: 'payment_in_progress' }, 1], '(1) only the rejected sync row and its sync.operation_rejected audit');

  // (2) the edit first: the claim takes its advisory locks, waits on the orders row and sees the new revision.
  const e2 = (await B.json(posTx(push(1, editOp('c21-e2', 'c21b'))))).results[0];
  sc.eq(pick(e2, ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    "(2) B: the edit (quantity 2 -> 3) applied (uncommitted; it holds app.edit_order's lock set)");
  const x2P = A.json(svc(claimLive(1, 'c21-x2', 'c21b')));
  sc.detail.claim_waits_for_edit = await provenWait(A, x2P, B, ['transactionid', 'tuple']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), sharedHeld(k.purge), held(k.x2)]),
    '(2) A (claim) holds the terminal, purge-barrier and identity locks and waits only on the orders row');
  await B.query('commit;');
  sc.eq(tsShape(await x2P), { ok: false, error: 'conflict', server_ts: 'string' },
    '(2) A: conflict once the edit committed (orders.revision 1 -> 2 against expected_revision 1)');
  sc.eq(await attempt(1, 'c21-x2'), null, '(2) no attempt row');
  sc.eq(await orderState('c21b'), { revision: 2, status: 'submitted', grand_total_minor: 1851, edit_count: 1, order_edits: 1 },
    '(2) the committed edit is the order state');

  // (3) the recording leg first: the edit waits on the orders row and is refused order_already_settled.
  await approvedAttempt('c21-x3', 'c21c');
  const leg3 = (await A.json(posTx(push(1, payOp('c21-x3', 'c21c'))))).results[0];
  sc.eq(pick(leg3, ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    '(3) A: the recording leg of the approved attempt applied (uncommitted)');
  const e3P = B.json(pos(push(1, editOp('c21-e3', 'c21c'))));
  sc.detail.edit_waits_for_recording_leg = await provenWait(B, e3P, A, ['transactionid', 'tuple']);
  await A.query('commit;');
  sc.eq(tsShape((await e3P).results[0]), { ok: false, error: 'order_already_settled', status: 'rejected',
    idempotency_replay: false, local_operation_id: nodeLop('c21-e3'), operation_type: 'order.edit',
    order_id: nodeId('order-c21c'), server_ts: 'string' },
  '(3) B: app.edit_order refuses order_already_settled once the recording committed (the claim is no longer active)');
  sc.eq([await paymentMethods(1, 'c21-x3'), (await derived(1, 'c21-x3')).classification], ['card:completed:1234', 'recorded'],
    '(3) exactly one card payment; the attempt is recorded');
  sc.eq(pick(await orderState('c21c'), ['grand_total_minor', 'edit_count', 'order_edits']),
    { grand_total_minor: 1234, edit_count: 0, order_edits: 0 }, '(3) the order is not edited');

  // (4a) the edit first, refused by the guard while it holds the orders row; the recording leg waits, records.
  await approvedAttempt('c21-x4', 'c21d');
  const e4 = (await B.json(posTx(push(1, editOp('c21-e4', 'c21d'))))).results[0];
  sc.eq(tsShape(e4), guardRefusal('c21-e4', 'c21d'),
    '(4a) B: the edit of the approved, unrecorded order is refused by the guard, which holds the orders row (uncommitted)');
  const leg4P = A.json(pos(push(1, payOp('c21-x4', 'c21d'))));
  sc.detail.recording_leg_waits_for_edit = await provenWait(A, leg4P, B, ['transactionid', 'tuple']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), held(k.x4)]),
    '(4a) A (recording leg) holds the terminal and identity locks and waits only on the orders row');
  await B.query('commit;');
  sc.eq(pick((await leg4P).results[0], ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    '(4a) A: the recording leg records once the edit transaction committed');
  sc.eq(await paymentMethods(1, 'c21-x4'), 'card:completed:1234', '(4a) exactly one card payment');

  // (4b) an owner session holds app.edit_order's whole lock set in its order; the recording leg waits, records.
  await approvedAttempt('c21-x5', 'c21e');
  sc.eq(await E.query(`begin;
select o.id from public.orders o where o.id = ${ord('c21e')} for update;
select r.id from public.order_service_rounds r where r.order_id = ${ord('c21e')} order by r.id for update;
select oi.id from public.order_items oi where oi.order_id = ${ord('c21e')} order by oi.id for update;
select b.id from public.branches b where b.id = ${F}.zc_branch() for share;
select m.id from public.menu_items m where m.id = ${id('menu-item-c21')} for update;`),
  [nodeId('order-c21e'), nodeId('item-c21e'), PILOT_BRANCH_ID, nodeId('menu-item-c21')],
  '(4b) E holds the orders row, its rounds (none) and items FOR UPDATE, the branch FOR SHARE and the menu item FOR UPDATE');
  const leg5P = A.json(pos(push(1, payOp('c21-x5', 'c21e'))));
  sc.detail.recording_leg_waits_for_edit_lock_set = await provenWait(A, leg5P, E, ['transactionid', 'tuple']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), held(k.x5)]),
    '(4b) A (recording leg) holds the terminal and identity locks and waits only on the orders row');
  await E.query('commit;');
  sc.eq(pick((await leg5P).results[0], ['ok', 'status', 'idempotency_replay']), { ok: true, status: 'applied', idempotency_replay: false },
    "(4b) A: the recording leg records once the edit lock set is released");
  sc.eq(await paymentMethods(1, 'c21-x5'), 'card:completed:1234', '(4b) exactly one card payment');

  for (const s of [A, B, E]) { await s.query('select pg_stat_force_next_flush();'); await s.query('select 1;'); }
  await sleep(300);
  sc.eq(await deadlocks() - deadlocks0, 0, 'pg_stat_database counts no deadlock across the five legs');
  sc.eq(await count(`select count(*) from public.sync_operations so where so.created_at >= ${lit(startedAt)}::timestamptz
    and (so.last_error_code in ('40P01', '40001') or so.last_error_class = 'transient' or so.status not in ('applied', 'rejected'))`),
  0, 'no deadlock, serialization or transient ledger row');
}

// ---------------------------------------------------------------------------------------------------------
// C22 (review fix 11): two concurrent app.set_payment_terminal calls for d1 and d2 naming one credential_ref
//      in conflicting modes serialize on hashtextextended('card-credential-ref/v1:' || ref, 0); the second is
//      refused by the ownership rule (23514) and exactly one binding names the reference. Both orders. Runs
//      after every d1 claim (only C26 follows): it leaves d1's LIVE binding drained / rotated (re-enabling it
//      needs every d1 attempt resolved).
// ---------------------------------------------------------------------------------------------------------
async function c22CredentialReferenceLock(sc) {
  const [S1, S2] = ['zc-cred-shared-1', 'zc-cred-shared-2'];
  const k = await keyValues({ t1: terminalKeySql(1), t2: terminalKeySql(2), s1: credKeySql(S1), s2: credKeySql(S2) });
  const naming = (ref) => ops.one(`select coalesce(string_agg(case t.device_id when ${dev(1)} then 'd1' when ${dev(2)} then 'd2'
    else 'other' end || '/' || t.terminal_ref || '/' || t.mode || '/' || t.lifecycle, ',' order by t.created_at), 'none')
    from app.payment_terminals t where t.credential_ref = ${lit(ref)}`);
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'enabled'), 'start: the original LIVE binding of d1 is enabled');
  sc.eq(await currentBinding(2), 'none', 'start: d2 has no current binding (its TEST binding was retired)');
  sc.eq(await ops.json(`select ${liveCall(ORIGINAL_LIVE, 'draining', 'rotation')}::text`), changed('live', 'enabled', 'draining'),
    'd1 drained (committed): its only INSERT path is now the rotation');
  const A = await sc.open('live');
  const B = await sc.open('test');

  // (1) the TEST row first; the LIVE rotation naming the same reference waits, then raises 23514.
  sc.eq(await B.json(`begin; select ${terminalCall(2, 'test', ['zc-term-test-2s', S1], 'configured', 'test_setup')}::text;`),
    changed('test', null, 'configured'), `(1) B: a d2 TEST binding naming ${S1} (uncommitted)`);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([held(k.t2), held(k.s1)]),
    '(1) B holds the d2 terminal lock and the credential-reference lock');
  const events1 = await operatorEvents(1);
  const liveP = A.one(caught(liveCall(['zc-term-live-1s', S1], 'configured', 'rotation')));
  sc.detail.live_rotation_waits_on_credential_ref = await provenWait(A, liveP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), waiting(k.s1)]),
    '(1) A (d1 LIVE rotation) holds the d1 terminal lock and waits on the credential-reference lock');
  await B.query('commit;');
  sc.eq(await liveP, 'SQLSTATE:23514', '(1) A: the ownership rule raises 23514 once the TEST row committed');
  sc.eq(await naming(S1), 'd2/zc-term-test-2s/test/configured', `(1) exactly one binding names ${S1}`);
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'draining'),
    "(1) A's call rolled back whole: d1 still draining, no row retired or inserted");
  sc.eq(await operatorEvents(1) - events1, 0, '(1) no operator event for the refused rotation');

  // (2) the LIVE row first; the TEST binding naming the same reference waits, then raises 23514.
  sc.eq(await ops.json(`select ${terminalCall(2, 'test', ['zc-term-test-2s', S1], 'retired', 'test_end')}::text`),
    changed('test', 'configured', 'retired'), 'the d2 TEST row retired (committed)');
  sc.eq(await A.json(`begin; select ${liveCall(['zc-term-live-1t', S2], 'configured', 'rotation')}::text;`),
    changed('live', 'draining', 'configured', { replaced: true }), `(2) A: the d1 rotation naming ${S2} (uncommitted)`);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), held(k.s2)]),
    '(2) A holds the d1 terminal lock and the credential-reference lock');
  const events2 = await operatorEvents(2);
  const testP = B.one(caught(terminalCall(2, 'test', ['zc-term-test-2t', S2], 'configured', 'test_setup')));
  sc.detail.test_binding_waits_on_credential_ref = await provenWait(B, testP, A, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([held(k.t2), waiting(k.s2)]),
    '(2) B (d2 TEST binding) holds the d2 terminal lock and waits on the credential-reference lock');
  await A.query('commit;');
  sc.eq(await testP, 'SQLSTATE:23514', '(2) B: the ownership rule raises 23514 once the LIVE row committed');
  sc.eq(await naming(S2), 'd1/zc-term-live-1t/live/configured', `(2) exactly one binding names ${S2}`);
  sc.eq(await currentBinding(2), 'none', '(2) d2 has no current binding (nothing inserted)');
  sc.eq(await operatorEvents(2) - events2, 0, '(2) no operator event for the refused TEST binding');
}

// =========================================================================================================
// Test pass 3 (TEST_BRIEF_3 §C lane CC-2): C23–C25, numbered after C22 (and the C13 purge / order.edit
// sessions above).
// =========================================================================================================
// [action, detail] of every private event of one attempt row, oldest first.
const attemptEvents = (rowId) => ops.json(`select coalesce(jsonb_agg(jsonb_build_array(e.action, e.detail)
  order by e.created_at, e.id), '[]'::jsonb)::text from app.card_provider_private_events e
  where e.attempt_row_id = ${lit(rowId)}::uuid`);
const purgeOperatorEvents = () => count(`select count(*) from app.card_provider_private_events e
  where e.action = 'operator.card_test_attempts_purged'`);
// Makes each session's statistics visible, so pg_stat_database.deadlocks counts any deadlock it detected.
async function flushStats(list) {
  for (const s of list) { await s.query('select pg_stat_force_next_flush();'); await s.query('select 1;'); }
  await sleep(300);
}

// ---------------------------------------------------------------------------------------------------------
// C23 (TEST phase; SECURITY:325 "a purge and a card_attempt_finish of an expired TEST attempt, in both
//      orders, end without deadlock (the purge deletes the attempt rows before any event)"): the finish locks
//      only the attempt row (FOR UPDATE, no advisory key); the purge takes the d2 terminal lock and the
//      exclusive barrier, then the expired rows FOR UPDATE. (1) The finish first, writing a private
//      field-dropped event while it holds the row: the purge waits on the row, then deletes the finished
//      attempt into the tombstone set and keeps the event (not past its own retention). (2) The purge first:
//      the finish waits on the deleted row, then answers what app.card_attempt_finish answers for a row id
//      that no longer exists, {ok:false, error:attempt_not_found}, and writes nothing.
// ---------------------------------------------------------------------------------------------------------
async function c23PurgeVsFinish(sc) {
  const k = await keyValues({ t2: terminalKeySql(2), purge: PURGE_KEY_SQL });
  const FIN = await sc.open('finish');
  const G = await sc.open('purger');
  const deadlocks0 = await deadlocks();
  // C1-3: the batch result also reports what stays deferred and how many device terminal locks it took.
  const purgedOne = { ok: true, attempts_purged: 1, events_purged: 0, attempts_deferred: 0, events_deferred: 0,
    devices_locked: 1, cutoff: 'string' };
  // A decline whose provider_saved_at fails its format rule: one security.card_provider_field_dropped event.
  const declinedSavedNow = { ...DECLINED, provider_saved_at: 'now' };
  const expiredTestAttempt = async (leg, label) => {
    const t = await ops.json(svc(claimTest(8, label)));
    sc.eq([t.ok, t.claim_created, t.state, t.mode], [true, true, 'sent', 'test'], `(${leg}) TEST claim of ${label} on d2 committed`);
    sc.eq(await ageRetention(t.attempt_row_id), ['1'],
      `(${leg}) race database only: the attempt aged past its retention (frozen-fact trigger bypassed for that UPDATE)`);
    return t;
  };
  const tombstoned = async (leg, label, t) => sc.eq(await tombstone(2, label), { device_id: nodeId('device-2'),
    local_operation_id: nodeLop(label), provider_key_format_version: t.provider_key_format_version,
    provider_query_key: t.provider_query_key, provider_duplicate_key: t.provider_duplicate_key, digests_of_identity: true },
  `(${leg}) the tombstone keeps the identity, its digests and the outbound keys the claim returned`);

  // (1) The finish first.
  const t1 = await expiredTestAttempt(1, 'c23-f');
  const events1 = await attemptEvents(t1.attempt_row_id);
  const purges1 = await purgeOperatorEvents();
  const finished = await FIN.json(svcTx(finish(t1, 'commit', 'declined', declinedSavedNow)));
  sc.eq(tsShape(finished), { ok: true, attempt_id: nodeLop('c23-f'), state: 'declined', classification: 'test_declined',
    recorded: false, amount_minor: 1234, currency_code: 'ILS', server_ts: 'string' },
  '(1) F: card_attempt_finish declines the expired TEST attempt (uncommitted; it holds the attempt row)');
  sc.eq(await advisoryLocks(FIN), [], '(1) F (card_attempt_finish) holds no advisory lock');
  const purgeP = G.json(`select ${PURGE_CALL}::text`);
  sc.detail.purge_waits_for_finish = await provenWait(G, purgeP, FIN, ['transactionid', 'tuple']);
  sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), held(k.purge)]),
    '(1) G (purge) holds the d2 terminal lock and the exclusive purge barrier and waits only on the attempt row');
  await FIN.query('commit;');
  const purged1 = await purgeP;
  sc.eq({ ...purged1, cutoff: typeof purged1.cutoff }, purgedOne, '(1) G: the purge deletes the finished attempt once the finish committed');
  sc.eq(await identityRows(2, 'c23-f'), [0, 1], '(1) no ledger row, one tombstone');
  await tombstoned(1, 'c23-f', t1);
  sc.eq(await attemptEvents(t1.attempt_row_id), [...events1, ['security.card_provider_field_dropped',
    { field: 'provider_saved_at', rule: 'format', source: 'commit' }]],
  "(1) exactly the finish's one private event is added and kept (not past its own retention): the purge deleted the row, not the event");
  sc.eq(await purgeOperatorEvents() - purges1, 1, '(1) one purge operator event');

  // (2) The purge first.
  const t2 = await expiredTestAttempt(2, 'c23-p');
  const events2 = await attemptEvents(t2.attempt_row_id);
  const purges2 = await purgeOperatorEvents();
  const purged2 = await G.json(`begin; select ${PURGE_CALL}::text;`);
  sc.eq({ ...purged2, cutoff: typeof purged2.cutoff }, purgedOne, '(2) G: the purge deletes the expired attempt (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), held(k.purge)]),
    '(2) G holds the d2 terminal lock and the exclusive purge barrier');
  const lateP = FIN.json(svc(finish(t2, 'commit', 'declined', declinedSavedNow)));
  sc.detail.finish_waits_for_purge = await provenWait(FIN, lateP, G, ['transactionid', 'tuple']);
  sc.eq(await advisoryLocks(FIN), [], '(2) F (card_attempt_finish) waits on the deleted attempt row and holds no advisory lock');
  await G.query('commit;');
  sc.eq(tsShape(await lateP), { ok: false, error: 'attempt_not_found', server_ts: 'string' },
    '(2) F: exactly {ok:false, error:attempt_not_found} once the purge committed (its FOR UPDATE finds no row)');
  sc.eq(await identityRows(2, 'c23-p'), [0, 1], '(2) the late finish wrote no ledger row; one tombstone');
  await tombstoned(2, 'c23-p', t2);
  sc.eq(await attemptEvents(t2.attempt_row_id), events2, '(2) the late finish wrote no private event (it answers before the field rules)');
  sc.eq(await purgeOperatorEvents() - purges2, 1, '(2) one purge operator event');
  sc.eq(tsShape(await ops.json(svc(finish(t2, 'lookup', 'pending', {}, 'auto')))), { ok: false, error: 'attempt_not_found', server_ts: 'string' },
    '(2) a later finish of the purged row id answers attempt_not_found again');
  await flushStats([FIN, G]);
  sc.eq(await deadlocks() - deadlocks0, 0, 'pg_stat_database counts no deadlock in either order');
}

// ---------------------------------------------------------------------------------------------------------
// C24 (SECURITY:325 "the guard decides the deferral on the membership row it reads FOR SHARE, so a grant
//      committed before that read makes it not defer and a grant committed after it waits until the dispatch
//      ends (both interleavings tested)"): app.card_dispatch_certain_deny reads the PIN session's membership
//      FOR SHARE. For staff 4 (kitchen_staff) a payment.create is certain to be denied (its role), so
//      app.card_claim_guard defers to app.record_payment's own refusal (permission_denied with its
//      payment.denied audit), never payment_in_progress; for a cashier it does not defer and refuses the
//      claimed order payment_in_progress / card_attempt_active. (i) The grant (kitchen_staff -> cashier) is
//      uncommitted when the push reaches that read: the push waits on the membership row and decides on the
//      committed grant. (ii) The push has read the row (deferred; the RPC's refusal returned) and its
//      transaction is open: the grant waits on the membership row until the push transaction ends, the push's
//      answer is the pre-grant one, and a later push decides on the grant.
// ---------------------------------------------------------------------------------------------------------
async function c24MembershipForShare(sc) {
  await makeOrders('c24');
  const k = await keyValues({ t1: terminalKeySql(1), i: identityKeySql(1, 'c24-i'), ii: identityKeySql(1, 'c24-ii') });
  const membership4 = id('membership-4');
  const role4 = () => ops.one(`select m.role from public.memberships m where m.id = ${membership4}`);
  const setRole4 = (role) => `update public.memberships m set role = ${lit(role)} where m.id = ${membership4} returning m.role`;
  // pg_locks: `waiter` holds the tuple lock of a row (the relations named) and waits on a transaction id that
  // `holder` holds: a row-lock wait on that row.
  const rowWait = (waiter, holder) => ops.json(`select jsonb_build_object(
    'tuple_lock_relations', (select coalesce(jsonb_agg(distinct n.nspname || '.' || c.relname), '[]'::jsonb)
       from pg_locks l join pg_class c on c.oid = l.relation join pg_namespace n on n.oid = c.relnamespace
      where l.pid = ${waiter.pid} and l.locktype = 'tuple' and l.granted),
    'waits_on_holder_transaction', exists (select 1 from pg_locks w join pg_locks h on h.locktype = 'transactionid'
       and h.transactionid = w.transactionid and h.granted and h.pid = ${holder.pid}
      where w.pid = ${waiter.pid} and w.locktype = 'transactionid' and not w.granted))::text`);
  const paymentDenied = () => count(`select count(*) from public.audit_events e where e.action = 'payment.denied'
    and e.actor_employee_profile_id = ${id('employee-4')} and e.new_values ->> 'order_id' = ${ord('c24')}::text`);
  const rejectedAudits = (label) => count(`select count(*) from public.audit_events e where e.action = 'sync.operation_rejected'
    and e.new_values ->> 'local_operation_id' = ${lop(label)}`);
  const guardRefusal = (label) => ({ ok: false, error: 'payment_in_progress', detail: 'card_attempt_active', status: 'rejected',
    idempotency_replay: false, local_operation_id: nodeLop(label), operation_type: 'payment.create',
    order_id: nodeId('order-c24'), server_ts: 'string' });
  const cashPush = (label) => push(4, payOp(label, 'c24', 'cash', 2000));
  sc.eq(await role4(), 'kitchen_staff', 'start: staff 4 holds the fixture kitchen_staff role');
  const claimed = await ops.json(svc(claimLive(1, 'c24-x', 'c24')));
  sc.eq(pick(claimed, ['ok', 'claim_created', 'state']), { ok: true, claim_created: true, state: 'sent' },
    'a committed LIVE claim keeps order c24 claimed');
  const A = await sc.open('push');
  const G = await sc.open('grant');
  try {
    // (i) The grant is uncommitted when the push reaches the guard's FOR SHARE read.
    const denied0 = await paymentDenied();
    sc.eq(await G.one(`begin; ${setRole4('cashier')};`), 'cashier', '(i) G: staff 4 kitchen_staff -> cashier (uncommitted)');
    const iP = A.json(pos(cashPush('c24-i')));
    sc.detail.i_push_waits_on_uncommitted_grant = await provenWait(A, iP, G, ['transactionid', 'tuple']);
    sc.eq(await rowWait(A, G), { tuple_lock_relations: ['public.memberships'], waits_on_holder_transaction: true },
      "(i) A waits on the membership row G updated (it holds that row's tuple lock and waits on G's transaction)");
    sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), held(k.i)]),
      '(i) A already holds the d1 terminal lock and the identity lock: it waits inside the claim guard');
    await G.query('commit;');
    sc.eq(tsShape((await iP).results[0]), guardRefusal('c24-i'),
      '(i) A: the guard read the committed grant, did not defer, and refused the claimed order payment_in_progress');
    sc.eq([await paymentsUnder(1, 'c24-i'), await paymentDenied() - denied0, await rejectedAudits('c24-i')], [0, 0, 1],
      '(i) no payment and no payment.denied (app.record_payment never ran); one sync.operation_rejected');
    sc.eq(await ops.one(setRole4('kitchen_staff')), 'kitchen_staff', 'between the legs: staff 4 is kitchen_staff again (committed)');

    // (ii) The push has read the row and its transaction is open; the grant is attempted after the read.
    const ii = (await A.json(posTx(cashPush('c24-ii')))).results[0];
    sc.eq(tsShape(ii), { ok: false, error: 'permission_denied', order_id: nodeId('order-c24'), server_ts: 'string',
      idempotency_replay: false, local_operation_id: nodeLop('c24-ii'), operation_type: 'payment.create', status: 'rejected' },
    "(ii) A: deferred to app.record_payment's own refusal, exactly its permission_denied envelope (uncommitted; the dispatch ended)");
    sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), held(k.ii)]),
      '(ii) A still holds the d1 terminal lock and the identity lock (its transaction is open)');
    const gP = G.one(setRole4('cashier'));
    sc.detail.ii_grant_waits_for_push_transaction = await provenWait(G, gP, A, ['transactionid', 'tuple']);
    sc.eq(await rowWait(G, A), { tuple_lock_relations: ['public.memberships'], waits_on_holder_transaction: true },
      "(ii) G waits on the membership row A read FOR SHARE (it holds that row's tuple lock and waits on A's transaction)");
    sc.eq(await role4(), 'kitchen_staff', '(ii) while G waits the committed role is still kitchen_staff');
    await A.query('commit;');
    sc.eq(await gP, 'cashier', '(ii) G: the grant applies once the push transaction ended');
    sc.eq([await paymentsUnder(1, 'c24-ii'), await paymentDenied() - denied0, await rejectedAudits('c24-ii'),
      pick(await syncRow(1, 'c24-ii'), ['status', 'rejection_reason'])],
    [0, 1, 1, { status: 'rejected', rejection_reason: 'permission_denied' }],
    "(ii) no payment; the RPC's own payment.denied audit and one sync.operation_rejected; memoized rejected permission_denied");
    sc.eq(tsShape((await A.json(pos(cashPush('c24-iii')))).results[0]), guardRefusal('c24-iii'),
      '(ii) a later push of staff 4 (now cashier) is not deferred: payment_in_progress');
    sc.eq([await paymentsUnder(1, 'c24-iii'), await paymentDenied() - denied0], [0, 1], '(ii) no payment, no further payment.denied');
  } finally {
    // Whatever happened above: end both sessions (releasing any row lock), then restore the fixture role.
    for (const s of [A, G]) await s.close();
    await ops.query(`${setRole4('kitchen_staff')};`);
  }
  sc.eq(await role4(), 'kitchen_staff', 'cleanup: staff 4 holds the fixture kitchen_staff role again');
  sc.eq((await ops.json(svc(finish(claimed, 'commit', 'declined', DECLINED)))).state, 'declined', 'cleanup: the claim is declined');
}

// ---------------------------------------------------------------------------------------------------------
// C25 (review fix 20; TEST_BRIEF_3 §C item 4): the freshness race. A begins a transaction (its now() = T_A)
//      before M commits the recording-result mark of an approved attempt's permission_denied refusal (stamp
//      t_M); A then pushes the manager Resume (authorized; the guard's history entry `at` = T_G), whose
//      re-dispatch is refused again with the same token by a forced P0001 'permission_denied' raise on the
//      payments insert (race database only; this identity, A's transaction only), and commits. The sync row's
//      updated_at is stamped by its trigger with A's now() (T_A < t_M), so only the last-Resume rule (t_M < T_G)
//      makes the report stale: the next Resume answers refusal_not_recorded with its bounded audit and no
//      dispatch; a new mark re-stamps (one more card_attempt.recording_refused) and the following Resume is
//      authorized and records exactly once.
// ---------------------------------------------------------------------------------------------------------
async function c25FreshnessRace(sc) {
  await makeOrders('c25');
  const label = 'c25-x';
  const claimed = await ops.json(svc(claimLive(1, label, 'c25')));
  sc.eq([claimed.ok, claimed.claim_created], [true, true], 'the LIVE attempt is claimed');
  sc.eq((await ops.json(svc(finish(claimed, 'commit', 'approved', APPROVED)))).state, 'approved', 'the attempt is approved');
  const kitchen = (await ops.json(pos(push(4, payOp(label, 'c25'))))).results[0];
  sc.eq(pick(kitchen, ['ok', 'error', 'status']), { ok: false, error: 'permission_denied', status: 'rejected' },
    'the leg pushed under the kitchen PIN session is memoized permission_denied');
  const resumeOp = (n) => payOp(label, 'c25', 'card', 1234, { recording_resume: n });
  const resumeAudits = () => ops.json(`select coalesce(jsonb_agg(jsonb_build_array(e.new_values ->> 'outcome',
    e.new_values -> 'resume_count', e.new_values ->> 'denied_reason', e.new_values ->> 'prior_refusal_code')
    order by e.created_at, e.id), '[]'::jsonb)::text from public.audit_events e
    where e.action = 'card_attempt.recording_resume_requested' and e.new_values ->> 'local_operation_id' = ${lop(label)}`);
  const reportAudits = () => count(`select count(*) from public.audit_events e where e.action = 'card_attempt.recording_refused'
    and e.device_id = ${dev(1)}`);
  const rejectedAudits = () => count(`select count(*) from public.audit_events e where e.action = 'sync.operation_rejected'
    and e.new_values ->> 'local_operation_id' = ${lop(label)}`);
  // The attempt's report / Resume facts and its sync row (timestamps as text, microseconds kept).
  const facts = () => ops.json(`select jsonb_build_object('refusal_code', a.refusal_code,
    'recording_refused_at', a.recording_refused_at::text, 'resume_count', a.recording_resume_count,
    'last_resume_at', (a.recording_resume_history -> -1 ->> 'at')::timestamptz::text,
    'resume_history', jsonb_array_length(a.recording_resume_history),
    'refusal_history', jsonb_array_length(a.recording_refusal_history),
    'so_status', so.status, 'so_reason', so.rejection_reason, 'so_retry_count', so.retry_count,
    'so_updated_at', so.updated_at::text)::text
    from app.card_provider_attempts a join public.sync_operations so on so.organization_id = a.organization_id
     and so.device_id = a.device_id and so.local_operation_id = a.local_operation_id
   where a.organization_id = ${ORG} and a.device_id = ${dev(1)} and a.local_operation_id = ${lop(label)}`);
  const precedes = (x, y) => ops.one(`select (${lit(x)}::timestamptz < ${lit(y)}::timestamptz)::text`);
  const sameInstant = (x, y) => ops.one(`select (${lit(x)}::timestamptz = ${lit(y)}::timestamptz)::text`);
  const f0 = await facts();
  sc.eq({ ...f0, so_updated_at: typeof f0.so_updated_at }, { refusal_code: null, recording_refused_at: null, resume_count: 0,
    last_resume_at: null, resume_history: 0, refusal_history: 0, so_status: 'rejected', so_reason: 'permission_denied',
    so_retry_count: 0, so_updated_at: 'string' },
  'the refusal is not reported yet; no Resume; the sync row rejected permission_denied');
  const reports0 = await reportAudits();
  const rejected0 = await rejectedAudits();
  sc.eq(rejected0, 1, "the kitchen leg's one sync.operation_rejected");
  // Race database only: a payments insert of THIS identity raises P0001 'permission_denied' while the
  // transaction-local zc001d.c25_fault_lop names it (A sets it only for its Resume).
  await ops.query(`create function ${F}.zc_c25_fault() returns trigger language plpgsql as $zc$
begin
  if new.local_operation_id = current_setting('zc001d.c25_fault_lop', true) then
    raise exception 'permission_denied' using errcode = 'P0001';
  end if;
  return new;
end $zc$;
create trigger zc_c25_fault before insert on public.payments for each row execute function ${F}.zc_c25_fault();`);
  let A = null;
  let M = null;
  try {
    A = await sc.open('resume');
    M = await sc.open('mark');
    const marked = (resumeCount) => ({ ok: true, attempt_id: nodeLop(label), state: 'approved',
      classification: 'approved_unrecorded', recorded: false, amount_minor: 1234, currency_code: 'ILS',
      provider_return_code: 0, refusal_code: 'permission_denied', recoverable: true, resume_count: resumeCount, server_ts: 'string' });

    // A's transaction starts before M's mark commits.
    const tA = await A.one('begin; select now()::text;');
    await sleep(5);
    sc.eq(tsShape(await M.json(svc(markRefused(label, 'permission_denied')))), marked(0),
      'M: the recording-result mark reports the recoverable permission_denied refusal (committed)');
    const f1 = await facts();
    const tM = f1.recording_refused_at;
    sc.eq([await precedes(tA, tM), await reportAudits() - reports0], ['true', 1],
      "M's stamp is later than A's now() (A's transaction began first); one card_attempt.recording_refused");
    await sleep(5);
    // A pushes the manager Resume: authorized, re-dispatched, refused again by the forced raise.
    await A.query(`select set_config('zc001d.c25_fault_lop', ${lop(label)}, true);`);
    sc.eq((await A.json(pos(push(2, resumeOp(0))))).results[0], { local_operation_id: nodeLop(label),
      operation_type: 'payment.create', ok: false, error: 'rejected', sqlstate: 'P0001', detail: null, status: 'rejected',
      idempotency_replay: false },
    "A: the manager Resume is authorized and its re-dispatch is refused again with the same token (forced P0001 'permission_denied')");
    await A.query('commit;');
    const f2 = await facts();
    sc.eq({ ...f2, last_resume_at: typeof f2.last_resume_at, so_updated_at: typeof f2.so_updated_at },
      { refusal_code: 'permission_denied', recording_refused_at: tM, resume_count: 1, last_resume_at: 'string',
        resume_history: 1, refusal_history: 1, so_status: 'rejected', so_reason: 'permission_denied', so_retry_count: 1,
        so_updated_at: 'string' },
    "after A's commit: the stored report is unchanged (review fix 6), one authorized Resume, the row rejected permission_denied again");
    sc.eq([await precedes(tA, tM), await precedes(tM, f2.last_resume_at)], ['true', 'true'],
      "the ordering: A's now() < M's stamp < the authorized Resume's `at` (A's guard clock)");
    sc.eq([await sameInstant(f2.so_updated_at, tA), await precedes(tM, f2.so_updated_at)], ['true', 'false'],
      "the sync row's updated_at is A's now() (its trigger stamps now()), so the report does NOT predate the row's latest "
        + 'rejection: only the last-Resume rule (review fix 20) can make it stale');
    sc.eq([await paymentsUnder(1, label), await resumeAudits(), await rejectedAudits() - rejected0],
      [0, [['dispatched', 0, null, 'permission_denied']], 1], 'no payment; one dispatched Resume audit; one more sync.operation_rejected');

    // The next Resume (no new report): refusal_not_recorded, bounded audit, no dispatch.
    const replayDenied = { ok: false, error: 'rejected', sqlstate: 'P0001', detail: null, local_operation_id: nodeLop(label),
      operation_type: 'payment.create', status: 'rejected', idempotency_replay: true, resume_denied: 'refusal_not_recorded' };
    for (const attemptNo of [1, 2]) {
      sc.eq((await A.json(pos(push(2, resumeOp(1))))).results[0], replayDenied,
        `next Resume #${attemptNo} (recording_resume 1, no new report): the stored result replayed with resume_denied refusal_not_recorded`);
      sc.eq([await facts(), await paymentsUnder(1, label), await resumeAudits()],
        [f2, 0, [['dispatched', 0, null, 'permission_denied'], ['refused', 1, 'refusal_not_recorded', 'permission_denied']]],
        `next Resume #${attemptNo}: nothing dispatched or changed; exactly one bounded refused audit (resume_count 1)`);
    }

    // A new mark re-stamps the report; the following Resume is authorized and records exactly once.
    sc.eq(tsShape(await M.json(svc(markRefused(label, 'permission_denied')))), marked(1),
      'M: a new mark of the same token re-stamps (the report predated the last authorized Resume)');
    const f3 = await facts();
    sc.eq([await precedes(f2.last_resume_at, f3.recording_refused_at), await reportAudits() - reports0], ['true', 2],
      'the new stamp is later than the authorized Resume; exactly one more card_attempt.recording_refused');
    const recorded = (await A.json(pos(push(2, resumeOp(1))))).results[0];
    sc.eq(pick(recorded, ['ok', 'status', 'idempotency_replay', 'local_operation_id', 'operation_type']),
      { ok: true, status: 'applied', idempotency_replay: false, local_operation_id: nodeLop(label), operation_type: 'payment.create' },
      'the following Resume (recording_resume 1) is authorized and records');
    sc.eq([await paymentMethods(1, label), (await derived(1, label)).classification, (await attempt(1, label)).recording_resume_count],
      ['card:completed:1234', 'recorded', 2], 'exactly one card payment; the attempt is recorded; two authorized Resumes');
    sc.eq((await resumeAudits()).filter((x) => x[0] === 'dispatched'), [['dispatched', 0, null, 'permission_denied'],
      ['dispatched', 1, null, 'permission_denied']], 'two dispatched Resume audits (resume_count 0 and 1)');
    const again = (await A.json(pos(push(2, resumeOp(1))))).results[0];
    sc.eq(pick(again, ['status', 'idempotency_replay', 'payment_id']), { status: 'applied', idempotency_replay: true,
      payment_id: recorded.payment_id }, 'a further resend replays the recording');
    sc.eq(await paymentsUnder(1, label), 1, 'still exactly one payment');
    sc.detail.ordering = { a_now: tA, m_stamp: tM, a_guard_at: f2.last_resume_at, sync_row_updated_at: f2.so_updated_at,
      new_stamp: f3.recording_refused_at };
  } finally {
    for (const s of [A, M]) if (s) await s.close();
    await ops.query(`drop trigger if exists zc_c25_fault on public.payments; drop function if exists ${F}.zc_c25_fault();`);
  }
  sc.eq(await count(`select count(*) from pg_trigger t where t.tgname = 'zc_c25_fault'`), 0, 'cleanup (race database only): the forced-fault trigger dropped');
}

// =========================================================================================================
// Correction C1 (TEST_BRIEF_C1 §C lane CC): C26–C32, numbered after C25.
// =========================================================================================================
// The bounded TEST purge of C1-3: one batch of at most `maxDevices` devices (null = unbounded). It runs through
// `caught`, so a raise (e.g. the pre-fix three-argument signature: 42883) is answered 'SQLSTATE:<code>' and the
// session survives it; `purgeBatch` parses the answer (inside an open transaction when `open`).
const purgeCall = (maxDevices) => `app.purge_expired_test_card_attempts('ZC001D synthetic purge', 'zc001d-op/ref-3',
  ${OWNER}, ${maxDevices === null ? 'null::integer' : Number(maxDevices)})`;
const purgeText = (maxDevices) => caught(purgeCall(maxDevices));
const parsedJson = (text, what) => {
  assert.ok(typeof text === 'string' && !text.startsWith('SQLSTATE:'), `${what} raised ${text}`);
  return JSON.parse(text);
};
const purgeBatch = (session, maxDevices, open = false) => handled(session.one(`${open ? 'begin; ' : ''}${purgeText(maxDevices)}`)
  .then((text) => parsedJson(text, `the purge batch (p_max_devices ${maxDevices})`)));
// The C1-3 batch result, its cut-off replaced by its JSON type.
const batchShape = (r) => (r && typeof r === 'object' && 'cutoff' in r ? { ...r, cutoff: typeof r.cutoff } : r);
const batch = (attempts, events, attemptsDeferred, eventsDeferred, devices) => ({ ok: true, attempts_purged: attempts,
  events_purged: events, attempts_deferred: attemptsDeferred, events_deferred: eventsDeferred, devices_locked: devices,
  cutoff: 'string' });
const lastPurgeDetail = () => ops.json(`select e.detail::text from app.card_provider_private_events e
  where e.action = 'operator.card_test_attempts_purged' order by e.created_at desc, e.id desc limit 1`);
// The purge-eligible TEST rows right now, per device: expired and unheld (an event also needs an unheld attempt).
const deviceLabel = (column) => `case ${column} when ${dev(1)} then 'd1' when ${dev(2)} then 'd2' else 'other' end`;
const eligibleSet = () => ops.json(`select jsonb_build_object(
  'attempts', (select coalesce(jsonb_object_agg(x.d, x.n), '{}'::jsonb) from (
      select ${deviceLabel('a.device_id')} d, count(*) n from app.card_provider_attempts a
       where a.mode = 'test' and a.retention_until <= clock_timestamp() and a.incident_hold_at is null group by 1) x),
  'events', (select coalesce(jsonb_object_agg(x.d, x.n), '{}'::jsonb) from (
      select ${deviceLabel('e.device_id')} d, count(*) n from app.card_provider_private_events e
       where e.mode = 'test' and e.retention_until <= clock_timestamp() and e.incident_hold_at is null
         and not exists (select 1 from app.card_provider_attempts a where a.id = e.attempt_row_id
                          and a.incident_hold_at is not null) group by 1) x))::text`);
// Race database only: one TEST event's retention moved into the past (its immutability trigger bypassed for that
// one UPDATE, called between legs while no other session holds the table).
const ageEvent = (eventId) => ops.query(`begin;
alter table app.card_provider_private_events disable trigger card_events_guard;
with u as (update app.card_provider_private_events e set retention_until = clock_timestamp() - interval '1 second'
            where e.id = ${lit(eventId)}::uuid and e.mode = 'test' returning 1) select count(*) from u;
alter table app.card_provider_private_events enable trigger card_events_guard;
commit;`);
const eventIds = (action, d) => ops.json(`select coalesce(jsonb_agg(e.id order by e.created_at, e.id), '[]'::jsonb)::text
  from app.card_provider_private_events e where e.action = ${lit(action)} and e.device_id = ${dev(d)}`);
const eventExists = (eventId) => ops.one(`select exists (select 1 from app.card_provider_private_events e
  where e.id = ${lit(eventId)}::uuid)::text`);
const refusalEventIds = (rowId) => ops.json(`select coalesce(jsonb_agg(e.id order by e.created_at, e.id), '[]'::jsonb)::text
  from app.card_provider_private_events e where e.action = 'test.card_recording_refused' and e.attempt_row_id = ${lit(rowId)}::uuid`);
// A TEST attempt of d2 (cashier 8), declined and (unless age:false) aged past its retention (race database only).
async function agedDeclinedTest(sc, label, { age = true } = {}) {
  const t = await ops.json(svc(claimTest(8, label)));
  sc.eq([t.ok, t.claim_created, t.state, t.mode], [true, true, 'sent', 'test'], `${label}: TEST claim on d2`);
  sc.eq((await ops.json(svc(finish(t, 'commit', 'declined', DECLINED)))).state, 'declined', `${label}: declined`);
  if (age) sc.eq(await ageRetention(t.attempt_row_id), ['1'], `${label}: race database only: aged past its retention`);
  return t;
}
// One attempt-less TEST denial event of device d, aged past its retention (race database only): on d1 a TEST claim
// under the kitchen PIN (a proof-level permission_denied with a proven scope), on d2 a TEST claim over the pilot's
// TEST cap (precondition_failed / max_test_amount_exceeded). Answers the event id.
async function agedTestDenial(sc, d, label) {
  const before = await eventIds('test.card_attempt_denied', d);
  const refused = await ops.json(svc(d === 1 ? claimTest(4, label) : claimTest(8, label, 100001)));
  sc.eq(tsShape(refused), d === 1 ? { ok: false, error: 'permission_denied', server_ts: 'string' }
    : { ok: false, error: 'precondition_failed', detail: 'max_test_amount_exceeded', server_ts: 'string' },
  `${label}: the TEST claim on d${d} is refused with denial evidence`);
  const fresh = (await eventIds('test.card_attempt_denied', d)).filter((x) => !before.includes(x));
  sc.eq(fresh.length, 1, `${label}: exactly one attempt-less test.card_attempt_denied event on d${d}`);
  sc.eq(await ageEvent(fresh[0]), ['1'], `${label}: race database only: the event aged past its retention`);
  return fresh[0];
}
const holdCall = (kind, targetId, on, reference = null) => `app.card_attempt_set_incident_hold(${lit(kind)},
  ${lit(targetId)}::uuid, ${on}, ${on ? lit(reference) : 'null'}, 'ZC001D synthetic incident hold', 'zc001d-op/ref-5', ${OWNER})`;
const attemptHold = (rowId) => ops.json(`select coalesce((select jsonb_build_object('held', a.incident_hold_at is not null,
  'state', a.state) from app.card_provider_attempts a where a.id = ${lit(rowId)}::uuid), 'null'::jsonb)::text`);
const eventHold = (eventId) => ops.json(`select coalesce((select jsonb_build_object('held', e.incident_hold_at is not null)
  from app.card_provider_private_events e where e.id = ${lit(eventId)}::uuid), 'null'::jsonb)::text`);
// pg_locks: `waiter` holds the tuple lock of a row (the relations named) and waits on a transaction id `holder`
// holds: a row-lock wait on that row.
const rowLockWait = (waiter, holder) => ops.json(`select jsonb_build_object(
  'tuple_lock_relations', (select coalesce(jsonb_agg(distinct n.nspname || '.' || c.relname), '[]'::jsonb)
     from pg_locks l join pg_class c on c.oid = l.relation join pg_namespace n on n.oid = c.relnamespace
    where l.pid = ${waiter.pid} and l.locktype = 'tuple' and l.granted),
  'waits_on_holder_transaction', exists (select 1 from pg_locks w join pg_locks h on h.locktype = 'transactionid'
     and h.transactionid = w.transactionid and h.granted and h.pid = ${holder.pid}
    where w.pid = ${waiter.pid} and w.locktype = 'transactionid' and not w.granted))::text`);
// Race database only: a synthetic Supabase Auth principal linked to the fixture org_owner (staff 9), so the owner's
// dashboard RPCs (revoke_device_management, revoke_membership) run under a real JWT actor.
const OWNER_AUTH = nodeId('auth-9');
async function ensureOwnerJwt(sc) {
  await ops.query(`insert into auth.users (id, email) values (${id('auth-9')}, 'zc001d-auth-9@example.test')
  on conflict (id) do nothing;
update public.app_users u set auth_user_id = ${id('auth-9')} where u.id = ${OWNER} and u.auth_user_id is null;`);
  sc.eq(await ops.one(`select (u.auth_user_id = ${id('auth-9')})::text from public.app_users u where u.id = ${OWNER}`), 'true',
    'race database only: the org_owner (staff 9) signs in with a synthetic JWT principal');
}
// Race database only: cashiers shaped like the fixture's staff (user, membership and employee profile of the pilot
// restaurant and branch, a PIN session on device d's session).
async function addStaff(sc, ns, d) {
  const rows = (f) => ns.map(f).join(',\n  ');
  await ops.query(`begin;
insert into public.app_users (id, email) values
  ${rows((n) => `(${id(`user-${n}`)}, ${lit(`zc001d-staff-${n}@example.test`)})`)};
insert into public.memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role) values
  ${rows((n) => `(${id(`membership-${n}`)}, ${id(`user-${n}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), 'cashier')`)};
insert into public.employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id,
                                      display_name) values
  ${rows((n) => `(${id(`employee-${n}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${id(`user-${n}`)},
    ${id(`membership-${n}`)}, ${lit(`ZC001D Staff ${n}`)})`)};
insert into public.pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
                                 resolved_membership_id, expires_at) values
  ${rows((n) => `(${id(`pin-${n}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${id(`dsession-${d}`)},
    ${id(`employee-${n}`)}, ${id(`membership-${n}`)}, now() + interval '6 hours')`)};
commit;`);
  sc.eq(await count(`select count(*) from public.pin_sessions p where p.id in (${ns.map((n) => id(`pin-${n}`)).join(', ')})`),
    ns.length, `race database only: cashier${ns.length > 1 ? 's' : ''} ${ns.join(' and ')} with a PIN session on d${d}`);
}
const deviceState = (d) => ops.json(`select jsonb_build_object('is_active', dv.is_active,
  'pairings', (select coalesce(string_agg(dp.status, ',' order by dp.id), 'none') from public.device_pairings dp
                where dp.device_id = dv.id),
  'live_sessions', (select count(*) from public.device_sessions ds where ds.device_id = dv.id and ds.is_active
                     and ds.revoked_at is null))::text from public.devices dv where dv.id = ${dev(d)}`);
// Race database only: a third pilot POS till d6 shaped like the fixture's tills (the device, an active pairing, a
// live session for token zc-token-6, cashier 11 with a PIN session on it, an open shift and an active drawer).
async function addTill6(sc) {
  await ops.query(`begin;
insert into public.devices (id, organization_id, restaurant_id, branch_id, device_type)
values (${dev(6)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), 'pos');
insert into public.device_pairings (id, organization_id, restaurant_id, branch_id, device_id, status)
values (${id('pairing-6')}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(6)}, 'active');
insert into public.device_sessions (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id,
                                    session_token_ref, expires_at)
values (${id('dsession-6')}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(6)}, ${id('pairing-6')},
        app.hash_provisioning_secret('zc-token-6'), now() + interval '30 days');
commit;`);
  await addStaff(sc, [11], 6);
  await ops.query(`begin;
insert into public.shifts (id, organization_id, restaurant_id, branch_id, device_id, opened_by_employee_profile_id,
                           resolved_membership_id, local_operation_id, status)
values (${id('shift-6')}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(6)}, ${id('employee-11')}, ${id('membership-11')},
        'zc001d-shift-6', 'open');
insert into public.cash_drawer_sessions (id, organization_id, restaurant_id, branch_id, device_id, shift_id,
                                         opened_by_employee_profile_id, opening_float_minor, local_operation_id)
values (${id('drawer-6')}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${dev(6)}, ${id('shift-6')}, ${id('employee-11')}, 0,
        'zc001d-drawer-6');
commit;`);
  sc.eq(await deviceState(6), { is_active: true, pairings: 'active', live_sessions: 1 },
    'race database only: a third pilot POS till d6 (active pairing, live session, cashier 11, open shift and drawer)');
}
// A LIVE claim of cashier n on device d (the fixture's claim helper with an explicit device).
const claimLiveOn = (n, d, label, orderLabel) =>
  `${F}.zc_claim(${n}, ${lop(label)}, 'live', 1234, ${ord(orderLabel)}, 1, 'alpha16-l32-v1', ${d})`;
// The owner's dashboard revocation of a device (the RF management RPC, JWT actor, idempotency key per label).
const revokeDevice = (d, label) => `public.revoke_device_management(${lit(md5Uuid(`zc001d-revoke-device-${label}`))}::uuid,
  ${dev(d)}, 'ZC001D synthetic till revocation')`;
const revokedEnvelope = (d) => ({ ok: true, idempotent_replay: false, entity: 'device', device_id: nodeId(`device-${d}`),
  pairings_revoked: 1, sessions_revoked: 1 });
const revokeAudits = (d) => count(`select count(*) from public.audit_events e where e.action = 'device.revoked_management'
  and e.new_values ->> 'device_id' = ${dev(d)}::text`);
// The pilot organization admits one enabled / draining binding at a time. C26 runs after C22, which leaves d1's
// LIVE binding configured; run alone, C26 first drains d1's binding and rotates it into a configured row (a
// rotation needs no gate).
async function parkD1Binding(sc) {
  const current = await ops.json(`select coalesce((select jsonb_build_object('refs', jsonb_build_array(t.terminal_ref,
    t.credential_ref), 'lifecycle', t.lifecycle) from app.payment_terminals t where t.organization_id = ${ORG}
    and t.device_id = ${dev(1)} and t.deleted_at is null and t.lifecycle <> 'retired'), 'null'::jsonb)::text`);
  if (current?.lifecycle === 'enabled') {
    const drained = await ops.json(`select ${terminalCall(1, 'live', current.refs, 'draining', 'rotation')}::text`);
    assert.equal(drained.ok, true, `C26 setup: d1 drain: ${JSON.stringify(drained)}`);
  }
  if (current?.lifecycle === 'enabled' || current?.lifecycle === 'draining') {
    const rotated = await ops.json(`select ${terminalCall(1, 'live', ['zc-term-live-1p', 'zc-cred-live-1p'], 'configured',
      'rotation')}::text`);
    assert.equal(rotated.ok, true, `C26 setup: d1 rotation: ${JSON.stringify(rotated)}`);
  }
  sc.eq(await count(`select count(*) from app.payment_terminals t where t.organization_id = ${ORG}
    and t.lifecycle in ('enabled', 'draining')`), 0, 'start: no binding of the pilot organization admits or drains (d1 parked)');
}

// ---------------------------------------------------------------------------------------------------------
// C27 (TEST phase; C1-3 bounded batch; SECURITY:325 "the bounded purge leaves a device outside its batch
//      untouched until the next batch"): d2 sorts before d1, so a one-device batch over an expired d2 attempt and
//      an expired attempt-less d1 denial locks d2 only and defers the d1 event (exact deferred counts). (a) The
//      batch first: a claim on d1 (outside the set) is granted its own terminal lock at once and waits only for
//      the shared barrier, while a claim on d2 (inside the set) waits on the d2 terminal lock; (b) the next batch
//      takes the deferred device (eventual coverage); (c) a claim on d1 first: the batch takes the d2 terminal lock
//      without waiting and waits only for the exclusive barrier. p_max_devices 0 / 1001 hold no lock.
// ---------------------------------------------------------------------------------------------------------
async function c27LockedSetPurge(sc) {
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'start: no purge-eligible TEST row exists');
  sc.eq(await ops.one(`select (${dev(2)} < ${dev(1)})::text`), 'true',
    'device order: d2 sorts before d1, so a one-device batch over both selects d2');
  const k = await keyValues({ t1: terminalKeySql(1), t2: terminalKeySql(2), purge: PURGE_KEY_SQL,
    b4: identityKeySql(1, 'c27-b4') });
  const G = await sc.open('purger');
  const A = await sc.open('claim_d2');
  const B = await sc.open('claim_d1');
  const purges0 = await purgeOperatorEvents();
  for (const size of [0, 1001]) {
    sc.eq(await purgeBatch(G, size, true), { ok: false, error: 'invalid_request' },
      `p_max_devices ${size}: invalid_request (C1-3: checked first)`);
    sc.eq(await advisoryLocks(G), [], `p_max_devices ${size}: the refused batch took no terminal lock and no purge barrier`);
    await G.query('rollback;');
  }
  sc.eq(await purgeOperatorEvents() - purges0, 0, 'the refused batch sizes wrote no operator event');
  await agedDeclinedTest(sc, 'c27-a1');
  const e1 = await agedTestDenial(sc, 1, 'c27-b1');
  sc.eq(await eligibleSet(), { attempts: { d2: 1 }, events: { d1: 1 } },
    'eligible: one expired attempt on d2 and one expired attempt-less TEST denial on d1');

  // (a) The batch first.
  const first = await purgeBatch(G, 1, true);
  sc.eq(batchShape(first), batch(1, 0, 0, 1, 1),
    '(a) G: a one-device batch locks d2 only, purges its expired attempt and reports the d1 event deferred (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), held(k.purge)]),
    '(a) G holds the d2 terminal lock and the exclusive purge barrier, never the d1 terminal lock');
  const bP = B.json(svc(claimTest(1, 'c27-b2')));
  sc.detail.a_claim_outside_the_set_waits_on_the_barrier = await provenWait(B, bP, G, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([held(k.t1), sharedWaiting(k.purge)]),
    '(a) a claim on d1 (outside the batch) is granted its own terminal lock at once and waits only for the shared barrier');
  const aP = A.json(svc(claimTest(8, 'c27-a2')));
  sc.detail.a_claim_inside_the_set_waits_on_its_terminal_lock = await provenWait(A, aP, G, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([waiting(k.t2)]),
    '(a) a claim on d2 (inside the batch) waits on the d2 terminal lock the batch holds');
  await G.query('commit;');
  sc.eq(tsShape(await bP), { ok: false, error: 'card_payments_disabled', server_ts: 'string' },
    '(a) the d1 claim proceeds once the batch committed (card_payments_disabled: d1 has no TEST binding)');
  const a2 = await aP;
  sc.eq(pick(a2, ['ok', 'claim_created', 'replayed', 'state', 'mode']),
    { ok: true, claim_created: true, replayed: false, state: 'sent', mode: 'test' },
    '(a) the d2 claim of a fresh identity is admitted after the batch');
  sc.eq([await identityRows(2, 'c27-a1'), await eventExists(e1)], [[0, 1], 'true'],
    '(a) the d2 attempt is tombstoned; the d1 event outside the batch is untouched');
  sc.eq(await eligibleSet(), { attempts: {}, events: { d1: 1 } }, '(a) exactly the deferred d1 event stays eligible');
  const detail = await lastPurgeDetail();
  sc.eq({ ...detail, cutoff: detail.cutoff === first.cutoff ? 'the result cut-off' : 'another cut-off' },
    { attempts_purged: 1, events_purged: 0, attempts_deferred: 0, events_deferred: 1, devices_locked: 1,
      cutoff: 'the result cut-off' }, '(a) its operator.card_test_attempts_purged detail carries the same counts and cut-off');

  // (b) Eventual coverage: the next batch takes the deferred device.
  sc.eq(batchShape(await purgeBatch(G, 1)), batch(0, 1, 0, 0, 1),
    '(b) the next one-device batch locks d1 and purges the deferred event');
  sc.eq([await eventExists(e1), await eligibleSet()], ['false', { attempts: {}, events: {} }],
    '(b) eventual coverage: nothing eligible remains');

  // (c) The claim on d1 first.
  sc.eq((await ops.json(svc(finish(a2, 'commit', 'declined', DECLINED)))).state, 'declined',
    '(c) setup: the d2 claim of (a) declined');
  sc.eq(await ageRetention(a2.attempt_row_id), ['1'], '(c) setup: race database only: and aged past its retention');
  await agedTestDenial(sc, 1, 'c27-b3');
  sc.eq(await eligibleSet(), { attempts: { d2: 1 }, events: { d1: 1 } }, '(c) eligible again: one d2 attempt, one d1 event');
  sc.eq(tsShape(await B.json(svcTx(claimTest(1, 'c27-b4')))), { ok: false, error: 'card_payments_disabled', server_ts: 'string' },
    '(c) B: a claim on d1 answered, its transaction left open');
  sc.eq(lockSet(await advisoryLocks(B)), lockSet([held(k.t1), sharedHeld(k.purge), held(k.b4)]),
    '(c) B holds the d1 terminal lock, the shared purge barrier and its identity lock');
  const gP = purgeBatch(G, 1);
  sc.detail.c_batch_waits_on_the_barrier = await provenWait(G, gP, B, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), waiting(k.purge)]),
    "(c) G took the d2 terminal lock at once (B holds only d1's) and waits only for the exclusive barrier");
  await B.query('commit;');
  sc.eq(batchShape(await gP), batch(1, 0, 0, 1, 1),
    "(c) G: once B committed, the batch purges d2's attempt and defers the d1 event");
  sc.eq(batchShape(await purgeBatch(G, null)), batch(0, 1, 0, 0, 1), '(c) an unbounded batch then takes the deferred d1 event');
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'end: nothing eligible remains');
  sc.eq(await purgeOperatorEvents() - purges0, 4, 'exactly four purge operator events (one per completed batch)');
}

// ---------------------------------------------------------------------------------------------------------
// C28 (TEST phase; C1-3; SECURITY:325 "keeps held and unexpired evidence"): an incident hold set and cleared
//      against a purge, both orders. (A1) a hold set first: the batch waits on the attempt row and its re-check
//      keeps the held attempt; (A2) the batch first: the hold waits on the deleted row and answers
//      attempt_not_found; (A3) a hold cleared first: the batch does not wait and keeps the attempt (held in its
//      snapshot) for the next batch; (A4) the batch first: the clear does not wait (the batch never locked the
//      held row) and the next batch takes it; (E1) / (E2) the same two orders for an event hold.
// ---------------------------------------------------------------------------------------------------------
async function c28HoldsVsPurge(sc) {
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'start: no purge-eligible TEST row exists');
  const k = await keyValues({ t2: terminalKeySql(2), purge: PURGE_KEY_SQL });
  const G = await sc.open('purger');
  const H = await sc.open('holder');
  const set = (kind, target, reference) => `select ${holdCall(kind, target, true, reference)}::text`;
  const clear = (kind, target) => `select ${holdCall(kind, target, false)}::text`;
  const holdOk = (kind, on) => ({ ok: true, target_kind: kind, hold: on });
  const holdEvents = (rowId) => count(`select count(*) from app.card_provider_private_events e
    where e.action = 'operator.card_test_attempt_hold_updated' and e.attempt_row_id = ${lit(rowId)}::uuid`);

  // (A1) An attempt hold set first.
  const h1 = await agedDeclinedTest(sc, 'c28-h1');
  sc.eq(await H.json(`begin; ${set('attempt', h1.attempt_row_id, 'zc-hold-c28-h1')};`), holdOk('attempt', true),
    '(A1) H: an incident hold set on the expired attempt (uncommitted)');
  const g1 = purgeBatch(G, null);
  sc.detail.a1_batch_waits_on_the_held_attempt = await provenWait(G, g1, H, ['transactionid', 'tuple']);
  sc.eq([lockSet(await advisoryLocks(G)), await rowLockWait(G, H)], [lockSet([held(k.t2), held(k.purge)]),
    { tuple_lock_relations: ['app.card_provider_attempts'], waits_on_holder_transaction: true }],
  '(A1) G holds the d2 terminal lock and the barrier and waits only on the attempt row H holds');
  await H.query('commit;');
  sc.eq(batchShape(await g1), batch(0, 0, 0, 0, 1),
    '(A1) G: its re-check under the row lock sees the committed hold: nothing purged, nothing deferred');
  sc.eq([await attemptHold(h1.attempt_row_id), await identityRows(2, 'c28-h1')], [{ held: true, state: 'declined' }, [1, 0]],
    '(A1) the held attempt survives; no tombstone');

  // (A2) The batch first, then a hold set.
  const h2 = await agedDeclinedTest(sc, 'c28-h2');
  sc.eq(batchShape(await purgeBatch(G, 1, true)), batch(1, 0, 0, 0, 1), '(A2) G: the batch deletes the expired attempt (uncommitted)');
  const h2P = H.json(set('attempt', h2.attempt_row_id, 'zc-hold-c28-h2'));
  sc.detail.a2_hold_waits_on_the_batch = await provenWait(H, h2P, G, ['transactionid', 'tuple']);
  await G.query('commit;');
  sc.eq(await h2P, { ok: false, error: 'attempt_not_found' }, '(A2) H: attempt_not_found once the batch committed');
  sc.eq([await identityRows(2, 'c28-h2'), await holdEvents(h2.attempt_row_id)], [[0, 1], 0], '(A2) tombstoned; no hold event');

  // (A3) A hold cleared first.
  const h3 = await agedDeclinedTest(sc, 'c28-h3');
  sc.eq(await ops.json(set('attempt', h3.attempt_row_id, 'zc-hold-c28-h3')), holdOk('attempt', true),
    '(A3) setup: the expired attempt held (committed)');
  await agedDeclinedTest(sc, 'c28-h3b');
  sc.eq(await eligibleSet(), { attempts: { d2: 1 }, events: {} }, '(A3) eligible: only the other, unheld expired attempt');
  sc.eq(await H.json(`begin; ${clear('attempt', h3.attempt_row_id)};`), holdOk('attempt', false), '(A3) H: the hold cleared (uncommitted)');
  sc.eq(batchShape(await within(purgeBatch(G, null), 10_000, '(A3) the batch waited for the uncommitted clear')),
    batch(1, 0, 0, 0, 1), '(A3) G (taking the d2 terminal lock) does not wait for the clearing transaction: it purges the '
      + 'unheld attempt and keeps the one still held in its snapshot');
  await H.query('commit;');
  sc.eq([await attemptHold(h3.attempt_row_id), await identityRows(2, 'c28-h3b')], [{ held: false, state: 'declined' }, [0, 1]],
    '(A3) the cleared attempt survives this batch; the other is tombstoned');
  sc.eq(batchShape(await purgeBatch(G, 1)), batch(1, 0, 0, 0, 1), '(A3) the next batch purges the attempt whose hold was cleared');
  sc.eq(await identityRows(2, 'c28-h3'), [0, 1], '(A3) its tombstone');

  // (A4) The batch first, then a hold cleared.
  const h4 = await agedDeclinedTest(sc, 'c28-h4');
  sc.eq(await ops.json(set('attempt', h4.attempt_row_id, 'zc-hold-c28-h4')), holdOk('attempt', true),
    '(A4) setup: the expired attempt held (committed)');
  await agedDeclinedTest(sc, 'c28-h4b');
  sc.eq(batchShape(await purgeBatch(G, 1, true)), batch(1, 0, 0, 0, 1),
    '(A4) G: the batch purges the unheld attempt (uncommitted), never locking the held one');
  sc.eq(await within(H.json(clear('attempt', h4.attempt_row_id)), 10_000, '(A4) the clear waited for the batch'),
    holdOk('attempt', false), '(A4) H: the hold cleared (committed) without waiting for the open batch');
  await G.query('commit;');
  sc.eq([await attemptHold(h4.attempt_row_id), await identityRows(2, 'c28-h4b')], [{ held: false, state: 'declined' }, [0, 1]],
    '(A4) the cleared attempt survives that batch; the other is tombstoned');
  sc.eq(batchShape(await purgeBatch(G, null)), batch(1, 0, 0, 0, 1), '(A4) the next batch purges the cleared attempt');

  // (E1) An event hold set first.
  const e1 = await agedTestDenial(sc, 2, 'c28-e1');
  sc.eq(await eligibleSet(), { attempts: {}, events: { d2: 1 } }, '(E1) eligible: the attempt-less d2 event');
  sc.eq(await H.json(`begin; ${set('event', e1, 'zc-hold-c28-e1')};`), holdOk('event', true),
    '(E1) H: an incident hold set on the expired event (uncommitted)');
  const g5 = purgeBatch(G, null);
  sc.detail.e1_batch_waits_on_the_held_event = await provenWait(G, g5, H, ['transactionid', 'tuple']);
  sc.eq([lockSet(await advisoryLocks(G)), await rowLockWait(G, H)], [lockSet([held(k.t2), held(k.purge)]),
    { tuple_lock_relations: ['app.card_provider_private_events'], waits_on_holder_transaction: true }],
  '(E1) G holds the d2 terminal lock and the barrier and waits only on the event row H holds');
  await H.query('commit;');
  sc.eq(batchShape(await g5), batch(0, 0, 0, 0, 1), '(E1) G: its re-check under the row lock keeps the held event');
  sc.eq(await eventHold(e1), { held: true }, '(E1) the held event survives');

  // (E2) The batch first, then an event hold set.
  const e2 = await agedTestDenial(sc, 2, 'c28-e2');
  sc.eq(batchShape(await purgeBatch(G, 1, true)), batch(0, 1, 0, 0, 1), '(E2) G: the batch deletes the expired event (uncommitted)');
  const e2P = H.json(set('event', e2, 'zc-hold-c28-e2'));
  sc.detail.e2_hold_waits_on_the_batch = await provenWait(H, e2P, G, ['transactionid', 'tuple']);
  await G.query('commit;');
  sc.eq(await e2P, { ok: false, error: 'event_not_found' }, '(E2) H: event_not_found once the batch committed');
  sc.eq(await eventHold(e2), null, '(E2) the event is gone');

  // Cleanup: both holds cleared; one batch purges the formerly held attempt and event.
  for (const [kind, target] of [['attempt', h1.attempt_row_id], ['event', e1]]) {
    sc.eq(await ops.json(clear(kind, target)), holdOk(kind, false), `cleanup: the ${kind} hold cleared`);
  }
  sc.eq(batchShape(await purgeBatch(G, null)), batch(1, 1, 0, 0, 1), 'cleanup: one batch purges the formerly held attempt and event');
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'end: nothing eligible remains');
}

// ---------------------------------------------------------------------------------------------------------
// C29 (TEST phase; C1-3; SECURITY:325 "keeps the pre-ledger refusal de-duplicated in both orders"): (1) two
//      pushes of an expired TEST identity first (the second and the batch queue on the d2 terminal lock): one
//      refusal event, kept, the identity tombstoned, none after it; (2) the batch first: the push waits on the
//      terminal lock and is refused from the tombstone with no event.
// ---------------------------------------------------------------------------------------------------------
async function c29RefusalVsPurge(sc) {
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'start: no purge-eligible TEST row exists');
  await makeOrders('c29');
  const k = await keyValues({ t2: terminalKeySql(2), purge: PURGE_KEY_SQL, i1: identityKeySql(2, 'c29-t1') });
  const P1 = await sc.open('first_push');
  const P2 = await sc.open('second_push');
  const G = await sc.open('purger');
  const refusal = (label) => ({ ok: false, error: 'test_attempt_not_recordable', status: 'rejected', idempotency_replay: false,
    local_operation_id: nodeLop(label), operation_type: 'payment.create', order_id: nodeId('order-c29'), server_ts: 'string' });
  const pushOf = (label) => push(8, payOp(label, 'c29'));

  // (1) Two pushes first, the batch queued behind them.
  const t1 = await agedDeclinedTest(sc, 'c29-t1');
  sc.eq(await recordingRefusals(t1.attempt_row_id), 0, '(1) the expired TEST attempt has no refusal event yet');
  sc.eq(tsShape((await P1.json(posTx(pushOf('c29-t1')))).results[0]), refusal('c29-t1'),
    '(1) P1: the pre-ledger TEST refusal, writing the first refusal event (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(P1)), lockSet([held(k.t2), held(k.i1)]), '(1) P1 holds the d2 terminal lock and the identity lock');
  const p2P = P2.json(pos(pushOf('c29-t1')));
  sc.detail.second_push_waits = await provenWait(P2, p2P, P1, ['advisory']);
  const gP = purgeBatch(G, 1);
  sc.detail.batch_waits_behind_the_pushes = await provenWait(G, gP, P1, ['advisory']);
  sc.eq([lockSet(await advisoryLocks(P2)), lockSet(await advisoryLocks(G))], [lockSet([waiting(k.t2)]), lockSet([waiting(k.t2)])],
    '(1) the second push and the batch both queue on the d2 terminal lock');
  await P1.query('commit;');
  sc.eq(tsShape((await p2P).results[0]), refusal('c29-t1'), '(1) P2: the same refusal');
  sc.eq(batchShape(await gP), batch(1, 0, 0, 0, 1),
    '(1) G: the batch then purges the expired attempt (the fresh refusal event is not past its own retention)');
  sc.eq([await recordingRefusals(t1.attempt_row_id), await identityRows(2, 'c29-t1'), await syncRow(2, 'c29-t1')],
    [1, [0, 1], null], '(1) exactly one refusal event for the attempt (kept), the identity tombstoned, no sync row');
  sc.eq(tsShape((await ops.json(pos(pushOf('c29-t1')))).results[0]), refusal('c29-t1'), '(1) a push after the tombstone: the same refusal');
  sc.eq(await recordingRefusals(t1.attempt_row_id), 1, '(1) and no refusal event after the tombstone');

  // (2) The batch first.
  const t2 = await agedDeclinedTest(sc, 'c29-t2');
  sc.eq(batchShape(await purgeBatch(G, 1, true)), batch(1, 0, 0, 0, 1),
    '(2) G: the batch deletes the expired attempt into the tombstone set (uncommitted)');
  sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), held(k.purge)]), '(2) G holds the d2 terminal lock and the exclusive barrier');
  const pP = P1.json(pos(pushOf('c29-t2')));
  sc.detail.push_waits_for_the_batch = await provenWait(P1, pP, G, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(P1)), lockSet([waiting(k.t2)]), '(2) the push waits on the d2 terminal lock');
  await G.query('commit;');
  sc.eq(tsShape((await pP).results[0]), refusal('c29-t2'), '(2) P1: refused from the committed tombstone');
  sc.eq([await recordingRefusals(t2.attempt_row_id), await syncRow(2, 'c29-t2'), await identityRows(2, 'c29-t2')], [0, null, [0, 1]],
    '(2) no refusal event (none after the tombstone), no sync row, one tombstone');
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'end: nothing eligible remains');
}

// ---------------------------------------------------------------------------------------------------------
// C30 (TEST phase; C1-3; SECURITY:325 "rolls back as a whole on failure"): a forced failure inside the batch, in
//      the race database only — a BEFORE DELETE trigger on the private events that, when the batch's session
//      sets zc001d.c30_fault, waits for a gate key held by X and then raises P0001. The batch blocks inside its
//      event delete holding the d2 terminal lock and the barrier; a claim of the identity waits on it; at the
//      raise (caught: the batch's subtransaction rolls back) every lock the batch took is released and nothing
//      of it persists — no tombstone, the attempt and its event kept, no operator event — until a clean batch.
// ---------------------------------------------------------------------------------------------------------
async function c30PurgeFailureRollsBack(sc) {
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'start: no purge-eligible TEST row exists');
  await makeOrders('c30');
  const FAULT_KEY = `hashtextextended('zc001d-c30-fault', 0)`;
  const k = await keyValues({ t2: terminalKeySql(2), purge: PURGE_KEY_SQL, fault: `${FAULT_KEY}::text` });
  const t3 = await agedDeclinedTest(sc, 'c30-t3', { age: false });
  sc.eq(pick((await ops.json(pos(push(8, payOp('c30-t3', 'c30'))))).results[0], ['ok', 'error']),
    { ok: false, error: 'test_attempt_not_recordable' }, 'setup: a push of the TEST identity writes its one refusal event');
  const [refusalEvent] = await refusalEventIds(t3.attempt_row_id);
  sc.eq([await ageRetention(t3.attempt_row_id), await ageEvent(refusalEvent)], [['1'], ['1']],
    'setup: race database only: the attempt and its refusal event aged past their retention');
  sc.eq(await eligibleSet(), { attempts: { d2: 1 }, events: { d2: 1 } }, 'eligible: the d2 attempt and its refusal event');
  const purges0 = await purgeOperatorEvents();
  await ops.query(`create function ${F}.zc_c30_fault() returns trigger language plpgsql as $zc$
begin
  if current_setting('zc001d.c30_fault', true) = 'on' then
    perform pg_advisory_xact_lock(${FAULT_KEY});
    raise exception 'zc001d forced purge failure' using errcode = 'P0001';
  end if;
  return old;
end $zc$;
create trigger zc_c30_fault before delete on app.card_provider_private_events
  for each row execute function ${F}.zc_c30_fault();`);
  let X = null;
  let G = null;
  let W = null;
  try {
    X = await sc.open('fault_gate');
    G = await sc.open('purger');
    W = await sc.open('claim');
    await X.query(`begin; select pg_advisory_xact_lock(${FAULT_KEY});`);
    sc.eq(lockSet(await advisoryLocks(X)), lockSet([held(k.fault)]), 'race database only: X holds the fault-gate key');
    await G.query(`begin; select set_config('zc001d.c30_fault', 'on', true);`);
    const gP = G.one(purgeText(null));
    sc.detail.batch_blocks_inside_its_event_delete = await provenWait(G, gP, X, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(G)), lockSet([held(k.t2), held(k.purge), waiting(k.fault)]),
      "G: the batch is blocked inside its event delete (the forced-fault trigger), holding the d2 terminal lock and the barrier");
    const wP = W.json(svc(claimTest(8, 'c30-t3')));
    sc.detail.claim_waits_on_the_batch = await provenWait(W, wP, G, ['advisory']);
    sc.eq(lockSet(await advisoryLocks(W)), lockSet([waiting(k.t2)]), 'W (a claim of the identity) waits on the d2 terminal lock');
    await X.query('commit;');
    sc.eq(await gP, 'SQLSTATE:P0001', 'G: the forced failure raises inside the batch (caught; the batch subtransaction rolled back)');
    sc.eq(pick(await wP, ['ok', 'claim_created', 'replayed', 'state', 'mode', 'attempt_row_id']),
      { ok: true, claim_created: false, replayed: true, state: 'declined', mode: 'test', attempt_row_id: t3.attempt_row_id },
      'W: proceeds at the failure and replays the attempt row');
    sc.eq(await advisoryLocks(G), [],
      "G: the failed batch released its terminal lock and barrier with its rolled-back work (G's transaction still open)");
    await G.query('commit;');
    sc.eq([await identityRows(2, 'c30-t3'), await eventExists(refusalEvent), await purgeOperatorEvents() - purges0],
      [[1, 0], 'true', 0], 'after G committed: the attempt kept, no tombstone, its event kept, no purge operator event '
        + '(the whole batch rolled back)');
    sc.eq(await eligibleSet(), { attempts: { d2: 1 }, events: { d2: 1 } }, 'both rows stay eligible');
  } finally {
    for (const s of [X, G, W]) if (s) await s.close();
    await ops.query(`drop trigger if exists zc_c30_fault on app.card_provider_private_events;
drop function if exists ${F}.zc_c30_fault();`);
  }
  sc.eq(await count(`select count(*) from pg_trigger t where t.tgname = 'zc_c30_fault'`), 0,
    'cleanup (race database only): the forced-fault trigger dropped');
  sc.eq(batchShape(await purgeBatch(ops, null)), batch(1, 1, 0, 0, 1), 'a clean batch then purges the attempt and its event');
  sc.eq([await identityRows(2, 'c30-t3'), await eventExists(refusalEvent)], [[0, 1], 'false'],
    'the attempt tombstoned and its event deleted');
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'end: nothing eligible remains');
}

// ---------------------------------------------------------------------------------------------------------
// C33 (TEST phase; C1-3 "the cut-off is fixed before selection and locking"; the C1 delta review): while a session
//      holds the d2 terminal lock, a batch over an expired d2 attempt waits on it; a second d2 attempt and an
//      attempt-less d2 TEST denial event whose retentions end after the batch's cut-off but before the lock is
//      released are neither purged nor reported deferred by that batch (not eligible at its cut-off: the attempt
//      and the event legs), and the next batch purges both.
// ---------------------------------------------------------------------------------------------------------
// Race database only: one TEST attempt's retention set to end `interval` from now (its guard bypassed for that one
// UPDATE, while no other session holds the table).
const retainFromNow = (rowId, interval) => ops.query(`begin;
alter table app.card_provider_attempts disable trigger card_attempts_guard;
with u as (update app.card_provider_attempts a set retention_until = clock_timestamp() + interval ${lit(interval)}
            where a.id = ${lit(rowId)}::uuid and a.mode = 'test' returning 1) select count(*) from u;
alter table app.card_provider_attempts enable trigger card_attempts_guard;
commit;`);
// Race database only: one TEST event's retention set to end `interval` from now (its immutability trigger bypassed for
// that one UPDATE, while no other session holds the table).
const retainEventFromNow = (eventId, interval) => ops.query(`begin;
alter table app.card_provider_private_events disable trigger card_events_guard;
with u as (update app.card_provider_private_events e set retention_until = clock_timestamp() + interval ${lit(interval)}
            where e.id = ${lit(eventId)}::uuid and e.mode = 'test' returning 1) select count(*) from u;
alter table app.card_provider_private_events enable trigger card_events_guard;
commit;`);
// Polls the database clock until the attempt's retention has passed (at most 15 s).
async function untilExpired(rowId) {
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    const passed = await ops.one(`select (a.retention_until < clock_timestamp())::text from app.card_provider_attempts a
      where a.id = ${lit(rowId)}::uuid`);
    if (passed === 'true') return;
    await sleep(100);
  }
  assert.fail(`attempt ${rowId} never expired`);
}
async function c33CutoffBeforeLocks(sc) {
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'start: no purge-eligible TEST row exists');
  const k = await keyValues({ t2: terminalKeySql(2), purge: PURGE_KEY_SQL });
  const G = await sc.open('purger');
  const H = await sc.open('holder');
  const purges0 = await purgeOperatorEvents();
  await agedDeclinedTest(sc, 'c33-a1');
  const a2 = await agedDeclinedTest(sc, 'c33-a2', { age: false });
  // An attempt-less TEST denial on d2 (a claim over the pilot's TEST cap), its retention ending first.
  const denialsBefore = await eventIds('test.card_attempt_denied', 2);
  sc.eq(tsShape(await ops.json(svc(claimTest(8, 'c33-e1', 100001)))),
    { ok: false, error: 'precondition_failed', detail: 'max_test_amount_exceeded', server_ts: 'string' },
    'a TEST claim over the cap on d2 is refused with denial evidence');
  const e1 = (await eventIds('test.card_attempt_denied', 2)).filter((x) => !denialsBefore.includes(x));
  sc.eq(e1.length, 1, 'exactly one attempt-less test.card_attempt_denied event on d2');
  sc.eq(await retainEventFromNow(e1[0], '3 seconds'), ['1'],
    'race database only: the d2 denial event retention set to end 3 s from now');
  sc.eq(await retainFromNow(a2.attempt_row_id, '3 seconds'), ['1'],
    'race database only: c33-a2 retention set to end 3 s from now (after the event)');
  sc.eq(await eligibleSet(), { attempts: { d2: 1 }, events: {} }, 'eligible now: exactly the expired d2 attempt c33-a1');
  await H.query(`begin; select app.card_terminal_lock(${ORG}, ${dev(2)});`);
  sc.eq(lockSet(await advisoryLocks(H)), lockSet([held(k.t2)]), 'H holds the d2 terminal lock');
  const gP = purgeBatch(G, null);
  sc.detail.batch_waits_on_the_terminal_lock = await provenWait(G, gP, H, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(G)), lockSet([waiting(k.t2)]),
    'the batch (its cut-off already fixed) waits on the d2 terminal lock and holds no purge barrier yet');
  await untilExpired(a2.attempt_row_id);
  sc.eq(await eligibleSet(), { attempts: { d2: 2 }, events: { d2: 1 } },
    'while the batch waits, c33-a2 and the d2 denial event expire too (by the database clock)');
  await H.query('commit;');
  const r = await gP;
  sc.eq(batchShape(r), batch(1, 0, 0, 0, 1),
    'the batch purges c33-a1 only and reports nothing deferred: c33-a2 and the event expired after its cut-off');
  sc.eq(await ops.json(`select jsonb_build_array(
      (select (${lit(r.cutoff)}::timestamptz < a.retention_until) from app.card_provider_attempts a
        where a.id = ${lit(a2.attempt_row_id)}::uuid),
      (select (${lit(r.cutoff)}::timestamptz < e.retention_until) from app.card_provider_private_events e
        where e.id = ${lit(e1[0])}::uuid))::text`), [true, true],
    "c33-a2's and the event's retentions end after the batch's cut-off");
  sc.eq([await identityRows(2, 'c33-a1'), await identityRows(2, 'c33-a2'), await eventExists(e1[0])],
    [[0, 1], [1, 0], 'true'], 'c33-a1 is tombstoned; c33-a2 and the event survive the batch');
  sc.eq(batchShape(await purgeBatch(G, null)), batch(1, 1, 0, 0, 1),
    'the next batch purges c33-a2 and the event (eventual coverage)');
  sc.eq(await eventExists(e1[0]), 'false', 'the event is gone after the next batch');
  sc.eq(await eligibleSet(), { attempts: {}, events: {} }, 'end: nothing eligible remains');
  sc.eq(await purgeOperatorEvents() - purges0, 2, 'exactly two purge operator events (one per batch)');
}

// ---------------------------------------------------------------------------------------------------------
// C31 (C1-5; SECURITY:325 "an ACTIVE support session is refused at the caller proof with valid staff inputs, an
//      expired, ended or un-exchanged one is not active, and a grant alone confers nothing"): a platform admin's
//      JWT (active grant, no support session) passes app.card_attempt_context with valid staff inputs; another
//      session of the same operator exchanges a support handoff — uncommitted, the next call still passes without
//      waiting; once committed, the next call is refused permission_denied before any proof, renewal or read
//      (nothing written); after the operator ends the support session the normal proof decides again.
// ---------------------------------------------------------------------------------------------------------
const SESSION_1 = id('dsession-1');
// Race database only: d1's device session made due for renewal, so a proven context call visibly renews it.
const shortenSession1 = () => ops.one(`update public.device_sessions ds set expires_at = now() + interval '1 day'
  where ds.id = ${SESSION_1} returning (ds.expires_at < now() + interval '2 days')::text`);
const session1Renewed = () => ops.one(`select (ds.expires_at > now() + interval '29 days')::text
  from public.device_sessions ds where ds.id = ${SESSION_1}`);
// d1's session deadline and device activity stamp (kept in memory, compared in SQL, never printed).
const session1Facts = () => ops.json(`select jsonb_build_object('expires_at', ds.expires_at::text,
  'last_seen_at', d.last_seen_at::text)::text from public.device_sessions ds join public.devices d on d.id = ds.device_id
  where ds.id = ${SESSION_1}`);
const session1Unchanged = (f) => ops.one(`select (ds.expires_at = ${lit(f.expires_at)}::timestamptz
  and d.last_seen_at is not distinct from ${f.last_seen_at === null ? 'null' : lit(f.last_seen_at)}::timestamptz)::text
  from public.device_sessions ds join public.devices d on d.id = ds.device_id where ds.id = ${SESSION_1}`);
const writeCounts = () => ops.json(`select jsonb_build_array((select count(*) from app.card_provider_private_events),
  (select count(*) from public.audit_events), (select count(*) from public.platform_admin_audit_events))::text`);

async function c31SupportActivation(sc) {
  const ADMIN_AUTH = nodeId('auth-c31');
  const HANDOFF = 'zc001d-c31-handoff';
  await ops.query(`begin;
insert into auth.users (id, email) values (${id('auth-c31')}, 'zc001d-support-c31@example.test');
insert into public.app_users (id, email, auth_user_id)
values (${id('user-c31')}, 'zc001d-support-c31@example.test', ${id('auth-c31')});
insert into public.platform_admin_grants (app_user_id, status, granted_by) values (${id('user-c31')}, 'active', ${OWNER});
commit;`);
  const principal = () => ops.json(`select jsonb_build_object(
    'linked', exists (select 1 from public.app_users u where u.id = ${id('user-c31')} and u.auth_user_id = ${id('auth-c31')}),
    'grant', exists (select 1 from public.platform_admin_grants g where g.app_user_id = ${id('user-c31')} and g.status = 'active'),
    'support', (select coalesce(string_agg(s.status || '/' || (s.token_consumed_at is not null)::text, ','
      order by s.created_at), 'none') from public.platform_support_sessions s
      where s.platform_admin_app_user_id = ${id('user-c31')}))::text`);
  const contextFor = (n) => pos(`public.card_attempt_context(${id(`pin-${n}`)}, ${dev(1)}, 'zc-token-1', null, null)`);
  const P = await sc.open('pos_tab', `set request.jwt.claim.sub = ${lit(ADMIN_AUTH)};`);
  const S = await sc.open('dashboard_tab', `set request.jwt.claim.sub = ${lit(ADMIN_AUTH)};`);
  sc.eq(await principal(), { linked: true, grant: true, support: 'none' },
    'start: P and S carry the JWT of a platform admin (active grant) without any support session');

  // (1) The first context call: the normal proof decides.
  sc.eq(await shortenSession1(), 'true', "(1) race database only: d1's device session is due for renewal");
  sc.eq(pick(await P.json(contextFor(1)), ['ok', 'role', 'device_id', 'employee_profile_id']),
    { ok: true, role: 'cashier', device_id: nodeId('device-1'), employee_profile_id: nodeId('employee-1') },
    '(1) P: the first context call with the cashier PIN and the d1 token passes (a grant alone confers and bans nothing)');
  sc.eq(await session1Renewed(), 'true', "(1) the proven call renewed d1's device session");

  // (2) A started handoff is not active; its exchange by another session, uncommitted, is not visible either.
  await ops.query(`insert into public.platform_support_sessions (id, platform_admin_app_user_id, target_organization_id,
    reason, status, expires_at, token_hash)
  values (${id('support-c31')}, ${id('user-c31')}, ${ORG}, 'ZC001D synthetic support visit', 'pending',
    now() + interval '15 minutes', encode(extensions.digest(${lit(HANDOFF)}, 'sha256'), 'hex'));`);
  sc.eq((await principal()).support, 'pending/false', '(2) a started support session waits for its exchange (pending)');
  sc.eq(pick(await P.json(contextFor(1)), ['ok', 'role']), { ok: true, role: 'cashier' },
    '(2) P: an un-exchanged support session is not active: the context call still passes');
  sc.eq(pick(await S.json(posTx(`public.platform_support_exchange(${lit(HANDOFF)})`)), ['ok', 'read_only', 'support_session_id']),
    { ok: true, read_only: true, support_session_id: nodeId('support-c31') },
    '(2) S (the same operator in another session): the handoff exchanged (uncommitted)');
  sc.eq(pick(await within(P.json(contextFor(2)), 10_000, '(2) the context call waited for the uncommitted exchange'),
    ['ok', 'role']), { ok: true, role: 'manager' },
  '(2) P with the manager PIN while the exchange is uncommitted: ok, without waiting (no lock; the committed state decides)');
  await S.query('commit;');
  sc.eq((await principal()).support, 'active/true', '(2) the support session is ACTIVE once S committed (token consumed)');

  // (3) The next context call after the activation: refused before any proof, renewal or read.
  sc.eq(await shortenSession1(), 'true', "(3) race database only: d1's device session is due for renewal again");
  const facts = await session1Facts();
  const writes0 = await writeCounts();
  for (const [n, who] of [[1, 'cashier'], [2, 'manager']]) {
    sc.eq(await P.json(contextFor(n)), { ok: false, error: 'permission_denied' },
      `(3) P's next context call with the ${who} PIN and the d1 token: exactly {ok:false, error:permission_denied} (C1-5)`);
  }
  sc.eq(await session1Unchanged(facts), 'true', "(3) d1's device session was not renewed and the device was not stamped");
  sc.eq(await writeCounts(), writes0, '(3) no private event, no tenant audit row, no platform audit row');
  sc.eq(pick(await ops.json(contextFor(1)), ['ok', 'role']), { ok: true, role: 'cashier' },
    '(3) the same staff inputs under the native transport JWT (no support session) still pass');

  // (4) The operator ends the support session: the normal proof decides again.
  sc.eq(pick(await S.json(pos('public.platform_support_end()')), ['ok', 'ended', 'support_session_id']),
    { ok: true, ended: true, support_session_id: nodeId('support-c31') }, '(4) S ends the support session');
  sc.eq(pick(await P.json(contextFor(1)), ['ok', 'role']), { ok: true, role: 'cashier' },
    '(4) an ended support session is not active: P passes again');
}

// ---------------------------------------------------------------------------------------------------------
// C32 (C1-5 / §4.55.2 write-time re-proof; SECURITY:325): a membership revoked between the context proof and the
//      service-only write, both orders, through the owner's revoke_membership. (a) The revocation first: the
//      claim waits inside its write-time proof on the membership row it reads FOR SHARE and answers
//      invalid_session with nothing written. (b) The claim first: the revocation waits on that row until the
//      claim commits; the claim stands, the next service-only write (a release mark) and a new context proof
//      answer invalid_session, and the scope-bound provider finish still records the provider fact.
// ---------------------------------------------------------------------------------------------------------
async function c32MembershipRevokedAfterProof(sc) {
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'enabled'), 'start: the original LIVE binding of d1 is enabled');
  await ensureOwnerJwt(sc);
  await addStaff(sc, [12, 13], 1);
  await makeOrders('c32a', 'c32b');
  const k = await keyValues({ t1: terminalKeySql(1), purge: PURGE_KEY_SQL });
  const P = await sc.open('context');
  const A = await sc.open('writer');
  const R = await sc.open('owner', `set request.jwt.claim.sub = ${lit(OWNER_AUTH)};`);
  const context = (n) => pos(`public.card_attempt_context(${id(`pin-${n}`)}, ${dev(1)}, 'zc-token-1', null, null)`);
  const revokeMembership = (n) => `public.revoke_membership(${lit(md5Uuid(`zc001d-c32-revoke-membership-${n}`))}::uuid,
    ${id(`membership-${n}`)}, 'ZC001D synthetic membership revocation')`;
  const revoked = (n) => ({ ok: true, idempotent_replay: false, entity: 'membership', membership_id: nodeId(`membership-${n}`),
    status: 'revoked' });
  const authority = (n) => ops.json(`select jsonb_build_object('membership', m.status, 'deleted', m.deleted_at is not null,
    'employment', e.employment_status)::text from public.memberships m join public.employee_profiles e on e.membership_id = m.id
    where m.id = ${id(`membership-${n}`)}`);
  // [attempt rows, card_attempt.* audits, private events] of cashier n.
  const writes = (n) => ops.json(`select jsonb_build_array(
    (select count(*) from app.card_provider_attempts a where a.initiated_by_employee_profile_id = ${id(`employee-${n}`)}),
    (select count(*) from public.audit_events e where e.action like 'card_attempt.%'
        and e.actor_employee_profile_id = ${id(`employee-${n}`)}),
    (select count(*) from app.card_provider_private_events e
      where e.actor_employee_profile_id = ${id(`employee-${n}`)}))::text`);

  // (a) The revocation first.
  sc.eq(pick(await P.json(context(12)), ['ok', 'role', 'membership_id']),
    { ok: true, role: 'cashier', membership_id: nodeId('membership-12') }, '(a) P: the context proof of cashier 12 on d1 passes');
  sc.eq(await R.json(posTx(revokeMembership(12))), revoked(12),
    "(a) R (the owner's dashboard): revoke_membership of cashier 12 (uncommitted)");
  const aP = A.json(svc(claimLive(12, 'c32-a', 'c32a')));
  sc.detail.a_write_waits_for_the_revocation = await provenWait(A, aP, R, ['transactionid', 'tuple']);
  sc.eq(await rowLockWait(A, R), { tuple_lock_relations: ['public.memberships'], waits_on_holder_transaction: true },
    '(a) A (the service-only claim) waits inside its write-time proof on the membership row it reads FOR SHARE');
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t1), sharedHeld(k.purge)]),
    '(a) A holds the d1 terminal lock and the shared purge barrier (its identity lock follows the proof)');
  await R.query('commit;');
  sc.eq(tsShape(await aP), { ok: false, error: 'invalid_session', server_ts: 'string' },
    '(a) A: the service-only write answers invalid_session once the revocation committed');
  sc.eq([await writes(12), await attempt(1, 'c32-a')], [[0, 0, 0], null],
    '(a) nothing written: no attempt row, no card_attempt.* audit, no private event');
  sc.eq(await authority(12), { membership: 'revoked', deleted: true, employment: 'terminated' },
    '(a) the membership revoked and its employee profile terminated');

  // (b) The write first.
  sc.eq(pick(await P.json(context(13)), ['ok', 'role', 'membership_id']),
    { ok: true, role: 'cashier', membership_id: nodeId('membership-13') }, '(b) P: the context proof of cashier 13 on d1 passes');
  const written = await A.json(svcTx(claimLive(13, 'c32-b', 'c32b')));
  sc.eq(pick(written, ['ok', 'claim_created', 'state', 'mode']), { ok: true, claim_created: true, state: 'sent', mode: 'live' },
    '(b) A: the claim of cashier 13 (uncommitted; its write-time proof holds the membership row FOR SHARE)');
  const rP = R.json(pos(revokeMembership(13)));
  sc.detail.b_revocation_waits_for_the_write = await provenWait(R, rP, A, ['transactionid', 'tuple']);
  sc.eq(await rowLockWait(R, A), { tuple_lock_relations: ['public.memberships'], waits_on_holder_transaction: true },
    '(b) R waits on the membership row the claim read FOR SHARE');
  sc.eq(await advisoryLocks(R), [], '(b) R takes no advisory lock');
  await A.query('commit;');
  sc.eq(await rP, revoked(13), '(b) R: the revocation applies once the claim committed');
  sc.eq(pick(await attempt(1, 'c32-b'), ['state', 'mode', 'initiated_by_membership_id', 'release_requested_at']),
    { state: 'sent', mode: 'live', initiated_by_membership_id: nodeId('membership-13'), release_requested_at: null },
    '(b) the claim committed under the then-valid authority stands');
  sc.eq(tsShape(await A.json(svc(`public.card_attempt_mark_release_requested(${id('pin-13')}, ${dev(1)}, 'zc-token-1',
    ${lop('c32-b')}, ${F}.zc_caller())`))), { ok: false, error: 'invalid_session', server_ts: 'string' },
  "(b) cashier 13's next service-only write (a release mark) answers invalid_session");
  sc.eq([pick(await attempt(1, 'c32-b'), ['release_requested_at']), await writes(13)], [{ release_requested_at: null }, [1, 1, 0]],
    '(b) the mark wrote nothing: the one attempt and its card_attempt.started audit only, no private event');
  sc.eq(await P.json(context(13)), { ok: false, error: 'invalid_session' }, '(b) a new context proof of cashier 13: invalid_session');
  sc.eq(pick(await ops.json(svc(finish(written, 'commit', 'declined', DECLINED))), ['ok', 'state', 'classification']),
    { ok: true, state: 'declined', classification: 'declined' },
    '(b) the scope-bound provider finish (no PIN proof) still records the provider fact');
}

// ---------------------------------------------------------------------------------------------------------
// C26 (C1-2; SECURITY:325 "an inactive or management-revoked till's binding drains, retires only when every
//      attempt is resolved and no payment.create is pending, and is never created, enabled or rotated, with a
//      replacement blocked until then"): on a third pilot till d6 (race database only) with an enabled LIVE
//      binding, (1) a claim first, then the owner's revoke_device_management, which waits on the d6 device row the
//      claim's proof holds; (2) only draining / retirement reach the inactive till's binding and the replacement
//      till d2 cannot be enabled; (3) a drain and a retirement serialize on the d6 terminal lock, the retirement
//      refused while the claim is unresolved; (4) the provider approval makes it orphan_approved / device_revoked;
//      (5) the operator resolves it; (6) two retirements serialize, exactly one retires; (7) the replacement is
//      enabled; (8) revoke_device_management first, then a claim on d2, which waits inside its proof and answers
//      invalid_session; (9) the genuinely clear d2 binding drains and retires at once. Runs last (after C22).
// ---------------------------------------------------------------------------------------------------------
async function c26InactiveDeviceShutdown(sc) {
  const D6 = ['zc-term-live-6', 'zc-cred-live-6'];
  const D2 = ['zc-term-live-2', 'zc-cred-live-2'];
  sc.eq(await ops.json(`select jsonb_build_object('enabled', c.enabled, 'mode', c.mode, 'open', c.window_until > now())::text
    from app.card_pilot_revision_current() c`), { enabled: true, mode: 'live', open: true },
  'start: the current pilot revision admits LIVE starts');
  await parkD1Binding(sc);
  sc.eq(await currentBinding(2), 'none', 'start: d2 has no current binding');
  sc.eq(await ops.one(`select coalesce(bool_or((app.card_attempt_derive(a) ->> 'unresolved')::boolean), false)::text
    from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(2)}`), 'false',
  'start: d2 holds no unresolved attempt');
  await ensureOwnerJwt(sc);
  await addTill6(sc);
  await makeOrders('c26a', 'c26a2', 'c26b');
  const k = await keyValues({ t6: terminalKeySql(6), t2: terminalKeySql(2), purge: PURGE_KEY_SQL,
    a: identityKeySql(6, 'c26-a') });
  const set6 = (refs, lifecycle, reason) => `select ${terminalCall(6, 'live', refs, lifecycle, reason)}::text`;
  const set2 = (lifecycle, reason) => `select ${terminalCall(2, 'live', D2, lifecycle, reason)}::text`;
  const admittingRefused = { ok: false, error: 'precondition_failed', detail: 'admitting_binding_exists' };
  const unresolvedRefused = { ok: false, error: 'precondition_failed', detail: 'attempt_unresolved' };
  sc.eq(await ops.json(set6(D6, 'configured', 'live_activation')), changed('live', null, 'configured'), 'd6: a LIVE binding configured');
  sc.eq(await ops.json(set6(D6, 'enabled', 'live_activation')), changed('live', 'configured', 'enabled'),
    'd6: enabled (no other admitting binding, no unresolved attempt, no payment.create backlog)');
  const A = await sc.open('claim');
  const R = await sc.open('owner', `set request.jwt.claim.sub = ${lit(OWNER_AUTH)};`);
  const B1 = await sc.open('operator_1');
  const B2 = await sc.open('operator_2');
  const events6 = await operatorEvents(6);
  const events2 = await operatorEvents(2);

  // (1) The claim first, then revoke_device_management.
  const claimed = await A.json(svcTx(claimLiveOn(11, 6, 'c26-a', 'c26a')));
  sc.eq(pick(claimed, ['ok', 'claim_created', 'replayed', 'state', 'mode', 'device_id']),
    { ok: true, claim_created: true, replayed: false, state: 'sent', mode: 'live', device_id: nodeId('device-6') },
    '(1) A: a fresh LIVE claim on d6 (uncommitted; its write-time proof holds the d6 device row FOR NO KEY UPDATE)');
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t6), sharedHeld(k.purge), held(k.a)]),
    '(1) A holds the d6 terminal lock, the shared purge barrier and the identity lock');
  const revokeA = R.json(pos(revokeDevice(6, 'a')));
  sc.detail.revocation_waits_for_the_claim = await provenWait(R, revokeA, A, ['transactionid', 'tuple']);
  sc.eq(await rowLockWait(R, A), { tuple_lock_relations: ['public.devices'], waits_on_holder_transaction: true },
    "(1) R (the owner's revoke_device_management) waits on the d6 device row the claim holds");
  sc.eq(await advisoryLocks(R), [], '(1) R takes no advisory lock');
  await A.query('commit;');
  sc.eq(await revokeA, revokedEnvelope(6), '(1) R: the revocation completes once the claim committed (one pairing, one session)');
  sc.eq([await deviceState(6), await revokeAudits(6)], [{ is_active: false, pairings: 'revoked', live_sessions: 0 }, 1],
    '(1) d6 inactive, its pairing revoked, no live session; one device.revoked_management audit');
  sc.eq(pick(await attempt(6, 'c26-a'), ['state', 'mode', 'resolution', 'order_freed_at']),
    { state: 'sent', mode: 'live', resolution: null, order_freed_at: null },
    '(1) the committed claim stands: the revocation resolves and frees nothing');
  sc.eq(pick(await derived(6, 'c26-a'), ['classification', 'unresolved', 'claim_active']),
    { classification: 'in_progress', unresolved: true, claim_active: true }, '(1) it is in progress and unresolved');
  sc.eq(tsShape(await A.json(svc(claimLiveOn(11, 6, 'c26-a2', 'c26a2')))), { ok: false, error: 'invalid_session', server_ts: 'string' },
    '(1) a later claim on the revoked d6: invalid_session');
  sc.eq(await attempt(6, 'c26-a2'), null, '(1) no row for it');

  // (2) Only draining / retirement reach the inactive till's binding; the replacement cannot be enabled.
  sc.eq(await ops.json(set6(['zc-term-live-6r', 'zc-cred-live-6r'], 'configured', 'rotation')), { ok: false, error: 'invalid_request' },
    '(2) a new / rotated binding on the inactive d6: invalid_request (C1-2)');
  sc.eq(await ops.json(set6(D6, 'enabled', 'live_activation')), { ok: false, error: 'invalid_request' },
    '(2) enabling on the inactive d6: invalid_request (C1-2)');
  sc.eq([await currentBinding(6), await operatorEvents(6) - events6], [terminalLabel(D6, 'live', 'enabled'), 0],
    "(2) nothing written: d6's binding still enabled, no operator event");
  sc.eq(await ops.json(set2('configured', 'live_activation')), changed('live', null, 'configured'),
    '(2) the replacement till d2: a LIVE binding configured (a configured row admits nothing)');
  sc.eq(await ops.json(set2('enabled', 'live_activation')), admittingRefused,
    "(2) the replacement cannot be enabled while the revoked till's binding is enabled");

  // (3) A drain and a retirement of the revoked till's binding serialize on its terminal lock.
  sc.eq(await B1.json(`begin; ${set6(D6, 'draining', 'incident')};`), changed('live', 'enabled', 'draining'),
    "(3) B1: the drain of the inactive d6's binding proceeds (C1-2; uncommitted)");
  sc.eq(lockSet(await advisoryLocks(B1)), lockSet([held(k.t6)]), '(3) B1 holds exactly the d6 terminal lock');
  const retireP = B2.json(set6(D6, 'retired', 'end_of_pilot'));
  sc.detail.retirement_waits_for_the_drain = await provenWait(B2, retireP, B1, ['advisory']);
  sc.eq(lockSet(await advisoryLocks(B2)), lockSet([waiting(k.t6)]), '(3) B2 (the retirement) waits on the d6 terminal lock');
  await B1.query('commit;');
  sc.eq(await retireP, unresolvedRefused, '(3) B2: serialized after the drain, the retirement is refused while the claim is unresolved');
  sc.eq([await currentBinding(6), await operatorEvents(6) - events6], [terminalLabel(D6, 'live', 'draining'), 1],
    "(3) d6's binding draining; exactly one operator event (the drain)");
  sc.eq(await ops.json(`select jsonb_build_object('executor', e.executor_principal = session_user,
    'approver', e.actor_app_user_id = ${OWNER}, 'actor_kind', e.actor_kind, 'detail', e.detail)::text
    from app.card_provider_private_events e where e.action = 'operator.payment_terminal_updated' and e.device_id = ${dev(6)}
    order by e.created_at desc, e.id desc limit 1`), { executor: true, approver: true, actor_kind: 'attested_owner_approver',
    detail: { binding_mode: 'live', prior_lifecycle: 'enabled', new_lifecycle: 'draining', starts_admitted: false,
      reason_code: 'incident' } }, '(3) the drain event: executor session_user, the attested approver, the closed detail');
  sc.eq(await ops.json(set2('enabled', 'live_activation')), admittingRefused,
    "(3) the replacement still cannot be enabled while the revoked till's binding drains");

  // (4) The provider approval still reaches the attempt (scope-bound finish): an orphan, still unresolved.
  sc.eq(pick(await ops.json(svc(finish(claimed, 'commit', 'approved', APPROVED))), ['ok', 'state', 'classification', 'recorded']),
    { ok: true, state: 'approved', classification: 'orphan_approved', recorded: false },
    "(4) the provider's approval is recorded on the revoked till's attempt: orphan_approved");
  sc.eq(pick(await derived(6, 'c26-a'), ['classification', 'reason', 'recoverable', 'unresolved']),
    { classification: 'orphan_approved', reason: 'device_revoked', recoverable: false, unresolved: true },
    '(4) orphan_approved / device_revoked, not recoverable, unresolved');
  sc.eq(await ops.json(set6(D6, 'retired', 'end_of_pilot')), unresolvedRefused, '(4) the retirement is still refused');

  // (5) The operator resolution.
  sc.eq(pick(await ops.json(`select app.card_attempt_resolve_orphan(${lit(claimed.attempt_row_id)}::uuid, 'provider_voided',
    'zc-void-ref-c26', 'ZC001D synthetic provider void', 'zc001d-op/ref-4', ${OWNER})::text`),
  ['ok', 'state', 'classification', 'resolution', 'recorded']),
  { ok: true, state: 'approved', classification: 'resolved', resolution: 'provider_voided', recorded: false },
  '(5) the operator resolves the orphan (provider_voided)');

  // (6) Two retirements serialize on the terminal lock: exactly one retires.
  sc.eq(await B1.json(`begin; ${set6(D6, 'retired', 'end_of_pilot')};`), changed('live', 'draining', 'retired'),
    '(6) B1: the retirement succeeds once every attempt is resolved and no payment.create is pending (uncommitted)');
  const againP = B2.json(set6(D6, 'retired', 'end_of_pilot'));
  sc.detail.second_retirement_waits = await provenWait(B2, againP, B1, ['advisory']);
  await B1.query('commit;');
  sc.eq(await againP, { ok: false, error: 'precondition_failed', detail: 'lifecycle_transition' },
    '(6) B2: serialized after the committed retirement, it finds no current binding');
  sc.eq([await currentBinding(6), await operatorEvents(6) - events6], ['none', 2],
    '(6) d6 has no current binding; two operator events (the drain, the retirement)');

  // (7) The replacement till is enabled once the revoked till's binding was lawfully retired.
  sc.eq(await ops.json(set2('enabled', 'live_activation')), changed('live', 'configured', 'enabled'), '(7) the replacement d2 is enabled');

  // (8) revoke_device_management first, then the claim.
  const audits2 = await cardAudits(2);
  sc.eq(await R.json(posTx(revokeDevice(2, 'b'))), revokedEnvelope(2),
    '(8) R: the revocation of d2 (uncommitted; it holds the d2 device row)');
  const lateP = A.json(svc(claimLive(8, 'c26-b', 'c26b')));
  sc.detail.claim_waits_for_the_revocation = await provenWait(A, lateP, R, ['transactionid', 'tuple']);
  sc.eq(await rowLockWait(A, R), { tuple_lock_relations: ['public.devices'], waits_on_holder_transaction: true },
    '(8) A (a LIVE claim on d2) waits inside its write-time proof on the d2 device row R updated');
  sc.eq(lockSet(await advisoryLocks(A)), lockSet([held(k.t2), sharedHeld(k.purge)]),
    '(8) A holds the d2 terminal lock and the shared purge barrier (its identity lock follows the proof)');
  await R.query('commit;');
  sc.eq(tsShape(await lateP), { ok: false, error: 'invalid_session', server_ts: 'string' },
    '(8) A: invalid_session once the revocation committed');
  sc.eq([await attempt(2, 'c26-b'), await cardAudits(2) - audits2, await revokeAudits(2)], [null, 0, 1],
    '(8) no attempt row, no card_attempt.* audit; one device.revoked_management audit');

  // (9) Genuinely clear: the revoked replacement's binding drains and retires at once.
  sc.eq(await ops.json(set2('draining', 'incident')), changed('live', 'enabled', 'draining'), "(9) the inactive d2's binding drains");
  sc.eq(await ops.json(set2('retired', 'end_of_pilot')), changed('live', 'draining', 'retired'),
    '(9) and retires at once: no attempt to resolve, no payment.create pending');
  sc.eq([await operatorEvents(2) - events2, await count(`select count(*) from app.payment_terminals t
    where t.organization_id = ${ORG} and t.lifecycle in ('enabled', 'draining')`)], [4, 0],
  "(9) d2's four operator events (configured, enabled, drained, retired); no binding of the organization admits a start");
}

// =========================================================================================================
// Correction C2 (TEST_BRIEF_C2 §C lane CC; packet §13.2 "Authorization cutoff" and §13.5 CC; D-060 points 1 and 2):
// C34–C39, numbered after C33. The original caller is a person who can hold a platform support session: a synthetic
// Supabase Auth principal linked to an app user with an active platform-admin grant (a grant-only admin proving the
// context with cashier 1's PIN, or a dual-role manager with its own PIN on d1). Its context proof passes while no
// support session is active and returns caller_auth_user_id, the binding the adapter passes unchanged to the
// service-only call of the same request. A separate session S (an operator SQL session that sets the exchange's
// lifecycle columns directly, or inserts an ACTIVE row) activates a support session of that app user. Winner order
// (a): S's activation is written before the call and left uncommitted, the call passes its early check and waits on
// a lock held by H, S commits during the wait, H releases: the binding check after the wait refuses permission_denied
// and nothing is written. Winner order (b): H releases first, the call passes its final check and commits while S's
// activation is still uncommitted: it stands, and once S committed the next call with the same binding is refused.
// No advisory lock serializes the support writers (none is added; the packet claims no stronger serialization).
// app.sync_push (change 7) decides once, at its first statement.
// =========================================================================================================
// Race database only: a person who can hold a support session — auth principal 'auth-<key>' linked to app user
// 'user-<key>', an active platform-admin grant, no support session. role 'admin': the grant alone (no membership; its
// context proof carries cashier 1's PIN on d1, so the binding is not the PIN employee); role 'manager': the dual role
// (also a manager of the pilot branch with its own PIN session 'pin-<key>' on d1's device session).
async function supportCapablePerson(sc, key, role) {
  const manager = role === 'manager';
  await ops.query(`begin;
insert into auth.users (id, email) values (${id(`auth-${key}`)}, ${lit(`zc001d-support-${key}@example.test`)});
insert into public.app_users (id, email, auth_user_id)
values (${id(`user-${key}`)}, ${lit(`zc001d-support-${key}@example.test`)}, ${id(`auth-${key}`)});
insert into public.platform_admin_grants (app_user_id, status, granted_by) values (${id(`user-${key}`)}, 'active', ${OWNER});
${manager ? `insert into public.memberships (id, app_user_id, organization_id, restaurant_id, branch_id, role)
values (${id(`membership-${key}`)}, ${id(`user-${key}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), 'manager');
insert into public.employee_profiles (id, organization_id, restaurant_id, branch_id, app_user_id, membership_id,
                                      display_name)
values (${id(`employee-${key}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${id(`user-${key}`)},
        ${id(`membership-${key}`)}, ${lit(`ZC001D dual-role manager ${key}`)});
insert into public.pin_sessions (id, organization_id, restaurant_id, branch_id, device_session_id, employee_profile_id,
                                 resolved_membership_id, expires_at)
values (${id(`pin-${key}`)}, ${ORG}, ${F}.zc_rest(), ${F}.zc_branch(), ${id('dsession-1')}, ${id(`employee-${key}`)},
        ${id(`membership-${key}`)}, now() + interval '6 hours');` : ''}
commit;`);
  sc.eq(await ops.json(`select jsonb_build_object(
    'linked', exists (select 1 from public.app_users u where u.id = ${id(`user-${key}`)} and u.auth_user_id = ${id(`auth-${key}`)}),
    'grant', exists (select 1 from public.platform_admin_grants g where g.app_user_id = ${id(`user-${key}`)} and g.status = 'active'),
    'memberships', (select coalesce(string_agg(m.role, ','), 'none') from public.memberships m
                     where m.app_user_id = ${id(`user-${key}`)}),
    'support_sessions', (select count(*) from public.platform_support_sessions s
                          where s.platform_admin_app_user_id = ${id(`user-${key}`)}))::text`),
  { linked: true, grant: true, memberships: manager ? 'manager' : 'none', support_sessions: 0 },
  `race database only: ${manager ? 'a dual-role manager (its own manager PIN on d1)' : 'a grant-only platform admin'} '${key}': `
    + 'auth principal linked to its app user, an active platform-admin grant, no support session');
  return { key, auth: nodeId(`auth-${key}`), user: nodeId(`user-${key}`), pin: manager ? `pin-${key}` : 'pin-1',
    role: manager ? 'manager' : 'cashier', employee: nodeId(manager ? `employee-${key}` : 'employee-1') };
}
// The person's support session `label`, committed 'pending' (started, not exchanged: never ACTIVE).
const pendingSupport = (person, label) => ops.query(`insert into public.platform_support_sessions (id,
  platform_admin_app_user_id, target_organization_id, reason, status, expires_at, token_hash)
values (${id(`support-${label}`)}, ${lit(person.user)}::uuid, ${ORG}, 'ZC001D synthetic support visit', 'pending',
  now() + interval '15 minutes', ${lit(`zc001d-${label}-handoff-hash`)});`);
// S's activation, left uncommitted: 'update' sets the exchange's lifecycle columns on the pending row (status active,
// token consumed); 'insert' writes an ACTIVE row at once. Answers status / consumed.
const activateSupport = (person, label, how) => (how === 'update'
  ? `begin; update public.platform_support_sessions s set status = 'active', token_consumed_at = now()
  where s.id = ${id(`support-${label}`)} and s.status = 'pending'
  returning s.status || '/' || (s.token_consumed_at is not null)::text;`
  : `begin; insert into public.platform_support_sessions (id, platform_admin_app_user_id, target_organization_id, reason,
  status, expires_at, token_hash, token_consumed_at)
values (${id(`support-${label}`)}, ${lit(person.user)}::uuid, ${ORG}, 'ZC001D synthetic support visit', 'active',
  now() + interval '15 minutes', ${lit(`zc001d-${label}-handoff-hash`)}, now())
returning status || '/' || (token_consumed_at is not null)::text;`);
// Every support session of the person ended (each leg starts with none ACTIVE).
const endSupport = (person) => ops.query(`update public.platform_support_sessions s set status = 'ended', ended_at = now()
  where s.platform_admin_app_user_id = ${lit(person.user)}::uuid and s.status <> 'ended';`);
// The binding check for an explicit binding right now, read by the operator session outside any service request:
// app.card_caller_binding_denial (the canonical predicate of app.current_support_session() applied to the explicit
// identity); 'null' = admitted.
const bindingDenial = (binding) => ops.one(`select coalesce(app.card_caller_binding_denial(${lit(binding)}::uuid), 'null')`);
// app.current_support_session() as the person's JWT resolves it (the predicate of app.sync_push change 7), read by the
// operator session (the JWT subject set for that one block only): 'true' = an ACTIVE support session.
const supportSessionOf = (person) => ops.one(`do $zc$ begin
  perform set_config('request.jwt.claim.sub', ${lit(person.auth)}, true);
  perform set_config('zc001d.support', (app.current_support_session() is not null)::text, false);
end $zc$;
select current_setting('zc001d.support');`);
// A letters-only md5 (no digit run is ever printed).
const lettersMd5 = (expr) => `translate(md5(${expr}), '0123456789', 'ghijklmnop')`;
// Row counts of every table a refused call could write (the race database is this run's alone) and d1's device
// session deadline / device activity stamp (digested): compared, never printed.
const writeState = () => ops.json(`select jsonb_build_object(
  'attempts', (select count(*) from app.card_provider_attempts),
  'private_events', (select count(*) from app.card_provider_private_events),
  'tenant_audits', (select count(*) from public.audit_events),
  'platform_audits', (select count(*) from public.platform_admin_audit_events),
  'payments', (select count(*) from public.payments),
  'sync_operations', (select count(*) from public.sync_operations),
  'tombstones', (select count(*) from app.card_attempt_identity_tombstones),
  'd1_session', (select ${lettersMd5(`ds.expires_at::text || '/' || coalesce(d.last_seen_at::text, '-')`)}
                   from public.device_sessions ds join public.devices d on d.id = ds.device_id
                  where ds.id = ${id('dsession-1')}))::text`);
// One d1 attempt row, every column digested ('none' = no row): compared, never printed.
const attemptDigest = (label) => ops.one(`select coalesce((select ${lettersMd5('to_jsonb(a)::text')}
  from app.card_provider_attempts a where a.organization_id = ${ORG} and a.device_id = ${dev(1)}
  and a.local_operation_id = ${lop(label)}), 'none')`);
// card_attempt.<action> audits of d1.
const auditsOf = (action) => count(`select count(*) from public.audit_events e
  where e.action = ${lit(`card_attempt.${action}`)} and e.device_id = ${dev(1)}`);
// The original-caller binding, the last argument of the five session-proving service-only calls (D-060 point 2).
const bindArg = (binding) => `, ${lit(binding)}::uuid`;
const claimAs = (person, label, orderLabel, binding) => `public.card_attempt_claim(${id(person.pin)}, ${dev(1)},
  'zc-token-1', ${lop(label)}, 'live', 1234, 'ILS', ${ord(orderLabel)}, 1, 'production', ${F}.zc_terminals(1, 'live'),
  ${F}.zc_credentials(1, 'live'), 'alpha16-l32-v1'${bindArg(binding)})`;
const releaseAs = (person, label, binding) => `public.card_attempt_mark_release_requested(${id(person.pin)}, ${dev(1)},
  'zc-token-1', ${lop(label)}${bindArg(binding)})`;
const recordingAs = (person, label, binding) => `public.card_attempt_mark_recording_result(${id(person.pin)}, ${dev(1)},
  'zc-token-1', ${lop(label)}, 'permission_denied'${bindArg(binding)})`;
const freeAs = (person, label, binding) => `public.card_attempt_free_order(${id(person.pin)}, ${dev(1)}, 'zc-token-1',
  ${lop(label)}, 'ZC001D synthetic free', 'provider_report', ${lit(`zc-report-${label}`)}${bindArg(binding)})`;
const readAs = (person, label, binding, environment) => `public.card_attempt_adapter_read(${id(person.pin)}, ${dev(1)},
  'zc-token-1', ${lop(label)}, ${lit(environment)}, ${F}.zc_terminals(1, 'live'), ${F}.zc_credentials(1, 'live')${bindArg(binding)})`;
const pushAs = (person, op) => `public.sync_push(${id(person.pin)}, ${dev(1)}, jsonb_build_array(${op}))`;
// Runs `expr` as the POS (authenticated) inside a PL/pgSQL block and answers its text, or 'SQLSTATE:<code>:<message>'
// when it raises (its subtransaction rolled back; psql's ON_ERROR_STOP never ends the session).
const posCaught = (expr) => `set role authenticated; do $zc$ begin perform set_config('zc001d.caught', (${expr})::text, false);
exception when others then perform set_config('zc001d.caught', 'SQLSTATE:' || sqlstate || ':' || sqlerrm, false); end $zc$;
reset role; select current_setting('zc001d.caught');`;
const BINDING_REFUSED = { ok: false, error: 'permission_denied', server_ts: 'string' };
const SUPPORT_REFUSED_PUSH = 'SQLSTATE:42501:sync_push: permission denied (active support session)';
// H's locks: the d1 terminal admission lock, or one row FOR UPDATE / FOR NO KEY UPDATE.
const terminalHold = (key) => ({ kind: 'terminal', key, what: 'the d1 terminal lock' });
const rowHold = (what, relation, where, mode = 'update') => ({ kind: 'row', what, relation, mode,
  sql: `begin; select 1 from ${relation} x where ${where} for ${mode};` });
const orderHold = (orderLabel) => rowHold(`the orders row of ${orderLabel}`, 'public.orders', `x.id = ${ord(orderLabel)}`);
const attemptRowHold = (label) => rowHold(`the attempt row of ${label}`, 'app.card_provider_attempts',
  `x.organization_id = ${ORG} and x.device_id = ${dev(1)} and x.local_operation_id = ${lop(label)}`);
const syncRowHold = (label) => rowHold(`the sync_operations row of ${label}`, 'public.sync_operations',
  `x.organization_id = ${ORG} and x.device_id = ${dev(1)} and x.local_operation_id = ${lop(label)}`);
const pinSessionHold = (pin) => rowHold(`the PIN session row of ${pin}`, 'public.pin_sessions', `x.id = ${id(pin)}`,
  'no key update');
const ISOLATION_SERVICE = 'READ COMMITTED (observed): the binding check after the lock wait is a new statement of the VOLATILE body '
  + 'with a new snapshot - it saw the activation S committed during the wait (a: permission_denied); a call whose final check ran '
  + 'while S was uncommitted was admitted and committed (b: it stands), and the next call saw the committed activation (refused)';
const ISOLATION_PUSH = 'READ COMMITTED (observed): app.sync_push decides the support guard once, at its first statement; a push '
  + 'that passed it and waited on the terminal lock while S committed completed, and the next request saw the committed '
  + 'activation (42501)';

// The four sessions of one leg: P (the person's POS tab: its JWT), A (the adapter's service client), H (the lock
// holder) and S (the activating operator session); closed at the end of the leg.
async function legSessions(sc, tag, person) {
  const P = await sc.open(`${tag}_pos`, `set request.jwt.claim.sub = ${lit(person.auth)};`);
  const A = await sc.open(`${tag}_adapter`);
  const H = await sc.open(`${tag}_holder`);
  const S = await sc.open(`${tag}_activator`);
  return { P, A, H, S, close: async () => { for (const s of [P, A, H, S]) await s.close(); } };
}
// A scenario's legs, in order: each opens and closes its own sessions and starts with no ACTIVE support session.
async function runLegs(sc, legs) {
  sc.detail.legs = legs.map(([name]) => name);
  for (const [, leg] of legs) await leg();
}
// The transaction isolation of a leg's calling session (recorded with the observed cutoff semantics).
async function isolationOf(sc, session, who, note) {
  const level = await session.one(`select current_setting('transaction_isolation')`);
  sc.eq(level, 'read committed', `start: ${who} runs READ COMMITTED (the default; each statement takes a new snapshot)`);
  return { transaction_isolation: level, cutoff: note };
}
// The person's caller-scoped context proof (P: the person's JWT): ok, and caller_auth_user_id = its auth principal —
// the binding the adapter passes unchanged to the service-only call of the same request.
async function provenBinding(sc, P, person, leg, orderLabel = null, attemptLabel = null) {
  const ctx = await P.json(pos(`public.card_attempt_context(${id(person.pin)}, ${dev(1)}, 'zc-token-1',
    ${orderLabel ? ord(orderLabel) : 'null'}, ${attemptLabel ? lop(attemptLabel) : 'null'})`));
  sc.eq(pick(ctx, ['ok', 'role', 'employee_profile_id']), { ok: true, role: person.role, employee_profile_id: person.employee },
    `${leg} P: the person's context proof passes (no ACTIVE support session)`);
  sc.eq(ctx.caller_auth_user_id, person.auth, `${leg} P: it returns caller_auth_user_id = the person's auth principal (the binding)`);
  return ctx.caller_auth_user_id;
}
// One race between a call admitted under the person's binding and S's support activation. S writes the activation
// first and leaves it uncommitted (`how`: 'update' of a pending row, or 'insert' of an ACTIVE row); H takes `hold`;
// `start()` begins the call in `waiter`, which provenWait proves blocked on H. Then `first` commits first:
// 'activation' (S commits during the wait, then H releases) or 'call' (H releases, the call answers and commits, then
// S commits). `observe()` is the support predicate as another session sees it: `admitted` while S's activation is
// uncommitted, `refused` once it committed.
async function supportRace(sc, leg, { waiter, H, S, person, label, how, hold, waitLocks, waitWhat, start, first, observe,
  admitted, refused }) {
  if (how === 'update') await pendingSupport(person, label);
  sc.eq(await S.one(activateSupport(person, label, how)), 'active/true', `${leg} S: a support session of the person activated (${
    how === 'update' ? 'the pending row exchanged: status active, token consumed' : 'an ACTIVE row inserted'}; uncommitted)`);
  sc.eq(await observe(), admitted, `${leg} while S's activation is uncommitted the support predicate does not see it`);
  if (hold.kind === 'terminal') {
    await H.query(`begin; select app.card_terminal_lock(${ORG}, ${dev(1)});`);
    sc.eq(lockSet(await advisoryLocks(H)), lockSet([held(hold.key)]), `${leg} H holds ${hold.what} (uncommitted)`);
  } else if (hold.kind === 'advisory') {
    await H.query(hold.sql);
    sc.eq(lockSet(await advisoryLocks(H)), lockSet([held(hold.key)]), `${leg} H holds ${hold.what} (uncommitted)`);
  } else {
    sc.eq(await H.query(hold.sql), ['1'], `${leg} H holds ${hold.what} FOR ${hold.mode.toUpperCase()} (uncommitted)`);
  }
  const pending = start();
  const advisoryHold = hold.kind === 'terminal' || hold.kind === 'advisory';
  const wait = await provenWait(waiter, pending, H, advisoryHold ? ['advisory'] : ['transactionid', 'tuple']);
  if (!advisoryHold) {
    sc.eq(await rowLockWait(waiter, H), { tuple_lock_relations: [hold.relation], waits_on_holder_transaction: true },
      `${leg} the call waits on ${hold.what} that H holds`);
  }
  sc.eq(lockSet(await advisoryLocks(waiter)), lockSet(waitLocks), `${leg} while waiting ${waitWhat}`);
  if (first === 'activation') {
    await S.query('commit;');
    sc.eq(await observe(), refused, `${leg} S committed the activation DURING the call's wait`);
    await H.query('commit;');
    return { answer: await pending, wait };
  }
  await H.query('commit;');
  const answer = await pending;
  sc.eq(await observe(), admitted, `${leg} the call answered (and committed) while S's activation was still uncommitted`);
  await S.query('commit;');
  sc.eq(await observe(), refused, `${leg} S committed the activation only after the call`);
  return { answer, wait };
}
// Standing LIVE claims declined by the scope-bound provider finish, while the person's last support session is still
// ACTIVE: the finish takes no binding and no support check (packet §13.4), so d1 keeps none of them unresolved.
async function declineAll(sc, standing) {
  for (const [label, claim] of standing) {
    sc.eq(pick(await ops.json(svc(finish(claim, 'commit', 'declined', DECLINED))), ['ok', 'state']), { ok: true, state: 'declined' },
      `cleanup: ${label} declined by the provider finish (no binding; the person's support session still ACTIVE)`);
  }
}

// ---------------------------------------------------------------------------------------------------------
// C34 (D-060 point 2; packet §13.2 "Authorization cutoff"): card_attempt_claim (LIVE) under the binding of a
//      grant-only platform admin (cashier 1's PIN on d1) against a support activation of that admin. (a1) a fresh
//      claim waits on the d1 terminal lock, taken before its proof; (a2) a fresh claim passes the check after its
//      identity lock and waits on the orders row; (a3) the replay of a standing claim waits on the terminal lock. In
//      each, S commits the activation during the wait and the claim answers permission_denied with nothing written
//      ((a2) at the final check after the orders / shifts / drawers locks; (a3) before the replay: no attempt fact),
//      and once the support session ended the identical request is admitted. (b1) / (b2) the same two waits with H
//      released first: the claim passes its final check and commits while S's activation is uncommitted and stands;
//      once S committed, the next claim and the replay with the same binding are refused.
// ---------------------------------------------------------------------------------------------------------
async function c34ClaimCutoff(sc) {
  sc.eq(await currentBinding(1), terminalLabel(ORIGINAL_LIVE, 'live', 'enabled'), 'start: the original LIVE binding of d1 is enabled');
  const person = await supportCapablePerson(sc, 'c34', 'admin');
  await makeOrders('c34a1', 'c34a2', 'c34a3', 'c34b1', 'c34b2', 'c34n1', 'c34n2');
  const k = await keyValues({ t1: terminalKeySql(1), purge: PURGE_KEY_SQL, a2: identityKeySql(1, 'c34-a2'),
    b2: identityKeySql(1, 'c34-b2') });
  const standing = [];
  const fresh = { ok: true, claim_created: true, replayed: false, state: 'sent', mode: 'live' };
  const race = (L, leg, label, orderLabel, binding, onOrders, first) => supportRace(sc, leg, { waiter: L.A, H: L.H, S: L.S,
    person, label, how: onOrders ? 'insert' : 'update', hold: onOrders ? orderHold(orderLabel) : terminalHold(k.t1),
    waitLocks: onOrders ? [held(k.t1), sharedHeld(k.purge), held(k[label === 'c34-a2' ? 'a2' : 'b2'])] : [waiting(k.t1)],
    waitWhat: onOrders ? 'past its proof and the check after its identity lock it holds the d1 terminal lock, the shared purge '
      + 'barrier and its identity lock' : 'it waits on the d1 terminal lock and holds no other advisory lock (before its proof)',
    start: () => L.A.json(svc(claimAs(person, label, orderLabel, binding))), first,
    observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
  const refusedLeg = (tag, label, orderLabel, onOrders, replay) => async () => {
    const leg = `(${tag})`;
    const L = await legSessions(sc, tag, person);
    await endSupport(person);
    if (tag === 'a1') sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
    const binding = await provenBinding(sc, L.P, person, leg, orderLabel);
    if (replay) {
      const first = await L.A.json(svc(claimAs(person, label, orderLabel, binding)));
      sc.eq(pick(first, Object.keys(fresh)), fresh, `${leg} A: a claim of the person outside support stands (committed)`);
      standing.push([label, first]);
    }
    const before = await writeState();
    const row = await attemptDigest(label);
    const { answer, wait } = await race(L, leg, label, orderLabel, binding, onOrders, 'activation');
    sc.detail[`${tag}_${replay ? 'replay' : 'claim'}_waits_on_${onOrders ? 'orders_row' : 'terminal_lock'}`] = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED, `${leg} A: the ${replay ? 'replay' : 'claim'} answers exactly permission_denied ${onOrders
      ? '(its final check after the orders / shifts / drawers locks, before the refusal evidence or the insert)'
      : replay ? '(the check after its identity lock precedes the replay: no attempt id, state or envelope)'
        : '(the check after its terminal / barrier / identity locks)'}`);
    sc.eq([await writeState(), await attemptDigest(label)], [before, row], `${leg} nothing written: ${replay ? 'the standing row unchanged'
      : 'no attempt row'}, no private event, tenant / platform audit, payment, sync row or tombstone; d1's session not renewed`);
    await endSupport(person);
    const retry = await L.A.json(svc(claimAs(person, label, orderLabel, binding)));
    if (replay) {
      sc.eq(pick(retry, ['ok', 'claim_created', 'replayed', 'state']), { ok: true, claim_created: false, replayed: true, state: 'sent' },
        `${leg} control: once the support session ended, the replay answers its envelope`);
    } else {
      sc.eq(pick(retry, Object.keys(fresh)), fresh,
        `${leg} control: once the support session ended, the identical request claims (the refusal was the support boundary alone)`);
      standing.push([label, retry]);
    }
    await L.close();
  };
  const standingLeg = (tag, label, orderLabel, onOrders, nextLabel, nextOrder) => async () => {
    const leg = `(${tag})`;
    const L = await legSessions(sc, tag, person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, leg, orderLabel);
    const { answer, wait } = await race(L, leg, label, orderLabel, binding, onOrders, 'call');
    sc.detail[`${tag}_claim_waits_on_${onOrders ? 'orders_row' : 'terminal_lock'}`] = wait;
    sc.eq(pick(answer, Object.keys(fresh)), fresh,
      `${leg} A: released first, the claim passed its final check while S's activation was uncommitted and committed`);
    standing.push([label, answer]);
    sc.eq(pick(await attempt(1, label), ['state', 'mode', 'initiated_by_employee_profile_id', 'initiated_by_membership_id']),
      { state: 'sent', mode: 'live', initiated_by_employee_profile_id: nodeId('employee-1'),
        initiated_by_membership_id: nodeId('membership-1') },
      `${leg} the claim stands after the activation committed (the PIN employee's authority; the binding confers none)`);
    const before = await writeState();
    const row = await attemptDigest(label);
    sc.eq(tsShape(await L.A.json(svc(claimAs(person, nextLabel, nextOrder, binding)))), BINDING_REFUSED,
      `${leg} the next claim with the same binding (a new identity) answers permission_denied`);
    sc.eq(tsShape(await L.A.json(svc(claimAs(person, label, orderLabel, binding)))), BINDING_REFUSED,
      `${leg} the replay of the standing claim with the same binding answers permission_denied (no attempt fact disclosed)`);
    sc.eq([await writeState(), await attemptDigest(nextLabel), await attemptDigest(label)], [before, 'none', row],
      `${leg} nothing written by either refusal; the standing row unchanged`);
    await L.close();
  };
  await runLegs(sc, [['a1', refusedLeg('a1', 'c34-a1', 'c34a1', false, false)],
    ['a2', refusedLeg('a2', 'c34-a2', 'c34a2', true, false)],
    ['a3', refusedLeg('a3', 'c34-a3', 'c34a3', false, true)],
    ['b1', standingLeg('b1', 'c34-b1', 'c34b1', false, 'c34-n1', 'c34n1')],
    ['b2', standingLeg('b2', 'c34-b2', 'c34b2', true, 'c34-n2', 'c34n2')]]);
  await declineAll(sc, standing);
  await endSupport(person);
}

// ---------------------------------------------------------------------------------------------------------
// C35 (D-060 point 2; packet §13.2: the release mark's final check after the attempt row lock):
//      card_attempt_mark_release_requested of a sent LIVE attempt under the binding of a grant-only platform admin
//      (cashier 1's PIN). (a) the mark waits on the attempt row H holds FOR UPDATE while S commits the activation:
//      permission_denied, release_requested_at not stamped, no card_attempt.release_requested audit; once the
//      support session ended the identical request stamps it. (b) H releases first: the mark stamps and commits
//      while S's activation is uncommitted and stands; once S committed the next mark with the same binding is
//      refused and re-stamps nothing.
// ---------------------------------------------------------------------------------------------------------
async function c35ReleaseMarkCutoff(sc) {
  const person = await supportCapablePerson(sc, 'c35', 'admin');
  await makeOrders('c35a', 'c35b');
  const standing = [];
  for (const tag of ['a', 'b']) {
    const claimed = await ops.json(svc(claimLive(1, `c35-${tag}`, `c35${tag}`)));
    sc.eq(pick(claimed, ['ok', 'claim_created', 'state']), { ok: true, claim_created: true, state: 'sent' },
      `setup: a committed LIVE claim c35-${tag} (sent; the native transport binding)`);
    standing.push([`c35-${tag}`, claimed]);
  }
  const envelope = (label) => ({ ok: true, attempt_id: nodeLop(label), state: 'sent' });
  const stamped = async (label) => (await attempt(1, label)).release_requested_at !== null;
  const race = (L, leg, label, binding, first) => supportRace(sc, leg, { waiter: L.A, H: L.H, S: L.S, person, label: `${label}-s`,
    how: 'update', hold: attemptRowHold(label), waitLocks: [], waitWhat: 'the mark holds no advisory lock',
    start: () => L.A.json(svc(releaseAs(person, label, binding))), first,
    observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
  const a = async () => {
    const L = await legSessions(sc, 'a', person);
    await endSupport(person);
    sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
    const binding = await provenBinding(sc, L.P, person, '(a)', null, 'c35-a');
    const [before, row, audits] = [await writeState(), await attemptDigest('c35-a'), await auditsOf('release_requested')];
    const { answer, wait } = await race(L, '(a)', 'c35-a', binding, 'activation');
    sc.detail.a_mark_waits_on_attempt_row = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED,
      '(a) A: the release mark answers permission_denied (its final check after the attempt row lock saw the committed activation)');
    sc.eq([await writeState(), await attemptDigest('c35-a'), await stamped('c35-a')], [before, row, false],
      '(a) nothing written: release_requested_at not stamped (the attempt row unchanged), no audit, no private event');
    await endSupport(person);
    sc.eq(pick(await L.A.json(svc(releaseAs(person, 'c35-a', binding))), ['ok', 'attempt_id', 'state']), envelope('c35-a'),
      '(a) control: once the support session ended, the identical request answers the attempt envelope');
    sc.eq([await stamped('c35-a'), await auditsOf('release_requested') - audits], [true, 1],
      '(a) control: it stamped release_requested_at with one card_attempt.release_requested audit');
    await L.close();
  };
  const b = async () => {
    const L = await legSessions(sc, 'b', person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, '(b)', null, 'c35-b');
    const audits = await auditsOf('release_requested');
    const { answer, wait } = await race(L, '(b)', 'c35-b', binding, 'call');
    sc.detail.b_mark_waits_on_attempt_row = wait;
    sc.eq(pick(answer, ['ok', 'attempt_id', 'state']), envelope('c35-b'),
      "(b) A: released first, the mark passed its final check while S's activation was uncommitted and committed");
    sc.eq([await stamped('c35-b'), await auditsOf('release_requested') - audits], [true, 1],
      '(b) the stamp stands after the activation committed (one card_attempt.release_requested audit)');
    const [before, row] = [await writeState(), await attemptDigest('c35-b')];
    sc.eq(tsShape(await L.A.json(svc(releaseAs(person, 'c35-b', binding)))), BINDING_REFUSED,
      '(b) the next release mark with the same binding answers permission_denied');
    sc.eq([await writeState(), await attemptDigest('c35-b')], [before, row], '(b) it re-stamped nothing and wrote nothing');
    await L.close();
  };
  await runLegs(sc, [['a', a], ['b', b]]);
  await declineAll(sc, standing);
  await endSupport(person);
}

// ---------------------------------------------------------------------------------------------------------
// C36 (D-060 point 2; packet §13.2: the recording mark's final check after the sync_operations -> attempt row
//      locks): card_attempt_mark_recording_result of an approved LIVE attempt whose recording leg was refused
//      (pushed under the kitchen PIN: memoized permission_denied; the refusal not yet reported) under the binding of a
//      grant-only platform admin. The mark passes its check before the first envelope answer and (a1) waits on the
//      sync_operations row or (a2), holding that row, on the attempt row H holds FOR UPDATE while S commits the
//      activation: permission_denied, no refusal code, no card_attempt.recording_refused audit; once the support
//      session ended the identical request records it. (b) H releases first: the mark records the refusal and commits
//      while S's activation is uncommitted and stands; once S committed the next mark with the same binding is refused.
// ---------------------------------------------------------------------------------------------------------
async function c36RecordingMarkCutoff(sc) {
  const person = await supportCapablePerson(sc, 'c36', 'admin');
  await makeOrders('c36a1', 'c36a2', 'c36b');
  for (const tag of ['a1', 'a2', 'b']) {
    const [label, orderLabel] = [`c36-${tag}`, `c36${tag}`];
    const claimed = await ops.json(svc(claimLive(1, label, orderLabel)));
    sc.eq(pick(claimed, ['ok', 'claim_created']), { ok: true, claim_created: true }, `setup ${label}: claimed (the native transport binding)`);
    sc.eq((await ops.json(svc(finish(claimed, 'commit', 'approved', APPROVED)))).state, 'approved', `setup ${label}: approved`);
    sc.eq(pick((await ops.json(pos(push(4, payOp(label, orderLabel))))).results[0], ['ok', 'error', 'status']),
      { ok: false, error: 'permission_denied', status: 'rejected' },
      `setup ${label}: its recording leg pushed under the kitchen PIN session is memoized permission_denied`);
    sc.eq(pick(await attempt(1, label), ['state', 'refusal_code', 'recording_refused_at']),
      { state: 'approved', refusal_code: null, recording_refused_at: null }, `setup ${label}: approved, its refusal not yet reported`);
  }
  const recorded = { ok: true, refusal_code: 'permission_denied', classification: 'approved_unrecorded', recoverable: true,
    resume_count: 0 };
  const refusal = async (label) => pick(await attempt(1, label), ['refusal_code']);
  const race = (L, leg, label, binding, hold, first) => supportRace(sc, leg, { waiter: L.A, H: L.H, S: L.S, person,
    label: `${label}-s`, how: 'update', hold, waitLocks: [], waitWhat: 'the mark holds no advisory lock',
    start: () => L.A.json(svc(recordingAs(person, label, binding))), first,
    observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
  const refusedLeg = (tag, hold, where) => async () => {
    const [leg, label] = [`(${tag})`, `c36-${tag}`];
    const L = await legSessions(sc, tag, person);
    await endSupport(person);
    if (tag === 'a1') sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
    const binding = await provenBinding(sc, L.P, person, leg, null, label);
    const [before, row, audits] = [await writeState(), await attemptDigest(label), await auditsOf('recording_refused')];
    const { answer, wait } = await race(L, leg, label, binding, hold, 'activation');
    sc.detail[`${tag}_mark_waits_on_${where}`] = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED, `${leg} A: the recording mark answers permission_denied (its final check after the `
      + 'sync_operations -> attempt row locks, before the evidence, the refusal write and the envelope)');
    sc.eq([await writeState(), await attemptDigest(label), await refusal(label)], [before, row, { refusal_code: null }],
      `${leg} nothing written: no refusal code (the attempt row unchanged), no audit, no denial evidence`);
    await endSupport(person);
    sc.eq(pick(await L.A.json(svc(recordingAs(person, label, binding))), Object.keys(recorded)), recorded,
      `${leg} control: once the support session ended, the identical request records the refusal (recoverable)`);
    sc.eq(await auditsOf('recording_refused') - audits, 1, `${leg} control: one card_attempt.recording_refused audit`);
    await L.close();
  };
  const b = async () => {
    const L = await legSessions(sc, 'b', person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, '(b)', null, 'c36-b');
    const audits = await auditsOf('recording_refused');
    const { answer, wait } = await race(L, '(b)', 'c36-b', binding, syncRowHold('c36-b'), 'call');
    sc.detail.b_mark_waits_on_sync_row = wait;
    sc.eq(pick(answer, Object.keys(recorded)), recorded,
      "(b) A: released first, the mark passed its final check while S's activation was uncommitted and recorded the refusal");
    sc.eq([await refusal('c36-b'), await auditsOf('recording_refused') - audits], [{ refusal_code: 'permission_denied' }, 1],
      '(b) the recorded refusal stands after the activation committed (one card_attempt.recording_refused audit)');
    const [before, row] = [await writeState(), await attemptDigest('c36-b')];
    sc.eq(tsShape(await L.A.json(svc(recordingAs(person, 'c36-b', binding)))), BINDING_REFUSED,
      '(b) the next recording mark with the same binding answers permission_denied (no envelope)');
    sc.eq([await writeState(), await attemptDigest('c36-b')], [before, row], '(b) nothing written by the refusal');
    await L.close();
  };
  await runLegs(sc, [['a1', refusedLeg('a1', syncRowHold('c36-a1'), 'sync_row')],
    ['a2', refusedLeg('a2', attemptRowHold('c36-a2'), 'attempt_row')], ['b', b]]);
  await endSupport(person);
}

// ---------------------------------------------------------------------------------------------------------
// C37 (D-060 point 2; packet §13.2: free_order's final check after the orders -> attempt row locks):
//      card_attempt_free_order of a LIVE attempt left unknown after a lookup (no charge risk) under the binding of a
//      dual-role manager (its own manager PIN and JWT; the binding is the PIN employee's own principal). The free (a1)
//      waits on the orders row or (a2), holding that row, on the attempt row H holds FOR UPDATE while S commits the
//      activation: permission_denied, the order not freed, no card_attempt.order_freed audit; once the support session
//      ended the identical request frees it. (b) H releases first: the free commits while S's activation is
//      uncommitted and stands; once S committed the next free with the same binding is refused (no envelope of the
//      freed attempt).
// ---------------------------------------------------------------------------------------------------------
async function c37FreeOrderCutoff(sc) {
  const person = await supportCapablePerson(sc, 'c37', 'manager');
  await makeOrders('c37a1', 'c37a2', 'c37b');
  for (const tag of ['a1', 'a2', 'b']) {
    const [label, orderLabel] = [`c37-${tag}`, `c37${tag}`];
    const claimed = await ops.json(svc(claimLive(1, label, orderLabel)));
    sc.eq(pick(claimed, ['ok', 'claim_created']), { ok: true, claim_created: true }, `setup ${label}: claimed (the native transport binding)`);
    sc.eq((await ops.json(svc(finish(claimed, 'commit', 'unknown')))).state, 'unknown', `setup ${label}: commit reply unknown`);
    sc.eq((await ops.json(svc(finish(claimed, 'lookup', 'pending', {}, 'operator')))).state, 'unknown',
      `setup ${label}: a lookup was attempted`);
    sc.eq(pick(await attempt(1, label), ['state', 'charge_may_exist', 'order_freed_at']),
      { state: 'unknown', charge_may_exist: false, order_freed_at: null }, `setup ${label}: unknown, no charge risk, not freed`);
  }
  const freed = { ok: true, state: 'unknown', classification: 'freed' };
  const freedAt = async (label) => (await attempt(1, label)).order_freed_at !== null;
  const race = (L, leg, label, binding, hold, first) => supportRace(sc, leg, { waiter: L.A, H: L.H, S: L.S, person,
    label: `${label}-s`, how: 'update', hold, waitLocks: [], waitWhat: 'the free holds no advisory lock',
    start: () => L.A.json(svc(freeAs(person, label, binding))), first,
    observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
  const refusedLeg = (tag, hold, where) => async () => {
    const [leg, label, orderLabel] = [`(${tag})`, `c37-${tag}`, `c37${tag}`];
    const L = await legSessions(sc, tag, person);
    await endSupport(person);
    if (tag === 'a1') sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
    const binding = await provenBinding(sc, L.P, person, leg, orderLabel, label);
    const [before, row, audits] = [await writeState(), await attemptDigest(label), await auditsOf('order_freed')];
    const { answer, wait } = await race(L, leg, label, binding, hold, 'activation');
    sc.detail[`${tag}_free_waits_on_${where}`] = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED, `${leg} A: the free answers permission_denied (its final check after the orders -> `
      + 'attempt row locks, before the envelope, the evidence and the free)');
    sc.eq([await writeState(), await attemptDigest(label), await freedAt(label)], [before, row, false],
      `${leg} nothing written: the order not freed (the attempt row unchanged), no audit, no denial evidence`);
    await endSupport(person);
    sc.eq(pick(await L.A.json(svc(freeAs(person, label, binding))), Object.keys(freed)), freed,
      `${leg} control: once the support session ended, the identical request frees the order (the manager's evidence-bound free)`);
    sc.eq(await auditsOf('order_freed') - audits, 1, `${leg} control: one card_attempt.order_freed audit`);
    await L.close();
  };
  const b = async () => {
    const L = await legSessions(sc, 'b', person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, '(b)', 'c37b', 'c37-b');
    const audits = await auditsOf('order_freed');
    const { answer, wait } = await race(L, '(b)', 'c37-b', binding, orderHold('c37b'), 'call');
    sc.detail.b_free_waits_on_orders_row = wait;
    sc.eq(pick(answer, Object.keys(freed)), freed,
      "(b) A: released first, the free passed its final check while S's activation was uncommitted and committed");
    sc.eq([await freedAt('c37-b'), await auditsOf('order_freed') - audits], [true, 1],
      '(b) the free stands after the activation committed (one card_attempt.order_freed audit)');
    const [before, row] = [await writeState(), await attemptDigest('c37-b')];
    sc.eq(tsShape(await L.A.json(svc(freeAs(person, 'c37-b', binding)))), BINDING_REFUSED,
      '(b) the next free with the same binding answers permission_denied (not the envelope of the freed attempt)');
    sc.eq([await writeState(), await attemptDigest('c37-b')], [before, row], '(b) nothing written by the refusal');
    await L.close();
  };
  await runLegs(sc, [['a1', refusedLeg('a1', orderHold('c37a1'), 'orders_row')],
    ['a2', refusedLeg('a2', attemptRowHold('c37-a2'), 'attempt_row')], ['b', b]]);
  await endSupport(person);
}

// ---------------------------------------------------------------------------------------------------------
// C38 (D-060 point 2; packet §13.2: adapter_read's final check right after its write-time proof - the attempt read
//      takes no lock - before the attempt lookup, the credential check, its event and the answer):
//      card_attempt_adapter_read of a sent LIVE attempt under the binding of a
//      grant-only platform admin. adapter_read takes no lock of its own: (a) the activation committed before the call
//      — a read whose configuration mismatches answers permission_denied with no security.card_credential_mismatch
//      event (once the support session ended the same read writes that event; a matching read answers the attempt);
//      (b) the activation committed after the call — the read runs while S's activation is uncommitted, without
//      waiting, and answers the attempt; the next read with the same binding is refused. Across the row locks of its
//      write-time proof (H holds cashier 1's PIN session row FOR NO KEY UPDATE): (c) S commits during the wait — the
//      final check refuses, no event; (d) H releases first — the read answers the attempt and stands; the next read
//      is refused.
// ---------------------------------------------------------------------------------------------------------
async function c38AdapterReadCutoff(sc) {
  const person = await supportCapablePerson(sc, 'c38', 'admin');
  await makeOrders('c38');
  const claimed = await ops.json(svc(claimLive(1, 'c38', 'c38')));
  sc.eq(pick(claimed, ['ok', 'claim_created', 'state']), { ok: true, claim_created: true, state: 'sent' },
    'setup: a committed LIVE claim c38 (sent; the native transport binding)');
  const envelope = { ok: true, attempt_id: nodeLop('c38'), state: 'sent', mode: 'live' };
  const mismatchEvents = () => count(`select count(*) from app.card_provider_private_events e
    where e.action = 'security.card_credential_mismatch' and e.device_id = ${dev(1)}`);
  const read = (L, binding, environment) => L.A.json(svc(readAs(person, 'c38', binding, environment)));
  const race = (L, leg, binding, environment, first) => supportRace(sc, leg, { waiter: L.A, H: L.H, S: L.S, person,
    label: `c38-${leg.slice(1, 2)}`, how: 'update', hold: pinSessionHold('pin-1'), waitLocks: [],
    waitWhat: 'the read holds no advisory lock (it waits inside its write-time proof)',
    start: () => read(L, binding, environment), first,
    observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
  const a = async () => {
    const L = await legSessions(sc, 'a', person);
    await endSupport(person);
    sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
    const binding = await provenBinding(sc, L.P, person, '(a)', null, 'c38');
    await pendingSupport(person, 'c38-a');
    sc.eq(await L.S.one(activateSupport(person, 'c38-a', 'update')), 'active/true',
      '(a) S: a support session of the person activated (the pending row exchanged; uncommitted)');
    await L.S.query('commit;');
    sc.eq(await bindingDenial(binding), 'permission_denied', '(a) S committed the activation before the read');
    const before = await writeState();
    sc.eq(tsShape(await read(L, binding, 'test')), BINDING_REFUSED, "(a) A: a read whose environment mismatches the attempt's "
      + 'mode answers permission_denied (before its proof, the attempt read and the credential check)');
    sc.eq(await writeState(), before, '(a) nothing written: no security.card_credential_mismatch event');
    await endSupport(person);
    const events = await mismatchEvents();
    sc.eq(tsShape(await read(L, binding, 'test')), { ok: false, error: 'provider_unavailable', attempt_id: nodeLop('c38'),
      attempt_state: 'sent', server_ts: 'string' }, '(a) control: once the support session ended, the same read answers provider_unavailable');
    sc.eq(await mismatchEvents() - events, 1, '(a) control: it wrote one security.card_credential_mismatch event (the write the refusal prevented)');
    sc.eq(pick(await read(L, binding, 'production'), Object.keys(envelope)), envelope,
      '(a) control: a read with the matching configuration answers the attempt');
    await L.close();
  };
  const b = async () => {
    const L = await legSessions(sc, 'b', person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, '(b)', null, 'c38');
    sc.eq(await L.S.one(activateSupport(person, 'c38-b', 'insert')), 'active/true',
      '(b) S: an ACTIVE support session of the person inserted (uncommitted)');
    sc.eq(await bindingDenial(binding), 'null', "(b) while S's activation is uncommitted the binding check admits the binding");
    sc.eq(pick(await within(read(L, binding, 'production'), 10_000, '(b) the read waited for the uncommitted activation'),
      Object.keys(envelope)), envelope,
    "(b) A: the read runs while S's activation is uncommitted, without waiting (no lock S holds), and answers the attempt");
    await L.S.query('commit;');
    sc.eq(await bindingDenial(binding), 'permission_denied', '(b) S committed the activation only after the read');
    const before = await writeState();
    sc.eq(tsShape(await read(L, binding, 'production')), BINDING_REFUSED,
      '(b) the next read with the same binding answers permission_denied (no attempt fact)');
    sc.eq(await writeState(), before, '(b) nothing written by the refusal');
    await L.close();
  };
  const c = async () => {
    const L = await legSessions(sc, 'c', person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, '(c)', null, 'c38');
    const before = await writeState();
    const { answer, wait } = await race(L, '(c)', binding, 'test', 'activation');
    sc.detail.c_read_waits_inside_its_proof = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED, '(c) A: the read (configuration mismatching) answers permission_denied at its final '
      + 'check right after its write-time proof (the attempt read takes no lock), before the attempt lookup, the '
      + 'credential check, its event and the answer');
    sc.eq(await writeState(), before, '(c) nothing written: no security.card_credential_mismatch event');
    await L.close();
  };
  const d = async () => {
    const L = await legSessions(sc, 'd', person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, '(d)', null, 'c38');
    const { answer, wait } = await race(L, '(d)', binding, 'production', 'call');
    sc.detail.d_read_waits_inside_its_proof = wait;
    sc.eq(pick(answer, Object.keys(envelope)), envelope,
      "(d) A: released first, the read passed its final check while S's activation was uncommitted and answered the attempt");
    const before = await writeState();
    sc.eq(tsShape(await read(L, binding, 'production')), BINDING_REFUSED, '(d) the next read with the same binding answers permission_denied');
    sc.eq(await writeState(), before, '(d) nothing written by the refusal');
    await L.close();
  };
  await runLegs(sc, [['a', a], ['b', b], ['c', c], ['d', d]]);
  await declineAll(sc, [['c38', claimed]]);
  await endSupport(person);
}

// ---------------------------------------------------------------------------------------------------------
// C39 (D-060 point 1; packet §13.1 change 7): app.sync_push through the public wrapper AS authenticated with the
//      person's own JWT (a dual-role manager) and its valid manager PIN on d1, a cash payment.create. (i) The
//      activation committed before the push: 42501 'sync_push: permission denied (active support session)', nothing
//      written; once the support session ended the identical push is applied. (ii) The push passes its guard while
//      S's activation is uncommitted and waits on the d1 terminal lock H holds (change 5); S commits during the wait;
//      H releases: the push completes (the guard at the start of the request is its cutoff); the next push and a
//      replay of the applied operation raise 42501 with nothing written.
// ---------------------------------------------------------------------------------------------------------
async function c39SyncPushCutoff(sc) {
  const person = await supportCapablePerson(sc, 'c39', 'manager');
  await makeOrders('c39i', 'c39ii', 'c39n');
  const k = await keyValues({ t1: terminalKeySql(1) });
  const cashPush = (label, orderLabel) => posCaught(pushAs(person, payOp(label, orderLabel, 'cash', 2000)));
  const applied = (label) => ({ ok: true, status: 'applied', idempotency_replay: false, local_operation_id: nodeLop(label),
    operation_type: 'payment.create' });
  const result = (text, what, label) => pick(parsedJson(text, what).results[0], Object.keys(applied(label)));
  const i = async () => {
    const L = await legSessions(sc, 'i', person);
    await endSupport(person);
    sc.detail.isolation = await isolationOf(sc, L.P, "the person's POS session", ISOLATION_PUSH);
    await pendingSupport(person, 'c39-i');
    sc.eq(await L.S.one(activateSupport(person, 'c39-i', 'update')), 'active/true',
      '(i) S: a support session of the person activated (the pending row exchanged; uncommitted)');
    await L.S.query('commit;');
    sc.eq(await supportSessionOf(person), 'true', "(i) S committed: the person's JWT resolves an ACTIVE support session");
    const before = await writeState();
    sc.eq(await L.P.one(cashPush('c39-i', 'c39i')), SUPPORT_REFUSED_PUSH, "(i) P: the person's push (its own JWT, its valid "
      + "manager PIN and d1's token, a cash payment.create) raises 42501 sync_push: permission denied (active support session)");
    sc.eq([await writeState(), await syncRow(1, 'c39-i'), await paymentsUnder(1, 'c39-i')], [before, null, 0],
      '(i) nothing written: no sync row, no payment, no audit, no private event');
    await endSupport(person);
    sc.eq(result(await L.P.one(cashPush('c39-i', 'c39i')), '(i) control push', 'c39-i'), applied('c39-i'),
      '(i) control: once the support session ended, the identical push is applied');
    sc.eq(await paymentMethods(1, 'c39-i'), 'cash:completed:1234', '(i) control: exactly one cash payment');
    await L.close();
  };
  const ii = async () => {
    const L = await legSessions(sc, 'ii', person);
    await endSupport(person);
    const { answer, wait } = await supportRace(sc, '(ii)', { waiter: L.P, H: L.H, S: L.S, person, label: 'c39-ii', how: 'update',
      hold: terminalHold(k.t1), waitLocks: [waiting(k.t1)],
      waitWhat: 'past its support guard and its PIN / device checks the push waits on the d1 terminal lock (change 5)',
      start: () => L.P.one(cashPush('c39-ii', 'c39ii')), first: 'activation',
      observe: () => supportSessionOf(person), admitted: 'false', refused: 'true' });
    sc.detail.ii_push_waits_on_terminal_lock = wait;
    sc.eq(result(answer, '(ii) push', 'c39-ii'), applied('c39-ii'),
      '(ii) P: the push that passed its guard before the activation committed completes: applied (the guard is its cutoff)');
    sc.eq(await paymentMethods(1, 'c39-ii'), 'cash:completed:1234', '(ii) exactly one cash payment');
    const before = await writeState();
    sc.eq(await L.P.one(cashPush('c39-n', 'c39n')), SUPPORT_REFUSED_PUSH, '(ii) the next push (a new operation) raises 42501');
    sc.eq(await L.P.one(cashPush('c39-ii', 'c39ii')), SUPPORT_REFUSED_PUSH,
      '(ii) a replay of the applied operation raises 42501 (no stored result disclosed)');
    sc.eq([await writeState(), await syncRow(1, 'c39-n'), await paymentsUnder(1, 'c39-n')], [before, null, 0],
      '(ii) nothing written by either refusal');
    await L.close();
  };
  await runLegs(sc, [['i', i], ['ii', ii]]);
  await endSupport(person);
}

// ---------------------------------------------------------------------------------------------------------
// C40 (D-060 point 2; packet §13.2 "after the proof", added by the C2 self-review of the first C2 build): the
//      binding check right after the write-time proof of card_attempt_mark_release_requested,
//      card_attempt_mark_recording_result, card_attempt_free_order (a dual-role manager) and
//      card_attempt_adapter_read. Each call names an attempt id that does not exist, so the attempt resolver would
//      answer attempt_not_found (an attempt fact), and each waits inside its write-time proof on the PIN session row
//      H holds FOR NO KEY UPDATE. (a) S commits the activation during that wait: the call answers permission_denied,
//      never attempt_not_found, and writes nothing (the first C2 build, without this check, answered
//      attempt_not_found here); once the support session ended the identical request answers attempt_not_found.
//      (b) H releases first: the call passes the check while S's activation is uncommitted and answers
//      attempt_not_found (admitted before the cutoff); once S committed, the next call with the same binding is
//      refused.
// ---------------------------------------------------------------------------------------------------------
async function c40PostProofCheck(sc) {
  const admin = await supportCapablePerson(sc, 'c40', 'admin');
  const manager = await supportCapablePerson(sc, 'c40m', 'manager');
  const NOT_FOUND = { ok: false, error: 'attempt_not_found', server_ts: 'string' };
  const calls = [
    ['release', admin, (label, binding) => releaseAs(admin, label, binding)],
    ['recording', admin, (label, binding) => recordingAs(admin, label, binding)],
    ['free', manager, (label, binding) => freeAs(manager, label, binding)],
    ['read', admin, (label, binding) => readAs(admin, label, binding, 'production')],
  ];
  const target = (op, tag) => `c40-${op}-${tag}-none`;
  sc.eq(await count(`select count(*) from app.card_provider_attempts a where a.organization_id = ${ORG}
    and a.local_operation_id in (${calls.flatMap(([op]) => ['a', 'b'].map((tag) => lop(target(op, tag)))).join(', ')})`), 0,
  'setup: none of the attempt ids the calls name exists (the resolver would answer attempt_not_found)');
  const legs = [];
  for (const [op, person, call] of calls) {
    const race = (L, tag, binding, first) => supportRace(sc, `(${tag}) ${op}:`, { waiter: L.A, H: L.H, S: L.S, person,
      label: `c40-${op}-${tag}`, how: 'update', hold: pinSessionHold(person.pin), waitLocks: [],
      waitWhat: 'the call holds no advisory lock (it waits inside its write-time proof)',
      start: () => L.A.json(svc(call(target(op, tag), binding))), first,
      observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
    legs.push([`${op}-a`, async () => {
      const L = await legSessions(sc, `${op}a`, person);
      await endSupport(person);
      if (op === 'release') sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
      const binding = await provenBinding(sc, L.P, person, `(a) ${op}:`);
      const before = await writeState();
      const { answer, wait } = await race(L, 'a', binding, 'activation');
      sc.detail[`${op}_a_waits_inside_its_proof`] = wait;
      sc.eq(tsShape(answer), BINDING_REFUSED, `(a) ${op}: the call answers permission_denied at the check right after its `
        + "proof, never the resolver's attempt_not_found");
      sc.eq(await writeState(), before, `(a) ${op}: nothing written`);
      await endSupport(person);
      sc.eq(tsShape(await L.A.json(svc(call(target(op, 'a'), binding)))), NOT_FOUND,
        `(a) ${op}: control: once the support session ended, the identical request answers attempt_not_found`);
      await L.close();
    }]);
    legs.push([`${op}-b`, async () => {
      const L = await legSessions(sc, `${op}b`, person);
      await endSupport(person);
      const binding = await provenBinding(sc, L.P, person, `(b) ${op}:`);
      const { answer, wait } = await race(L, 'b', binding, 'call');
      sc.detail[`${op}_b_waits_inside_its_proof`] = wait;
      sc.eq(tsShape(answer), NOT_FOUND, `(b) ${op}: released first, the call passed the check while S's activation was `
        + 'uncommitted and answered attempt_not_found (admitted before the cutoff)');
      const before = await writeState();
      sc.eq(tsShape(await L.A.json(svc(call(target(op, 'b'), binding)))), BINDING_REFUSED,
        `(b) ${op}: the next call with the same binding answers permission_denied`);
      sc.eq(await writeState(), before, `(b) ${op}: nothing written by the refusal`);
      await L.close();
    }]);
  }
  await runLegs(sc, legs);
  await endSupport(admin);
  await endSupport(manager);
}

// ---------------------------------------------------------------------------------------------------------
// C41 (D-060 points 1 and 2; the C2 review, TESTS-01 / TESTS-04): the positions of the claim's two later binding
//      checks and change 7 before the terminal lock. Under the binding of a grant-only platform admin (cashier 1's
//      PIN): (a1) the replay of a standing claim waits on its full-identity lock, which follows the proof - S
//      commits the activation during the wait and the replay answers permission_denied with no attempt envelope
//      (the check right after the identity lock precedes the replay); (s) / (d) a fresh LIVE claim waits on d1's
//      open shift row / its active drawer row, which follow the orders row - the claim answers permission_denied
//      and inserts nothing (its final check follows the order / shift / drawer locks, not merely the orders row).
//      (p) a dual-role manager in an ACTIVE support session pushes a cash payment.create while H holds the d1
//      terminal lock: 42501 at once, without waiting (change 7 is the first statement, before the terminal lock),
//      nothing written.
// ---------------------------------------------------------------------------------------------------------
const identityHold = (label, key) => ({ kind: 'advisory', key, what: `the full-identity lock of ${label}`,
  sql: `begin; select app.card_identity_lock(${ORG}, ${dev(1)}, ${lop(label)});` });
async function c41ClaimCheckPositions(sc) {
  const person = await supportCapablePerson(sc, 'c41', 'admin');
  const manager = await supportCapablePerson(sc, 'c41m', 'manager');
  await makeOrders('c41r', 'c41s', 'c41d', 'c41p');
  const k = await keyValues({ t1: terminalKeySql(1), purge: PURGE_KEY_SQL, r: identityKeySql(1, 'c41-r'),
    s: identityKeySql(1, 'c41-s'), d: identityKeySql(1, 'c41-d') });
  const openShift = `(select s.id from public.shifts s where s.organization_id = ${ORG} and s.device_id = ${dev(1)}
    and s.status = 'open')`;
  const holds = {
    s: rowHold('the open shift row of d1', 'public.shifts', `x.id = ${openShift}`),
    d: rowHold('the active drawer row of d1', 'public.cash_drawer_sessions',
      `x.organization_id = ${ORG} and x.shift_id = ${openShift} and x.status = 'active'`),
  };
  // Setup: the standing claim c41-r under the person's binding while no support session is active.
  await endSupport(person);
  const P0 = await sc.open('setup_pos', `set request.jwt.claim.sub = ${lit(person.auth)};`);
  const binding0 = await provenBinding(sc, P0, person, 'setup:');
  const standing = await ops.json(svc(claimAs(person, 'c41-r', 'c41r', binding0)));
  sc.eq(pick(standing, ['ok', 'claim_created', 'state']), { ok: true, claim_created: true, state: 'sent' },
    "setup: a committed LIVE claim c41-r under the person's binding (no support session active)");
  await P0.close();
  const a1 = async () => {
    const L = await legSessions(sc, 'a1', person);
    await endSupport(person);
    sc.detail.isolation = await isolationOf(sc, L.A, "the adapter's service session", ISOLATION_SERVICE);
    const binding = await provenBinding(sc, L.P, person, '(a1)', 'c41r', 'c41-r');
    const [before, row] = [await writeState(), await attemptDigest('c41-r')];
    const { answer, wait } = await supportRace(sc, '(a1)', { waiter: L.A, H: L.H, S: L.S, person, label: 'c41-a1',
      how: 'update', hold: identityHold('c41-r', k.r), waitLocks: [held(k.t1), sharedHeld(k.purge), waiting(k.r)],
      waitWhat: 'the replay holds the d1 terminal lock and the shared purge barrier and waits on the identity key (after its proof)',
      start: () => L.A.json(svc(claimAs(person, 'c41-r', 'c41r', binding))), first: 'activation',
      observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
    sc.detail.a1_replay_waits_on_identity_lock = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED, '(a1) A: the replay answers exactly permission_denied - the check right after '
      + 'the identity lock precedes the replay (no attempt id, state or envelope)');
    sc.eq([await writeState(), await attemptDigest('c41-r')], [before, row], '(a1) nothing written; the standing attempt unchanged');
    await L.close();
  };
  const fresh = (tag) => async () => {
    const label = `c41-${tag}`;
    const order = `c41${tag}`;
    const L = await legSessions(sc, `a${tag}`, person);
    await endSupport(person);
    const binding = await provenBinding(sc, L.P, person, `(${tag})`, order);
    const before = await writeState();
    const { answer, wait } = await supportRace(sc, `(${tag})`, { waiter: L.A, H: L.H, S: L.S, person, label: `c41-${tag}-s`,
      how: 'update', hold: holds[tag], waitLocks: [held(k.t1), sharedHeld(k.purge), held(k[tag])],
      waitWhat: `the claim holds the d1 terminal lock, the shared purge barrier and its identity lock while it waits on ${holds[tag].what}`,
      start: () => L.A.json(svc(claimAs(person, label, order, binding))), first: 'activation',
      observe: () => bindingDenial(binding), admitted: 'null', refused: 'permission_denied' });
    sc.detail[`${tag}_claim_waits`] = wait;
    sc.eq(tsShape(answer), BINDING_REFUSED, `(${tag}) A: the claim answers exactly permission_denied - its final check follows `
      + `the wait on ${holds[tag].what}, not merely the orders row`);
    sc.eq([await writeState(), await attempt(1, label)], [before, null], `(${tag}) nothing written: no attempt row, no audit, no event`);
    await L.close();
  };
  const p = async () => {
    const L = await legSessions(sc, 'p', manager);
    await endSupport(manager);
    sc.eq(await L.S.one(activateSupport(manager, 'c41-p', 'insert')), 'active/true',
      '(p) S: an ACTIVE support session of the dual-role manager inserted (uncommitted)');
    await L.S.query('commit;');
    sc.eq(await supportSessionOf(manager), 'true', "(p) the manager's JWT now resolves an ACTIVE support session");
    await L.H.query(`begin; select app.card_terminal_lock(${ORG}, ${dev(1)});`);
    sc.eq(lockSet(await advisoryLocks(L.H)), lockSet([held(k.t1)]), '(p) H holds the d1 terminal lock (uncommitted)');
    const before = await writeState();
    sc.eq(await within(L.P.one(posCaught(pushAs(manager, payOp('c41-p', 'c41p', 'cash', 2000)))), 10_000,
      '(p) the support push waited on the terminal lock'), SUPPORT_REFUSED_PUSH,
    '(p) P: the push raises 42501 at once while H holds the d1 terminal lock - change 7 runs before the terminal lock');
    sc.eq([await writeState(), await syncRow(1, 'c41-p'), await paymentsUnder(1, 'c41-p')], [before, null, 0],
      '(p) nothing written');
    await L.H.query('commit;');
    await endSupport(manager);
    await L.close();
  };
  await runLegs(sc, [['a1', a1], ['s', fresh('s')], ['d', fresh('d')], ['p', p]]);
  await declineAll(sc, [['c41-r', standing]]);
  await endSupport(person);
  await endSupport(manager);
}

// ---------------------------------------------------------------------------------------------------------
// Fixture: the shared synthetic prefix, rewritten from pg_temp to a committed schema of the race database.
// ---------------------------------------------------------------------------------------------------------
async function loadFixture() {
  let text;
  if (fixturePath !== null) {
    text = await readFile(fixturePath, 'utf8');
  } else {
    const suite = await readFile(new URL('../bizbot_zcredit_001d_claim_identity_test.sql', import.meta.url), 'utf8');
    assert.equal(suite.split(FIXTURE_MARKER).length, 2, 'the claim-identity suite carries the fixture marker exactly once');
    const start = suite.indexOf('begin;');
    const end = suite.indexOf(FIXTURE_MARKER);
    assert.ok(start >= 0 && start < end, 'the fixture prefix starts at begin;');
    text = suite.slice(start + 'begin;'.length, end);
  }
  text = text.replace(/\r\n/g, '\n')
    .replace(/^[ \t]*create extension if not exists pgtap\b[^\n]*$/gim, '')
    .replace(/^[ \t]*select\s+(no_)?plan\([^)]*\);[ \t]*$/gim, '')
    .replace(/^[ \t]*create temp table _zc_r\b[^\n]*$/gim, '')
    .replace(/^[ \t]*grant all on _zc_r\b[^\n]*$/gim, '')
    .replace(/^-- ZC001D FIXTURE END:[^\n]*$/gm, '')
    .replaceAll('pg_temp.', `${F}.`);
  assert.ok(!text.includes('pg_temp.') && !/\b_zc_r\b/.test(text), 'the fixture is rewritten to the committed schema');
  assert.ok(!/^[ \t]*(commit|rollback|abort)\b/im.test(text) && !/^[ \t]*\\/m.test(text),
    'the fixture neither ends the transaction nor uses psql meta-commands');
  return text;
}

// ---------------------------------------------------------------------------------------------------------
// Pre-run sweep, once-only cleanup and interrupt handling (robustness).
// ---------------------------------------------------------------------------------------------------------
// Clones and dumps of this runner's naming whose creation epoch is older than 6 hours are left-overs of a
// killed run: dropped / removed before this run starts. Newer ones (a concurrent run's) and names without an
// epoch (an earlier format) are never touched.
async function sweepStale() {
  const cutoff = Math.floor(Date.now() / 1000) - STALE_AFTER_SECONDS;
  const stale = (match) => match !== null && Number(match[1]) < cutoff;
  const names = (await docker([...psqlArgs('postgres'), '-c',
    "select datname from pg_database where datname ~ '^zc001d_race_[0-9]{10}_[0-9a-f]{12}$' order by 1"]))
    .split('\n').map((s) => s.trim()).filter(Boolean);
  const databases = names.filter((name) => name !== database && stale(name.match(RACE_DATABASE)));
  for (const name of databases) {
    assert.match(name, RACE_DATABASE);
    await docker(['exec', container, 'dropdb', '-U', 'supabase_admin', '--force', '--if-exists', name]);
  }
  const files = (await docker(['exec', container, 'ls', '-1', '/tmp'])).split('\n').map((s) => s.trim()).filter(Boolean);
  const dumps = files.filter((file) => file !== dumpFile && stale(file.match(RACE_DUMP_FILE)));
  for (const file of dumps) {
    assert.match(file, RACE_DUMP_FILE);
    await docker(['exec', container, 'rm', '-f', `/tmp/${file}`]);
  }
  return { stale_after_hours: STALE_AFTER_SECONDS / 3600, dropped_databases: databases,
    removed_dumps: dumps.map((file) => `/tmp/${file}`) };
}

// The clone is dropped and the in-container dump removed exactly once: at the end of the run, or on SIGINT /
// SIGTERM, which end every psql session first and then exit non-zero (130 / 143).
// An in-flight createdb / pg_dump is awaited first, so neither can recreate what the cleanup removed.
const lifecycle = { dumpStarted: false, dumped: false, createStarted: false, created: false, dropped: false, dumpRemoved: false,
  dumpCall: null, createCall: null };
let cleanupPromise = null;
function dropCloneAndDump() {
  cleanupPromise ??= (async () => {
    let failure = null;
    if (lifecycle.createStarted) {
      try {
        await lifecycle.createCall?.catch(() => {});
        assert.match(database, RACE_DATABASE);
        await docker(['exec', container, 'dropdb', '-U', 'supabase_admin', '--force', '--if-exists', database]);
        lifecycle.dropped = true;
      } catch (error) { failure = error; }
    }
    if (lifecycle.dumpStarted) {
      try {
        await lifecycle.dumpCall?.catch(() => {});
        assert.match(dumpFile, RACE_DUMP_FILE);
        await docker(['exec', container, 'rm', '-f', dumpPath]);
        lifecycle.dumpRemoved = true;
      } catch (error) { failure ??= error; }
    }
    if (failure) throw failure;
  })();
  return cleanupPromise;
}
const CONSTANTS = {
  productionContacted: false,
  providerRequests: 0,
  constantsByConstruction: 'productionContacted and providerRequests are constants by construction, not measurements: '
    + 'this runner has no backend URL, credential, HTTP client or provider transport, and every command it runs is '
    + 'docker exec into the allowlisted local container',
};
function onSignal(signal) {
  if (interrupted !== null) return;
  interrupted = signal;
  const code = signal === 'SIGINT' ? 130 : 143;
  process.stderr.write(`[zc001d] ${signal}: ending the psql sessions, dropping ${database}, removing ${dumpPath}\n`);
  const hardStop = setTimeout(() => process.exit(code), 120_000);
  for (const s of [...sessions]) { try { s.child.kill(); } catch { /* already ended */ } }
  dropCloneAndDump()
    .catch((error) => process.stderr.write(`[zc001d] ${signal}: cleanup failed: ${error?.message ?? error}\n`))
    .finally(() => {
      console.log(JSON.stringify({ status: 'INTERRUPTED', signal, scenarios: results, database, sourceDatabase,
        databaseCreated: lifecycle.created, databaseDropped: lifecycle.dropped, dumpRemoved: lifecycle.dumpRemoved,
        container, ...CONSTANTS }, null, 2));
      clearTimeout(hardStop);
      process.exit(code);
    });
}
process.on('SIGINT', () => onSignal('SIGINT'));
process.on('SIGTERM', () => onSignal('SIGTERM'));

// ---------------------------------------------------------------------------------------------------------
// Main.
// ---------------------------------------------------------------------------------------------------------
let fatal = null;
let sweep = null;
try {
  const listed = await docker(['ps', '--filter', `name=^${container}$`, '--format', '{{.Names}} {{.Ports}}']);
  assert.match(listed, new RegExp(`^${container} .*:${expectedDbPort}->5432/tcp`),
    `refused: ${container} is not running with its database published on port ${expectedDbPort}`);
  sweep = await sweepStale();
  const fixture = await loadFixture();
  // The source database is only read (schema-only dump); every write below targets the fresh clone.
  lifecycle.dumpStarted = true;
  lifecycle.dumpCall = docker(['exec', container, 'pg_dump', '-U', 'supabase_admin', '-d', sourceDatabase, '--schema-only',
    '-Fc', '-f', dumpPath], { timeoutMs: 300_000 });
  await lifecycle.dumpCall;
  lifecycle.dumped = true;
  assert.equal(interrupted, null, 'interrupted before the clone was created');
  lifecycle.createStarted = true;
  lifecycle.createCall = docker(['exec', container, 'createdb', '-U', 'supabase_admin', '-O', 'postgres', '-T', 'template0', database]);
  await lifecycle.createCall;
  lifecycle.created = true;
  await docker(['exec', container, 'pg_restore', '-U', 'supabase_admin', '-d', database, '--exit-on-error', dumpPath],
    { timeoutMs: 600_000 });
  await docker(psqlArgs(database), { timeoutMs: 120_000, input: `begin;
create schema ${F};
grant usage on schema ${F} to authenticated, service_role;
set local search_path to extensions, public, pg_catalog;
set local timezone to 'UTC';
${fixture}
grant execute on all functions in schema ${F} to authenticated, service_role;
commit;
` });
  ops = await new Session('zc_ops').ready;
  assert.equal(await ops.one('select current_database()'), database, 'every session targets the race database');
  assert.equal(await ops.one(`select to_regprocedure('app.card_attempt_claim(uuid, uuid, text, text, text, bigint, text, uuid,
    integer, text, jsonb, jsonb, text, uuid)') is not null and to_regprocedure('app.card_claim_guard(uuid, uuid, uuid, text, text,
    text, uuid)') is not null`), 't', 'the race database carries the 001D migration');
  assert.equal(await count(`select count(*) from public.devices d where d.organization_id = ${ORG}`), 4, 'the fixture is committed');

  // TEST phase: the operator TEST revision and the enabled TEST binding of till d2, retired afterwards.
  if (wants('C5') || wants('C14') || wants('C19') || wants('C20') || wants('C23') || wants('C13')
      || wants('C27') || wants('C28') || wants('C29') || wants('C30') || wants('C33')) {
    const pilot = await ops.json(`select ${F}.zc_pilot('test')::text`);
    assert.equal(pilot.ok, true, `TEST revision: ${JSON.stringify(pilot)}`);
    const bind = await ops.json(`select ${F}.zc_bind(2, 'test')::text`);
    assert.equal(bind.new_lifecycle, 'enabled', `TEST binding: ${JSON.stringify(bind)}`);
    await scenario('C5', 'purge barrier: a claim of the purged identity waits, then identity_in_use', c5PurgeBarrier);
    await scenario('C14', 'TEST identity: concurrent pushes refused pre-ledger, one private event', c14TestPushes);
    await scenario('C19', 'purge vs a push / a claim of its identity holding the terminal lock (purge-first order: C5)',
      c19PurgeAfterHolders);
    await scenario('C23', 'purge vs card_attempt_finish of an expired TEST attempt, both orders, no deadlock',
      c23PurgeVsFinish);
    // Correction C1 (C1-3): the bounded batch over its locked device set; each leaves nothing purge-eligible.
    await scenario('C27', 'bounded purge: a device outside the locked set is untouched until the next batch, both orders',
      c27LockedSetPurge);
    await scenario('C28', 'bounded purge: incident holds set and cleared against a batch, both orders', c28HoldsVsPurge);
    await scenario('C29', 'bounded purge: the pre-ledger TEST refusal against a batch, both orders, de-duplicated',
      c29RefusalVsPurge);
    await scenario('C30', 'bounded purge: a forced failure inside the batch rolls the whole batch back', c30PurgeFailureRollsBack);
    // C1 delta review: the batch's cut-off is fixed before its terminal locks.
    await scenario('C33', 'bounded purge: the cut-off is fixed before the terminal locks - a row expiring while the batch waits survives it',
      c33CutoffBeforeLocks);
    if (wants('C20')) await c20Prepare();
    if (wants('C13')) await c13Prepare();
    for (const lifecycle of ['draining', 'retired']) {
      const step = await ops.json(`select ${setTerminal(2, 'test', lifecycle, 'test_end')}::text`);
      assert.equal(step.new_lifecycle, lifecycle, `TEST binding ${lifecycle}: ${JSON.stringify(step)}`);
    }
  }
  // LIVE phase: the operator revision and the enabled LIVE binding of till d1.
  const live = await ops.json(`select ${F}.zc_pilot('live')::text`);
  assert.equal(live.ok, true, `LIVE revision: ${JSON.stringify(live)}`);
  const bound = await ops.json(`select ${F}.zc_bind(1, 'live')::text`);
  assert.equal(bound.new_lifecycle, 'enabled', `LIVE binding: ${JSON.stringify(bound)}`);
  await scenario('C4', 'terminal lock vs the operator binding setter, both orders', c4TerminalVsOperator);
  // C15 / C16 need d1 without an unresolved attempt (retirement / LIVE activation gates): right after C4.
  await scenario('C15', 'C4 legs: start vs uncommitted retirement / rotation; activation / retirement vs uncommitted start',
    c15TerminalAdmissionLegs);
  await scenario('C16', 'C4 leg: cash and hand-recorded card payment.create vs a retirement, both orders',
    c16PushesVsRetirement);
  await scenario('C17', 'C4 leg: two concurrent set_card_payments_pilot calls serialize, revisions in order',
    c17PilotRevisions);
  await scenario('C3', 'pg_locks of an uncommitted claim: terminal + identity exclusive, purge barrier shared', c3ClaimLocks);
  await scenario('C1', 'identity lock, claim and push, both winning orders', c1IdentityBothOrders);
  await scenario('C2', 'rollback / retry in both directions', c2RollbackRetry);
  await scenario('C6', 'same-identity concurrent claims', c6SameIdentity);
  await scenario('C7', 'two identities, one order', c7OneOrder);
  await scenario('C8', 'M9: a colliding key committed while the claim waits on the unique index', c8PlantedKey);
  await scenario('C9', 'concurrent D-054 Resumes dispatch once; recording-result / other Resume / close vs Resume',
    c9ConcurrentResumes);
  await scenario('C10', 'claim vs shift.close, both orders', c10ClaimVsClose);
  await scenario('C11', 'finish vs shift.close, both interleavings (+ a declining finish)', c11FinishVsClose);
  await scenario('C12', 'forced deadlock on the recording leg: transient_failure, then one recording', c12ForcedDeadlock);
  await scenario('C13', 'lock-order stress, five sessions (with a TEST purge and an order.edit), ordinary and printer-only branch', async (sc) => {
    await stress(sc, 'kds');
    await stress(sc, 'printer_only');
  });
  await scenario('C18', 'a session holding only the identity lock blocks a claim and a push after their terminal lock',
    c18IdentityLockAlone);
  await scenario('C20', 'a claim whose outbound key is forced equal to a purged identity, both orders vs the purge',
    c20ForcedKeyVsPurge);
  await scenario('C21', 'order.edit vs a claim and vs the recording leg of the same order, both orders, deadlock-free',
    c21EditOrderLockOrder);
  // C24 / C25 claim on d1, so they run while its LIVE binding is still enabled (before C22).
  await scenario('C24', 'the guard decides the deferral on the membership row read FOR SHARE: a role grant before / after it',
    c24MembershipForShare);
  await scenario('C25', 'freshness race: a mark committed inside a Resume transaction cannot stand in for its re-dispatch refusal',
    c25FreshnessRace);
  // Correction C1 (C1-5): the support-authority transitions; C32 claims on d1, so it runs before C22.
  await scenario('C31', 'support context: a support session activated by another session between two context calls',
    c31SupportActivation);
  await scenario('C32', 'a membership revoked between the context proof and the service-only write, both orders',
    c32MembershipRevokedAfterProof);
  // Correction C2 (D-060 point 2): the authorization cutoff against a support activation committed by another session,
  // both winner orders; C34–C38 claim on d1 (its LIVE binding enabled), so they run before C22.
  await scenario('C34', 'support cutoff: card_attempt_claim vs an activation committed during / after its wait (terminal lock, orders row, replay)',
    c34ClaimCutoff);
  await scenario('C35', 'support cutoff: card_attempt_mark_release_requested vs an activation during / after its attempt row wait',
    c35ReleaseMarkCutoff);
  await scenario('C36', 'support cutoff: card_attempt_mark_recording_result vs an activation during / after its sync_operations row wait',
    c36RecordingMarkCutoff);
  await scenario('C37', 'support cutoff: card_attempt_free_order (dual-role manager) vs an activation during / after its orders row wait',
    c37FreeOrderCutoff);
  await scenario('C38', 'support cutoff: card_attempt_adapter_read vs an activation before / after the call and across its proof wait',
    c38AdapterReadCutoff);
  await scenario('C39', 'support cutoff: app.sync_push (own JWT and PIN) vs an activation before the push / during its terminal lock wait',
    c39SyncPushCutoff);
  await scenario('C40', 'support cutoff: the check right after the write-time proof (both marks, free_order, adapter_read; no attempt_not_found after the wait)',
    c40PostProofCheck);
  await scenario('C41', 'support cutoff: the claim checks after its identity lock and its shift / drawer locks; change 7 before the terminal lock',
    c41ClaimCheckPositions);
  // C22 leaves d1's binding drained / rotated (configured).
  await scenario('C22', 'credential-reference lock: two bindings naming one reference in conflicting modes, both orders',
    c22CredentialReferenceLock);
  // Last (correction C1, C1-2): C26 needs d1's binding parked and revokes the tills d6 and d2.
  await scenario('C26', 'inactive-device shutdown: claim vs revoke_device_management, drain / retire, replacement till',
    c26InactiveDeviceShutdown);
} catch (error) {
  fatal = error;
} finally {
  for (const s of [...sessions]) await s.close().catch(() => {});
  await dropCloneAndDump().catch((error) => { fatal ??= error; });
}
// After a signal the handler prints the INTERRUPTED evidence and sets the exit code.
if (interrupted === null) {
  const pass = fatal === null && results.length > 0 && results.every((r) => r.pass);
  const summary = {
    status: pass ? 'PASS' : 'FAIL',
    scenarios: results,
    database,
    sourceDatabase,
    databaseCreated: lifecycle.created,
    databaseDropped: lifecycle.dropped,
    dumpRemoved: lifecycle.dumpRemoved,
    container,
    ...(container === CI_CONTAINER ? { ciRunId } : {}),
    sweep,
    fixtureSource: fixturePath ?? 'supabase/tests/bizbot_zcredit_001d_claim_identity_test.sql (prefix)',
    assertions: results.reduce((n, r) => n + (r.detail.assertions ?? 0), 0),
    ...CONSTANTS,
    ...(fatal ? { fatal: String(fatal?.message ?? fatal) } : {}),
  };
  console.log(JSON.stringify(summary, null, 2));
  process.exitCode = pass ? 0 : 1;
}
