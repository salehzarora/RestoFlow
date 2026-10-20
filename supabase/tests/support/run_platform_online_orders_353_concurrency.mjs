// Real independent PostgreSQL connections, disposable LOCAL database only.
// No backend URL, production credentials, HTTP or printer transport exists here.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { createInterface } from 'node:readline';

const [flag, container] = process.argv.slice(2);
assert.equal(flag, '--container');
const ownNamespace = /^bizbot_platform353_pg_[a-zA-Z0-9_]+$/.test(container ?? '');
const freshCi = process.env.GITHUB_ACTIONS === 'true' && process.env.CI === 'true' && container === 'supabase_db_RestoFlow';
assert.ok(ownNamespace || freshCi, 'Only this task fixture or the exact disposable GitHub CI database is permitted');
assert.equal(process.argv.length, 4);
const nonce = randomBytes(6).toString('hex');
const database = `platform353_race_${nonce}`;
const dump = `/tmp/platform353-race-${nonce}.dump`;
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
const psql = (db) => ['exec', '-i', container, 'psql', '-X', '-qAt', '-U', 'postgres', '-d', db, '-v', 'ON_ERROR_STOP=1'];
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
    assert.equal(this.pending, null);
    return new Promise((resolve, reject) => {
      const marker = `__p353_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error('Local race query timeout')), 25_000);
      this.pending = { marker, rows: [], timer, resolve, reject };
      this.child.stdin.write(`${text}\n\\echo ${marker}\n`);
    });
  }
  close() { if (!this.child.stdin.writableEnded) this.child.stdin.end('rollback;\n\\q\n'); }
}
const one = (rows) => { assert.equal(rows.length, 1); return JSON.parse(rows[0]); };
const fixture = 'platform353_fixture';
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
    assert.equal(settled, false, 'Second real connection must wait on the first transaction');
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail('Concurrent local connection never observed waiting for lock');
}
const results = [];
try {
  // Existing database is read only during dump; every fixture write below is
  // directed exclusively to a unique newly created database in this container.
  if (freshCi) assert.equal(await sql('select (select count(*) from public.orders)+(select count(*) from public.web_order_requests)+(select count(*) from public.devices)+(select count(*) from app.pos_order_alert_registrations)+(select count(*) from app.pos_order_alert_deliveries);', 'postgres'), '0', 'CI must run before committed fixture suites');
  await command(['exec', container, 'pg_dump', '-U', 'supabase_admin', '-d', 'postgres', '--schema-only', '-Fc', '-f', dump]);
  await command(['exec', container, 'createdb', '-U', 'supabase_admin', '-O', 'postgres', '-T', 'template0', database]);
  await command(['exec', container, 'pg_restore', '-U', 'supabase_admin', '-d', database, '--exit-on-error', dump]);
  const original = await readFile(new URL('../platform_online_orders_353_test.sql', import.meta.url), 'utf8');
  const cutoff = original.indexOf('set local role service_role;');
  assert.ok(cutoff > 0);
  const seed = original.slice(0, cutoff).replaceAll('pg_temp.', `${fixture}.`)
    .replace('begin;', `begin; create schema ${fixture}; grant usage on schema ${fixture} to authenticated,service_role;`);
  await sql(`${seed}\nreset role; commit;`);
  await sql(`set role service_role; select ${fixture}.p353_submit(1);`);
  const a = new Session('p353_accept_a'), b = new Session('p353_accept_b');
  const accepted = one(await a.query(`begin; ${auth} select ${fixture}.p353_accept(1,1)::text;`));
  assert.equal(accepted.ok, true); assert.equal(accepted.replayed, false);
  const acceptance = b.query(`set application_name='p353_accept_b'; begin; ${auth} select ${fixture}.p353_accept(1,2)::text;`);
  await blocked(b.name, acceptance); await a.query('commit;');
  const lost = one(await acceptance); assert.equal(lost.ok, false); assert.equal(lost.error, 'decision_conflict'); await b.query('commit;');
  const reconciled = one(await a.query(`begin; ${auth} select ${fixture}.p353_accept(1,1)::text;`));
  assert.equal(reconciled.replayed, true); assert.equal(reconciled.canonical_order_id, accepted.canonical_order_id); await a.query('commit;');
  assert.equal(await sql(`select count(*) from public.web_order_decisions where request_id=${request(1)};`), '1');
  assert.equal(await sql(`select count(*) from public.kitchen_print_dispatches where order_id=${lit(accepted.canonical_order_id)} and dispatch_type='initial_order';`), '1');
  results.push('acceptance_race_one_canonical_decision_dispatch');
  const claim = (device) => `select public.pos_claim_web_order_print(${id(`pin-${device}`)},${id(`device-${device}`)},'synthetic-platform353-token-${device}',${request(1)})::text;`;
  assert.equal(one(await a.query(`begin; ${auth} ${claim(1)}`)).state, 'claimed');
  const foreignClaim = b.query(`set application_name='p353_accept_b'; begin; ${auth} ${claim(2)}`);
  await blocked(b.name, foreignClaim); await a.query('commit;');
  assert.equal(one(await foreignClaim).error, 'containment_blocked'); await b.query('commit;');
  results.push('concurrent_nonaccepting_claim_is_fenced');
  const begin = (n) => `select public.pos_begin_web_order_print(${id('pin-1')},${id('device-1')},'synthetic-platform353-token-1',${request(1)},${fixture}.p353_client(${n}))::text;`;
  assert.equal(one(await a.query(`begin; ${auth} ${begin(9001)}`)).send_authorized, true);
  const secondBegin = b.query(`set application_name='p353_accept_b'; begin; ${auth} ${begin(9002)}`);
  await blocked(b.name, secondBegin); await a.query('commit;');
  assert.equal(one(await secondBegin).send_authorized, false); await b.query('commit;');
  assert.equal(await sql(`select count(*) from public.web_order_print_attempts where request_id=${request(1)} and attempt_id=${fixture}.p353_client(9001);`), '1');
  results.push('two_connections_single_irreversible_begin');
  a.close(); b.close();
  console.log(JSON.stringify({ status: 'PASS', transport: 'two independent Docker-local psql connections', database,
    assertions: results, productionContacted: false, printerTransmissions: 0, retainedFixture: true }));
} finally {
  for (const session of sessions) session.close();
}
