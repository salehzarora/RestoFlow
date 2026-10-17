// BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001: explicit disposable LOCAL races.
// Never a node:test auto-runner. Requires the task's native loopback PG17 clone:
// node <this-file> --psql <absolute-psql.exe> --port 55451 \
//   --template mapsburger_live_001_1717 --expected-data-dir <task>/build/always-on-local-pg/data
// The verified template is READ ONLY. Only unique, ownership-marked clones are
// seeded/committed/dropped. Acceptance below is synthetic LOCAL SQL only.
// No hosted connection, physical printer, device or external HTTP call occurs.
import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { spawn } from "node:child_process";
import { readFile, realpath } from "node:fs/promises";
import { basename, isAbsolute, resolve } from "node:path";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

const WORK_ID = "BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001";
const argv = process.argv.slice(2);
assert.equal(argv.length, 8, "Pass all four explicit local-only arguments");
assert.deepEqual(argv.filter((_, i) => i % 2 === 0),
  ["--psql", "--port", "--template", "--expected-data-dir"]);
const [, executable, , port, , template, , expectedData] = argv;
assert.ok(isAbsolute(executable) && /^psql(?:\.exe)?$/i.test(basename(executable)), "Use an absolute psql executable");
assert.equal(port, "55451", "Only this work item's isolated native port is allowed");
assert.equal(template, "mapsburger_live_001_1717", "Only the explicitly prepared synthetic template is allowed");
assert.ok(isAbsolute(expectedData), "Expected data directory must be explicit and absolute");
assert.match(expectedData.replaceAll("\\", "/"), /\/build\/always-on-local-pg\/data\/?$/i,
  "Only the task-created disposable native cluster is allowed");
