// WEB-ORDERS-001. Explicit local-only integration harness; not a node:test file.
// Prerequisite: a prepared local database with the current migration applied.
// Usage: node supabase/functions/web-order-submit/test/run-sql-concurrency.mjs \
//   --container restoflow_storefront_publish_002_pg --template web_orders_001_verified
// Native: --psql <task>/build/local-pg17/pgsql/bin/psql.exe --port 55437 --template web_orders_001_base
// Independent psql sessions commit synthetic fixtures inside a disposable clone.
// The template is never changed; the generated clone is dropped in finally.
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { isAbsolute, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const args = process.argv.slice(2);
const native = args[0] === "--psql";
assert.equal(args.length, native ? 6 : 4, "Pass explicit container or native psql settings and a test template");
assert.equal(args[0], native ? "--psql" : "--container");
assert.equal(args[native ? 4 : 2], "--template");
const container = native ? undefined : args[1];
const template = args[native ? 5 : 3];
const nativePsql = native ? args[1] : undefined;
const port = native ? args[3] : undefined;
const expectedPsql = fileURLToPath(new URL("../../../../build/local-pg17/pgsql/bin/psql.exe", import.meta.url));
const expectedData = fileURLToPath(new URL("../../../../build/local-pg17/data", import.meta.url));
const normalizedPath = (path) => resolve(path).toLowerCase();
if (native) {
  assert.equal(args[2], "--port");
  assert.equal(port, "55437", "Only the task's isolated portable Postgres port is allowed");
  assert.ok(isAbsolute(nativePsql), "Pass the absolute portable psql executable path");
  assert.equal(normalizedPath(nativePsql), normalizedPath(expectedPsql), "Use only the task's portable psql executable");
} else assert.match(container, /^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,100}$/);
assert.match(template, /^[a-zA-Z][a-zA-Z0-9_]{0,62}$/);
assert.ok(!["postgres", "template0", "template1"].includes(template), "Use a prepared test template");
const database = `web_orders_001_concurrency_${process.pid}_${Date.now()}`;
const literal = (value) => `'${String(value).replaceAll("'", "''")}'`;
const ref = (label) => {
  const h = createHash("md5").update(`web-orders-001-test-${label}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
};
const org = ref("org_a");
const branch = ref("branch_a");
const tokenHash = "a".repeat(64); // Synthetic digest; no credentials are read.
const sessions = new Set();
const isLocalSocket = (host) => /^unix:\/\/\//.test(host) || /^npipe:\/{2,4}\.\/pipe\//.test(host);

function command(executable, commandArgs, input = "", timeoutMs = 30_000) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, commandArgs, { stdio: ["pipe", "pipe", "pipe"], shell: false });
    let stdout = "";
    let stderr = "";
    const timer = setTimeout(() => { child.kill(); reject(new Error("Local test command timed out")); }, timeoutMs);
    child.stdout.setEncoding("utf8").on("data", (chunk) => { stdout += chunk; });
    child.stderr.setEncoding("utf8").on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => { clearTimeout(timer); reject(error); });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) resolve(stdout.trim());
      else reject(new Error(`Local test command failed (${code}): ${stderr.trim()}`));
    });
    child.stdin.on("error", () => {});
    child.stdin.end(input);
  });
}

function psqlArgs(db) {
  if (native) return ["-X", "-qAt", "--no-password", "--host=127.0.0.1", `--port=${port}`,
    "--username=postgres", `--dbname=${db}`, "--set=ON_ERROR_STOP=1"];
  return ["exec", "-i", container, "psql", "-X", "-qAt", "--no-password",
    "--host=/var/run/postgresql", "--username=postgres", `--dbname=${db}`, "--set=ON_ERROR_STOP=1"];
}

const executable = native ? nativePsql : "docker";
const sql = (text, db = database) => command(executable, psqlArgs(db), text);

class Session {
  constructor(name) {
    this.name = name;
    this.sequence = 0;
    this.pending = null;
    this.stderr = "";
    this.child = spawn(executable, psqlArgs(database), { stdio: ["pipe", "pipe", "pipe"], shell: false });
    this.child.stderr.setEncoding("utf8").on("data", (chunk) => { this.stderr += chunk; });
    createInterface({ input: this.child.stdout }).on("line", (line) => {
      if (!this.pending) return;
      if (line === this.pending.marker) {
        const { resolve, rows, timer } = this.pending;
        clearTimeout(timer);
        this.pending = null;
        resolve(rows);
      } else if (line.trim()) this.pending.rows.push(line);
    });
    this.child.on("error", (error) => this.fail(error));
    this.child.on("close", (code) => {
      this.exited = true;
      sessions.delete(this);
      this.fail(new Error(`Session ${name} exited (${code}): ${this.stderr.trim()}`));
    });
    this.child.stdin.on("error", (error) => this.fail(error));
    sessions.add(this);
  }

  fail(error) {
    this.failure = error;
    if (this.pending) {
      clearTimeout(this.pending.timer);
      this.pending.reject(error);
      this.pending = null;
    }
  }

  query(text) {
    assert.equal(this.pending, null, "One query at a time per session");
    if (this.failure) return Promise.reject(this.failure);
    return new Promise((resolve, reject) => {
      const marker = `__wo_done_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error(`Session ${this.name} timed out`)), 20_000);
      this.pending = { marker, rows: [], resolve, reject, timer };
      this.child.stdin.write(`${text}\n\\echo ${marker}\n`);
    });
  }

  close() {
    if (!this.exited && !this.child.stdin.writableEnded) this.child.stdin.end("\\q\n");
  }
}

