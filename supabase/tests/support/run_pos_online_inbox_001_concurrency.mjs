// POS-ONLINE-INBOX-001: separate native psql connections, disposable clone only.
// node <this file> --psql <WEB-ORDERS-001>/build/local-pg17/pgsql/bin/psql.exe \
//   --port 55438 --template pos_inbox_test_r1
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
assert.equal(args.length, 6);
assert.equal(args[0], "--psql"); assert.equal(args[2], "--port"); assert.equal(args[4], "--template");
const [psql, port, template] = [args[1], args[3], args[5]];
const normalize = (p) => resolve(p).toLowerCase();
const expectedPsql = fileURLToPath(new URL("../../../../WEB-ORDERS-001/build/local-pg17/pgsql/bin/psql.exe", import.meta.url));
const expectedData = fileURLToPath(new URL("../../../build/local-pg17/data", import.meta.url));
assert.ok(isAbsolute(psql)); assert.equal(normalize(psql), normalize(expectedPsql));
assert.equal(port, "55438"); assert.match(template, /^pos_inbox_[a-zA-Z0-9_]+$/);
const database = `pos_inbox_concurrency_${process.pid}_${Date.now()}`;
const lit = (v) => `'${String(v).replaceAll("'", "''")}'`;
function id(label) {
  const h = createHash("md5").update(`pos-online-inbox-001-${label}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
const connectionArgs = (db) => ["-X", "-qAt", "--no-password", "--host=127.0.0.1", `--port=${port}`,
  "--username=postgres", `--dbname=${db}`, "--set=ON_ERROR_STOP=1"];
const sessions = new Set();
function sql(text, db = database) {
  return new Promise((resolveQuery, reject) => {
    const child = spawn(psql, connectionArgs(db), { stdio: ["pipe", "pipe", "pipe"], shell: false });
    let out = "", err = "";
    const timer = setTimeout(() => { child.kill(); reject(new Error("Local SQL command timed out")); }, 30_000);
    child.stdout.setEncoding("utf8").on("data", (x) => { out += x; });
    child.stderr.setEncoding("utf8").on("data", (x) => { err += x; });
    child.on("error", (e) => { clearTimeout(timer); reject(e); });
    child.on("close", (code) => { clearTimeout(timer); code === 0 ? resolveQuery(out.trim()) : reject(new Error(err.trim())); });
    child.stdin.on("error", () => {}); child.stdin.end(text);
  });
}
class Session {
  constructor(name) {
    this.name = name; this.pending = null; this.sequence = 0; this.stderr = "";
    this.child = spawn(psql, connectionArgs(database), { stdio: ["pipe", "pipe", "pipe"], shell: false });
    this.child.stderr.setEncoding("utf8").on("data", (x) => { this.stderr += x; });
    createInterface({ input: this.child.stdout }).on("line", (line) => {
      if (!this.pending) return;
      if (line === this.pending.marker) {
        const { done, rows, timer } = this.pending; clearTimeout(timer); this.pending = null; done(rows);
      } else if (line.trim()) this.pending.rows.push(line);
    });
    this.child.on("error", (e) => this.fail(e));
    this.child.stdin.on("error", (e) => this.fail(e));
    this.child.on("close", () => { this.exited = true; sessions.delete(this); this.fail(new Error(this.stderr || "psql exited")); });
    sessions.add(this);
  }
  fail(e) {
    this.failure = e;
    if (this.pending) { clearTimeout(this.pending.timer); this.pending.reject(e); this.pending = null; }
  }
  query(text) {
    assert.equal(this.pending, null);
    if (this.failure) return Promise.reject(this.failure);
    return new Promise((done, reject) => {
      const marker = `__pi_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error(`${this.name} timed out`)), 20_000);
      this.pending = { marker, rows: [], timer, done, reject };
      this.child.stdin.write(`${text}\n\\echo ${marker}\n`);
    });
  }
  close() { if (!this.exited && !this.child.stdin.writableEnded) this.child.stdin.end("\\q\n"); }
}
const one = (rows) => { assert.equal(rows.length, 1); return JSON.parse(rows[0]); };
const auth = `set request.jwt.claim.sub=${lit(id("transport-only"))}; set role authenticated;`;
const call = (action, n, decision = n, device = 1) => action === "read"
  ? `select pi_fixture.pi_inbox(${lit(id(`request-${n}`))},${device})::text;`
  : action === "accept" ? `select pi_fixture.pi_accept(${lit(id(`request-${n}`))},${decision},${device})::text;`
    : `select pi_fixture.pi_reject(${lit(id(`request-${n}`))},${decision},'Unavailable',${device})::text;`;
