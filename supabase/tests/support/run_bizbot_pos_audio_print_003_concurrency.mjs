// BIZBOT-POS-AUDIO-PRINT-003: real lock races, disposable localhost database only.
// node <this file> --psql /absolute/path/to/psql \
//   --port 55439 --template audio_print_003 --expected-data-dir /isolated/postgres/data
// WORK-ID in the data directory's parent must contain this exact work item.
import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, resolve } from "node:path";
import { createInterface } from "node:readline";


const args = process.argv.slice(2);
assert.equal(args.length, 8);
assert.equal(args[0], "--psql"); assert.equal(args[2], "--port"); assert.equal(args[4], "--template");
assert.equal(args[6], "--expected-data-dir");
const [psql, port, template] = [args[1], args[3], args[5]];
const normalize = (p) => process.platform === "win32" ? resolve(p).toLowerCase() : resolve(p);
const expectedData = args[7];
assert.ok(isAbsolute(psql)); assert.match(basename(psql), /^psql(?:\.exe)?$/i);
assert.ok(isAbsolute(expectedData));
assert.match(port, /^[0-9]{1,5}$/); assert.ok(Number(port) > 0 && Number(port) <= 65535);
assert.match(template, /^audio_print_003(?:_[a-zA-Z0-9_]+)?$/);
assert.equal((await readFile(resolve(dirname(expectedData), "WORK-ID"), "utf8")).trim(), "BIZBOT-POS-AUDIO-PRINT-003");
const database = `print_003_concurrency_${process.pid}_${Date.now()}`;
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
const request = (n) => lit(id(`request-${n}`));
const accept = (n) => `select tp_fixture.pi_accept(${request(n)},${n})::text;`;
const claim = (n, device = 1) => `select tp_fixture.tp_claim(${request(n)},${device})::text;`;
const begin = (n, attempt = n, device = 1) => `select tp_fixture.tp_begin(${request(n)},${attempt},${device})::text;`;
const fixture = async (n) => {
  await sql(`select tp_fixture.pi_request(${n});`);
  assert.equal(one(await new Session(`accept_${n}`).query(`${auth} ${accept(n)}`)).ok, true);
};
async function blocked(name, promise) {
  let settled = false; promise.then(() => { settled = true; }, () => { settled = true; });
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    if (await sql(`select exists(select 1 from pg_stat_activity where datname=${lit(database)}
      and application_name=${lit(name)} and wait_event_type='Lock');`) === "t") return;
    assert.equal(settled, false, `${name} must wait for the peer transaction`);
    await new Promise((r) => setTimeout(r, 40));
  }
  assert.fail(`${name} did not wait on a database lock`);
}
const results = [];
let created = false;
try {
  const server = JSON.parse(await sql(`select jsonb_build_object('data',current_setting('data_directory'),
    'listen',current_setting('listen_addresses'),'address',inet_server_addr(),'port',inet_server_port())::text;`, "postgres"));
  assert.equal(normalize(server.data), normalize(expectedData));
  assert.ok(["127.0.0.1", "localhost"].includes(server.listen));
  assert.equal(server.address, "127.0.0.1"); assert.equal(server.port, Number(port));
  created = true; await sql(`create database "${database}" template "${template}";`, "postgres");
  const suite = await readFile(new URL("../bizbot_pos_audio_print_003_test.sql", import.meta.url), "utf8");
  const marker = "-- PRINT-003 HARNESS SETUP END:";
  assert.equal(suite.split(marker).length, 2);
  const setup = suite.slice(0, suite.indexOf(marker)).replace("select no_plan();", "").replaceAll("pg_temp.", "tp_fixture.");
  await sql(`create schema tp_fixture; ${setup}
    grant usage on schema tp_fixture to authenticated;
    update public.branches set kitchen_workflow_mode='printer_only' where id=${lit(id("branch"))};
    select tp_fixture.tp_readiness(); commit;`);

  // A reader racing acceptance sees no uncommitted dispatch. Once committed,
  // the new dispatch and broad-feed exclusion become visible together.
  await sql("select tp_fixture.pi_request(1);");
  const acceptor = new Session("atomic_accept"), broad = new Session("broad_reader");
  assert.equal(one(await acceptor.query(`begin; ${auth} ${accept(1)}`)).ok, true);
  const beforeCommit = one(await broad.query(`${auth} select tp_fixture.tp_pull(2)::text;`));
  assert.deepEqual(beforeCommit.dispatches, []);
  await acceptor.query("commit;");
  const afterCommit = one(await broad.query("select tp_fixture.tp_pull(2)::text;"));
  assert.deepEqual(afterCommit.dispatches, []);
  acceptor.close(); broad.close();
  results.push({ scenario: "acceptance/broad-pull", broad_visible_dispatches: 0 });

  // Two real devices racing the same exact claim serialize on the target.
  const a = new Session("claim_a"), b = new Session("claim_b");
  assert.equal(one(await a.query(`begin; ${auth} ${claim(1)}`)).state, "claimed");
  const competingClaim = b.query(`set application_name='claim_b'; ${auth} ${claim(1, 2)}`);
  await blocked("claim_b", competingClaim); await a.query("commit;");
  const busy = one(await competingClaim);
  assert.equal(busy.state, "busy"); assert.equal(busy.dispatch, undefined);
  a.close(); b.close();
  results.push({ scenario: "two-device-claim", lock_wait: true, winning_claims: 1 });

  // Crash before begin permits a new lease, but never a send by the stale owner.
  await sql(`update web_order_print_attempts set claim_expires_at=clock_timestamp()-interval '1 second' where request_id=${request(1)};
    update kitchen_print_dispatches set claim_expires_at=clock_timestamp()-interval '1 second'
    where id=(select dispatch_id from web_order_print_attempts where request_id=${request(1)});`);
  const recovered = new Session("recovered_claim");
  assert.equal(one(await recovered.query(`${auth} ${claim(1, 2)}`)).state, "claimed");
  assert.equal(one(await recovered.query(begin(1, 1, 1))).error, "not_claim_owner");
  recovered.close();
  results.push({ scenario: "crash-before-reservation", recovery_claims: 1, stale_send_grants: 0 });

  // Begin and a competing device claim race: once reserved, every automatic
  // claimant gets reconciliation, including after the original lease expires.
  const sender = new Session("sender"), other = new Session("other_claim");
  const granted = one(await sender.query(`begin; ${auth} ${begin(1, 1, 2)}`));
  assert.equal(granted.send_authorized, true);
  const afterBeginClaim = other.query(`set application_name='other_claim'; ${auth} ${claim(1, 1)}`);
  await blocked("other_claim", afterBeginClaim); await sender.query("commit;");
  assert.equal(one(await afterBeginClaim).state, "reconciliation_required");
  assert.equal(one(await sender.query(begin(1, 1, 2))).send_authorized, false);
  assert.equal(one(await sender.query(begin(1, 2, 2))).send_authorized, false);
  sender.close(); other.close();
  results.push({ scenario: "begin/other-device-claim-and-lost-reply", lock_wait: true, send_grants: 1 });

  // A possible physical send followed by lost ACK, old ACK API, expiry and
  // restart cannot reopen either the broad or exact automatic path.
  await sql(`update kitchen_print_dispatches set claim_expires_at=clock_timestamp()-interval '1 second'
    where id=(select dispatch_id from web_order_print_attempts where request_id=${request(1)});`);
  const restart = new Session("restart");
  const legacyAck = one(await restart.query(`${auth} select public.acknowledge_kitchen_print_dispatch(
    ${lit(id("device-2"))},'synthetic-pos-token-2',
    ${lit(granted.dispatch_id)},
    'failed_retryable','network.unavailable')::text;`));
  assert.equal(legacyAck.ok, true);
  assert.deepEqual(one(await restart.query("select tp_fixture.tp_pull(1)::text;")).dispatches, []);
  assert.equal(one(await restart.query(begin(1, 3, 1))).send_authorized, false);
  restart.close();
  results.push({ scenario: "possible-send/lost-ack/lease-expiry/restart", send_grants: 0, broad_claims: 0 });

  // Multiple callbacks with the SAME attempt UUID in independent connections
  // still receive a single authorization; the losing reply cannot be retried.
  await fixture(2);
  const c = new Session("callback_a"), d = new Session("callback_b");
  assert.equal(one(await c.query(`${auth} ${claim(2)}`)).state, "claimed");
  assert.equal(one(await c.query(`begin; ${begin(2, 20)}`)).send_authorized, true);
  const sameAttempt = d.query(`set application_name='callback_b'; ${auth} ${begin(2, 20)}`);
  await blocked("callback_b", sameAttempt); await c.query("commit;");
  assert.equal(one(await sameAttempt).send_authorized, false);
  c.close(); d.close();
  results.push({ scenario: "same-attempt-concurrent-callbacks", lock_wait: true, send_grants: 1 });
} finally {
  for (const session of sessions) session.close();
  if (created) {
    assert.match(database, /^print_003_concurrency_[0-9]+_[0-9]+$/);
    await sql(`drop database if exists "${database}" with(force);`, "postgres");
  }
}
console.log(JSON.stringify({ work_id: "BIZBOT-POS-AUDIO-PRINT-003", local_only: true,
  results, disposable_database_removed: true }, null, 2));