function order(phone, notes = "") {
  return { order_type: "takeaway", customer: { name: "Synthetic Race Guest", phone }, notes,
    items: [{ menu_item_id: ref("item_plain"), quantity: 1, modifiers: [] }] };
}

function submit(id, body) {
  return `select public.submit_web_order_request('wo001-alpha',${literal(id)}::uuid,
    ${literal(tokenHash)},${literal(JSON.stringify(body))}::jsonb)::text;`;
}

function oneJson(rows) {
  assert.equal(rows.length, 1, `Expected one JSON row, got ${rows.length}`);
  return JSON.parse(rows[0]);
}

async function assertBlocked(name, work) {
  let settled = false;
  work.then(() => { settled = true; }, () => { settled = true; });
  const deadline = Date.now() + 5_000;
  while (Date.now() < deadline) {
    const blocked = await sql(`select exists(select 1 from pg_stat_activity
      where datname=${literal(database)} and application_name=${literal(name)}
      and wait_event_type='Lock');`);
    if (blocked === "t") return;
    assert.equal(settled, false, `${name} returned before the first transaction committed`);
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  assert.fail(`${name} did not wait on a database lock`);
}

async function resetAdmission() {
  // Only this clone's synthetic requests are aged. Restore the one guard before
  // opening real service_role connections; event triggers remain enabled.
  await sql(`begin;
    alter table public.web_order_requests disable trigger web_order_request_guard;
    update public.web_order_requests set created_at=now()-interval '16 minutes',
      expires_at=now()-interval '1 minute',status_until=now()+interval '23 hours 44 minutes'
      where organization_id=${literal(org)} and status='pending';
    alter table public.web_order_requests enable trigger web_order_request_guard;
    update public.web_order_channel_settings set submit_window_started_at=clock_timestamp(),
      submit_attempt_count=0,submitted_in_window=0,submit_day=current_date,submitted_today=0,
      status_window_started_at=clock_timestamp(),status_attempt_count=0
      where branch_id=${literal(branch)};
    commit;`);
}

async function seedPending(count, phone = null) {
  // Generate row identities before the LATERAL expansion. In the same-phone
  // case the old expansion depended only on w, so Postgres reused its one UUID
  // for every generate_series row and the second insert hit the primary key.
  await sql(`with seed as materialized (
      select gen_random_uuid() id,gen_random_uuid() client_request_id,
        ${phone ? literal(phone) : "'+972530'||lpad(n::text,6,'0')"} customer_phone
      from generate_series(1,${count}) n
    ) insert into public.web_order_requests
    select z.* from (select * from public.web_order_requests
      where organization_id=${literal(org)} order by created_at limit 1) w
    cross join seed s
    cross join lateral jsonb_populate_record(null::public.web_order_requests,to_jsonb(w)||
      jsonb_build_object('id',s.id,'client_request_id',s.client_request_id,
      'customer_phone',s.customer_phone,
      'created_at',now(),'expires_at',now()+interval '15 minutes',
      'status_until',now()+interval '24 hours')) z;`);
}

async function race(label, idA, bodyA, idB, bodyB, expectedB, expectedPending = 1) {
  const a = new Session(`${label}_a`);
  const b = new Session(`${label}_b`);
  const appB = `web_orders_001_${label}_b`;
  const first = oneJson(await a.query(`begin; set local role service_role;
    set local statement_timeout='15s'; ${submit(idA, bodyA)}`));
  assert.equal(first.ok, true, `${label}: first request accepted`);
  assert.equal(first.replayed, false, `${label}: first request is new`);
  const secondWork = b.query(`set application_name=${literal(appB)};
    set statement_timeout='15s'; set role service_role; ${submit(idB, bodyB)}`);
  await assertBlocked(appB, secondWork);
  await a.query("commit;");
  const second = oneJson(await secondWork);
  if (expectedB === "replayed") {
    assert.equal(second.replayed, true, `${label}: blocked submit replays`);
    assert.deepEqual({ ...second, replayed: false }, first, `${label}: replay preserves original result`);
  } else {
    assert.equal(second.ok, false, `${label}: blocked submit refused`);
    assert.equal(second.error, expectedB, `${label}: correct refusal`);
  }
  const counts = JSON.parse(await sql(`select jsonb_build_object(
    'requests',(select count(*) from public.web_order_requests where client_request_id in (${literal(idA)}::uuid,${literal(idB)}::uuid)),
    'events',(select count(*) from public.web_order_request_events e join public.web_order_requests w on w.id=e.request_id
      where w.client_request_id in (${literal(idA)}::uuid,${literal(idB)}::uuid)),
    'pending',(select count(*) from public.web_order_requests where branch_id=${literal(branch)}
      and status='pending' and expires_at>clock_timestamp()))::text;`));
  assert.equal(counts.requests, 1, `${label}: exactly one API request persisted`);
  assert.equal(counts.events, 1, `${label}: exactly one received event persisted`);
  assert.equal(counts.pending, expectedPending, `${label}: exact live pending capacity`);
  a.close();
  b.close();
  return { scenario: label, blocked: true, accepted: 1, second: expectedB, ...counts };
}

async function operationalCounts() {
  return JSON.parse(await sql(`select jsonb_build_object(
    'orders',(select count(*) from public.orders),
    'order_items',(select count(*) from public.order_items),
    'order_item_modifiers',(select count(*) from public.order_item_modifiers),
    'service_rounds',(select count(*) from public.order_service_rounds),
    'dispatches',(select count(*) from public.kitchen_print_dispatches),
    'payments',(select count(*) from public.payments),'users',(select count(*) from public.app_users))::text;`));
}

let created = false;
let report;
try {
  if (native) {
    const server = JSON.parse(await sql(`select jsonb_build_object(
      'data_directory',current_setting('data_directory'),'listen_addresses',current_setting('listen_addresses'),
      'address',inet_server_addr(),'port',inet_server_port())::text;`, "postgres"));
    assert.equal(normalizedPath(server.data_directory), normalizedPath(expectedData), "Use only the task's disposable Postgres cluster");
    assert.ok(["127.0.0.1", "localhost"].includes(server.listen_addresses), "Portable Postgres must listen only on loopback");
    assert.equal(server.address, "127.0.0.1");
    assert.equal(server.port, Number(port));
  } else {
    // Docker may itself point at a remote daemon; reject before any mutation.
    const dockerHost = process.env.DOCKER_HOST;
    assert.ok(!dockerHost || isLocalSocket(dockerHost), "Only a local Docker socket is allowed");
    const context = JSON.parse(await command("docker", ["context", "inspect"]))[0];
    assert.ok(isLocalSocket(context?.Endpoints?.docker?.Host ?? ""), "Docker context must be local");
    const info = JSON.parse(await command("docker", ["inspect", container]))[0];
    assert.equal(info?.State?.Running, true, "Local Postgres container must already be running");
    assert.equal(info?.HostConfig?.NetworkMode, "none", "Postgres container must have NetworkMode=none");
    assert.equal(Object.keys(info?.HostConfig?.PortBindings ?? {}).length, 0, "Postgres container must expose no host ports");
  }
  created = true;
  await sql(`create database "${database}" template "${template}";`, "postgres");

  const suite = await readFile(new URL("../../../tests/web_orders_001_test.sql", import.meta.url), "utf8");
  const marker = "-- The browser has no capability to submit or read stored requests directly.";
  assert.equal(suite.split(marker).length, 2, "Expected exactly one pgTAP fixture boundary");
  const fixtures = suite.slice(0, suite.indexOf(marker)).replace("select no_plan();", "");
  await sql(`${fixtures}
    insert into public.web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
      values(${literal(org)},${literal(ref("rest_a"))},${literal(branch)},true);
    commit;`);
  const before = await operationalCounts();
  const results = [];
  await resetAdmission();
  const identicalId = randomUUID();
  const identicalBody = order("+972520001101");
  results.push(await race("identity_replay", identicalId, identicalBody, identicalId, identicalBody, "replayed"));
  await resetAdmission();
  const conflictingId = randomUUID();
  results.push(await race("identity_conflict", conflictingId, order("+972520001102"),
    conflictingId, order("+972520001102", "Changed request body"), "idempotency_conflict"));
  await resetAdmission();
  await seedPending(49);
  results.push(await race("pending_cap", randomUUID(), order("+972520001103"),
    randomUUID(), order("+972520001104"), "capacity_reached", 50));
  await resetAdmission();
  const limitedPhone = "+972520001105";
  await seedPending(2, limitedPhone);
  results.push(await race("phone_cap", randomUUID(), order(limitedPhone),
    randomUUID(), order(limitedPhone), "capacity_reached", 3));
  assert.deepEqual(await operationalCounts(), before, "Concurrent requests never create canonical operational records");
  report = { work_id: "WEB-ORDERS-001", local_only: true, runtime: native ? "portable-postgres" : "docker",
    container, port, template, results, operational_deltas: 0 };
} finally {
  for (const session of sessions) session.close();
  if (created) {
    assert.match(database, /^web_orders_001_concurrency_[0-9]+_[0-9]+$/);
    await sql(`drop database if exists "${database}" with (force);`, "postgres");
  }
}
console.log(JSON.stringify({ ...report, disposable_database_removed: true }, null, 2));