const counts = async () => JSON.parse(await sql("select pi_fixture.pi_counts()::text;"));
const fixtureRequest = (n) => sql(`select pi_fixture.pi_request(${n});`);
async function blocked(name, promise) {
  let settled = false; promise.then(() => { settled = true; }, () => { settled = true; });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (await sql(`select exists(select 1 from pg_stat_activity where datname=${lit(database)}
      and application_name=${lit(name)} and wait_event_type='Lock');`) === "t") return;
    assert.equal(settled, false, `${name} must block before its peer commits`);
    await new Promise((r) => setTimeout(r, 40));
  }
  assert.fail(`${name} did not wait on a database lock`);
}
const results = [];
async function decisionRace(n, firstAction, secondAction) {
  await fixtureRequest(n); const before = await counts();
  const a = new Session(`decision_${n}_a`), b = new Session(`decision_${n}_b`);
  const first = one(await a.query(`begin; ${auth} ${call(firstAction, n)}`));
  assert.equal(first.ok, true);
  const waiting = b.query(`set application_name=${lit(b.name)}; set statement_timeout='15s'; ${auth} ${call(secondAction, n, n + 100, 2)}`);
  await blocked(b.name, waiting); await a.query("commit;");
  const second = one(await waiting);
  if (secondAction === "read") {
    assert.equal(second.requests[0].status, first.status);
    assert.equal(second.requests[0].canonical_order_id, first.canonical_order_id);
  } else if (firstAction === secondAction) {
    assert.equal(second.replayed, true); assert.equal(second.canonical_order_id, first.canonical_order_id);
    assert.equal(second.decision_id, first.decision_id);
  } else assert.equal(second.error, "decision_conflict");
  const after = await counts();
  assert.equal(after.decisions - before.decisions, 1);
  for (const key of ["orders", "sync", "dispatch"]) assert.equal(after[key] - before[key], firstAction === "accept" ? 1 : 0, `${key}: exactly one canonical path`);
  assert.equal(after.payments, before.payments);
  a.close(); b.close(); results.push({ scenario: `${firstAction}/${secondAction}`, lock_wait: true, canonical: firstAction === "accept" ? 1 : 0 });
}
async function configurationWait(n, mutation, expectedError, restore) {
  await fixtureRequest(n); const before = await counts();
  const a = new Session(`config_${n}_a`), b = new Session(`config_${n}_b`);
  await a.query(`begin; ${mutation}`);
  const waiting = b.query(`set application_name=${lit(b.name)}; set statement_timeout='15s'; ${auth} ${call("accept", n)}`);
  await blocked(b.name, waiting); await a.query("commit;");
  assert.equal(one(await waiting).error, expectedError);
  assert.deepEqual(await counts(), before, "configuration wait refusal has no operational effects");
  if (restore) await sql(restore);
  a.close(); b.close(); results.push({ scenario: `config-${n}`, lock_wait: true, refusal: expectedError });
}

