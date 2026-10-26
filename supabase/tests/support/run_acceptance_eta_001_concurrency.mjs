// Real independent PostgreSQL connections, disposable LOCAL database only.
// No backend URL, production credentials, HTTP or printer transport exists here.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';

let assertionCount = 0;
function verify(...args) { assert.equal(...args); assertionCount++; }
function verifyOk(...args) { assert.ok(...args); assertionCount++; }

const [flag, container, schemaFlag, schemaDatabase = 'postgres'] = process.argv.slice(2);
verify(flag, '--container');
const ownNamespace = /^bizbot_platform353_pg_[a-zA-Z0-9_]+$/.test(container ?? '');
const freshCi = process.env.GITHUB_ACTIONS === 'true' && process.env.CI === 'true' && container === 'supabase_db_RestoFlow';
verifyOk(ownNamespace || freshCi, 'Only this task fixture or the exact disposable GitHub CI database is permitted');
verifyOk(process.argv.length === 4 || (ownNamespace && process.argv.length === 6 && schemaFlag === '--schema-database' && /^eta_sql_[0-9_]+$/.test(schemaDatabase)));
verifyOk(freshCi || /^eta_sql_[0-9_]+$/.test(schemaDatabase), 'Local input is a newly owned ETA fixture only');
const nonce = randomBytes(6).toString('hex');
const database = `acceptance_eta_race_${nonce}`;
const dump = `/tmp/acceptance-eta-race-${nonce}.dump`;
const lit = (v) => `'${String(v).replaceAll("'", "''")}'`;
const sessions = new Set();
function command(args, input = '') {
  return new Promise((resolve, reject) => {
    const p = spawn('docker', args, { shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '', stderr = '';
    const timer = setTimeout(() => { p.kill(); reject(new Error('Local fixture process timeout')); }, 60_000);
    p.stdout.setEncoding('utf8').on('data', (x) => { stdout += x; });
    p.stderr.setEncoding('utf8').on('data', (x) => { stderr += x; });
    p.on('error', reject);
    p.on('close', (code) => { clearTimeout(timer); code === 0 ? resolve(stdout.trim()) : reject(new Error(stderr.trim())); });
    p.stdin.on('error', () => {}); p.stdin.end(input);
  });
}
const psql = (db) => ['exec', '-i', container, 'psql', '-X', '-qAt', '-w', '-h', '/var/run/postgresql', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1'];
const sql = (text, db = database) => command(psql(db), text);
class Session {
  constructor(name) {
    this.name = name; this.sequence = 0; this.pending = null; this.stderr = '';
    this.child = spawn('docker', psql(database), { shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
    this.child.stderr.setEncoding('utf8').on('data', (x) => { this.stderr += x; });
    createInterface({ input: this.child.stdout }).on('line', (line) => {
      if (!this.pending) return;
      if (line === this.pending.marker) {
        const { resolve, rows, timer } = this.pending; clearTimeout(timer); this.pending = null; resolve(rows);
      } else if (line.trim()) this.pending.rows.push(line);
    });
    this.child.on('error', (e) => this.fail(e));
    this.child.stdin.on('error', (e) => this.fail(e));
    this.child.on('close', () => { sessions.delete(this); this.fail(new Error(this.stderr || 'Local psql exited')); });
    sessions.add(this);
  }
  fail(error) { if (this.pending) { clearTimeout(this.pending.timer); this.pending.reject(error); this.pending = null; } }
  query(text) {
    verify(this.pending, null);
    return new Promise((resolve, reject) => {
      const marker = `__p353_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error('Local race query timeout')), 25_000);
      this.pending = { marker, rows: [], timer, resolve, reject };
      this.child.stdin.write(`${text}\n\\echo ${marker}\n`);
    });
  }
  close() { if (!this.child.stdin.writableEnded) this.child.stdin.end('rollback;\n\\q\n'); }
}
const one = (rows) => { verify(rows.length, 1); return JSON.parse(rows[0]); };
const fixture = 'acceptance_eta_fixture';
const id = (label) => `${fixture}.p353_id(${lit(label)})`;
const request = (n) => `${fixture}.p353_request(${n})`;
const authHash = createHash('md5').update('bizbot-platform-353-synthetic-transport-user').digest('hex');
const authUuid = `${authHash.slice(0,8)}-${authHash.slice(8,12)}-${authHash.slice(12,16)}-${authHash.slice(16,20)}-${authHash.slice(20)}`;
const auth = `set request.jwt.claim.sub=${lit(authUuid)}; set role authenticated;`;
async function blocked(name, pending) {
  let settled = false; pending.finally(() => { settled = true; }).catch(() => {});
  const deadline = Date.now() + 8000;
  while (Date.now() < deadline) {
    if (await sql(`select exists(select 1 from pg_stat_activity where datname=${lit(database)} and application_name=${lit(name)} and wait_event_type='Lock');`) === 't') return;
    verify(settled, false, 'Second real connection must wait on the first transaction');
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail('Concurrent local connection never observed waiting for lock');
}
const results = [];
try {
  // Existing database is read only during dump; every fixture write below is
  // directed exclusively to a unique newly created database in this container.
  if (freshCi) verify(await sql('select (select count(*) from public.orders)+(select count(*) from public.web_order_requests)+(select count(*) from public.devices)+(select count(*) from app.pos_order_alert_registrations)+(select count(*) from app.pos_order_alert_deliveries);', 'postgres'), '0', 'CI must run before committed fixture suites');
  if (ownNamespace) {
    const meta = JSON.parse(await command(['inspect', container]))[0];
    verify(meta.Image, 'sha256:80d7b27c3e8d77cfa7226eee9508671796da214781ff15a35b3670d7ad5ee453');
    const networks = Object.keys(meta.NetworkSettings.Networks);
    verify(networks.length, 1);
    const network = JSON.parse(await command(['network', 'inspect', networks[0]]))[0];
    verify(network.Internal, true); verify(network.EnableIPv6, false);
  }
  await command(['exec', container, 'pg_dump', '-h', '/var/run/postgresql', '-U', 'supabase_admin', '-d', schemaDatabase, '--schema-only', '-Fc', '-f', dump]);
  await command(['exec', container, 'createdb', '-h', '/var/run/postgresql', '-U', 'supabase_admin', '-O', 'postgres', '-T', 'template0', database]);
  await command(['exec', container, 'pg_restore', '-h', '/var/run/postgresql', '-U', 'supabase_admin', '-d', database, '--exit-on-error', dump]);
  const original = await readFile(new URL('../storefront_acceptance_eta_001_test.sql', import.meta.url), 'utf8');
  const cutoff = original.indexOf('create temp table _eta_legacy_functions');
  verifyOk(cutoff > 0);
  const seed = original.slice(0, cutoff).replaceAll('pg_temp.', `${fixture}.`)
    .replace('begin;', `begin; create schema ${fixture}; grant usage on schema ${fixture} to authenticated,service_role;`);
  await sql(`${seed}\nreset role; commit;`);
  for (let n = 1; n <= 8; n++) verify(JSON.parse(await sql(`set role service_role; select ${fixture}.p353_submit(${n})::text;`)).ok, true);
  const a = new Session('p353_accept_a'), b = new Session('p353_accept_b');
  // Distinct request/device pairs must never reuse a fixture decision UUID.
  const decision = (n, device) => `${fixture}.p353_client(${10000}+${n}*10+${device})`;
  const eta = (n, minutes, device = 1) => `select public.pos_accept_web_order_with_eta(${id(`pin-${device}`)},${id(`device-${device}`)},'synthetic-platform353-token-${device}',${request(n)},${decision(n,device)},${minutes})::text;`;
  const legacy = (n, device = 1) => `select public.pos_accept_web_order(${id(`pin-${device}`)},${id(`device-${device}`)},'synthetic-platform353-token-${device}',${request(n)},${decision(n,device)})::text;`;
  const accepted = one(await a.query(`begin; ${auth} ${eta(1,15)}`));
  verify(accepted.ok, true); verify(accepted.replayed, false);
  const acceptance = b.query(`set application_name='p353_accept_b'; begin; ${auth} ${eta(1,30,2)}`);
  await blocked(b.name, acceptance); await a.query('commit;');
  verify(one(await acceptance).error, 'decision_conflict'); await b.query('commit;');
  verify(await sql(`select count(*) from app.web_order_acceptance_estimates where request_id=${request(1)};`), '1');
  verify(await sql(`select count(*) from public.web_order_decisions where request_id=${request(1)};`), '1');
  verify(await sql(`select count(*) from public.kitchen_print_dispatches where order_id=${lit(accepted.canonical_order_id)};`), '1');
  verify(await sql(`select count(*) from app.online_order_print_leases where request_id=${request(1)};`), '1');
  results.push('two_devices_one_order_decision_dispatch_lease_and_estimate');

  const originalEta = await sql(`select row_to_json(e)::text from app.web_order_acceptance_estimates e where request_id=${request(1)};`);
  verify(one(await a.query(`begin; ${auth} ${eta(1,15)}`)).replayed, true);
  const same = b.query(`begin; ${auth} ${eta(1,15)}`);
  await blocked(b.name, same); await a.query('commit;');
  verify(one(await same).replayed, true); await b.query('commit;');
  verify(await sql(`select row_to_json(e)::text from app.web_order_acceptance_estimates e where request_id=${request(1)};`), originalEta);
  results.push('same_intent_concurrent_replay_retains_exact_immutable_tuple');

  verify(one(await a.query(`begin; ${auth} ${eta(2,15)}`)).ok, true);
  const changed = b.query(`begin; ${auth} ${eta(2,20)}`);
  await blocked(b.name, changed); await a.query('commit;');
  verify(one(await changed).error, 'decision_conflict'); await b.query('commit;');
  verify(await sql(`select preparation_minutes from app.web_order_acceptance_estimates where request_id=${request(2)};`), '15');
  results.push('same_identity_changed_duration_is_conflict_after_wait');

  verify(one(await a.query(`begin; ${auth} ${eta(3,15)}`)).ok, true);
  const afterRollback = b.query(`begin; ${auth} ${eta(3,20,2)}`);
  await blocked(b.name, afterRollback); await a.query('rollback;');
  const winnerAfterRollback = one(await afterRollback);
  verify(winnerAfterRollback.ok, true); verify(winnerAfterRollback.replayed, false); await b.query('commit;');
  verify(await sql(`select preparation_minutes from app.web_order_acceptance_estimates where request_id=${request(3)};`), '20');
  results.push('winner_rollback_leaves_no_estimate_and_waiter_wins_once');

  verify(one(await a.query(`begin; ${auth} ${legacy(4)}`)).ok, true);
  const legacyLoser = b.query(`begin; ${auth} ${eta(4,15)}`);
  await blocked(b.name, legacyLoser); await a.query('commit;');
  verify(one(await legacyLoser).error, 'decision_conflict'); await b.query('commit;');
  verify(await sql(`select count(*) from app.web_order_acceptance_estimates where request_id=${request(4)};`), '0');
  results.push('legacy_winner_never_backfilled_by_eta_waiter');

  // The original authority helper rechecks after a real row-lock wait.
  await a.query(`reset role; begin; update public.pin_sessions set is_active=false where id=${id('pin-1')};`);
  const revoked = b.query(`begin; ${auth} ${eta(5,15)}`);
  await blocked(b.name, revoked); await a.query('commit;');
  verify(one(await revoked).error, 'invalid_session'); await b.query('commit;');
  verify(await sql(`select count(*) from public.web_order_decisions where request_id=${request(5)};`), '0');
  verify(await sql(`select count(*) from app.web_order_acceptance_estimates where request_id=${request(5)};`), '0');
  results.push('revoked_pin_after_lock_wait_cannot_accept_or_append_metadata');

  // A status read waits on its admission lock, then sees the committed winner.
  await a.query(`reset role; begin; update public.pin_sessions set is_active=true where id=${id('pin-1')}; update public.web_order_channel_settings set status_attempt_count=0 where branch_id=${id('branch-a1')};`);
  const status = b.query(`begin; set role service_role; select ${fixture}.eta_status(6)::text;`);
  await blocked(b.name, status);
  verify(one(await a.query(`${auth} ${eta(6,45)}`)).ok, true); await a.query('commit;');
  const observed = one(await status); verify(observed.status, 'accepted'); verify(observed.acceptance_eta.preparation_minutes, 45); await b.query('commit;');
  verify(await sql(`select status_attempt_count from public.web_order_channel_settings where branch_id=${id('branch-a1')};`), '1');
  results.push('status_post_admission_wait_observes_atomic_tuple_once');
  const reject = (n, device = 2) => `select public.pos_reject_web_order(${id(`pin-${device}`)},${id(`device-${device}`)},'synthetic-platform353-token-${device}',${request(n)},${fixture}.p353_client(${3000}+${n}),'Synthetic private rejection')::text;`;
  verify(one(await a.query(`begin; ${auth} ${eta(7,15)}`)).ok, true);
  const rejectLoser = b.query(`begin; ${auth} ${reject(7)}`);
  await blocked(b.name, rejectLoser); await a.query('commit;');
  verify(one(await rejectLoser).error, 'decision_conflict'); await b.query('commit;');
  verify(await sql(`select count(*) from app.web_order_acceptance_estimates where request_id=${request(7)};`), '1');
  verify(await sql(`select count(*) from public.web_order_decisions where request_id=${request(7)};`), '1');
  results.push('eta_accept_winner_legacy_reject_waiter_has_no_second_decision');

  verify(one(await a.query(`begin; ${auth} ${reject(8,1)}`)).ok, true);
  const acceptLoser = b.query(`begin; ${auth} ${eta(8,15,2)}`);
  await blocked(b.name, acceptLoser); await a.query('commit;');
  verify(one(await acceptLoser).error, 'decision_conflict'); await b.query('commit;');
  verify(await sql(`select count(*) from app.web_order_acceptance_estimates where request_id=${request(8)};`), '0');
  verify(await sql(`select count(*) from public.web_order_decisions where request_id=${request(8)};`), '1');
  results.push('legacy_reject_winner_eta_accept_waiter_has_no_estimate');
  a.close(); b.close();
  console.log(JSON.stringify({ status: 'PASS', assertionCount, raceCount: results.length, transport: 'two independent Docker-local psql connections', database,
    assertions: results, productionContacted: false, printerTransmissions: 0, retainedFixture: true }));
} finally {
  for (const session of sessions) session.close();
}
