// BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: explicit disposable LOCAL races.
// Never a node:test auto-runner. Requires the task's native loopback PG17 clone:
// node <this-file> --psql <absolute-psql.exe> --port 55443 \
//   --template manual_pilot_001 --expected-data-dir <task>/build/manual-pilot-local-pg/data
// The verified template is READ ONLY. Only unique, ownership-marked clones are
// seeded/committed/dropped. No order acceptance, printer or external HTTP calls.
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { readFile, realpath } from "node:fs/promises";
import { basename, isAbsolute, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const WORK_ID = "BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001";
const argv = process.argv.slice(2);
assert.equal(argv.length, 8, "Pass all four explicit local-only arguments");
assert.deepEqual(argv.filter((_, i) => i % 2 === 0),
  ["--psql", "--port", "--template", "--expected-data-dir"]);
const [, executable, , port, , template, , expectedData] = argv;
assert.ok(isAbsolute(executable) && /^psql(?:\.exe)?$/i.test(basename(executable)), "Use an absolute psql executable");
assert.equal(port, "55443", "Only this work item's isolated native port is allowed");
assert.equal(template, "manual_pilot_001", "Only the explicitly prepared synthetic template is allowed");
assert.ok(isAbsolute(expectedData), "Expected data directory must be explicit and absolute");
assert.match(expectedData.replaceAll("\\", "/"), /\/build\/manual-pilot-local-pg\/data\/?$/i,
  "Only the task-created disposable native cluster is allowed");
assert.ok(fileURLToPath(import.meta.url).includes(WORK_ID), "Run from the isolated work-item checkout");
await realpath(executable);
const normalize = (p) => resolve(p).replaceAll("\\", "/").toLowerCase();
const expectedCanonical = normalize(await realpath(expectedData));
const literal = (v) => `'${String(v).replaceAll("'", "''")}'`;
const identifier = (v) => {
  assert.match(v, /^manual_pilot_001_[a-z0-9_]{1,40}$/);
  return `"${v}"`;
};
const runId = `${Date.now().toString(36)}_${randomUUID().replaceAll("-", "").slice(0, 10)}`;
const org = "20605c2b-3145-4803-a990-bbec3d9c1096";
const restaurant = "de3bbc64-edad-4ff4-bccd-c2ef217c1d56";
const branch = "2847c0be-3e31-45a5-957c-508729f1971e";
const ref = (label) => {
  const h = createHash("md5").update(`manual-order-pilot-001-synthetic-${label}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
};
const client = (n) => `62000000-0000-4000-8000-${String(n).padStart(12, "0")}`;
const tokenHash = "a".repeat(64);
const salt = "c".repeat(64);
const contactHash = createHash("sha256").update(`${salt}\nsynthetic pilot guest\n+972520000123`).digest("hex");
const order = { order_type: "takeaway", customer: { name: "Synthetic Pilot Guest", phone: "+972520000123" },
  notes: "Synthetic manual Pickup test", items: [{ menu_item_id: ref("item"), quantity: 2,
    notes: "Synthetic line note", modifiers: [{ modifier_option_id: ref("option"), quantity: 2 }] }] };
const owned = new Map();
const sessions = new Set();
const sqlArgs = (db) => ["-X", "-qAt", "--no-password", "--host=127.0.0.1", `--port=${port}`,
  "--username=postgres", `--dbname=${db}`, "--set=ON_ERROR_STOP=1"];
const command = (text, db, timeoutMs = 20_000) => new Promise((resolvePromise, reject) => {
  const child = spawn(executable, sqlArgs(db), { stdio: ["pipe", "pipe", "pipe"], shell: false });
  let out = ""; let err = "";
  const timer = setTimeout(() => { child.kill(); reject(new Error("Bounded local SQL command timed out")); }, timeoutMs);
  child.stdout.setEncoding("utf8").on("data", (v) => { out += v; });
  child.stderr.setEncoding("utf8").on("data", (v) => { err += v; });
  child.stdin.on("error", () => {});
  child.on("error", (e) => { clearTimeout(timer); reject(e); });
  child.on("close", (code) => {
    clearTimeout(timer);
    if (code === 0) resolvePromise(out.trim());
    else reject(new Error(`Local SQL failed (${code}): ${err.trim()}`));
  });
  child.stdin.end(text);
});
const oneJson = (rows) => {
  const values = Array.isArray(rows) ? rows : rows.split(/\r?\n/).filter(Boolean);
  assert.equal(values.length, 1, "Expected exactly one local JSON result");
  return JSON.parse(values[0]);
};

class Session {
  constructor(db, name) {
    assert.ok(owned.has(db), "Interactive sessions may connect only to this run's owned clones");
    this.name = name; this.pending = null; this.sequence = 0; this.stderr = "";
    this.child = spawn(executable, sqlArgs(db), { stdio: ["pipe", "pipe", "pipe"], shell: false });
    sessions.add(this);
    this.child.stderr.setEncoding("utf8").on("data", (v) => { this.stderr += v; });
    createInterface({ input: this.child.stdout }).on("line", (line) => {
      if (!this.pending) return;
      if (line === this.pending.marker) {
        const current = this.pending;
        this.pending = null; clearTimeout(current.timer); current.resolve(current.rows);
      } else if (line.trim()) this.pending.rows.push(line);
    });
    this.child.on("error", (e) => this.fail(e));
    this.child.on("close", (code) => {
      this.exited = true; sessions.delete(this);
      this.fail(new Error(`Local session ${name} exited (${code}): ${this.stderr.trim()}`));
    });
    this.child.stdin.on("error", (e) => this.fail(e));
  }
  fail(error) {
    this.failure = error;
    if (this.pending) {
      const current = this.pending; this.pending = null;
      clearTimeout(current.timer); current.reject(error);
    }
  }
  query(text) {
    assert.equal(this.pending, null, "One statement batch per session at a time");
    if (this.failure) return Promise.reject(this.failure);
    return new Promise((resolvePromise, reject) => {
      const marker = `__manual_pilot_${this.name}_${++this.sequence}__`;
      const timer = setTimeout(() => this.fail(new Error(`Bounded local session ${this.name} timed out`)), 20_000);
      this.pending = { marker, rows: [], resolve: resolvePromise, reject, timer };
      this.child.stdin.write(`${text}\n\\echo ${marker}\n`);
    });
  }
  stop() { if (!this.exited) this.child.kill(); }
}

const submit = (n) => `select public.submit_web_order_pilot_request('mapsburger',${literal(client(n))}::uuid,
 ${literal(tokenHash)},${literal(JSON.stringify(order))}::jsonb)::text;`;
const snapshotSql = `select jsonb_build_object(
 'requests',(select count(*) from public.web_order_requests where organization_id=${literal(org)}),
 'events',(select count(*) from public.web_order_request_events where organization_id=${literal(org)}),
 'orders',(select count(*) from public.orders where organization_id=${literal(org)}),
 'decisions',(select count(*) from public.web_order_decisions where organization_id=${literal(org)}),
 'dispatches',(select count(*) from public.kitchen_print_dispatches where organization_id=${literal(org)}),
 'attempts',(select count(*) from public.web_order_print_attempts where organization_id=${literal(org)}),
 'channel',(select to_jsonb(c) from public.web_order_channel_settings c where branch_id=${literal(branch)}),
 'pilot',(select to_jsonb(p) from app.storefront_manual_order_pilots p where branch_id=${literal(branch)}
   order by (consumed_request_id is not null) desc,created_at desc,id limit 1),
 'all_pilot_windows',(select jsonb_agg(to_jsonb(p) order by p.id)
   from app.storefront_manual_order_pilots p where branch_id=${literal(branch)}),
 'mode',app.kitchen_print_containment_state(${literal(org)}::uuid,${literal(restaurant)}::uuid,${literal(branch)}::uuid)->>'mode')::text;`;
const fixturePath = new URL("../storefront_manual_order_pilot_001_test.sql", import.meta.url);
const fixture = (await readFile(fixturePath, "utf8")).split("-- MP_FIXTURE_END:")[0];
assert.ok(fixture.startsWith(`-- ${WORK_ID}:`) && fixture.includes("begin;")
  && !fixture.includes("select ok("), "Use only this task's synthetic fixture prefix");
const renewalMigration = await readFile(new URL(
  "../../migrations/20261016184616_bizbot_storefront_manual_order_pilot_001_unused_window_renewal.sql", import.meta.url), "utf8");
assert.ok(renewalMigration.startsWith(`-- ${WORK_ID}:`), "Use only the task's additive unused-window migration");

async function makeClone(kind) {
  const db = `manual_pilot_001_${runId}_${kind}`;
  const tag = `${WORK_ID}:${runId}:${kind}`;
  identifier(db);
  assert.equal(await command(`select count(*) from pg_database where datname=${literal(db)};`, template), "0",
    "Never overwrite a pre-existing database");
  await command(`create database ${identifier(db)} template ${template};`, "postgres");
  // Recording ownership follows successful creation. A comment failure leaves
  // an inspectable clone; cleanup refuses to drop without the matching marker.
  owned.set(db, tag);
  await command(`comment on database ${identifier(db)} is ${literal(tag)};`, "postgres");
  // Apply only to this newly generated owned clone. The preserved template
  // retains its original schema and is never migrated, seeded or reset.
  await command(renewalMigration, db);
  await command(`${fixture}\ncommit;`, db);
  return db;
}

async function insertPilot(db, seconds) {
  await command(`insert into app.storefront_manual_order_pilots(
   organization_id,restaurant_id,branch_id,enabled,starts_at,expires_at,
   contact_salt,contact_hash,operator_reference)
   values(${literal(org)}::uuid,${literal(restaurant)}::uuid,${literal(branch)}::uuid,true,
   clock_timestamp()-interval '1 second',clock_timestamp()+interval '${seconds} seconds',
   ${literal(salt)},${literal(contactHash)},${literal(`${WORK_ID}:${runId}`)});`, db);
}

async function insertClosedUnusedWindow(db) {
  return oneJson(await command(`insert into app.storefront_manual_order_pilots(
   organization_id,restaurant_id,branch_id,enabled,starts_at,expires_at,closed_at,
   contact_salt,contact_hash,operator_reference)
   values(${literal(org)}::uuid,${literal(restaurant)}::uuid,${literal(branch)}::uuid,false,
   clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute',clock_timestamp(),
   ${literal(salt)},${literal(contactHash)},${literal(`${WORK_ID}:${runId}:closed-unused`)})
   returning to_jsonb(storefront_manual_order_pilots)::text;`, db));
}

async function waitFor(check, message, maxMs = 10_000) {
  const until = Date.now() + maxMs;
  while (Date.now() < until) {
    if (await check()) return;
    await new Promise((done) => setTimeout(done, 40));
  }
  assert.fail(message);
}

async function witnessWait(observer, waiterPid, blockerPid, promise) {
  let finished = false;
  promise.then(() => { finished = true; }, () => { finished = true; });
  await waitFor(async () => {
    const blocked = oneJson(await observer.query(`select to_jsonb(${blockerPid}=any(pg_blocking_pids(${waiterPid})))::text;`));
    if (blocked === true) return true;
    assert.equal(finished, false, "Contender returned before the protected lock was released");
    return false;
  }, "Actual contender lock wait was not observed");
}

async function group(db, name) {
  const holder = new Session(db, `${name}_holder`);
  const contender = new Session(db, `${name}_contender`);
  const observer = new Session(db, `${name}_observer`);
  const holderPid = Number((await holder.query("select pg_backend_pid();"))[0]);
  const contenderPid = Number((await contender.query("select pg_backend_pid();"))[0]);
  await observer.query("select 1;");
  return { holder, contender, observer, holderPid, contenderPid };
}

const evidence = { workId: WORK_ID, server: "127.0.0.1:55443", template, cases: [], cleanup: [] };
let failure;
try {
  const server = oneJson(await command(`select jsonb_build_object('data',current_setting('data_directory'),
   'port',inet_server_port(),'address',host(inet_server_addr()),'version',current_setting('server_version_num'),
   'database',current_database(),'pilot_rpc',to_regprocedure('public.submit_web_order_pilot_request(text,uuid,text,jsonb)') is not null,
   'target_org_rows',(select count(*) from public.organizations where id=${literal(org)}::uuid),
   'pilot_rows',(select count(*) from app.storefront_manual_order_pilots))::text;`, template));
  assert.equal(normalize(await realpath(server.data)), expectedCanonical, "Server data directory identity differs from the explicit task clone");
  assert.equal(server.port, Number(port));
  assert.ok(["127.0.0.1", "::1"].includes(server.address), "Server connection must be loopback");
  assert.equal(Math.floor(Number(server.version) / 10_000), 17, "Use the verified native PG17 runtime");
  assert.equal(server.database, template);
  assert.equal(server.pilot_rpc, true);
  assert.equal(server.target_org_rows, 0, "Template already contains target-scope data; do not reuse or reset it");
  assert.equal(server.pilot_rows, 0, "Template already contains pilot evidence; do not reuse or reset it");

  const budgetDb = await makeClone("budget");
  const budget = await group(budgetDb, "budget");
  const oldBudgetWindow = await insertClosedUnusedWindow(budgetDb);
  await insertPilot(budgetDb, 120);
  const first = oneJson(await budget.holder.query(`begin; set local role service_role;
   set local statement_timeout='15s'; ${submit(101)}`));
  assert.equal(first.ok, true); assert.equal(first.replayed, false);
  const secondPending = budget.contender.query(`set role service_role; set statement_timeout='15s'; ${submit(102)}`);
  secondPending.catch(() => {});
  await witnessWait(budget.observer, budget.contenderPid, budget.holderPid, secondPending);
  await budget.holder.query("commit;");
  const second = oneJson(await secondPending);
  assert.equal(second.error, "ordering_unavailable");
  const state = oneJson(await budget.observer.query(snapshotSql));
  assert.deepEqual([state.requests, state.events, state.orders, state.decisions, state.dispatches, state.attempts],
    [1, 1, 0, 0, 0, 0]);
  assert.equal(state.pilot.enabled, false);
  assert.equal(state.pilot.consumed_client_request_id, client(101));
  assert.equal(state.channel.submission_enabled, false);
  assert.equal(state.mode, "blocked");
  assert.equal(state.all_pilot_windows.length, 2);
  assert.deepEqual(state.all_pilot_windows.find((p) => p.id === oldBudgetWindow.id), oldBudgetWindow,
    "The closed unused window must remain byte-identical through concurrent consumption");
  const replay = oneJson(await budget.contender.query(submit(101)));
  assert.equal(replay.replayed, true);
  evidence.cases.push({ name: "distinct identities serialize on one pilot budget", passed: true,
    lockWaitObserved: true, newRequests: state.requests, events: state.events, secondRefused: true,
    closedPilot: true, disabledChannel: true, originalReplay: true, historicalWindows: 1,
    priorWindowUnchanged: true, lifetimeConsumedWindows: state.all_pilot_windows.filter((p) => p.consumed_request_id !== null).length,
    canonicalOrders: 0, dispatches: 0, printAttempts: 0 });
  for (const session of [budget.holder, budget.contender, budget.observer]) session.stop();

  const expiryDb = await makeClone("expiry");
  const expiry = await group(expiryDb, "expiry");
  const oldExpiryWindow = await insertClosedUnusedWindow(expiryDb);
  await insertPilot(expiryDb, 5);
  await expiry.holder.query("begin; select id from app.storefront_manual_order_pilots where enabled for update;");
  const before = oneJson(await expiry.observer.query(snapshotSql));
  const latePending = expiry.contender.query(`set role service_role; set statement_timeout='15s'; ${submit(201)}`);
  latePending.catch(() => {});
  await witnessWait(expiry.observer, expiry.contenderPid, expiry.holderPid, latePending);
  // Poll the actual database deadline: no guessed delay substitutes for expiry.
  await waitFor(async () => oneJson(await expiry.observer.query(`select to_jsonb(clock_timestamp()>=expires_at)::text
   from app.storefront_manual_order_pilots where enabled;`)) === true, "Pilot expiry was not observed", 10_000);
  await expiry.holder.query("commit;");
  const late = oneJson(await latePending);
  assert.equal(late.error, "ordering_unavailable");
  const after = oneJson(await expiry.observer.query(snapshotSql));
  assert.deepEqual(after, before, "Expiry after actual pilot-lock wait must have no mutation effects");
  assert.deepEqual(after.all_pilot_windows.find((p) => p.id === oldExpiryWindow.id), oldExpiryWindow,
    "Expiry while waiting must not rewrite the previous unused window");
  assert.equal((await expiry.observer.query("select public.storefront_menu('mapsburger')#>>'{service,ordering_enabled}';"))[0], "false");
  evidence.cases.push({ name: "pilot expiry while waiting for row lock", passed: true,
    lockWaitObserved: true, serverDeadlineObserved: true, refused: true,
    allStateUnchanged: true, priorWindowUnchanged: true, historicalWindows: 1,
    requests: 0, events: 0, canonicalOrders: 0, dispatches: 0, printAttempts: 0 });
} catch (error) {
  failure = error;
} finally {
  for (const session of sessions) session.stop();
  for (const [db, tag] of owned) {
    try {
      const actual = await command(`select shobj_description(oid,'pg_database') from pg_database where datname=${literal(db)};`, "postgres");
      assert.equal(actual, tag, "Clone ownership marker differs; do not drop it");
      await waitFor(async () => await command(`select count(*) from pg_stat_activity where datname=${literal(db)};`, "postgres") === "0",
        "Owned clone still has connections; preserve rather than force termination");
      await command(`drop database ${identifier(db)};`, "postgres");
      evidence.cleanup.push({ database: db, ownershipVerified: true, dropped: true });
    } catch (error) {
      evidence.cleanup.push({ database: db, dropped: false, reason: error.message });
      failure ??= error;
    }
  }
}
evidence.result = failure ? "FAIL" : "PASS";
if (failure) evidence.error = failure.message;
console.log(JSON.stringify(evidence, null, 2));
if (failure) process.exitCode = 1;