let created = false;
try {
  const server = JSON.parse(await sql(`select jsonb_build_object('data',current_setting('data_directory'),
    'listen',current_setting('listen_addresses'),'address',inet_server_addr(),'port',inet_server_port())::text;`, "postgres"));
  assert.equal(normalize(server.data), normalize(expectedData));
  assert.ok(["127.0.0.1", "localhost"].includes(server.listen)); assert.equal(server.address, "127.0.0.1"); assert.equal(server.port, 55438);
  created = true; await sql(`create database "${database}" template "${template}";`, "postgres");
  const suite = await readFile(new URL("../pos_online_inbox_001_test.sql", import.meta.url), "utf8");
  const marker = "-- POS-INBOX FIXTURE END:"; assert.equal(suite.split(marker).length, 2);
  const setup = suite.slice(0, suite.indexOf(marker)).replace("select no_plan();", "").replaceAll("pg_temp.", "pi_fixture.");
  await sql(`create schema pi_fixture; ${setup}
    grant usage on schema pi_fixture to authenticated;
    update public.branches set kitchen_workflow_mode='printer_only' where id=${lit(id("branch"))}; commit;`);
  await decisionRace(1, "accept", "accept");
  await decisionRace(2, "accept", "reject");
  await decisionRace(3, "reject", "accept");
  await decisionRace(4, "accept", "read");
  await configurationWait(5, `update menu_items set base_price_minor=1001 where id=${lit(id("paid"))};`, "quote_changed",
    `update menu_items set base_price_minor=1000 where id=${lit(id("paid"))};`);
  await configurationWait(6, `update modifier_options set is_active=false where id=${lit(id("option"))};`, "modifier_selection_invalid",
    `update modifier_options set is_active=true where id=${lit(id("option"))};`);
  await configurationWait(7, `update branches set tax_rate_bp=1900 where id=${lit(id("branch"))};`, "quote_changed",
    `update branches set tax_rate_bp=1800 where id=${lit(id("branch"))};`);
  await configurationWait(8, `update shifts set status='closed',closed_at=clock_timestamp() where id=${lit(id("shift-1"))};`, "shift_required",
    `update shifts set status='open',closed_at=null where id=${lit(id("shift-1"))};`);

  // An absent override must not slip in while acceptance holds the item parent.
  await fixtureRequest(9); const absentBefore = await counts();
  const a = new Session("absent_a"), b = new Session("absent_b");
  assert.equal(one(await a.query(`begin; ${auth} ${call("accept", 9)}`)).ok, true);
  const insert = b.query(`set application_name='absent_b'; set statement_timeout='15s';
    insert into menu_item_branch_availability(organization_id,restaurant_id,branch_id,menu_item_id,availability,reason)
    values(${lit(id("org"))},${lit(id("restaurant"))},${lit(id("branch"))},${lit(id("paid"))},'unavailable','sold_out');`);
  await blocked(b.name, insert); await a.query("commit;"); await insert;
  assert.equal((await counts()).orders - absentBefore.orders, 1);
  await sql(`update menu_item_branch_availability set availability='available',reason=null where menu_item_id=${lit(id("paid"))};`);
  a.close(); b.close(); results.push({ scenario: "absent-availability-insert", lock_wait: true, canonical: 1 });

  // A decision which was valid before waiting must sample real time afterward.
  await fixtureRequest(10); const expiryBefore = await counts();
  await sql(`begin; alter table web_order_requests disable trigger web_order_request_guard;
    with t as(select clock_timestamp() now) update web_order_requests set created_at=t.now-interval '14 minutes 58 seconds',
      expires_at=t.now+interval '2 seconds',status_until=t.now+interval '23 hours 45 minutes 2 seconds'
      from t where id=${lit(id("request-10"))};
    alter table web_order_requests enable trigger web_order_request_guard; commit;`);
  const x = new Session("expiry_a"), y = new Session("expiry_b");
  await x.query(`begin; select id from web_order_requests where id=${lit(id("request-10"))} for update;`);
  const expiryWork = y.query(`set application_name='expiry_b'; set statement_timeout='15s'; ${auth} ${call("accept", 10)}`);
  await blocked(y.name, expiryWork); await x.query("select pg_sleep(2.1); commit;");
  assert.equal(one(await expiryWork).error, "request_expired");
  assert.deepEqual(await counts(), expiryBefore); x.close(); y.close(); results.push({ scenario: "expiry-after-wait", lock_wait: true, canonical: 0 });

  // Deliberate item/request lock inversion models a catalogue reparent/reorder
  // deadlock. Either victim must roll back; retry the unchanged decision ID.
  await fixtureRequest(11); const deadlockBefore = await counts();
  const writer = new Session("deadlock_writer"), acceptor = new Session("deadlock_acceptor");
  await writer.query(`begin; set deadlock_timeout='50ms'; select id from menu_items where id=${lit(id("paid"))} for update;`);
  const acceptWork = acceptor.query(`set application_name='deadlock_acceptor'; set statement_timeout='15s'; ${auth} ${call("accept", 11)}`);
  await blocked(acceptor.name, acceptWork);
  const lockWork = writer.query(`select id from web_order_requests where id=${lit(id("request-11"))} for update;`);
  const writerResult = await lockWork.then((rows) => ({ rows }), (error) => ({ error }));
  if (writerResult.error) assert.match(writerResult.error.message, /deadlock detected/);
  else await writer.query("rollback;");
  const acceptResult = await acceptWork.then((rows) => ({ rows }), (error) => ({ error }));
  if (acceptResult.error) assert.match(acceptResult.error.message, /deadlock detected/);
  else assert.equal(one(acceptResult.rows).ok, true);
  assert.notEqual(Boolean(writerResult.error), Boolean(acceptResult.error), "exactly one transaction is the deadlock victim");
  const recovered = one(await new Session("deadlock_recovery").query(`${auth} ${call("accept", 11)}`));
  assert.equal(recovered.ok, true);
  const deadlockAfter = await counts();
  assert.equal(deadlockAfter.orders - deadlockBefore.orders, 1); assert.equal(deadlockAfter.dispatch - deadlockBefore.dispatch, 1);
  assert.equal(deadlockAfter.decisions - deadlockBefore.decisions, 1);
  writer.close(); acceptor.close(); results.push({ scenario: "catalogue-lock-inversion", deadlock: true, same_id_recovery: true, canonical: 1 });
} finally {
  for (const session of sessions) session.close();
  if (created) { assert.match(database, /^pos_inbox_concurrency_[0-9]+_[0-9]+$/); await sql(`drop database if exists "${database}" with(force);`, "postgres"); }
}
console.log(JSON.stringify({ work_id: "POS-ONLINE-INBOX-001", local_only: true, results, disposable_database_removed: true }, null, 2));