assert.ok(fileURLToPath(import.meta.url).includes(WORK_ID), "Run from the isolated work-item checkout");
await realpath(executable);
const normalize = (p) => resolve(p).replaceAll("\\", "/").toLowerCase();
const expectedCanonical = normalize(await realpath(expectedData));
const literal = (v) => `'${String(v).replaceAll("'", "''")}'`;
const identifier = (v) => {
  assert.match(v, /^mapsburger_live_001_[a-z0-9_]{1,50}$/);
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

const fixture = (await readFile(new URL('../mapsburger_always_on_web_orders_001_test.sql', import.meta.url),'utf8'))
  .split('-- ALWAYS_ON_FIXTURE_END:')[0];
assert.ok(fixture.startsWith(`-- ${WORK_ID}:`) && fixture.includes('begin;'), 'Use only this task fixture');
const auth = `set role authenticated; set request.jwt.claim.sub=${literal(ref('transport-user'))};`;
const config = (intake, printing) => `select app.set_mapsburger_web_orders(${intake},${printing},
 array[${literal(ref('device-1'))}::uuid,${literal(ref('device-2'))}::uuid],
 'Synthetic isolated race','${WORK_ID}');`;
const submit = (n) => `select public.submit_web_order_live_request('mapsburger',${literal(client(n))}::uuid,
 ${literal(tokenHash)},${literal(JSON.stringify({...order,customer:{...order.customer,phone:`+9725200${String(n).padStart(5,'0')}`}}))}::jsonb)::text;`;
const accept = (request, n=1) => `select public.pos_accept_web_order(${literal(ref(`pin-${n}`))}::uuid,
 ${literal(ref(`device-${n}`))}::uuid,'synthetic-live-token-${n}',${literal(request)}::uuid,${literal(randomUUID())}::uuid)::text;`;
const claim = (request) => `select public.pos_claim_web_order_print(${literal(ref('pin-1'))}::uuid,
 ${literal(ref('device-1'))}::uuid,'synthetic-live-token-1',${literal(request)}::uuid)::text;`;
const beginSend = (request,attempt) => `select public.pos_begin_web_order_print(${literal(ref('pin-1'))}::uuid,
 ${literal(ref('device-1'))}::uuid,'synthetic-live-token-1',${literal(request)}::uuid,${literal(attempt)}::uuid)::text;`;
async function makeClone(kind,{requests=2,shortLease=false}={}) {
  const db=`mapsburger_live_001_${runId}_${kind}`; const tag=`${WORK_ID}:${runId}:${kind}`;
  assert.equal(await command(`select count(*) from pg_database where datname=${literal(db)};`,template),'0');
  await command(`create database ${identifier(db)} template ${template};`,'postgres'); owned.set(db,tag);
  await command(`comment on database ${identifier(db)} is ${literal(tag)};`,'postgres');
  await command(`${fixture}\n${config(true,true)} commit;`,db);
  if(shortLease) await command(`create function app.synthetic_short_lease() returns trigger language plpgsql as $$
    begin new.expires_at:=new.created_at+interval '3 seconds'; return new; end $$;
    create trigger synthetic_short_lease before insert on app.mapsburger_web_print_leases
      for each row execute function app.synthetic_short_lease();`,db);
  const ids=[];
  for(let n=1;n<=requests;n++) {
    const result=oneJson(await command(`set role service_role; ${submit(n)}`,db)); assert.equal(result.status,'pending');
    ids.push((await command(`select id from public.web_order_requests where client_request_id=${literal(client(n))};`,db)).trim());
  }
  return {db,ids};
}
const evidence={workId:WORK_ID,server:'127.0.0.1:55451',template,cases:[],cleanup:[]}; let failure;
try {
  const server=oneJson(await command(`select jsonb_build_object('data',current_setting('data_directory'),
    'port',inet_server_port(),'address',host(inet_server_addr()),'orgs',(select count(*) from public.organizations),
    'requests',(select count(*) from public.web_order_requests),'live_rpc',to_regprocedure('public.submit_web_order_live_request(text,uuid,text,jsonb)') is not null)::text;`,template));
  assert.equal(normalize(await realpath(server.data)),expectedCanonical,'Wrong disposable data directory');
  assert.equal(server.port,Number(port)); assert.ok(['127.0.0.1','::1'].includes(server.address));
  assert.equal(server.orgs,0); assert.equal(server.requests,0); assert.equal(server.live_rpc,true);

  const intake=await makeClone('intake',{requests:0}); const g=await group(intake.db,'intake');
  const first=oneJson(await g.holder.query(`begin; set local role service_role; ${submit(1)}`));
  const waiting=g.contender.query(`set role service_role; ${submit(2)}`); waiting.catch(()=>{});
  await witnessWait(g.observer,g.contenderPid,g.holderPid,waiting); await g.holder.query('commit;');
  assert.equal(first.status,'pending'); assert.equal(oneJson(await waiting).status,'pending');
  assert.equal(await command('select count(*) from app.mapsburger_live_web_requests;',intake.db),'2');
  evidence.cases.push({name:'two independent ordinary customers serialize without a one-request budget',pass:true,lockWaitObserved:true});

  const same=await makeClone('same'); const s=await group(same.db,'same');
  await s.holder.query(`begin; ${auth}`); const accepted=oneJson(await s.holder.query(accept(same.ids[0])));
  await s.contender.query(auth); const duplicate=s.contender.query(accept(same.ids[0])); duplicate.catch(()=>{});
  await witnessWait(s.observer,s.contenderPid,s.holderPid,duplicate); await s.holder.query('commit;');
  assert.equal(accepted.replayed,false); assert.equal(oneJson(await duplicate).replayed,true);
  assert.equal(await command('select count(*) from public.orders;',same.db),'1');
  assert.equal(await command('select count(*) from app.mapsburger_web_print_leases;',same.db),'1');
  evidence.cases.push({name:'concurrent same-device same-request acceptance creates one canonical order and lease',pass:true,lockWaitObserved:true});

  const distinct=await makeClone('distinct'); const d=await group(distinct.db,'distinct');
  await d.holder.query(`begin; ${auth}`); const a=oneJson(await d.holder.query(accept(distinct.ids[0]))); assert.equal(a.status,'accepted');
  await d.contender.query(auth); const other=d.contender.query(accept(distinct.ids[1])); other.catch(()=>{});
  await witnessWait(d.observer,d.contenderPid,d.holderPid,other); await d.holder.query('commit;');
  assert.equal(oneJson(await other).error,'order_rejected');
  assert.equal(await command('select count(*) from public.orders;',distinct.db),'1');
  assert.equal(await command(`select status from public.web_order_requests where id=${literal(distinct.ids[1])};`,distinct.db),'pending');
  evidence.cases.push({name:'different pending requests on one device cannot displace an unresolved print callback',pass:true,lockWaitObserved:true});

  const devices=await makeClone('devices'); const v=await group(devices.db,'devices');
  await v.holder.query(`begin; ${auth}`); const win=oneJson(await v.holder.query(accept(devices.ids[0],1))); assert.equal(win.status,'accepted');
  await v.contender.query(auth); const lose=v.contender.query(accept(devices.ids[0],2)); lose.catch(()=>{});
  await witnessWait(v.observer,v.contenderPid,v.holderPid,lose); await v.holder.query('commit;');
  assert.equal(oneJson(await lose).replayed,true);
  assert.equal(await command('select count(*) from public.orders;',devices.db),'1');
  assert.equal(await command('select count(*) from app.mapsburger_web_print_leases;',devices.db),'1');
  assert.equal(await command(`select device_id from app.mapsburger_web_print_leases;`,devices.db),ref('device-1'));
  evidence.cases.push({name:'concurrent devices accept one request; replaying device gets no print lease',pass:true,lockWaitObserved:true});

  const off=await makeClone('off',{requests:0}); const o=await group(off.db,'off');
  await o.holder.query(`begin; ${config(false,true)}`);
  const late=o.contender.query(`set role service_role; ${submit(1)}`); late.catch(()=>{});
  await witnessWait(o.observer,o.contenderPid,o.holderPid,late); await o.holder.query('commit;');
  assert.equal(oneJson(await late).error,'ordering_unavailable');
  assert.equal(await command('select count(*) from public.web_order_requests;',off.db),'0');
  evidence.cases.push({name:'operator intake OFF wins against a submission waiting on the branch fence',pass:true,lockWaitObserved:true});

  const revoke=await makeClone('revoke'); await command(`${auth} ${accept(revoke.ids[0])} ${claim(revoke.ids[0])}`,revoke.db);
  const r=await group(revoke.db,'revoke'); await r.holder.query(`begin; ${config(false,false)}`);
  await r.contender.query(auth); const denied=r.contender.query(beginSend(revoke.ids[0],randomUUID())); denied.catch(()=>{});
  await witnessWait(r.observer,r.contenderPid,r.holderPid,denied); await r.holder.query('commit;');
  assert.equal(oneJson(await denied).error,'containment_blocked');
  assert.equal(await command('select count(*) from public.web_order_print_attempts where attempt_id is not null;',revoke.db),'0');
  evidence.cases.push({name:'emergency print OFF wins before an irreversible begin waiting on branch fence',pass:true,lockWaitObserved:true});

  const expiry=await makeClone('expiry',{shortLease:true}); await command(`${auth} ${accept(expiry.ids[0])}`,expiry.db);
  const e=await group(expiry.db,'expiry');
  await e.holder.query(`begin; select request_id from public.web_order_print_attempts where request_id=${literal(expiry.ids[0])} for update;`);
  await e.contender.query(auth); const expired=e.contender.query(claim(expiry.ids[0])); expired.catch(()=>{});
  await witnessWait(e.observer,e.contenderPid,e.holderPid,expired);
  await waitFor(async()=>oneJson(await e.observer.query('select to_jsonb(clock_timestamp()>=expires_at)::text from app.mapsburger_web_print_leases;'))===true,'Actual lease expiry not observed');
  await e.holder.query('commit;'); assert.equal(oneJson(await expired).error,'containment_blocked');
  assert.equal(await command('select count(*) from public.web_order_print_attempts where claimed_by_device_id is not null;',expiry.db),'0');
  const successor=oneJson(await command(`${auth} ${accept(expiry.ids[1])}`,expiry.db)); assert.equal(successor.status,'accepted');
  assert.equal(await command("select reason from app.mapsburger_web_print_lease_closures;",expiry.db),'expired_before_send');
  evidence.cases.push({name:'lease expiry during real claim lock wait denies claim; new acceptance retires exact old no-send lease',pass:true,lockWaitObserved:true,serverExpiryObserved:true});

  const crash=await makeClone('crash',{shortLease:true}); const attempt=randomUUID();
  const reserved=await command(`${auth} ${accept(crash.ids[0])} ${claim(crash.ids[0])} ${beginSend(crash.ids[0],attempt)}`,crash.db);
  assert.equal(oneJson(reserved.split(/\r?\n/).slice(-1)).send_authorized,true);
  await waitFor(async()=>await command('select clock_timestamp()>=expires_at from app.mapsburger_web_print_leases;',crash.db)==='t','Reserved lease expiry not observed');
  assert.equal(oneJson(await command(`${auth} ${accept(crash.ids[1])}`,crash.db)).error,'order_rejected');
  const replay=oneJson((await command(`${auth} ${beginSend(crash.ids[0],attempt)}`,crash.db)).split(/\r?\n/).slice(-1));
  assert.equal(replay.send_authorized,false); assert.equal(replay.state,'reconciliation_required');
  assert.equal(await command('select count(*) from public.orders;',crash.db),'1');
  evidence.cases.push({name:'crash after irreversible begin remains fenced after expiry and prevents callback displacement',pass:true,serverExpiryObserved:true});
} catch(error) {failure=error;} finally {
  for(const session of sessions) session.stop();
  for(const [db,tag] of owned) {
    try {
      assert.equal(await command(`select shobj_description(oid,'pg_database') from pg_database where datname=${literal(db)};`,'postgres'),tag);
      await waitFor(async()=>await command(`select count(*) from pg_stat_activity where datname=${literal(db)};`,'postgres')==='0','Owned clone still connected');
      await command(`drop database ${identifier(db)};`,'postgres'); evidence.cleanup.push({database:db,ownershipVerified:true,dropped:true});
    } catch(error) { evidence.cleanup.push({database:db,dropped:false,reason:error.message}); failure??=error; }
  }
}
evidence.result=failure?'FAIL':'PASS'; if(failure) evidence.error=failure.message;
console.log(JSON.stringify(evidence,null,2)); if(failure) process.exitCode=1;
